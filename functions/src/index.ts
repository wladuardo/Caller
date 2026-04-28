import * as admin from "firebase-admin";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {onRequest} from "firebase-functions/v2/https";
import {defineSecret, defineString} from "firebase-functions/params";
import {SignJWT, importPKCS8} from "jose";
import {randomUUID} from "node:crypto";
import {request as httpsRequest} from "node:https";

admin.initializeApp();

const apnsTeamID = defineString("APNS_TEAM_ID");
const apnsKeyID = defineString("APNS_KEY_ID");
const apnsBundleID = defineString("APNS_BUNDLE_ID");
const apnsProduction = defineString("APNS_PRODUCTION", {default: "false"});
const locationPushCallbackURL = defineString("LOCATION_PUSH_CALLBACK_URL");
const apnsPrivateKey = defineSecret("APNS_PRIVATE_KEY");

type RequestFriendLocationInput = {
    friendID?: unknown;
};

type LocationPushCallbackBody = {
    requestID?: unknown;
    callbackSecret?: unknown;
    latitude?: unknown;
    longitude?: unknown;
    horizontalAccuracy?: unknown;
    speed?: unknown;
    updatedAt?: unknown;
    batteryLevelPercent?: unknown;
};

type ChatMessageDocument = {
    senderID?: unknown;
    recipientID?: unknown;
    text?: unknown;
    attachment?: unknown;
};

type IncomingCallNotificationDocument = {
    toUserID?: unknown;
    fromUserID?: unknown;
    callID?: unknown;
    callType?: unknown;
};

export const sendChatMessagePush = onDocumentCreated(
    "conversations/{conversationID}/messages/{messageID}",
    async (event) => {
        const message = event.data?.data() as ChatMessageDocument | undefined;
        if (!message) {
            return;
        }

        const senderID = stringValue(message.senderID);
        const recipientID = stringValue(message.recipientID);
        if (!senderID || !recipientID || senderID === recipientID) {
            return;
        }

        const [senderSnapshot, recipientSnapshot] = await Promise.all([
            admin.firestore().collection("users").doc(senderID).get(),
            admin.firestore().collection("users").doc(recipientID).get()
        ]);
        const fcmToken = stringValue(recipientSnapshot.get("fcmToken"));
        if (!fcmToken) {
            return;
        }

        const senderName = displayName(senderSnapshot, "Новое сообщение");
        const text = stringValue(message.text);
        const body = text && text.length > 0 ? text : attachmentPushText(message.attachment);

        await admin.messaging().send({
            token: fcmToken,
            notification: {
                title: senderName,
                body
            },
            data: {
                type: "chat_message",
                senderId: senderID,
                conversationID: event.params.conversationID,
                messageID: event.params.messageID
            },
            apns: {
                payload: {
                    aps: {
                        sound: "default"
                    }
                }
            }
        });
    }
);

export const sendIncomingCallPush = onDocumentCreated(
    "incomingCallNotifications/{notificationID}",
    async (event) => {
        const notification = event.data?.data() as IncomingCallNotificationDocument | undefined;
        if (!notification) {
            return;
        }

        const toUserID = stringValue(notification.toUserID);
        const fromUserID = stringValue(notification.fromUserID);
        const callID = stringValue(notification.callID);
        const callType = stringValue(notification.callType) ?? "audio";
        if (!toUserID || !fromUserID || !callID || toUserID === fromUserID) {
            return;
        }

        const [callerSnapshot, recipientSnapshot] = await Promise.all([
            admin.firestore().collection("users").doc(fromUserID).get(),
            admin.firestore().collection("users").doc(toUserID).get()
        ]);
        const fcmToken = stringValue(recipientSnapshot.get("fcmToken"));
        if (!fcmToken) {
            return;
        }

        const callerName = displayName(callerSnapshot, "Входящий звонок");
        const callTitle = callType === "video" ? "Видеозвонок" : "Звонок";

        await admin.messaging().send({
            token: fcmToken,
            notification: {
                title: callerName,
                body: callTitle
            },
            data: {
                type: "incoming_call",
                callId: callID,
                callerId: fromUserID,
                callerName,
                callType
            },
            apns: {
                payload: {
                    aps: {
                        sound: "default"
                    }
                }
            }
        });
    }
);

export const requestFriendLocation = onCall(
    {secrets: [apnsPrivateKey]},
    async (request) => {
        const requesterID = request.auth?.uid;
        if (!requesterID) {
            throw new HttpsError("unauthenticated", "Authentication is required.");
        }

        return await requestLocationPushForFriend(requesterID, request.data as RequestFriendLocationInput);
    }
);

export const requestFriendLocationHttp = onRequest(
    {secrets: [apnsPrivateKey]},
    async (request, response) => {
        if (request.method !== "POST") {
            response.status(405).send("Method Not Allowed");
            return;
        }

        try {
            const requesterID = await authenticatedUserID(request.headers.authorization);
            const result = await requestLocationPushForFriend(requesterID, request.body as RequestFriendLocationInput);
            response.status(200).json(result);
        } catch (error) {
            if (error instanceof HttpsError) {
                response.status(httpStatusCode(error.code)).json({
                    code: error.code,
                    message: error.message
                });
                return;
            }

            console.error("requestFriendLocationHttp failed", error);
            response.status(500).json({
                code: "internal",
                message: "Internal Server Error"
            });
        }
    }
);

export const locationPushCallback = onRequest(async (request, response) => {
    if (request.method !== "POST") {
        response.status(405).send("Method Not Allowed");
        return;
    }

    const body = request.body as LocationPushCallbackBody;
    const requestID = stringValue(body.requestID);
    const callbackSecret = stringValue(body.callbackSecret);
    const latitude = numberValue(body.latitude);
    const longitude = numberValue(body.longitude);
    const horizontalAccuracy = numberValue(body.horizontalAccuracy);

    if (!requestID || !callbackSecret || latitude == null || longitude == null || horizontalAccuracy == null) {
        response.status(400).send("Invalid payload");
        return;
    }

    const db = admin.firestore();
    const requestRef = db.collection("locationRequests").doc(requestID);
    const requestSnapshot = await requestRef.get();
    if (!requestSnapshot.exists) {
        response.status(404).send("Location request not found");
        return;
    }

    const expectedSecret = requestSnapshot.get("callbackSecret");
    if (expectedSecret !== callbackSecret) {
        response.status(403).send("Invalid callback secret");
        return;
    }

    const requesterID = requestSnapshot.get("requesterID");
    const targetUserID = requestSnapshot.get("targetUserID");
    if (typeof requesterID !== "string" || typeof targetUserID !== "string") {
        response.status(409).send("Location request is corrupted");
        return;
    }

    const updatedAt = dateValue(body.updatedAt) ?? new Date();
    const sharedLocation: Record<string, unknown> = {
        latitude,
        longitude,
        horizontalAccuracy,
        updatedAt: admin.firestore.Timestamp.fromDate(updatedAt)
    };

    const speed = numberValue(body.speed);
    if (speed != null) {
        sharedLocation.speed = speed;
    }

    const batteryLevelPercent = numberValue(body.batteryLevelPercent);
    if (batteryLevelPercent != null) {
        sharedLocation.batteryLevelPercent = Math.round(batteryLevelPercent);
    }

    const batch = db.batch();
    batch.set(
        db.collection("users").doc(requesterID).collection("friends").doc(targetUserID),
        {
            sharedLocation,
            updatedAt: admin.firestore.FieldValue.serverTimestamp()
        },
        {merge: true}
    );
    batch.set(
        requestRef,
        {
            status: "completed",
            completedAt: admin.firestore.FieldValue.serverTimestamp()
        },
        {merge: true}
    );
    await batch.commit();

    response.status(204).send();
});

async function requestLocationPushForFriend(
    requesterID: string,
    input: RequestFriendLocationInput
): Promise<{requestID: string}> {
    const friendID = typeof input.friendID === "string" ? input.friendID.trim() : "";
    if (!friendID) {
        throw new HttpsError("invalid-argument", "friendID is required.");
    }
    if (friendID === requesterID) {
        throw new HttpsError("invalid-argument", "Cannot request your own location.");
    }

    const db = admin.firestore();
    const friendRef = db
        .collection("users")
        .doc(requesterID)
        .collection("friends")
        .doc(friendID);
    const friendSnapshot = await friendRef.get();
    if (!friendSnapshot.exists) {
        throw new HttpsError("permission-denied", "The target user is not your friend.");
    }

    const targetUserSnapshot = await db.collection("users").doc(friendID).get();
    const locationPushToken = targetUserSnapshot.get("locationPushToken");
    if (typeof locationPushToken !== "string" || locationPushToken.length === 0) {
        throw new HttpsError("failed-precondition", "Friend has no location push token.");
    }

    const callbackURL = locationPushCallbackURL.value();
    if (!callbackURL) {
        throw new HttpsError("failed-precondition", "LOCATION_PUSH_CALLBACK_URL is not configured.");
    }

    const requestID = randomUUID();
    const callbackSecret = randomUUID();
    await db.collection("locationRequests").doc(requestID).set({
        requesterID,
        targetUserID: friendID,
        callbackSecret,
        status: "pending",
        createdAt: admin.firestore.FieldValue.serverTimestamp()
    });

    await sendLocationPush(locationPushToken, {
        callbackURL,
        requestID,
        callbackSecret
    });

    return {requestID};
}

async function authenticatedUserID(authorizationHeader: string | undefined): Promise<string> {
    const prefix = "Bearer ";
    if (!authorizationHeader?.startsWith(prefix)) {
        throw new HttpsError("unauthenticated", "Authentication is required.");
    }

    const decodedToken = await admin.auth().verifyIdToken(authorizationHeader.slice(prefix.length));
    return decodedToken.uid;
}

function httpStatusCode(code: HttpsError["code"]): number {
    switch (code) {
    case "invalid-argument":
        return 400;
    case "unauthenticated":
        return 401;
    case "permission-denied":
        return 403;
    case "not-found":
        return 404;
    case "failed-precondition":
        return 412;
    default:
        return 500;
    }
}

async function sendLocationPush(
    token: string,
    payload: {
        callbackURL: string;
        requestID: string;
        callbackSecret: string;
    }
): Promise<void> {
    const jwt = await makeAPNsJWT();
    const host = apnsProduction.value() === "true" ? "api.push.apple.com" : "api.sandbox.push.apple.com";
    const body = JSON.stringify(payload);

    await new Promise<void>((resolve, reject) => {
        const request = httpsRequest(
            {
                host,
                method: "POST",
                path: `/3/device/${token}`,
                headers: {
                    authorization: `bearer ${jwt}`,
                    "apns-topic": `${apnsBundleID.value()}.location-query`,
                    "apns-push-type": "location",
                    "apns-priority": "10",
                    "content-type": "application/json",
                    "content-length": Buffer.byteLength(body)
                }
            },
            (response) => {
                let responseBody = "";
                response.setEncoding("utf8");
                response.on("data", (chunk) => {
                    responseBody += chunk;
                });
                response.on("end", () => {
                    if (response.statusCode && response.statusCode >= 200 && response.statusCode < 300) {
                        resolve();
                    } else {
                        reject(new Error(`APNs failed with ${response.statusCode}: ${responseBody}`));
                    }
                });
            }
        );

        request.on("error", reject);
        request.write(body);
        request.end();
    });
}

async function makeAPNsJWT(): Promise<string> {
    const privateKey = apnsPrivateKey.value().replace(/\\n/g, "\n");
    const key = await importPKCS8(privateKey, "ES256");

    return new SignJWT({})
        .setProtectedHeader({
            alg: "ES256",
            kid: apnsKeyID.value()
        })
        .setIssuer(apnsTeamID.value())
        .setIssuedAt()
        .setExpirationTime("50m")
        .sign(key);
}

function stringValue(value: unknown): string | undefined {
    return typeof value === "string" && value.length > 0 ? value : undefined;
}

function attachmentPushText(value: unknown): string {
    if (typeof value !== "object" || value == null) {
        return "Вложение";
    }

    const attachment = value as Record<string, unknown>;
    const kind = stringValue(attachment.kind);
    if (kind === "image") {
        return "Фото";
    }

    const fileName = stringValue(attachment.fileName);
    return fileName ? `Файл: ${fileName}` : "Файл";
}

function displayName(snapshot: admin.firestore.DocumentSnapshot, fallback: string): string {
    return stringValue(snapshot.get("displayName")) ??
        stringValue(snapshot.get("username")) ??
        stringValue(snapshot.get("email")) ??
        fallback;
}

function numberValue(value: unknown): number | undefined {
    if (typeof value === "number" && Number.isFinite(value)) {
        return value;
    }

    if (typeof value === "string") {
        const parsed = Number(value);
        return Number.isFinite(parsed) ? parsed : undefined;
    }

    return undefined;
}

function dateValue(value: unknown): Date | undefined {
    if (typeof value !== "string") {
        return undefined;
    }

    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? undefined : date;
}

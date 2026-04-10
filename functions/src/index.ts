import {initializeApp} from "firebase-admin/app";
import {getFirestore, Timestamp} from "firebase-admin/firestore";
import {getMessaging} from "firebase-admin/messaging";
import {setGlobalOptions} from "firebase-functions/v2";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import * as logger from "firebase-functions/logger";

initializeApp();
setGlobalOptions({maxInstances: 10});

type UserProfile = {
  displayName?: string;
  username?: string;
  fcmToken?: string;
  mutedNotificationUserIDs?: string[];
};

type ChatAttachment = {
  kind?: string;
  fileName?: string;
};

type ChatMessage = {
  senderID?: string;
  recipientID?: string;
  text?: string;
  sentAt?: Timestamp;
  attachment?: ChatAttachment;
};

type SignalingDocument = {
  fromUserID?: string;
  toUserID?: string;
  callID?: string;
  callType?: CallPushType;
  payload?: string;
  sentAt?: Timestamp;
};

type CallPushType = "audio" | "video";

export const sendChatMessagePush = onDocumentCreated(
  {
    document: "conversations/{conversationId}/messages/{messageId}",
    region: "us-central1",
  },
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) {
      logger.warn("Missing Firestore snapshot for chat message trigger.");
      return;
    }

    const message = snapshot.data() as ChatMessage;
    const senderID = message.senderID;
    const recipientID = message.recipientID;

    if (!senderID || !recipientID) {
      logger.warn("Chat message is missing senderID or recipientID.", {
        messageId: snapshot.id,
      });
      return;
    }

    if (senderID === recipientID) {
      logger.info("Skipping push for self-message.", {messageId: snapshot.id});
      return;
    }

    const db = getFirestore();
    const [senderSnapshot, recipientSnapshot] = await Promise.all([
      db.collection("users").doc(senderID).get(),
      db.collection("users").doc(recipientID).get(),
    ]);

    const sender = (senderSnapshot.data() ?? {}) as UserProfile;
    const recipient = (recipientSnapshot.data() ?? {}) as UserProfile;
    const fcmToken = recipient.fcmToken;
    const mutedNotificationUserIDs = recipient.mutedNotificationUserIDs ?? [];

    if (!fcmToken) {
      logger.info("Recipient does not have fcmToken. Push skipped.", {
        recipientID,
        messageId: snapshot.id,
      });
      return;
    }

    if (mutedNotificationUserIDs.includes(senderID)) {
      logger.info("Chat push skipped because sender is muted.", {
        recipientID,
        senderID,
        messageId: snapshot.id,
      });
      return;
    }

    const senderName =
      sender.displayName ||
      sender.username ||
      "Новое сообщение";
    const body = buildNotificationBody(message);
    const conversationId = event.params.conversationId;

    try {
      await getMessaging().send({
        token: fcmToken,
        notification: {
          title: senderName,
          body,
        },
        data: {
          type: "chat_message",
          conversationId,
          messageId: snapshot.id,
          senderId: senderID,
          recipientId: recipientID,
          senderName,
          body,
        },
        apns: {
          payload: {
            aps: {
              sound: "default",
              badge: 1,
            },
          },
        },
      });

      logger.info("Chat push sent successfully.", {
        messageId: snapshot.id,
        conversationId,
        recipientID,
      });
    } catch (error) {
      logger.error("Failed to send chat push.", {
        messageId: snapshot.id,
        recipientID,
        error,
      });
    }
  }
);

export const sendIncomingCallPush = onDocumentCreated(
  {
    document: "incomingCallNotifications/{messageId}",
    region: "us-central1",
  },
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) {
      logger.warn("Missing Firestore snapshot for signaling trigger.");
      return;
    }

    const document = snapshot.data() as SignalingDocument;
    const fromUserID = document.fromUserID;
    const toUserID = document.toUserID;
    const callType = document.callType;

    if (!fromUserID || !toUserID || !callType) {
      logger.warn("Signaling document is missing required fields.", {
        messageId: snapshot.id,
      });
      return;
    }

    const db = getFirestore();
    const [callerSnapshot, recipientSnapshot] = await Promise.all([
      db.collection("users").doc(fromUserID).get(),
      db.collection("users").doc(toUserID).get(),
    ]);

    const caller = (callerSnapshot.data() ?? {}) as UserProfile;
    const recipient = (recipientSnapshot.data() ?? {}) as UserProfile;
    const fcmToken = recipient.fcmToken;
    const mutedNotificationUserIDs = recipient.mutedNotificationUserIDs ?? [];

    if (!fcmToken) {
      logger.info("Recipient does not have fcmToken. Call push skipped.", {
        toUserID,
        messageId: snapshot.id,
      });
      return;
    }

    if (mutedNotificationUserIDs.includes(fromUserID)) {
      logger.info("Incoming call push skipped because caller is muted.", {
        toUserID,
        fromUserID,
        messageId: snapshot.id,
      });
      return;
    }

    const callerName =
      caller.displayName ||
      caller.username ||
      "Неизвестный пользователь";
    const body = callType === "video" ? "Видеозвонок" : "Аудиозвонок";

    try {
      await getMessaging().send({
        token: fcmToken,
        notification: {
          title: `Входящий звонок: ${callerName}`,
          body,
        },
        data: {
          type: "incoming_call",
          callId: document.callID ?? "",
          callerId: fromUserID,
          recipientId: toUserID,
          callerName,
          callType,
        },
        apns: {
          headers: {
            "apns-priority": "10",
          },
          payload: {
            aps: {
              sound: "default",
              badge: 1,
            },
          },
        },
      });

      logger.info("Incoming call push sent successfully.", {
        messageId: snapshot.id,
        toUserID,
        callType,
      });
    } catch (error) {
      logger.error("Failed to send incoming call push.", {
        messageId: snapshot.id,
        toUserID,
        error,
      });
    }
  }
);

/**
 * Builds a human-readable push body for a chat message.
 * Falls back to attachment labels when text is empty.
 * @param {ChatMessage} message
 * @return {string}
 */
function buildNotificationBody(message: ChatMessage): string {
  const trimmedText = (message.text ?? "").trim();
  if (trimmedText.length > 0) {
    return trimmedText;
  }

  if (message.attachment?.kind === "image") {
    return "Фото";
  }

  if (message.attachment?.fileName) {
    return `Файл: ${message.attachment.fileName}`;
  }

  return "Новое сообщение";
}

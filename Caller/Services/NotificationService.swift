import FirebaseCore
import FirebaseFirestore
import FirebaseMessaging
import Foundation
import UIKit
import UserNotifications

enum NotificationEvent {
    case openChat(userID: String)
    case openIncomingCall(VoIPIncomingCallPayload)
}

protocol NotificationServicing {
    var events: AsyncStream<NotificationEvent> { get }
    func configure()
    func requestAuthorization() async
    func updateCurrentUser(_ user: AppUser?) async
}

final class NotificationService: NSObject, NotificationServicing {
    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()
    private let logger = Logger()
    private var currentUserID: String?
    private var fcmToken: String?
    private var eventsContinuation: AsyncStream<NotificationEvent>.Continuation?
    private var bufferedEvents: [NotificationEvent] = []

    lazy var events: AsyncStream<NotificationEvent> = {
        AsyncStream { continuation in
            self.eventsContinuation = continuation
            self.flushBufferedEvents()
        }
    }()

    private override init() {}

    func configure() {
        center.delegate = self
        Messaging.messaging().delegate = self
    }

    func requestAuthorization() async {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            guard granted else { return }
            await MainActor.run {
                UIApplication.shared.registerForRemoteNotifications()
            }
        } catch {
            print("[ERROR] Notification authorization failed: \(error.localizedDescription)")
        }
    }

    func updateCurrentUser(_ user: AppUser?) async {
        let previousUserID = currentUserID
        currentUserID = user?.id
        guard user != nil else {
            await removeFCMToken(for: previousUserID)
            return
        }
        await syncPushTokenIfPossible()
    }

    func registerDeviceToken(_ deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) {
        logger.info("Received remote notification payload: \(userInfo)")
    }

    func handleNotificationResponse(_ userInfo: [AnyHashable: Any]) {
        handleRemoteNotification(userInfo)
        guard let event = makeNotificationEvent(from: userInfo) else { return }
        yield(event)
    }

    private func updateFCMToken(_ token: String) {
        fcmToken = token
        Task {
            await syncPushTokenIfPossible()
        }
    }

    private func syncPushTokenIfPossible() async {
        guard FirebaseApp.app() != nil,
              let currentUserID,
              let fcmToken,
              !fcmToken.isEmpty else {
            return
        }

        do {
            try await Firestore.firestore().collection("users").document(currentUserID).setData([
                "fcmToken": fcmToken,
                "fcmUpdatedAt": Timestamp(date: .now)
            ], merge: true)
        } catch {
            logger.error("Failed to sync FCM token: \(error.localizedDescription)")
        }
    }

    private func removeFCMToken(for userID: String?) async {
        guard FirebaseApp.app() != nil,
              let userID else {
            return
        }

        do {
            try await Firestore.firestore().collection("users").document(userID).updateData([
                "fcmToken": FieldValue.delete(),
                "fcmUpdatedAt": FieldValue.delete()
            ])
        } catch {
            logger.error("Failed to remove FCM token: \(error.localizedDescription)")
        }
    }

    private func makeNotificationEvent(from userInfo: [AnyHashable: Any]) -> NotificationEvent? {
        let rawType = (userInfo["type"] as? String) ?? ((userInfo["data"] as? [String: Any])?["type"] as? String)

        switch rawType {
        case "chat_message":
            guard let userID = (userInfo["senderId"] as? String) ??
                    ((userInfo["data"] as? [String: Any])?["senderId"] as? String) else {
                return nil
            }
            return .openChat(userID: userID)
        case "incoming_call":
            return makeIncomingCallEvent(from: userInfo)
        default:
            return nil
        }
    }

    private func makeIncomingCallEvent(from userInfo: [AnyHashable: Any]) -> NotificationEvent? {
        let callIDString = (userInfo["callId"] as? String) ??
            ((userInfo["data"] as? [String: Any])?["callId"] as? String)
        let callerID = (userInfo["callerId"] as? String) ??
            ((userInfo["data"] as? [String: Any])?["callerId"] as? String) ?? ""
        let callerName = (userInfo["callerName"] as? String) ??
            ((userInfo["data"] as? [String: Any])?["callerName"] as? String) ??
            "Неизвестный пользователь"
        let callTypeRawValue = (userInfo["callType"] as? String) ??
            ((userInfo["data"] as? [String: Any])?["callType"] as? String) ??
            CallType.audio.rawValue

        guard let callIDString,
              let callID = UUID(uuidString: callIDString),
              let callType = CallType(rawValue: callTypeRawValue) else {
            return nil
        }

        return .openIncomingCall(
            VoIPIncomingCallPayload(
                callID: callID,
                callerID: callerID,
                callerName: callerName,
                callerEmail: "",
                type: callType
            )
        )
    }

    private func yield(_ event: NotificationEvent) {
        if let eventsContinuation {
            eventsContinuation.yield(event)
        } else {
            bufferedEvents.append(event)
        }
    }

    private func flushBufferedEvents() {
        guard let eventsContinuation else { return }
        bufferedEvents.forEach { eventsContinuation.yield($0) }
        bufferedEvents.removeAll()
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        handleNotificationResponse(response.notification.request.content.userInfo)
        completionHandler()
    }
}

extension NotificationService: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        logger.info("FCM token received.")
        updateFCMToken(fcmToken)
    }
}

final class NotificationAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        NotificationService.shared.registerDeviceToken(deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Logger().error("APNs registration failed: \(error.localizedDescription)")
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        NotificationService.shared.handleRemoteNotification(userInfo)
        completionHandler(.newData)
    }
}

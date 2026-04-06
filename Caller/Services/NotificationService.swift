import Foundation
import UserNotifications

protocol NotificationServicing {
    func configure()
    func requestAuthorization() async
    func notifyIncomingMessage(from senderName: String, message: String)
    func notifyIncomingCall(from callerName: String, type: CallType)
}

final class NotificationService: NSObject, NotificationServicing {
    private let center = UNUserNotificationCenter.current()

    func configure() {
        center.delegate = self
    }

    func requestAuthorization() async {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            print("[ERROR] Notification authorization failed: \(error.localizedDescription)")
        }
    }

    func notifyIncomingMessage(from senderName: String, message: String) {
        scheduleNotification(
            identifier: "message-\(UUID().uuidString)",
            title: senderName,
            body: message.isEmpty ? "Новое сообщение" : message,
            sound: .default
        )
    }

    func notifyIncomingCall(from callerName: String, type: CallType) {
        scheduleNotification(
            identifier: "call-\(UUID().uuidString)",
            title: callerName,
            body: type == .video ? "Видеозвонок" : "Аудиозвонок",
            sound: .default
        )
    }

    private func scheduleNotification(identifier: String, title: String, body: String, sound: UNNotificationSound?) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = sound

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        )

        center.add(request)
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
}

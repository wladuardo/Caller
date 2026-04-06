import AVFoundation
import CallKit
import FirebaseCore
import FirebaseFirestore
import Foundation
import PushKit

enum SystemCallEvent {
    case incomingPush(VoIPIncomingCallPayload)
    case answerRequested(UUID)
    case endRequested(UUID)
}

struct VoIPIncomingCallPayload: Equatable {
    let callID: UUID
    let callerID: String
    let callerName: String
    let callerEmail: String
    let type: CallType
}

final class SystemCallService: NSObject {
    static let shared = SystemCallService()

    private let logger = Logger()
    private let provider: CXProvider
    private var pushRegistry: PKPushRegistry?
    private var currentUserID: String?
    private var voipToken: String?
    private var eventsContinuation: AsyncStream<SystemCallEvent>.Continuation?
    private var bufferedEvents: [SystemCallEvent] = []
    private var pendingAnswerActions: [UUID: CXAnswerCallAction] = [:]

    lazy var events: AsyncStream<SystemCallEvent> = {
        AsyncStream { continuation in
            self.eventsContinuation = continuation
            self.flushBufferedEvents()
        }
    }()

    private override init() {
        let configuration = CXProviderConfiguration(localizedName: "Caller")
        configuration.supportsVideo = true
        configuration.maximumCallsPerCallGroup = 1
        configuration.maximumCallGroups = 1
        configuration.supportedHandleTypes = [.generic]
        configuration.includesCallsInRecents = false
        self.provider = CXProvider(configuration: configuration)
        super.init()
    }

    func configure() {
        provider.setDelegate(self, queue: nil)

        DispatchQueue.main.async {
            let registry = PKPushRegistry(queue: .main)
            registry.delegate = self
            registry.desiredPushTypes = [.voIP]
            self.pushRegistry = registry
        }
    }

    func updateCurrentUser(_ user: AppUser?) async {
        let previousUserID = currentUserID
        currentUserID = user?.id
        guard user != nil else {
            await removeVoIPToken(for: previousUserID)
            return
        }
        await syncVoIPTokenIfPossible()
    }

    func reportCallConnected(_ callID: UUID) {
        pendingAnswerActions.removeValue(forKey: callID)?.fulfill()
    }

    func reportCallEnded(_ callID: UUID, reason: CXCallEndedReason) {
        pendingAnswerActions.removeValue(forKey: callID)?.fulfill()
        provider.reportCall(with: callID, endedAt: .now, reason: reason)
    }

    private func handleIncomingVoIPPush(_ payload: PKPushPayload, completion: @escaping () -> Void) {
        guard let callPayload = makeIncomingCallPayload(from: payload.dictionaryPayload) else {
            logger.error("Failed to parse incoming VoIP push payload.")
            completion()
            return
        }

        yield(.incomingPush(callPayload))

        let update = CXCallUpdate()
        update.localizedCallerName = callPayload.callerName
        update.remoteHandle = CXHandle(type: .generic, value: callPayload.callerEmail.isEmpty ? callPayload.callerName : callPayload.callerEmail)
        update.hasVideo = callPayload.type == .video

        provider.reportNewIncomingCall(with: callPayload.callID, update: update) { [weak self] error in
            if let error {
                self?.logger.error("Failed to report incoming call: \(error.localizedDescription)")
            }
            completion()
        }
    }

    private func makeIncomingCallPayload(from dictionary: [AnyHashable: Any]) -> VoIPIncomingCallPayload? {
        let callIDKey = dictionary["callID"] as? String ?? dictionary["callId"] as? String ?? dictionary["uuid"] as? String
        let callerID = dictionary["callerID"] as? String ?? dictionary["callerId"] as? String ?? dictionary["fromUserID"] as? String ?? ""
        let callerName = dictionary["callerName"] as? String ?? dictionary["displayName"] as? String ?? "Неизвестный пользователь"
        let callerEmail = dictionary["callerEmail"] as? String ?? dictionary["email"] as? String ?? ""
        let typeRawValue = dictionary["callType"] as? String ?? dictionary["type"] as? String ?? CallType.audio.rawValue

        guard let callIDKey,
              let callID = UUID(uuidString: callIDKey),
              let type = CallType(rawValue: typeRawValue) else {
            return nil
        }

        return VoIPIncomingCallPayload(
            callID: callID,
            callerID: callerID,
            callerName: callerName,
            callerEmail: callerEmail,
            type: type
        )
    }

    private func yield(_ event: SystemCallEvent) {
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

    private func updateVoIPToken(_ token: String?) {
        voipToken = token
        Task {
            await syncVoIPTokenIfPossible()
        }
    }

    private func syncVoIPTokenIfPossible() async {
        guard FirebaseApp.app() != nil,
              let currentUserID else {
            return
        }

        do {
            if let voipToken, !voipToken.isEmpty {
                try await Firestore.firestore().collection("users").document(currentUserID).setData([
                    "voipToken": voipToken,
                    "voipUpdatedAt": Timestamp(date: .now)
                ], merge: true)
            } else {
                try await Firestore.firestore().collection("users").document(currentUserID).updateData([
                    "voipToken": FieldValue.delete(),
                    "voipUpdatedAt": FieldValue.delete()
                ])
            }
        } catch {
            logger.error("Failed to sync VoIP token: \(error.localizedDescription)")
        }
    }

    private func removeVoIPToken(for userID: String?) async {
        guard FirebaseApp.app() != nil,
              let userID else {
            return
        }

        do {
            try await Firestore.firestore().collection("users").document(userID).updateData([
                "voipToken": FieldValue.delete(),
                "voipUpdatedAt": FieldValue.delete()
            ])
        } catch {
            logger.error("Failed to remove VoIP token: \(error.localizedDescription)")
        }
    }

    private func hexString(from data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}

extension SystemCallService: PKPushRegistryDelegate {
    func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        guard type == .voIP else { return }
        updateVoIPToken(hexString(from: pushCredentials.token))
    }

    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        guard type == .voIP else { return }
        updateVoIPToken(nil)
    }

    func pushRegistry(
        _ registry: PKPushRegistry,
        didReceiveIncomingPushWith payload: PKPushPayload,
        for type: PKPushType,
        completion: @escaping @Sendable () -> Void
    ) {
        guard type == .voIP else {
            completion()
            return
        }

        handleIncomingVoIPPush(payload, completion: completion)
    }
}

extension SystemCallService: CXProviderDelegate {
    func providerDidReset(_ provider: CXProvider) {
        pendingAnswerActions.values.forEach { $0.fail() }
        pendingAnswerActions.removeAll()
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        pendingAnswerActions[action.callUUID] = action
        yield(.answerRequested(action.callUUID))
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        pendingAnswerActions.removeValue(forKey: action.callUUID)
        yield(.endRequested(action.callUUID))
        action.fulfill()
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        logger.info("CallKit activated audio session.")
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        logger.info("CallKit deactivated audio session.")
    }
}

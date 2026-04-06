import Foundation

enum CallType: String, Codable, CaseIterable {
    case audio
    case video
}

enum CallStatus: String, Codable {
    case idle
    case ringing
    case connecting
    case connected
    case ended
    case failed
}

enum CallDirection: String, Codable {
    case incoming
    case outgoing
}

struct CallParticipant: Identifiable, Equatable {
    let id: String
    let name: String
    let email: String
}

struct CallSession: Identifiable, Equatable {
    let id: UUID
    let participant: CallParticipant
    let direction: CallDirection
    let type: CallType
    var status: CallStatus
    var isMuted: Bool
    var isSpeakerEnabled: Bool
    var isCameraEnabled: Bool
    var isUsingFrontCamera: Bool
    var startedAt: Date?

    static let preview = CallSession(
        id: UUID(),
        participant: CallParticipant(
            id: "preview-user",
            name: "Jordan Lee",
            email: "jordan@example.com"
        ),
        direction: .outgoing,
        type: .video,
        status: .connected,
        isMuted: false,
        isSpeakerEnabled: true,
        isCameraEnabled: true,
        isUsingFrontCamera: true,
        startedAt: .now
    )
}

enum CallError: LocalizedError, Identifiable {
    case permissionDenied(String)
    case signalingUnavailable
    case transportFailure
    case general(String)

    var id: String { localizedDescription }

    var errorDescription: String? {
        switch self {
        case .permissionDenied(let value):
            return value
        case .signalingUnavailable:
            return "Сервер сигналинга недоступен."
        case .transportFailure:
            return "Соединение передачи медиа было разорвано."
        case .general(let value):
            return value
        }
    }
}

enum SignalingPayload: Codable, Equatable {
    case offer(sdp: String, type: CallType)
    case answer(sdp: String)
    case iceCandidate(IceCandidatePayload)
    case hangup
}

struct SignalingMessage: Codable, Equatable {
    let callID: UUID
    let fromUserID: String
    let toUserID: String
    let payload: SignalingPayload
    let sentAt: Date
}

struct IceCandidatePayload: Codable, Equatable {
    let sdp: String
    let sdpMLineIndex: Int32
    let sdpMid: String?
}

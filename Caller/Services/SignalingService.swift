import FirebaseFirestore
import Foundation

protocol SignalingServicing: AnyObject {
    var incomingMessages: AsyncStream<SignalingMessage> { get }
    func connect(userID: String) async throws
    func disconnect()
    func send(_ message: SignalingMessage) async throws
}

final class MockWebSocketSignalingService: SignalingServicing {
    private var continuation: AsyncStream<SignalingMessage>.Continuation?
    private var bufferedMessages: [SignalingMessage] = []
    lazy var incomingMessages: AsyncStream<SignalingMessage> = {
        AsyncStream { continuation in
            self.continuation = continuation
            self.flushBufferedMessages()
        }
    }()

    func connect(userID: String) async throws {
        _ = userID
    }

    func disconnect() {
    }

    func send(_ message: SignalingMessage) async throws {
        // Intentionally a no-op. Real SDP and ICE exchange requires another peer
        // and a signaling backend; fake answers would break the WebRTC handshake.
        _ = message
    }

    private func flushBufferedMessages() {
        guard let continuation else { return }
        bufferedMessages.forEach { continuation.yield($0) }
        bufferedMessages.removeAll()
    }
}

final class WebSocketSignalingService: SignalingServicing {
    private let client: WebSocketClient

    var incomingMessages: AsyncStream<SignalingMessage> {
        client.messages
    }

    init(client: WebSocketClient) {
        self.client = client
    }

    func connect(userID: String) async throws {
        _ = userID
        try await client.connect()
    }

    func disconnect() {
        client.disconnect()
    }

    func send(_ message: SignalingMessage) async throws {
        try await client.send(message)
    }
}

final class FirebaseFirestoreSignalingService: SignalingServicing {
    private let db: Firestore
    private let collectionName: String
    private let logger = Logger()
    private var listener: ListenerRegistration?
    private var continuation: AsyncStream<SignalingMessage>.Continuation?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var processedDocumentIDs = Set<String>()
    private var bufferedMessages: [SignalingMessage] = []

    lazy var incomingMessages: AsyncStream<SignalingMessage> = {
        AsyncStream { continuation in
            self.continuation = continuation
            self.flushBufferedMessages()
        }
    }()

    init(db: Firestore = Firestore.firestore(), collectionName: String = "signalingMessages") {
        self.db = db
        self.collectionName = collectionName
    }

    func connect(userID: String) async throws {
        listener?.remove()
        processedDocumentIDs.removeAll()
        logger.info("Starting Firestore signaling listener for user \(userID)")
        listener = db.collection(collectionName)
            .whereField("toUserID", isEqualTo: userID)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error {
                    self.logger.error("Firestore signaling listener failed: \(error.localizedDescription)")
                    return
                }
                guard let snapshot else { return }
                self.logger.info("Received signaling snapshot with \(snapshot.documents.count) documents for user \(userID)")

                let sortedDocuments = snapshot.documents.sorted {
                    let lhs = ($0["sentAt"] as? Timestamp)?.dateValue() ?? .distantPast
                    let rhs = ($1["sentAt"] as? Timestamp)?.dateValue() ?? .distantPast
                    return lhs < rhs
                }

                for document in sortedDocuments {
                    guard !self.processedDocumentIDs.contains(document.documentID),
                          let payload = document["payload"] as? String,
                          let data = payload.data(using: .utf8),
                          let message = try? self.decoder.decode(SignalingMessage.self, from: data) else {
                        continue
                    }

                    self.logger.info("Received signaling message \(message.payload.logDescription) for call \(message.callID.uuidString) from \(message.fromUserID) to \(message.toUserID)")
                    self.processedDocumentIDs.insert(document.documentID)
                    if let continuation = self.continuation {
                        continuation.yield(message)
                    } else {
                        self.bufferedMessages.append(message)
                    }
                    document.reference.delete()
                }
            }
    }

    func disconnect() {
        listener?.remove()
        listener = nil
    }

    func send(_ message: SignalingMessage) async throws {
        let data = try encoder.encode(message)
        let payload = String(decoding: data, as: UTF8.self)
        logger.info("Sending signaling message \(message.payload.logDescription) for call \(message.callID.uuidString) from \(message.fromUserID) to \(message.toUserID)")
        try await db.collection(collectionName).addDocument(data: [
            "toUserID": message.toUserID,
            "fromUserID": message.fromUserID,
            "callID": message.callID.uuidString,
            "sentAt": Timestamp(date: message.sentAt),
            "payload": payload
        ])
    }

    private func flushBufferedMessages() {
        guard let continuation else { return }
        bufferedMessages.forEach { continuation.yield($0) }
        bufferedMessages.removeAll()
    }
}

extension SignalingPayload {
    var logDescription: String {
        switch self {
        case .offer:
            return "offer"
        case .answer:
            return "answer"
        case .iceCandidate:
            return "iceCandidate"
        case .hangup:
            return "hangup"
        }
    }
}

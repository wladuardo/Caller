import FirebaseFirestore
import Foundation

protocol ChatServicing {
    func observeMessages(with user: AppUser, currentUser: AppUser) -> AsyncStream<[ChatMessage]>
    func observeConversationSummaries(for currentUser: AppUser) -> AsyncStream<[ChatConversationSummary]>
    func observeUnreadMessages(for currentUser: AppUser) -> AsyncStream<[UnreadMessageSummary]>
    func prepareConversation(with user: AppUser, currentUser: AppUser) async throws
    func markConversationAsRead(with user: AppUser, currentUser: AppUser) async throws
    func sendMessage(_ text: String, to user: AppUser, from currentUser: AppUser) async throws
}

struct MockChatService: ChatServicing {
    func observeMessages(with user: AppUser, currentUser: AppUser) -> AsyncStream<[ChatMessage]> {
        let conversationID = ChatConversation.id(for: currentUser.id, and: user.id)
        let messages = [
            ChatMessage(
                id: "welcome-1",
                conversationID: conversationID,
                senderID: user.id,
                recipientID: currentUser.id,
                text: "Hey, ready for a call later?",
                sentAt: Date().addingTimeInterval(-180),
                isReadByRecipient: false
            ),
            ChatMessage(
                id: "welcome-2",
                conversationID: conversationID,
                senderID: currentUser.id,
                recipientID: user.id,
                text: "Sure. Ping me here first.",
                sentAt: Date().addingTimeInterval(-120),
                isReadByRecipient: true
            )
        ]

        return AsyncStream { continuation in
            continuation.yield(messages)
            continuation.finish()
        }
    }

    func observeConversationSummaries(for currentUser: AppUser) -> AsyncStream<[ChatConversationSummary]> {
        let summary = ChatConversationSummary(
            id: ChatConversation.id(for: currentUser.id, and: "jordan"),
            participantIDs: [currentUser.id, "jordan"],
            lastMessageText: "Sure. Ping me here first.",
            lastMessageSenderID: currentUser.id,
            updatedAt: .now,
            unreadCounts: ["jordan": 0, currentUser.id: 1]
        )

        return AsyncStream { continuation in
            continuation.yield([summary])
            continuation.finish()
        }
    }

    func observeUnreadMessages(for currentUser: AppUser) -> AsyncStream<[UnreadMessageSummary]> {
        _ = currentUser
        return AsyncStream { continuation in
            continuation.yield([])
            continuation.finish()
        }
    }

    func prepareConversation(with user: AppUser, currentUser: AppUser) async throws {
        _ = user
        _ = currentUser
    }

    func markConversationAsRead(with user: AppUser, currentUser: AppUser) async throws {
        _ = user
        _ = currentUser
    }

    func sendMessage(_ text: String, to user: AppUser, from currentUser: AppUser) async throws {
        _ = text
        _ = user
        _ = currentUser
    }
}

final class FirebaseChatService: ChatServicing {
    private let db: Firestore
    private let logger: Logger
    private let cache = PersistentChatMessageCache()

    init(db: Firestore = Firestore.firestore(), logger: Logger = Logger()) {
        self.db = db
        self.logger = logger
    }

    func observeMessages(with user: AppUser, currentUser: AppUser) -> AsyncStream<[ChatMessage]> {
        let conversationID = ChatConversation.id(for: currentUser.id, and: user.id)

        return AsyncStream { continuation in
            let listenerBox = ListenerBox()
            let setupTask = Task {
                let cachedMessages = await cache.messages(for: conversationID)
                if !cachedMessages.isEmpty {
                    continuation.yield(cachedMessages)
                }

                do {
                    try await prepareConversation(with: user, currentUser: currentUser)
                } catch {
                    logger.error("Failed to prepare conversation: \(error.localizedDescription)")
                }

                listenerBox.listener = db.collection("conversations")
                    .document(conversationID)
                    .collection("messages")
                    .order(by: "sentAt")
                    .addSnapshotListener { [logger] snapshot, error in
                        if let error {
                            logger.error("Chat listener failed: \(error.localizedDescription)")
                            return
                        }
                        guard let snapshot else { return }

                        let messages = snapshot.documents.compactMap { document -> ChatMessage? in
                            guard let senderID = document["senderID"] as? String,
                                  let recipientID = document["recipientID"] as? String,
                                  let text = document["text"] as? String else {
                                return nil
                            }

                            return ChatMessage(
                                id: document.documentID,
                                conversationID: conversationID,
                                senderID: senderID,
                                recipientID: recipientID,
                                text: text,
                                sentAt: (document["sentAt"] as? Timestamp)?.dateValue() ?? .now,
                                isReadByRecipient: (document["isReadByRecipient"] as? Bool) ?? false
                            )
                        }

                        Task {
                            await self.cache.store(messages, for: conversationID)
                        }
                        continuation.yield(messages)
                    }
            }

            continuation.onTermination = { _ in
                setupTask.cancel()
                listenerBox.listener?.remove()
            }
        }
    }

    func observeConversationSummaries(for currentUser: AppUser) -> AsyncStream<[ChatConversationSummary]> {
        AsyncStream { continuation in
            let listener = db.collection("conversations")
                .whereField("participantIDs", arrayContains: currentUser.id)
                .addSnapshotListener { [logger] snapshot, error in
                    if let error {
                        logger.error("Conversation listener failed: \(error.localizedDescription)")
                        return
                    }
                    guard let snapshot else { return }

                    let summaries = snapshot.documents.compactMap { document -> ChatConversationSummary? in
                        guard let participantIDs = document["participantIDs"] as? [String] else {
                            return nil
                        }

                        let rawUnreadCounts = document["unreadCounts"] as? [String: Any] ?? [:]
                        let unreadCounts = rawUnreadCounts.reduce(into: [String: Int]()) { partialResult, entry in
                            if let value = entry.value as? Int {
                                partialResult[entry.key] = value
                            } else if let number = entry.value as? NSNumber {
                                partialResult[entry.key] = number.intValue
                            }
                        }

                        return ChatConversationSummary(
                            id: document.documentID,
                            participantIDs: participantIDs,
                            lastMessageText: document["lastMessageText"] as? String ?? "",
                            lastMessageSenderID: document["lastMessageSenderID"] as? String ?? "",
                            updatedAt: (document["updatedAt"] as? Timestamp)?.dateValue() ?? .distantPast,
                            unreadCounts: unreadCounts
                        )
                    }
                    .sorted { $0.updatedAt > $1.updatedAt }

                    continuation.yield(summaries)
                }

            continuation.onTermination = { _ in
                listener.remove()
            }
        }
    }

    func observeUnreadMessages(for currentUser: AppUser) -> AsyncStream<[UnreadMessageSummary]> {
        _ = currentUser
        return AsyncStream { continuation in
            continuation.yield([])
            continuation.finish()
        }
    }

    func prepareConversation(with user: AppUser, currentUser: AppUser) async throws {
        let conversationID = ChatConversation.id(for: currentUser.id, and: user.id)
        let conversationRef = db.collection("conversations").document(conversationID)
        try await conversationRef.setData([
            "id": conversationID,
            "participantIDs": [currentUser.id, user.id].sorted(),
            "unreadCounts": [
                currentUser.id: 0,
                user.id: 0
            ],
            "updatedAt": Timestamp(date: .now)
        ], merge: true)
    }

    func markConversationAsRead(with user: AppUser, currentUser: AppUser) async throws {
        let conversationID = ChatConversation.id(for: currentUser.id, and: user.id)
        let conversationRef = db.collection("conversations").document(conversationID)
        try await conversationRef.setData([
            "unreadCounts.\(currentUser.id)": 0
        ], merge: true)

        let unreadMessages = try await conversationRef
            .collection("messages")
            .whereField("senderID", isEqualTo: user.id)
            .whereField("recipientID", isEqualTo: currentUser.id)
            .getDocuments()

        let batch = db.batch()
        unreadMessages.documents.forEach { document in
            batch.updateData(["isReadByRecipient": true], forDocument: document.reference)
        }
        try await batch.commit()

        let cachedMessages = await cache.messages(for: conversationID).map { message in
            guard message.senderID == user.id, message.recipientID == currentUser.id else {
                return message
            }
            return ChatMessage(
                id: message.id,
                conversationID: message.conversationID,
                senderID: message.senderID,
                recipientID: message.recipientID,
                text: message.text,
                sentAt: message.sentAt,
                isReadByRecipient: true
            )
        }
        await cache.store(cachedMessages, for: conversationID)
    }

    func sendMessage(_ text: String, to user: AppUser, from currentUser: AppUser) async throws {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        let conversationID = ChatConversation.id(for: currentUser.id, and: user.id)
        let conversationRef = db.collection("conversations").document(conversationID)
        let messageRef = conversationRef.collection("messages").document()
        let sentAt = Timestamp(date: .now)

        let batch = db.batch()
        batch.setData([
            "id": conversationID,
            "participantIDs": [currentUser.id, user.id].sorted(),
            "updatedAt": sentAt,
            "lastMessageText": trimmedText,
            "lastMessageSenderID": currentUser.id,
            "unreadCounts.\(currentUser.id)": 0,
            "unreadCounts.\(user.id)": FieldValue.increment(Int64(1))
        ], forDocument: conversationRef, merge: true)
        batch.setData([
            "senderID": currentUser.id,
            "recipientID": user.id,
            "text": trimmedText,
            "sentAt": sentAt,
            "isReadByRecipient": false
        ], forDocument: messageRef)
        do {
            try await batch.commit()
            let newMessage = ChatMessage(
                id: messageRef.documentID,
                conversationID: conversationID,
                senderID: currentUser.id,
                recipientID: user.id,
                text: trimmedText,
                sentAt: sentAt.dateValue(),
                isReadByRecipient: false
            )
            await cache.append(newMessage, for: conversationID)
        } catch {
            logger.error("Failed to send chat message: \(error.localizedDescription)")
            throw error
        }
    }
}

private actor PersistentChatMessageCache {
    private var storage: [String: [ChatMessage]] = [:]
    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let cacheDirectoryURL: URL?

    init() {
        if let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let directoryURL = applicationSupportURL.appendingPathComponent("ChatCache", isDirectory: true)
            try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            cacheDirectoryURL = directoryURL
        } else {
            cacheDirectoryURL = nil
        }
    }

    func messages(for conversationID: String) -> [ChatMessage] {
        if let cachedMessages = storage[conversationID] {
            return cachedMessages
        }

        guard let fileURL = fileURL(for: conversationID),
              let data = try? Data(contentsOf: fileURL),
              let messages = try? decoder.decode([ChatMessage].self, from: data) else {
            return []
        }

        storage[conversationID] = messages
        return messages
    }

    func store(_ messages: [ChatMessage], for conversationID: String) {
        storage[conversationID] = messages
        persist(messages, for: conversationID)
    }

    func append(_ message: ChatMessage, for conversationID: String) {
        var messages = storage[conversationID] ?? []
        messages.removeAll { $0.id == message.id }
        messages.append(message)
        messages.sort { $0.sentAt < $1.sentAt }
        storage[conversationID] = messages
        persist(messages, for: conversationID)
    }

    private func persist(_ messages: [ChatMessage], for conversationID: String) {
        guard let fileURL = fileURL(for: conversationID),
              let data = try? encoder.encode(messages) else {
            return
        }

        try? data.write(to: fileURL, options: .atomic)
    }

    private func fileURL(for conversationID: String) -> URL? {
        cacheDirectoryURL?.appendingPathComponent("\(conversationID).json")
    }
}

private final class ListenerBox {
    var listener: ListenerRegistration?
}

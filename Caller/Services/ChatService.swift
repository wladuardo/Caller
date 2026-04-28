import FirebaseFirestore
import Foundation
#if canImport(FirebaseStorage)
import FirebaseStorage
#endif
import UIKit

protocol ChatServicing {
    func cachedMessages(with user: AppUser, currentUser: AppUser) async -> [ChatMessage]
    func observeMessages(with user: AppUser, currentUser: AppUser) -> AsyncStream<[ChatMessage]>
    func observeTypingStatus(with user: AppUser, currentUser: AppUser) -> AsyncStream<Bool>
    func observeConversationSummaries(for currentUser: AppUser) -> AsyncStream<[ChatConversationSummary]>
    func observeUnreadMessages(for currentUser: AppUser) -> AsyncStream<[UnreadMessageSummary]>
    func prepareConversation(with user: AppUser, currentUser: AppUser) async throws
    func markConversationAsRead(with user: AppUser, currentUser: AppUser) async throws
    func setTyping(_ isTyping: Bool, with user: AppUser, currentUser: AppUser) async throws
    func sendMessage(_ text: String, attachment: ChatDraftAttachment?, to user: AppUser, from currentUser: AppUser) async throws
}

struct MockChatService: ChatServicing {
    func cachedMessages(with user: AppUser, currentUser: AppUser) async -> [ChatMessage] {
        let conversationID = ChatConversation.id(for: currentUser.id, and: user.id)
        return [
            ChatMessage(
                id: "welcome-1",
                conversationID: conversationID,
                senderID: user.id,
                recipientID: currentUser.id,
                text: "Hey, ready for a call later?",
                attachment: nil,
                sentAt: Date().addingTimeInterval(-180),
                isReadByRecipient: false
            ),
            ChatMessage(
                id: "welcome-2",
                conversationID: conversationID,
                senderID: currentUser.id,
                recipientID: user.id,
                text: "Sure. Ping me here first.",
                attachment: nil,
                sentAt: Date().addingTimeInterval(-120),
                isReadByRecipient: true
            )
        ]
    }

    func observeMessages(with user: AppUser, currentUser: AppUser) -> AsyncStream<[ChatMessage]> {
        return AsyncStream { continuation in
            Task {
                let messages = await cachedMessages(with: user, currentUser: currentUser)
                continuation.yield(messages)
                continuation.finish()
            }
        }
    }

    func observeTypingStatus(with user: AppUser, currentUser: AppUser) -> AsyncStream<Bool> {
        _ = user
        _ = currentUser
        return AsyncStream { continuation in
            continuation.yield(false)
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

    func setTyping(_ isTyping: Bool, with user: AppUser, currentUser: AppUser) async throws {
        _ = isTyping
        _ = user
        _ = currentUser
    }

    func sendMessage(_ text: String, attachment: ChatDraftAttachment?, to user: AppUser, from currentUser: AppUser) async throws {
        _ = text
        _ = attachment
        _ = user
        _ = currentUser
    }
}

final class FirebaseChatService: ChatServicing {
    private let db: Firestore
    private let logger: Logger
    private let cache = PersistentChatMessageCache()
    private let encryptionService: ChatEncryptionService

    init(
        db: Firestore = Firestore.firestore(),
        logger: Logger = Logger(),
        encryptionService: ChatEncryptionService = .shared
    ) {
        self.db = db
        self.logger = logger
        self.encryptionService = encryptionService
    }

    func cachedMessages(with user: AppUser, currentUser: AppUser) async -> [ChatMessage] {
        let conversationID = ChatConversation.id(for: currentUser.id, and: user.id)
        let records = await cache.records(for: conversationID)
        return await makeChatMessages(
            from: records,
            participant: user,
            currentUser: currentUser,
            conversationID: conversationID
        )
    }

    func observeMessages(with user: AppUser, currentUser: AppUser) -> AsyncStream<[ChatMessage]> {
        let conversationID = ChatConversation.id(for: currentUser.id, and: user.id)

        return AsyncStream { continuation in
            let listenerBox = ListenerBox()
            let setupTask = Task {
                let cachedMessages = await cachedMessages(with: user, currentUser: currentUser)
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

                        let records = snapshot.documents.compactMap { document -> StoredChatMessageRecord? in
                            guard let senderID = document["senderID"] as? String,
                                  let recipientID = document["recipientID"] as? String else {
                                return nil
                            }

                            let attachment: ChatAttachment?
                            if let rawAttachment = document["attachment"] as? [String: Any],
                               let kindRawValue = rawAttachment["kind"] as? String,
                               let kind = ChatAttachmentKind(rawValue: kindRawValue),
                               let fileName = rawAttachment["fileName"] as? String,
                               let storagePath = rawAttachment["storagePath"] as? String,
                               let downloadURL = rawAttachment["downloadURL"] as? String {
                                attachment = ChatAttachment(
                                    kind: kind,
                                    fileName: fileName,
                                    storagePath: storagePath,
                                    downloadURL: downloadURL,
                                    contentType: rawAttachment["contentType"] as? String,
                                    fileSize: rawAttachment["fileSize"] as? Int
                                )
                            } else {
                                attachment = nil
                            }

                            let textEncryptionVersion = document["textEncryptionVersion"] as? Int
                                ?? (document["textEncryptionVersion"] as? NSNumber)?.intValue

                            return StoredChatMessageRecord(
                                id: document.documentID,
                                conversationID: conversationID,
                                senderID: senderID,
                                recipientID: recipientID,
                                text: document["text"] as? String ?? "",
                                textEncryptionVersion: textEncryptionVersion,
                                attachment: attachment,
                                sentAt: (document["sentAt"] as? Timestamp)?.dateValue() ?? .now,
                                isReadByRecipient: (document["isReadByRecipient"] as? Bool) ?? false
                            )
                        }

                        Task {
                            await self.cache.store(records, for: conversationID)
                            let messages = await self.makeChatMessages(
                                from: records,
                                participant: user,
                                currentUser: currentUser,
                                conversationID: conversationID
                            )
                            continuation.yield(messages)
                        }
                    }
            }

            continuation.onTermination = { _ in
                setupTask.cancel()
                Task { @MainActor in
                    listenerBox.listener?.remove()
                }
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

    func observeTypingStatus(with user: AppUser, currentUser: AppUser) -> AsyncStream<Bool> {
        let conversationID = ChatConversation.id(for: currentUser.id, and: user.id)

        return AsyncStream { continuation in
            let listener = db.collection("conversations")
                .document(conversationID)
                .addSnapshotListener { [logger] snapshot, error in
                    if let error {
                        logger.error("Typing listener failed: \(error.localizedDescription)")
                        continuation.yield(false)
                        return
                    }

                    guard let data = snapshot?.data() else {
                        continuation.yield(false)
                        return
                    }

                    let rawTypingStates = data["typingStates"] as? [String: Any] ?? [:]
                    let typingStates = rawTypingStates.reduce(into: [String: Bool]()) { partialResult, entry in
                        if let value = entry.value as? Bool {
                            partialResult[entry.key] = value
                        } else if let number = entry.value as? NSNumber {
                            partialResult[entry.key] = number.boolValue
                        }
                    }
                    continuation.yield(typingStates[user.id] ?? false)
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
            "typingStates": [
                currentUser.id: false,
                user.id: false
            ],
            "typingUpdatedAt": [
                currentUser.id: Timestamp(date: .now),
                user.id: Timestamp(date: .now)
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

        let cachedRecords = await cache.records(for: conversationID).map { record in
            guard record.senderID == user.id, record.recipientID == currentUser.id else {
                return record
            }
            return StoredChatMessageRecord(
                id: record.id,
                conversationID: record.conversationID,
                senderID: record.senderID,
                recipientID: record.recipientID,
                text: record.text,
                textEncryptionVersion: record.textEncryptionVersion,
                attachment: record.attachment,
                sentAt: record.sentAt,
                isReadByRecipient: true
            )
        }
        await cache.store(cachedRecords, for: conversationID)
    }

    func setTyping(_ isTyping: Bool, with user: AppUser, currentUser: AppUser) async throws {
        let conversationID = ChatConversation.id(for: currentUser.id, and: user.id)
        let conversationRef = db.collection("conversations").document(conversationID)
        do {
            try await conversationRef.updateData([
                "typingStates.\(currentUser.id)": isTyping,
                "typingUpdatedAt.\(currentUser.id)": Timestamp(date: .now)
            ])
        } catch {
            logger.error("Typing update failed, recreating conversation document: \(error.localizedDescription)")
            try await conversationRef.setData([
                "id": conversationID,
                "participantIDs": [currentUser.id, user.id].sorted(),
                "typingStates": [
                    currentUser.id: isTyping,
                    user.id: false
                ],
                "typingUpdatedAt": [
                    currentUser.id: Timestamp(date: .now),
                    user.id: Timestamp(date: .now)
                ],
                "updatedAt": Timestamp(date: .now)
            ], merge: true)
        }
    }

    func sendMessage(_ text: String, attachment: ChatDraftAttachment?, to user: AppUser, from currentUser: AppUser) async throws {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty || attachment != nil else { return }

        let conversationID = ChatConversation.id(for: currentUser.id, and: user.id)
        await encryptionService.ensureCurrentUserPublicKeyIsPublished(userID: currentUser.id)
        let conversationRef = db.collection("conversations").document(conversationID)
        let messageRef = conversationRef.collection("messages").document()
        let sentAt = Timestamp(date: .now)
        let uploadedAttachment = try await uploadAttachmentIfNeeded(
            attachment,
            conversationID: conversationID,
            messageID: messageRef.documentID
        )
        let previewText = conversationPreviewText(text: trimmedText, attachment: uploadedAttachment)
        let participantPublicKey = try await resolveEncryptionPublicKey(for: user)
        let encryptedTextPayload: EncryptedChatTextPayload? = if !trimmedText.isEmpty {
            try encryptionService.encryptText(
                trimmedText,
                with: participantPublicKey,
                conversationID: conversationID
            )
        } else {
            nil
        }

        let batch = db.batch()
        batch.setData([
            "id": conversationID,
            "participantIDs": [currentUser.id, user.id].sorted(),
            "updatedAt": sentAt,
            "lastMessageText": previewText,
            "lastMessageSenderID": currentUser.id,
            "typingStates.\(currentUser.id)": false,
            "unreadCounts.\(currentUser.id)": 0,
            "unreadCounts.\(user.id)": FieldValue.increment(Int64(1))
        ], forDocument: conversationRef, merge: true)
        var messagePayload: [String: Any] = [
            "senderID": currentUser.id,
            "recipientID": user.id,
            "text": encryptedTextPayload?.ciphertextBase64 ?? "",
            "sentAt": sentAt,
            "isReadByRecipient": false
        ]
        if let encryptedTextPayload {
            messagePayload["textEncryptionVersion"] = encryptedTextPayload.encryptionVersion
        }
        if let uploadedAttachment {
            var attachmentPayload: [String: Any] = [
                "kind": uploadedAttachment.kind.rawValue,
                "fileName": uploadedAttachment.fileName,
                "storagePath": uploadedAttachment.storagePath,
                "downloadURL": uploadedAttachment.downloadURL
            ]
            if let contentType = uploadedAttachment.contentType {
                attachmentPayload["contentType"] = contentType
            }
            if let fileSize = uploadedAttachment.fileSize {
                attachmentPayload["fileSize"] = fileSize
            }
            messagePayload["attachment"] = attachmentPayload
        }
        batch.setData(messagePayload, forDocument: messageRef)
        do {
            try await batch.commit()
            let cachedRecord = StoredChatMessageRecord(
                id: messageRef.documentID,
                conversationID: conversationID,
                senderID: currentUser.id,
                recipientID: user.id,
                text: encryptedTextPayload?.ciphertextBase64 ?? "",
                textEncryptionVersion: encryptedTextPayload?.encryptionVersion,
                attachment: uploadedAttachment,
                sentAt: sentAt.dateValue(),
                isReadByRecipient: false
            )
            await cache.append(cachedRecord, for: conversationID)
        } catch {
            logger.error("Failed to send chat message: \(error.localizedDescription)")
            throw error
        }
    }

    private func conversationPreviewText(text: String, attachment: ChatAttachment?) -> String {
        if !text.isEmpty {
            return "Новое сообщение"
        }
        guard let attachment else {
            return ""
        }
        switch attachment.kind {
        case .image:
            return "Фото"
        case .file:
            return "Файл"
        }
    }

    private func resolveEncryptionPublicKey(for user: AppUser) async throws -> String {
        if let publicKey = user.chatEncryptionPublicKey,
           !publicKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return publicKey
        }

        let document = try await db.collection("users").document(user.id).getDocument()
        guard let publicKey = document.data()?["chatEncryptionPublicKey"] as? String,
              !publicKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ChatEncryptionError.missingRecipientPublicKey
        }

        return publicKey
    }

    private func makeChatMessages(
        from records: [StoredChatMessageRecord],
        participant: AppUser,
        currentUser: AppUser,
        conversationID: String
    ) async -> [ChatMessage] {
        let participantPublicKey = try? await resolveEncryptionPublicKey(for: participant)

        return records.map { record in
            let resolvedText: String
            if let version = record.textEncryptionVersion, version > 0 {
                guard let participantPublicKey else {
                    resolvedText = "Сообщение недоступно"
                    return ChatMessage(
                        id: record.id,
                        conversationID: record.conversationID,
                        senderID: record.senderID,
                        recipientID: record.recipientID,
                        text: resolvedText,
                        attachment: record.attachment,
                        sentAt: record.sentAt,
                        isReadByRecipient: record.isReadByRecipient
                    )
                }

                resolvedText = (try? encryptionService.decryptText(
                    record.text,
                    with: participantPublicKey,
                    conversationID: conversationID
                )) ?? "Сообщение недоступно"
            } else {
                resolvedText = record.text
            }

            return ChatMessage(
                id: record.id,
                conversationID: record.conversationID,
                senderID: record.senderID,
                recipientID: record.recipientID,
                text: resolvedText,
                attachment: record.attachment,
                sentAt: record.sentAt,
                isReadByRecipient: record.isReadByRecipient
            )
        }
    }

    private func uploadAttachmentIfNeeded(
        _ attachment: ChatDraftAttachment?,
        conversationID: String,
        messageID: String
    ) async throws -> ChatAttachment? {
        guard let attachment else { return nil }
#if canImport(FirebaseStorage)
        let normalizedPayload = await normalizedAttachmentPayload(for: attachment)
        let sanitizedFileName = sanitizedAttachmentFileName(normalizedPayload.fileName)
        let storagePath = "chatAttachments/\(conversationID)/\(messageID)/\(sanitizedFileName)"
        let storageRef = Storage.storage().reference().child(storagePath)
        let metadata = StorageMetadata()
        metadata.contentType = normalizedPayload.contentType

        _ = try await storageRef.putDataAsync(normalizedPayload.data, metadata: metadata)
        let downloadURL = try await storageRef.downloadURL()

        return ChatAttachment(
            kind: normalizedPayload.kind,
            fileName: normalizedPayload.fileName,
            storagePath: storagePath,
            downloadURL: downloadURL.absoluteString,
            contentType: normalizedPayload.contentType,
            fileSize: normalizedPayload.data.count
        )
#else
        throw NSError(domain: "FirebaseStorageUnavailable", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Firebase Storage не подключен для отправки вложений."
        ])
#endif
    }

    private func sanitizedAttachmentFileName(_ fileName: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let parts = fileName.components(separatedBy: invalidCharacters)
        let sanitized = parts.joined(separator: "_")
        return sanitized.isEmpty ? UUID().uuidString : sanitized
    }

    private func normalizedAttachmentPayload(for attachment: ChatDraftAttachment) async -> ChatDraftAttachment {
        guard attachment.kind == .image else {
            return attachment
        }

        let data = attachment.data
        guard let normalizedData = await Task.detached(priority: .userInitiated, operation: {
            Self.normalizedImageData(from: data)
        }).value else {
            return attachment
        }

        let normalizedName: String
        if attachment.fileName.lowercased().hasSuffix(".jpg") || attachment.fileName.lowercased().hasSuffix(".jpeg") {
            normalizedName = attachment.fileName
        } else {
            let baseName = attachment.fileName
                .components(separatedBy: ".")
                .dropLast()
                .joined(separator: ".")
            normalizedName = (baseName.isEmpty ? "photo" : baseName) + ".jpg"
        }

        return ChatDraftAttachment(
            kind: .image,
            fileName: normalizedName,
            data: normalizedData,
            contentType: "image/jpeg"
        )
    }

    nonisolated private static func normalizedImageData(from imageData: Data) -> Data? {
        guard let image = UIImage(data: imageData) else {
            return nil
        }

        let maxDimension: CGFloat = 1800
        let largestSide = max(image.size.width, image.size.height)
        let scale = largestSide > maxDimension ? maxDimension / largestSide : 1
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resizedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        var compression: CGFloat = 0.82
        let targetBytes = 8 * 1024 * 1024

        while compression >= 0.45 {
            if let data = resizedImage.jpegData(compressionQuality: compression), data.count <= targetBytes {
                return data
            }
            compression -= 0.12
        }

        return resizedImage.jpegData(compressionQuality: 0.35)
    }
}

private actor PersistentChatMessageCache {
    private var storage: [String: [StoredChatMessageRecord]] = [:]
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

    func records(for conversationID: String) -> [StoredChatMessageRecord] {
        if let cachedMessages = storage[conversationID] {
            return cachedMessages
        }

        guard let fileURL = fileURL(for: conversationID),
              let data = try? Data(contentsOf: fileURL),
              let messages = try? decoder.decode([StoredChatMessageRecord].self, from: data) else {
            return []
        }

        storage[conversationID] = messages
        return messages
    }

    func store(_ messages: [StoredChatMessageRecord], for conversationID: String) {
        storage[conversationID] = messages
        persist(messages, for: conversationID)
    }

    func append(_ message: StoredChatMessageRecord, for conversationID: String) {
        var messages = storage[conversationID] ?? []
        messages.removeAll { $0.id == message.id }
        messages.append(message)
        messages.sort { $0.sentAt < $1.sentAt }
        storage[conversationID] = messages
        persist(messages, for: conversationID)
    }

    private func persist(_ messages: [StoredChatMessageRecord], for conversationID: String) {
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

private struct StoredChatMessageRecord: Codable, Equatable {
    let id: String
    let conversationID: String
    let senderID: String
    let recipientID: String
    let text: String
    let textEncryptionVersion: Int?
    let attachment: ChatAttachment?
    let sentAt: Date
    let isReadByRecipient: Bool
}

private final class ListenerBox: @unchecked Sendable {
    var listener: ListenerRegistration?
}

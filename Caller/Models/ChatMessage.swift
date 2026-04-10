import Foundation

enum ChatAttachmentKind: String, Codable, Equatable, Sendable {
    case image
    case file
}

struct ChatAttachment: Codable, Equatable, Sendable {
    let kind: ChatAttachmentKind
    let fileName: String
    let storagePath: String
    let downloadURL: String
    let contentType: String?
    let fileSize: Int?
}

struct ChatDraftAttachment: Identifiable, Equatable, Sendable {
    let id = UUID()
    let kind: ChatAttachmentKind
    let fileName: String
    let data: Data
    let contentType: String

    var fileSize: Int {
        data.count
    }
}

struct ChatMessage: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let conversationID: String
    let senderID: String
    let recipientID: String
    let text: String
    let attachment: ChatAttachment?
    let sentAt: Date
    let isReadByRecipient: Bool

    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachment == nil
    }

    func isOutgoing(for userID: String) -> Bool {
        senderID == userID
    }

    func isUnreadIncoming(for userID: String) -> Bool {
        recipientID == userID && !isReadByRecipient
    }
}

struct ChatConversationSummary: Identifiable, Equatable, Sendable {
    let id: String
    let participantIDs: [String]
    let lastMessageText: String
    let lastMessageSenderID: String
    let updatedAt: Date
    let unreadCounts: [String: Int]

    func otherParticipantID(for currentUserID: String) -> String? {
        participantIDs.first { $0 != currentUserID }
    }
}

struct UnreadMessageSummary: Identifiable, Equatable, Sendable {
    let id: String
    let senderID: String
    let count: Int
    let latestMessageText: String
    let latestSentAt: Date
}

enum ChatConversation {
    static func id(for firstUserID: String, and secondUserID: String) -> String {
        [firstUserID, secondUserID]
            .sorted()
            .joined(separator: "__")
    }
}

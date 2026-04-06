import Foundation

struct ChatMessage: Identifiable, Codable, Equatable {
    let id: String
    let conversationID: String
    let senderID: String
    let recipientID: String
    let text: String
    let sentAt: Date
    let isReadByRecipient: Bool

    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func isOutgoing(for userID: String) -> Bool {
        senderID == userID
    }

    func isUnreadIncoming(for userID: String) -> Bool {
        recipientID == userID && !isReadByRecipient
    }
}

struct ChatConversationSummary: Identifiable, Equatable {
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

struct UnreadMessageSummary: Identifiable, Equatable {
    let id: String
    let senderID: String
    let count: Int
    let latestMessageText: String
    let latestSentAt: Date
}

struct ChatBanner: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
}

enum ChatConversation {
    static func id(for firstUserID: String, and secondUserID: String) -> String {
        [firstUserID, secondUserID]
            .sorted()
            .joined(separator: "__")
    }
}

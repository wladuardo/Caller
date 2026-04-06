import Foundation

struct OutgoingFriendRequest: Identifiable, Equatable {
    let id: String
    let toUser: AppUser
    let sentAt: Date
}

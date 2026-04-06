import Foundation

struct FriendRequest: Identifiable, Equatable {
    let id: String
    let fromUser: AppUser
    let sentAt: Date
}

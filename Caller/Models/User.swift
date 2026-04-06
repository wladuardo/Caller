import Foundation

struct AppUser: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let displayName: String
    let email: String
    let avatarSystemName: String
    let username: String?

    init(
        id: String,
        displayName: String,
        email: String,
        avatarSystemName: String,
        username: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.email = email
        self.avatarSystemName = avatarSystemName
        self.username = username
    }
}

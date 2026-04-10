import Foundation

struct SharedLocation: Codable, Equatable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double
    let updatedAt: Date
    let horizontalAccuracy: Double?
}

struct AppUser: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let displayName: String
    let email: String
    let avatarSystemName: String
    let avatarURL: String?
    let username: String?
    let mutedNotificationUserIDs: [String]
    let sharedLocation: SharedLocation?

    init(
        id: String,
        displayName: String,
        email: String,
        avatarSystemName: String,
        avatarURL: String? = nil,
        username: String? = nil,
        mutedNotificationUserIDs: [String] = [],
        sharedLocation: SharedLocation? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.email = email
        self.avatarSystemName = avatarSystemName
        self.avatarURL = avatarURL
        self.username = username
        self.mutedNotificationUserIDs = mutedNotificationUserIDs
        self.sharedLocation = sharedLocation
    }
}

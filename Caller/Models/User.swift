import Foundation
import UIKit
import CoreLocation

struct SharedLocation: Codable, Equatable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double
    let updatedAt: Date
    let horizontalAccuracy: Double?
    let speed: Double?
    let batteryLevelPercent: Int?
    
    var locationCoordinate2D: CLLocationCoordinate2D {
        .init(latitude: latitude, longitude: longitude)
    }

    nonisolated init(
        latitude: Double,
        longitude: Double,
        updatedAt: Date,
        horizontalAccuracy: Double?,
        speed: Double? = nil,
        batteryLevelPercent: Int? = nil
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.updatedAt = updatedAt
        self.horizontalAccuracy = horizontalAccuracy
        self.speed = speed
        self.batteryLevelPercent = batteryLevelPercent
    }
}

enum DeviceModelResolver {
    static func currentDeviceModelName() -> String {
        let identifier = currentDeviceIdentifier()
        return iPhoneModelNames[identifier] ?? identifier
    }

    private static func currentDeviceIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        return withUnsafePointer(to: &systemInfo.machine) { pointer in
            pointer.withMemoryRebound(
                to: CChar.self,
                capacity: machineMirror.children.count
            ) { pointer in
                String(cString: pointer)
            }
        }
    }

    private static let iPhoneModelNames: [String: String] = [
        "iPhone10,1": "iPhone 8",
        "iPhone10,4": "iPhone 8",
        "iPhone10,2": "iPhone 8 Plus",
        "iPhone10,5": "iPhone 8 Plus",
        "iPhone10,3": "iPhone X",
        "iPhone10,6": "iPhone X",
        "iPhone11,2": "iPhone XS",
        "iPhone11,4": "iPhone XS Max",
        "iPhone11,6": "iPhone XS Max",
        "iPhone11,8": "iPhone XR",
        "iPhone12,1": "iPhone 11",
        "iPhone12,3": "iPhone 11 Pro",
        "iPhone12,5": "iPhone 11 Pro Max",
        "iPhone12,8": "iPhone SE (2nd generation)",
        "iPhone13,1": "iPhone 12 mini",
        "iPhone13,2": "iPhone 12",
        "iPhone13,3": "iPhone 12 Pro",
        "iPhone13,4": "iPhone 12 Pro Max",
        "iPhone14,4": "iPhone 13 mini",
        "iPhone14,5": "iPhone 13",
        "iPhone14,2": "iPhone 13 Pro",
        "iPhone14,3": "iPhone 13 Pro Max",
        "iPhone14,6": "iPhone SE (3rd generation)",
        "iPhone14,7": "iPhone 14",
        "iPhone14,8": "iPhone 14 Plus",
        "iPhone15,2": "iPhone 14 Pro",
        "iPhone15,3": "iPhone 14 Pro Max",
        "iPhone15,4": "iPhone 15",
        "iPhone15,5": "iPhone 15 Plus",
        "iPhone16,1": "iPhone 15 Pro",
        "iPhone16,2": "iPhone 15 Pro Max",
        "iPhone17,3": "iPhone 16",
        "iPhone17,4": "iPhone 16 Plus",
        "iPhone17,1": "iPhone 16 Pro",
        "iPhone17,2": "iPhone 16 Pro Max",
        "iPhone17,5": "iPhone 16e",
        "i386": "iPhone Simulator",
        "x86_64": "iPhone Simulator",
        "arm64": "iPhone Simulator"
    ]
}

struct AppUser: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let displayName: String
    let email: String
    let avatarSystemName: String
    let avatarURL: String?
    let username: String?
    let mutedNotificationUserIDs: [String]
    let deviceModel: String?
    let sharedLocation: SharedLocation?
    let chatEncryptionPublicKey: String?

    init(
        id: String,
        displayName: String,
        email: String,
        avatarSystemName: String,
        avatarURL: String? = nil,
        username: String? = nil,
        mutedNotificationUserIDs: [String] = [],
        deviceModel: String? = nil,
        sharedLocation: SharedLocation? = nil,
        chatEncryptionPublicKey: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.email = email
        self.avatarSystemName = avatarSystemName
        self.avatarURL = avatarURL
        self.username = username
        self.mutedNotificationUserIDs = mutedNotificationUserIDs
        self.deviceModel = deviceModel
        self.sharedLocation = sharedLocation
        self.chatEncryptionPublicKey = chatEncryptionPublicKey
    }
}

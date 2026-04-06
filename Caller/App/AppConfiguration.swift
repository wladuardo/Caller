import Foundation

struct AppConfiguration {
    let signalingServerURL: URL?
    let hasFirebaseConfiguration: Bool

    init(bundle: Bundle = .main) {
        hasFirebaseConfiguration = bundle.path(forResource: "GoogleService-Info", ofType: "plist") != nil

        if let rawValue = bundle.object(forInfoDictionaryKey: "SignalingServerURL") as? String,
           let url = URL(string: rawValue),
           !rawValue.isEmpty {
            signalingServerURL = url
        } else {
            signalingServerURL = nil
        }
    }
}

import FirebaseCore
import Foundation

enum FirebaseBootstrapper {
    static func configureIfPossible(logger: Logger = Logger(), bundle: Bundle = .main) {
        guard FirebaseApp.app() == nil else { return }

        guard bundle.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            logger.info("Firebase configuration file is missing. Falling back to mock services where needed.")
            return
        }

        FirebaseApp.configure()
        logger.info("Firebase configured successfully.")
    }
}

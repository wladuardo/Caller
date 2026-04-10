import Foundation
import FirebaseCore

final class AppEnvironment {
    let authService: AuthenticationServicing
    let contactService: ContactServicing
    let friendService: FriendServicing
    let chatService: ChatServicing
    let notificationService: NotificationServicing
    let permissionService: PermissionServicing
    let locationService: LocationSharingServicing
    let signalingService: SignalingServicing
    let callService: CallServicing
    let logger: Logger
    let configuration: AppConfiguration

    init(
        configuration: AppConfiguration = AppConfiguration(),
        authService: AuthenticationServicing? = nil,
        contactService: ContactServicing? = nil,
        permissionService: PermissionServicing = PermissionService(),
        signalingService: SignalingServicing? = nil,
        logger: Logger = Logger()
    ) {
        self.configuration = configuration
        self.permissionService = permissionService
        self.logger = logger

        let resolvedAuthService = authService ?? Self.makeAuthService(configuration: configuration, logger: logger)
        let resolvedContactService = contactService ?? Self.makeContactService(
            configuration: configuration,
            authService: resolvedAuthService
        )
        let resolvedFriendService = Self.makeFriendService(
            configuration: configuration,
            authService: resolvedAuthService
        )
        let resolvedChatService = Self.makeChatService(configuration: configuration, logger: logger)
        let resolvedNotificationService = Self.makeNotificationService()
        let resolvedLocationService = Self.makeLocationService(configuration: configuration, logger: logger)
        self.authService = resolvedAuthService
        self.contactService = resolvedContactService
        self.friendService = resolvedFriendService
        self.chatService = resolvedChatService
        self.notificationService = resolvedNotificationService
        self.locationService = resolvedLocationService

        let resolvedSignalingService = signalingService ?? Self.makeSignalingService(
            configuration: configuration,
            logger: logger
        )
        self.signalingService = resolvedSignalingService
        self.callService = WebRTCCallService(
            signalingService: resolvedSignalingService,
            contactService: resolvedContactService,
            permissionService: permissionService,
            logger: logger
        )
    }

    private static func makeSignalingService(
        configuration: AppConfiguration,
        logger: Logger
    ) -> SignalingServicing {
        if configuration.hasFirebaseConfiguration, FirebaseApp.app() != nil {
            logger.info("Using Firebase Firestore signaling service.")
            return FirebaseFirestoreSignalingService()
        } else if let signalingServerURL = configuration.signalingServerURL {
            logger.info("Using live signaling server: \(signalingServerURL.absoluteString)")
            return WebSocketSignalingService(
                client: URLSessionWebSocketClient(url: signalingServerURL)
            )
        } else {
            logger.info("Using mock signaling service. Set SignalingServerURL in Info.plist for live calls.")
            return MockWebSocketSignalingService()
        }
    }

    private static func makeAuthService(
        configuration: AppConfiguration,
        logger: Logger
    ) -> AuthenticationServicing {
        if configuration.hasFirebaseConfiguration, FirebaseApp.app() != nil {
            logger.info("Using Firebase Authentication service.")
            return FirebaseAuthenticationService()
        } else {
            logger.info("Using mock authentication service.")
            return MockAuthenticationService()
        }
    }

    private static func makeContactService(
        configuration: AppConfiguration,
        authService: AuthenticationServicing
    ) -> ContactServicing {
        if configuration.hasFirebaseConfiguration, FirebaseApp.app() != nil {
            return FirebaseSocialGraphService(currentUserProvider: { authService.currentUser })
        } else {
            return MockContactService()
        }
    }

    private static func makeFriendService(
        configuration: AppConfiguration,
        authService: AuthenticationServicing
    ) -> FriendServicing {
        if configuration.hasFirebaseConfiguration, FirebaseApp.app() != nil {
            return FirebaseSocialGraphService(currentUserProvider: { authService.currentUser })
        } else {
            return MockFriendService()
        }
    }

    private static func makeChatService(configuration: AppConfiguration, logger: Logger) -> ChatServicing {
        if configuration.hasFirebaseConfiguration, FirebaseApp.app() != nil {
            return FirebaseChatService(logger: logger)
        } else {
            return MockChatService()
        }
    }

    private static func makeNotificationService() -> NotificationServicing {
        let service = NotificationService.shared
        service.configure()
        return service
    }

    private static func makeLocationService(
        configuration: AppConfiguration,
        logger: Logger
    ) -> LocationSharingServicing {
        if configuration.hasFirebaseConfiguration, FirebaseApp.app() != nil {
            return FirebaseLocationSharingService(logger: logger)
        } else {
            return MockLocationSharingService()
        }
    }
}

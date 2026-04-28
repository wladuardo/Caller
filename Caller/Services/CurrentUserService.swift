import Foundation

protocol CurrentUserServicing {
    var currentUser: AppUser? { get }
}

final class CurrentUserService: CurrentUserServicing {
    private let authService: AuthenticationServicing

    init(authService: AuthenticationServicing) {
        self.authService = authService
    }

    var currentUser: AppUser? {
        authService.currentUser
    }
}

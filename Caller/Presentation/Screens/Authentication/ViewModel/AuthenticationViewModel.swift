import AuthenticationServices
import CryptoKit
import FirebaseCore
import Foundation
import GoogleSignIn
import Observation
import Security
import UIKit

@MainActor
@Observable
final class AuthenticationViewModel: Store {
    struct Dependencies {
        let signInWithGoogle: @MainActor @Sendable (_ idToken: String, _ accessToken: String) async -> Void
        let signInWithApple: @MainActor @Sendable (
            _ idToken: String,
            _ nonce: String,
            _ fullName: PersonNameComponents?
        ) async -> Void
        let showError: @MainActor @Sendable (String) -> Void
    }

    var state = State()

    private let dependencies: Dependencies
    private var currentNonce = ""
    private var appleSignInCoordinator: AppleSignInCoordinator?

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func trigger(_ input: Input) async {
        switch input {
        case .tapGoogleSignIn:
            await signInWithGoogle()
        case .tapAppleSignIn:
            startSignInWithApple()
        }
    }

    private func signInWithGoogle() async {
        guard !state.isLoading else { return }

        guard let clientID = FirebaseApp.app()?.options.clientID else {
            dependencies.showError("Отсутствует Firebase client ID.")
            return
        }

        guard let presentingViewController = topViewController() else {
            dependencies.showError("Не удалось найти контроллер для показа Google Sign-In.")
            return
        }

        update { state in
            state.isLoading = true
        }
        defer {
            update { state in
                state.isLoading = false
            }
        }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController)

            guard let idToken = result.user.idToken?.tokenString else {
                dependencies.showError("Google Sign-In не вернул ID token.")
                return
            }

            let accessToken = result.user.accessToken.tokenString
            await dependencies.signInWithGoogle(idToken, accessToken)
        } catch {
            guard !isUserCancelledAuthorization(error) else { return }
            dependencies.showError(error.localizedDescription)
        }
    }

    private func startSignInWithApple() {
        guard !state.isLoading else { return }

        guard let window = topViewController()?.view.window else {
            dependencies.showError("Не удалось показать Apple Sign-In.")
            return
        }

        let nonce = randomNonceString()
        currentNonce = nonce

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)

        let coordinator = AppleSignInCoordinator(window: window) { [weak self] authorization in
            guard let self else { return }
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let identityToken = credential.identityToken,
                  let tokenString = String(data: identityToken, encoding: .utf8) else {
                dependencies.showError("Apple Sign-In did not return a valid identity token.")
                appleSignInCoordinator = nil
                return
            }

            Task { @MainActor in
                self.update { state in
                    state.isLoading = true
                }
                await self.dependencies.signInWithApple(tokenString, self.currentNonce, credential.fullName)
                self.update { state in
                    state.isLoading = false
                }
                self.appleSignInCoordinator = nil
            }
        } onFailure: { [weak self] error in
            guard let self else { return }
            guard !isUserCancelledAuthorization(error) else {
                appleSignInCoordinator = nil
                return
            }
            dependencies.showError(error.localizedDescription)
            appleSignInCoordinator = nil
        }

        appleSignInCoordinator = coordinator

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = coordinator
        controller.presentationContextProvider = coordinator
        controller.performRequests()
    }

    private func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let rootController = scenes
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController

        var controller = rootController
        while let presentedViewController = controller?.presentedViewController {
            controller = presentedViewController
        }
        return controller
    }

    private func isUserCancelledAuthorization(_ error: Error) -> Bool {
        let nsError = error as NSError

        if nsError.domain == ASAuthorizationError.errorDomain,
           nsError.code == ASAuthorizationError.canceled.rawValue {
            return true
        }

        if let googleError = error as? GIDSignInError,
           googleError.code == .canceled {
            return true
        }

        return false
    }
}

extension AuthenticationViewModel {
    struct State {
        var isLoading = false
    }

    enum Input: Sendable {
        case tapGoogleSignIn
        case tapAppleSignIn
    }
}

private final class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private let window: UIWindow
    private let onSuccess: (ASAuthorization) -> Void
    private let onFailure: (Error) -> Void

    init(
        window: UIWindow,
        onSuccess: @escaping (ASAuthorization) -> Void,
        onFailure: @escaping (Error) -> Void
    ) {
        self.window = window
        self.onSuccess = onSuccess
        self.onFailure = onFailure
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        window
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        onSuccess(authorization)
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        onFailure(error)
    }
}

private func randomNonceString(length: Int = 32) -> String {
    precondition(length > 0)
    let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
    var result = ""
    var remainingLength = length

    while remainingLength > 0 {
        let randoms: [UInt8] = (0..<16).map { _ in
            var random: UInt8 = 0
            let errorCode = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
            if errorCode != errSecSuccess {
                fatalError("Unable to generate nonce. OSStatus \(errorCode)")
            }
            return random
        }

        randoms.forEach { random in
            if remainingLength == 0 {
                return
            }

            if random < charset.count {
                result.append(charset[Int(random)])
                remainingLength -= 1
            }
        }
    }

    return result
}

private func sha256(_ input: String) -> String {
    let inputData = Data(input.utf8)
    let hashedData = SHA256.hash(data: inputData)
    return hashedData.compactMap { String(format: "%02x", $0) }.joined()
}

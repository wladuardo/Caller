import AuthenticationServices
import CryptoKit
import FirebaseCore
import GoogleSignIn
import Security
import SwiftUI
import UIKit

struct AuthenticationView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var currentNonce = ""
    @State private var appleSignInCoordinator: AppleSignInCoordinator?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.06, green: 0.10, blue: 0.16)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    Spacer(minLength: 24)

                    VStack(spacing: 12) {
                        Image(systemName: "video.circle.fill")
                            .font(.system(size: 72))
                            .foregroundStyle(.white, Color.blue)
                        Text("Caller")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                        Text("Безопасные аудио- и видеозвонки, а также сообщения в одном удобном приложении.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 12)

                    VStack(alignment: .leading, spacing: 18) {
                        Text("Продолжить через")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        VStack(spacing: 14) {
                            providerButton(
                                title: "Continue with Google",
                                subtitle: "Use your Google account",
                                systemName: "g.circle.fill",
                                iconBackground: Color(red: 0.20, green: 0.47, blue: 0.96)
                            ) {
                                Task {
                                    await signInWithGoogle()
                                }
                            }
                            .overlay(alignment: .leading) {
                                if viewModel.isLoading {
                                    ProgressView()
                                        .tint(.white)
                                        .padding(.leading, 16)
                                }
                            }

                            appleProviderButton
                        }

                        Text("Авторизация доступна только через Google и Apple.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(20)
                    .frame(maxWidth: 420)
                    .background(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 28, style: .continuous)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )
                    )
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.vertical, 28)
            }
        }
    }
}

extension AuthenticationView {
    private var appleProviderButton: some View {
        providerButton(
            title: "Войти через Apple",
            subtitle: "Использовать Apple ID",
            systemName: "apple.logo",
            iconBackground: Color.white.opacity(0.14)
        ) {
            startSignInWithApple()
        }
    }

    private func providerButton(
        title: String,
        subtitle: String,
        systemName: String,
        iconBackground: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(iconBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .frame(height: 68)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func signInWithGoogle() async {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            viewModel.callError = .general("Отсутствует Firebase client ID.")
            return
        }

        guard let presentingViewController = topViewController() else {
            viewModel.callError = .general("Не удалось найти контроллер для показа Google Sign-In.")
            return
        }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController)

            guard let idToken = result.user.idToken?.tokenString else {
                viewModel.callError = .general("Google Sign-In не вернул ID token.")
                return
            }

            let accessToken = result.user.accessToken.tokenString
            await viewModel.signInWithGoogle(idToken: idToken, accessToken: accessToken)
        } catch {
            viewModel.callError = .general(error.localizedDescription)
        }
    }

    @MainActor
    private func startSignInWithApple() {
        guard let window = topViewController()?.view.window else {
            viewModel.callError = .general("Не удалось показать Apple Sign-In.")
            return
        }

        let nonce = randomNonceString()
        currentNonce = nonce

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)

        let coordinator = AppleSignInCoordinator(window: window) { authorization in
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let identityToken = credential.identityToken,
                  let tokenString = String(data: identityToken, encoding: .utf8) else {
                self.viewModel.callError = .general("Apple Sign-In did not return a valid identity token.")
                self.appleSignInCoordinator = nil
                return
            }

            Task {
                await self.viewModel.signInWithApple(
                    idToken: tokenString,
                    nonce: self.currentNonce,
                    fullName: credential.fullName
                )
                self.appleSignInCoordinator = nil
            }
        } onFailure: { error in
            self.viewModel.callError = .general(error.localizedDescription)
            self.appleSignInCoordinator = nil
        }

        appleSignInCoordinator = coordinator

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = coordinator
        controller.presentationContextProvider = coordinator
        controller.performRequests()
    }

    @MainActor
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

import SwiftUI

struct AuthenticationView: View {
    @ObservedObject private var appViewModel: AppViewModel
    @State private var viewModel: AuthenticationViewModel

    init(viewModel: AppViewModel) {
        _appViewModel = ObservedObject(wrappedValue: viewModel)
        _viewModel = State(
            initialValue: AuthenticationViewModel(
                dependencies: .init(
                    signInWithGoogle: { idToken, accessToken in
                        await viewModel.signInWithGoogle(idToken: idToken, accessToken: accessToken)
                    },
                    signInWithApple: { idToken, nonce, fullName in
                        await viewModel.signInWithApple(idToken: idToken, nonce: nonce, fullName: fullName)
                    },
                    showError: { message in
                        viewModel.callError = .general(message)
                    }
                )
            )
        )
    }

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
                                send(.tapGoogleSignIn)
                            }
                            .overlay(alignment: .leading) {
                                if viewModel.state.isLoading || appViewModel.isLoading {
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
                    .callerGlassCard(cornerRadius: 28, tint: .blue)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.vertical, 28)
            }

            if isAuthenticationLoading {
                authenticationLoadingOverlay
            }
        }
        .animation(.easeInOut(duration: 0.18), value: isAuthenticationLoading)
    }
}

extension AuthenticationView {
    private var isAuthenticationLoading: Bool {
        viewModel.state.isLoading || appViewModel.isLoading
    }

    private var authenticationLoadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.46)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)

                Text("Выполняем вход")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)

                Text("Пожалуйста, подождите")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.72))
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.28), radius: 28, y: 16)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
        .zIndex(10)
    }

    private var appleProviderButton: some View {
        providerButton(
            title: "Войти через Apple",
            subtitle: "Использовать Apple ID",
            systemName: "apple.logo",
            iconBackground: Color.white.opacity(0.14)
        ) {
            send(.tapAppleSignIn)
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
            .callerGlassCard(cornerRadius: 20, tint: iconBackground)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.state.isLoading || appViewModel.isLoading)
    }

    private func send(_ input: AuthenticationViewModel.Input) {
        Task {
            await viewModel.trigger(input)
        }
    }
}

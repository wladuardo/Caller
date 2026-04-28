import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = AppViewModel(environment: AppEnvironment())
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        ZStack {
            Group {
                if !hasCompletedOnboarding {
                    OnboardingView {
                        hasCompletedOnboarding = true
                    }
                } else if viewModel.currentUser == nil {
                    AuthenticationView(viewModel: viewModel)
                } else if viewModel.isRestoringSession {
                    launchLoadingView
                } else if viewModel.requiresUsernameSetup {
                    UsernameSetupView(viewModel: viewModel)
                } else {
                    MainTabView(viewModel: viewModel)
                }
            }
            .preferredColorScheme(.dark)

            if let incomingCall = viewModel.incomingCall {
                IncomingCallView(
                    call: incomingCall,
                    onAccept: { Task { await viewModel.acceptIncomingCall() } },
                    onDecline: { Task { await viewModel.declineIncomingCall() } }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(1)
            }

            if let activeCall = viewModel.activeCall {
                ActiveCallView(
                    call: activeCall,
                    localVideoTrack: viewModel.localVideoTrack,
                    remoteVideoTrack: viewModel.remoteVideoTrack,
                    onEnd: { Task { await viewModel.endCall() } },
                    onToggleMute: viewModel.toggleMute,
                    onToggleSpeaker: viewModel.toggleSpeaker,
                    onToggleCamera: viewModel.toggleCamera,
                    onSwitchCamera: viewModel.switchCamera
                )
                .transition(.opacity)
                .zIndex(2)
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.88), value: viewModel.incomingCall != nil)
        .animation(.spring(response: 0.38, dampingFraction: 0.88), value: viewModel.activeCall != nil)
        .alert("Caller", isPresented: Binding(
            get: { viewModel.callError != nil },
            set: { if !$0 { viewModel.dismissError() } }
        )) {
            Button("ОК", role: .cancel) {
                viewModel.dismissError()
            }
        } message: {
            Text(viewModel.callError?.localizedDescription ?? "Что-то пошло не так.")
        }
        .onOpenURL { url in
            Task {
                await viewModel.handleIncomingURL(url)
            }
        }
    }

    private var launchLoadingView: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.black,
                    Color(red: 0.05, green: 0.09, blue: 0.16),
                    Color(red: 0.02, green: 0.16, blue: 0.24)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color.cyan.opacity(0.18))
                .frame(width: 220, height: 220)
                .blur(radius: 24)
                .offset(x: 110, y: -220)

            Circle()
                .fill(Color.blue.opacity(0.16))
                .frame(width: 260, height: 260)
                .blur(radius: 28)
                .offset(x: -120, y: 260)

            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.cyan.opacity(0.95), Color.blue.opacity(0.9)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 84, height: 84)

                    Image(systemName: "phone.connection.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .shadow(color: .cyan.opacity(0.22), radius: 24, y: 14)

                VStack(spacing: 8) {
                    Text("Caller")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Подготавливаем профиль и подключаем сервисы")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 12) {
                    ProgressView()
                        .tint(.white)

                    Text("Загрузка")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .callerGlassCard(cornerRadius: 22, tint: .cyan)
            }
            .padding(.horizontal, 28)
        }
    }
}

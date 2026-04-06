import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = AppViewModel(environment: AppEnvironment())

    var body: some View {
        ZStack {
            Group {
                if viewModel.currentUser == nil {
                    AuthenticationView(viewModel: viewModel)
                } else if viewModel.isRestoringSession {
                    ProgressView()
                        .tint(.white)
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
    }
}

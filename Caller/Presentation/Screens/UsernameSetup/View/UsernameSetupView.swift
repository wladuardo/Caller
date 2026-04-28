import SwiftUI

struct UsernameSetupView: View {
    @ObservedObject private var appViewModel: AppViewModel
    @State private var viewModel: UsernameSetupViewModel
    @FocusState private var isUsernameFocused: Bool

    init(viewModel: AppViewModel) {
        _appViewModel = ObservedObject(wrappedValue: viewModel)
        _viewModel = State(
            initialValue: UsernameSetupViewModel(
                dependencies: .init(
                    saveUsername: { username in
                        await viewModel.saveUsername(username)
                    }
                )
            )
        )
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.08, green: 0.09, blue: 0.14)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 24) {
                Spacer()

                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Придумайте никнейм")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                        Text("По этому никнейму вас смогут найти другие пользователи. Используйте английские буквы и цифры.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        TextField(
                            "Например, alex",
                            text: Binding(
                                get: { viewModel.state.username },
                                set: { username in
                                    send(.setUsername(username))
                                }
                            )
                        )
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($isUsernameFocused)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 15)
                            .callerGlassCard(cornerRadius: 18, tint: .blue)

                        Text(
                            viewModel.state.validationMessage ??
                            "Никнейм должен быть уникальным и состоять только из латинских букв и цифр."
                        )
                            .font(.footnote)
                            .foregroundStyle(viewModel.state.validationMessage == nil ? Color.secondary : Color.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        send(.tapSubmit)
                    } label: {
                        HStack {
                            Spacer()
                            if viewModel.state.isSubmitting {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Продолжить")
                                    .font(.headline)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 16)
                        .callerGlassButtonSurface(cornerRadius: 18, tint: .blue)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.state.isSubmitting)
                    .opacity(viewModel.state.isSubmitting ? 0.7 : 1)
                }
                .padding(24)
                .callerGlassCard(cornerRadius: 28, tint: .blue)

                Spacer()
            }
            .padding(24)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            isUsernameFocused = true
        }
    }

    private func send(_ input: UsernameSetupViewModel.Input) {
        Task {
            await viewModel.trigger(input)
        }
    }
}

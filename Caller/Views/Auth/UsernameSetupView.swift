import SwiftUI

struct UsernameSetupView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var username = ""
    @State private var validationMessage: String?
    @State private var isSubmitting = false
    @FocusState private var isUsernameFocused: Bool

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

                VStack(alignment: .leading, spacing: 12) {
                    Text("Придумайте никнейм")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text("По этому никнейму вас смогут найти другие пользователи. Используйте только английские буквы.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    TextField("Например, alex", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($isUsernameFocused)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 15)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                )
                        )

                    Text(validationMessage ?? "Никнейм должен быть уникальным и состоять только из букв A-Z.")
                        .font(.footnote)
                        .foregroundStyle(validationMessage == nil ? Color.secondary : Color.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    submit()
                } label: {
                    HStack {
                        Spacer()
                        if isSubmitting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Продолжить")
                                .font(.headline)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 16)
                    .background(Color.blue, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isSubmitting)
                .opacity(isSubmitting ? 0.7 : 1)

                Spacer()
            }
            .padding(24)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            isUsernameFocused = true
        }
    }

    private func submit() {
        let normalizedUsername = UsernameValidator.normalized(username)

        if let error = UsernameValidator.validate(normalizedUsername) {
            validationMessage = error
            return
        }

        validationMessage = nil
        isSubmitting = true

        Task {
            let didSave = await viewModel.saveUsername(normalizedUsername)
            await MainActor.run {
                isSubmitting = false
                if !didSave {
                    validationMessage = viewModel.callError?.localizedDescription ?? "Не удалось сохранить никнейм."
                }
            }
        }
    }
}

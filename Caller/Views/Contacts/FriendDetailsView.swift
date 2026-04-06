import SwiftUI

struct FriendDetailsView: View {
    let user: AppUser
    let unreadMessageCount: Int
    let onOpenChat: () -> Void
    let onStartAudioCall: () -> Void
    let onStartVideoCall: () -> Void
    let onRemoveFriend: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isShowingRemoveConfirmation = false
    @State private var isRemoving = false
    @State private var hasAnimatedIn = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.08, green: 0.09, blue: 0.14)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    profileCard
                        .offset(y: hasAnimatedIn ? 0 : 18)
                        .opacity(hasAnimatedIn ? 1 : 0)
                    actionsCard
                        .offset(y: hasAnimatedIn ? 0 : 28)
                        .opacity(hasAnimatedIn ? 1 : 0)
                    destructiveCard
                        .offset(y: hasAnimatedIn ? 0 : 36)
                        .opacity(hasAnimatedIn ? 1 : 0)
                }
                .padding(20)
            }
        }
        .navigationTitle("Профиль")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.84)) {
                hasAnimatedIn = true
            }
        }
    }

    private var profileCard: some View {
        HStack(spacing: 16) {
            Image(systemName: user.avatarSystemName)
                .font(.system(size: 44))
                .foregroundStyle(.white, .blue)
                .frame(width: 76, height: 76)
                .background(Color.white.opacity(0.08), in: Circle())

            VStack(alignment: .leading, spacing: 6) {
                Text(user.displayName)
                    .font(.title3.weight(.semibold))
                if let username = user.username, !username.isEmpty {
                    Text("@\(username)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.blue)
                }
                Text(user.email)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if unreadMessageCount > 0 {
                    Text("\(unreadMessageCount) непрочитанных сообщений")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.indigo)
                }
            }

            Spacer()
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var actionsCard: some View {
        VStack(spacing: 12) {
            DetailsActionButton(
                title: "Открыть чат",
                subtitle: "Перейти к переписке с этим пользователем.",
                systemName: "message.fill",
                tint: .indigo,
                action: onOpenChat
            )

            DetailsActionButton(
                title: "Аудиозвонок",
                subtitle: "Позвонить без видео.",
                systemName: "phone.fill",
                tint: .green,
                action: onStartAudioCall
            )

            DetailsActionButton(
                title: "Видеозвонок",
                subtitle: "Начать звонок с видео.",
                systemName: "video.fill",
                tint: .blue,
                action: onStartVideoCall
            )
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var destructiveCard: some View {
        Button {
            isShowingRemoveConfirmation = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "person.crop.circle.badge.minus")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(Color.red.opacity(0.9), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Удалить из друзей")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("После удаления потребуется новый запрос в друзья.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isRemoving {
                    ProgressView()
                        .tint(.white)
                }
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.red.opacity(0.14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.red.opacity(0.28), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isRemoving)
        .scaleEffect(isRemoving ? 0.98 : 1)
        .animation(.spring(response: 0.24, dampingFraction: 0.8), value: isRemoving)
        .confirmationDialog("Удалить друга?", isPresented: $isShowingRemoveConfirmation, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                removeFriend()
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Вы удалите \(user.displayName) из друзей.")
        }
    }

    private func removeFriend() {
        isRemoving = true
        Task {
            await onRemoveFriend()
            await MainActor.run {
                isRemoving = false
                dismiss()
            }
        }
    }
}

private struct DetailsActionButton: View {
    let title: String
    let subtitle: String
    let systemName: String
    let tint: Color
    let action: () -> Void
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemName)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(tint.opacity(0.9), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()
            }
            .padding(14)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.985 : 1)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed { isPressed = true }
                }
                .onEnded { _ in
                    isPressed = false
                }
        )
        .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isPressed)
    }
}

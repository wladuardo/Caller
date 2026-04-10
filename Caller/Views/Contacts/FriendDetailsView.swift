import SwiftUI

struct FriendDetailsView: View {
    let user: AppUser
    let unreadMessageCount: Int
    let isNotificationsMuted: Bool
    let onOpenChat: () -> Void
    let onStartAudioCall: () -> Void
    let onStartVideoCall: () -> Void
    let onSetNotificationsMuted: (Bool) async -> Void
    let onRemoveFriend: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isShowingRemoveConfirmation = false
    @State private var isRemoving = false
    @State private var isUpdatingNotifications = false
    @State private var notificationsMuted = false

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
                    actionsCard
                    destructiveCard
                }
                .padding(20)
            }
        }
        .navigationTitle("Профиль")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            notificationsMuted = isNotificationsMuted
        }
    }

    private var profileCard: some View {
        HStack(spacing: 16) {
            UserAvatarView(
                user: user,
                size: 76,
                iconSize: 44,
                iconTint: .white
            )

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
        .callerGlassCard(cornerRadius: 24, tint: .cyan)
    }

    private var actionsCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                compactActionButton(
                    title: "Чат",
                    systemName: "message.fill",
                    tint: .indigo,
                    action: onOpenChat
                )
                compactActionButton(
                    title: "Звонок",
                    systemName: "phone.fill",
                    tint: .green,
                    action: onStartAudioCall
                )
                compactActionButton(
                    title: "Видео",
                    systemName: "video.fill",
                    tint: .blue,
                    action: onStartVideoCall
                )
                compactActionButton(
                    title: notificationsMuted ? "Звук выкл" : "Звук",
                    systemName: notificationsMuted ? "bell.slash.fill" : "bell.fill",
                    tint: notificationsMuted ? .orange : .teal,
                    isLoading: isUpdatingNotifications,
                    action: {
                        updateNotificationsMuted(!notificationsMuted)
                    }
                )
            }

            Text(
                notificationsMuted
                    ? "Уведомления от этого пользователя отключены."
                    : "Уведомления о сообщениях и звонках от этого пользователя включены."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .callerGlassCard(cornerRadius: 24, tint: .indigo)
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
            .callerGlassCard(cornerRadius: 24, tint: .red)
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

    private func updateNotificationsMuted(_ isMuted: Bool) {
        guard !isUpdatingNotifications else { return }

        isUpdatingNotifications = true
        notificationsMuted = isMuted

        Task {
            await onSetNotificationsMuted(isMuted)
            await MainActor.run {
                isUpdatingNotifications = false
                notificationsMuted = isMuted
            }
        }
    }

    private func compactActionButton(
        title: String,
        systemName: String,
        tint: Color,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.06))

                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: systemName)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(tint)
                    }
                }
                .frame(height: 64)

                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(tint)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}

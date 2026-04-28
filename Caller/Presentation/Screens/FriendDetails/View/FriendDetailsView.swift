import SwiftUI

struct FriendDetailsView: View {
    let user: AppUser
    let unreadMessageCount: Int
    let isNotificationsMuted: Bool
    let onOpenChat: @MainActor @Sendable () -> Void
    let onStartAudioCall: @MainActor @Sendable () -> Void
    let onStartVideoCall: @MainActor @Sendable () -> Void
    let onShowOnMap: @MainActor @Sendable () -> Void
    let onSetNotificationsMuted: @MainActor @Sendable (Bool) async -> Void
    let onRemoveFriend: @MainActor @Sendable () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: FriendDetailsViewModel

    init(
        user: AppUser,
        unreadMessageCount: Int,
        isNotificationsMuted: Bool,
        onOpenChat: @escaping @MainActor @Sendable () -> Void,
        onStartAudioCall: @escaping @MainActor @Sendable () -> Void,
        onStartVideoCall: @escaping @MainActor @Sendable () -> Void,
        onShowOnMap: @escaping @MainActor @Sendable () -> Void,
        onSetNotificationsMuted: @escaping @MainActor @Sendable (Bool) async -> Void,
        onRemoveFriend: @escaping @MainActor @Sendable () async -> Void
    ) {
        self.user = user
        self.unreadMessageCount = unreadMessageCount
        self.isNotificationsMuted = isNotificationsMuted
        self.onOpenChat = onOpenChat
        self.onStartAudioCall = onStartAudioCall
        self.onStartVideoCall = onStartVideoCall
        self.onShowOnMap = onShowOnMap
        self.onSetNotificationsMuted = onSetNotificationsMuted
        self.onRemoveFriend = onRemoveFriend
        _viewModel = State(
            initialValue: FriendDetailsViewModel(
                user: user,
                unreadMessageCount: unreadMessageCount,
                isNotificationsMuted: isNotificationsMuted,
                dependencies: .init(
                    onOpenChat: onOpenChat,
                    onStartAudioCall: onStartAudioCall,
                    onStartVideoCall: onStartVideoCall,
                    onShowOnMap: onShowOnMap,
                    onSetNotificationsMuted: onSetNotificationsMuted,
                    onRemoveFriend: onRemoveFriend,
                    onDismiss: {}
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

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    profileCard
                    if viewModel.hasDeviceTelemetry {
                        deviceInfoCard
                    }
                    actionsCard
                    destructiveCard
                }
                .padding(20)
            }
        }
        .navigationTitle("Профиль")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            viewModel = FriendDetailsViewModel(
                user: user,
                unreadMessageCount: unreadMessageCount,
                isNotificationsMuted: isNotificationsMuted,
                dependencies: .init(
                    onOpenChat: { @MainActor @Sendable in onOpenChat() },
                    onStartAudioCall: { @MainActor @Sendable in onStartAudioCall() },
                    onStartVideoCall: { @MainActor @Sendable in onStartVideoCall() },
                    onShowOnMap: { @MainActor @Sendable in onShowOnMap() },
                    onSetNotificationsMuted: { @MainActor @Sendable isMuted in
                        await onSetNotificationsMuted(isMuted)
                    },
                    onRemoveFriend: { @MainActor @Sendable in await onRemoveFriend() },
                    onDismiss: { dismiss() }
                )
            )
        }
    }

    private var profileCard: some View {
        HStack(spacing: 16) {
            UserAvatarView(
                user: viewModel.state.user,
                size: 76,
                iconSize: 44,
                iconTint: .white
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(viewModel.state.user.displayName)
                    .font(.title3.weight(.semibold))
                if let username = viewModel.state.user.username, !username.isEmpty {
                    Text("@\(username)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.blue)
                }
                Text(viewModel.state.user.email)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if viewModel.state.unreadMessageCount > 0 {
                    Text("\(viewModel.state.unreadMessageCount) непрочитанных сообщений")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.indigo)
                }
            }

            Spacer()
        }
        .padding(18)
        .callerGlassCard(cornerRadius: 24, tint: .cyan)
    }

    private var deviceInfoCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Устройство")
                .font(.headline.weight(.semibold))

            if let deviceModel = viewModel.deviceModelText {
                deviceInfoRow(title: "Модель", value: deviceModel, systemName: "iphone")
            }

            if let batteryLevel = viewModel.batteryLevelText {
                deviceInfoRow(title: "Батарея", value: batteryLevel, systemName: "battery.75percent")
            }
        }
        .padding(18)
        .callerGlassCard(cornerRadius: 24, tint: .green)
    }

    private func deviceInfoRow(title: String, value: String, systemName: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemName)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.green)
                .frame(width: 36, height: 36)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }

            Spacer()
        }
    }

    private var actionsCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                compactActionButton(
                    title: "Чат",
                    systemName: "message.fill",
                    tint: .indigo,
                    action: { send(.tapOpenChat) }
                )
                compactActionButton(
                    title: "Звонок",
                    systemName: "phone.fill",
                    tint: .green,
                    action: { send(.tapStartAudioCall) }
                )
                compactActionButton(
                    title: "Видео",
                    systemName: "video.fill",
                    tint: .blue,
                    action: { send(.tapStartVideoCall) }
                )
                compactActionButton(
                    title: viewModel.state.notificationsMuted ? "Звук выкл" : "Звук",
                    systemName: viewModel.state.notificationsMuted ? "bell.slash.fill" : "bell.fill",
                    tint: viewModel.state.notificationsMuted ? .orange : .teal,
                    isLoading: viewModel.state.isUpdatingNotifications,
                    action: { send(.tapToggleNotifications) }
                )
            }

            HStack(spacing: 12) {
                compactActionButton(
                    title: "На карте",
                    systemName: "location.fill",
                    tint: .cyan,
                    action: { send(.tapShowOnMap) }
                )

                Spacer(minLength: 0)
            }

            Text(
                viewModel.state.notificationsMuted
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
            send(.setRemoveConfirmationPresented(true))
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

                if viewModel.state.isRemoving {
                    ProgressView()
                        .tint(.white)
                }
            }
            .padding(18)
            .callerGlassCard(cornerRadius: 24, tint: .red)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.state.isRemoving)
        .scaleEffect(viewModel.state.isRemoving ? 0.98 : 1)
        .animation(.spring(response: 0.24, dampingFraction: 0.8), value: viewModel.state.isRemoving)
        .confirmationDialog(
            "Удалить друга?",
            isPresented: Binding(
                get: { viewModel.state.isShowingRemoveConfirmation },
                set: { isPresented in
                    send(.setRemoveConfirmationPresented(isPresented))
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) {
                send(.tapConfirmRemoveFriend)
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Вы удалите \(viewModel.state.user.displayName) из друзей.")
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

    private func send(_ input: FriendDetailsViewModel.Input) {
        Task {
            await viewModel.trigger(input)
        }
    }
}

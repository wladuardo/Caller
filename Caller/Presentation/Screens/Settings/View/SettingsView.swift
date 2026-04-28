import PhotosUI
import SwiftUI

struct SettingsView: View {
    let currentUser: AppUser
    let onUpdateAvatar: @Sendable (Data) async -> Void
    let onSignOut: @Sendable () -> Void
    let onDeleteAccount: @Sendable () -> Void

    @State private var viewModel: SettingsViewModel
    @State private var selectedPhoto: PhotosPickerItem?

    init(
        currentUser: AppUser,
        onUpdateAvatar: @escaping @Sendable (Data) async -> Void,
        onSignOut: @escaping @Sendable () -> Void,
        onDeleteAccount: @escaping @Sendable () -> Void
    ) {
        self.currentUser = currentUser
        self.onUpdateAvatar = onUpdateAvatar
        self.onSignOut = onSignOut
        self.onDeleteAccount = onDeleteAccount
        _viewModel = State(
            initialValue: SettingsViewModel(
                currentUser: currentUser,
                dependencies: .init(
                    onUpdateAvatar: onUpdateAvatar,
                    onSignOut: onSignOut,
                    onDeleteAccount: onDeleteAccount
                )
            )
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color.black, Color(red: 0.08, green: 0.09, blue: 0.14)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        profileCard
                        actionsCard
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Профиль")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onFirstAppear {
            send(.setCurrentUser(currentUser))
        }
        .onChange(of: currentUser) { _, user in
            send(.setCurrentUser(user))
        }
        .onChange(of: selectedPhoto) { _, newValue in
            guard let newValue else { return }
            Task {
                guard let data = try? await newValue.loadTransferable(type: Data.self) else {
                    await MainActor.run {
                        selectedPhoto = nil
                    }
                    return
                }
                await viewModel.trigger(.pickedAvatarData(data))
                await MainActor.run {
                    selectedPhoto = nil
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Профиль")
                .font(.system(size: 34, weight: .bold, design: .rounded))
            Text("Управляйте профилем и текущей сессией в одном месте.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var profileCard: some View {
        HStack(spacing: 16) {
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                ZStack(alignment: .bottomTrailing) {
                    UserAvatarView(
                        user: viewModel.state.currentUser,
                        size: 72,
                        iconSize: 42,
                        iconTint: .white
                    )

                    Circle()
                        .fill(Color.blue)
                        .frame(width: 24, height: 24)
                        .overlay {
                            if viewModel.state.isUploadingAvatar {
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .tint(.white)
                            } else {
                                Image(systemName: "camera.fill")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.white)
                            }
                        }
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 6) {
                Text(viewModel.state.currentUser.displayName)
                    .font(.title3.weight(.semibold))
                Text(viewModel.state.currentUser.email)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let username = viewModel.state.currentUser.username, !username.isEmpty {
                    Text("Никнейм: @\(username)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.blue)
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
                if viewModel.state.currentUser.username?.isEmpty == false {
                    ShareLink(item: shareInviteMessage, subject: Text("Приглашение в Caller")) {
                        compactActionButton(
                            title: "Поделиться",
                            systemName: "square.and.arrow.up",
                            tint: .cyan
                        )
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                }

                compactActionButton(
                    title: "Выйти",
                    systemName: "rectangle.portrait.and.arrow.right",
                    tint: .blue,
                    action: {
                        send(.tapSignOut)
                    }
                )

                compactActionButton(
                    title: "Удалить аккаунт",
                    systemName: "trash.fill",
                    tint: .red,
                    action: {
                        send(.tapDeleteAccount)
                    }
                )
            }
        }
        .padding(18)
        .callerGlassCard(cornerRadius: 24, tint: .blue)
    }

    private var shareDeepLink: String {
        let username = viewModel.state.currentUser.username ?? ""
        return "caller://invite?username=\(username)"
    }

    private var shareInviteMessage: String {
        "Открой эту ссылку в Caller, чтобы сразу отправить мне запрос в друзья:\n\(shareDeepLink)"
    }

    private func compactActionButton(
        title: String,
        systemName: String,
        tint: Color,
        action: (() -> Void)? = nil
    ) -> some View {
        Group {
            if let action {
                Button(action: action) {
                    compactActionContent(
                        title: title,
                        systemName: systemName,
                        tint: tint
                    )
                }
                .buttonStyle(.plain)
            } else {
                compactActionContent(
                    title: title,
                    systemName: systemName,
                    tint: tint
                )
            }
        }
    }

    private func compactActionContent(
        title: String,
        systemName: String,
        tint: Color
    ) -> some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.06))

                Image(systemName: systemName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
            }
            .frame(height: 64)

            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(tint)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private func send(_ input: SettingsViewModel.Input) {
        Task {
            await viewModel.trigger(input)
        }
    }
}

import PhotosUI
import SwiftUI

struct SettingsView: View {
    let currentUser: AppUser
    let onUpdateAvatar: (Data) async -> Void
    let onSignOut: () -> Void
    let onDeleteAccount: () -> Void

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isUploadingAvatar = false

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
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onChange(of: selectedPhoto) { _, newValue in
            guard let newValue else { return }
            uploadAvatar(from: newValue)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Аккаунт")
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
                        user: currentUser,
                        size: 72,
                        iconSize: 42,
                        iconTint: .white
                    )

                    Circle()
                        .fill(Color.blue)
                        .frame(width: 24, height: 24)
                        .overlay {
                            if isUploadingAvatar {
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
                Text(currentUser.displayName)
                    .font(.title3.weight(.semibold))
                Text(currentUser.email)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let username = currentUser.username, !username.isEmpty {
                    Text("Никнейм: @\(username)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.blue)
                }
                Text("ID пользователя: \(currentUser.id)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()
        }
        .padding(18)
        .callerGlassCard(cornerRadius: 24, tint: .cyan)
    }

    private var actionsCard: some View {
        VStack(spacing: 12) {
            SettingsActionButton(
                title: "Выйти",
                subtitle: "Завершить текущую сессию на этом устройстве.",
                systemName: "rectangle.portrait.and.arrow.right",
                tint: .blue,
                action: onSignOut
            )

            SettingsActionButton(
                title: "Удалить аккаунт",
                subtitle: "Удалить этот аккаунт. Firebase может потребовать повторный вход.",
                systemName: "trash.fill",
                tint: .red,
                action: onDeleteAccount
            )
        }
        .padding(18)
        .callerGlassCard(cornerRadius: 24, tint: .blue)
    }

    private func uploadAvatar(from item: PhotosPickerItem) {
        isUploadingAvatar = true

        Task {
            defer {
                Task { @MainActor in
                    isUploadingAvatar = false
                    selectedPhoto = nil
                }
            }

            guard let data = try? await item.loadTransferable(type: Data.self) else {
                return
            }

            await onUpdateAvatar(data)
        }
    }
}

private struct SettingsActionButton: View {
    let title: String
    let subtitle: String
    let systemName: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemName)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .callerGlassButtonSurface(cornerRadius: 14, tint: tint)

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
            .callerGlassCard(cornerRadius: 18, tint: tint)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SettingsView(
        currentUser: AppUser(id: "me", displayName: "Алекс Джонсон", email: "alex@example.com", avatarSystemName: "person.crop.circle.fill"),
        onUpdateAvatar: { _ in },
        onSignOut: {},
        onDeleteAccount: {}
    )
    .preferredColorScheme(.dark)
}

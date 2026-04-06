import SwiftUI

struct SettingsView: View {
    let currentUser: AppUser
    let onSignOut: () -> Void
    let onDeleteAccount: () -> Void

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
            Image(systemName: currentUser.avatarSystemName)
                .font(.system(size: 42))
                .foregroundStyle(.white, .blue)
                .frame(width: 72, height: 72)
                .background(Color.white.opacity(0.08), in: Circle())

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
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
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
    }
}

#Preview {
    SettingsView(
        currentUser: AppUser(id: "me", displayName: "Алекс Джонсон", email: "alex@example.com", avatarSystemName: "person.crop.circle.fill"),
        onSignOut: {},
        onDeleteAccount: {}
    )
    .preferredColorScheme(.dark)
}

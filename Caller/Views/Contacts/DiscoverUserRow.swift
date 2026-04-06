import SwiftUI

struct DiscoverUserRow: View {
    let user: AppUser
    let onAddFriend: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            UserAvatarView(
                user: user,
                size: 52,
                iconSize: 34,
                iconTint: .white
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(user.displayName)
                    .font(.headline)
                if let username = user.username, !username.isEmpty {
                    Text("@\(username)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.blue)
                }
                Text(user.email)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onAddFriend) {
                Text("Добавить")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .callerGlassButtonSurface(cornerRadius: 999, tint: .blue)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .callerGlassCard(cornerRadius: 22, tint: .blue)
    }
}

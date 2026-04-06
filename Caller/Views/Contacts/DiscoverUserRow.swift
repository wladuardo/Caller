import SwiftUI

struct DiscoverUserRow: View {
    let user: AppUser
    let onAddFriend: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: user.avatarSystemName)
                .font(.system(size: 34))
                .foregroundStyle(.white, .blue)
                .frame(width: 52, height: 52)
                .background(Color.white.opacity(0.08), in: Circle())

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
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.blue, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
    }
}

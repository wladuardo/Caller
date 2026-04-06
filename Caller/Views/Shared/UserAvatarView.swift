import SwiftUI

struct UserAvatarView: View {
    let user: AppUser
    let size: CGFloat
    let iconSize: CGFloat
    let iconTint: Color

    init(
        user: AppUser,
        size: CGFloat,
        iconSize: CGFloat? = nil,
        iconTint: Color = .white
    ) {
        self.user = user
        self.size = size
        self.iconSize = iconSize ?? size * 0.58
        self.iconTint = iconTint
    }

    var body: some View {
        avatarContent
            .frame(width: size, height: size)
            .background(
                LinearGradient(
                    colors: [Color.white.opacity(0.16), Color.white.opacity(0.06)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: Circle()
            )
            .clipShape(Circle())
    }

    @ViewBuilder
    private var avatarContent: some View {
        if let avatarURL = user.avatarURL,
           let url = URL(string: avatarURL) {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                placeholderAvatar
            }
        } else {
            placeholderAvatar
        }
    }

    private var placeholderAvatar: some View {
        Image(systemName: user.avatarSystemName)
            .font(.system(size: iconSize))
            .foregroundStyle(iconTint)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

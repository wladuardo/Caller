import SwiftUI

struct FriendRequestRow: View {
    let request: FriendRequest
    let onAccept: () -> Void
    let onDecline: () -> Void
    @State private var hasAnimatedIn = false

    var body: some View {
        HStack(spacing: 16) {
            UserAvatarView(
                user: request.fromUser,
                size: 52,
                iconSize: 34,
                iconTint: .white
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(request.fromUser.displayName)
                    .font(.headline)
                Text("Хочет добавить вас в друзья")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 10) {
                FriendRequestActionChip(systemName: "xmark", tint: .gray, action: onDecline)
                FriendRequestActionChip(systemName: "checkmark", tint: .green, action: onAccept)
            }
        }
        .padding(16)
        .callerGlassCard(cornerRadius: 22, tint: .green)
        .scaleEffect(hasAnimatedIn ? 1 : 0.96)
        .opacity(hasAnimatedIn ? 1 : 0)
        .offset(y: hasAnimatedIn ? 0 : 10)
        .onAppear {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                hasAnimatedIn = true
            }
        }
    }
}

private struct FriendRequestActionChip: View {
    let systemName: String
    let tint: Color
    let action: () -> Void
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .callerGlassButtonSurface(cornerRadius: 999, tint: tint)
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.9 : 1)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed { isPressed = true }
                }
                .onEnded { _ in
                    isPressed = false
                }
        )
        .animation(.spring(response: 0.22, dampingFraction: 0.7), value: isPressed)
    }
}

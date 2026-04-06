import SwiftUI

struct OutgoingFriendRequestRow: View {
    let request: OutgoingFriendRequest
    let onCancel: () -> Void
    @State private var hasAnimatedIn = false
    @State private var isPressed = false

    var body: some View {
        HStack(spacing: 16) {
            UserAvatarView(
                user: request.toUser,
                size: 52,
                iconSize: 34,
                iconTint: .white
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(request.toUser.displayName)
                    .font(.headline)
                Text("Запрос отправлен")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onCancel) {
                Text("Отменить")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .callerGlassButtonSurface(cornerRadius: 999, tint: .red)
            }
            .buttonStyle(.plain)
            .scaleEffect(isPressed ? 0.95 : 1)
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
        .padding(16)
        .callerGlassCard(cornerRadius: 22, tint: .red)
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

import SwiftUI

struct FriendRequestRow: View {
    let request: FriendRequest
    let onAccept: () -> Void
    let onDecline: () -> Void
    @State private var hasAnimatedIn = false

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: request.fromUser.avatarSystemName)
                .font(.system(size: 34))
                .foregroundStyle(.white, .orange)
                .frame(width: 52, height: 52)
                .background(Color.white.opacity(0.08), in: Circle())

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
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
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
                .background(tint, in: Circle())
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

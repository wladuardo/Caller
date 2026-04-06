import SwiftUI

struct OutgoingFriendRequestRow: View {
    let request: OutgoingFriendRequest
    let onCancel: () -> Void
    @State private var hasAnimatedIn = false
    @State private var isPressed = false

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: request.toUser.avatarSystemName)
                .font(.system(size: 34))
                .foregroundStyle(.white, .blue)
                .frame(width: 52, height: 52)
                .background(Color.white.opacity(0.08), in: Circle())

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
                    .background(Color.red.opacity(0.9), in: Capsule())
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

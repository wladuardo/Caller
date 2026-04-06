import SwiftUI

struct ContactRow: View {
    let user: AppUser
    let unreadMessageCount: Int
    let onDetailsTap: () -> Void
    let onChatTap: () -> Void
    let onAudioTap: () -> Void
    let onVideoTap: () -> Void
    @State private var isShowingUnreadPulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 14) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: user.avatarSystemName)
                        .font(.system(size: 34))
                        .foregroundStyle(.white, .blue)
                        .frame(width: 58, height: 58)
                        .background(
                            LinearGradient(
                                colors: [Color.white.opacity(0.16), Color.white.opacity(0.06)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: Circle()
                        )

                    if unreadMessageCount > 0 {
                        Text(unreadBadgeText)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(Color.red, in: Capsule())
                            .offset(x: 8, y: -6)
                            .scaleEffect(isShowingUnreadPulse ? 1.06 : 1)
                            .transition(.scale(scale: 0.7).combined(with: .opacity))
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(user.displayName)
                        .font(.headline.weight(.semibold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(user.email)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                    if unreadMessageCount > 0 {
                        Text("\(unreadMessageCount) непрочит. сообщ.")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.indigo)
                    }
                }
                .layoutPriority(1)

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onDetailsTap)

            HStack(spacing: 10) {
                ContactActionButton(
                    title: "Чат",
                    systemName: "message.fill",
                    tint: .indigo,
                    badgeCount: unreadMessageCount,
                    action: onChatTap
                )
                ContactActionButton(
                    title: "Аудио",
                    systemName: "phone.fill",
                    tint: .green,
                    badgeCount: 0,
                    action: onAudioTap
                )
                ContactActionButton(
                    title: "Видео",
                    systemName: "video.fill",
                    tint: .blue,
                    badgeCount: 0,
                    action: onVideoTap
                )
            }
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
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: unreadMessageCount)
        .onChange(of: unreadMessageCount) { oldValue, newValue in
            guard newValue > oldValue, newValue > 0 else { return }
            withAnimation(.spring(response: 0.24, dampingFraction: 0.45)) {
                isShowingUnreadPulse = true
            }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8).delay(0.12)) {
                isShowingUnreadPulse = false
            }
        }
    }
}

extension ContactRow {
    private var unreadBadgeText: String {
        unreadMessageCount > 99 ? "99+" : "\(unreadMessageCount)"
    }
}

private struct ContactActionButton: View {
    let title: String
    let systemName: String
    let tint: Color
    let badgeCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemName)
                    .font(.footnote.weight(.semibold))
                Text(title)
                    .font(.subheadline.weight(.semibold))
                if badgeCount > 0 {
                    Text("\(badgeCount)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.white, in: Capsule())
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(tint.opacity(0.9), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.97 : 1)
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

    @State private var isPressed = false
}

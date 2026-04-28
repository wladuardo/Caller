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
        Group {
            if #available(iOS 26.0, *) {
                liquidGlassCard
            } else {
                fallbackCard
            }
        }
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
    private var rowContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 14) {
                ZStack(alignment: .topTrailing) {
                    UserAvatarView(
                        user: user,
                        size: 58,
                        iconSize: 34,
                        iconTint: .white
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
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(user.email)
                        .font(.subheadline)
                        .foregroundStyle(Color.white.opacity(0.72))
                        .lineLimit(2)
                        .truncationMode(.middle)
                    if unreadMessageCount > 0 {
                        Text("\(unreadMessageCount) непрочит. сообщ.")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.cyan)
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
    }

    private var fallbackCard: some View {
        rowContent
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    @available(iOS 26.0, *)
    private var liquidGlassCard: some View {
        rowContent
            .background {
                GlassEffectContainer(spacing: 18) {
                    ZStack {
                        Color.clear
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.12),
                                        Color.white.opacity(0.04),
                                        Color.cyan.opacity(0.07)
                                    ],
                                    startPoint: UnitPoint.topLeading,
                                    endPoint: UnitPoint.bottomTrailing
                                )
                            )

                        VStack {
                            HStack {
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.20))
                                    .frame(width: 120, height: 10)
                                    .blur(radius: 10)
                                Spacer()
                            }
                            Spacer()
                        }
                        .padding(.top, 12)
                        .padding(.leading, 18)
                    }
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 28))
                }
            }
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 22, y: 14)
    }

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
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(.white)
            .background(buttonBackground)
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

    @ViewBuilder
    private var buttonBackground: some View {
        if #available(iOS 26.0, *) {
            ZStack {
                Color.clear
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(tint.opacity(0.14))
            }
            .glassEffect(.regular.tint(tint.opacity(0.45)).interactive(), in: .rect(cornerRadius: 18))
        } else {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint.opacity(0.9))
        }
    }

    @State private var isPressed = false
}

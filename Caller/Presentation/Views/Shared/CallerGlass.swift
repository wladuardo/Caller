import SwiftUI

extension View {
    func callerGlassCard(
        cornerRadius: CGFloat = 24,
        tint: Color = .cyan,
        padding: CGFloat? = nil,
        showsShadow: Bool = true
    ) -> some View {
        modifier(
            CallerGlassCardModifier(
                cornerRadius: cornerRadius,
                tint: tint,
                padding: padding,
                showsShadow: showsShadow
            )
        )
    }

    func callerGlassButtonSurface(
        cornerRadius: CGFloat = 18,
        tint: Color
    ) -> some View {
        modifier(
            CallerGlassButtonModifier(
                cornerRadius: cornerRadius,
                tint: tint
            )
        )
    }
}

private struct CallerGlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color
    let padding: CGFloat?
    let showsShadow: Bool

    func body(content: Content) -> some View {
        let shapedContent = Group {
            if let padding {
                content.padding(padding)
            } else {
                content
            }
        }

        return shapedContent
            .background(backgroundLayer)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(showsShadow ? 0.18 : 0), radius: showsShadow ? 22 : 0, y: showsShadow ? 14 : 0)
    }

    @ViewBuilder
    private var backgroundLayer: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 18) {
                ZStack {
                    Color.clear
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.12),
                                    Color.white.opacity(0.04),
                                    tint.opacity(0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    VStack {
                        HStack {
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.18))
                                .frame(width: 120, height: 10)
                                .blur(radius: 10)
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(.top, 12)
                    .padding(.leading, 18)
                }
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        }
    }
}

private struct CallerGlassButtonModifier: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color

    func body(content: Content) -> some View {
        content.background(backgroundLayer)
    }

    @ViewBuilder
    private var backgroundLayer: some View {
        if #available(iOS 26.0, *) {
            ZStack {
                Color.clear
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(tint.opacity(0.14))
            }
            .glassEffect(.regular.tint(tint.opacity(0.45)).interactive(), in: .rect(cornerRadius: cornerRadius))
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(tint.opacity(0.9))
        }
    }
}

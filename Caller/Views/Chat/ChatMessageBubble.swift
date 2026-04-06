import SwiftUI

struct ChatMessageBubble: View {
    let message: ChatMessage
    let isOutgoing: Bool

    var body: some View {
        HStack {
            if isOutgoing {
                Spacer(minLength: 56)
            }

            VStack(alignment: isOutgoing ? .trailing : .leading, spacing: 6) {
                Text(message.text)
                    .font(.body)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)

                Text(message.sentAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.68))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(bubbleBackground)

            if !isOutgoing {
                Spacer(minLength: 56)
            }
        }
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        if isOutgoing {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.blue.gradient)
                .callerGlassCard(cornerRadius: 18, tint: .blue, showsShadow: false)
        } else {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .callerGlassCard(cornerRadius: 18, tint: .cyan, showsShadow: false)
        }
    }
}

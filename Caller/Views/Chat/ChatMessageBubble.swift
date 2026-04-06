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
            .background(bubbleColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            if !isOutgoing {
                Spacer(minLength: 56)
            }
        }
    }

    private var bubbleColor: AnyShapeStyle {
        if isOutgoing {
            return AnyShapeStyle(Color.blue.gradient)
        } else {
            return AnyShapeStyle(Color.white.opacity(0.12))
        }
    }
}

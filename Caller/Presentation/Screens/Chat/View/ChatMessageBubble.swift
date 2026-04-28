import SwiftUI

struct ChatMessageBubble: View {
    let message: ChatMessage
    let isOutgoing: Bool
    let onAttachmentTap: ((ChatAttachment) -> Void)?

    init(
        message: ChatMessage,
        isOutgoing: Bool,
        onAttachmentTap: ((ChatAttachment) -> Void)? = nil
    ) {
        self.message = message
        self.isOutgoing = isOutgoing
        self.onAttachmentTap = onAttachmentTap
    }

    var body: some View {
        HStack {
            if isOutgoing {
                Spacer(minLength: 56)
            }

            VStack(alignment: isOutgoing ? .trailing : .leading, spacing: 6) {
                if let attachment = message.attachment {
                    attachmentView(attachment)
                }

                if !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(message.text)
                        .font(.body)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                }

                HStack(spacing: 4) {
                    Text(message.sentAt.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.68))

                    if isOutgoing {
                        if message.isReadByRecipient {
                            HStack(spacing: -3) {
                                Image(systemName: "checkmark")
                                Image(systemName: "checkmark")
                            }
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.green.opacity(0.95))
                            .accessibilityLabel(Text("Прочитано"))
                        } else {
                            Image(systemName: "checkmark")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Color.white.opacity(0.7))
                                .accessibilityLabel(Text("Отправлено"))
                        }
                    }
                }
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

    @ViewBuilder
    private func attachmentView(_ attachment: ChatAttachment) -> some View {
        switch attachment.kind {
        case .image:
            Button {
                onAttachmentTap?(attachment)
            } label: {
                imageAttachmentView(attachment)
            }
            .buttonStyle(.plain)
        case .file:
            Button {
                onAttachmentTap?(attachment)
            } label: {
                fileAttachmentView(attachment)
            }
            .buttonStyle(.plain)
        }
    }

    private func imageAttachmentView(_ attachment: ChatAttachment) -> some View {
        CachedRemoteImage(url: URL(string: attachment.downloadURL)) { image in
            image
                .resizable()
                .scaledToFill()
        } placeholder: {
            ZStack {
                Color.white.opacity(0.08)
                ProgressView()
                    .tint(.white)
            }
        }
        .frame(width: 220, height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            if URL(string: attachment.downloadURL) == nil {
                fallbackAttachmentIcon(systemName: "photo.fill")
            }
        }
    }

    private func fileAttachmentView(_ attachment: ChatAttachment) -> some View {
        fileAttachmentLabel(attachment)
    }

    private func fileAttachmentLabel(_ attachment: ChatAttachment) -> some View {
        HStack(spacing: 10) {
            fallbackAttachmentIcon(systemName: "doc.fill")
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.fileName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if let fileSize = attachment.fileSize {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.68))
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: 220, alignment: .leading)
    }

    private func fallbackAttachmentIcon(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.white.opacity(0.92))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white.opacity(0.12))
    }
}

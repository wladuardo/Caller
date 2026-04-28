import SwiftUI

enum DiscoverUserStatus: Equatable {
    case addable
    case friend
    case outgoingRequest
    case incomingRequest

    var title: String {
        switch self {
        case .addable:
            return "Добавить"
        case .friend:
            return "В друзьях"
        case .outgoingRequest:
            return "Приглашение отправлено"
        case .incomingRequest:
            return "Входящий запрос"
        }
    }

    var tint: Color {
        switch self {
        case .addable:
            return .blue
        case .friend:
            return .green
        case .outgoingRequest:
            return .orange
        case .incomingRequest:
            return .cyan
        }
    }

    var isActionAvailable: Bool {
        self == .addable
    }
}

struct DiscoverUserRow: View {
    let user: AppUser
    let status: DiscoverUserStatus
    let onPrimaryAction: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                UserAvatarView(
                    user: user,
                    size: 58,
                    iconSize: 36,
                    iconTint: .white
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text(user.displayName)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if let username = user.username, !username.isEmpty {
                        Text("@\(username)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(status.tint)
                            .lineLimit(1)
                    }

                    Text(user.email)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .fixedSize(horizontal: false, vertical: true)

                    statusCaption
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button(action: { onPrimaryAction?() }) {
                HStack {
                    Text(status.title)
                        .font(.subheadline.weight(.semibold))

                    if status.isActionAvailable {
                        Image(systemName: "plus")
                            .font(.caption.weight(.bold))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .callerGlassButtonSurface(cornerRadius: 16, tint: status.tint)
            }
            .buttonStyle(.plain)
            .disabled(!status.isActionAvailable)
        }
        .padding(18)
        .callerGlassCard(cornerRadius: 22, tint: status.tint)
    }

    @ViewBuilder
    private var statusCaption: some View {
        switch status {
        case .addable:
            Text("Можно отправить приглашение в друзья.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .friend:
            Text("Этот пользователь уже у вас в друзьях.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .outgoingRequest:
            Text("Пользователь ещё не принял ваше приглашение.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .incomingRequest:
            Text("У этого пользователя уже есть входящий запрос к вам.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

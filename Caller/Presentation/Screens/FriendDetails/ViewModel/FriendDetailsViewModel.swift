import Foundation
import Observation

@Observable
final class FriendDetailsViewModel: Store {
    struct Dependencies {
        let onOpenChat: @MainActor @Sendable () -> Void
        let onStartAudioCall: @MainActor @Sendable () -> Void
        let onStartVideoCall: @MainActor @Sendable () -> Void
        let onShowOnMap: @MainActor @Sendable () -> Void
        let onSetNotificationsMuted: @MainActor @Sendable (Bool) async -> Void
        let onRemoveFriend: @MainActor @Sendable () async -> Void
        let onDismiss: @MainActor @Sendable () -> Void
    }

    var state: State

    private let dependencies: Dependencies

    init(
        user: AppUser,
        unreadMessageCount: Int,
        isNotificationsMuted: Bool,
        dependencies: Dependencies
    ) {
        self.state = State(
            user: user,
            unreadMessageCount: unreadMessageCount,
            notificationsMuted: isNotificationsMuted
        )
        self.dependencies = dependencies
    }

    func trigger(_ input: Input) async {
        switch input {
        case .tapOpenChat:
            dependencies.onOpenChat()
        case .tapStartAudioCall:
            dependencies.onStartAudioCall()
        case .tapStartVideoCall:
            dependencies.onStartVideoCall()
        case .tapShowOnMap:
            dependencies.onShowOnMap()
        case .tapToggleNotifications:
            guard !state.isUpdatingNotifications else { return }
            let nextValue = !state.notificationsMuted
            update { state in
                state.isUpdatingNotifications = true
                state.notificationsMuted = nextValue
            }
            await dependencies.onSetNotificationsMuted(nextValue)
            update { state in
                state.isUpdatingNotifications = false
            }
        case .setRemoveConfirmationPresented(let isPresented):
            update { state in
                state.isShowingRemoveConfirmation = isPresented
            }
        case .tapConfirmRemoveFriend:
            guard !state.isRemoving else { return }
            update { state in
                state.isRemoving = true
                state.isShowingRemoveConfirmation = false
            }
            await dependencies.onRemoveFriend()
            update { state in
                state.isRemoving = false
            }
            dependencies.onDismiss()
        }
    }

    var hasDeviceTelemetry: Bool {
        deviceModelText != nil || batteryLevelText != nil
    }

    var deviceModelText: String? {
        state.user.deviceModel
    }

    var batteryLevelText: String? {
        guard let batteryLevelPercent = state.user.sharedLocation?.batteryLevelPercent else {
            return nil
        }

        return "\(batteryLevelPercent)%"
    }
}

extension FriendDetailsViewModel {
    struct State {
        var user: AppUser
        var unreadMessageCount: Int
        var notificationsMuted: Bool
        var isShowingRemoveConfirmation = false
        var isRemoving = false
        var isUpdatingNotifications = false
    }

    enum Input: Sendable {
        case tapOpenChat
        case tapStartAudioCall
        case tapStartVideoCall
        case tapShowOnMap
        case tapToggleNotifications
        case setRemoveConfirmationPresented(Bool)
        case tapConfirmRemoveFriend
    }
}

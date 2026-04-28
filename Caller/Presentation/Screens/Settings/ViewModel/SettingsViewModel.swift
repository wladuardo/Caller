import Foundation
import Observation

@Observable
final class SettingsViewModel: Store {
    struct Dependencies {
        let onUpdateAvatar: @MainActor @Sendable (Data) async -> Void
        let onSignOut: @MainActor @Sendable () -> Void
        let onDeleteAccount: @MainActor @Sendable () -> Void
    }

    var state: State

    private let dependencies: Dependencies

    init(
        currentUser: AppUser,
        dependencies: Dependencies
    ) {
        self.state = State(currentUser: currentUser)
        self.dependencies = dependencies
    }

    func trigger(_ input: Input) async {
        switch input {
        case .setCurrentUser(let user):
            update { state in
                state.currentUser = user
            }

        case .pickedAvatarData(let data):
            update { state in
                state.isUploadingAvatar = true
            }
            await dependencies.onUpdateAvatar(data)
            update { state in
                state.isUploadingAvatar = false
            }

        case .tapSignOut:
            await dependencies.onSignOut()

        case .tapDeleteAccount:
            await dependencies.onDeleteAccount()
        }
    }
}

extension SettingsViewModel {
    struct State {
        var currentUser: AppUser
        var isUploadingAvatar = false
    }

    enum Input: Sendable {
        case setCurrentUser(AppUser)
        case pickedAvatarData(Data)
        case tapSignOut
        case tapDeleteAccount
    }
}

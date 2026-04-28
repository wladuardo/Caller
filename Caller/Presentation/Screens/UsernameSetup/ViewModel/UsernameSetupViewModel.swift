import Foundation
import Observation

@Observable
final class UsernameSetupViewModel: Store {
    struct Dependencies {
        let saveUsername: @MainActor @Sendable (String) async -> AppViewModel.UsernameSaveResult
    }

    var state = State()

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func trigger(_ input: Input) async {
        switch input {
        case .setUsername(let username):
            update { state in
                state.username = username
            }

        case .tapSubmit:
            let normalizedUsername = UsernameValidator.normalized(state.username)

            if let error = UsernameValidator.validate(normalizedUsername) {
                update { state in
                    state.validationMessage = error
                }
                return
            }

            update { state in
                state.validationMessage = nil
                state.isSubmitting = true
                state.username = normalizedUsername
            }

            let result = await dependencies.saveUsername(normalizedUsername)
            update { state in
                state.isSubmitting = false
                switch result {
                case .success:
                    state.validationMessage = nil
                case .inlineError(let message):
                    state.validationMessage = message
                case .alertError:
                    state.validationMessage = nil
                }
            }
        }
    }
}

extension UsernameSetupViewModel {
    struct State {
        var username = ""
        var validationMessage: String?
        var isSubmitting = false
    }

    enum Input: Sendable {
        case setUsername(String)
        case tapSubmit
    }
}

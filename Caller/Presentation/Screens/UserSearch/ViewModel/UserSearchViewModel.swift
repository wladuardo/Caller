import Foundation
import Observation

@Observable
final class UserSearchViewModel: Store {
    struct Dependencies {
        let currentUser: @MainActor () -> AppUser?
        let contacts: @MainActor () -> [AppUser]
        let outgoingRequests: @MainActor () -> [OutgoingFriendRequest]
        let incomingRequests: @MainActor () -> [FriendRequest]
        let takePendingInviteSearch: @MainActor () -> (username: String?, shouldAutoSend: Bool)
        let searchUser: @MainActor (String) async -> AppUser?
        let sendFriendRequest: @MainActor (AppUser) async -> Void
    }

    var state = State()

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func trigger(_ input: Input) async {
        switch input {
        case .onFirstAppear:
            let currentUser = dependencies.currentUser()
            update { state in
                state.currentUser = currentUser
            }
            await trigger(.syncPendingInvite)

        case .syncPendingInvite:
            let payload = dependencies.takePendingInviteSearch()
            guard let username = payload.username else { return }

            update { state in
                state.searchQuery = username
                state.searchMessage = "Открыта ссылка-приглашение."
            }
            await performSearch(using: username, automaticallySendRequest: payload.shouldAutoSend)

        case .setSearchQuery(let query):
            update { state in
                state.searchQuery = query
            }

        case .tapSearch:
            let query = UsernameValidator.normalized(state.searchQuery)
            await performSearch(using: query, automaticallySendRequest: false)

        case .tapPrimaryAction:
            let result = state.searchResult
            guard let result, result.status == .addable else { return }
            await sendFriendRequest(to: result.user)

        case .tapShowQRScanner:
            update { state in
                state.isShowingQRScanner = true
            }

        case .dismissQRScanner:
            update { state in
                state.isShowingQRScanner = false
            }

        case .tapShowMyQRCode:
            let currentUser = dependencies.currentUser()
            update { state in
                state.currentUser = currentUser
                state.isShowingMyQRCode = true
            }

        case .dismissMyQRCode:
            update { state in
                state.isShowingMyQRCode = false
            }

        case .scannedCode(let code):
            guard let username = extractUsername(from: code) else {
                await trigger(.scannerFailed("Не удалось распознать QR-код Caller."))
                return
            }

            update { state in
                state.isShowingQRScanner = false
                state.searchQuery = username
                state.searchMessage = "Никнейм получен из QR-кода."
            }
            await performSearch(using: username, automaticallySendRequest: false)

        case .scannerFailed(let message):
            update { state in
                state.isShowingQRScanner = false
                state.searchMessage = message
            }
        }
    }

    private func performSearch(using rawQuery: String, automaticallySendRequest: Bool) async {
        let normalizedQuery = UsernameValidator.normalized(rawQuery)

        if let error = UsernameValidator.validate(normalizedQuery) {
            update { state in
                state.searchMessage = error
                state.searchResult = nil
                state.hasSearched = false
                state.isSearching = false
            }
            return
        }

        update { state in
            state.searchQuery = normalizedQuery
            state.isSearching = true
            state.searchMessage = nil
            state.searchResult = nil
        }

        let result = await resolveSearchResult(for: normalizedQuery)

        update { state in
            state.isSearching = false
            state.hasSearched = true
            state.searchResult = result
            if result == nil {
                state.searchMessage = nil
            }
        }

        if let result, automaticallySendRequest, result.status == .addable {
            await sendFriendRequest(to: result.user)
        }
    }

    private func sendFriendRequest(to user: AppUser) async {
        await dependencies.sendFriendRequest(user)
        update { state in
            state.searchMessage = "Запрос в друзья отправлен."
            state.searchResult = ResultState(user: user, status: .outgoingRequest)
            state.hasSearched = true
        }
    }

    private func resolveSearchResult(for username: String) async -> ResultState? {
        let contacts = dependencies.contacts()
        if let friend = contacts.first(where: {
            UsernameValidator.normalized($0.username ?? "") == username
        }) {
            return ResultState(user: friend, status: .friend)
        }

        let outgoingRequests = dependencies.outgoingRequests()
        if let outgoing = outgoingRequests.first(where: {
            UsernameValidator.normalized($0.toUser.username ?? "") == username
        }) {
            return ResultState(user: outgoing.toUser, status: .outgoingRequest)
        }

        let incomingRequests = dependencies.incomingRequests()
        if let incoming = incomingRequests.first(where: {
            UsernameValidator.normalized($0.fromUser.username ?? "") == username
        }) {
            return ResultState(user: incoming.fromUser, status: .incomingRequest)
        }

        guard let user = await dependencies.searchUser(username) else {
            return nil
        }

        return ResultState(user: user, status: .addable)
    }

    private func extractUsername(from payload: String) -> String? {
        if let components = URLComponents(string: payload),
           components.scheme == "caller",
           components.host == "invite",
           let username = components.queryItems?.first(where: { $0.name == "username" })?.value {
            let normalized = UsernameValidator.normalized(username)
            return normalized.isEmpty ? nil : normalized
        }

        let normalized = UsernameValidator.normalized(payload)
        return normalized.isEmpty ? nil : normalized
    }
}

extension UserSearchViewModel {
    struct ResultState: Equatable {
        let user: AppUser
        var status: DiscoverUserStatus
    }

    struct State: Equatable {
        var currentUser: AppUser?
        var searchQuery = ""
        var searchResult: ResultState?
        var searchMessage: String?
        var isSearching = false
        var hasSearched = false
        var isShowingQRScanner = false
        var isShowingMyQRCode = false
    }

    enum Input: Sendable {
        case onFirstAppear
        case syncPendingInvite
        case setSearchQuery(String)
        case tapSearch
        case tapPrimaryAction
        case tapShowQRScanner
        case dismissQRScanner
        case tapShowMyQRCode
        case dismissMyQRCode
        case scannedCode(String)
        case scannerFailed(String)
    }
}

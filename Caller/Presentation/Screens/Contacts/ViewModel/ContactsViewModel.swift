import Foundation
import Observation

enum ContactsRoute: Hashable, Sendable {
    case chat(AppUser)
    case details(AppUser)
}

@Observable
final class ContactsViewModel: Store {
    struct Dependencies {
        let loadContacts: @MainActor @Sendable () async -> Void
        let loadFriendRequests: @MainActor @Sendable () async -> Void
        let consumePendingChatNavigation: @MainActor @Sendable () -> Void
        let acceptFriendRequest: @MainActor @Sendable (AppUser) async -> Void
        let declineFriendRequest: @MainActor @Sendable (AppUser) async -> Void
        let cancelOutgoingFriendRequest: @MainActor @Sendable (AppUser) async -> Void
        let startCall: @MainActor @Sendable (AppUser, CallType) async -> Void
        let setNotificationsMuted: @MainActor @Sendable (Bool, AppUser) async -> Void
        let removeFriend: @MainActor @Sendable (AppUser) async -> Void
        let showUserOnMap: @MainActor @Sendable (AppUser) -> Void
    }

    var state = State()

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func trigger(_ input: Input) async {
        switch input {
        case .onAppear:
            await trigger(.tapPendingChatNavigation)
            await trigger(.tapPendingInviteSearch)

        case .refresh:
            await dependencies.loadContacts()
            await dependencies.loadFriendRequests()

        case .syncExternalState(let externalState):
            update { state in
                state.contacts = externalState.contacts
                state.incomingFriendRequests = externalState.incomingFriendRequests
                state.outgoingFriendRequests = externalState.outgoingFriendRequests
                state.unreadMessageCounts = externalState.unreadMessageCounts
                state.pendingChatNavigationUser = externalState.pendingChatNavigationUser
                state.pendingInviteSearchUsername = externalState.pendingInviteSearchUsername
            }

        case .tapSearch:
            update { state in
                state.isShowingSearch = true
            }

        case .setSearchPresented(let isPresented):
            update { state in
                state.isShowingSearch = isPresented
            }

        case .tapOpenChat(let user):
            update { state in
                state.navigationPath.append(.chat(user))
            }

        case .tapOpenDetails(let user):
            update { state in
                state.navigationPath.append(.details(user))
            }

        case .tapPendingChatNavigation:
            guard let user = state.pendingChatNavigationUser,
                  state.navigationPath.last != .chat(user) else {
                return
            }

            update { state in
                state.navigationPath = [.chat(user)]
                state.pendingChatNavigationUser = nil
            }
            dependencies.consumePendingChatNavigation()

        case .tapPendingInviteSearch:
            guard state.pendingInviteSearchUsername != nil else { return }
            update { state in
                state.isShowingSearch = true
            }

        case .setNavigationPath(let navigationPath):
            update { state in
                state.navigationPath = navigationPath
            }

        case .removeRoutes(for: let user):
            update { state in
                state.navigationPath.removeAll { route in
                    switch route {
                    case .chat(let routeUser), .details(let routeUser):
                        return routeUser.id == user.id
                    }
                }
            }

        case .acceptFriendRequest(let user):
            await dependencies.acceptFriendRequest(user)

        case .declineFriendRequest(let user):
            await dependencies.declineFriendRequest(user)

        case .cancelOutgoingFriendRequest(let user):
            await dependencies.cancelOutgoingFriendRequest(user)

        case .startCall(let user, let type):
            await dependencies.startCall(user, type)

        case .setNotificationsMuted(let isMuted, let user):
            await dependencies.setNotificationsMuted(isMuted, user)

        case .removeFriend(let user):
            await dependencies.removeFriend(user)

        case .showUserOnMap(let user):
            dependencies.showUserOnMap(user)
        }
    }
}

extension ContactsViewModel {
    struct ExternalState {
        var contacts: [AppUser]
        var incomingFriendRequests: [FriendRequest]
        var outgoingFriendRequests: [OutgoingFriendRequest]
        var unreadMessageCounts: [String: Int]
        var pendingChatNavigationUser: AppUser?
        var pendingInviteSearchUsername: String?
    }

    struct State {
        var contacts: [AppUser] = []
        var incomingFriendRequests: [FriendRequest] = []
        var outgoingFriendRequests: [OutgoingFriendRequest] = []
        var unreadMessageCounts: [String: Int] = [:]
        var pendingChatNavigationUser: AppUser?
        var pendingInviteSearchUsername: String?
        var navigationPath: [ContactsRoute] = []
        var isShowingSearch = false
    }

    enum Input: Sendable {
        case onAppear
        case refresh
        case syncExternalState(ExternalState)
        case tapSearch
        case setSearchPresented(Bool)
        case tapOpenChat(AppUser)
        case tapOpenDetails(AppUser)
        case tapPendingChatNavigation
        case tapPendingInviteSearch
        case setNavigationPath([ContactsRoute])
        case removeRoutes(for: AppUser)
        case acceptFriendRequest(AppUser)
        case declineFriendRequest(AppUser)
        case cancelOutgoingFriendRequest(AppUser)
        case startCall(AppUser, CallType)
        case setNotificationsMuted(Bool, AppUser)
        case removeFriend(AppUser)
        case showUserOnMap(AppUser)
    }
}

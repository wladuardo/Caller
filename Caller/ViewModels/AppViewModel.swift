import Combine
import CoreLocation
import Foundation
import WebRTC

@MainActor
final class AppViewModel: ObservableObject {
    enum UsernameSaveResult {
        case success
        case inlineError(String)
        case alertError
    }

    @Published private(set) var currentUser: AppUser?
    @Published private(set) var contacts: [AppUser] = []
    @Published private(set) var incomingFriendRequests: [FriendRequest] = []
    @Published private(set) var outgoingFriendRequests: [OutgoingFriendRequest] = []
    @Published private(set) var activeCall: CallSession?
    @Published private(set) var incomingCall: CallSession?
    @Published private(set) var localVideoTrack: RTCVideoTrack?
    @Published private(set) var remoteVideoTrack: RTCVideoTrack?
    @Published private(set) var unreadMessageCounts: [String: Int] = [:]
    @Published private(set) var currentLocation: SharedLocation?
    @Published var pendingChatNavigationUser: AppUser?
    @Published var pendingMapFocusUser: AppUser?
    @Published var pendingInviteSearchUsername: String?
    @Published var pendingInviteShouldAutoSend = false
    @Published var callError: CallError?
    @Published var isLoading = false
    @Published private(set) var isRestoringSession = false

    var requiresUsernameSetup: Bool {
        guard let username = currentUser?.username else { return true }
        return username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private let environment: AppEnvironment
    private var subscriptions = Set<AnyCancellable>()
    private var contactsObservationTask: Task<Void, Never>?
    private var conversationObservationTasks: [String: Task<Void, Never>] = [:]
    private var incomingRequestsObservationTask: Task<Void, Never>?
    private var outgoingRequestsObservationTask: Task<Void, Never>?
    private var systemCallEventsTask: Task<Void, Never>?
    private var notificationEventsTask: Task<Void, Never>?
    private var locationObservationTask: Task<Void, Never>?
    private var previousUnreadMessageCounts: [String: Int] = [:]
    private var activeChatUserID: String?
    private var initializedUnreadUsers = Set<String>()
    private var notifiedIncomingCallID: UUID?
    private var deferredInviteUsername: String?

    init(environment: AppEnvironment) {
        self.environment = environment
        bind()
        observeSystemCallEvents()
        observeNotificationEvents()
        observeLocationUpdates()
        restoreSessionIfNeeded()
    }

    func signInWithGoogle(idToken: String, accessToken: String) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let user = try await environment.authService.signInWithGoogle(
                idToken: idToken,
                accessToken: accessToken
            )
            currentUser = user
            isRestoringSession = true
            await bootstrapSession()
        } catch let error as CallError {
            callError = error
        } catch {
            callError = .general(error.localizedDescription)
        }
    }

    func signInWithApple(idToken: String, nonce: String, fullName: PersonNameComponents?) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let user = try await environment.authService.signInWithApple(
                idToken: idToken,
                nonce: nonce,
                fullName: fullName
            )
            currentUser = user
            isRestoringSession = true
            await bootstrapSession()
        } catch let error as CallError {
            callError = error
        } catch {
            callError = .general(error.localizedDescription)
        }
    }

    func signOut() async {
        await environment.notificationService.updateCurrentUser(nil)
        await SystemCallService.shared.updateCurrentUser(nil)
        await environment.locationService.updateCurrentUser(nil)
        await environment.authService.signOut()
        environment.signalingService.disconnect()
        resetSessionState()
    }

    func deleteAccount() async {
        do {
            try await environment.authService.deleteAccount()
            await environment.notificationService.updateCurrentUser(nil)
            await SystemCallService.shared.updateCurrentUser(nil)
            await environment.locationService.updateCurrentUser(nil)
            environment.signalingService.disconnect()
            resetSessionState()
        } catch {
            callError = .general(error.localizedDescription)
        }
    }

    private func resetSessionState() {
        currentUser = nil
        contacts = []
        incomingFriendRequests = []
        outgoingFriendRequests = []
        activeCall = nil
        incomingCall = nil
        localVideoTrack = nil
        remoteVideoTrack = nil
        unreadMessageCounts = [:]
        currentLocation = nil
        previousUnreadMessageCounts = [:]
        initializedUnreadUsers = []
        activeChatUserID = nil
        notifiedIncomingCallID = nil
        pendingChatNavigationUser = nil
        pendingMapFocusUser = nil
        pendingInviteSearchUsername = nil
        pendingInviteShouldAutoSend = false
        deferredInviteUsername = nil
        isRestoringSession = false
        contactsObservationTask?.cancel()
        contactsObservationTask = nil
        incomingRequestsObservationTask?.cancel()
        incomingRequestsObservationTask = nil
        outgoingRequestsObservationTask?.cancel()
        outgoingRequestsObservationTask = nil
        conversationObservationTasks.values.forEach { $0.cancel() }
        conversationObservationTasks.removeAll()
        notificationEventsTask?.cancel()
        notificationEventsTask = nil
        locationObservationTask?.cancel()
        locationObservationTask = nil
    }

    func loadContacts() async {
        do {
            contacts = try await environment.contactService.fetchContacts()
            if let currentUser {
                observeUnreadCounts(for: contacts, currentUser: currentUser)
            }
            await environment.locationService.updateFriends(contacts)
        } catch {
            callError = .general("Не удалось загрузить контакты.")
        }
    }

    func loadFriendRequests() async {
        do {
            incomingFriendRequests = try await environment.friendService.fetchIncomingRequests()
        } catch {
            callError = .general("Не удалось загрузить запросы в друзья.")
        }
    }

    func sendFriendRequest(to user: AppUser) async {
        do {
            try await environment.friendService.sendFriendRequest(to: user)
        } catch {
            callError = .general("Не удалось отправить запрос в друзья.")
        }
    }

    func acceptFriendRequest(from user: AppUser) async {
        do {
            try await environment.friendService.acceptFriendRequest(from: user)
        } catch {
            callError = .general("Не удалось принять запрос в друзья.")
        }
    }

    func declineFriendRequest(from user: AppUser) async {
        do {
            try await environment.friendService.declineFriendRequest(from: user)
        } catch {
            callError = .general("Не удалось отклонить запрос в друзья.")
        }
    }

    func cancelOutgoingFriendRequest(to user: AppUser) async {
        do {
            try await environment.friendService.cancelOutgoingRequest(to: user)
        } catch {
            callError = .general("Не удалось отменить исходящий запрос.")
        }
    }

    func removeFriend(_ user: AppUser) async {
        do {
            try await environment.friendService.removeFriend(user)
        } catch {
            callError = .general("Не удалось удалить друга.")
        }
    }

    func startCall(with user: AppUser, type: CallType) async {
        guard let currentUser else { return }
        await environment.callService.startCall(with: user, type: type, currentUser: currentUser)
    }

    func acceptIncomingCall() async {
        guard let currentUser else { return }
        await environment.callService.acceptIncomingCall(currentUser: currentUser)
    }

    func declineIncomingCall() async {
        guard let currentUser else { return }
        await environment.callService.declineIncomingCall(currentUser: currentUser)
    }

    func endCall() async {
        guard let currentUser else { return }
        await environment.callService.endCall(currentUser: currentUser)
    }

    func toggleMute() {
        environment.callService.toggleMute()
    }

    func toggleSpeaker() {
        environment.callService.toggleSpeaker()
    }

    func toggleCamera() {
        environment.callService.toggleCamera()
    }

    func switchCamera() {
        environment.callService.switchCamera()
    }

    func dismissError() {
        callError = nil
    }

    func isNotificationsMuted(for user: AppUser) -> Bool {
        currentUser?.mutedNotificationUserIDs.contains(user.id) == true
    }

    func setNotificationsMuted(_ isMuted: Bool, for user: AppUser) async {
        guard let currentUser else { return }

        do {
            let mutedUserIDs = try await environment.contactService.setNotificationsMuted(
                isMuted,
                for: user.id
            )
            self.currentUser = AppUser(
                id: currentUser.id,
                displayName: currentUser.displayName,
                email: currentUser.email,
                avatarSystemName: currentUser.avatarSystemName,
                avatarURL: currentUser.avatarURL,
                username: currentUser.username,
                mutedNotificationUserIDs: mutedUserIDs
            )
        } catch {
            callError = .general("Не удалось обновить настройки уведомлений.")
        }
    }

    func showUserOnMap(_ user: AppUser) {
        pendingMapFocusUser = user
    }

    func consumePendingMapFocus() {
        pendingMapFocusUser = nil
    }

    func consumePendingChatNavigation() {
        pendingChatNavigationUser = nil
    }

    func consumePendingInviteSearch() {
        pendingInviteSearchUsername = nil
        pendingInviteShouldAutoSend = false
    }

    func handleIncomingURL(_ url: URL) async {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "caller",
              components.host == "invite",
              let usernameValue = components.queryItems?.first(where: { $0.name == "username" })?.value else {
            return
        }

        let normalizedUsername = UsernameValidator.normalized(usernameValue)
        guard !normalizedUsername.isEmpty else { return }

        guard currentUser != nil, !isRestoringSession, !requiresUsernameSetup else {
            deferredInviteUsername = normalizedUsername
            return
        }

        pendingInviteSearchUsername = normalizedUsername
        pendingInviteShouldAutoSend = true
    }

    func makeChatViewModel(for user: AppUser) -> ChatViewModel? {
        guard let currentUser else { return nil }
        return ChatViewModel(
            currentUser: currentUser,
            participant: user,
            chatService: environment.chatService,
            onAppear: { [weak self] in
                self?.activeChatUserID = user.id
                self?.unreadMessageCounts[user.id] = 0
                self?.previousUnreadMessageCounts[user.id] = 0
            },
            onDisappear: { [weak self] in
                guard self?.activeChatUserID == user.id else { return }
                self?.activeChatUserID = nil
            }
        )
    }

    func enableLocationSharing() async {
        let granted = await environment.locationService.requestLocationAccess()
        if !granted {
            callError = .general(environment.permissionService.deniedMessage(for: .location))
        }
    }

    func saveUsername(_ username: String) async -> UsernameSaveResult {
        guard let currentUser else { return .alertError }

        do {
            let updatedUser = try await environment.contactService.updateUsername(username, for: currentUser)
            self.currentUser = updatedUser
            startBackgroundSessionServices(for: updatedUser)
            await loadSocialData()
            processDeferredInviteIfNeeded()
            return .success
        } catch let error as ContactServiceError {
            switch error {
            case .usernameTaken:
                return .inlineError(error.localizedDescription)
            case .usernameUpdateFailed:
                callError = .general(error.localizedDescription)
                return .alertError
            case .avatarUploadUnavailable:
                callError = .general(error.localizedDescription)
                return .alertError
            }
        } catch {
            callError = .general(error.localizedDescription)
            return .alertError
        }
    }

    func searchUser(by username: String) async -> AppUser? {
        do {
            return try await environment.contactService.searchUser(username: username)
        } catch {
            callError = .general("Не удалось найти пользователя.")
            return nil
        }
    }

    func updateAvatar(imageData: Data) async {
        guard let currentUser else { return }

        do {
            let updatedUser = try await environment.contactService.updateAvatar(imageData: imageData, for: currentUser)
            self.currentUser = updatedUser
        } catch {
            callError = .general(error.localizedDescription)
        }
    }

    private func bootstrapSession() async {
        isRestoringSession = true
        await synchronizeCurrentUserProfile()
        isRestoringSession = false
        guard let currentUser else { return }
        guard !requiresUsernameSetup else { return }
        startBackgroundSessionServices(for: currentUser)
        processDeferredInviteIfNeeded()
    }

    private func observeUnreadCounts(for contacts: [AppUser], currentUser: AppUser) {
        let contactIDs = Set(contacts.map(\.id))

        for removedUserID in conversationObservationTasks.keys.filter({ !contactIDs.contains($0) }) {
            conversationObservationTasks[removedUserID]?.cancel()
            conversationObservationTasks[removedUserID] = nil
            unreadMessageCounts[removedUserID] = nil
            previousUnreadMessageCounts[removedUserID] = nil
            initializedUnreadUsers.remove(removedUserID)
        }

        for contact in contacts where conversationObservationTasks[contact.id] == nil {
            conversationObservationTasks[contact.id] = Task { [weak self] in
                guard let self else { return }

                for await messages in environment.chatService.observeMessages(with: contact, currentUser: currentUser) {
                    if Task.isCancelled {
                        break
                    }

                    let unreadCount = messages.filter { $0.isUnreadIncoming(for: currentUser.id) }.count
                    handleUnreadCountUpdate(
                        unreadCount,
                        latestMessage: messages.last,
                        for: contact
                    )
                }
            }
        }
    }

    private func handleUnreadCountUpdate(_ unreadCount: Int, latestMessage: ChatMessage?, for user: AppUser) {
        _ = latestMessage
        unreadMessageCounts[user.id] = unreadCount
        previousUnreadMessageCounts[user.id] = unreadCount
        initializedUnreadUsers.insert(user.id)
    }

    private func bind() {
        environment.callService.activeCallPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.activeCall = $0 }
            .store(in: &subscriptions)

        environment.callService.incomingCallPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] call in
                guard let self else { return }
                self.incomingCall = call

                guard let call else {
                    self.notifiedIncomingCallID = nil
                    return
                }

                guard self.notifiedIncomingCallID != call.id else { return }
                self.notifiedIncomingCallID = call.id
            }
            .store(in: &subscriptions)

        environment.callService.errorPublisher
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.callError = $0 }
            .store(in: &subscriptions)

        environment.callService.localVideoTrackPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.localVideoTrack = $0 }
            .store(in: &subscriptions)

        environment.callService.remoteVideoTrackPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.remoteVideoTrack = $0 }
            .store(in: &subscriptions)
    }

    private func observeSystemCallEvents() {
        systemCallEventsTask?.cancel()
        systemCallEventsTask = Task { [weak self] in
            guard let self else { return }

            for await event in SystemCallService.shared.events {
                if Task.isCancelled {
                    break
                }

                await handleSystemCallEvent(event)
            }
        }
    }

    private func observeLocationUpdates() {
        locationObservationTask?.cancel()
        locationObservationTask = Task { [weak self] in
            guard let self else { return }

            for await location in environment.locationService.observeCurrentLocation() {
                if Task.isCancelled {
                    break
                }

                currentLocation = location
            }
        }
    }

    private func observeNotificationEvents() {
        notificationEventsTask?.cancel()
        notificationEventsTask = Task { [weak self] in
            guard let self else { return }

            for await event in environment.notificationService.events {
                if Task.isCancelled {
                    break
                }

                await handleNotificationEvent(event)
            }
        }
    }

    @MainActor
    private func handleSystemCallEvent(_ event: SystemCallEvent) async {
        switch event {
        case .incomingPush(let payload):
            environment.callService.prepareIncomingCall(from: payload)
        case .answerRequested(let callID):
            guard let currentUser else { return }
            await environment.callService.answerIncomingCallIfPossible(callID: callID, currentUser: currentUser)
        case .endRequested(let callID):
            guard let currentUser else { return }
            await environment.callService.endCall(callID: callID, currentUser: currentUser)
        }
    }

    @MainActor
    private func handleNotificationEvent(_ event: NotificationEvent) async {
        switch event {
        case .openChat(let userID):
            let user: AppUser?
            if let contact = contacts.first(where: { $0.id == userID }) {
                user = contact
            } else {
                user = try? await environment.contactService.fetchUser(id: userID)
            }
            guard let user else { return }
            pendingChatNavigationUser = user
        case .openIncomingCall(let payload):
            environment.callService.prepareIncomingCall(from: payload)
        }
    }

    private func restoreSessionIfNeeded() {
        guard let user = environment.authService.currentUser else { return }
        currentUser = user
        isRestoringSession = true

        Task {
            await bootstrapSession()
        }
    }

    private func loadSocialData() async {
        await loadContacts()
        await loadFriendRequests()
        await loadOutgoingFriendRequests()
    }

    private func observeContacts(currentUser: AppUser) {
        contactsObservationTask?.cancel()
        contactsObservationTask = Task { [weak self] in
            guard let self else { return }

            for await contacts in environment.contactService.observeContacts() {
                if Task.isCancelled {
                    break
                }

                self.contacts = contacts
                observeUnreadCounts(for: contacts, currentUser: currentUser)
                Task {
                    await self.environment.locationService.updateFriends(contacts)
                }
            }
        }
    }

    private func observeIncomingFriendRequests() {
        incomingRequestsObservationTask?.cancel()
        incomingRequestsObservationTask = Task { [weak self] in
            guard let self else { return }

            for await requests in environment.friendService.observeIncomingRequests() {
                if Task.isCancelled {
                    break
                }

                incomingFriendRequests = requests
            }
        }
    }

    private func observeOutgoingFriendRequests() {
        outgoingRequestsObservationTask?.cancel()
        outgoingRequestsObservationTask = Task { [weak self] in
            guard let self else { return }

            for await requests in environment.friendService.observeOutgoingRequests() {
                if Task.isCancelled {
                    break
                }

                outgoingFriendRequests = requests
            }
        }
    }

    private func loadOutgoingFriendRequests() async {
        do {
            outgoingFriendRequests = try await environment.friendService.fetchOutgoingRequests()
        } catch {
            callError = .general("Не удалось загрузить исходящие запросы.")
        }
    }

    private func synchronizeCurrentUserProfile() async {
        guard let currentUser else { return }
        if let profile = try? await environment.contactService.fetchUser(id: currentUser.id) {
            self.currentUser = profile
        }
    }

    private func startBackgroundSessionServices(for currentUser: AppUser) {
        Task { [weak self] in
            guard let self else { return }
            await self.environment.notificationService.updateCurrentUser(currentUser)
            await SystemCallService.shared.updateCurrentUser(currentUser)
            await self.environment.locationService.updateCurrentUser(currentUser)
            await self.environment.callService.connect(currentUser: currentUser)
            await MainActor.run {
                self.observeContacts(currentUser: currentUser)
                self.observeIncomingFriendRequests()
                self.observeOutgoingFriendRequests()
            }
        }
    }

    private func processDeferredInviteIfNeeded() {
        guard let deferredInviteUsername else { return }
        pendingInviteSearchUsername = deferredInviteUsername
        pendingInviteShouldAutoSend = true
        self.deferredInviteUsername = nil
    }
}

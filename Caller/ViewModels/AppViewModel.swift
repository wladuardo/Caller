import Combine
import Foundation
import WebRTC

@MainActor
final class AppViewModel: ObservableObject {
    @Published private(set) var currentUser: AppUser?
    @Published private(set) var contacts: [AppUser] = []
    @Published private(set) var incomingFriendRequests: [FriendRequest] = []
    @Published private(set) var outgoingFriendRequests: [OutgoingFriendRequest] = []
    @Published private(set) var activeCall: CallSession?
    @Published private(set) var incomingCall: CallSession?
    @Published private(set) var localVideoTrack: RTCVideoTrack?
    @Published private(set) var remoteVideoTrack: RTCVideoTrack?
    @Published private(set) var unreadMessageCounts: [String: Int] = [:]
    @Published var chatBanner: ChatBanner?
    @Published var callError: CallError?
    @Published var isLoading = false
    @Published private(set) var isRestoringSession = false

    var requiresUsernameSetup: Bool {
        guard let username = currentUser?.username else { return true }
        return username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private let environment: AppEnvironment
    private var subscriptions = Set<AnyCancellable>()
    private var conversationObservationTasks: [String: Task<Void, Never>] = [:]
    private var incomingRequestsObservationTask: Task<Void, Never>?
    private var outgoingRequestsObservationTask: Task<Void, Never>?
    private var previousUnreadMessageCounts: [String: Int] = [:]
    private var activeChatUserID: String?
    private var initializedUnreadUsers = Set<String>()
    private var notifiedIncomingCallID: UUID?

    init(environment: AppEnvironment) {
        self.environment = environment
        bind()
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
        await environment.authService.signOut()
        environment.signalingService.disconnect()
        resetSessionState()
    }

    func deleteAccount() async {
        do {
            try await environment.authService.deleteAccount()
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
        chatBanner = nil
        previousUnreadMessageCounts = [:]
        initializedUnreadUsers = []
        activeChatUserID = nil
        notifiedIncomingCallID = nil
        isRestoringSession = false
        incomingRequestsObservationTask?.cancel()
        incomingRequestsObservationTask = nil
        outgoingRequestsObservationTask?.cancel()
        outgoingRequestsObservationTask = nil
        conversationObservationTasks.values.forEach { $0.cancel() }
        conversationObservationTasks.removeAll()
    }

    func loadContacts() async {
        do {
            contacts = try await environment.contactService.fetchContacts()
            if let currentUser {
                observeUnreadCounts(for: contacts, currentUser: currentUser)
            }
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
            await loadSocialData()
        } catch {
            callError = .general("Не удалось отправить запрос в друзья.")
        }
    }

    func acceptFriendRequest(from user: AppUser) async {
        do {
            try await environment.friendService.acceptFriendRequest(from: user)
            await loadSocialData()
        } catch {
            callError = .general("Не удалось принять запрос в друзья.")
        }
    }

    func declineFriendRequest(from user: AppUser) async {
        do {
            try await environment.friendService.declineFriendRequest(from: user)
            await loadSocialData()
        } catch {
            callError = .general("Не удалось отклонить запрос в друзья.")
        }
    }

    func cancelOutgoingFriendRequest(to user: AppUser) async {
        do {
            try await environment.friendService.cancelOutgoingRequest(to: user)
            await loadSocialData()
        } catch {
            callError = .general("Не удалось отменить исходящий запрос.")
        }
    }

    func removeFriend(_ user: AppUser) async {
        do {
            try await environment.friendService.removeFriend(user)
            await loadSocialData()
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

    func dismissChatBanner() {
        chatBanner = nil
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

    func saveUsername(_ username: String) async -> Bool {
        guard let currentUser else { return false }

        do {
            let updatedUser = try await environment.contactService.updateUsername(username, for: currentUser)
            self.currentUser = updatedUser
            await loadSocialData()
            return true
        } catch {
            callError = .general(error.localizedDescription)
        }

        return false
    }

    func searchUser(by username: String) async -> AppUser? {
        do {
            return try await environment.contactService.searchUser(username: username)
        } catch {
            callError = .general("Не удалось найти пользователя.")
            return nil
        }
    }

    private func bootstrapSession() async {
        isRestoringSession = true
        defer { isRestoringSession = false }
        await synchronizeCurrentUserProfile()
        guard let currentUser else { return }
        await environment.callService.connect(currentUser: currentUser)
        observeIncomingFriendRequests()
        observeOutgoingFriendRequests()
        guard !requiresUsernameSetup else { return }
        await loadSocialData()
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
        let previousUnreadCount = previousUnreadMessageCounts[user.id] ?? 0
        let shouldNotify = initializedUnreadUsers.contains(user.id) &&
            unreadCount > previousUnreadCount &&
            latestMessage?.senderID == user.id &&
            activeChatUserID != user.id

        unreadMessageCounts[user.id] = unreadCount
        previousUnreadMessageCounts[user.id] = unreadCount
        initializedUnreadUsers.insert(user.id)

        if shouldNotify {
            let messageText = latestMessage?.text ?? "New message"
            environment.notificationService.notifyIncomingMessage(
                from: user.displayName,
                message: messageText
            )
            presentChatBanner(
                title: user.displayName,
                message: messageText
            )
        }
    }

    private func userDisplayName(for userID: String) -> String {
        if let user = contacts.first(where: { $0.id == userID }) {
            return user.displayName
        }
        if let request = incomingFriendRequests.first(where: { $0.fromUser.id == userID }) {
            return request.fromUser.displayName
        }
        return "New Message"
    }

    private func presentChatBanner(title: String, message: String) {
        let banner = ChatBanner(title: title, message: message)
        chatBanner = banner

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard self?.chatBanner?.id == banner.id else { return }
            self?.chatBanner = nil
        }
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
                self.environment.notificationService.notifyIncomingCall(
                    from: call.participant.name,
                    type: call.type
                )
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
}

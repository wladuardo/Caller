import SwiftUI

struct ContactsView: View {
    @ObservedObject private var appViewModel: AppViewModel
    @Binding var isBottomBarHidden: Bool
    @State private var viewModel: ContactsViewModel

    init(viewModel: AppViewModel, isBottomBarHidden: Binding<Bool>) {
        _appViewModel = ObservedObject(wrappedValue: viewModel)
        _isBottomBarHidden = isBottomBarHidden
        _viewModel = State(
            initialValue: ContactsViewModel(
                dependencies: .init(
                    loadContacts: { await viewModel.loadContacts() },
                    loadFriendRequests: { await viewModel.loadFriendRequests() },
                    consumePendingChatNavigation: { viewModel.consumePendingChatNavigation() },
                    acceptFriendRequest: { user in await viewModel.acceptFriendRequest(from: user) },
                    declineFriendRequest: { user in await viewModel.declineFriendRequest(from: user) },
                    cancelOutgoingFriendRequest: { user in await viewModel.cancelOutgoingFriendRequest(to: user) },
                    startCall: { user, type in await viewModel.startCall(with: user, type: type) },
                    setNotificationsMuted: { isMuted, user in
                        await viewModel.setNotificationsMuted(isMuted, for: user)
                    },
                    removeFriend: { user in await viewModel.removeFriend(user) },
                    showUserOnMap: { user in viewModel.showUserOnMap(user) }
                )
            )
        )
    }

    var body: some View {
        NavigationStack(
            path: Binding(
                get: { viewModel.state.navigationPath },
                set: { navigationPath in
                    send(.setNavigationPath(navigationPath))
                }
            )
        ) {
            mainContent
            .safeAreaInset(edge: .top) {
                HStack {
                    Spacer()
                    searchButton
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            .refreshable {
                await viewModel.trigger(.refresh)
            }
            .navigationDestination(for: ContactsRoute.self) { route in
                destination(for: route)
            }
            .navigationDestination(
                isPresented: Binding(
                    get: { viewModel.state.isShowingSearch },
                    set: { isPresented in
                        send(.setSearchPresented(isPresented))
                    }
                )
            ) {
                UserSearchView(viewModel: appViewModel)
            }
        }
        .toolbar(
            (viewModel.state.navigationPath.isEmpty && !viewModel.state.isShowingSearch) ? .visible : .hidden,
            for: .tabBar
        )
        .onAppear {
            syncFromAppViewModel()
            send(.onAppear)
            updateBottomBarVisibility()
        }
        .onDisappear {
            isBottomBarHidden = false
        }
        .onChange(of: appViewModel.contacts) { _, _ in
            syncFromAppViewModel()
        }
        .onChange(of: appViewModel.incomingFriendRequests) { _, _ in
            syncFromAppViewModel()
        }
        .onChange(of: appViewModel.outgoingFriendRequests) { _, _ in
            syncFromAppViewModel()
        }
        .onChange(of: appViewModel.unreadMessageCounts) { _, _ in
            syncFromAppViewModel()
        }
        .onChange(of: appViewModel.pendingChatNavigationUser) { _, _ in
            syncFromAppViewModel()
        }
        .onChange(of: appViewModel.pendingInviteSearchUsername) { _, _ in
            syncFromAppViewModel()
        }
        .onChange(of: viewModel.state.pendingChatNavigationUser?.id) { _, userID in
            guard userID != nil else { return }
            send(.tapPendingChatNavigation)
        }
        .onChange(of: viewModel.state.pendingInviteSearchUsername) { _, username in
            guard username != nil else { return }
            send(.tapPendingInviteSearch)
        }
        .onChange(of: viewModel.state.navigationPath) { _, _ in
            updateBottomBarVisibility()
        }
        .onChange(of: viewModel.state.isShowingSearch) { _, _ in
            updateBottomBarVisibility()
        }
    }

    private var mainContent: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.08, green: 0.09, blue: 0.14)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            contentScrollView
        }
    }

    private func updateBottomBarVisibility() {
        isBottomBarHidden = !(viewModel.state.navigationPath.isEmpty && !viewModel.state.isShowingSearch)
    }

    private var searchButton: some View {
        Button {
            send(.tapSearch)
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .callerGlassButtonSurface(cornerRadius: 999, tint: .blue)
                .shadow(color: .black.opacity(0.2), radius: 12, y: 8)
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3.bold())
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func emptyState(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .callerGlassCard(cornerRadius: 18, tint: .cyan)
    }

    private var contentScrollView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                incomingRequestsSection
                outgoingRequestsSection
                contactsSection
            }
            .padding(20)
        }
    }

    @ViewBuilder
    private var incomingRequestsSection: some View {
        if !viewModel.state.incomingFriendRequests.isEmpty {
            sectionHeader("Запросы", subtitle: "Ответьте на новые заявки в друзья.")
            LazyVStack(spacing: 14) {
                ForEach(viewModel.state.incomingFriendRequests) { request in
                    incomingRequestRow(for: request)
                }
            }
        }
    }

    @ViewBuilder
    private var outgoingRequestsSection: some View {
        if !viewModel.state.outgoingFriendRequests.isEmpty {
            sectionHeader("Отправленные", subtitle: "Ожидают подтверждения от других пользователей.")
            LazyVStack(spacing: 14) {
                ForEach(viewModel.state.outgoingFriendRequests) { request in
                    outgoingRequestRow(for: request)
                }
            }
        }
    }

    private var contactsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Друзья", subtitle: "Общайтесь в чате или начинайте звонок.")

            if viewModel.state.contacts.isEmpty {
                emptyState("Друзей пока нет. Найдите пользователя по никнейму и отправьте ему запрос в друзья.")
            } else {
                LazyVStack(spacing: 14) {
                    ForEach(viewModel.state.contacts) { contact in
                        contactRow(for: contact)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func destination(for route: ContactsRoute) -> some View {
        switch route {
        case .chat(let user):
            if let chatViewModel = appViewModel.makeChatViewModel(for: user) {
                ChatView(
                    viewModel: chatViewModel,
                    unreadMessageCount: viewModel.state.unreadMessageCounts[user.id] ?? 0,
                    isNotificationsMuted: appViewModel.isNotificationsMuted(for: user),
                    onStartAudioCall: {
                        send(.startCall(user, .audio))
                    },
                    onStartVideoCall: {
                        send(.startCall(user, .video))
                    },
                    onShowOnMap: {
                        send(.showUserOnMap(user))
                    },
                    onSetNotificationsMuted: { isMuted in
                        await viewModel.trigger(.setNotificationsMuted(isMuted, user))
                    },
                    onRemoveFriend: {
                        await viewModel.trigger(.removeFriend(user))
                        await viewModel.trigger(.removeRoutes(for: user))
                    }
                )
            }
        case .details(let user):
            FriendDetailsView(
                user: user,
                unreadMessageCount: viewModel.state.unreadMessageCounts[user.id] ?? 0,
                isNotificationsMuted: appViewModel.isNotificationsMuted(for: user),
                onOpenChat: {
                    send(.tapOpenChat(user))
                },
                onStartAudioCall: {
                    send(.startCall(user, .audio))
                },
                onStartVideoCall: {
                    send(.startCall(user, .video))
                },
                onShowOnMap: {
                    send(.showUserOnMap(user))
                },
                onSetNotificationsMuted: { isMuted in
                    await viewModel.trigger(.setNotificationsMuted(isMuted, user))
                },
                onRemoveFriend: {
                    await viewModel.trigger(.removeFriend(user))
                    await viewModel.trigger(.removeRoutes(for: user))
                }
            )
        }
    }

    private func contactRow(for contact: AppUser) -> some View {
        let unreadCount = viewModel.state.unreadMessageCounts[contact.id] ?? 0

        return ContactRow(
            user: contact,
            unreadMessageCount: unreadCount,
            onDetailsTap: { send(.tapOpenDetails(contact)) },
            onChatTap: { send(.tapOpenChat(contact)) },
            onAudioTap: { send(.startCall(contact, .audio)) },
            onVideoTap: { send(.startCall(contact, .video)) }
        )
    }

    private func incomingRequestRow(for request: FriendRequest) -> some View {
        FriendRequestRow(
            request: request,
            onAccept: { send(.acceptFriendRequest(request.fromUser)) },
            onDecline: { send(.declineFriendRequest(request.fromUser)) }
        )
    }

    private func outgoingRequestRow(for request: OutgoingFriendRequest) -> some View {
        OutgoingFriendRequestRow(
            request: request,
            onCancel: {
                send(.cancelOutgoingFriendRequest(request.toUser))
            }
        )
    }

    private func statPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.headline.weight(.bold))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .callerGlassCard(cornerRadius: 16, tint: .cyan)
    }

    private func syncFromAppViewModel() {
        let externalState = ContactsViewModel.ExternalState(
            contacts: appViewModel.contacts,
            incomingFriendRequests: appViewModel.incomingFriendRequests,
            outgoingFriendRequests: appViewModel.outgoingFriendRequests,
            unreadMessageCounts: appViewModel.unreadMessageCounts,
            pendingChatNavigationUser: appViewModel.pendingChatNavigationUser,
            pendingInviteSearchUsername: appViewModel.pendingInviteSearchUsername
        )
        send(.syncExternalState(externalState))
    }

    private func send(_ input: ContactsViewModel.Input) {
        Task {
            await viewModel.trigger(input)
        }
    }
}

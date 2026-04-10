import SwiftUI

private enum ContactsRoute: Hashable {
    case chat(AppUser)
    case details(AppUser)
}

struct ContactsView: View {
    @ObservedObject var viewModel: AppViewModel
    @Binding var isBottomBarHidden: Bool
    @State private var navigationPath: [ContactsRoute] = []
    @State private var isShowingSearch = false

    var body: some View {
        NavigationStack(path: $navigationPath) {
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
                await viewModel.loadContacts()
                await viewModel.loadFriendRequests()
            }
            .navigationDestination(for: ContactsRoute.self) { route in
                destination(for: route)
            }
            .navigationDestination(isPresented: $isShowingSearch) {
                UserSearchView(viewModel: viewModel)
            }
        }
        .toolbar((navigationPath.isEmpty && !isShowingSearch) ? .visible : .hidden, for: .tabBar)
        .onAppear {
            updateBottomBarVisibility()
            navigateToPendingChatIfNeeded()
            presentSearchIfNeeded()
        }
        .onDisappear {
            isBottomBarHidden = false
        }
        .onChange(of: viewModel.pendingChatNavigationUser?.id) { _, userID in
            guard userID != nil else { return }
            navigateToPendingChatIfNeeded()
        }
        .onChange(of: viewModel.pendingInviteSearchUsername) { _, username in
            guard username != nil else { return }
            presentSearchIfNeeded()
        }
        .onChange(of: navigationPath) { _, _ in
            updateBottomBarVisibility()
        }
        .onChange(of: isShowingSearch) { _, _ in
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

    private func navigateToPendingChatIfNeeded() {
        guard let user = viewModel.pendingChatNavigationUser,
              navigationPath.last != .chat(user) else {
            return
        }

        navigationPath = [.chat(user)]
        viewModel.consumePendingChatNavigation()
    }

    private func presentSearchIfNeeded() {
        guard viewModel.pendingInviteSearchUsername != nil else { return }
        isShowingSearch = true
    }

    private func updateBottomBarVisibility() {
        isBottomBarHidden = !(navigationPath.isEmpty && !isShowingSearch)
    }

    private var searchButton: some View {
        Button {
            isShowingSearch = true
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
        if !viewModel.incomingFriendRequests.isEmpty {
            sectionHeader("Запросы", subtitle: "Ответьте на новые заявки в друзья.")
            LazyVStack(spacing: 14) {
                ForEach(viewModel.incomingFriendRequests) { request in
                    incomingRequestRow(for: request)
                }
            }
        }
    }

    @ViewBuilder
    private var outgoingRequestsSection: some View {
        if !viewModel.outgoingFriendRequests.isEmpty {
            sectionHeader("Отправленные", subtitle: "Ожидают подтверждения от других пользователей.")
            LazyVStack(spacing: 14) {
                ForEach(viewModel.outgoingFriendRequests) { request in
                    outgoingRequestRow(for: request)
                }
            }
        }
    }

    private var contactsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Друзья", subtitle: "Общайтесь в чате или начинайте звонок.")

            if viewModel.contacts.isEmpty {
                emptyState("Друзей пока нет. Найдите пользователя по никнейму и отправьте ему запрос в друзья.")
            } else {
                LazyVStack(spacing: 14) {
                    ForEach(viewModel.contacts) { contact in
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
            if let chatViewModel = viewModel.makeChatViewModel(for: user) {
                ChatView(
                    viewModel: chatViewModel,
                    unreadMessageCount: viewModel.unreadMessageCounts[user.id] ?? 0,
                    isNotificationsMuted: viewModel.isNotificationsMuted(for: user),
                    onStartAudioCall: {
                        Task { await viewModel.startCall(with: user, type: .audio) }
                    },
                    onStartVideoCall: {
                        Task { await viewModel.startCall(with: user, type: .video) }
                    },
                    onShowOnMap: {
                        viewModel.showUserOnMap(user)
                    },
                    onSetNotificationsMuted: { isMuted in
                        await viewModel.setNotificationsMuted(isMuted, for: user)
                    },
                    onRemoveFriend: {
                        await viewModel.removeFriend(user)
                        await MainActor.run {
                            navigationPath.removeAll { route in
                                switch route {
                                case .chat(let routeUser), .details(let routeUser):
                                    return routeUser.id == user.id
                                }
                            }
                        }
                    }
                )
            }
        case .details(let user):
            FriendDetailsView(
                user: user,
                unreadMessageCount: viewModel.unreadMessageCounts[user.id] ?? 0,
                isNotificationsMuted: viewModel.isNotificationsMuted(for: user),
                onOpenChat: {
                    navigationPath.append(.chat(user))
                },
                onStartAudioCall: {
                    Task { await viewModel.startCall(with: user, type: .audio) }
                },
                onStartVideoCall: {
                    Task { await viewModel.startCall(with: user, type: .video) }
                },
                onShowOnMap: {
                    viewModel.showUserOnMap(user)
                },
                onSetNotificationsMuted: { isMuted in
                    await viewModel.setNotificationsMuted(isMuted, for: user)
                },
                onRemoveFriend: {
                    await viewModel.removeFriend(user)
                    await MainActor.run {
                        navigationPath.removeAll { route in
                            if case .details(let routeUser) = route {
                                return routeUser.id == user.id
                            }
                            return false
                        }
                    }
                }
            )
        }
    }

    private func contactRow(for contact: AppUser) -> some View {
        let unreadCount = viewModel.unreadMessageCounts[contact.id] ?? 0

        return ContactRow(
            user: contact,
            unreadMessageCount: unreadCount,
            onDetailsTap: { navigationPath.append(.details(contact)) },
            onChatTap: { navigationPath.append(.chat(contact)) },
            onAudioTap: { Task { await viewModel.startCall(with: contact, type: .audio) } },
            onVideoTap: { Task { await viewModel.startCall(with: contact, type: .video) } }
        )
    }

    private func incomingRequestRow(for request: FriendRequest) -> some View {
        FriendRequestRow(
            request: request,
            onAccept: { Task { await viewModel.acceptFriendRequest(from: request.fromUser) } },
            onDecline: { Task { await viewModel.declineFriendRequest(from: request.fromUser) } }
        )
    }

    private func outgoingRequestRow(for request: OutgoingFriendRequest) -> some View {
        OutgoingFriendRequestRow(
            request: request,
            onCancel: {
                Task { await viewModel.cancelOutgoingFriendRequest(to: request.toUser) }
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
}

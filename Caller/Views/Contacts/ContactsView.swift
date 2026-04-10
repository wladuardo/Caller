import SwiftUI

private enum ContactsRoute: Hashable {
    case chat(AppUser)
    case details(AppUser)
}

struct ContactsView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var navigationPath: [ContactsRoute] = []

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                LinearGradient(
                    colors: [Color.black, Color(red: 0.08, green: 0.09, blue: 0.14)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if !viewModel.incomingFriendRequests.isEmpty {
                            sectionHeader("Запросы", subtitle: "Ответьте на новые заявки в друзья.")
                            LazyVStack(spacing: 14) {
                                ForEach(viewModel.incomingFriendRequests) { request in
                                    FriendRequestRow(
                                        request: request,
                                        onAccept: { Task { await viewModel.acceptFriendRequest(from: request.fromUser) } },
                                        onDecline: { Task { await viewModel.declineFriendRequest(from: request.fromUser) } }
                                    )
                                }
                            }
                        }

                        if !viewModel.outgoingFriendRequests.isEmpty {
                            sectionHeader("Отправленные", subtitle: "Ожидают подтверждения от других пользователей.")
                            LazyVStack(spacing: 14) {
                                ForEach(viewModel.outgoingFriendRequests) { request in
                                    OutgoingFriendRequestRow(
                                        request: request,
                                        onCancel: {
                                            Task { await viewModel.cancelOutgoingFriendRequest(to: request.toUser) }
                                        }
                                    )
                                }
                            }
                        }

                        sectionHeader("Друзья", subtitle: "Общайтесь в чате или начинайте звонок.")
                        
                        if viewModel.contacts.isEmpty {
                            emptyState("Друзей пока нет. Найдите пользователя по никнейму и отправьте ему запрос в друзья.")
                        } else {
                            LazyVStack(spacing: 14) {
                                ForEach(viewModel.contacts) { contact in
                                    ContactRow(
                                        user: contact,
                                        unreadMessageCount: viewModel.unreadMessageCounts[contact.id] ?? 0,
                                        onDetailsTap: { navigationPath.append(.details(contact)) },
                                        onChatTap: { navigationPath.append(.chat(contact)) },
                                        onAudioTap: { Task { await viewModel.startCall(with: contact, type: .audio) } },
                                        onVideoTap: { Task { await viewModel.startCall(with: contact, type: .video) } }
                                    )
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .refreshable {
                await viewModel.loadContacts()
                await viewModel.loadFriendRequests()
            }
            .navigationDestination(for: ContactsRoute.self) { route in
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
        }
        .toolbar(navigationPath.isEmpty ? .visible : .hidden, for: .tabBar)
        .onAppear {
            navigateToPendingChatIfNeeded()
        }
        .onChange(of: viewModel.pendingChatNavigationUser?.id) { _, userID in
            guard userID != nil else { return }
            navigateToPendingChatIfNeeded()
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

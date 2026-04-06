import SwiftUI

private enum ContactsRoute: Hashable {
    case chat(AppUser)
    case details(AppUser)
}

struct ContactsView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var navigationPath: [ContactsRoute] = []
    @State private var isShowingSearch = false
    @State private var hasAppeared = false

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
                                .offset(y: hasAppeared ? 0 : 16)
                                .opacity(hasAppeared ? 1 : 0)
                                .transition(.move(edge: .top).combined(with: .opacity))
                            LazyVStack(spacing: 14) {
                                ForEach(viewModel.incomingFriendRequests) { request in
                                    FriendRequestRow(
                                        request: request,
                                        onAccept: { Task { await viewModel.acceptFriendRequest(from: request.fromUser) } },
                                        onDecline: { Task { await viewModel.declineFriendRequest(from: request.fromUser) } }
                                    )
                                    .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
                                    .scrollTransition(axis: .vertical) { content, phase in
                                        content
                                            .scaleEffect(phase.isIdentity ? 1 : 0.97)
                                            .opacity(phase.isIdentity ? 1 : 0.7)
                                    }
                                }
                            }
                            .contentTransition(.identity)
                        }

                        if !viewModel.outgoingFriendRequests.isEmpty {
                            sectionHeader("Отправленные", subtitle: "Ожидают подтверждения от других пользователей.")
                                .offset(y: hasAppeared ? 0 : 16)
                                .opacity(hasAppeared ? 1 : 0)
                                .transition(.move(edge: .top).combined(with: .opacity))
                            LazyVStack(spacing: 14) {
                                ForEach(viewModel.outgoingFriendRequests) { request in
                                    OutgoingFriendRequestRow(
                                        request: request,
                                        onCancel: {
                                            Task { await viewModel.cancelOutgoingFriendRequest(to: request.toUser) }
                                        }
                                    )
                                    .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
                                    .scrollTransition(axis: .vertical) { content, phase in
                                        content
                                            .scaleEffect(phase.isIdentity ? 1 : 0.97)
                                            .opacity(phase.isIdentity ? 1 : 0.7)
                                    }
                                }
                            }
                            .contentTransition(.identity)
                        }

                        sectionHeader("Друзья", subtitle: "Общайтесь в чате или начинайте звонок.")
                            .offset(y: hasAppeared ? 0 : 22)
                            .opacity(hasAppeared ? 1 : 0)
                        
                        if viewModel.contacts.isEmpty {
                            emptyState("Друзей пока нет. Найдите пользователя по никнейму и отправьте ему запрос в друзья.")
                                .transition(.opacity.combined(with: .scale(scale: 0.96)))
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
                                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                                    .scrollTransition(axis: .vertical) { content, phase in
                                        content
                                            .scaleEffect(phase.isIdentity ? 1 : 0.985)
                                            .opacity(phase.isIdentity ? 1 : 0.78)
                                    }
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .safeAreaInset(edge: .top) {
                HStack {
                    Spacer()
                    searchButton
                        .offset(y: hasAppeared ? 0 : -8)
                        .opacity(hasAppeared ? 1 : 0)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            .refreshable {
                await viewModel.loadContacts()
                await viewModel.loadFriendRequests()
            }
            .navigationDestination(for: ContactsRoute.self) { route in
                switch route {
                case .chat(let user):
                    if let chatViewModel = viewModel.makeChatViewModel(for: user) {
                        ChatView(viewModel: chatViewModel)
                    }
                case .details(let user):
                    FriendDetailsView(
                        user: user,
                        unreadMessageCount: viewModel.unreadMessageCounts[user.id] ?? 0,
                        onOpenChat: {
                            navigationPath.append(.chat(user))
                        },
                        onStartAudioCall: {
                            Task { await viewModel.startCall(with: user, type: .audio) }
                        },
                        onStartVideoCall: {
                            Task { await viewModel.startCall(with: user, type: .video) }
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
            .navigationDestination(isPresented: $isShowingSearch) {
                UserSearchView(viewModel: viewModel)
            }
        }
        .toolbar((navigationPath.isEmpty && !isShowingSearch) ? .visible : .hidden, for: .tabBar)
        .animation(.easeInOut(duration: 0.25), value: navigationPath.isEmpty && !isShowingSearch)
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: viewModel.contacts.map(\.id))
        .animation(.spring(response: 0.36, dampingFraction: 0.84), value: viewModel.incomingFriendRequests.map(\.id))
        .animation(.spring(response: 0.36, dampingFraction: 0.84), value: viewModel.outgoingFriendRequests.map(\.id))
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.84)) {
                hasAppeared = true
            }
        }
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
        Text(message)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
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

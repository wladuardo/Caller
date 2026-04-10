import SwiftUI

enum AppTab: Int, CaseIterable {
    case friends = 0
    case map = 1
    case profile = 2

    var title: String {
        switch self {
        case .friends:
            "Друзья"
        case .map:
            "Карта"
        case .profile:
            "Профиль"
        }
    }

    var systemImage: String {
        switch self {
        case .friends:
            "person.3.fill"
        case .map:
            "map.fill"
        case .profile:
            "gearshape.fill"
        }
    }
}

struct MainTabView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var isShowingDeleteConfirmation = false
    @State private var selectedTab: AppTab = .friends
    @State private var isBottomBarHidden = false

    private let bottomBarHeight: CGFloat = 86

    var body: some View {
        ZStack {
            ContactsView(
                viewModel: viewModel,
                isBottomBarHidden: $isBottomBarHidden
            )
            .opacity(selectedTab == .friends ? 1 : 0)
            .allowsHitTesting(selectedTab == .friends)

            FriendsMapView(
                viewModel: viewModel,
                selectedTab: $selectedTab,
                bottomBarHeight: bottomBarHeight
            )
            .opacity(selectedTab == .map ? 1 : 0)
            .allowsHitTesting(selectedTab == .map)

            if let currentUser = viewModel.currentUser {
                SettingsView(
                    currentUser: currentUser,
                    onUpdateAvatar: { imageData in
                        await viewModel.updateAvatar(imageData: imageData)
                    },
                    onSignOut: {
                        Task { await viewModel.signOut() }
                    },
                    onDeleteAccount: {
                        isShowingDeleteConfirmation = true
                    }
                )
                .opacity(selectedTab == .profile ? 1 : 0)
                .allowsHitTesting(selectedTab == .profile)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !isBottomBarHidden && selectedTab != .map {
                SharedTabBar(selectedTab: $selectedTab)
                    .padding(.horizontal, 12)
            }
        }
        .onChange(of: viewModel.pendingChatNavigationUser?.id) { _, userID in
            guard userID != nil else { return }
            selectedTab = .friends
        }
        .onChange(of: viewModel.pendingInviteSearchUsername) { _, username in
            guard username != nil else { return }
            selectedTab = .friends
        }
        .onChange(of: viewModel.pendingMapFocusUser?.id) { _, userID in
            guard userID != nil else { return }
            selectedTab = .map
        }
        .onChange(of: selectedTab) { _, tab in
            guard tab != .friends else { return }
            isBottomBarHidden = false
        }
        .alert("Удалить аккаунт?", isPresented: $isShowingDeleteConfirmation) {
            Button("Отмена", role: .cancel) {}
            Button("Удалить", role: .destructive) {
                Task { await viewModel.deleteAccount() }
            }
        } message: {
            Text("Это удалит текущий аккаунт. Если Firebase потребует недавнюю авторизацию, войдите снова и повторите попытку.")
        }
    }
}

struct SharedTabBar: View {
    @Binding var selectedTab: AppTab
    @Namespace private var selectionAnimation
    var showsBackground = true

    var body: some View {
        HStack(spacing: 12) {
            ForEach(AppTab.allCases, id: \.rawValue) { tab in
                tabButton(for: tab)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .frame(maxWidth: .infinity)
        .frame(height: 76, alignment: .top)
        .background {
            if showsBackground {
                tabBarBackground
            }
        }
        .shadow(color: .black.opacity(showsBackground ? 0.2 : 0), radius: 20, y: -2)
    }

    private func tabButton(for tab: AppTab) -> some View {
        let isSelected = selectedTab == tab

        return Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                Text(tab.title)
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(isSelected ? .white : .secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background {
                if isSelected {
                    selectionBackground
                        .matchedGeometryEffect(id: "selected-tab-pill", in: selectionAnimation)
                }
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var tabBarBackground: some View {
        if #available(iOS 26.0, *) {
            ZStack {
                Color.clear
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.08),
                                Color.white.opacity(0.04),
                                Color.blue.opacity(0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .glassEffect(.regular.interactive(), in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }
        } else {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                }
        }
    }

    @ViewBuilder
    private var selectionBackground: some View {
        if #available(iOS 26.0, *) {
            Capsule(style: .continuous)
                .fill(Color.clear)
                .glassEffect(.regular.tint(.blue.opacity(0.3)).interactive(), in: Capsule(style: .continuous))
        } else {
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.12))
        }
    }
}

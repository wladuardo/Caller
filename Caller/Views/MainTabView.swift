import SwiftUI

struct MainTabView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var isShowingDeleteConfirmation = false
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            ContactsView(viewModel: viewModel)
                .tag(0)
                .tabItem {
                    Label("Друзья", systemImage: "person.3.fill")
                }

            UserSearchView(viewModel: viewModel)
                .tag(1)
                .tabItem {
                    Label("Поиск", systemImage: "magnifyingglass")
                }

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
                .tag(2)
                .tabItem {
                    Label("Профиль", systemImage: "gearshape.fill")
                }
            }
        }
        .onChange(of: viewModel.pendingChatNavigationUser?.id) { _, userID in
            guard userID != nil else { return }
            selectedTab = 0
        }
        .onChange(of: viewModel.pendingInviteSearchUsername) { _, username in
            guard username != nil else { return }
            selectedTab = 1
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

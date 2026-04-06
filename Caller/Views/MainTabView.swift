import SwiftUI

struct MainTabView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var isShowingDeleteConfirmation = false

    var body: some View {
        TabView {
            ContactsView(viewModel: viewModel)
                .tabItem {
                    Label("Главная", systemImage: "person.3.fill")
                }

            if let currentUser = viewModel.currentUser {
                SettingsView(
                    currentUser: currentUser,
                    onSignOut: {
                        Task { await viewModel.signOut() }
                    },
                    onDeleteAccount: {
                        isShowingDeleteConfirmation = true
                    }
                )
                .tabItem {
                    Label("Настройки", systemImage: "gearshape.fill")
                }
            }
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

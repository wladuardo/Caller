import SwiftUI

struct UserSearchView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var searchQuery = ""
    @State private var searchResult: AppUser?
    @State private var searchMessage: String?
    @State private var isSearching = false
    @State private var hasSearched = false
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.08, green: 0.09, blue: 0.14)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    searchField
                    resultSection
                }
                .padding(20)
            }
        }
        .navigationTitle("Поиск")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            isSearchFocused = true
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Найти пользователя")
                .font(.system(size: 32, weight: .bold, design: .rounded))
            Text("Введите точный никнейм, чтобы найти пользователя и отправить ему запрос в друзья.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var searchField: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                TextField("Введите никнейм", text: $searchQuery)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($isSearchFocused)

                Button("Найти") {
                    search()
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.blue, in: Capsule())
                .buttonStyle(.plain)
                .disabled(isSearching)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )

            if let searchMessage {
                Text(searchMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var resultSection: some View {
        if isSearching {
            HStack {
                Spacer()
                ProgressView()
                    .tint(.white)
                Spacer()
            }
            .padding(.top, 30)
        } else if let searchResult {
            VStack(alignment: .leading, spacing: 12) {
                Text("Результат")
                    .font(.title3.bold())
                DiscoverUserRow(
                    user: searchResult,
                    onAddFriend: {
                        Task {
                            await viewModel.sendFriendRequest(to: searchResult)
                            await MainActor.run {
                                searchMessage = "Запрос в друзья отправлен."
                                self.searchResult = nil
                                hasSearched = false
                            }
                        }
                    }
                )
            }
        } else if hasSearched {
            ContentUnavailableView(
                "Пользователь не найден",
                systemImage: "person.crop.circle.badge.questionmark",
                description: Text("Проверьте никнейм и попробуйте снова.")
            )
            .foregroundStyle(.white.opacity(0.8))
            .padding(.top, 30)
        } else {
            ContentUnavailableView(
                "Введите никнейм",
                systemImage: "magnifyingglass",
                description: Text("Поиск работает только по точному никнейму пользователя.")
            )
            .foregroundStyle(.white.opacity(0.8))
            .padding(.top, 30)
        }
    }

    private func search() {
        let normalizedQuery = UsernameValidator.normalized(searchQuery)

        if let error = UsernameValidator.validate(normalizedQuery) {
            searchMessage = error
            searchResult = nil
            hasSearched = false
            return
        }

        isSearching = true
        searchMessage = nil
        searchResult = nil

        Task {
            let result = await viewModel.searchUser(by: normalizedQuery)
            await MainActor.run {
                isSearching = false
                hasSearched = true
                searchResult = result
                if result == nil {
                    searchMessage = nil
                }
            }
        }
    }
}

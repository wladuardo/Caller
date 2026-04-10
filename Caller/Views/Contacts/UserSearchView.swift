import SwiftUI
import CoreImage.CIFilterBuiltins

struct UserSearchView: View {
    private struct SearchResultState: Equatable {
        let user: AppUser
        var status: DiscoverUserStatus
    }

    @ObservedObject var viewModel: AppViewModel
    @State private var searchQuery = ""
    @State private var searchResult: SearchResultState?
    @State private var searchMessage: String?
    @State private var isSearching = false
    @State private var hasSearched = false
    @FocusState private var isSearchFocused: Bool
    @State private var isShowingQRScanner = false
    @State private var isShowingMyQRCode = false

    private let qrContext = CIContext()
    private let qrFilter = CIFilter.qrCodeGenerator()

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
                    qrActions
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
            handlePendingInviteIfNeeded()
        }
        .onChange(of: viewModel.pendingInviteSearchUsername) { _, username in
            guard username != nil else { return }
            handlePendingInviteIfNeeded()
        }
        .sheet(isPresented: $isShowingQRScanner) {
            NavigationStack {
                ZStack(alignment: .bottom) {
                    QRCodeScannerView(
                        onCodeScanned: handleScannedCode,
                        onFailure: handleScannerFailure
                    )

                    Text("Наведите камеру на QR-код приглашения Caller")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(.bottom, 32)
                }
                .ignoresSafeArea()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Закрыть") {
                            isShowingQRScanner = false
                        }
                    }
                }
            }
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isShowingMyQRCode) {
            qrCodeSheet
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

    private var qrActions: some View {
        HStack(spacing: 12) {
            Button {
                isSearchFocused = false
                isShowingQRScanner = true
            } label: {
                qrActionCard(
                    title: "Сканировать QR",
                    subtitle: "Добавить по коду",
                    systemName: "qrcode.viewfinder",
                    tint: .green
                )
            }
            .buttonStyle(.plain)

            if viewModel.currentUser?.username?.isEmpty == false {
                Button {
                    isSearchFocused = false
                    isShowingMyQRCode = true
                } label: {
                    qrActionCard(
                        title: "Мой QR-код",
                        subtitle: "Показать для сканирования",
                        systemName: "qrcode",
                        tint: .cyan
                    )
                }
                .buttonStyle(.plain)
            }
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
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .callerGlassButtonSurface(cornerRadius: 999, tint: .blue)
                .buttonStyle(.plain)
                .disabled(isSearching)

            }
            .padding(16)
            .callerGlassCard(cornerRadius: 22, tint: .blue)

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
                    user: searchResult.user,
                    status: searchResult.status,
                    onPrimaryAction: {
                        Task {
                            await sendFriendRequest(to: searchResult.user)
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
        search(automaticallySendRequest: false)
    }

    private func search(automaticallySendRequest: Bool) {
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
            let result = await resolveSearchResult(for: normalizedQuery)
            await MainActor.run {
                isSearching = false
                hasSearched = true
                searchResult = result
                if let result, automaticallySendRequest {
                    if result.status == .addable {
                        Task {
                            await sendFriendRequest(to: result.user)
                        }
                    }
                } else if result == nil {
                    searchMessage = nil
                }
            }
        }
    }

    @MainActor
    private func sendFriendRequest(to user: AppUser) async {
        await viewModel.sendFriendRequest(to: user)
        searchMessage = "Запрос в друзья отправлен."
        searchResult = SearchResultState(user: user, status: .outgoingRequest)
        hasSearched = true
    }

    private func handleScannedCode(_ code: String) {
        guard let username = extractUsername(from: code) else {
            handleScannerFailure("Не удалось распознать QR-код Caller.")
            return
        }

        isShowingQRScanner = false
        searchQuery = username
        searchMessage = "Никнейм получен из QR-кода."
        search(automaticallySendRequest: false)
    }

    private func handlePendingInviteIfNeeded() {
        guard let username = viewModel.pendingInviteSearchUsername else { return }
        searchQuery = username
        searchMessage = "Открыта ссылка-приглашение."
        let shouldAutoSend = viewModel.pendingInviteShouldAutoSend
        viewModel.consumePendingInviteSearch()
        search(automaticallySendRequest: shouldAutoSend)
    }

    private func handleScannerFailure(_ message: String) {
        isShowingQRScanner = false
        searchMessage = message
    }

    private func extractUsername(from payload: String) -> String? {
        if let components = URLComponents(string: payload),
           components.scheme == "caller",
           components.host == "invite",
           let username = components.queryItems?.first(where: { $0.name == "username" })?.value {
            let normalized = UsernameValidator.normalized(username)
            return normalized.isEmpty ? nil : normalized
        }

        let normalized = UsernameValidator.normalized(payload)
        return normalized.isEmpty ? nil : normalized
    }

    private func resolveSearchResult(for username: String) async -> SearchResultState? {
        if let friend = viewModel.contacts.first(where: {
            UsernameValidator.normalized($0.username ?? "") == username
        }) {
            return SearchResultState(user: friend, status: .friend)
        }

        if let outgoing = viewModel.outgoingFriendRequests.first(where: {
            UsernameValidator.normalized($0.toUser.username ?? "") == username
        }) {
            return SearchResultState(user: outgoing.toUser, status: .outgoingRequest)
        }

        if let incoming = viewModel.incomingFriendRequests.first(where: {
            UsernameValidator.normalized($0.fromUser.username ?? "") == username
        }) {
            return SearchResultState(user: incoming.fromUser, status: .incomingRequest)
        }

        guard let user = await viewModel.searchUser(by: username) else {
            return nil
        }

        return SearchResultState(user: user, status: .addable)
    }

    private var inviteQRCodePayload: String? {
        guard let username = viewModel.currentUser?.username, !username.isEmpty else {
            return nil
        }
        return "caller://invite?username=\(username)"
    }

    @ViewBuilder
    private var qrCodeSheet: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color.black, Color(red: 0.08, green: 0.09, blue: 0.14)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 24) {
                    if let payload = inviteQRCodePayload,
                       let qrImage = makeQRCodeImage(from: payload) {
                        Image(uiImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 240, height: 240)
                            .padding(20)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    }

                    VStack(spacing: 8) {
                        Text(viewModel.currentUser?.displayName ?? "")
                            .font(.title3.weight(.semibold))
                        if let username = viewModel.currentUser?.username, !username.isEmpty {
                            Text("@\(username)")
                                .font(.headline)
                                .foregroundStyle(.green)
                        }
                        Text("Откройте поиск в Caller на другом устройстве и отсканируйте этот QR-код.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 20)

                    Spacer()
                }
                .padding(24)
            }
            .navigationTitle("Мой QR-код")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") {
                        isShowingMyQRCode = false
                    }
                }
            }
        }
    }

    private func makeQRCodeImage(from payload: String) -> UIImage? {
        qrFilter.setValue(Data(payload.utf8), forKey: "inputMessage")
        qrFilter.correctionLevel = "Q"

        guard let outputImage = qrFilter.outputImage else {
            return nil
        }

        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = qrContext.createCGImage(scaledImage, from: scaledImage.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    private func qrActionCard(
        title: String,
        subtitle: String,
        systemName: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: systemName)
                .font(.title2.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 48, height: 48)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .padding(18)
        .callerGlassCard(cornerRadius: 24, tint: tint)
    }
}

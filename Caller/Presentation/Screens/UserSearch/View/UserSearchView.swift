import CoreImage.CIFilterBuiltins
import SwiftUI

struct UserSearchView: View {
    @ObservedObject private var appViewModel: AppViewModel
    @State private var viewModel: UserSearchViewModel
    @FocusState private var isSearchFocused: Bool

    private let qrContext = CIContext()
    private let qrFilter = CIFilter.qrCodeGenerator()

    init(viewModel: AppViewModel) {
        self._appViewModel = ObservedObject(wrappedValue: viewModel)
        self._viewModel = State(
            initialValue: UserSearchViewModel(
                dependencies: .init(
                    currentUser: { viewModel.currentUser },
                    contacts: { viewModel.contacts },
                    outgoingRequests: { viewModel.outgoingFriendRequests },
                    incomingRequests: { viewModel.incomingFriendRequests },
                    takePendingInviteSearch: { viewModel.takePendingInviteSearch() },
                    searchUser: { username in await viewModel.searchUser(by: username) },
                    sendFriendRequest: { user in await viewModel.sendFriendRequest(to: user) }
                )
            )
        )
    }

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
        .onFirstAppear {
            isSearchFocused = true
            send(.onFirstAppear)
        }
        .onChange(of: appViewModel.pendingInviteSearchUsername) { _, username in
            guard username != nil else { return }
            send(.syncPendingInvite)
        }
        .sheet(
            isPresented: Binding(
                get: { viewModel.state.isShowingQRScanner },
                set: { isPresented in
                    send(isPresented ? .tapShowQRScanner : .dismissQRScanner)
                }
            )
        ) {
            qrScannerSheet
        }
        .sheet(
            isPresented: Binding(
                get: { viewModel.state.isShowingMyQRCode },
                set: { isPresented in
                    if !isPresented {
                        send(.dismissMyQRCode)
                    }
                }
            )
        ) {
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
                send(.tapShowQRScanner)
            } label: {
                qrActionCard(
                    title: "Сканировать QR",
                    subtitle: "Добавить по коду",
                    systemName: "qrcode.viewfinder",
                    tint: .green
                )
            }
            .buttonStyle(.plain)

            if viewModel.state.currentUser?.username?.isEmpty == false {
                Button {
                    isSearchFocused = false
                    send(.tapShowMyQRCode)
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
                TextField(
                    "Введите никнейм",
                    text: Binding(
                        get: { viewModel.state.searchQuery },
                        set: { send(.setSearchQuery($0)) }
                    )
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isSearchFocused)

                Button("Найти") {
                    send(.tapSearch)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .callerGlassButtonSurface(cornerRadius: 999, tint: .blue)
                .buttonStyle(.plain)
                .disabled(viewModel.state.isSearching)
            }
            .padding(16)
            .callerGlassCard(cornerRadius: 22, tint: .blue)

            if let searchMessage = viewModel.state.searchMessage {
                Text(searchMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var resultSection: some View {
        if viewModel.state.isSearching {
            HStack {
                Spacer()
                ProgressView()
                    .tint(.white)
                Spacer()
            }
            .padding(.top, 30)
        } else if let searchResult = viewModel.state.searchResult {
            VStack(alignment: .leading, spacing: 12) {
                Text("Результат")
                    .font(.title3.bold())
                DiscoverUserRow(
                    user: searchResult.user,
                    status: searchResult.status,
                    onPrimaryAction: {
                        send(.tapPrimaryAction)
                    }
                )
            }
        } else if viewModel.state.hasSearched {
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

    private var inviteQRCodePayload: String? {
        guard let username = viewModel.state.currentUser?.username, !username.isEmpty else {
            return nil
        }
        return "caller://invite?username=\(username)"
    }

    @ViewBuilder
    private var qrScannerSheet: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                QRCodeScannerView(
                    onCodeScanned: { code in
                        send(.scannedCode(code))
                    },
                    onFailure: { message in
                        send(.scannerFailed(message))
                    }
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
                        send(.dismissQRScanner)
                    }
                }
            }
        }
        .presentationDragIndicator(.visible)
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
                        Text(viewModel.state.currentUser?.displayName ?? "")
                            .font(.title3.weight(.semibold))
                        if let username = viewModel.state.currentUser?.username, !username.isEmpty {
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
                        send(.dismissMyQRCode)
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

    private func send(_ input: UserSearchViewModel.Input) {
        Task {
            await viewModel.trigger(input)
        }
    }
}

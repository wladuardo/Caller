import MapKit
import SwiftUI

struct FriendsMapView: View {
    @ObservedObject private var appViewModel: AppViewModel
    @Binding var selectedTab: AppTab
    let bottomBarHeight: CGFloat
    @State private var viewModel: FriendsMapViewModel
    @State private var drawerTopChromeHeight: CGFloat = 0
    @State private var selectedFriendContentHeight: CGFloat = 0
    @State private var listModeContentHeight: CGFloat = 0

    init(
        viewModel: AppViewModel,
        selectedTab: Binding<AppTab>,
        bottomBarHeight: CGFloat
    ) {
        _appViewModel = ObservedObject(wrappedValue: viewModel)
        _selectedTab = selectedTab
        self.bottomBarHeight = bottomBarHeight
        _viewModel = State(
            initialValue: FriendsMapViewModel(
                dependencies: .init(
                    enableLocationSharing: { await viewModel.enableLocationSharing() },
                    consumePendingMapFocus: { viewModel.consumePendingMapFocus() },
                    requestFriendLocation: { friend in await viewModel.requestFriendLocation(friend) }
                )
            )
        )
    }

    private var friendAnnotations: [FriendMapAnnotation] {
        viewModel.friendAnnotations(from: viewModel.state.mapContacts)
    }

    private var selectedFriend: AppUser? {
        guard let selectedFriendID = viewModel.state.selectedFriendID else { return nil }
        return appViewModel.contacts.first(where: { $0.id == selectedFriendID })
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let defaultExpandedDrawerHeight = max(proxy.size.height * 0.5, 280)
                let maxExpandedDrawerHeight = max(
                    viewModel.compactDrawerHeight,
                    proxy.size.height - proxy.safeAreaInsets.top - 12
                )
                let measuredExpandedDrawerHeight = if selectedFriend != nil {
                    drawerTopChromeHeight + selectedFriendContentHeight
                } else {
                    drawerTopChromeHeight + listModeContentHeight
                }
                let targetExpandedDrawerHeight = measuredExpandedDrawerHeight > 0
                    ? measuredExpandedDrawerHeight
                    : defaultExpandedDrawerHeight
                let selectedFriendExpandedDrawerHeight = min(
                    max(targetExpandedDrawerHeight, viewModel.compactDrawerHeight),
                    maxExpandedDrawerHeight
                )
                let expandedDrawerHeight = selectedFriend != nil
                    ? selectedFriendExpandedDrawerHeight
                    : min(max(targetExpandedDrawerHeight, viewModel.compactDrawerHeight), maxExpandedDrawerHeight)

                ZStack(alignment: .bottom) {
                    mapContent

                    if !viewModel.state.isLocationAccessGranted {
                        permissionCard
                            .padding(.horizontal, 20)
                            .padding(.bottom, expandedDrawerHeight + 16)
                    }

                    friendsDrawer(expandedHeight: expandedDrawerHeight)
                }
                .navigationTitle("Карта")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .task {
            await viewModel.trigger(.requestLocationAccess)
        }
        .onAppear {
            send(.onAppear(
                currentLocation: appViewModel.currentLocation,
                contacts: appViewModel.contacts,
                pendingMapFocusUser: appViewModel.pendingMapFocusUser
            ))
        }
        .onChange(of: appViewModel.currentLocation?.latitude) { _, _ in
            send(.currentLocationChanged(appViewModel.currentLocation))
        }
        .onChange(of: appViewModel.contacts) { _, contacts in
            send(.contactsChanged(contacts))
        }
        .onChange(of: selectedTab) { _, tab in
            guard tab == .map else { return }
            send(.selectedMapTab(
                currentLocation: appViewModel.currentLocation,
                contacts: appViewModel.contacts,
                pendingMapFocusUser: appViewModel.pendingMapFocusUser
            ))
        }
        .onChange(of: appViewModel.pendingMapFocusUser?.id) { _, userID in
            guard userID != nil, selectedTab == .map else { return }
            send(.pendingMapFocusChanged(
                appViewModel.pendingMapFocusUser,
                contacts: appViewModel.contacts,
                isMapSelected: selectedTab == .map
            ))
        }
        .onPreferenceChange(SelectedFriendContentHeightPreferenceKey.self) { height in
            selectedFriendContentHeight = height
        }
        .onPreferenceChange(DrawerTopChromeHeightPreferenceKey.self) { height in
            drawerTopChromeHeight = height
        }
        .onPreferenceChange(ListModeContentHeightPreferenceKey.self) { height in
            listModeContentHeight = height
        }
    }

    @ViewBuilder
    private var mapContent: some View {
        Map(
            position: Binding(
                get: { viewModel.state.cameraPosition },
                set: { position in
                    viewModel.state.cameraPosition = position
                }
            )
        ) {
            UserAnnotation()

            if let currentLocation = appViewModel.currentLocation,
               let currentUser = appViewModel.currentUser {
                Annotation(coordinate: currentLocation.locationCoordinate2D, anchor: .top) {
                    Text("Вы")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.blue.opacity(0.82), in: Capsule())
                        .padding(.bottom, 16)
                        .allowsHitTesting(false)
                } label: {
                    EmptyView()
                }
            }

            ForEach(friendAnnotations) { annotation in
                Annotation(coordinate: annotation.coordinate, anchor: .top) {
                    VStack(spacing: 6) {
                        UserAvatarView(
                            user: annotation.user,
                            size: 42,
                            iconSize: 20,
                            iconTint: .white
                        )
                        Text(annotation.user.displayName)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.62), in: Capsule())

                        if let speedText = viewModel.speedText(for: annotation.user) {
                            Label(speedText, systemImage: "speedometer")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.green.opacity(0.78), in: Capsule())
                        }
                    }
                    .scaleEffect(viewModel.state.selectedFriendID == annotation.user.id ? 1.06 : 1)
                } label: {
                    EmptyView()
                }
            }
        }
        .mapStyle(viewModel.state.mapDisplayMode.mapStyle)
        .onMapCameraChange(frequency: .continuous) { context in
            send(.setVisibleRegion(context.region))
        }
        .overlay(alignment: .trailing) {
            mapControls
                .fixedSize()
                .padding(.trailing, 16)
        }
        .ignoresSafeArea()
    }

    private var mapControls: some View {
        VStack(spacing: 8) {
            VStack(spacing: 0) {
                mapControlButton(systemName: "plus") {
                    send(.zoom(0.55, currentLocation: appViewModel.currentLocation, contacts: appViewModel.contacts))
                }

                Divider()
                    .overlay(Color.white.opacity(0.1))
                    .padding(.horizontal, 10)

                mapControlButton(systemName: "minus") {
                    send(.zoom(1.65, currentLocation: appViewModel.currentLocation, contacts: appViewModel.contacts))
                }
            }
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.14), radius: 12, y: 6)

            mapControlButton(systemName: "location.fill") {
                send(.centerCurrentLocation(appViewModel.currentLocation))
            }
            .background(.ultraThinMaterial, in: Circle())
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.14), radius: 12, y: 6)

            Menu {
                ForEach(MapDisplayMode.allCases, id: \.self) { mode in
                    Button {
                        send(.setMapDisplayMode(mode))
                    } label: {
                        Label(mode.title, systemImage: mode.systemImage)
                    }
                }
            } label: {
                Image(systemName: viewModel.state.mapDisplayMode.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.14), radius: 12, y: 6)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private func mapControlButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func friendsDrawer(expandedHeight: CGFloat) -> some View {
        let restingHeight: CGFloat = switch viewModel.state.drawerDetent {
        case .collapsed:
            viewModel.collapsedDrawerHeight
        case .compact:
            viewModel.compactDrawerHeight
        case .expanded:
            expandedHeight
        }
        let clampedDragOffset = min(
            max(viewModel.state.dragOffset, -(expandedHeight - viewModel.collapsedDrawerHeight)),
            expandedHeight - viewModel.collapsedDrawerHeight
        )
        let appliedHeight = min(
            max(restingHeight - clampedDragOffset, viewModel.collapsedDrawerHeight),
            expandedHeight
        )
        let isCollapsed = viewModel.state.drawerDetent == .collapsed
        let totalHeight = bottomBarHeight + appliedHeight

        return VStack(spacing: 0) {
            if !isCollapsed {
                VStack(spacing: 0) {
                    Capsule()
                        .fill(Color.white.opacity(0.26))
                        .frame(width: 44, height: 5)
                        .padding(.top, 10)
                        .padding(.bottom, 14)
                        .background(
                            GeometryReader { geometry in
                                Color.clear.preference(
                                    key: DrawerTopChromeHeightPreferenceKey.self,
                                    value: geometry.size.height
                                )
                            }
                        )

                    if let selectedFriend {
                        ScrollView(showsIndicators: false) {
                            selectedFriendContent(selectedFriend)
                                .padding(.horizontal, 16)
                                .padding(.top, 4)
                                .padding(.bottom, 20)
                                .background(
                                    GeometryReader { geometry in
                                        Color.clear.preference(
                                            key: SelectedFriendContentHeightPreferenceKey.self,
                                            value: geometry.size.height
                                        )
                                    }
                                )
                        }
                        .scrollDisabled(viewModel.state.drawerDetent != .expanded)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                    } else {
                        VStack(spacing: 0) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Друзья")
                                        .font(.headline.weight(.semibold))
                                        .foregroundStyle(.white)
                                    Text("\(appViewModel.contacts.count) пользователей")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Button {
                                    withAnimation(.spring(response: 0.42, dampingFraction: 0.9, blendDuration: 0.12)) {
                                        send(.cycleDrawerDetent)
                                    }
                                } label: {
                                    Image(systemName: viewModel.drawerChevron(for: viewModel.state.drawerDetent))
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 36, height: 36)
                                        .background(Color.white.opacity(0.08), in: Circle())
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)

                            if appViewModel.contacts.isEmpty {
                                ContentUnavailableView(
                                    "Друзей пока нет",
                                    systemImage: "person.2.slash",
                                    description: Text("Добавьте друзей, чтобы видеть их на карте.")
                                )
                                .foregroundStyle(.white.opacity(0.8))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding(.horizontal, 16)
                            } else {
                                ScrollView(showsIndicators: false) {
                                    LazyVStack(spacing: 10) {
                                        ForEach(appViewModel.contacts) { friend in
                                            friendRow(friend)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.bottom, 20)
                                }
                                .scrollDisabled(viewModel.state.drawerDetent != .expanded)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .leading).combined(with: .opacity),
                                    removal: .move(edge: .trailing).combined(with: .opacity)
                                ))
                            }
                        }
                        .background(
                            GeometryReader { geometry in
                                Color.clear.preference(
                                    key: ListModeContentHeightPreferenceKey.self,
                                    value: geometry.size.height
                                )
                            }
                        )
                    }
                }
                .frame(height: appliedHeight, alignment: .top)
            }

            SharedTabBar(selectedTab: $selectedTab, showsBackground: false)
        }
        .frame(maxWidth: .infinity)
        .frame(height: totalHeight, alignment: .bottom)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(alignment: .top) {
            if isCollapsed {
                Capsule()
                    .fill(Color.white.opacity(0.28))
                    .frame(width: 38, height: 5)
                    .padding(.top, 9)
                    .transition(.opacity)
            }
        }
        .shadow(color: .black.opacity(isCollapsed ? 0.12 : 0.24), radius: isCollapsed ? 10 : 24, y: isCollapsed ? 4 : 12)
        .padding(.horizontal, 12)
        .animation(.spring(response: 0.42, dampingFraction: 0.9, blendDuration: 0.12), value: viewModel.state.drawerDetent)
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: viewModel.state.selectedFriendID)
        .gesture(
            DragGesture(minimumDistance: 10)
                .onChanged { value in
                    send(.setDragOffset(value.translation.height))
                }
                .onEnded { value in
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.9, blendDuration: 0.12)) {
                        send(.endDrawerDrag(
                            currentHeight: appliedHeight,
                            dragTranslation: value.translation.height,
                            expandedHeight: expandedHeight
                        ))
                    }
                }
        )
    }

    private func friendRow(_ friend: AppUser) -> some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.28)) {
                    send(.centerMap(friend))
                }
            } label: {
                HStack(spacing: 14) {
                    UserAvatarView(
                        user: friend,
                        size: 48,
                        iconSize: 24,
                        iconTint: .white
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(friend.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        if let username = friend.username, !username.isEmpty {
                            Text("@\(username)")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.cyan)
                        }

                        Text(viewModel.locationStatus(for: friend))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        if let speedText = viewModel.speedText(for: friend) {
                            Label(speedText, systemImage: "speedometer")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.green)
                        }
                    }

                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            requestLocationButton(for: friend)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(viewModel.state.selectedFriendID == friend.id ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
        )
    }

    private func requestLocationButton(for friend: AppUser) -> some View {
        let isRequesting = viewModel.isRequestingLocation(for: friend)

        return Button {
            send(.requestFriendLocation(friend))
        } label: {
            ZStack {
                if isRequesting {
                    ProgressView()
                        .controlSize(.regular)
                        .tint(.white)
                } else {
                    Image(systemName: "location.viewfinder")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 50, height: 50)
            .background(Color.white.opacity(0.14), in: Circle())
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isRequesting)
        .accessibilityLabel("Запросить геопозицию \(friend.displayName)")
    }

    private func selectedFriendContent(_ friend: AppUser) -> some View {
        let isRequestingLocation = viewModel.isRequestingLocation(for: friend)

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Button {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.9, blendDuration: 0.12)) {
                        send(.clearSelectedFriend)
                    }
                } label: {
                    Image(systemName: "chevron.backward")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)

                UserAvatarView(
                    user: friend,
                    size: 60,
                    iconSize: 30,
                    iconTint: .white
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(friend.displayName)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                    if let username = friend.username, !username.isEmpty {
                        Text("@\(username)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.cyan)
                    }
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 10) {
                infoRow(systemImage: "clock.fill", title: "Обновление", value: viewModel.locationStatus(for: friend))

                if let speedText = viewModel.speedText(for: friend) {
                    infoRow(systemImage: "speedometer", title: "Скорость", value: speedText, tint: .green)
                }

                if let batteryLevelPercent = friend.sharedLocation?.batteryLevelPercent {
                    infoRow(
                        systemImage: "battery.100",
                        title: "Батарея",
                        value: "\(batteryLevelPercent)%",
                        tint: batteryTint(for: batteryLevelPercent)
                    )
                }

                if let deviceModel = viewModel.deviceModelText(for: friend), !deviceModel.isEmpty {
                    infoRow(systemImage: "iphone", title: "Устройство", value: deviceModel)
                }
            }

            HStack(spacing: 10) {
                actionButton(
                    title: "Аудио",
                    systemImage: "phone.fill",
                    tint: .blue
                ) {
                    Task { await appViewModel.startCall(with: friend, type: .audio) }
                }
                actionButton(
                    title: "Видео",
                    systemImage: "video.fill",
                    tint: .mint
                ) {
                    Task { await appViewModel.startCall(with: friend, type: .video) }
                }
                actionButton(
                    title: "Чат",
                    systemImage: "message.fill",
                    tint: .cyan
                ) {
                    appViewModel.openChat(with: friend)
                }
            }

            Button {
                send(.requestFriendLocation(friend))
            } label: {
                HStack(spacing: 10) {
                    if isRequestingLocation {
                        ProgressView()
                            .controlSize(.regular)
                            .tint(.white)
                    } else {
                        Image(systemName: "location.viewfinder")
                            .font(.headline.weight(.bold))
                    }

                    Text(isRequestingLocation ? "Запрашиваем геопозицию..." : "Запросить текущую геопозицию")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .disabled(isRequestingLocation)
        }
    }

    private func actionButton(
        title: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(tint.opacity(0.45), in: Circle())

                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(tint.opacity(0.2), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(tint.opacity(0.38), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func infoRow(systemImage: String, title: String, value: String, tint: Color = .cyan) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.18), in: Circle())

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            Text(value)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.trailing)
        }
    }

    private func batteryTint(for batteryLevelPercent: Int) -> Color {
        switch batteryLevelPercent {
        case 60...100:
            return .green
        case 25..<60:
            return .yellow
        default:
            return .red
        }
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Включите геолокацию")
                .font(.title3.bold())
                .foregroundStyle(.white)

            Text("После включения ваши друзья смогут делиться своим местоположением, а вы увидите их на карте.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                send(.requestLocationAccess)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "location.fill")
                    Text("Включить геолокацию")
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .callerGlassButtonSurface(cornerRadius: 16, tint: .blue)
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .callerGlassCard(cornerRadius: 24, tint: .cyan)
    }

    private func send(_ input: FriendsMapViewModel.Input) {
        Task {
            await viewModel.trigger(input)
        }
    }
}

private struct SelectedFriendContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct DrawerTopChromeHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ListModeContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

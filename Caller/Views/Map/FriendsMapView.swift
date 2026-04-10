import MapKit
import SwiftUI

private struct FriendMapAnnotation: Identifiable {
    let id: String
    let user: AppUser
    let coordinate: CLLocationCoordinate2D
}

private enum FriendsDrawerDetent {
    case collapsed
    case compact
    case expanded
}

struct FriendsMapView: View {
    @ObservedObject var viewModel: AppViewModel
    @Binding var selectedTab: AppTab
    let bottomBarHeight: CGFloat
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var hasPositionedInitialCamera = false
    @State private var drawerDetent: FriendsDrawerDetent = .collapsed
    @State private var dragOffset: CGFloat = 0
    @State private var selectedFriendID: String?

    private let collapsedDrawerHeight: CGFloat = 0
    private let compactDrawerHeight: CGFloat = 206

    private var friendAnnotations: [FriendMapAnnotation] {
        viewModel.contacts.compactMap { user in
            guard let location = user.sharedLocation else { return nil }
            return FriendMapAnnotation(
                id: user.id,
                user: user,
                coordinate: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
            )
        }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let expandedDrawerHeight = max(proxy.size.height * 0.5, 280)

                ZStack(alignment: .bottom) {
                    mapContent

                    if viewModel.currentLocation == nil && friendAnnotations.isEmpty {
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
            await viewModel.enableLocationSharing()
        }
        .onAppear {
            handleMapPresentation()
        }
        .onChange(of: viewModel.currentLocation?.latitude) { _, _ in
            positionInitialCameraIfNeeded()
        }
        .onChange(of: selectedTab) { _, tab in
            guard tab == .map else { return }
            handleMapPresentation()
        }
        .onChange(of: viewModel.pendingMapFocusUser?.id) { _, userID in
            guard userID != nil, selectedTab == .map else { return }
            focusPendingUserIfNeeded()
        }
    }

    @ViewBuilder
    private var mapContent: some View {
        Map(position: $cameraPosition) {
            UserAnnotation()

            ForEach(friendAnnotations) { annotation in
                Annotation(annotation.user.displayName, coordinate: annotation.coordinate, anchor: .bottom) {
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
                    }
                    .scaleEffect(selectedFriendID == annotation.user.id ? 1.06 : 1)
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .ignoresSafeArea()
    }

    private func friendsDrawer(expandedHeight: CGFloat) -> some View {
        let restingHeight: CGFloat = switch drawerDetent {
        case .collapsed:
            collapsedDrawerHeight
        case .compact:
            compactDrawerHeight
        case .expanded:
            expandedHeight
        }
        let clampedDragOffset = min(
            max(dragOffset, -(expandedHeight - collapsedDrawerHeight)),
            expandedHeight - collapsedDrawerHeight
        )
        let appliedHeight = min(
            max(restingHeight - clampedDragOffset, collapsedDrawerHeight),
            expandedHeight
        )
        let isCollapsed = drawerDetent == .collapsed
        let totalHeight = bottomBarHeight + appliedHeight

        return VStack(spacing: 0) {
            if !isCollapsed {
                VStack(spacing: 0) {
                    Capsule()
                        .fill(Color.white.opacity(0.26))
                        .frame(width: 44, height: 5)
                        .padding(.top, 10)
                        .padding(.bottom, 14)

                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Друзья")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.white)
                            Text("\(viewModel.contacts.count) пользователей")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                drawerDetent = nextDrawerDetent(from: drawerDetent)
                                dragOffset = 0
                            }
                        } label: {
                            Image(systemName: drawerChevron(for: drawerDetent))
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(Color.white.opacity(0.08), in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                    if viewModel.contacts.isEmpty {
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
                                ForEach(viewModel.contacts) { friend in
                                    friendRow(friend)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 20)
                        }
                        .scrollDisabled(drawerDetent != .expanded)
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
        .gesture(
            DragGesture(minimumDistance: 10)
                .onChanged { value in
                    dragOffset = value.translation.height
                }
                .onEnded { value in
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        drawerDetent = resolvedDrawerDetent(
                            currentHeight: appliedHeight,
                            dragTranslation: value.translation.height,
                            expandedHeight: expandedHeight
                        )
                        dragOffset = 0
                    }
                }
        )
    }

    private func friendRow(_ friend: AppUser) -> some View {
        Button {
            centerMap(on: friend)
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

                    Text(locationStatus(for: friend))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: friend.sharedLocation == nil ? "location.slash" : "location.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(friend.sharedLocation == nil ? Color.secondary : Color.green)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(selectedFriendID == friend.id ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
        .disabled(friend.sharedLocation == nil)
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
                Task {
                    await viewModel.enableLocationSharing()
                }
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

    private func locationStatus(for friend: AppUser) -> String {
        guard let location = friend.sharedLocation else {
            return "Геопозиция ещё не доступна"
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        let relativeTime = formatter.localizedString(for: location.updatedAt, relativeTo: .now)
        return "Обновлено \(relativeTime)"
    }

    private func centerMap(on friend: AppUser) {
        guard let location = friend.sharedLocation else { return }

        selectedFriendID = friend.id
        withAnimation(.easeInOut(duration: 0.28)) {
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
                    span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                )
            )
            drawerDetent = .compact
            dragOffset = 0
        }
    }

    private func nextDrawerDetent(from detent: FriendsDrawerDetent) -> FriendsDrawerDetent {
        switch detent {
        case .collapsed:
            .compact
        case .compact:
            .expanded
        case .expanded:
            .collapsed
        }
    }

    private func drawerChevron(for detent: FriendsDrawerDetent) -> String {
        switch detent {
        case .collapsed, .compact:
            "chevron.up"
        case .expanded:
            "chevron.down"
        }
    }

    private func resolvedDrawerDetent(
        currentHeight: CGFloat,
        dragTranslation: CGFloat,
        expandedHeight: CGFloat
    ) -> FriendsDrawerDetent {
        let projectedHeight = currentHeight - dragTranslation
        let collapsedMidpoint = (collapsedDrawerHeight + compactDrawerHeight) / 2
        let compactMidpoint = (compactDrawerHeight + expandedHeight) / 2

        if projectedHeight <= collapsedMidpoint {
            return .collapsed
        }
        if projectedHeight <= compactMidpoint {
            return .compact
        }
        return .expanded
    }

    private func positionInitialCameraIfNeeded() {
        guard !hasPositionedInitialCamera, let location = viewModel.currentLocation else { return }
        hasPositionedInitialCamera = true
        cameraPosition = .region(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
                span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
            )
        )
    }

    private func expandDrawerIfNeeded() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
            drawerDetent = .expanded
            dragOffset = 0
        }
    }

    private func focusPendingUserIfNeeded() {
        guard let pendingUser = viewModel.pendingMapFocusUser else { return }

        if let contact = viewModel.contacts.first(where: { $0.id == pendingUser.id }) {
            focusMap(on: contact)
        } else {
            focusMap(on: pendingUser)
        }

        viewModel.consumePendingMapFocus()
    }

    private func handleMapPresentation() {
        expandDrawerIfNeeded()
        focusPendingUserIfNeeded()
    }

    private func focusMap(on friend: AppUser) {
        guard let location = friend.sharedLocation else { return }

        selectedFriendID = friend.id
        withAnimation(.easeInOut(duration: 0.28)) {
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
                    span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                )
            )
        }
    }
}

import MapKit
import Observation
import SwiftUI

struct FriendMapAnnotation: Identifiable {
    let id: String
    let user: AppUser
    let coordinate: CLLocationCoordinate2D
}

enum FriendsDrawerDetent {
    case collapsed
    case compact
    case expanded
}

enum MapDisplayMode: CaseIterable, Hashable {
    case standard
    case satellite
    case hybrid

    var title: String {
        switch self {
        case .standard:
            "Карта"
        case .satellite:
            "Спутник"
        case .hybrid:
            "Гибрид"
        }
    }

    var systemImage: String {
        switch self {
        case .standard:
            "map"
        case .satellite:
            "globe.europe.africa.fill"
        case .hybrid:
            "map.fill"
        }
    }

    var mapStyle: MapStyle {
        switch self {
        case .standard:
            .standard(elevation: .realistic)
        case .satellite:
            .imagery(elevation: .realistic)
        case .hybrid:
            .hybrid(elevation: .realistic)
        }
    }
}

@Observable
final class FriendsMapViewModel: Store {
    struct Dependencies {
        let enableLocationSharing: @MainActor @Sendable () async -> Bool
        let consumePendingMapFocus: @MainActor @Sendable () -> Void
        let requestFriendLocation: @MainActor @Sendable (AppUser) async -> Void
    }

    let collapsedDrawerHeight: CGFloat = 0
    let compactDrawerHeight: CGFloat = 206
    var state = State()

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func trigger(_ input: Input) async {
        switch input {
        case .onAppear(let currentLocation, let contacts, let pendingMapFocusUser),
             .selectedMapTab(let currentLocation, let contacts, let pendingMapFocusUser):
            setMapContacts(contacts, animated: false)
            expandDrawer()
            focusPendingUserIfNeeded(pendingMapFocusUser, contacts: contacts)
            positionInitialCameraIfNeeded(currentLocation)

        case .contactsChanged(let contacts):
            setMapContacts(contacts, animated: true)

        case .currentLocationChanged(let currentLocation):
            if currentLocation != nil {
                update { state in
                    state.isLocationAccessGranted = true
                }
            }
            positionInitialCameraIfNeeded(currentLocation)

        case .pendingMapFocusChanged(let pendingUser, let contacts, let isMapSelected):
            guard isMapSelected else { return }
            focusPendingUserIfNeeded(pendingUser, contacts: contacts)

        case .setVisibleRegion(let region):
            update { state in
                state.visibleRegion = region
            }

        case .setMapDisplayMode(let mode):
            update { state in
                state.mapDisplayMode = mode
            }

        case .zoom(let factor, let currentLocation, let contacts):
            zoomMap(by: factor, currentLocation: currentLocation, contacts: contacts)

        case .centerCurrentLocation(let currentLocation):
            centerMap(on: currentLocation)

        case .requestLocationAccess:
            let isGranted = await dependencies.enableLocationSharing()
            update { state in
                state.isLocationAccessGranted = isGranted
            }

        case .requestFriendLocation(let user):
            await requestFriendLocation(user)

        case .centerMap(let user):
            centerMap(on: user)

        case .focusMap(let user):
            focusMap(on: user)

        case .clearSelectedFriend:
            update { state in
                state.selectedFriendID = nil
            }

        case .cycleDrawerDetent:
            update { state in
                state.drawerDetent = nextDrawerDetent(from: state.drawerDetent)
                state.dragOffset = 0
            }

        case .setDragOffset(let offset):
            update { state in
                state.dragOffset = offset
            }

        case .endDrawerDrag(let currentHeight, let dragTranslation, let expandedHeight):
            update { state in
                state.drawerDetent = resolvedDrawerDetent(
                    currentHeight: currentHeight,
                    dragTranslation: dragTranslation,
                    expandedHeight: expandedHeight
                )
                state.dragOffset = 0
            }
        }
    }

    func friendAnnotations(from contacts: [AppUser]) -> [FriendMapAnnotation] {
        contacts.compactMap { user in
            guard let location = user.sharedLocation else { return nil }
            return FriendMapAnnotation(
                id: user.id,
                user: user,
                coordinate: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
            )
        }
    }

    func locationStatus(for friend: AppUser) -> String {
        guard let location = friend.sharedLocation else {
            return "Геопозиция ещё не доступна"
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        let relativeTime = formatter.localizedString(for: location.updatedAt, relativeTo: .now)
        return "Обновлено \(relativeTime)"
    }

    func speedText(for friend: AppUser) -> String? {
        guard let speed = friend.sharedLocation?.speed, speed >= 1 else {
            return nil
        }

        let speedInKilometersPerHour = Int((speed * 3.6).rounded())
        return "\(speedInKilometersPerHour) км/ч"
    }

    func deviceModelText(for friend: AppUser) -> String? {
        friend.deviceModel
    }

    func batteryLevelText(for friend: AppUser) -> String? {
        guard let batteryLevelPercent = friend.sharedLocation?.batteryLevelPercent else {
            return nil
        }

        return "\(batteryLevelPercent)%"
    }

    func drawerChevron(for detent: FriendsDrawerDetent) -> String {
        switch detent {
        case .collapsed, .compact:
            "chevron.up"
        case .expanded:
            "chevron.down"
        }
    }

    func isRequestingLocation(for friend: AppUser) -> Bool {
        state.requestingLocationFriendIDs.contains(friend.id)
    }

    private func zoomMap(by factor: CLLocationDegrees, currentLocation: SharedLocation?, contacts: [AppUser]) {
        guard let region = state.visibleRegion ?? fallbackRegion(currentLocation: currentLocation, contacts: contacts) else {
            return
        }

        let nextSpan = MKCoordinateSpan(
            latitudeDelta: min(max(region.span.latitudeDelta * factor, 0.002), 80),
            longitudeDelta: min(max(region.span.longitudeDelta * factor, 0.002), 80)
        )

        withAnimation(.easeInOut(duration: 0.24)) {
            update { state in
                state.cameraPosition = .region(
                    MKCoordinateRegion(
                        center: region.center,
                        span: nextSpan
                    )
                )
            }
        }
    }

    private func fallbackRegion(currentLocation: SharedLocation?, contacts: [AppUser]) -> MKCoordinateRegion? {
        if let currentLocation {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: currentLocation.latitude, longitude: currentLocation.longitude),
                span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
            )
        }

        if let annotation = friendAnnotations(from: contacts).first {
            return MKCoordinateRegion(
                center: annotation.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
            )
        }

        return nil
    }

    private func setMapContacts(_ contacts: [AppUser], animated: Bool) {
        guard state.mapContacts != contacts else { return }

        let updateContacts = {
            self.update { state in
                state.mapContacts = contacts
            }
        }

        if animated {
            withAnimation(.easeInOut(duration: 0.85)) {
                updateContacts()
            }
        } else {
            updateContacts()
        }

        if let selectedFriendID = state.selectedFriendID,
           contacts.contains(where: { $0.id == selectedFriendID }) == false {
            update { state in
                state.selectedFriendID = nil
            }
        }
    }

    private func centerMap(on friend: AppUser) {
        guard let location = friend.sharedLocation else { return }

        update { state in
            state.selectedFriendID = friend.id
            state.cameraPosition = .region(
                MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
                    span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                )
            )
            state.drawerDetent = .expanded
            state.dragOffset = 0
        }
    }

    private func centerMap(on currentLocation: SharedLocation?) {
        guard let currentLocation else { return }

        withAnimation(.easeInOut(duration: 0.28)) {
            update { state in
                state.selectedFriendID = nil
                state.cameraPosition = .region(
                    MKCoordinateRegion(
                        center: CLLocationCoordinate2D(
                            latitude: currentLocation.latitude,
                            longitude: currentLocation.longitude
                        ),
                        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                    )
                )
            }
        }
    }

    private func focusMap(on friend: AppUser) {
        guard let location = friend.sharedLocation else { return }

        update { state in
            state.selectedFriendID = friend.id
            state.cameraPosition = .region(
                MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
                    span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                )
            )
            state.drawerDetent = .expanded
            state.dragOffset = 0
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

    private func positionInitialCameraIfNeeded(_ currentLocation: SharedLocation?) {
        guard !state.hasPositionedInitialCamera, let currentLocation else { return }

        update { state in
            state.hasPositionedInitialCamera = true
            state.cameraPosition = .region(
                MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: currentLocation.latitude, longitude: currentLocation.longitude),
                    span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
                )
            )
        }
    }

    private func expandDrawer() {
        update { state in
            state.drawerDetent = .expanded
            state.dragOffset = 0
        }
    }

    private func focusPendingUserIfNeeded(_ pendingUser: AppUser?, contacts: [AppUser]) {
        guard let pendingUser else { return }

        if let contact = contacts.first(where: { $0.id == pendingUser.id }) {
            focusMap(on: contact)
        } else {
            focusMap(on: pendingUser)
        }

        dependencies.consumePendingMapFocus()
    }

    private func requestFriendLocation(_ friend: AppUser) async {
        guard !state.requestingLocationFriendIDs.contains(friend.id) else { return }

        update { state in
            state.requestingLocationFriendIDs.insert(friend.id)
        }

        await dependencies.requestFriendLocation(friend)

        update { state in
            state.requestingLocationFriendIDs.remove(friend.id)
        }
    }
}

extension FriendsMapViewModel {
    struct State {
        var cameraPosition: MapCameraPosition = .automatic
        var visibleRegion: MKCoordinateRegion?
        var mapDisplayMode: MapDisplayMode = .standard
        var mapContacts: [AppUser] = []
        var hasPositionedInitialCamera = false
        var drawerDetent: FriendsDrawerDetent = .collapsed
        var dragOffset: CGFloat = 0
        var selectedFriendID: String?
        var requestingLocationFriendIDs = Set<String>()
        var isLocationAccessGranted = false
    }

    enum Input: Sendable {
        case onAppear(currentLocation: SharedLocation?, contacts: [AppUser], pendingMapFocusUser: AppUser?)
        case selectedMapTab(currentLocation: SharedLocation?, contacts: [AppUser], pendingMapFocusUser: AppUser?)
        case contactsChanged([AppUser])
        case currentLocationChanged(SharedLocation?)
        case pendingMapFocusChanged(AppUser?, contacts: [AppUser], isMapSelected: Bool)
        case setVisibleRegion(MKCoordinateRegion)
        case setMapDisplayMode(MapDisplayMode)
        case zoom(CLLocationDegrees, currentLocation: SharedLocation?, contacts: [AppUser])
        case centerCurrentLocation(SharedLocation?)
        case requestLocationAccess
        case requestFriendLocation(AppUser)
        case centerMap(AppUser)
        case focusMap(AppUser)
        case clearSelectedFriend
        case cycleDrawerDetent
        case setDragOffset(CGFloat)
        case endDrawerDrag(currentHeight: CGFloat, dragTranslation: CGFloat, expandedHeight: CGFloat)
    }
}

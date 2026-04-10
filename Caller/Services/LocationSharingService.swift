import CoreLocation
import Foundation
import FirebaseFirestore

protocol LocationSharingServicing {
    func updateCurrentUser(_ user: AppUser?) async
    func updateFriends(_ friends: [AppUser]) async
    func requestLocationAccess() async -> Bool
    func observeCurrentLocation() -> AsyncStream<SharedLocation?>
}

final class MockLocationSharingService: LocationSharingServicing {
    private var currentLocationContinuation: AsyncStream<SharedLocation?>.Continuation?

    func updateCurrentUser(_ user: AppUser?) async {
        guard user != nil else {
            currentLocationContinuation?.yield(nil)
            return
        }

        currentLocationContinuation?.yield(
            SharedLocation(
                latitude: 41.7151,
                longitude: 44.8271,
                updatedAt: .now,
                horizontalAccuracy: 25
            )
        )
    }

    func updateFriends(_ friends: [AppUser]) async {
        _ = friends
    }

    func requestLocationAccess() async -> Bool {
        true
    }

    func observeCurrentLocation() -> AsyncStream<SharedLocation?> {
        AsyncStream { continuation in
            currentLocationContinuation = continuation
            continuation.onTermination = { [weak self] _ in
                Task { [weak self] in
                    self?.currentLocationContinuation = nil
                }
            }
        }
    }
}

final class FirebaseLocationSharingService: NSObject, LocationSharingServicing {
    private let db: Firestore
    private let logger: Logger
    private let locationManager = CLLocationManager()

    private var currentUser: AppUser?
    private var friends: [AppUser] = []
    private var currentLocationContinuation: AsyncStream<SharedLocation?>.Continuation?
    private var locationAuthorizationContinuation: CheckedContinuation<Bool, Never>?

    init(db: Firestore = Firestore.firestore(), logger: Logger = Logger()) {
        self.db = db
        self.logger = logger
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 50
        locationManager.pausesLocationUpdatesAutomatically = true
    }

    func updateCurrentUser(_ user: AppUser?) async {
        currentUser = user

        guard user != nil else {
            locationManager.stopUpdatingLocation()
            currentLocationContinuation?.yield(nil)
            return
        }

        startUpdatingIfAuthorized()
    }

    func updateFriends(_ friends: [AppUser]) async {
        self.friends = friends
    }

    func requestLocationAccess() async -> Bool {
        let status = locationManager.authorizationStatus
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            startUpdatingIfAuthorized()
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                locationAuthorizationContinuation = continuation
                locationManager.requestWhenInUseAuthorization()
            }
        default:
            return false
        }
    }

    func observeCurrentLocation() -> AsyncStream<SharedLocation?> {
        AsyncStream { continuation in
            currentLocationContinuation = continuation
            continuation.onTermination = { [weak self] _ in
                Task { [weak self] in
                    self?.currentLocationContinuation = nil
                }
            }
        }
    }

    private func startUpdatingIfAuthorized() {
        guard currentUser != nil else { return }

        let status = locationManager.authorizationStatus
        guard status == .authorizedAlways || status == .authorizedWhenInUse else { return }
        locationManager.startUpdatingLocation()
    }

    private func propagateLocation(_ location: SharedLocation) async {
        guard let currentUser, !friends.isEmpty else { return }

        let payload: [String: Any] = [
            "sharedLocation": [
                "latitude": location.latitude,
                "longitude": location.longitude,
                "updatedAt": Timestamp(date: location.updatedAt),
                "horizontalAccuracy": location.horizontalAccuracy as Any
            ],
            "updatedAt": Timestamp(date: .now)
        ]

        for chunkStart in stride(from: 0, to: friends.count, by: 400) {
            let batch = db.batch()
            let chunkEnd = min(chunkStart + 400, friends.count)

            for friend in friends[chunkStart..<chunkEnd] {
                let friendRef = db
                    .collection("users")
                    .document(friend.id)
                    .collection("friends")
                    .document(currentUser.id)
                batch.setData(payload, forDocument: friendRef, merge: true)
            }

            do {
                try await batch.commit()
            } catch {
                logger.error("Failed to propagate location: \(error.localizedDescription)")
            }
        }
    }
}

extension FirebaseLocationSharingService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }

            let status = manager.authorizationStatus
            if let continuation = locationAuthorizationContinuation {
                locationAuthorizationContinuation = nil
                continuation.resume(returning: status == .authorizedAlways || status == .authorizedWhenInUse)
            }

            if status == .authorizedAlways || status == .authorizedWhenInUse {
                startUpdatingIfAuthorized()
            }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else { return }

        let sharedLocation = SharedLocation(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            updatedAt: location.timestamp,
            horizontalAccuracy: location.horizontalAccuracy
        )

        Task { @MainActor [weak self] in
            guard let self else { return }
            currentLocationContinuation?.yield(sharedLocation)
            await propagateLocation(sharedLocation)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.logger.error("Location manager failed: \(error.localizedDescription)")
        }
    }
}

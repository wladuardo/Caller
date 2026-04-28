import CoreLocation
import Foundation
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
#if canImport(FirebaseFunctions)
import FirebaseFunctions
#endif
import UIKit

protocol LocationSharingServicing {
    func updateCurrentUser(_ user: AppUser?) async
    func updateFriends(_ friends: [AppUser]) async
    func requestLocationAccess(for user: AppUser?) async -> Bool
    func requestFriendLocation(_ friend: AppUser) async throws
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
                horizontalAccuracy: 25,
                speed: 4.2,
                batteryLevelPercent: 82
            )
        )
    }

    func updateFriends(_ friends: [AppUser]) async {
        _ = friends
    }

    func requestLocationAccess(for user: AppUser?) async -> Bool {
        _ = user
        return true
    }

    func requestFriendLocation(_ friend: AppUser) async throws {
        _ = friend
    }

    func observeCurrentLocation() -> AsyncStream<SharedLocation?> {
        AsyncStream { continuation in
            currentLocationContinuation = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
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
    private var locationPushTokenRegistrationTask: Task<Void, Never>?
    private var shouldRequestAlwaysAfterWhenInUse = false
    private var isRequestingAlwaysAuthorization = false

    private var currentUserID: String? {
        currentUser?.id ?? Auth.auth().currentUser?.uid
    }

    init(db: Firestore = Firestore.firestore(), logger: Logger = Logger()) {
        self.db = db
        self.logger = logger
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        locationManager.distanceFilter = 10
        locationManager.activityType = .otherNavigation
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.allowsBackgroundLocationUpdates = true
        UIDevice.current.isBatteryMonitoringEnabled = true
    }

    func updateCurrentUser(_ user: AppUser?) async {
        currentUser = user

        guard let user else {
            locationPushTokenRegistrationTask?.cancel()
            locationPushTokenRegistrationTask = nil
            if #available(iOS 15.0, *) {
                locationManager.stopMonitoringLocationPushes()
            }
            locationManager.stopUpdatingLocation()
            currentLocationContinuation?.yield(nil)
            return
        }

        await saveLocationAuthorizationStatus(locationManager.authorizationStatus)
        startUpdatingIfAuthorized()
        registerLocationPushTokenIfPossible(for: user.id)
    }

    func updateFriends(_ friends: [AppUser]) async {
        self.friends = friends
    }

    func requestLocationAccess(for user: AppUser?) async -> Bool {
        if let user {
            currentUser = user
        }

        let status = locationManager.authorizationStatus
        await saveLocationAuthorizationStatus(status)
        switch status {
        case .authorizedAlways:
            startUpdatingIfAuthorized()
            if let currentUserID {
                registerLocationPushTokenIfPossible(for: currentUserID)
            }
            return true
        case .authorizedWhenInUse:
            await clearStaleLocationPushAuthorizationStatus()
            return await requestAlwaysAuthorization()
        case .notDetermined:
            await clearStaleLocationPushAuthorizationStatus()
            return await requestWhenInUseThenAlwaysAuthorization()
        default:
            return false
        }
    }

    func requestFriendLocation(_ friend: AppUser) async throws {
        do {
            guard let firebaseUser = Auth.auth().currentUser else {
                throw LocationSharingError.firebaseUserMissing
            }
            let token = try await firebaseUser.getIDToken(forcingRefresh: true)

            try await requestFriendLocationViaHTTP(friend, idToken: token)
        } catch {
            logger.error("Failed to request friend location: \(error.localizedDescription)")
            if let locationError = error as? LocationSharingError {
                throw locationError
            }
            throw LocationSharingError.locationRequestFailed(error.localizedDescription)
        }
    }

    private func requestFriendLocationViaHTTP(_ friend: AppUser, idToken: String) async throws {
        guard let projectID = FirebaseApp.app()?.options.projectID,
              let url = URL(string: "https://us-central1-\(projectID).cloudfunctions.net/requestFriendLocationHttp") else {
            throw LocationSharingError.locationRequestsUnavailable
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "friendID": friend.id
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LocationSharingError.locationRequestFailed("Некорректный ответ сервера.")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw LocationSharingError.locationRequestFailed(serverErrorMessage(from: data) ?? "HTTP \(httpResponse.statusCode)")
        }
    }

    private func serverErrorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8)
        }

        return object["message"] as? String ?? object["code"] as? String
    }

    private func requestAlwaysAuthorization() async -> Bool {
        isRequestingAlwaysAuthorization = true
        return await withCheckedContinuation { continuation in
            locationAuthorizationContinuation = continuation
            locationManager.requestAlwaysAuthorization()
        }
    }

    private func requestWhenInUseThenAlwaysAuthorization() async -> Bool {
        shouldRequestAlwaysAfterWhenInUse = true
        return await withCheckedContinuation { continuation in
            locationAuthorizationContinuation = continuation
            locationManager.requestWhenInUseAuthorization()
        }
    }

    private func registerLocationPushTokenIfPossible(for userID: String) {
        guard locationManager.authorizationStatus == .authorizedAlways else { return }

        locationPushTokenRegistrationTask?.cancel()
        locationPushTokenRegistrationTask = Task { [weak self, userID] in
            guard let self else { return }

            do {
                let token = try await getLocationPushToken()
                print("hii \(token)")
                try await saveLocationPushToken(token, for: userID)
            } catch {
                logger.error("Failed to register location push token: \(error.localizedDescription)")
                await saveLocationPushTokenStatus(
                    "failed",
                    error: error,
                    for: userID
                )
            }
        }
    }
    
    private func getLocationPushTokenWithTimeout() async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { [weak self] in
                guard let self else { throw LocationSharingError.missingLocationPushToken }
                return try await getLocationPushToken()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 20_000_000_000)
                throw LocationSharingError.locationPushTokenTimeout
            }

            guard let token = try await group.next() else {
                throw LocationSharingError.missingLocationPushToken
            }
            group.cancelAll()
            return token
        }
    }

    @MainActor
    private func getLocationPushToken() async throws -> String {
        try await locationManager.startMonitoringLocationPushes()
            .map { String(format: "%02.2hhx", $0) }
            .joined()
    }

    private func saveLocationPushToken(_ token: String, for userID: String) async throws {
        try await db.collection("users").document(userID).setData([
            "locationPushToken": token,
            "locationPushTokenStatus": "registered",
            "locationPushTokenError": FieldValue.delete(),
            "locationPushTokenUpdatedAt": Timestamp(date: .now)
        ], merge: true)
    }

    private func saveLocationPushTokenStatus(_ status: String, error: Error, for userID: String) async {
        let nsError = error as NSError
        do {
            try await db.collection("users").document(userID).setData([
                "locationPushTokenStatus": status,
                "locationPushTokenError": error.localizedDescription,
                "locationPushTokenErrorCode": nsError.code,
                "locationPushTokenErrorDomain": nsError.domain,
                "locationPushTokenUpdatedAt": Timestamp(date: .now)
            ], merge: true)
        } catch {
            logger.error("Failed to save location push token status: \(error.localizedDescription)")
        }
    }

    private func clearStaleLocationPushAuthorizationStatus() async {
        guard let currentUserID else { return }

        do {
            try await db.collection("users").document(currentUserID).setData([
                "locationPushTokenStatus": "pendingAuthorization",
                "locationPushTokenError": FieldValue.delete(),
                "locationPushTokenUpdatedAt": Timestamp(date: .now)
            ], merge: true)
        } catch {
            logger.error("Failed to clear stale location push status: \(error.localizedDescription)")
        }
    }

    private func saveLocationAuthorizationStatus(_ status: CLAuthorizationStatus) async {
        guard let currentUserID else { return }

        var payload: [String: Any] = [
            "locationAuthorizationStatus": status.locationSharingDescription,
            "locationAuthorizationStatusRaw": status.rawValue,
            "locationAuthorizationStatusUpdatedAt": Timestamp(date: .now)
        ]

        if status == .notDetermined {
            payload["locationPushTokenStatus"] = "pendingAuthorization"
            payload["locationPushTokenError"] = FieldValue.delete()
            payload["locationPushTokenUpdatedAt"] = Timestamp(date: .now)
        }

        do {
            try await db.collection("users").document(currentUserID).setData(payload, merge: true)
        } catch {
            logger.error("Failed to save location authorization status: \(error.localizedDescription)")
        }
    }

    private enum LocationSharingError: LocalizedError {
        case missingLocationPushToken
        case locationPushTokenTimeout
        case locationRequestsUnavailable
        case firebaseUserMissing
        case locationRequestFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingLocationPushToken:
                return "Location push token is missing."
            case .locationPushTokenTimeout:
                return "CoreLocation did not return location push token within 20 seconds."
            case .locationRequestsUnavailable:
                return "Firebase Functions is not available."
            case .firebaseUserMissing:
                return "Firebase Auth сессия не найдена. Выйдите из аккаунта и войдите снова."
            case .locationRequestFailed(let message):
                if message.localizedCaseInsensitiveContains("UNAUTHENTICATED") ||
                    message.localizedCaseInsensitiveContains("Authentication is required") {
                    return "Сервер не получил Firebase Auth токен. Выйдите из аккаунта и войдите снова."
                }
                if message.localizedCaseInsensitiveContains("Friend has no location push token") {
                    return "У друга пока нет location push токена. Нужно открыть приложение друга и выдать разрешение геолокации «Всегда»."
                }
                if message.localizedCaseInsensitiveContains("LOCATION_PUSH_CALLBACK_URL") {
                    return "На сервере не настроен LOCATION_PUSH_CALLBACK_URL."
                }
                if message.localizedCaseInsensitiveContains("permission-denied") ||
                    message.localizedCaseInsensitiveContains("not your friend") {
                    return "Сервер не подтвердил, что пользователь находится в друзьях."
                }
                if message.localizedCaseInsensitiveContains("not-found") {
                    return "Функция requestFriendLocation не найдена. Проверь деплой Cloud Functions."
                }
                return message
            }
        }
    }

    func observeCurrentLocation() -> AsyncStream<SharedLocation?> {
        AsyncStream { continuation in
            currentLocationContinuation = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.currentLocationContinuation = nil
                }
            }
        }
    }

    private func startUpdatingIfAuthorized() {
        guard currentUserID != nil else { return }

        let status = locationManager.authorizationStatus
        guard status == .authorizedAlways || status == .authorizedWhenInUse else { return }
        locationManager.startUpdatingLocation()
    }

    private func propagateLocation(_ location: SharedLocation) async {
        guard let currentUserID, !friends.isEmpty else { return }

        var sharedLocationPayload: [String: Any] = [
            "latitude": location.latitude,
            "longitude": location.longitude,
            "updatedAt": Timestamp(date: location.updatedAt),
            "horizontalAccuracy": location.horizontalAccuracy as Any
        ]
        if let speed = location.speed {
            sharedLocationPayload["speed"] = speed
        }
        if let batteryLevelPercent = location.batteryLevelPercent {
            sharedLocationPayload["batteryLevelPercent"] = batteryLevelPercent
        }

        let payload: [String: Any] = [
            "sharedLocation": sharedLocationPayload,
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
                    .document(currentUserID)
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
            await saveLocationAuthorizationStatus(status)
            if status == .authorizedWhenInUse, shouldRequestAlwaysAfterWhenInUse {
                shouldRequestAlwaysAfterWhenInUse = false
                isRequestingAlwaysAuthorization = true
                locationManager.requestAlwaysAuthorization()
                startUpdatingIfAuthorized()
                return
            }

            if let continuation = locationAuthorizationContinuation {
                if status == .authorizedAlways || status == .denied || status == .restricted ||
                    (status == .authorizedWhenInUse && isRequestingAlwaysAuthorization) {
                    shouldRequestAlwaysAfterWhenInUse = false
                    isRequestingAlwaysAuthorization = false
                    locationAuthorizationContinuation = nil
                    continuation.resume(returning: status == .authorizedAlways)
                }
            }

            startUpdatingIfAuthorized()
            if status == .authorizedAlways, let currentUserID {
                registerLocationPushTokenIfPossible(for: currentUserID)
            }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else { return }
        let coordinate = location.coordinate
        let timestamp = location.timestamp
        let horizontalAccuracy = location.horizontalAccuracy
        let speed = location.speed

        Task { @MainActor [weak self] in
            guard let self else { return }
            let sharedLocation = SharedLocation(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                updatedAt: timestamp,
                horizontalAccuracy: horizontalAccuracy,
                speed: speed >= 0 ? speed : nil,
                batteryLevelPercent: currentBatteryLevelPercent()
            )
            currentLocationContinuation?.yield(sharedLocation)
            await propagateLocation(sharedLocation)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.logger.error("Location manager failed: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func currentBatteryLevelPercent() -> Int? {
        let batteryLevel = UIDevice.current.batteryLevel
        guard batteryLevel >= 0 else { return nil }
        return Int((batteryLevel * 100).rounded())
    }
}

private extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

private extension CLAuthorizationStatus {
    var locationSharingDescription: String {
        switch self {
        case .notDetermined:
            return "notDetermined"
        case .restricted:
            return "restricted"
        case .denied:
            return "denied"
        case .authorizedAlways:
            return "authorizedAlways"
        case .authorizedWhenInUse:
            return "authorizedWhenInUse"
        @unknown default:
            return "unknown"
        }
    }
}

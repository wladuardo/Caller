import Combine
import CoreLocation
import Foundation
import SwiftUI
import UIKit
import UserNotifications

@MainActor
final class OnboardingViewModel: NSObject, ObservableObject {
    struct Page: Identifiable {
        enum Kind {
            case mapFriends
            case callsAndVideo
            case messenger
        }

        enum PermissionAction {
            case none
            case location
            case notifications
        }

        let id: Kind
        let title: String
        let subtitle: String
        let permissionMessage: String?
        let systemImage: String
        let accent: Color
        let actionTitle: String
        let permissionAction: PermissionAction
    }

    @Published var selectedIndex = 0
    @Published private(set) var isRequestInFlight = false

    let pages: [Page] = [
        .init(
            id: .mapFriends,
            title: "Друзья на карте",
            subtitle: "Смотрите, где находятся ваши друзья в реальном времени и оставайтесь рядом.",
            permissionMessage: "Дайте доступ к вашей геопозиции, чтобы друзья тоже могли видеть вас на карте.",
            systemImage: "map.fill",
            accent: .cyan,
            actionTitle: "Далее",
            permissionAction: .location
        ),
        .init(
            id: .callsAndVideo,
            title: "Звонки и видео",
            subtitle: "Запускайте аудио- и видеозвонки друзьям в один тап прямо из чата или контактов.",
            permissionMessage: "Включите уведомления, чтобы не пропускать входящие звонки и срочные события.",
            systemImage: "video.fill",
            accent: .blue,
            actionTitle: "Далее",
            permissionAction: .notifications
        ),
        .init(
            id: .messenger,
            title: "Мессенджер",
            subtitle: "Пишите друзьям мгновенно, делитесь важным и оставайтесь на связи каждый день.",
            permissionMessage: nil,
            systemImage: "message.fill",
            accent: .mint,
            actionTitle: "Начать",
            permissionAction: .none
        )
    ]

    private let locationManager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<Bool, Never>?
    private var isRequestingAlwaysAuthorization = false

    override init() {
        super.init()
        locationManager.delegate = self
    }

    var currentPage: Page {
        pages[selectedIndex]
    }

    var canSkip: Bool {
        selectedIndex < pages.count - 1
    }

    var isLastPage: Bool {
        selectedIndex == pages.count - 1
    }

    func handlePrimaryAction(onFinish: @escaping () -> Void) async {
        guard !isRequestInFlight else { return }
        isRequestInFlight = true
        defer { isRequestInFlight = false }

        switch currentPage.permissionAction {
        case .none:
            break
        case .location:
            let granted = await requestLocationPermissionIfNeeded()
            guard granted else { return }
        case .notifications:
            _ = await requestNotificationPermissionIfNeeded()
        }

        if isLastPage {
            onFinish()
        } else {
            goNext()
        }
    }

    func skip(onFinish: @escaping () -> Void) {
        if isLastPage {
            onFinish()
        } else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                selectedIndex = pages.count - 1
            }
        }
    }

    private func goNext() {
        guard selectedIndex + 1 < pages.count else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
            selectedIndex += 1
        }
    }

    private func requestNotificationPermissionIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            await MainActor.run {
                UIApplication.shared.registerForRemoteNotifications()
            }
            return true
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
                if granted {
                    await MainActor.run {
                        UIApplication.shared.registerForRemoteNotifications()
                    }
                }
                return granted
            } catch {
                return false
            }
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    private func requestLocationPermissionIfNeeded() async -> Bool {
        let status = locationManager.authorizationStatus
        switch status {
        case .authorizedAlways:
            return true
        case .authorizedWhenInUse:
            return await requestAlwaysAuthorization()
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await requestWhenInUseThenAlwaysAuthorization()
        @unknown default:
            return false
        }
    }

    private func requestWhenInUseThenAlwaysAuthorization() async -> Bool {
        isRequestingAlwaysAuthorization = false
        return await withCheckedContinuation { continuation in
            locationContinuation = continuation
            locationManager.requestWhenInUseAuthorization()
        }
    }

    private func requestAlwaysAuthorization() async -> Bool {
        isRequestingAlwaysAuthorization = true
        return await withCheckedContinuation { continuation in
            locationContinuation = continuation
            locationManager.requestAlwaysAuthorization()
        }
    }
}

extension OnboardingViewModel: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self, let continuation = locationContinuation else { return }
            let status = manager.authorizationStatus
            switch status {
            case .authorizedAlways:
                locationContinuation = nil
                isRequestingAlwaysAuthorization = false
                continuation.resume(returning: true)
            case .authorizedWhenInUse:
                if isRequestingAlwaysAuthorization {
                    break
                }
                isRequestingAlwaysAuthorization = true
                locationManager.requestAlwaysAuthorization()
                break
            case .denied, .restricted:
                locationContinuation = nil
                isRequestingAlwaysAuthorization = false
                continuation.resume(returning: false)
            case .notDetermined:
                break
            @unknown default:
                locationContinuation = nil
                isRequestingAlwaysAuthorization = false
                continuation.resume(returning: false)
            }
        }
    }
}

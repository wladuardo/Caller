import CoreLocation
import Foundation
import UIKit

final class LocationPushService: NSObject, CLLocationPushServiceExtension {
    private var completion: (() -> Void)?
    private var locationManager: CLLocationManager?
    private var payload: LocationPushPayload?

    func didReceiveLocationPushPayload(_ payload: [String: Any], completion: @escaping () -> Void) {
        self.completion = completion
        self.payload = LocationPushPayload(payload: payload)

        UIDevice.current.isBatteryMonitoringEnabled = true

        let locationManager = CLLocationManager()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestLocation()
        self.locationManager = locationManager
    }

    func serviceExtensionWillTerminate() {
        finish()
    }

    private func sendLocation(_ location: CLLocation) {
        guard let payload, let callbackURL = payload.callbackURL else {
            finish()
            return
        }

        var request = URLRequest(url: callbackURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        request.httpBody = try? JSONEncoder().encode(
            LocationPushResponse(
                requestID: payload.requestID,
                callbackSecret: payload.callbackSecret,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                horizontalAccuracy: location.horizontalAccuracy,
                speed: location.speed >= 0 ? location.speed : nil,
                updatedAt: location.timestamp,
                batteryLevelPercent: currentBatteryLevelPercent()
            )
        )

        URLSession.shared.dataTask(with: request) { [weak self] _, _, _ in
            self?.finish()
        }.resume()
    }

    private func finish() {
        let completion = completion
        self.completion = nil
        locationManager = nil
        payload = nil
        completion?()
    }

    private func currentBatteryLevelPercent() -> Int? {
        let batteryLevel = UIDevice.current.batteryLevel
        guard batteryLevel >= 0 else { return nil }
        return Int((batteryLevel * 100).rounded())
    }
}

extension LocationPushService: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            finish()
            return
        }

        sendLocation(location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish()
    }
}

private struct LocationPushPayload {
    let callbackURL: URL?
    let requestID: String?
    let callbackSecret: String?

    init(payload: [String: Any]) {
        if let callbackURLString = payload["callbackURL"] as? String {
            callbackURL = URL(string: callbackURLString)
        } else {
            callbackURL = nil
        }

        requestID = payload["requestID"] as? String
        callbackSecret = payload["callbackSecret"] as? String
    }
}

private struct LocationPushResponse: Encodable {
    let requestID: String?
    let callbackSecret: String?
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: CLLocationAccuracy
    let speed: CLLocationSpeed?
    let updatedAt: Date
    let batteryLevelPercent: Int?
}

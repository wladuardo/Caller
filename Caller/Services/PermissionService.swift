import AVFoundation
import Foundation

enum PermissionKind {
    case microphone
    case camera
    case location
}

protocol PermissionServicing {
    func requestMicrophoneAccess() async -> Bool
    func requestCameraAccess() async -> Bool
    func deniedMessage(for kind: PermissionKind) -> String
}

struct PermissionService: PermissionServicing {
    func requestMicrophoneAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    func requestCameraAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    func deniedMessage(for kind: PermissionKind) -> String {
        switch kind {
        case .microphone:
            return "Для звонков необходим доступ к микрофону. Включите его в Настройках."
        case .camera:
            return "Для видеозвонков необходим доступ к камере. Включите его в Настройках."
        case .location:
            return "Для отображения друзей на карте необходим доступ к геопозиции. Включите его в Настройках."
        }
    }
}

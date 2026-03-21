import AVFoundation
import ScreenCaptureKit

enum PermissionStatus {
    case granted
    case denied
    case notDetermined
}

enum Permissions {
    static func checkScreenRecording() async -> PermissionStatus {
        do {
            _ = try await SCShareableContent.current
            return .granted
        } catch {
            return .denied
        }
    }

    static var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    static func promptAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func checkMicrophone() -> PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    static func requestMicrophone() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }
}

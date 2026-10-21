import AppKit
import AVFoundation
import Speech

// MARK: - Permission Status Enum

public enum AppPermissionStatus: String, Equatable {
    case granted = "Granted"
    case denied = "Denied"
    case notDetermined = "Not Requested"
    case restricted = "Restricted"

    public var isGranted: Bool {
        self == .granted
    }
}

// MARK: - Permissions Manager

public final class PermissionsManager: ObservableObject {
    public static let shared = PermissionsManager()

    @Published public var microphoneStatus: AppPermissionStatus = .notDetermined
    @Published public var accessibilityStatus: AppPermissionStatus = .notDetermined
    @Published public var speechRecognitionStatus: AppPermissionStatus = .notDetermined

    public var allRequiredPermissionsGranted: Bool {
        microphoneStatus == .granted && accessibilityStatus == .granted
    }

    public init() {
        refreshStatuses()
    }

    public func refreshStatuses() {
        // 1. Microphone Check
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphoneStatus = .granted
        case .denied:
            microphoneStatus = .denied
        case .restricted:
            microphoneStatus = .restricted
        case .notDetermined:
            microphoneStatus = .notDetermined
        @unknown default:
            microphoneStatus = .notDetermined
        }

        // 2. Accessibility Check (required for paste & voice commands)
        if AXIsProcessTrusted() {
            accessibilityStatus = .granted
        } else {
            accessibilityStatus = .denied
        }

        // 3. Speech Recognition Check
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            speechRecognitionStatus = .granted
        case .denied:
            speechRecognitionStatus = .denied
        case .restricted:
            speechRecognitionStatus = .restricted
        case .notDetermined:
            speechRecognitionStatus = .notDetermined
        @unknown default:
            speechRecognitionStatus = .notDetermined
        }
    }

    // MARK: - Request Actions

    public func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            DispatchQueue.main.async {
                self?.refreshStatuses()
                completion(granted)
            }
        }
    }

    public func requestAccessibilityPermission() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options)

        // Poll briefly after prompt
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.refreshStatuses()
        }
    }

    public func openSystemSettings(for section: PrivacySection) {
        let urlString: String
        switch section {
        case .microphone:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case .accessibility:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .speechRecognition:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition"
        }

        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
        }
    }

    public enum PrivacySection {
        case microphone
        case accessibility
        case speechRecognition
    }
}

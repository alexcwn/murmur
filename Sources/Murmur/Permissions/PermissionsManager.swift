import AVFoundation
import AppKit
import ApplicationServices
import CoreGraphics
import Observation

/// The three TCC grants this app cannot function without.
///
/// Note for development: macOS keys these grants to bundle ID *plus* code
/// signature. An ad-hoc signed rebuild gets a new hash and silently loses every
/// grant. `scripts/make-cert.sh` creates a stable self-signed identity so you
/// approve each of these once instead of once per build.
@Observable
final class PermissionsManager {
    enum Grant: String, CaseIterable, Identifiable {
        case microphone = "Microphone"
        case accessibility = "Accessibility"
        case inputMonitoring = "Input Monitoring"

        var id: String { rawValue }

        var rationale: String {
            switch self {
            case .microphone: "To hear you while the hotkey is held."
            case .accessibility: "To insert text at your cursor in other apps."
            case .inputMonitoring: "To detect the push-to-talk key globally."
            }
        }

        var settingsURL: URL {
            let anchor = switch self {
            case .microphone: "Privacy_Microphone"
            case .accessibility: "Privacy_Accessibility"
            case .inputMonitoring: "Privacy_ListenEvent"
            }
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
        }
    }

    private(set) var granted: Set<Grant> = []

    var allGranted: Bool { granted.count == Grant.allCases.count }
    var missing: [Grant] { Grant.allCases.filter { !granted.contains($0) } }

    func refresh() async {
        var current: Set<Grant> = []

        if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
            current.insert(.microphone)
        }
        if AXIsProcessTrusted() {
            current.insert(.accessibility)
        }
        if CGPreflightListenEventAccess() {
            current.insert(.inputMonitoring)
        }
        granted = current
    }

    /// Triggers the system prompt where one exists, and opens the right
    /// Settings pane where it doesn't.
    func request(_ grant: Grant) async {
        switch grant {
        case .microphone:
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        case .accessibility:
            // Prompting adds us to the list; the user still has to flip the switch.
            // Spelled literally because `kAXTrustedCheckOptionPrompt` is imported
            // as a mutable global and so isn't readable under strict concurrency.
            let options = ["AXTrustedCheckOptionPrompt": true]
            _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        case .inputMonitoring:
            CGRequestListenEventAccess()
        }
        await refresh()
        if !granted.contains(grant) {
            NSWorkspace.shared.open(grant.settingsURL)
        }
    }
}

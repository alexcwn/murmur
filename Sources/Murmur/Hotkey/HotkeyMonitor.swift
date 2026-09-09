import AppKit
import CoreGraphics

enum Hotkey: String, CaseIterable, Identifiable, Codable, Sendable {
    case fn
    case rightOption
    case rightCommand

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fn: "Fn (globe)"
        case .rightOption: "Right Option"
        case .rightCommand: "Right Command"
        }
    }

    /// Virtual keycode we watch in `.flagsChanged`. Modifier-only push-to-talk is
    /// the reason this is a CGEventTap and not `RegisterEventHotKey` — Carbon
    /// hotkeys cannot express "a modifier is being held".
    var keyCode: CGKeyCode {
        switch self {
        case .fn: 0x3F           // kVK_Function
        case .rightOption: 0x3D  // kVK_RightOption
        case .rightCommand: 0x36 // kVK_RightCommand
        }
    }

    var flag: CGEventFlags {
        switch self {
        case .fn: .maskSecondaryFn
        case .rightOption: .maskAlternate
        case .rightCommand: .maskCommand
        }
    }
}

/// Watches a global event tap for a modifier key being held down.
///
/// The tap is listen-only (`.listenOnly`), so we never swallow the key. That is
/// deliberate: swallowing Fn would break the user's globe-key behaviour system
/// wide, and a passive tap is far less likely to be disabled by the system.
final class HotkeyMonitor {
    var hotkey: Hotkey = .fn
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isHeld = false

    func start() -> Bool {
        guard tap == nil else { return true }
        guard CGPreflightListenEventAccess() else {
            CGRequestListenEventAccess()
            return false
        }

        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            // The tap is attached to the main run loop, so we are already on the
            // main thread and the isolation assumption below is sound.
            MainActor.assumeIsolated { monitor.handle(type: type, event: event) }
            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.runLoopSource = source
        return true
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        isHeld = false
    }

    private func handle(type: CGEventType, event: CGEvent) {
        // macOS disables a tap that takes too long in its callback. Re-arm rather
        // than silently dying — this is the single most common way a global
        // hotkey "randomly stops working".
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        guard type == .flagsChanged else { return }
        guard CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode)) == hotkey.keyCode else { return }

        let down = event.flags.contains(hotkey.flag)
        guard down != isHeld else { return }
        isHeld = down
        down ? onPress?() : onRelease?()
    }
}

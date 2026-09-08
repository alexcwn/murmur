import AppKit
import ApplicationServices
import OSLog

/// Gets text to the user's cursor in whatever app is focused.
///
/// Strategy chain, cheapest and cleanest first:
///   1. Accessibility `AXSelectedText` — no clipboard involvement, replaces a
///      selection correctly. Works in native apps; unreliable in Electron and
///      most web views.
///   2. Pasteboard + synthetic ⌘V — universal, but briefly borrows the
///      clipboard, so we restore it afterwards.
final class TextInjector {
    private let log = Logger(subsystem: "com.alexchoo.murmur", category: "injector")

    func inject(_ text: String, into context: AppContext) {
        guard !text.isEmpty else { return }
        if injectViaAccessibility(text) { return }
        injectViaPaste(text)
    }

    // MARK: - Accessibility

    private func injectViaAccessibility(_ text: String) -> Bool {
        guard AXIsProcessTrusted() else { return false }

        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused as! AXUIElement?
        else { return false }

        // Only attempt this where the element actually advertises editable text;
        // setting AXSelectedText on a non-text element silently no-ops, which
        // would look to the user like the dictation vanished.
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success,
              settable.boolValue
        else { return false }

        let result = AXUIElementSetAttributeValue(
            element, kAXSelectedTextAttribute as CFString, text as CFTypeRef
        )
        return result == .success
    }

    // MARK: - Pasteboard

    private func injectViaPaste(_ text: String) {
        let pasteboard = NSPasteboard.general
        let saved = snapshot(of: pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        guard postCommandV() else {
            log.error("could not synthesize paste; text left on clipboard")
            return
        }

        // The paste is asynchronous in the target app. Restoring immediately
        // races it and pastes the *old* clipboard contents instead.
        Task { [saved] in
            try? await Task.sleep(for: .milliseconds(250))
            restore(saved, to: NSPasteboard.general)
        }
    }

    private func postCommandV() -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        else { return false }

        // Suppress local keyboard state so a still-held Fn (or any other modifier
        // the user hasn't released yet) doesn't turn our ⌘V into ⌘⌥V.
        source.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cgAnnotatedSessionEventTap)
        up.post(tap: .cgAnnotatedSessionEventTap)
        return true
    }

    private func snapshot(of pasteboard: NSPasteboard) -> [[String: Data]] {
        pasteboard.pasteboardItems?.compactMap { item in
            var payload: [String: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { payload[type.rawValue] = data }
            }
            return payload.isEmpty ? nil : payload
        } ?? []
    }

    private func restore(_ snapshot: [[String: Data]], to pasteboard: NSPasteboard) {
        guard !snapshot.isEmpty else { return }
        pasteboard.clearContents()
        let items = snapshot.map { payload -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in payload {
                item.setData(data, forType: NSPasteboard.PasteboardType(type))
            }
            return item
        }
        pasteboard.writeObjects(items)
    }
}

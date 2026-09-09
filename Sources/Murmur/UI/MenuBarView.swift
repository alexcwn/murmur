import AppKit
import SwiftUI

/// Secondary now: status and the hotkey while you're working in another app.
/// The main window is the interface.
struct MenuBarView: View {
    @Bindable var controller: DictationController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(controller.state.label)

        if case .needsPermissions = controller.state {
            Divider()
            ForEach(controller.permissions.missing) { grant in
                Button("Grant \(grant.rawValue)…") {
                    Task {
                        await controller.permissions.request(grant)
                        await controller.bootstrap()
                    }
                }
            }
        }

        Divider()

        Button(controller.state == .listening ? "Stop Recording" : "Start Recording") {
            controller.toggleManualCapture()
        }
        .disabled(controller.state != .idle && controller.state != .listening)

        Toggle("Raw mode", isOn: $controller.rawMode)

        if let last = controller.history.entries.first {
            Button("Copy Last Dictation") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(last.text, forType: .string)
            }
        }

        Divider()

        Button("Open Murmur") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: MurmurApp.mainWindowID)
        }

        SettingsLink { Text("Settings…") }

        Divider()

        Button("Quit Murmur") {
            controller.shutdown()
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}

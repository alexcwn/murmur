import AppKit
import SwiftUI

struct MenuBarView: View {
    @Bindable var controller: DictationController

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

        Toggle("Raw mode (skip cleanup)", isOn: $controller.rawMode)

        Picker("Push-to-talk key", selection: $controller.hotkey) {
            ForEach(Hotkey.allCases) { key in
                Text(key.label).tag(key)
            }
        }

        if !controller.lastInsertion.isEmpty {
            Divider()
            Button("Copy last dictation") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(controller.lastInsertion, forType: .string)
            }
        }

        Divider()

        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",", modifiers: .command)

        Button("Quit Murmur") {
            controller.shutdown()
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}

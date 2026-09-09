import AppKit
import SwiftUI

@main
struct MurmurApp: App {
    static let mainWindowID = "murmur.main"

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Murmur", id: Self.mainWindowID) {
            MainWindowView(controller: delegate.controller)
        }
        .defaultSize(width: 720, height: 660)
        .commands { MurmurCommands(controller: delegate.controller) }

        // Kept for status and for triggering a recording without leaving the
        // app you're working in — secondary to the window, not the interface.
        MenuBarExtra {
            MenuBarView(controller: delegate.controller)
        } label: {
            Image(systemName: delegate.controller.state.symbolName)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(controller: delegate.controller)
        }
    }
}

/// Menu items that belong to the app rather than to a view.
struct MurmurCommands: Commands {
    @Bindable var controller: DictationController

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(controller.state == .listening ? "Stop Recording" : "Start Recording") {
                controller.toggleManualCapture()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(controller.state != .idle && controller.state != .listening)
        }

        CommandGroup(after: .toolbar) {
            Toggle("Raw Mode", isOn: $controller.rawMode)
                .keyboardShortcut("j", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .help) {
            Button("Open Dictionary File") { controller.dictionaryStore.revealInFinder() }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = DictationController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await controller.bootstrap() }
    }

    /// Murmur keeps working while its window is closed — the hotkey is the
    /// point. Closing the window must not quit the app.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Clicking the Dock icon with no window open brings the machine back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { sender.windows.first?.makeKeyAndOrderFront(nil) }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.shutdown()
    }
}

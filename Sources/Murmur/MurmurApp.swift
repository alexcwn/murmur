import AppKit
import SwiftUI

@main
struct MurmurApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
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

/// SwiftUI has no launch hook that fires reliably for an `LSUIElement` menu bar
/// app before the user opens the menu, and pre-warming has to happen at launch
/// to be worth anything. Hence a delegate.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = DictationController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await controller.bootstrap() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.shutdown()
    }
}

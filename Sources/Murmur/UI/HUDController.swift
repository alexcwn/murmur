import AppKit
import SwiftUI

/// The floating "listening" pill.
///
/// This must never take key focus. If it does, the text field the user was
/// typing in loses its cursor and the injection lands nowhere — the single most
/// common bug in home-grown versions of this app. Hence `.nonactivatingPanel`,
/// `becomesKeyOnlyIfNeeded`, and an explicit `false` from `canBecomeKey`.
final class HUDController {
    enum Mode: Equatable {
        case listening
        case thinking
    }

    private var panel: NSPanel?
    private var model = HUDModel()

    func show(state: Mode, transcript: String) {
        model.mode = state
        model.transcript = transcript

        let panel = panel ?? makePanel()
        self.panel = panel
        position(panel)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NonActivatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 64),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        // Sit above full-screen apps and follow the user across Spaces.
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: HUDView(model: model))
        return panel
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(
            NSPoint(
                x: frame.midX - size.width / 2,
                y: frame.minY + 96
            )
        )
    }
}

private final class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@Observable
final class HUDModel {
    var mode: HUDController.Mode = .listening
    var transcript = ""
}

private struct HUDView: View {
    @Bindable var model: HUDModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: model.mode == .listening ? "waveform" : "ellipsis")
                .symbolEffect(.variableColor.iterative, isActive: model.mode == .listening)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(model.mode == .listening ? .red : .secondary)

            Text(model.transcript.isEmpty ? "Listening…" : model.transcript)
                .font(.system(size: 13))
                .lineLimit(2)
                .truncationMode(.head)
                .foregroundStyle(model.transcript.isEmpty ? .secondary : .primary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(width: 260, height: 64, alignment: .leading)
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
    }
}

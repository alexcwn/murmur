import AppKit
import SwiftUI

/// Past dictations, searchable, each with copy.
struct TranscriptionsView: View {
    @Bindable var controller: DictationController
    @Binding var query: String

    @State private var copiedID: UUID?

    private var results: [Transcription] { controller.history.search(query) }

    var body: some View {
        Group {
            if results.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: Tokens.Space.snug) {
                        ForEach(results) { entry in
                            row(entry)
                        }
                    }
                    .padding(Tokens.Space.base)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: Tokens.Space.snug) {
            Silkscreen(
                text: controller.history.entries.isEmpty ? "No recordings yet" : "No matches",
                size: .normal
            )
            if controller.history.entries.isEmpty {
                Text("Hold \(controller.hotkey.label) anywhere, or press Record.")
                    .font(Tokens.Typography.bodySmall)
                    .foregroundStyle(Tokens.Text.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(_ entry: Transcription) -> some View {
        Faceplate(padding: Tokens.Space.base) {
            VStack(alignment: .leading, spacing: Tokens.Space.snug) {
                HStack(spacing: Tokens.Space.snug) {
                    Silkscreen(text: entry.date.formatted(date: .abbreviated, time: .shortened),
                               size: .micro)
                    if let app = entry.appName {
                        Silkscreen(text: "→ \(app)", size: .micro, color: Tokens.Text.secondary)
                    } else {
                        Silkscreen(text: "Kept", size: .micro, color: Tokens.Text.secondary)
                    }
                    Spacer(minLength: 0)
                    Readout(text: String(format: "%.1fs", entry.duration), size: .small)
                        .font(Tokens.Typography.readoutSmall)

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(entry.text, forType: .string)
                        copiedID = entry.id
                        Task {
                            try? await Task.sleep(for: .seconds(1.4))
                            if copiedID == entry.id { copiedID = nil }
                        }
                    } label: {
                        Silkscreen(text: copiedID == entry.id ? "Copied" : "Copy", size: .micro,
                                   color: copiedID == entry.id ? Tokens.Signal.levelSafe : Tokens.Text.label)
                    }
                    .buttonStyle(.plain)
                    .help("Copy this transcription")
                }

                Text(entry.text)
                    .font(Tokens.Typography.body)
                    .foregroundStyle(Tokens.Text.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Whether the dictionary actually did anything.
                if entry.hasCorrections {
                    Well(padding: Tokens.Space.snug) {
                        VStack(alignment: .leading, spacing: Tokens.Space.tight) {
                            Silkscreen(text: "Dictionary applied", size: .micro,
                                       color: Tokens.Signal.levelWarn)
                            ForEach(entry.corrections) { c in
                                HStack(spacing: Tokens.Space.tight) {
                                    Text(c.matched)
                                        .font(Tokens.Typography.readoutSmall)
                                        .foregroundStyle(Tokens.Text.secondary)
                                        .strikethrough()
                                    Text("→")
                                        .font(Tokens.Typography.readoutSmall)
                                        .foregroundStyle(Tokens.Text.secondary)
                                    Text(c.replacement)
                                        .font(Tokens.Typography.readoutSmall)
                                        .foregroundStyle(Tokens.Text.readout)
                                    Silkscreen(
                                        text: c.source == .correction ? "pair" : "term",
                                        size: .micro, color: Tokens.Text.label
                                    )
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .contextMenu {
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.text, forType: .string)
            }
            Button("Copy raw transcript") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.raw, forType: .string)
            }
            Divider()
            Button("Delete", role: .destructive) { controller.history.delete(entry) }
        }
    }
}

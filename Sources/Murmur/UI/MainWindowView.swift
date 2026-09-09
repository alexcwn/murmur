import SwiftUI

/// The machine. Transport at the top, then whichever bank is selected.
struct MainWindowView: View {
    @Bindable var controller: DictationController

    enum Bank: String, CaseIterable, Identifiable {
        case transcriptions = "Transcriptions"
        case dictionary = "Dictionary"
        var id: String { rawValue }
    }

    @State private var bank: Bank = .transcriptions
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            TransportDeckView(controller: controller)
                .padding(Tokens.Space.loose)

            Seam()

            bankSelector

            Seam()

            switch bank {
            case .transcriptions:
                TranscriptionsView(controller: controller, query: $query)
            case .dictionary:
                DictionaryView(controller: controller, query: $query)
            }
        }
        .background(Tokens.Surface.chassis)
        .frame(minWidth: 620, minHeight: 560)
        .task { await controller.permissions.refresh() }
        .overlay(alignment: .top) {
            if controller.state == .needsPermissions { permissionsBanner }
        }
    }

    private var bankSelector: some View {
        HStack(spacing: Tokens.Space.base) {
            // A mode selector, the way a deck switches between functions.
            HStack(spacing: Tokens.Space.tight) {
                ForEach(Bank.allCases) { item in
                    DeckButton(
                        title: item.rawValue,
                        isLatched: bank == item,
                        indicator: Tokens.Signal.levelWarn
                    ) {
                        bank = item
                        query = ""
                    }
                    .frame(width: 144)
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: Tokens.Space.tight) {
                Silkscreen(text: "Search", size: .micro)
                TextField("", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .font(Tokens.Typography.bodySmall)
                    .frame(width: 190)
            }
        }
        .padding(.horizontal, Tokens.Space.loose)
        .padding(.vertical, Tokens.Space.base)
        .background(Tokens.Surface.chassis)
    }

    private var permissionsBanner: some View {
        HStack(spacing: Tokens.Space.snug) {
            Silkscreen(text: "Permissions needed", size: .normal, color: Tokens.Signal.record)
            Text(controller.permissions.missing.map(\.rawValue).joined(separator: ", "))
                .font(Tokens.Typography.bodySmall)
                .foregroundStyle(Tokens.Text.secondary)
            Spacer(minLength: 0)
            DeckButton(title: "Open Settings") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .frame(width: 130)
        }
        .padding(Tokens.Space.base)
        .background(Tokens.Surface.panel)
        .overlay(alignment: .bottom) { Seam() }
    }
}

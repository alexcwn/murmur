import SwiftUI

/// Hotkey and model. Everything else lives in the main window.
struct SettingsView: View {
    @Bindable var controller: DictationController

    private enum Tab: String, CaseIterable, Identifiable {
        case general = "General"
        case model = "Model"
        case permissions = "Permissions"
        var id: String { rawValue }
    }

    @State private var tab: Tab = .general

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Tokens.Space.tight) {
                ForEach(Tab.allCases) { t in
                    DeckButton(title: t.rawValue, isLatched: tab == t,
                               indicator: Tokens.Signal.levelWarn) { tab = t }
                        .frame(width: 128)
                }
            }
            .padding(Tokens.Space.base)

            Seam()

            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Space.loose) {
                    switch tab {
                    case .general: general
                    case .model: model
                    case .permissions: permissions
                    }
                }
                .padding(Tokens.Space.loose)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Tokens.Surface.chassis)
        .frame(width: 520, height: 440)
        .task { await controller.permissions.refresh() }
    }

    private var general: some View {
        Faceplate(padding: Tokens.Space.base) {
            VStack(alignment: .leading, spacing: Tokens.Space.base) {
                Silkscreen(text: "Push to talk", size: .large)

                HStack {
                    Silkscreen(text: "Hotkey", size: .micro)
                    Spacer()
                    Picker("", selection: $controller.hotkey) {
                        ForEach(Hotkey.allCases) { key in
                            Text(key.label).tag(key)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }

                Text("Hold the key anywhere to dictate into the app you're using. Release to insert.")
                    .font(Tokens.Typography.bodySmall)
                    .foregroundStyle(Tokens.Text.secondary)

                if controller.hotkey == .fn {
                    Well(padding: Tokens.Space.snug) {
                        Text("Set System Settings → Keyboard → “Press 🌐 key to” → Do Nothing, or the globe key also opens the emoji picker.")
                            .font(Tokens.Typography.bodySmall)
                            .foregroundStyle(Tokens.Text.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Divider()

                Toggle(isOn: $controller.rawMode) {
                    VStack(alignment: .leading, spacing: 2) {
                        Silkscreen(text: "Raw mode", size: .micro)
                        Text("Skip the cleanup pass. The dictionary still applies.")
                            .font(Tokens.Typography.bodySmall)
                            .foregroundStyle(Tokens.Text.secondary)
                    }
                }
            }
        }
    }

    private var model: some View {
        Faceplate(padding: Tokens.Space.base) {
            VStack(alignment: .leading, spacing: Tokens.Space.base) {
                Silkscreen(text: "Recognition", size: .large)

                HStack {
                    Silkscreen(text: "Engine", size: .micro)
                    Spacer()
                    Picker("", selection: $controller.engineChoice) {
                        ForEach(EngineChoice.allCases) { choice in
                            Text(choice.label).tag(choice)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 230)
                }

                Text(controller.engineChoice.detail)
                    .font(Tokens.Typography.bodySmall)
                    .foregroundStyle(Tokens.Text.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Silkscreen(text: "Language", size: .micro)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { controller.settings.values.localeIdentifier },
                        set: { controller.settings.values.localeIdentifier = $0 }
                    )) {
                        ForEach(Self.locales, id: \.self) { id in
                            Text(Locale.current.localizedString(forIdentifier: id) ?? id).tag(id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 230)
                }

                if let reason = controller.cleanupUnavailable {
                    Well(padding: Tokens.Space.snug) {
                        HStack(alignment: .top, spacing: Tokens.Space.snug) {
                            Rectangle().fill(Tokens.Signal.levelWarn).frame(width: 3)
                            VStack(alignment: .leading, spacing: Tokens.Space.tight) {
                                Silkscreen(text: "Cleanup unavailable", size: .micro,
                                           color: Tokens.Signal.levelWarn)
                                Text(reason)
                                    .font(Tokens.Typography.bodySmall)
                                    .foregroundStyle(Tokens.Text.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Button("Open Apple Intelligence settings…") {
                                    if let u = URL(string: "x-apple.systempreferences:com.apple.preferences.intelligence") {
                                        NSWorkspace.shared.open(u)
                                    }
                                }
                                .font(Tokens.Typography.bodySmall)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Text("Recognition and cleanup both run on this device. Changing the language takes effect on the next launch, and may download a model.")
                    .font(Tokens.Typography.bodySmall)
                    .foregroundStyle(Tokens.Text.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                Silkscreen(text: "Microphone", size: .large)
                HStack {
                    Silkscreen(text: "Release after", size: .micro)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { controller.settings.values.idleTimeoutSeconds },
                        set: { controller.settings.values.idleTimeoutSeconds = $0 }
                    )) {
                        Text("15 seconds").tag(15.0)
                        Text("30 seconds").tag(30.0)
                        Text("2 minutes").tag(120.0)
                        Text("Never").tag(86400.0)
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }
                Text("The system “mic in use” indicator stays lit while the microphone is held open.")
                    .font(Tokens.Typography.bodySmall)
                    .foregroundStyle(Tokens.Text.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var permissions: some View {
        Faceplate(padding: Tokens.Space.base) {
            VStack(alignment: .leading, spacing: Tokens.Space.base) {
                Silkscreen(text: "Required access", size: .large)
                ForEach(PermissionsManager.Grant.allCases) { grant in
                    HStack(spacing: Tokens.Space.snug) {
                        RecordLamp(isLit: controller.permissions.granted.contains(grant))
                        VStack(alignment: .leading, spacing: 2) {
                            Silkscreen(text: grant.rawValue, size: .micro)
                            Text(grant.rationale)
                                .font(Tokens.Typography.bodySmall)
                                .foregroundStyle(Tokens.Text.secondary)
                        }
                        Spacer(minLength: 0)
                        if !controller.permissions.granted.contains(grant) {
                            DeckButton(title: "Grant") {
                                Task {
                                    await controller.permissions.request(grant)
                                    await controller.bootstrap()
                                }
                            }
                            .frame(width: 84)
                        }
                    }
                }
            }
        }
    }

    /// Locales worth offering; the engine reports what it can actually install.
    private static let locales = [
        "en_US", "en_GB", "en_AU", "en_CA", "en_IN",
        "fr_FR", "de_DE", "es_ES", "it_IT", "pt_BR",
        "ja_JP", "ko_KR", "zh_CN", "zh_TW",
    ]
}

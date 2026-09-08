import SwiftUI

struct SettingsView: View {
    @Bindable var controller: DictationController

    var body: some View {
        Form {
            Section("Push to talk") {
                Picker("Hotkey", selection: $controller.hotkey) {
                    ForEach(Hotkey.allCases) { key in
                        Text(key.label).tag(key)
                    }
                }
                Toggle("Raw mode (skip cleanup)", isOn: $controller.rawMode)

                if controller.hotkey == .fn {
                    Text("Set System Settings → Keyboard → “Press 🌐 key to” → **Do Nothing** so the globe key doesn't also open the emoji picker.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Permissions") {
                ForEach(PermissionsManager.Grant.allCases) { grant in
                    HStack {
                        Image(systemName: controller.permissions.granted.contains(grant)
                              ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(controller.permissions.granted.contains(grant) ? .green : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(grant.rawValue)
                            Text(grant.rationale)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !controller.permissions.granted.contains(grant) {
                            Button("Grant…") {
                                Task {
                                    await controller.permissions.request(grant)
                                    await controller.bootstrap()
                                }
                            }
                        }
                    }
                }
            }

            Section("Status") {
                LabeledContent("State", value: controller.state.label)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 420)
        .task { await controller.permissions.refresh() }
    }
}

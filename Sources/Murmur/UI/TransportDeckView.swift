import SwiftUI

/// The top of the machine: meter, counter, record lamp, transport keys.
struct TransportDeckView: View {
    @Bindable var controller: DictationController

    private var isRecording: Bool { controller.state == .listening }

    var body: some View {
        Faceplate(padding: Tokens.Space.loose) {
            VStack(spacing: Tokens.Space.base) {
                HStack(alignment: .top, spacing: Tokens.Space.loose) {
                    VUMeterView(level: Double(controller.inputLevel), isActive: isRecording)
                        .frame(height: 96)

                    VStack(alignment: .trailing, spacing: Tokens.Space.tight) {
                        Silkscreen(text: "Counter", size: .micro)
                        Readout(text: elapsed, size: .normal)

                        HStack(spacing: Tokens.Space.snug) {
                            RecordLamp(isLit: isRecording)
                            Silkscreen(text: "Rec", size: .micro,
                                       color: isRecording ? Tokens.Signal.record : Tokens.Text.label)
                        }
                        .padding(.top, Tokens.Space.hair)

                        Silkscreen(text: controller.state.label, size: .micro,
                                   color: Tokens.Text.secondary)
                            .padding(.top, Tokens.Space.tight)
                    }
                    .frame(width: 112, alignment: .trailing)
                }

                HStack(spacing: Tokens.Space.snug) {
                    DeckButton(
                        title: "Record",
                        isLatched: isRecording,
                        tint: Tokens.Signal.record,
                        indicator: Tokens.Signal.record,
                        isEnabled: controller.state == .idle || isRecording
                    ) {
                        controller.toggleManualCapture()
                    }

                    DeckButton(title: "Stop", isEnabled: isRecording) {
                        controller.toggleManualCapture()
                    }

                    Spacer(minLength: Tokens.Space.base)

                    Toggle(isOn: $controller.rawMode) {
                        Silkscreen(text: "Raw", size: .micro)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .help("Skip the cleanup pass — useful for code and identifiers.")
                }

                if let reason = controller.cleanupUnavailable {
                    Well(padding: Tokens.Space.snug) {
                        HStack(alignment: .top, spacing: Tokens.Space.snug) {
                            Rectangle().fill(Tokens.Signal.levelWarn).frame(width: 3)
                            VStack(alignment: .leading, spacing: 2) {
                                Silkscreen(text: "Cleanup off", size: .micro,
                                           color: Tokens.Signal.levelWarn)
                                Text(reason)
                                    .font(Tokens.Typography.bodySmall)
                                    .foregroundStyle(Tokens.Text.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else if controller.rawMode {
                    Silkscreen(text: "Raw mode — cleanup skipped", size: .micro,
                               color: Tokens.Signal.levelWarn)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if isRecording && !controller.liveTranscript.isEmpty {
                    Well {
                        Text(controller.liveTranscript)
                            .font(Tokens.Typography.bodySmall)
                            .foregroundStyle(Tokens.Text.readout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(2)
                    }
                    .transition(.opacity)
                }
            }
        }
        .animation(Tokens.Motion.stateAnimation(), value: isRecording)
    }

    /// Manual captures show elapsed time; otherwise the counter rests at zero.
    private var elapsed: String {
        guard let started = controller.captureStarted, isRecording else { return "00:00" }
        let s = Int(Date().timeIntervalSince(started))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}

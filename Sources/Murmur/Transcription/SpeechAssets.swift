import AVFoundation
import Speech

/// Model installation and audio-format negotiation, shared by every engine
/// built on `SpeechAnalyzer`. The engines differ only in which module they
/// drive; this part is identical for all of them.
nonisolated enum SpeechAssets {

    /// Downloads the on-device model for these modules if it isn't present.
    /// Called at launch, never on a keypress — a first-run download is seconds.
    static func ensureInstalled(for modules: [any SpeechModule], locale: Locale) async throws {
        switch await AssetInventory.status(forModules: modules) {
        case .unsupported:
            throw AssetError.localeUnsupported(locale.identifier)
        case .installed:
            return
        case .supported, .downloading:
            if let request = try await AssetInventory.assetInstallationRequest(supporting: modules) {
                try await request.downloadAndInstall()
            }
        @unknown default:
            return
        }
    }

    static func bestFormat(for modules: [any SpeechModule]) async -> AVAudioFormat? {
        await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: modules)
    }

    enum AssetError: LocalizedError {
        case localeUnsupported(String)

        var errorDescription: String? {
            switch self {
            case .localeUnsupported(let id):
                "On-device speech isn't available for \(id)."
            }
        }
    }
}

/// Which recogniser drives transcription. Both are Apple's, both run entirely
/// on-device; they differ in what they are tuned for.
nonisolated enum EngineChoice: String, CaseIterable, Identifiable, Codable, Sendable {
    /// `SpeechTranscriber` — long-form prose. No spoken commands.
    case speech
    /// `DictationTranscriber` — what system Dictation uses. Understands spoken
    /// punctuation and "new line" natively, before any model sees the text.
    case dictation

    var id: String { rawValue }

    var label: String {
        switch self {
        case .speech: "Prose (Speech)"
        case .dictation: "Dictation (spoken commands)"
        }
    }

    var detail: String {
        switch self {
        case .speech:
            "Tuned for continuous prose. Spoken commands like “new line” are left to the cleanup pass, which handles them inconsistently."
        case .dictation:
            "The recogniser Apple's own Dictation uses. Understands “new line”, “period” and “comma” directly, so formatting does not depend on the cleanup model."
        }
    }
}

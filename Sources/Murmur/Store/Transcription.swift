import Foundation

/// One completed dictation. Text only — audio is never persisted.
struct Transcription: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var date: Date = .now
    /// What the recogniser produced, before cleanup or corrections.
    var raw: String
    /// What was actually inserted (or, for manual captures, what was kept).
    var text: String
    /// Bundle identifier and name of the destination, when there was one.
    var appName: String?
    var duration: TimeInterval
    /// Which dictionary corrections fired, so the user can tell whether the
    /// dictionary is doing anything at all.
    var corrections: [AppliedCorrection] = []
    /// Manual captures are kept but never injected.
    var wasInjected: Bool

    var hasCorrections: Bool { !corrections.isEmpty }
}

struct AppliedCorrection: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    /// The literal text that was matched, as the recogniser wrote it.
    var matched: String
    /// What it became.
    var replacement: String
    /// Which dictionary entry was responsible.
    var source: Source

    enum Source: String, Codable, Sendable {
        case correction   // an explicit "when you hear X, write Y" pair
        case term         // canonical casing for a known word
    }
}

/// The cleanup pass: filler removal, punctuation, list formatting, tone.
///
/// This is the layer that separates a dictation toy from something you'd
/// actually write email in, so it gets the same swappable treatment as the
/// transcription engine. A cloud implementation slots in here unchanged.
protocol TextFormatter: AnyObject {
    var displayName: String { get }
    /// Nil when cleanup is working. Set to a human-readable explanation when it
    /// is not, so the interface can say so rather than silently inserting raw
    /// text and leaving the user to wonder why nothing is being cleaned up.
    var unavailableReason: String? { get }
    func prepare() async
    func format(_ raw: String, context: AppContext) async -> String
}

/// Fallback when no model is available. Also what `rawMode` effectively uses.
final class PassthroughFormatter: TextFormatter {
    let displayName = "None (raw transcript)"
    let unavailableReason: String? = nil
    func prepare() async {}
    func format(_ raw: String, context: AppContext) async -> String { raw }
}

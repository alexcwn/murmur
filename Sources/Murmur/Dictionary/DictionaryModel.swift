import Foundation

/// A word or phrase the recogniser should know: product names, jargon,
/// colleagues. Used to bias the engine, and to normalise casing afterwards.
struct DictionaryTerm: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    /// The canonical spelling, exactly as it should be written.
    var text: String
    var note: String = ""
}

/// "When you hear X, write Y."
struct DictionaryCorrection: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    /// What the recogniser tends to produce.
    var heard: String
    /// What it should have produced.
    var write: String
    var note: String = ""
}

/// The on-disk shape. Deliberately plain and small so it can be edited by hand
/// in any text editor, diffed, and checked into a dotfiles repo.
struct MurmurDictionary: Codable, Equatable, Sendable {
    var version: Int = 1
    var terms: [DictionaryTerm] = []
    var corrections: [DictionaryCorrection] = []

    static let empty = MurmurDictionary()

    /// Seeded on first run so the file is self-explanatory when opened by hand.
    static let starter = MurmurDictionary(
        terms: [
            DictionaryTerm(text: "Anthropic"),
            DictionaryTerm(text: "Supabase"),
            DictionaryTerm(text: "Vercel"),
        ],
        corrections: [
            DictionaryCorrection(heard: "cloud code", write: "Claude Code",
                                 note: "Also catches CloudCode and Cloud-Code."),
        ]
    )
}

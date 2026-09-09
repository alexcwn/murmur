import Foundation

/// Warns before a dictionary entry starts quietly rewriting ordinary prose.
///
/// The real hazard is a single common word on the "heard" side: a rule for
/// `cloud` fires on every use of the word, whereas `cloud code` requires both
/// parts adjacent and is safe by construction. So the check is mostly about
/// arity, plus a lookup against the system word list.
nonisolated enum EntryValidator {

    struct Warning: Equatable {
        enum Severity: Equatable { case caution, danger }
        var severity: Severity
        var message: String
    }

    /// ~236k words shipped with macOS. Loaded once, off the main thread.
    private static let commonWords: Set<String> = {
        guard let text = try? String(contentsOfFile: "/usr/share/dict/words", encoding: .utf8) else {
            return []
        }
        return Set(text.split(separator: "\n").map { $0.lowercased() })
    }()

    /// Touch the list off the main thread so the first validation is instant.
    static func warmUp() {
        Task.detached(priority: .utility) { _ = EntryValidator.commonWords.count }
    }

    /// `heard` is the side that gets matched — the only side that can do damage.
    static func check(heard: String, write: String) -> Warning? {
        let h = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        let w = write.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !h.isEmpty else {
            return Warning(severity: .danger, message: "Nothing to match on.")
        }
        guard !w.isEmpty else {
            return Warning(severity: .danger, message: "Nothing to write.")
        }
        if h.compare(w, options: .caseInsensitive) == .orderedSame, h == w {
            return Warning(severity: .caution, message: "This rule changes nothing.")
        }

        let tokens = h.components(separatedBy: CharacterSet(charactersIn: " \t-–—_"))
            .filter { !$0.isEmpty }

        if h.count < 3 {
            return Warning(severity: .danger,
                           message: "“\(h)” is very short and will match often.")
        }

        // Multi-word rules need every part adjacent, which makes accidental
        // matches vanishingly unlikely. Single words are the dangerous case.
        guard tokens.count == 1, let only = tokens.first else { return nil }

        if commonWords.contains(only.lowercased()) {
            if only.count <= 8 {
                return Warning(
                    severity: .danger,
                    message: "“\(only)” is an ordinary English word. This will rewrite every use of it — consider a two-word rule instead."
                )
            }
            return Warning(
                severity: .caution,
                message: "“\(only)” is a real word, so this fires wherever it appears normally too."
            )
        }
        return nil
    }

    /// A bare term also generates a casing rule, so it carries the same risk.
    static func check(term: String) -> Warning? {
        let t = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else {
            return Warning(severity: .danger, message: "Nothing to add.")
        }
        let tokens = t.components(separatedBy: CharacterSet(charactersIn: " \t-–—_"))
            .filter { !$0.isEmpty }
        guard tokens.count == 1, let only = tokens.first else { return nil }

        // Only a problem if the canonical casing differs from the ordinary word,
        // because that is when it would start rewriting normal prose.
        if commonWords.contains(only.lowercased()), only != only.lowercased() {
            return Warning(
                severity: .caution,
                message: "“\(only.lowercased())” is an ordinary word. Every lowercase use will be recapitalised."
            )
        }
        return nil
    }
}

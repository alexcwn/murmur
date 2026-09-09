import Foundation

/// Applies the dictionary to recognised text.
///
/// This is the guaranteed path. Biasing the engine beforehand is a nudge that
/// often works; this pass is what actually holds. It runs last — after the
/// cleanup model — so nothing downstream can undo it.
///
/// Matching rules, in order of importance:
///
/// - **Whole-token only.** A rule is anchored with alphanumeric lookarounds, so
///   `cloud code` can never fire inside `Cloudflare`, and `cloud` on its own is
///   left alone because the pattern requires both parts.
/// - **Separator-tolerant.** The parts of a multi-word rule are joined with
///   "optional whitespace or hyphen", so one rule catches `cloud code`,
///   `CloudCode` and `Cloud-Code` alike — models glue words together
///   unpredictably.
/// - **Longest first, no overlaps.** All rules are matched against the original
///   text; a longer rule claims its range before a shorter one can, and the
///   shorter one is then refused that region.
struct CorrectionEngine {

    struct Rule {
        var pattern: NSRegularExpression
        var replacement: String
        var source: AppliedCorrection.Source
        /// Length of the matched-side text, for longest-first ordering.
        var weight: Int
    }

    private let rules: [Rule]

    init(dictionary: MurmurDictionary) {
        var built: [Rule] = []

        for c in dictionary.corrections {
            let heard = c.heard.trimmingCharacters(in: .whitespacesAndNewlines)
            let write = c.write.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !heard.isEmpty, !write.isEmpty else { continue }
            guard let re = Self.makePattern(for: heard) else { continue }
            built.append(Rule(pattern: re, replacement: write,
                              source: .correction, weight: heard.count))
        }

        // A known term also normalises its own casing: if the user taught us
        // "Supabase", writing "supabase" is still wrong.
        for t in dictionary.terms {
            let text = t.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            guard let re = Self.makePattern(for: text) else { continue }
            built.append(Rule(pattern: re, replacement: text,
                              source: .term, weight: text.count))
        }

        // Longest first; explicit corrections outrank casing normalisation at
        // equal length, because they express intent rather than a default.
        rules = built.sorted {
            $0.weight != $1.weight
                ? $0.weight > $1.weight
                : ($0.source == .correction && $1.source == .term)
        }
    }

    /// Splits on whitespace and hyphens, then rejoins the escaped parts with
    /// "optional whitespace or hyphen" and anchors the whole thing so it can
    /// only match a complete token run.
    private static func makePattern(for phrase: String) -> NSRegularExpression? {
        let parts = phrase
            .components(separatedBy: CharacterSet(charactersIn: " \t\n-–—_"))
            .filter { !$0.isEmpty }
            .map { NSRegularExpression.escapedPattern(for: $0) }
        guard !parts.isEmpty else { return nil }

        let body = parts.joined(separator: "[\\s\\-–—_]*")
        // Alphanumeric lookarounds rather than \b: predictable even when a term
        // begins or ends with punctuation, and it is what keeps `Cloudflare`
        // and `MyCloudCode` safe.
        let anchored = "(?<![A-Za-z0-9])" + body + "(?![A-Za-z0-9])"
        return try? NSRegularExpression(pattern: anchored, options: [.caseInsensitive])
    }

    /// Returns the corrected text and a record of everything that fired.
    func apply(to text: String) -> (text: String, applied: [AppliedCorrection]) {
        guard !rules.isEmpty, !text.isEmpty else { return (text, []) }

        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)

        var claimed: [NSRange] = []
        var hits: [(range: NSRange, replacement: String, source: AppliedCorrection.Source)] = []

        for rule in rules {
            rule.pattern.enumerateMatches(in: text, options: [], range: full) { match, _, _ in
                guard let r = match?.range, r.length > 0 else { return }
                // A longer rule already owns this text.
                guard !claimed.contains(where: { NSIntersectionRange($0, r).length > 0 }) else { return }

                let matched = ns.substring(with: r)
                // Casing normalisation that would change nothing is not a
                // correction, and should not be reported as one.
                if rule.source == .term, matched == rule.replacement { return }

                claimed.append(r)
                hits.append((r, rule.replacement, rule.source))
            }
        }

        guard !hits.isEmpty else { return (text, []) }

        // Apply back-to-front so earlier ranges stay valid.
        let ordered = hits.sorted { $0.range.location > $1.range.location }
        let result = NSMutableString(string: text)
        var applied: [AppliedCorrection] = []

        for hit in ordered {
            let matched = ns.substring(with: hit.range)
            result.replaceCharacters(in: hit.range, with: hit.replacement)
            applied.append(AppliedCorrection(matched: matched,
                                             replacement: hit.replacement,
                                             source: hit.source))
        }

        return (result as String, applied.reversed())
    }

    /// Terms and target spellings handed to the recogniser as context.
    ///
    /// Kept short on purpose: long context lists make these models drift and
    /// invent text on quiet audio, which is far worse than a missed term.
    static func biasStrings(from dictionary: MurmurDictionary, limit: Int = 100) -> [String] {
        var seen = Set<String>()
        var out: [String] = []

        // Explicit corrections first — those are words the user has already
        // watched the engine get wrong.
        for c in dictionary.corrections {
            let w = c.write.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !w.isEmpty, seen.insert(w.lowercased()).inserted else { continue }
            out.append(w)
            if out.count >= limit { return out }
        }
        for t in dictionary.terms {
            let w = t.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !w.isEmpty, seen.insert(w.lowercased()).inserted else { continue }
            out.append(w)
            if out.count >= limit { return out }
        }
        return out
    }
}

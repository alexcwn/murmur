import Foundation
import Observation
import OSLog

/// Transcription history, capped and written as plain JSON.
///
/// Deliberately not a database: the cap keeps it small enough that rewriting
/// the whole file on each append costs nothing, and a flat file stays greppable
/// and deletable by hand.
@Observable
final class HistoryStore {
    static let cap = 500

    private(set) var entries: [Transcription] = []

    private let log = Logger(subsystem: "com.alexchoo.murmur", category: "history")
    private let url: URL

    init(url: URL = AppPaths.history) {
        self.url = url
        load()
    }

    func add(_ entry: Transcription) {
        entries.insert(entry, at: 0)
        if entries.count > Self.cap { entries.removeLast(entries.count - Self.cap) }
        save()
    }

    func delete(_ entry: Transcription) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    /// Case-insensitive match across the inserted text and the destination app.
    func search(_ query: String) -> [Transcription] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return entries }
        return entries.filter {
            $0.text.localizedCaseInsensitiveContains(q)
                || ($0.appName?.localizedCaseInsensitiveContains(q) ?? false)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        do {
            entries = try JSONDecoder.murmur.decode([Transcription].self, from: data)
        } catch {
            log.error("history unreadable, starting empty: \(error.localizedDescription)")
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder.murmur.encode(entries)
            try data.write(to: url, options: .atomic)
        } catch {
            log.error("could not save history: \(error.localizedDescription)")
        }
    }
}

extension JSONEncoder {
    static var murmur: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }
}

extension JSONDecoder {
    static var murmur: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

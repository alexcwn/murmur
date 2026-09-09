import AppKit
import Foundation
import Observation
import OSLog

/// Owns the dictionary file, in both directions.
///
/// The file is the source of truth and is meant to be edited by hand as well as
/// through the UI, so an external write is watched for and picked up live.
@Observable
final class DictionaryStore {
    private(set) var dictionary: MurmurDictionary = .empty
    /// Rebuilt whenever the dictionary changes; the pipeline reads this.
    private(set) var engine = CorrectionEngine(dictionary: .empty)
    private(set) var lastExternalReload: Date?

    let url: URL

    private let log = Logger(subsystem: "com.alexchoo.murmur", category: "dictionary")
    private var watcher: DispatchSourceFileSystemObject?
    private var watchedDescriptor: CInt = -1
    /// Suppresses the reload our own save would otherwise trigger.
    private var selfWriteUntil: Date = .distantPast

    init(url: URL = AppPaths.dictionary) {
        self.url = url
        load(seedIfMissing: true)
        startWatching()
    }

    // MARK: - Mutation

    func addTerm(_ text: String, note: String = "") {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        dictionary.terms.append(DictionaryTerm(text: t, note: note))
        commit()
    }

    func addCorrection(heard: String, write: String, note: String = "") {
        let h = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        let w = write.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !h.isEmpty, !w.isEmpty else { return }
        dictionary.corrections.append(DictionaryCorrection(heard: h, write: w, note: note))
        commit()
    }

    func update(_ term: DictionaryTerm) {
        guard let i = dictionary.terms.firstIndex(where: { $0.id == term.id }) else { return }
        dictionary.terms[i] = term
        commit()
    }

    func update(_ correction: DictionaryCorrection) {
        guard let i = dictionary.corrections.firstIndex(where: { $0.id == correction.id }) else { return }
        dictionary.corrections[i] = correction
        commit()
    }

    func deleteTerm(_ id: UUID) {
        dictionary.terms.removeAll { $0.id == id }
        commit()
    }

    func deleteCorrection(_ id: UUID) {
        dictionary.corrections.removeAll { $0.id == id }
        commit()
    }

    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Persistence

    private func commit() {
        engine = CorrectionEngine(dictionary: dictionary)
        save()
    }

    private func load(seedIfMissing: Bool = false) {
        guard let data = try? Data(contentsOf: url) else {
            if seedIfMissing {
                dictionary = .starter
                engine = CorrectionEngine(dictionary: dictionary)
                save()
            }
            return
        }
        do {
            dictionary = try JSONDecoder.murmur.decode(MurmurDictionary.self, from: data)
            engine = CorrectionEngine(dictionary: dictionary)
        } catch {
            // Never clobber a file the user may have been editing by hand.
            log.error("dictionary unreadable, keeping previous: \(error.localizedDescription)")
        }
    }

    private func save() {
        do {
            selfWriteUntil = Date().addingTimeInterval(1.0)
            let data = try JSONEncoder.murmur.encode(dictionary)
            try data.write(to: url, options: .atomic)
        } catch {
            log.error("could not save dictionary: \(error.localizedDescription)")
        }
    }

    // MARK: - Watching for hand edits

    private func startWatching() {
        stopWatching()
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        watchedDescriptor = fd

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete, .extend], queue: .main
        )
        src.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = src.data
            // An atomic write replaces the inode, so the old descriptor stops
            // reporting. Re-open before reloading or we only ever see one edit.
            if flags.contains(.rename) || flags.contains(.delete) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.reloadFromDisk()
                    self?.startWatching()
                }
            } else {
                self.reloadFromDisk()
            }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        watcher = src
    }

    private func stopWatching() {
        watcher?.cancel()
        watcher = nil
        watchedDescriptor = -1
    }

    private func reloadFromDisk() {
        guard Date() >= selfWriteUntil else { return }  // our own save
        let before = dictionary
        load()
        if dictionary != before {
            lastExternalReload = .now
            log.info("dictionary reloaded from an external edit")
        }
    }
}

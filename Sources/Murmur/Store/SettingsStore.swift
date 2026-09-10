import Foundation
import Observation
import OSLog

/// User preferences, in the same visible folder as everything else.
@Observable
final class SettingsStore {
    struct Values: Codable, Equatable, Sendable {
        var hotkey: Hotkey = .fn
        var rawMode: Bool = false
        var engine: EngineChoice = .speech
        var localeIdentifier: String = Locale.current.identifier
        var idleTimeoutSeconds: Double = 30
    }

    var values: Values {
        didSet { if values != oldValue { save() } }
    }

    private let log = Logger(subsystem: "com.alexchoo.murmur", category: "settings")
    private let url: URL

    init(url: URL = AppPaths.settings) {
        self.url = url
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder.murmur.decode(Values.self, from: data) {
            values = decoded
        } else {
            values = Values()
        }
    }

    /// Locales the installed speech model actually supports, for the picker.
    var locale: Locale { Locale(identifier: values.localeIdentifier) }

    private func save() {
        do {
            try JSONEncoder.murmur.encode(values).write(to: url, options: .atomic)
        } catch {
            log.error("could not save settings: \(error.localizedDescription)")
        }
    }
}

import Foundation

/// Everything Murmur persists lives in one visible folder, because the
/// dictionary is required to be editable by hand as well as in the UI.
enum AppPaths {
    static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Murmur", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static var dictionary: URL { directory.appendingPathComponent("dictionary.json") }
    static var history: URL { directory.appendingPathComponent("history.json") }
    static var settings: URL { directory.appendingPathComponent("settings.json") }
}

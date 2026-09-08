import AppKit

/// What the user was focused on when they started dictating. Drives the tone of
/// the cleanup pass and, later, per-app injection overrides.
struct AppContext: Equatable, Sendable {
    var bundleID: String
    var appName: String

    static let unknown = AppContext(bundleID: "", appName: "the current app")

    static func frontmost() -> AppContext {
        guard let app = NSWorkspace.shared.frontmostApplication else { return .unknown }
        return AppContext(
            bundleID: app.bundleIdentifier ?? "",
            appName: app.localizedName ?? "the current app"
        )
    }

    /// Coarse register hint. Deliberately a small closed set — a long tail of
    /// per-app prompts is a maintenance problem, not a feature.
    enum Tone: String, Sendable {
        case email = "a professional email"
        case chat = "a casual chat message"
        case code = "a technical note for a code editor"
        case document = "a written document"
        case neutral = "general prose"
    }

    var tone: Tone {
        switch bundleID {
        case "com.apple.mail", "com.google.Chrome.app.Gmail", "com.microsoft.Outlook",
             "com.readdle.smartemail-Mac", "com.superhuman.electron":
            .email
        case "com.tinyspeck.slackmacgap", "com.hnc.Discord", "net.whatsapp.WhatsApp",
             "com.apple.MobileSMS", "org.telegram.desktop":
            .chat
        case "com.todesktop.230313mzl4w4u92", "com.microsoft.VSCode", "com.apple.dt.Xcode",
             "dev.zed.Zed", "com.googlecode.iterm2", "com.apple.Terminal":
            .code
        case "com.apple.Notes", "notion.id", "com.apple.iWork.Pages", "md.obsidian":
            .document
        default:
            .neutral
        }
    }
}

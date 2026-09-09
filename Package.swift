// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Murmur",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "Murmur",
            path: "Sources/Murmur",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                // Almost everything here is UI / AppKit-adjacent. Default-isolating to
                // MainActor keeps the concurrency annotations down to the few places
                // that genuinely leave the main thread (the audio tap, the event tap).
                .defaultIsolation(MainActor.self),
            ]
        )
        // NOTE: the XCTest suite in Tests/MurmurTests covers CorrectionEngine but
        // cannot be wired up yet - XCTest ships with Xcode, not Command Line
        // Tools. Re-add a .testTarget here once Xcode is installed.
    ]
)

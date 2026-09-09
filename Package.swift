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
        ),
        .testTarget(
            name: "MurmurTests",
            dependencies: ["Murmur"],
            path: "Tests/MurmurTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)

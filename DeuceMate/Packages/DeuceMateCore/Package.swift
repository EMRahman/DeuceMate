// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DeuceMateCore",
    platforms: [
        .iOS(.v16),
        .watchOS(.v9),
        .macOS(.v13)
    ],
    products: [
        .library(name: "DeuceMateCore", targets: ["DeuceMateCore"]),
        .executable(name: "DeuceMateArchiveTool", targets: ["DeuceMateArchiveTool"]),
        .executable(name: "DeuceMateWebSnapshot", targets: ["DeuceMateWebSnapshot"])
    ],
    targets: [
        .target(
            name: "DeuceMateCore",
            path: "Sources/DeuceMateCore"
        ),
        .executableTarget(
            name: "DeuceMateArchiveTool",
            dependencies: ["DeuceMateCore"],
            path: "Sources/DeuceMateArchiveTool"
        ),
        // macOS-only: renders a local HTML file (e.g. the interactive match
        // web export) via a headless WKWebView and saves PNG snapshots. Avoids
        // needing macOS Screen Recording permission since it's an in-process
        // view snapshot, not a display capture.
        .executableTarget(
            name: "DeuceMateWebSnapshot",
            path: "Sources/DeuceMateWebSnapshot"
        ),
        .testTarget(
            name: "DeuceMateCoreTests",
            dependencies: ["DeuceMateCore"],
            path: "Tests/DeuceMateCoreTests"
        )
    ]
)

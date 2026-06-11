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
        .library(name: "DeuceMateCore", targets: ["DeuceMateCore"])
    ],
    targets: [
        .target(
            name: "DeuceMateCore",
            path: "Sources/DeuceMateCore"
        ),
        .testTarget(
            name: "DeuceMateCoreTests",
            dependencies: ["DeuceMateCore"],
            path: "Tests/DeuceMateCoreTests"
        )
    ]
)

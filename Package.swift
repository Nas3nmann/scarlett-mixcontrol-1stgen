// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ScarlettMixControl",
    platforms: [.macOS(.v14)],
    products: [
        // Library that other Swift targets can link against.
        .library(name: "ScarlettCore", targets: ["ScarlettCore"]),
        // Executables — product names stay kebab-case (Unix-style binary
        // names) while target/folder names are PascalCase (Swift convention).
        .executable(name: "scarlett-cli", targets: ["ScarlettCLI"]),
        .executable(name: "scarlett-app", targets: ["ScarlettApp"]),
    ],
    targets: [
        .target(name: "ScarlettCore", path: "Sources/ScarlettCore"),
        .executableTarget(
            name: "ScarlettCLI",
            dependencies: ["ScarlettCore"],
            path: "Sources/ScarlettCLI"
        ),
        .executableTarget(
            name: "ScarlettApp",
            dependencies: ["ScarlettCore"],
            path: "Sources/ScarlettApp",
            resources: [.process("Resources")],
            // SwiftUI + @MainActor MixerState; keep Swift 5 concurrency rules so
            // private View helpers can touch state without per-closure isolation.
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)

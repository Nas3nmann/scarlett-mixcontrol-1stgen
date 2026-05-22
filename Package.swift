// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ScarlettMixControl",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ScarlettCore", targets: ["ScarlettCore"]),
        .executable(name: "scarlett-cli", targets: ["scarlett-cli"]),
        .executable(name: "scarlett-app", targets: ["ScarlettApp"]),
    ],
    targets: [
        .target(name: "ScarlettCore", path: "Sources/ScarlettCore"),
        .executableTarget(
            name: "scarlett-cli",
            dependencies: ["ScarlettCore"],
            path: "Sources/scarlett-cli"
        ),
        .executableTarget(
            name: "ScarlettApp",
            dependencies: ["ScarlettCore"],
            path: "Sources/ScarlettApp"
        ),
    ]
)

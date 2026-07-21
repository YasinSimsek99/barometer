// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Barometer",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BarometerCore", targets: ["BarometerCore"]),
        .library(name: "ClaudeCodeBridge", targets: ["ClaudeCodeBridge"]),
        .executable(name: "BarometerApp", targets: ["BarometerApp"]),
        .executable(name: "barometer-bridge", targets: ["BarometerBridgeCLI"]),
    ],
    targets: [
        .target(
            name: "BarometerCore",
            resources: [.process("Resources")]
        ),
        .target(
            name: "ClaudeCodeBridge",
            dependencies: ["BarometerCore"]
        ),
        .executableTarget(
            name: "BarometerApp",
            dependencies: ["BarometerCore", "ClaudeCodeBridge"]
        ),
        .executableTarget(
            name: "BarometerBridgeCLI",
            dependencies: ["BarometerCore", "ClaudeCodeBridge"]
        ),
        .testTarget(
            name: "BarometerCoreTests",
            dependencies: ["BarometerCore"]
        ),
        .testTarget(
            name: "ClaudeCodeBridgeTests",
            dependencies: ["ClaudeCodeBridge", "BarometerCore"]
        ),
    ]
)

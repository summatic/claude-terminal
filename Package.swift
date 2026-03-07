// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeTerminal",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "ClaudeTerminal",
            path: "Sources/ClaudeTerminal",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        )
    ]
)

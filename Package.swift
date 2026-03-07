// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeTerminal",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "ClaudeTerminal",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ],
            path: "Sources/ClaudeTerminal",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        ),
        .testTarget(
            name: "ClaudeTerminalTests",
            dependencies: ["ClaudeTerminal"],
            path: "Tests/ClaudeTerminalTests"
        )
    ]
)

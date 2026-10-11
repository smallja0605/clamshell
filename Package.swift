// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Clamshell",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Clamshell", targets: ["Clamshell"]),
        .executable(name: "clamshell-hook", targets: ["clamshell-hook"]),
    ],
    targets: [
        // Everything that can be tested without a screen: hook protocol, session state, installer, strings.
        .target(name: "ClamshellCore"),
        // Tiny headless helper that Claude Code's hooks run. No AppKit, so it starts fast.
        .executableTarget(name: "clamshell-hook", dependencies: ["ClamshellCore"]),
        // The menu-bar app.
        .executableTarget(name: "Clamshell", dependencies: ["ClamshellCore"]),
        .testTarget(name: "ClamshellCoreTests", dependencies: ["ClamshellCore"]),
    ]
)

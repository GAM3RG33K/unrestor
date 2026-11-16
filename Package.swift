// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Unrestor",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "UnrestorCore"),
        .target(name: "UnrestorDaemonCore", dependencies: ["UnrestorCore"]),
        // The command-line tool, including `install` and `uninstall`.
        .executableTarget(name: "unrestor", dependencies: ["UnrestorCore"]),
        // The root launchd daemon. `unrestor install` copies it into place.
        .executableTarget(name: "unrestor-daemon", dependencies: ["UnrestorDaemonCore"]),
        // The menu-bar app. scripts/make-app.sh wraps it in Unrestor.app.
        .executableTarget(name: "UnrestorApp", dependencies: ["UnrestorCore"]),
        .testTarget(name: "UnrestorCoreTests", dependencies: ["UnrestorCore"]),
        .testTarget(name: "UnrestorDaemonCoreTests", dependencies: ["UnrestorDaemonCore"]),
    ]
)

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Unrestor",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "UnrestorCore"),
        .target(name: "UnrestorDaemonCore", dependencies: ["UnrestorCore"]),
        .executableTarget(name: "unrestor", dependencies: ["UnrestorCore"]),
        // Built by Xcode for release (see project.yml). Listed here so
        // `swift build` type-checks them on every change.
        .executableTarget(name: "UnrestorDaemon", dependencies: ["UnrestorDaemonCore"]),
        .executableTarget(
            name: "UnrestorApp",
            dependencies: ["UnrestorCore", "UnrestorDaemonCore"]
        ),
        .testTarget(name: "UnrestorCoreTests", dependencies: ["UnrestorCore"]),
        .testTarget(name: "UnrestorDaemonCoreTests", dependencies: ["UnrestorDaemonCore"]),
    ]
)

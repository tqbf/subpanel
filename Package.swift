// swift-tools-version:6.0
import PackageDescription

// Subpanel: stable `<name>.localhost` URLs for local web apps.
//
// Targets, from the bottom up:
//
//   SubpanelCore     registry, validation, persistence, API models, agent
//                    instructions. Foundation only — shared by everything.
//   SubpanelServer   the SwiftNIO reverse proxy + control API. The only code
//                    that links NIO.
//   SubpanelService  `subpanel-service`, the launchd agent that owns port 80.
//   Subpanel         the SwiftUI app (Dock app, management window) — a
//                    *client* of the service.
//   SubpanelMenu     the menu-bar app: a login item bundled inside Subpanel.app
//                    that lists apps and opens the full app.
//
// See plans/architecture.md.
let swift6: [SwiftSetting] = [.swiftLanguageMode(.v6)]

let package = Package(
    name: "Subpanel",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .executable(name: "Subpanel", targets: ["Subpanel"]),
        .executable(name: "subpanel-service", targets: ["SubpanelService"]),
        .executable(name: "SubpanelMenu", targets: ["SubpanelMenu"]),
    ],
    dependencies: [
        // Pinned to an exact release; bump deliberately (plans/proxy.md).
        .package(url: "https://github.com/apple/swift-nio.git", exact: "2.103.0"),
    ],
    targets: [
        // <launch.h> — launch_activate_socket(3) for launchd socket activation.
        .systemLibrary(name: "CLaunch", path: "Sources/CLaunch"),
        .target(
            name: "SubpanelCore",
            path: "Sources/SubpanelCore",
            swiftSettings: swift6
        ),
        .target(
            name: "SubpanelServer",
            dependencies: [
                "SubpanelCore",
                "CLaunch",
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
            ],
            path: "Sources/SubpanelServer",
            swiftSettings: swift6
        ),
        .executableTarget(
            name: "SubpanelService",
            dependencies: ["SubpanelServer", "SubpanelCore"],
            path: "Sources/SubpanelService",
            swiftSettings: swift6
        ),
        .executableTarget(
            name: "Subpanel",
            dependencies: ["SubpanelCore"],
            path: "Sources/Subpanel",
            swiftSettings: swift6
        ),
        .executableTarget(
            name: "SubpanelMenu",
            dependencies: ["SubpanelCore"],
            path: "Sources/SubpanelMenu",
            swiftSettings: swift6
        ),
        .testTarget(
            name: "SubpanelTests",
            dependencies: [
                "SubpanelCore",
                "SubpanelServer",
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOWebSocket", package: "swift-nio"),
            ],
            path: "Tests/SubpanelTests",
            swiftSettings: swift6
        ),
    ]
)

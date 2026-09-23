// swift-tools-version:6.0
import PackageDescription

// A clean SwiftUI macOS app template. One executable target, one test
// target, zero third-party dependencies — add your own under `dependencies`
// and wire them into the `Starter` target as you grow the app.
let package = Package(
    name: "Starter",
    platforms: [
        .macOS(.v14),
    ],
    targets: [
        .executableTarget(
            name: "Starter",
            path: "Sources/Starter",
            swiftSettings: [
                // Swift 6 strict concurrency from day one — cheaper to start
                // here than to retrofit it later.
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "StarterTests",
            dependencies: ["Starter"],
            path: "Tests/StarterTests"
        ),
    ]
)

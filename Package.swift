// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Pith",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PithEditor", targets: ["PithEditor"]),
        .library(name: "PithApp", targets: ["PithApp"]),
    ],
    targets: [
        .target(name: "PithEditor"),
        .target(
            name: "PithApp",
            dependencies: ["PithEditor"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        // Restyle timings in release: `make bench`.
        .executableTarget(name: "PithBench", dependencies: ["PithEditor"]),
        .testTarget(name: "PithEditorTests", dependencies: ["PithEditor"]),
        .testTarget(
            name: "PithAppTests",
            dependencies: ["PithApp"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)

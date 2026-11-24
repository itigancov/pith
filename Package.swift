// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Pith",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PithEditor", targets: ["PithEditor"]),
        .library(name: "PithNotes", targets: ["PithNotes"]),
        .library(name: "PithApp", targets: ["PithApp"]),
    ],
    targets: [
        .target(name: "PithEditor"),
        .target(
            name: "PithNotes",
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .target(
            name: "PithApp",
            dependencies: ["PithEditor"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        // Restyle timings in release: `make bench`.
        .executableTarget(name: "PithBench", dependencies: ["PithEditor", "PithNotes"]),
        .testTarget(name: "PithEditorTests", dependencies: ["PithEditor"]),
        .testTarget(name: "PithNotesTests", dependencies: ["PithNotes"]),
        .testTarget(name: "PithAppTests", dependencies: ["PithApp"]),
    ]
)

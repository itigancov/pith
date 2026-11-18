// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PithEditor",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PithEditor", targets: ["PithEditor"]),
    ],
    targets: [
        .target(name: "PithEditor"),
        .testTarget(name: "PithEditorTests", dependencies: ["PithEditor"]),
    ]
)

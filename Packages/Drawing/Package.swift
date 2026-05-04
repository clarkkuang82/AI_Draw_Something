// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Drawing",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Drawing", targets: ["Drawing"]),
    ],
    targets: [
        .target(
            name: "Drawing",
            resources: [.copy("Resources/sketches.json")]
        ),
        .testTarget(name: "DrawingTests", dependencies: ["Drawing"]),
    ]
)

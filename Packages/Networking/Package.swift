// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Networking",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Networking", targets: ["Networking"]),
    ],
    dependencies: [
        .package(path: "../GameCore"),
        .package(path: "../Attest"),
    ],
    targets: [
        .target(name: "Networking", dependencies: ["GameCore", "Attest"]),
        .testTarget(name: "NetworkingTests", dependencies: ["Networking", "GameCore"]),
    ]
)

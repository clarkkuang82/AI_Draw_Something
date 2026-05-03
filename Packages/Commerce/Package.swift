// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Commerce",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Commerce", targets: ["Commerce"]),
    ],
    dependencies: [
        .package(path: "../Networking"),
        .package(path: "../Attest"),
    ],
    targets: [
        .target(name: "Commerce", dependencies: ["Networking", "Attest"]),
    ]
)

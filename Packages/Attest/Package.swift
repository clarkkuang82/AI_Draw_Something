// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Attest",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Attest", targets: ["Attest"]),
    ],
    dependencies: [
        .package(path: "../Persistence"),
    ],
    targets: [
        .target(name: "Attest", dependencies: ["Persistence"]),
    ]
)

// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Leaderboard",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Leaderboard", targets: ["Leaderboard"]),
    ],
    targets: [
        .target(name: "Leaderboard"),
    ]
)

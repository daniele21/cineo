// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CineoMusic",
    platforms: [.macOS(.v15)],
    products: [.library(name: "CineoMusic", targets: ["CineoMusic"])],
    targets: [
        .target(name: "CineoMusic"),
        .testTarget(name: "CineoMusicTests", dependencies: ["CineoMusic"])
    ]
)

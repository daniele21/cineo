// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CineoEvents",
    platforms: [.macOS(.v15)],
    products: [.library(name: "CineoEvents", targets: ["CineoEvents"])],
    targets: [
        .target(name: "CineoEvents"),
        .testTarget(name: "CineoEventsTests", dependencies: ["CineoEvents"])
    ]
)

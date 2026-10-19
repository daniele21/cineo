// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CineoDirector",
    platforms: [.macOS(.v15)],
    products: [.library(name: "CineoDirector", targets: ["CineoDirector"])],
    targets: [
        .target(name: "CineoDirector"),
        .testTarget(name: "CineoDirectorTests", dependencies: ["CineoDirector"])
    ]
)

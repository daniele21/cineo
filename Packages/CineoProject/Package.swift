// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CineoProject",
    platforms: [.macOS(.v15)],
    products: [.library(name: "CineoProject", targets: ["CineoProject"])],
    targets: [
        .target(name: "CineoProject"),
        .testTarget(name: "CineoProjectTests", dependencies: ["CineoProject"])
    ]
)

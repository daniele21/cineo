// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CineoScene",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "CineoScene", targets: ["CineoScene"]),
        .executable(name: "cineo-scene-spike", targets: ["CineoSceneSpike"]),
        .executable(name: "cineo-scene-smoke", targets: ["CineoSceneSmoke"])
    ],
    targets: [
        .target(name: "CineoScene"),
        .executableTarget(name: "CineoSceneSpike", dependencies: ["CineoScene"]),
        .executableTarget(name: "CineoSceneSmoke", dependencies: ["CineoScene"]),
        .testTarget(name: "CineoSceneTests", dependencies: ["CineoScene"])
    ]
)

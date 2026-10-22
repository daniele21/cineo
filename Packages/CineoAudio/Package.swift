// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CineoAudio",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "CineoAudio", targets: ["CineoAudio"]),
        .executable(name: "cineo-audio-smoke", targets: ["CineoAudioSmoke"])
    ],
    dependencies: [.package(path: "../CineoMusic")],
    targets: [
        .target(name: "CineoAudio",
                dependencies: [.product(name: "CineoMusic", package: "CineoMusic")]),
        .executableTarget(name: "CineoAudioSmoke",
                          dependencies: ["CineoAudio",
                            .product(name: "CineoMusic", package: "CineoMusic")])
    ]
)

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CineoDirector",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "CineoDirector", targets: ["CineoDirector"]),
        .executable(name: "cineo-camera-benchmark", targets: ["CineoCameraBenchmark"])
    ],
    dependencies: [
        .package(path: "../CineoEvents"),
        .package(path: "../CineoScene")
    ],
    targets: [
        .target(name: "CineoDirector", dependencies: [
            .product(name: "CineoEvents", package: "CineoEvents"),
            .product(name: "CineoScene", package: "CineoScene")
        ]),
        .testTarget(name: "CineoDirectorTests", dependencies: ["CineoDirector"]),
        .executableTarget(name: "CineoCameraBenchmark", dependencies: ["CineoDirector", "CineoEvents", "CineoScene"],
                          resources: [.process("Fixtures")])
    ]
)

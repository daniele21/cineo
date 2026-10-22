// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CineoDirector",
    platforms: [.macOS(.v15)],
    products: [.library(name: "CineoDirector", targets: ["CineoDirector"])],
    dependencies: [
        .package(path: "../CineoEvents"),
        .package(path: "../CineoScene")
    ],
    targets: [
        .target(name: "CineoDirector", dependencies: [
            .product(name: "CineoEvents", package: "CineoEvents"),
            .product(name: "CineoScene", package: "CineoScene")
        ]),
        .testTarget(name: "CineoDirectorTests", dependencies: ["CineoDirector"])
    ]
)

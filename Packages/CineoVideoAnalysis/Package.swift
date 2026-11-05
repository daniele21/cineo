// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CineoVideoAnalysis",
    platforms: [.macOS(.v15)],
    products: [.library(name: "CineoVideoAnalysis", targets: ["CineoVideoAnalysis"])],
    dependencies: [.package(path: "../CineoDirector")],
    targets: [
        .target(name: "CineoVideoAnalysis", dependencies: [
            .product(name: "CineoDirector", package: "CineoDirector")
        ])
    ]
)

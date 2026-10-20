// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CineoEditPlanner",
    platforms: [.macOS(.v15)],
    products: [.library(name: "CineoEditPlanner", targets: ["CineoEditPlanner"])],
    dependencies: [
        .package(path: "../CineoDirector"),
        .package(path: "../CineoProject")
    ],
    targets: [
        .target(name: "CineoEditPlanner", dependencies: [
            .product(name: "CineoDirector", package: "CineoDirector"),
            .product(name: "CineoProject", package: "CineoProject")
        ]),
        .testTarget(name: "CineoEditPlannerTests", dependencies: ["CineoEditPlanner"])
    ]
)

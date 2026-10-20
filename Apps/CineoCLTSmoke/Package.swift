// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CineoCLTSmoke",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "cineo-clt-smoke", targets: ["CineoCLTSmoke"])],
    dependencies: [
        .package(path: "../../Packages/CineoDirector"),
        .package(path: "../../Packages/CineoProject"),
        .package(path: "../../Packages/CineoEditPlanner")
    ],
    targets: [
        .executableTarget(
            name: "CineoCLTSmoke",
            dependencies: [
                .product(name: "CineoDirector", package: "CineoDirector"),
                .product(name: "CineoProject", package: "CineoProject"),
                .product(name: "CineoEditPlanner", package: "CineoEditPlanner")
            ]
        )
    ]
)

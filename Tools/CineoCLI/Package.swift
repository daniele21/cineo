// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CineoCLI",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "cineo", targets: ["CineoCLI"])],
    dependencies: [
        .package(path: "../../Packages/CineoProject"),
        .package(path: "../../Packages/CineoEditPlanner")
    ],
    targets: [
        .executableTarget(name: "CineoCLI", dependencies: [
            .product(name: "CineoProject", package: "CineoProject"),
            .product(name: "CineoEditPlanner", package: "CineoEditPlanner")
        ])
    ]
)

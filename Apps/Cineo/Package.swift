// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Cineo",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "Cineo", targets: ["Cineo"])],
    dependencies: [
        .package(path: "../../Packages/CineoScene"),
        .package(path: "../../Packages/CineoProject"),
        .package(path: "../../Packages/CineoMusic")
    ],
    targets: [
        .executableTarget(name: "Cineo", dependencies: [
            .product(name: "CineoScene", package: "CineoScene"),
            .product(name: "CineoProject", package: "CineoProject"),
            .product(name: "CineoMusic", package: "CineoMusic")
        ])
    ]
)

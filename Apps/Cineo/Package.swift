// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Cineo",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "Cineo", targets: ["Cineo"])],
    targets: [
        .executableTarget(name: "Cineo")
    ]
)

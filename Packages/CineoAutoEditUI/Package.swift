// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CineoAutoEditUI",
    platforms: [.macOS(.v15)],
    products: [.library(name: "CineoAutoEditUI", targets: ["CineoAutoEditUI"])],
    targets: [.target(name: "CineoAutoEditUI")]
)

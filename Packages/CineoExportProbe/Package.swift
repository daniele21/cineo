// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CineoExportProbe",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "cineo-export-probe", targets: ["CineoExportProbe"])],
    targets: [.executableTarget(name: "CineoExportProbe")]
)

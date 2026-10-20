// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "CineoCLTProof",
  platforms: [.macOS(.v15)],
  products: [.executable(name: "CineoCLTProof", targets: ["CineoCLTProof"])],
  targets: [.executableTarget(name: "CineoCLTProof")]
)

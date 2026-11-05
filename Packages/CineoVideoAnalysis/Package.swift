// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CineoVideoAnalysis",
    platforms: [.macOS(.v15)],
    products: [.library(name: "CineoVideoAnalysis", targets: ["CineoVideoAnalysis"]),
               .executable(name: "cineo-import-video-smoke", targets: ["CineoVideoAnalysisSmoke"]),
               .executable(name: "cineo-import-cursor-benchmark", targets: ["CineoVideoAnalysisBenchmark"])],
    dependencies: [.package(path: "../CineoDirector"),
                   .package(path: "../CineoScene")],
    targets: [
        .target(name: "CineoVideoAnalysis", dependencies: [
            .product(name: "CineoDirector", package: "CineoDirector")
        ]),
        .executableTarget(name: "CineoVideoAnalysisSmoke", dependencies: ["CineoVideoAnalysis",
            .product(name: "CineoDirector", package: "CineoDirector")]),
        .executableTarget(name: "CineoVideoAnalysisBenchmark", dependencies: ["CineoVideoAnalysis",
            .product(name: "CineoDirector", package: "CineoDirector"),
            .product(name: "CineoScene", package: "CineoScene")])
    ]
)

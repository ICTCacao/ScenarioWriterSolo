// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ScenarioWriterCore",
    platforms: [.macOS("14.0")],
    products: [
        .library(name: "ScenarioWriterCore", targets: ["ScenarioWriterCore"]),
    ],
    targets: [
        .target(
            name: "ScenarioWriterCore",
            resources: [.copy("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "ScenarioWriterCoreTests",
            dependencies: ["ScenarioWriterCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)

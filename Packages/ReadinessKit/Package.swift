// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ReadinessKit",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
        .macOS(.v14),
    ],
    products: [
        .library(name: "ReadinessCore", targets: ["ReadinessCore"]),
        .library(name: "HealthInsights", targets: ["HealthInsights"]),
        .library(name: "ReadinessHealthKit", targets: ["ReadinessHealthKit"]),
        .library(name: "AppleHealthImport", targets: ["AppleHealthImport"]),
        .executable(name: "openreadiness-cli", targets: ["openreadiness-cli"]),
    ],
    targets: [
        // Pure Swift scoring engine. No HealthKit, no UI — fully unit-testable on macOS.
        .target(name: "ReadinessCore"),
        // Metric catalogue, explorer analytics, correlations and insights. Also pure Swift.
        .target(name: "HealthInsights", dependencies: ["ReadinessCore"]),
        // Adapters that read HealthKit for the engine and the explorer.
        .target(
            name: "ReadinessHealthKit",
            dependencies: ["ReadinessCore", "HealthInsights"],
            linkerSettings: [.linkedFramework("HealthKit")]
        ),
        // Streaming parser for the Health app's "Export All Health Data" (export.xml).
        .target(name: "AppleHealthImport", dependencies: ["ReadinessCore", "HealthInsights"]),
        // Command-line tool: run the engine on an export to validate scoring on real data.
        .executableTarget(name: "openreadiness-cli", dependencies: ["AppleHealthImport", "ReadinessCore", "HealthInsights"]),
        .testTarget(name: "AppleHealthImportTests", dependencies: ["AppleHealthImport", "ReadinessCore", "HealthInsights"]),
        .testTarget(name: "ReadinessCoreTests", dependencies: ["ReadinessCore"]),
        .testTarget(name: "HealthInsightsTests", dependencies: ["HealthInsights", "ReadinessCore"]),
    ]
)

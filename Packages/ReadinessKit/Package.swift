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
        .testTarget(name: "ReadinessCoreTests", dependencies: ["ReadinessCore"]),
        .testTarget(name: "HealthInsightsTests", dependencies: ["HealthInsights", "ReadinessCore"]),
    ]
)

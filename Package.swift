// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TotalRecall",
    platforms: [
        .macOS(.v26)
    ],
    targets: [
        // Core library — models, data layer, classifiers, utilities
        .target(
            name: "TotalRecallCore",
            path: "TotalRecall",
            exclude: ["TotalRecallApp.swift"],
            sources: [
                "Models",
                "DataLayer",
                "Profiles",
                "Theme",
                "Utilities",
            ]
        ),
        // Main app — SwiftUI entry point + views
        .executableTarget(
            name: "TotalRecall",
            dependencies: ["TotalRecallCore"],
            path: "TotalRecall",
            sources: [
                "TotalRecallApp.swift",
                "AppState.swift",
                "Views",
            ]
        ),
        // CLI diagnostic tool
        .executableTarget(
            name: "TotalRecallDiag",
            dependencies: ["TotalRecallCore"],
            path: "TotalRecallDiag"
        ),
        .testTarget(
            name: "TotalRecallTests",
            dependencies: ["TotalRecallCore"],
            path: "TotalRecallTests"
        ),
    ]
)

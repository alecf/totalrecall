// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TotalRecall",
    platforms: [
        .macOS(.v26)
    ],
    targets: [
        .executableTarget(
            name: "TotalRecall",
            path: "TotalRecall"
        ),
        .testTarget(
            name: "TotalRecallTests",
            dependencies: ["TotalRecall"],
            path: "TotalRecallTests"
        ),
    ]
)

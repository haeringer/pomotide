// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PomoTide",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "PomoTide",
            path: "Sources/PomoTide"
        ),
        .testTarget(
            name: "PomoTideTests",
            dependencies: ["PomoTide"],
            path: "Tests/PomoTideTests"
        ),
    ]
)

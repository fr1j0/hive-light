// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HiveLight",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "HiveLightCore"),
        .executableTarget(
            name: "hive-light-hook",
            dependencies: ["HiveLightCore"]
        ),
        .executableTarget(
            name: "HiveLightApp",
            dependencies: ["HiveLightCore"]
        ),
        .testTarget(
            name: "HiveLightCoreTests",
            dependencies: ["HiveLightCore"]
        ),
    ]
)

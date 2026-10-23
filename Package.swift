// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CreatorBaseline",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CreatorCore", targets: ["CreatorCore"]),
        .executable(name: "CreatorReplica", targets: ["CreatorReplicaApp"])
    ],
    targets: [
        .target(name: "CreatorCore"),
        .executableTarget(name: "CreatorReplicaApp", dependencies: ["CreatorCore"]),
        .testTarget(name: "CreatorCoreTests", dependencies: ["CreatorCore"])
    ]
)

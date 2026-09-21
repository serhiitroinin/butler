// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "Butler",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "FoldHarnessV1", exclude: ["LICENSE"]),
        .target(name: "ButlerCore", dependencies: ["FoldHarnessV1"]),
        .executableTarget(name: "ButlerApp", dependencies: ["ButlerCore"]),
        .testTarget(name: "ButlerCoreTests", dependencies: ["ButlerCore"]),
        .testTarget(name: "ButlerAppTests", dependencies: ["ButlerApp", "ButlerCore"]),
    ]
)

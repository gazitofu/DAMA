// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "DamaCore",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "DamaCore", targets: ["DamaCore"]),
        .library(name: "DamaAudio", targets: ["DamaAudio"])
    ],
    targets: [
        .target(name: "DamaCore"),
        .target(name: "DamaAudio", dependencies: ["DamaCore"]),
        .testTarget(name: "DamaAudioTests", dependencies: ["DamaAudio"]),
        .testTarget(
            name: "DamaCoreTests",
            dependencies: ["DamaCore"]
        )
    ]
)

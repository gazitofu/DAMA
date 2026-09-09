// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "DamaCore",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "DamaCore", targets: ["DamaCore"]),
        .library(name: "DamaAudio", targets: ["DamaAudio"]),
        .library(name: "DamaManaged", targets: ["DamaManaged"])
    ],
    targets: [
        .target(name: "DamaCore"),
        .target(name: "DamaAudio", dependencies: ["DamaCore"]),
        .target(name: "DamaManaged", dependencies: ["DamaCore", "DamaAudio"]),
        .testTarget(name: "DamaManagedTests", dependencies: ["DamaManaged"]),
        .testTarget(name: "DamaAudioTests", dependencies: ["DamaAudio"]),
        .testTarget(
            name: "DamaCoreTests",
            dependencies: ["DamaCore"]
        )
    ]
)

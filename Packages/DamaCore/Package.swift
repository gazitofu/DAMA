// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "DamaCore",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "DamaCore", targets: ["DamaCore"])
    ],
    targets: [
        .target(name: "DamaCore"),
        .testTarget(
            name: "DamaCoreTests",
            dependencies: ["DamaCore"]
        )
    ]
)

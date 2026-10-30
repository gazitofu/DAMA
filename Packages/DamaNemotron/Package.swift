// swift-tools-version: 6.2

import PackageDescription

// FluidAudio lives here, apart from DamaCore, so `scripts/check.sh` package tests never fetch or build it.
let package = Package(
    name: "DamaNemotron",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "DamaNemotron", targets: ["DamaNemotron"])
    ],
    dependencies: [
        .package(path: "../DamaCore"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.18.0")
    ],
    targets: [
        .target(name: "DamaNemotron", dependencies: [
            .product(name: "DamaManaged", package: "DamaCore"),
            .product(name: "FluidAudio", package: "FluidAudio")
        ])
    ]
)

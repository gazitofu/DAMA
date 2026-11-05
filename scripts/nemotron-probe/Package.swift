// swift-tools-version: 6.0
// Offline diarization probe (2026-10-30). Not part of the DAMA app or DamaCore.
import PackageDescription

let package = Package(
    name: "NemotronProbe",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.18.0"),
    ],
    targets: [
        .executableTarget(name: "NemotronProbe", dependencies: [.product(name: "FluidAudio", package: "FluidAudio")]),
        .executableTarget(name: "EmbedProbe", dependencies: [.product(name: "FluidAudio", package: "FluidAudio")]),
    ]
)

// swift-tools-version: 6.2
// AC-12 offline measurement (nemotron-diarization, 2026-10-30): Soniox raw + stored Nemotron probabilities -> combined
// documents through the app's reconciler. Reads user Sessions only; writes a summary to the given output file. No network.
import PackageDescription

let package = Package(
    name: "NemotronCombine",
    platforms: [.macOS(.v26)],
    dependencies: [.package(path: "../../Packages/DamaCore")],
    targets: [
        .executableTarget(name: "NemotronCombine", dependencies: [
            .product(name: "DamaCore", package: "DamaCore"),
            .product(name: "DamaAudio", package: "DamaCore"),
        ]),
    ]
)

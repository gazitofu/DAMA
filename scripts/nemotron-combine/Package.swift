// swift-tools-version: 6.2
// AC-12 offline measurement (nemotron-diarization, 2026-10-30): Soniox raw + stored Nemotron probabilities -> combined
// documents through the app's reconciler. Reads user Sessions only; writes a summary to the given output file. No network.
import PackageDescription

let package = Package(
    name: "NemotronCombine",
    platforms: [.macOS(.v26)],
    dependencies: [.package(path: "../../Packages/DamaCore"), .package(path: "../../Packages/DamaNemotron")],
    targets: [
        .executableTarget(name: "NemotronCombine", dependencies: [
            .product(name: "DamaCore", package: "DamaCore"),
            .product(name: "DamaAudio", package: "DamaCore"),
        ]),
        // turn-continuity AC-13 · AC-14: replay a stored Soniox + Nemotron parent byte for byte, or combine with new probabilities as v4.
        .executableTarget(name: "NemotronV4Check", dependencies: [
            .product(name: "DamaCore", package: "DamaCore"),
        ]),
        // AC-13: the app's FluidNemotronDiarizer on a stored analysis WAV, compared with the 1a probabilities.
        .executableTarget(name: "NemotronAppRun", dependencies: [
            .product(name: "DamaManaged", package: "DamaCore"),
            .product(name: "DamaNemotron", package: "DamaNemotron"),
        ]),
    ]
)

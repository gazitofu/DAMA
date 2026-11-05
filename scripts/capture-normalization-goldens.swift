// Compile with DamaCore/*.swift and Tests/DamaCoreTests/NormalizationFixture.swift, -D GOLDEN_CAPTURE.
// Explicit baseline capture only. Tests never update expectations; existing output is not overwritten.
import Foundation

@main struct CaptureNormalizationGoldens {
    static func main() throws {
        guard CommandLine.arguments.count == 3 else { fatalError("expected synthetic fixture and NEW golden path") }
        let fixture = URL(fileURLWithPath: CommandLine.arguments[1]), output = URL(fileURLWithPath: CommandLine.arguments[2])
        let fingerprints = try NormalizationFixture.documents(fixture).mapValues { try NormalizationFixture.fingerprint($0) }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(fingerprints).write(to: output, options: .withoutOverwriting)
        print("Captured \(fingerprints.count) synthetic normalized/reading/Markdown fingerprints")
    }
}

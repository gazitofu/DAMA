// Foundation-only smoke test. No microphone, network, or model execution.
import Foundation

@main
struct ContractSmokeCheck {
    static func main() throws {
        guard CommandLine.arguments.count == 4 else {
            throw NSError(domain: "DamaContracts", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Usage: contract-check <normalized.json> <vendor.json> <output.json>"
            ])
        }
        let normalizedURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let vendorURL = URL(fileURLWithPath: CommandLine.arguments[2])
        let outputURL = URL(fileURLWithPath: CommandLine.arguments[3])
        let input = try Data(contentsOf: normalizedURL)
        let document = try JSONDecoder().decode(TranscriptDocument.self, from: input)
        let vendor = try JSONDecoder().decode(PyannoteJobDTO.self, from: Data(contentsOf: vendorURL))
        guard vendor.status == "succeeded",
              vendor.output?.diarization.first?.confidence?["SPEAKER_00"] == 94,
              document.words.last?.speakerId == nil else {
            throw NSError(domain: "DamaContracts", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Fixture semantic assertion failed"
            ])
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let output = try encoder.encode(document)
        guard let before = try JSONSerialization.jsonObject(with: input) as? NSDictionary,
              let after = try JSONSerialization.jsonObject(with: output) as? NSDictionary,
              before.isEqual(after) else {
            throw NSError(domain: "DamaContracts", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Normalized round-trip differs (check explicit null keys)"
            ])
        }
        try output.write(to: outputURL, options: .atomic)
        print("PASS: normalized Codable round-trip, explicit nulls, vendor confidence map")
    }
}

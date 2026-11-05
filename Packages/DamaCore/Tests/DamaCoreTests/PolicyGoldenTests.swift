import Foundation
import XCTest
@testable import DamaCore

/// Fixes v3/v4/v5 Soniox+P2 policy output so shared-normalizer refactors stay byte-identical.
/// Capture once with `DAMA_CAPTURE_POLICY_GOLDENS=1`; normal runs compare.
final class PolicyGoldenTests: XCTestCase {
    private var fixtures: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url.appendingPathComponent("fixtures")
    }
    private let newRunID = "00000000-0000-4000-8000-0000000000a4"
    private let compareRunID = "00000000-0000-4000-8000-0000000000c3"

    private func policyDocuments() throws -> [String: TranscriptDocument] {
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: fixtures.appendingPathComponent("normalization-evidence.synthetic.json"))) as! [String: Any]
        let duration = json["durationUs"] as! Int64, audioHash = String(repeating: "a", count: 64)
        let created = "2026-09-12T00:00:00Z"
        let base = try NormalizationFixture.documents(fixtures.appendingPathComponent("normalization-evidence.synthetic.json"))
        var result: [String: TranscriptDocument] = [:]
        for value in json["cases"] as! [[String: Any]] {
            let id = value["id"] as! String, tokens = value["tokens"] as! [[String: Any]]
            let asr = try JSONSerialization.data(withJSONObject: ["id": "job", "text": tokens.map { $0["text"] as! String }.joined(), "tokens": tokens])
            var output: [String: Any] = ["diarization": value["regular"]!, "exclusiveDiarization": value["exclusive"] ?? value["regular"]!]
            output["warning"] = value["warning"]
            let p2 = try JSONSerialization.data(withJSONObject: ["jobId": "p2", "status": "succeeded", "output": output])
            result[id + "/v4-new"] = try SonioxPrecisionReconciler.normalize(soniox: asr, diarization: p2, sonioxJobID: "job",
                sessionID: "synthetic", runID: newRunID, durationUs: duration, audioSHA256: audioHash, model: "stt-async-v5",
                createdAt: created, synthetic: true, captureInterrupted: value["captureInterrupted"] as? Bool ?? false)
            let v2 = try XCTUnwrap(base[id + "/combined"])
            for policy in SonioxPrecisionComparison.allCases {
                result[id + "/" + policy.rawValue] = try SonioxPrecisionReconciler.reconcile(v2, runID: compareRunID,
                    createdAt: created, policy: policy)
            }
        }
        return result
    }

    func testSonioxPrecisionPolicyOutputsMatchCapturedGoldens() throws {
        let documents = try policyDocuments()
        let url = fixtures.appendingPathComponent("policy-goldens.synthetic.json")
        let fingerprints = try documents.mapValues { try NormalizationFixture.fingerprint($0) }
        if ProcessInfo.processInfo.environment["DAMA_CAPTURE_POLICY_GOLDENS"] == "1" {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(fingerprints).write(to: url)
        }
        let expected = try JSONDecoder().decode([String: NormalizationFixture.Fingerprint].self, from: Data(contentsOf: url))
        XCTAssertEqual(Set(fingerprints.keys), Set(expected.keys))
        XCTAssertEqual(fingerprints.count, 35)
        for key in fingerprints.keys.sorted() { XCTAssertEqual(fingerprints[key], expected[key], key) }
    }
}

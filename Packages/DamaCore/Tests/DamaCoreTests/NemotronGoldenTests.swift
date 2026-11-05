import Foundation
import XCTest
@testable import DamaCore

/// Fixes Soniox + Nemotron output per combination version so later rule changes keep stored versions byte-identical.
/// Capture with `DAMA_CAPTURE_NEMOTRON_GOLDENS=1`; normal runs compare. A new version only adds keys.
final class NemotronGoldenTests: XCTestCase {
    private var fixtures: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url.appendingPathComponent("fixtures")
    }
    private let runID = "00000000-0000-4000-8000-00000000e0a1"
    private typealias On = [(channel: Int, ms: Range<Int>, value: Float)]

    private static func token(_ text: String, _ start: Int, _ end: Int, _ speaker: String = "one") -> [String: Any] {
        ["text": text, "start_ms": start, "end_ms": end, "speaker": speaker, "confidence": 0.9]
    }
    /// Synthetic cases: interjection, overlap, tie, split words across an overlap, sentence ends and commas.
    private let cases: [(id: String, tokens: [[String: Any]], on: On)] = [
        ("interjection", [token("다음", 100, 900), token(" 네", 1000, 1030, "two"), token(" 안 합니다", 1100, 1900)],
         [(0, 0..<1000, 0.9), (1, 1000..<1030, 0.9), (0, 1030..<2030, 0.9)]),
        ("overlap", [token("동시에", 1100, 1300), token(" 말함", 1600, 1900)], [(0, 0..<2000, 0.9), (1, 1000..<1500, 0.8)]),
        ("tie", [token("같이", 1100, 1300)], [(0, 0..<2000, 0.8), (1, 1000..<1500, 0.8)]),
        ("split-word", [token("연락", 100, 400), token(" 왔", 500, 600), token("어", 600, 700), token("요?", 700, 800),
                        token(" 그리고", 900, 1200), token(" 다음", 1300, 1600)],
         [(0, 0..<1300, 0.9), (1, 600..<800, 0.92), (1, 1300..<2000, 0.9)]),
        ("sentence-end", [token("끝났어요.", 100, 500), token(" 그", 600, 700), token("래서", 700, 900), token(" 이제", 1000, 1300),
                          token(", 다", 1400, 1500), token("음", 1500, 1600)],
         [(0, 0..<600, 0.9), (1, 600..<700, 0.91), (0, 650..<1000, 0.95), (1, 1000..<1700, 0.9), (0, 1500..<1600, 0.93)]),
    ]

    private func documents() throws -> [String: TranscriptDocument] {
        var result: [String: TranscriptDocument] = [:]
        for item in cases {
            let asr = try JSONSerialization.data(withJSONObject: ["id": "job", "text": item.tokens.map { $0["text"] as! String }.joined(), "tokens": item.tokens])
            let frames = 300
            var p = [Float](repeating: 0.02, count: frames * 8)
            for on in item.on { for f in (on.ms.lowerBound / 10)..<(on.ms.upperBound / 10) { p[f * 8 + on.channel] = on.value } }
            var data = Data()
            for value in p { withUnsafeBytes(of: value.bitPattern.littleEndian) { data.append(contentsOf: $0) } }
            for version in SonioxNemotronReconciler.Version.allCases {
                result[item.id + "/" + version.rawValue] = try SonioxNemotronReconciler.normalize(soniox: asr, probabilities: data,
                    frameCount: frames, channels: 8, sonioxJobID: "job", sessionID: "s", runID: runID, durationUs: 3_000_000,
                    audioSHA256: String(repeating: "a", count: 64), model: "stt-async-v5", createdAt: "2026-10-31T00:00:00Z",
                    synthetic: true, version: version)
            }
        }
        return result
    }

    func testNemotronOutputsMatchCapturedGoldens() throws {
        let fingerprints = try documents().mapValues { try NormalizationFixture.fingerprint($0) }
        let url = fixtures.appendingPathComponent("nemotron-goldens.synthetic.json")
        if ProcessInfo.processInfo.environment["DAMA_CAPTURE_NEMOTRON_GOLDENS"] == "1" {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(fingerprints).write(to: url)
        }
        let expected = try JSONDecoder().decode([String: NormalizationFixture.Fingerprint].self, from: Data(contentsOf: url))
        XCTAssertEqual(Set(fingerprints.keys), Set(expected.keys))
        XCTAssertEqual(fingerprints.count, cases.count * SonioxNemotronReconciler.Version.allCases.count)
        for key in fingerprints.keys.sorted() { XCTAssertEqual(fingerprints[key], expected[key], key) }
    }
}

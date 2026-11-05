import Foundation
import XCTest
@testable import DamaCore

final class NormalizationGoldenTests: XCTestCase {
    private var fixtures: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url.appendingPathComponent("fixtures")
    }
    func testAllThreePathsKeepCompleteNormalizedReadingAndMarkdownGoldens() throws {
        let documents = try NormalizationFixture.documents(fixtures.appendingPathComponent("normalization-evidence.synthetic.json"))
        let expected = try JSONDecoder().decode([String: NormalizationFixture.Fingerprint].self,
            from: Data(contentsOf: fixtures.appendingPathComponent("normalization-goldens.synthetic.json")))
        XCTAssertEqual(Set(documents.keys), Set(expected.keys))
        XCTAssertEqual(documents.count, 21)
        for key in documents.keys.sorted() {
            XCTAssertEqual(try NormalizationFixture.fingerprint(documents[key]!), expected[key], key)
        }
    }
    func testFingerprintDetectsChangedTimeSpeakerIssuesAndMissingMarkerButIgnoresJSONKeyOrder() throws {
        let documents = try NormalizationFixture.documents(fixtures.appendingPathComponent("normalization-evidence.synthetic.json"))
        let original = try XCTUnwrap(documents["missing-short-b/combined"])
        let baseline = try NormalizationFixture.fingerprint(original)
        let raw = try JSONSerialization.jsonObject(with: NormalizedTranscriptCodec.encode(original))
        let reordered = try NormalizedTranscriptCodec.decode(JSONSerialization.data(withJSONObject: raw, options: []))
        XCTAssertEqual(try NormalizationFixture.fingerprint(reordered), baseline)
        var changedTime = original
        changedTime.words[0].startUs! += 1
        XCTAssertNotEqual(try NormalizationFixture.fingerprint(changedTime).normalized, baseline.normalized)
        var changedSpeaker = original
        changedSpeaker.words[0].modelSpeakerId = original.speakers.last!.id
        XCTAssertNotEqual(try NormalizationFixture.fingerprint(changedSpeaker).normalized, baseline.normalized)
        var changedIssue = original
        changedIssue.reviewIssues[0].severity = .info
        XCTAssertNotEqual(try NormalizationFixture.fingerprint(changedIssue).normalized, baseline.normalized)
        var missingMarker = original
        missingMarker.turns.removeAll { $0.kind == .missingSpeech }
        XCTAssertNotEqual(try NormalizationFixture.fingerprint(missingMarker), baseline)
    }
}

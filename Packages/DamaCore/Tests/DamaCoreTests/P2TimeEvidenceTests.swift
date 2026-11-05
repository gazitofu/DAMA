import Foundation
import XCTest
@testable import DamaCore

final class P2TimeEvidenceTests: XCTestCase {
    private func interval(_ id: String, _ speaker: String, _ start: Int64, _ end: Int64) -> DiarizationInterval {
        DiarizationInterval(id: id, startUs: start, endUs: end, speakerId: speaker, confidence: nil)
    }

    func testConversionKeepsSourceOrderRoundingConfidenceAndRejectsInvalidIntervals() throws {
        let source = [PyannoteDiarizationDTO(start: 0.2000006, end: 0.8000006, speaker: "B", confidence: ["A": 91, "B": 14]),
                      PyannoteDiarizationDTO(start: 0, end: 0.2, speaker: "A", confidence: nil)]
        let values = try P2TimeEvidence.intervals(source, prefix: "d", mapping: ["A": "run-0", "B": "run-1"], durationUs: 1_000_000)
        XCTAssertEqual(values.map(\.id), ["d0", "d1"])
        XCTAssertEqual(values.map(\.speakerId), ["run-1", "run-0"])
        XCTAssertEqual(values.map(\.startUs), [200_001, 0])
        XCTAssertEqual(values.map(\.endUs), [800_001, 200_000])
        XCTAssertEqual(values[0].confidence, ["A": 91, "B": 14])
        XCTAssertNil(values[1].confidence)
        for (start, end) in [(-0.1, 0.2), (0.2, 0.2), (0.3, 0.2), (0.0, 1.1), (Double.nan, 0.2), (0.0, Double.infinity)] {
            XCTAssertThrowsError(try P2TimeEvidence.intervals(
                [PyannoteDiarizationDTO(start: start, end: end, speaker: "A", confidence: nil)],
                prefix: "d", mapping: ["A": "run-0"], durationUs: 1_000_000))
        }
        XCTAssertThrowsError(try P2TimeEvidence.intervals(source, prefix: "d", mapping: ["A": "run-0"], durationUs: 1_000_000))
    }

    func testFrameGridEndOverrunIsClampedOnlyWithinTolerance() throws {
        // Observed shape: final P2 interval ends 9ms past the analysis audio.
        let values = try P2TimeEvidence.intervals(
            [PyannoteDiarizationDTO(start: 0.5, end: 1.009, speaker: "A", confidence: nil),
             PyannoteDiarizationDTO(start: 0.9, end: 1.020, speaker: "A", confidence: nil)],
            prefix: "e", mapping: ["A": "run-0"], durationUs: 1_000_000)
        XCTAssertEqual(values.map(\.startUs), [500_000, 900_000])
        XCTAssertEqual(values.map(\.endUs), [1_000_000, 1_000_000])
        for (start, end) in [(0.5, 1.021), (1.005, 1.010), (1.0, 1.010)] {
            XCTAssertThrowsError(try P2TimeEvidence.intervals(
                [PyannoteDiarizationDTO(start: start, end: end, speaker: "A", confidence: nil)],
                prefix: "e", mapping: ["A": "run-0"], durationUs: 1_000_000))
        }
    }

    func testUnionDoesNotDoubleCountAndDistinguishesBoundaryFromOverlap() throws {
        let regular = [interval("d0", "A", 0, 600), interval("d1", "B", 600, 1000)]
        // Deliberate duplicate/nested exclusive ranges exercise the pure union calculation.
        let exclusive = [interval("e0", "A", 200, 600), interval("e1", "A", 0, 400),
                         interval("e2", "A", 0, 400), interval("e3", "A", 100, 200), interval("e4", "B", 600, 1000)]
        let evidence = P2TimeEvidence.token(startUs: 0, endUs: 1000, regular: regular, exclusive: exclusive)
        XCTAssertEqual(evidence.scores.map(\.speakerID), ["A", "B"])
        XCTAssertEqual(evidence.scores.map(\.coverage), [0.6, 0.4])
        XCTAssertEqual(evidence.sourceIDs, ["d0", "d1", "e0", "e1", "e2", "e3", "e4"])
        XCTAssertTrue(evidence.boundary)
        XCTAssertFalse(evidence.overlap)
        let sameSpeaker = P2TimeEvidence.token(startUs: 0, endUs: 1000,
            regular: [interval("d0", "A", 0, 800), interval("d1", "A", 200, 1000)], exclusive: [])
        XCTAssertFalse(sameSpeaker.overlap)
        XCTAssertFalse(sameSpeaker.boundary)
        let crossSpeaker = P2TimeEvidence.token(startUs: 0, endUs: 1000,
            regular: regular + [interval("d2", "B", 500, 700)], exclusive: exclusive)
        XCTAssertTrue(crossSpeaker.overlap)
        let touching = P2TimeEvidence.token(startUs: 600, endUs: 1000, regular: regular, exclusive: [])
        XCTAssertEqual(touching.sourceIDs, ["d1"])
        XCTAssertFalse(touching.boundary)
        for (start, end): (Int64?, Int64?) in [(nil, 1000), (0, nil), (100, 100), (200, 100)] {
            let empty = P2TimeEvidence.token(startUs: start, endUs: end, regular: regular, exclusive: exclusive)
            XCTAssertTrue(empty.sourceIDs.isEmpty)
            XCTAssertNil(empty.best)
            XCTAssertFalse(empty.overlap)
            XCTAssertFalse(empty.boundary)
        }
    }

    func testBothConsumersKeepRankingThresholdAndPunctuationEligibility() throws {
        var fixtures = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { fixtures.deleteLastPathComponent() }
        let documents = try NormalizationFixture.documents(fixtures.appendingPathComponent("fixtures/normalization-evidence.synthetic.json"))
        for (path, prefix) in [("combined", "golden-p2-"), ("qwen", "golden-speaker-")] {
            let ranked = try XCTUnwrap(documents["dominant-later-label/\(path)"])
            XCTAssertEqual(ranked.words[0].modelSpeakerId, prefix + "1")
            XCTAssertEqual(ranked.words[0].alignmentScore, 0.8)
            let threshold = try XCTUnwrap(documents["coverage-threshold-and-tie/\(path)"])
            XCTAssertEqual(threshold.words[0].modelSpeakerId, prefix + "0")
            XCTAssertEqual(threshold.words[0].alignmentScore, 0.5)
            XCTAssertNil(threshold.words[0].speakerId)
            XCTAssertEqual(threshold.words[1].speakerId, prefix + "0")
            XCTAssertEqual(threshold.words[1].alignmentScore, 0.6)
            XCTAssertNil(threshold.words[2].speakerId)
            XCTAssertEqual(threshold.words[2].alignmentScore, 0.599)
        }
        let combined = try XCTUnwrap(documents["short-b-missing-punctuation/combined"])
        let qwen = try XCTUnwrap(documents["short-b-missing-punctuation/qwen"])
        let shortB = combined.diarization[1]
        XCTAssertEqual(P2TimeEvidence.matchingWordIndices(combined.words, interval: shortB, lexicalOnly: false), [1])
        XCTAssertEqual(P2TimeEvidence.matchingWordIndices(combined.words, interval: shortB, lexicalOnly: true), [])
        XCTAssertEqual(P2TimeEvidence.matchingWordIndices(qwen.words, interval: shortB, lexicalOnly: false), [1])
    }
}

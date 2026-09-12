import Foundation
import XCTest
@testable import DamaCore

final class SonioxPrecisionReconcilerTests: XCTestCase {
    private let date = "2026-09-13T00:00:00Z"
    private func token(_ text: String, _ start: Int?, _ end: Int?) -> [String: Any] {
        var value: [String: Any] = ["text": text, "speaker": "one", "confidence": 0.91, "language": "ko"]
        if let start { value["start_ms"] = start }; if let end { value["end_ms"] = end }
        return value
    }
    private func interval(_ label: String, _ start: Double, _ end: Double) -> [String: Any] {
        ["speaker": label, "start": start, "end": end, "confidence": ["A": 91.0, "B": 14.0]]
    }
    private func source(_ tokens: [[String: Any]], _ regular: [[String: Any]], _ exclusive: [[String: Any]]? = nil) throws -> TranscriptDocument {
        // Both labels exist because confidence is a map, not a scalar or normalized probability.
        let asr = try JSONSerialization.data(withJSONObject: ["id": "job", "text": tokens.map { $0["text"] as! String }.joined(), "tokens": tokens])
        let p2 = try JSONSerialization.data(withJSONObject: ["jobId": "p2", "status": "succeeded",
            "output": ["diarization": regular, "exclusiveDiarization": exclusive ?? regular]])
        return try SonioxPrecisionNormalizer.normalize(soniox: asr, diarization: p2, sonioxJobID: "job",
            sessionID: "synthetic-session", runID: "source", durationUs: 3_000_000,
            audioSHA256: String(repeating: "a", count: 64), model: "stt-async-v5", createdAt: date, synthetic: true)
    }
    private func compare(_ source: TranscriptDocument, _ policy: SonioxPrecisionComparison = .timeline) throws -> TranscriptDocument {
        try SonioxPrecisionReconciler.reconcile(source, runID: UUID().uuidString, createdAt: date, policy: policy)
    }
    private func labels(_ doc: TranscriptDocument) -> [String?] {
        let map = Dictionary(uniqueKeysWithValues: doc.speakers.map { ($0.id, $0.providerId) })
        return doc.words.map { $0.speakerId.flatMap { map[$0] } }
    }
    private var aba: [[String: Any]] { [interval("A", 0, 1), interval("B", 1, 1.2), interval("A", 1.2, 3)] }
    private func script(_ doc: TranscriptDocument) throws -> LibraryScript {
        try LibraryScript(transcript: doc, title: "Synthetic comparison", recordedAt: nil,
            dateSource: "synthetic", input: ConversionNotes())
    }

    func testMaximumIntersectionWinsAndExactTieRemainsUnknown() throws {
        let raw = try source([token("다수", 900, 1200), token(" 동률", 900, 1100)], aba)
        XCTAssertTrue(raw.words.allSatisfy { $0.speakerId == nil }) // Existing default is unchanged.
        let result = try compare(raw)
        XCTAssertEqual(labels(result), ["B", nil])
        XCTAssertEqual(result.words[0].alignmentScore!, 2.0/3.0, accuracy: 1e-12)
        XCTAssertTrue(result.reviewIssues.contains { $0.kind == .boundary_conflict })
    }

    func testOverlapRetainsCandidateAndEvidence() throws {
        let raw = try source([token("겹말", 1000, 1200)],
            [interval("A", 0, 2), interval("B", 1, 1.5)], [interval("A", 0, 2)])
        let result = try compare(raw)
        XCTAssertEqual(labels(result), ["A"])
        XCTAssertTrue(result.words[0].overlap)
        XCTAssertTrue(result.reviewIssues.contains { $0.kind == .overlapping_speech })
        XCTAssertTrue(result.reviewIssues.contains { $0.kind == .unrepresented_speaker })
        XCTAssertEqual(result.diarization[0].confidence, ["A": 91, "B": 14])
        XCTAssertFalse(result.words[0].sourceIntervalIds.isEmpty)
    }

    func testPointContainmentUsesHalfOpenBoundaryWithoutInventingDurationOrCoverage() throws {
        let raw = try source([token("경계", 1000, 1000), token(" 끝", 3000, 3000)], aba)
        let result = try compare(raw)
        XCTAssertEqual(labels(result), ["B", nil])
        XCTAssertEqual(result.words.map(\.startUs), [1_000_000, 3_000_000])
        XCTAssertEqual(result.words.map(\.endUs), [1_000_000, 3_000_000])
        XCTAssertTrue(result.words.allSatisfy { $0.alignmentScore == nil })
        XCTAssertEqual(result.reviewIssues.filter { $0.kind == .invalid_timestamp }.count, 2)
        XCTAssertFalse(result.turns.contains { $0.kind == .missingSpeech && $0.speakerId == result.words[0].speakerId })
    }

    func testNoIntersectionOrMissingTimeDoesNotUseNearestSpeaker() throws {
        let raw = try source([token("없음", 2200, 2400), token("시간없음", nil, nil)],
            [interval("A", 0, 1), interval("B", 1, 2)])
        for policy in SonioxPrecisionComparison.allCases {
            let result = try compare(raw, policy)
            XCTAssertEqual(labels(result), [nil, nil])
            XCTAssertNil(result.words[1].startUs)
        }
    }

    func testWordFragmentsShareSingleSpeakerEvidenceButNotAcrossSpeakerBoundary() throws {
        let raw = try source([token("진", 100, 180), token("행", 180, 200)],
            [interval("A", 0, 0.18), interval("B", 1, 2)])
        XCTAssertEqual(labels(try compare(raw)), ["A", nil])
        let word = try compare(raw, .word)
        XCTAssertEqual(labels(word), ["A", "A"])
        XCTAssertNil(word.words[1].alignmentScore)
        XCTAssertTrue(word.words[1].sourceIntervalIds.contains("e0"))
        let boundary = try source([token("진", 100, 180), token("행", 180, 180)],
            [interval("A", 0, 0.18), interval("B", 0.18, 2)])
        XCTAssertEqual(labels(try compare(boundary, .word)), ["A", "B"])
    }

    func testClosingPunctuationFollowsTextAndDoesNotCreateAnotherSpeakerUtterance() throws {
        let raw = try source([token("합니다", 100, 900), token(".", 1000, 1000), token(" 네", 1050, 1150)], aba)
        for policy in SonioxPrecisionComparison.allCases {
            let result = try compare(raw, policy)
            XCTAssertEqual(labels(result), ["A", "A", "B"])
            XCTAssertEqual(result.words.map(\.text).joined(), "합니다. 네")
            XCTAssertNil(result.words[1].alignmentScore)
        }
    }

    func testABAAndMissingBackchannelAreBarriersEvenInsideOrthographicGroup() throws {
        let raw = try source([token("첫", 100, 900), token(" 네", 1000, 1200), token(" 다시", 1300, 1900)], aba)
        let result = try compare(raw, .word)
        XCTAssertEqual(labels(result), ["A", "B", "A"])
        XCTAssertEqual(try script(result).blocks().map(\.text), ["첫", "네", "다시"])
        let missing = try source([token("진", 100, 900), token("행", 1300, 1900)], aba)
        let missingResult = try compare(missing, .word)
        XCTAssertEqual(missingResult.turns.map(\.kind), [.speech, .missingSpeech, .speech])
        XCTAssertEqual(try script(missingResult).blocks().count, 3)
    }

    func testTimelineReadsSentencesAndWordPolicyReadsContinuousSpeakerTurns() throws {
        let raw = try source([token("시작합니다.", 100, 500), token(" 계속합니다.", 600, 900)], aba)
        XCTAssertEqual(try script(compare(raw)).blocks().filter(\.isSpeech).count, 2)
        XCTAssertEqual(try script(compare(raw, .word)).blocks().filter(\.isSpeech).count, 1)
        let reversed = try source([token("첫", 500, 700), token("조각", 100, 400)], aba)
        XCTAssertEqual(try compare(reversed, .word).turns.filter { $0.kind == .speech }.count, 2)
    }

    func testSourceFieldsRunIsolationAndSerializationArePreserved() throws {
        let raw = try source([token("원문", 100, 200), token(" 그대로", 1000, 1200)], aba)
        let before = try NormalizedTranscriptCodec.encode(raw)
        for policy in SonioxPrecisionComparison.allCases {
            let result = try compare(raw, policy)
            XCTAssertNotEqual(result.runId, raw.runId)
            XCTAssertTrue(Set(raw.speakers.map(\.id)).isDisjoint(with: result.speakers.map(\.id)))
            XCTAssertEqual(result.provenance.algorithmVersion, policy.rawValue)
            for (a,b) in zip(raw.words,result.words) {
                XCTAssertEqual(a.id,b.id); XCTAssertEqual(a.ordinal,b.ordinal); XCTAssertEqual(a.prefix,b.prefix)
                XCTAssertEqual(a.text,b.text); XCTAssertEqual(a.startUs,b.startUs); XCTAssertEqual(a.endUs,b.endUs)
                XCTAssertEqual(a.tokenKind,b.tokenKind); XCTAssertEqual(a.asrSpeakerLabel,b.asrSpeakerLabel)
                XCTAssertEqual(a.asrConfidence,b.asrConfidence); XCTAssertEqual(a.language,b.language)
            }
            _ = try NormalizedTranscriptCodec.decode(NormalizedTranscriptCodec.encode(result))
            _ = try script(result).markdown()
        }
        XCTAssertEqual(try NormalizedTranscriptCodec.encode(raw), before)
        XCTAssertThrowsError(try SonioxPrecisionReconciler.reconcile(raw, runID: raw.runId, createdAt: date, policy: .word))
    }
}

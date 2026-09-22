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

    // Use the same comparison run ID so byte comparisons isolate policy changes.
    private func atomicPair(_ raw: TranscriptDocument) throws -> (TranscriptDocument, TranscriptDocument) {
        let runID = UUID().uuidString
        return (try SonioxPrecisionReconciler.reconcile(raw, runID: runID, createdAt: date, policy: .wordRepair),
                try SonioxPrecisionReconciler.reconcile(raw, runID: runID, createdAt: date, policy: .wordAtomic))
    }

    private func wordBytes(_ words: [TranscriptWord]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(words)
    }

    private func splitAtomicSource() throws -> TranscriptDocument {
        try source([token("해", 0, 400), token("야", 400, 800), token("지", 800, 1000),
                    token(".", 1100, 1100)],
                   [interval("A", 0, 0.8), interval("B", 0.8, 1.2)])
    }

    func testWordAtomicUnifiesSplitOrthographicWord() throws {
        let (v4, v5) = try atomicPair(splitAtomicSource())
        XCTAssertEqual(labels(v4), ["A", "A", "B", "B"])
        XCTAssertEqual(labels(v5), ["A", "A", "A", "A"])
        XCTAssertTrue(v5.words.allSatisfy { $0.alignmentScore == nil })
        for word in v5.words {
            XCTAssertEqual(word.sourceIntervalIds, ["d0", "d1", "e0", "e1"])
        }
        XCTAssertTrue(v5.words[3].reviewIssueIds.isEmpty)
    }

    func testWordAtomicKeepsTiedWordUnchanged() throws {
        let raw = try source([token("차", 0, 500), token("액", 500, 1000)],
                             [interval("A", 0, 0.5), interval("B", 0.5, 1)])
        let (v4, v5) = try atomicPair(raw)
        XCTAssertEqual(labels(v4), ["A", "B"])
        XCTAssertEqual(try wordBytes(v5.words), try wordBytes(v4.words))
    }

    func testWordAtomicLeavesUnanimousWordAlone() throws {
        let tokens = [token("차", 0, 100), token("액", 900, 1000)]
        // Whole-word B wins, but both direct token choices are A.
        let unanimous = try source(tokens, [interval("A", 0, 0.1), interval("B", 0.1, 0.9), interval("A", 0.9, 1)])
        // Each token ties; whole-word A wins because it also covers the gap.
        let unknown = try source(tokens, [interval("A", 0, 0.05), interval("B", 0.05, 0.1),
            interval("A", 0.1, 0.95), interval("B", 0.95, 1)])
        let shared = try source([token("진", 100, 180), token("행", 180, 200)],
                                [interval("A", 0, 0.18), interval("B", 1, 2)])
        let tail = try source([token("앞", 100, 200), token(" 뒤", 300, 350), token("쪽", 350, 400)],
                              [interval("A", 0, 0.2), interval("B", 2, 3)])
        for (raw, expected) in [(unanimous, ["A", "A"] as [String?]),
                                (unknown, [nil, nil]), (shared, ["A", "A"]), (tail, ["A", "A", "A"])] {
            let (v4, v5) = try atomicPair(raw)
            XCTAssertEqual(labels(v4), expected)
            XCTAssertEqual(try wordBytes(v5.words), try wordBytes(v4.words))
        }
    }

    func testWordAtomicDoesNotCrossWhitespace() throws {
        let raw = try source([token("첫", 100, 900), token(" 네", 1000, 1200), token(" 다시", 1300, 1900)], aba)
        let (v4, v5) = try atomicPair(raw)
        XCTAssertEqual(labels(v5), ["A", "B", "A"])
        XCTAssertEqual(try wordBytes(v5.words), try wordBytes(v4.words))
        XCTAssertEqual(v5.turns.filter { $0.kind == .speech }.map(\.wordIds), v5.words.map { [$0.id] })
    }

    func testWordAtomicPreservesTokensAndTimes() throws {
        let (v4, v5) = try atomicPair(splitAtomicSource())
        XCTAssertNotEqual(try wordBytes(v5.words), try wordBytes(v4.words))
        var restored = v5.words
        for i in restored.indices {
            // Restore only the six permitted fields; every other serialized field must match.
            restored[i].speakerId = v4.words[i].speakerId
            restored[i].modelSpeakerId = v4.words[i].modelSpeakerId
            restored[i].assignmentSource = v4.words[i].assignmentSource
            restored[i].alignmentScore = v4.words[i].alignmentScore
            restored[i].sourceIntervalIds = v4.words[i].sourceIntervalIds
            restored[i].reviewIssueIds = v4.words[i].reviewIssueIds
        }
        XCTAssertEqual(try wordBytes(restored), try wordBytes(v4.words))
    }

    func testWordAtomicKeepsOverlapAndBoundaryFlags() throws {
        let raw = try source([token("해", 0, 400), token("야", 400, 850), token("지", 850, 1000)],
            [interval("A", 0, 0.8), interval("B", 0.6, 1)],
            [interval("A", 0, 0.8), interval("B", 0.8, 1)])
        let (v4, v5) = try atomicPair(raw)
        XCTAssertEqual(labels(v4), ["A", "A", "B"])
        XCTAssertEqual(labels(v5), ["A", "A", "A"])
        XCTAssertEqual(v5.words.map(\.overlap), [false, true, false])
        for (i, word) in v5.words.enumerated() {
            let direct = P2TimeEvidence.token(startUs: word.startUs, endUs: word.endUs,
                regular: v5.diarization, exclusive: v5.exclusiveDiarization)
            let issues = v5.reviewIssues.filter { word.reviewIssueIds.contains($0.id) }
            XCTAssertEqual(word.overlap, direct.overlap)
            XCTAssertEqual(issues.contains { $0.kind == .overlapping_speech }, direct.overlap)
            XCTAssertEqual(issues.contains { $0.kind == .boundary_conflict }, direct.boundary)
            XCTAssertEqual(direct.boundary, i == 1)
        }
    }

    func testWordAtomicRunPassesValidator() throws {
        let result = try compare(splitAtomicSource(), .wordAtomic)
        XCTAssertNoThrow(try TranscriptValidator().validate(result))
        XCTAssertEqual(result.provenance.algorithmVersion, "soniox-p2-word-v5")
        _ = try NormalizedTranscriptCodec.decode(NormalizedTranscriptCodec.encode(result))
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

    func testABABarriersRemainInSourceWhileUntranscribedDetectionDoesNotSplitReading() throws {
        let raw = try source([token("첫", 100, 900), token(" 네", 1000, 1200), token(" 다시", 1300, 1900)], aba)
        let result = try compare(raw, .word)
        XCTAssertEqual(labels(result), ["A", "B", "A"])
        XCTAssertEqual(try script(result).blocks().map(\.text), ["첫", "네", "다시"])
        let missing = try source([token("진", 100, 900), token("행", 1300, 1900)], aba)
        let missingResult = try compare(missing, .word)
        XCTAssertEqual(missingResult.turns.map(\.kind), [.speech, .missingSpeech, .speech])
        XCTAssertEqual(try script(missingResult).blocks().map(\.text), ["진행"])
    }

    func testBothPoliciesReadContinuousSpeakerWithDifferentSourceGranularity() throws {
        let raw = try source([token("시작합니다.", 100, 500), token(" 계속합니다.", 600, 900)], aba)
        XCTAssertEqual(try compare(raw).turns.filter { $0.kind == .speech }.count, 2)
        XCTAssertEqual(try script(compare(raw)).blocks().filter(\.isSpeech).count, 1)
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

    func testPhraseTailSharesP2EvidenceWithoutPunctuationTimeAttribution() throws {
        let raw = try source([token("질문", 100, 500), token(" ", 600, 660), token("인", 700, 760),
                              token("가", 800, 860), token("?", 1500, 1560), token(" 답", 1700, 1800)],
                             [interval("A", 0, 0.6), interval("B", 1.5, 3)])
        let old = try compare(raw, .word), repaired = try compare(raw, .wordRepair)
        XCTAssertEqual(Array(labels(old).prefix(5)), ["A", "A", nil, nil, nil])
        XCTAssertEqual(labels(repaired), ["A", "A", "A", "A", "A", "B"])
        XCTAssertNil(repaired.words[2].alignmentScore)
        XCTAssertEqual(repaired.words[2].sourceIntervalIds, ["d0", "e0"])
        XCTAssertFalse(repaired.words[4].sourceIntervalIds.contains("e1"))
        XCTAssertEqual(try script(repaired).blocks().map(\.text), ["질문 인가?", "답"])
    }

    func testTailRepairDoesNotCrossCommaASRChangeOtherVoiceOrTwoWords() throws {
        let base = [token("앞", 100, 200), token(",", 200, 260), token(" 이", 300, 360), token("거", 360, 420), token(".", 420, 480)]
        let intervals = [interval("A", 0, 0.25), interval("B", 1.5, 3)]
        XCTAssertEqual(Array(labels(try compare(source(base, intervals), .wordRepair)).suffix(3)), [nil, nil, nil])
        var changed = [token("앞", 100, 200), token(" 뒤", 300, 400)]
        changed[1]["speaker"] = "two"
        XCTAssertNil(try compare(source(changed, intervals), .wordRepair).words[1].speakerId)
        let newLine = [token("앞", 100, 200), token("\n뒤", 300, 400)]
        XCTAssertNil(try compare(source(newLine, intervals), .wordRepair).words[1].speakerId)
        let twoWords = [token("앞", 100, 200), token(" 뒤", 300, 360), token(" 또", 400, 460)]
        XCTAssertNil(try compare(source(twoWords, intervals), .wordRepair).words[1].speakerId)
        let interrupted = [interval("A", 0, 0.2), interval("B", 0.21, 0.22)]
        let raw = try source([token("앞", 100, 200), token(" 뒤", 300, 400)], interrupted)
        XCTAssertNil(try compare(raw, .wordRepair).words[1].speakerId)
    }

    func testTailRepairGapAndSpan500MillisecondsAreInclusiveNot501() throws {
        let intervals = [interval("A", 0, 0.2), interval("B", 2, 3)]
        for (start, end, expected) in [(700, 800, "A" as String?), (701, 801, nil), (300, 800, "A"), (300, 801, nil)] {
            let raw = try source([token("앞", 100, 200), token(" 뒤", start, end)], intervals)
            XCTAssertEqual(labels(try compare(raw, .wordRepair))[1], expected, "\(start)-\(end)ms")
        }
    }
}

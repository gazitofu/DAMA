import Foundation
import XCTest
@testable import DamaCore

final class SonioxPrecisionTests: XCTestCase {
    private func normalize(_ tokens: [[String: Any]], intervals: [[String: Any]], exclusive: [[String: Any]]? = nil) throws -> TranscriptDocument {
        let asr = try JSONSerialization.data(withJSONObject: ["id": "job", "text": tokens.map { $0["text"] as! String }.joined(), "tokens": tokens])
        let p2 = try JSONSerialization.data(withJSONObject: ["jobId": "p2", "status": "succeeded", "output": ["diarization": intervals, "exclusiveDiarization": exclusive ?? intervals]])
        return try SonioxPrecisionNormalizer.normalize(soniox: asr, diarization: p2, sonioxJobID: "job", sessionID: "s", runID: "r",
            durationUs: 3_000_000, audioSHA256: String(repeating: "a", count: 64), model: "stt-async-v5", createdAt: "2026-09-11T00:00:00Z", synthetic: true)
    }
    private func token(_ text: String, _ start: Int, _ end: Int) -> [String: Any] {
        ["text": text, "start_ms": start, "end_ms": end, "speaker": "one", "confidence": 0.9]
    }
    private let intervals: [[String: Any]] = [
        ["speaker": "A", "start": 0.0, "end": 1.0],
        ["speaker": "B", "start": 1.0, "end": 1.2],
        ["speaker": "A", "start": 1.2, "end": 3.0]]
    func testTokenReassignmentPreservesOriginalCandidateAndABA() throws {
        let doc = try normalize([token("다음", 100, 900), token(" 네", 1000, 1200), token(" 안 합니다", 1300, 2000)], intervals: intervals)
        XCTAssertEqual(doc.words.map(\.speakerId), ["r-p2-0", "r-p2-1", "r-p2-0"])
        XCTAssertEqual(doc.words.map(\.asrSpeakerLabel), ["one", "one", "one"])
        XCTAssertEqual(doc.words.map(\.asrConfidence), [0.9, 0.9, 0.9])
        XCTAssertEqual(doc.words.map(\.startUs), [100_000, 1_000_000, 1_300_000])
        XCTAssertTrue(doc.reviewIssues.contains { $0.kind == .provider_disagreement })
        let script = try LibraryScript(transcript: doc, title: "synthetic", recordedAt: nil, dateSource: "synthetic", input: ConversionNotes())
        XCTAssertEqual(script.blocks().map(\.text), ["다음", "네", "안 합니다"])
        let decoded = try NormalizedTranscriptCodec.decode(NormalizedTranscriptCodec.encode(doc))
        XCTAssertEqual(decoded.words.map(\.asrSpeakerLabel), doc.words.map(\.asrSpeakerLabel))
    }
    func testMissingShortSpeakerRemainsBarrier() throws {
        let doc = try normalize([token("그래서", 100, 900), token(" 이어서", 1300, 2000)], intervals: intervals)
        XCTAssertEqual(doc.turns.map(\.kind), [.speech, .missingSpeech, .speech])
        XCTAssertEqual(doc.words.map(\.text).joined(), "그래서 이어서")
    }
    func testDisagreementIsLocalToTransitionNotEveryWordInCluster() throws {
        let doc = try normalize([token("첫", 100, 200), token(" 계속", 200, 300), token(" 전환 전", 800, 900),
                                 token(" 네", 1000, 1200), token(" 다시", 1300, 1500), token(" 계속", 1500, 1700)], intervals: intervals)
        let flagged = Set(doc.reviewIssues.filter { $0.kind == .provider_disagreement }.flatMap(\.wordIds))
        XCTAssertEqual(flagged, Set(doc.words[2...4].map(\.id)))
        let events = ScriptReviewEvent.forListening(doc.reviewIssues)
        XCTAssertEqual(Set(events.flatMap { $0.issues.map(\.id) }), Set(doc.reviewIssues.map(\.id)))
        XCTAssertEqual(events.count, 1)
    }
    func testBoundaryZeroTimeAndUncoveredTokenNeverGuessSpeaker() throws {
        let doc = try normalize([token("경계", 900, 1100), token(".", 1100, 1100), token("바깥", 2000, 2100)],
            intervals: Array(intervals.prefix(2)))
        XCTAssertTrue(doc.words.allSatisfy { $0.speakerId == nil })
        XCTAssertEqual(doc.words[1].startUs, 1_100_000)
        XCTAssertTrue(doc.reviewIssues.contains { $0.kind == .boundary_conflict })
        XCTAssertFalse(doc.words[0].overlap)
        let overlap = try normalize([token("겹말", 1000, 1200)], intervals: [
            ["speaker":"A", "start":0.0,"end":2.0], ["speaker":"B","start":1.0,"end":1.5]],
            exclusive: [["speaker":"A", "start":0.0,"end":2.0]])
        XCTAssertTrue(overlap.words[0].overlap); XCTAssertNil(overlap.words[0].speakerId)
    }
}

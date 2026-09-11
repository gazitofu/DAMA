import Foundation
import XCTest
@testable import DamaCore

final class SonioxNormalizerTests: XCTestCase {
    private func normalize(_ tokens: [[String: Any]], text: String? = nil, run: String = "run") throws -> TranscriptDocument {
        let data = try JSONSerialization.data(withJSONObject: ["id": "job", "text": text ?? tokens.map { $0["text"] as! String }.joined(), "tokens": tokens])
        return try SonioxNormalizer.normalize(data, jobID: "job", sessionID: "session", runID: run,
            durationUs: 100_000_000, audioSHA256: String(repeating: "a", count: 64), synthetic: true, createdAt: "2026-09-11T00:00:00Z")
    }
    private func token(_ text: String, _ start: Int, _ end: Int, _ speaker: String? = "1") -> [String: Any] {
        ["text": text, "start_ms": start, "end_ms": end, "speaker": speaker as Any? ?? NSNull(), "confidence": 0.91, "language": "ko"]
    }
    func testSubwordsWhitespaceSentenceAndSpeakerBoundariesSurviveExport() throws {
        let tokens = [token("이번", 0, 100), token("에", 100, 200), token(" 검토", 2_000, 2_500),
                      token("할 회사입니다", 40_000, 41_000), token(".", 41_000, 41_000),
                      token(" 다음", 42_000, 43_000), token(" 네", 43_000, 43_500, "2"), token(" 이어서", 44_000, 45_000)]
        let document = try normalize(tokens)
        XCTAssertEqual(document.turns.map { $0.wordIds.count }, [5, 1, 1, 1])
        XCTAssertEqual(document.words.map(\.text), tokens.map { $0["text"] as! String })
        XCTAssertTrue(document.words.allSatisfy { $0.prefix.isEmpty && $0.alignmentScore == nil && $0.asrConfidence == 0.91 })
        XCTAssertEqual(document.words[3].startUs, 40_000_000)
        XCTAssertTrue(document.diarization.isEmpty); XCTAssertTrue(document.exclusiveDiarization.isEmpty)
        let script = try LibraryScript(transcript: document, title: "합성 비교", recordedAt: nil, dateSource: "synthetic", input: ConversionNotes())
        XCTAssertEqual(script.blocks().map(\.text), ["이번에 검토할 회사입니다.", "다음", "네", "이어서"])
        let normalized = try NormalizedTranscriptCodec.decode(NormalizedTranscriptCodec.encode(document))
        XCTAssertEqual(normalized.words.map(\.asrConfidence), document.words.map(\.asrConfidence))
        let loaded = try JSONDecoder().decode(LibraryScript.self, from: JSONEncoder().encode(script))
        let md = String(decoding: try loaded.markdown(), as: UTF8.self)
        XCTAssertTrue(md.contains("이번에 검토할 회사입니다\\.")); XCTAssertFalse(md.contains("이번 에"))
        XCTAssertTrue(md.contains("Soniox")); XCTAssertTrue(md.contains("stt\\-async\\-v5"))
        XCTAssertEqual(loaded.transcript.words.map(\.language), Array(repeating: "ko", count: 8))
    }
    func testUnknownSpeakerInvalidAndReversedTimingRemainVisibleWithoutAttributionGuess() throws {
        let doc = try normalize([token("A", 1_000, 1_200), token("네", 1_200, 1_300, nil),
                                 token("A", 1_400, 1_500), token("역행", 900, 950), token("잘못된 시간", -1, 99)])
        XCTAssertNil(doc.words[1].speakerId); XCTAssertEqual(doc.words[1].assignmentSource, .unknown)
        XCTAssertNil(doc.words[4].startUs)
        XCTAssertEqual(doc.turns.count, 5)
        XCTAssertTrue(doc.reviewIssues.contains { $0.kind == .ambiguous_speaker })
        XCTAssertTrue(doc.reviewIssues.contains { $0.kind == .invalid_timestamp })
        XCTAssertEqual(doc.words.map(\.ordinal), [0, 1, 2, 3, 4])
        let other = try normalize([token("A", 0, 10)], run: "new-run")
        XCTAssertNotEqual(doc.speakers.first?.id, other.speakers.first?.id)
    }
    func testSeparateClosingQuoteEllipsisAndDecimalTokensDoNotCreateFragments() throws {
        let values = ["말했습니다", ".", "\"", " 다음", "...", " 숫자는 3", ".", "14", "입니다", "."]
        let doc = try normalize(values.enumerated().map { token($0.element, $0.offset * 100, ($0.offset + 1) * 100) })
        let script = try LibraryScript(transcript: doc, title: "punctuation", recordedAt: nil, dateSource: "synthetic", input: ConversionNotes())
        XCTAssertEqual(script.blocks().map(\.text), ["말했습니다.\"", "다음... 숫자는 3.14입니다."])
        XCTAssertEqual(doc.words.map(\.text), values)
    }
    func testOverlapAndTextMismatchAreNotSilentlyDiscarded() throws {
        let doc = try normalize([token("A", 0, 500), token("B", 200, 400, "2"), token("A", 500, 800)])
        XCTAssertEqual(doc.words.map(\.overlap), [true, true, false])
        XCTAssertEqual(doc.turns.count, 3)
        XCTAssertThrowsError(try normalize([token("원문", 0, 10)], text: "다른 원문"))
        var bad = token("bad confidence", 0, 10); bad["confidence"] = 91
        XCTAssertThrowsError(try normalize([bad]))
    }
    func testLegacyNotesAndContextOptInSnapshot() throws {
        var input = try JSONDecoder().decode(ConversionNotes.self, from: Data("{\"context\":\"topic\",\"reference\":\"local only\"}".utf8))
        XCTAssertEqual(input.provider, .pyannote)
        input.transcriptionProvider = .soniox
        let file = UUID().uuidString, run = UUID().uuidString
        var payload = try JSONSerialization.jsonObject(with: SonioxRequest.payload(fileID: file, runID: run, input: input)) as! [String: Any]
        XCTAssertNil(payload["context"]); XCTAssertNil(payload["numSpeakers"])
        XCTAssertEqual(payload["language_hints"] as? [String], ["ko", "en"])
        XCTAssertEqual(payload["model"] as? String, "stt-async-v5")
        input.sonioxContext = true; input.sonioxTerms = "DAMA\nSMR\n"
        payload = try JSONSerialization.jsonObject(with: SonioxRequest.payload(fileID: file, runID: run, input: input)) as! [String: Any]
        let context = payload["context"] as! [String: Any]
        XCTAssertEqual(context["terms"] as? [String], ["DAMA", "SMR"])
        XCTAssertEqual(context["text"] as? String, "local only")
        input.reference = String(repeating: "가", count: 3_000)
        XCTAssertThrowsError(try input.validate())
        input.sonioxContext = false
        XCTAssertNoThrow(try input.validate())
    }
}

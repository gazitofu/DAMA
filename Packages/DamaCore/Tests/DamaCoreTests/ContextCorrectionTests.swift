import Foundation
import XCTest
@testable import DamaCore

final class ContextCorrectionTests: XCTestCase {
    func makeScript(_ texts: [String]) throws -> LibraryScript {
        let intervals: [[String: Any]] = texts.enumerated().map { ["start": $0.offset * 3, "end": $0.offset * 3 + 2, "speaker": "A"] }
        let words: [[String: Any]] = texts.enumerated().map { ["start": $0.offset * 3, "end": $0.offset * 3 + 1, "speaker": "A", "text": $0.element] }
        let bytes = try JSONSerialization.data(withJSONObject: ["jobId": "synthetic", "status": "succeeded", "output":
            ["diarization": intervals, "exclusiveDiarization": intervals, "wordLevelTranscription": words]])
        let model = try ManagedNormalizer.normalize(bytes, sessionID: "synthetic", runID: "synthetic", durationUs: Int64(texts.count * 3_000_000),
            audioSHA256: String(repeating: "a", count: 64), synthetic: true, createdAt: "2026-09-10T00:00:00Z")
        return try LibraryScript(transcript: model, title: "합성 문맥 교정", recordedAt: nil, dateSource: "합성", input: ConversionNotes(participants: "김민수 · 예시회사"))
    }
    func testAutomaticCorrectionPreservesOriginalHumanEditsAndMarkdownJourney() throws {
        var script = try makeScript(["예시 회사를 논의합니다", "매출은 30억원이 아닙니다", "확인 필요"])
        let original = try JSONEncoder().encode(script.transcript)
        let chunk = try XCTUnwrap(ContextCorrection.chunks(script).first)
        let response = CorrectionReply(turns: [
            .init(id: chunk.turns[0].id, text: "예시회사를 논의합니다.", certain: true, reason: "회사명 표기"),
            .init(id: chunk.turns[1].id, text: "매출은 50억원입니다", certain: true, reason: "참고 문서"),
            .init(id: chunk.turns[2].id, text: "확인 필요", certain: false, reason: "원음 확인")], names: [])
        let result = try ContextCorrection.validated(response, chunk: chunk, input: script.input)
        XCTAssertEqual(result.edits.map(\.applied), [true, false, false])
        var correction = ScriptCorrection(input: script.input, engine: "synthetic", state: .completed)
        correction.edits = result.edits; script.correction = correction
        XCTAssertEqual(script.text(for: script.transcript.turns[0]), "예시회사를 논의합니다.")
        XCTAssertTrue(script.blocks()[0].text.contains("예시회사를"))
        XCTAssertEqual(script.text(for: script.transcript.turns[1]), script.originalText(for: script.transcript.turns[1]))
        script.showsOriginal = true
        XCTAssertEqual(script.text(for: script.transcript.turns[0]), "예시 회사를 논의합니다")
        script.showsOriginal = false
        try script.editText(chunk.turns[0].id, text: "사람이 수정한 회사명")
        let loaded = try JSONDecoder().decode(LibraryScript.self, from: JSONEncoder().encode(script))
        try loaded.validate()
        XCTAssertEqual(loaded.text(for: loaded.transcript.turns[0]), "사람이 수정한 회사명")
        let before = try JSONSerialization.jsonObject(with: original) as! NSDictionary
        XCTAssertEqual(try JSONSerialization.jsonObject(with: JSONEncoder().encode(loaded.transcript)) as? NSDictionary, before)
        let md = String(decoding: try loaded.markdown(), as: UTF8.self)
        XCTAssertTrue(md.contains("사람이 수정한 회사명")); XCTAssertTrue(md.contains("AI 교정 정보"))
        XCTAssertTrue(md.contains("교정 전:")); XCTAssertTrue(md.contains("김민수"))
    }
    func testChunkOwnershipCoverageMalformedReplyAndLegacyDecode() throws {
        let script = try makeScript((0..<250).map { "합성 발화 \($0)" })
        let chunks = try ContextCorrection.chunks(script)
        XCTAssertEqual(chunks.map { $0.turns.count }, [100, 100, 50])
        XCTAssertEqual(chunks.flatMap(\.turns).map(\.id), script.transcript.turns.map(\.id))
        XCTAssertFalse(chunks[1].contextBefore.isEmpty)
        XCTAssertThrowsError(try ContextCorrection.validated(.init(turns: [], names: []), chunk: chunks[0], input: script.input))
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(script)) as! [String: Any]
        json.removeValue(forKey: "correction"); json.removeValue(forKey: "showsOriginal")
        json["input"] = ["context": "", "reference": ""]
        let legacy = try JSONDecoder().decode(LibraryScript.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(legacy.correction); XCTAssertNil(legacy.input.participants)
    }
    func testNamesNeedRosterAndLiteralIntroductionInsteadOfTopicGuess() throws {
        let script = try makeScript(["저는 김민수입니다", "다음은 제품 설명입니다"])
        let chunk = try XCTUnwrap(ContextCorrection.chunks(script).first)
        let speaker = try XCTUnwrap(chunk.turns[0].speakerID)
        let turns = chunk.turns.map { CorrectionReply.Turn(id: $0.id, text: $0.text, certain: true, reason: "") }
        let guess = CorrectionReply.Name(speakerID: speaker, name: "김민수", evidenceTurnID: chunk.turns[1].id, quote: "제품 설명입니다")
        XCTAssertTrue(try ContextCorrection.validated(.init(turns: turns, names: [guess]), chunk: chunk, input: script.input).names.isEmpty)
        let literal = CorrectionReply.Name(speakerID: speaker, name: "김민수", evidenceTurnID: chunk.turns[0].id, quote: "저는 김민수입니다")
        XCTAssertEqual(try ContextCorrection.validated(.init(turns: turns, names: [literal]), chunk: chunk, input: script.input).names[speaker], "김민수")
    }
}

import Foundation
import XCTest
@testable import DamaCore

/// turn-continuity AC-07 (D-02 · reading-v9): 이웃한 «화자 미확정» 어절은 같은 ASR label · 사이 부호뿐 · 간격 300 ms 이하일 때
/// 한 문단으로 잇는다. 화자는 null 그대로이고 Turn·이슈는 바뀌지 않는다 (INV-05 · INV-10). 시간은 Int64 µs.
final class ReadingUnknownNeighbourTests: XCTestCase {
    private let runID = "00000000-0000-4000-8000-00000000e0c1"

    /// Soniox + Nemotron v3, 활성 채널 없음 → 모든 단어 미배정, 단어마다 Turn (v3는 미상 Turn을 잇지 않는다).
    private func document(_ tokens: [(String, Int, Int, String?)]) throws -> TranscriptDocument {
        let items: [[String: Any]] = tokens.map { item in
            var token: [String: Any] = ["text": item.0, "start_ms": item.1, "end_ms": item.2, "confidence": 0.9]
            if let label = item.3 { token["speaker"] = label }
            return token
        }
        let asr = try JSONSerialization.data(withJSONObject: ["id": "job", "text": tokens.map(\.0).joined(), "tokens": items])
        var data = Data()
        for value in [Float](repeating: 0.02, count: 300 * 8) { withUnsafeBytes(of: value.bitPattern.littleEndian) { data.append(contentsOf: $0) } }
        let doc = try SonioxNemotronReconciler.normalize(soniox: asr, probabilities: data, frameCount: 300, channels: 8,
            sonioxJobID: "job", sessionID: "s", runID: runID, durationUs: 3_000_000, audioSHA256: String(repeating: "a", count: 64),
            model: "stt-async-v5", createdAt: "2026-11-17T00:00:00Z", synthetic: true, version: .v3)
        XCTAssertTrue(doc.words.allSatisfy { $0.speakerId == nil })
        return doc
    }
    private func script(_ doc: TranscriptDocument) throws -> LibraryScript {
        try LibraryScript(transcript: doc, title: "합성 미상", recordedAt: nil, dateSource: "합성", input: ConversionNotes())
    }
    private func blocks(_ tokens: [(String, Int, Int, String?)]) throws -> [ScriptBlock] { try script(document(tokens)).blocks() }
    /// 두 번째 단어 Turn의 시작을 µs로 옮긴다 (단어 하나짜리 Turn).
    private func moved(_ doc: TranscriptDocument, wordIndex: Int, startUs: Int64) -> TranscriptDocument {
        var value = doc
        value.words[wordIndex].startUs = startUs
        let id = value.words[wordIndex].id
        if let t = value.turns.firstIndex(where: { $0.wordIds == [id] }) { value.turns[t].startUs = startUs }
        return value
    }

    func testVersionAndGap() {
        XCTAssertEqual(ScriptReadingPolicy.algorithmVersion, "reading-v9")
        XCTAssertEqual(ScriptReadingPolicy.unknownWordGapUs, 300_000)
    }

    func testNeighbouringUnknownWordsJoinIntoOneUnknownParagraph() throws {
        let doc = try document([("그래서", 100, 400, "x"), (" 다음", 500, 700, "x")])
        let value = try script(doc)
        let result = value.blocks()
        XCTAssertEqual(result.map(\.text), ["그래서 다음"])
        XCTAssertEqual(result[0].name, "화자 미확정")
        XCTAssertNil(result[0].speakerID)
        // Turn·화자·이슈는 그대로 (읽기 표시만 잇는다).
        XCTAssertEqual(value.transcript.turns.filter { $0.kind == .speech }.count, 2)
        XCTAssertTrue(value.transcript.words.allSatisfy { $0.speakerId == nil })
        XCTAssertEqual(value.transcript.reviewIssues.filter { $0.kind == .ambiguous_speaker }.count, 2)
        XCTAssertTrue(String(decoding: try value.markdown(), as: UTF8.self).contains("화자 미확정\n\n그래서 다음"))
        // 사이 부호만 있으면 잇는다.
        XCTAssertEqual(try blocks([("그래서", 100, 400, "x"), (".", 400, 410, "x"), (" 다음", 500, 700, "x")]).map(\.text), ["그래서. 다음"])
    }

    /// 간격 경계: 300,000 µs 이음 · 300,001 µs 안 이음 · −1 µs(겹침) 이음.
    func testGapBoundaryInMicroseconds() throws {
        let doc = try document([("그래서", 100, 400, "x"), (" 다음", 500, 900, "x")])
        XCTAssertEqual(try script(moved(doc, wordIndex: 1, startUs: 400_000 + 300_000)).blocks().count, 1)
        XCTAssertEqual(try script(moved(doc, wordIndex: 1, startUs: 400_000 + 300_001)).blocks().count, 2)
        XCTAssertEqual(try script(moved(doc, wordIndex: 1, startUs: 400_000 - 1)).blocks().count, 1)
    }

    /// 조건 하나씩 어김 → 안 이음.
    func testEachConditionAloneBlocksTheJoin() throws {
        let base: [(String, Int, Int, String?)] = [("그래서", 100, 400, "x"), (" 다음", 500, 700, "x")]
        XCTAssertEqual(try blocks(base).count, 1) // 대조군
        // ① 원문 공백을 보존하지 않는 엔진.
        var engine = try document(base); engine.provenance.engine = .hybridPyannoteWhisperKit
        XCTAssertEqual(try script(engine).blocks().count, 2)
        // ② ASR label 다름 · 한쪽 없음.
        XCTAssertEqual(try blocks([("그래서", 100, 400, "x"), (" 다음", 500, 700, "y")]).count, 2)
        XCTAssertEqual(try blocks([("그래서", 100, 400, "x"), (" 다음", 500, 700, nil)]).count, 2)
        XCTAssertEqual(try blocks([("그래서", 100, 400, nil), (" 다음", 500, 700, nil)]).count, 2)
        // ③ 원 ordinal 사이에 lexical 1개 (Turn 순서 ≠ ordinal 순서).
        var between = try document([("그래서", 100, 400, "x"), (" 나중", 2_000, 2_100, "x"), (" 다음", 500, 700, "x")])
        between.turns = [between.turns[0], between.turns[2], between.turns[1]]
        XCTAssertEqual(try script(between).blocks().map(\.text), ["그래서", "다음", "나중"])
        var ordered = between; ordered.words[1].tokenKind = .punctuation; ordered.words[1].text = "…"
        // 대조: 사이가 부호면 이음 (뒤의 부호 Turn은 장식으로 같은 문단에 붙는다).
        XCTAssertEqual(try script(ordered).blocks().first.map { Array($0.turnIDs.prefix(2)) }, [between.turns[0].id, between.turns[1].id])
        // ④ 시간 없음: 다음 Turn의 첫 lexical에 시간이 없다 (Turn 시간은 뒤 단어에서).
        let timed = try document([("그래서", 100, 400, "x"), (" 다", 450, 480, "x"), ("음", 500, 700, "x")])
        var merged = timed
        let tail = TranscriptTurn(id: "t-tail", kind: .speech, startUs: 450_000, endUs: 700_000, speakerId: nil,
            wordIds: [timed.words[1].id, timed.words[2].id], markerText: nil, reviewed: false,
            reviewIssueIds: timed.turns[1].reviewIssueIds + timed.turns[2].reviewIssueIds)
        merged.turns = [timed.turns[0], tail]
        XCTAssertEqual(try script(merged).blocks().count, 1) // 대조: 시간 있으면 이음
        var untimed = merged
        untimed.words[1].startUs = nil; untimed.words[1].endUs = nil
        XCTAssertEqual(try script(untimed).blocks().count, 2)
        // ⑤ 수동 문단 나눔이 우선.
        var split = try script(document(base))
        let second = try XCTUnwrap(split.transcript.turns.last { $0.kind == .speech }).id
        try split.setParagraphBreak(before: second, split: true)
        XCTAssertEqual(split.blocks().count, 2)
        try split.setParagraphBreak(before: second, split: nil)
        XCTAssertEqual(split.blocks().count, 1)
        // ⑥ 사람 수정 Revision이면 자동 잇기를 하지 않는다 (현행 :40).
        var human = try document(base); human.revision.humanEdited = true
        XCTAssertEqual(try script(human).blocks().count, 2)
        // ⑦ 이름 붙인 미상 Turn은 이름이 다르면 잇지 않고, 같으면 잇는다.
        var named = try script(document(base))
        let ids = named.transcript.turns.filter { $0.kind == .speech }.map(\.id)
        named.turnNames = [ids[0]: "김가상"]
        XCTAssertEqual(named.blocks().count, 2)
        named.turnNames = [ids[0]: "김가상", ids[1]: "김가상"]
        XCTAssertEqual(named.blocks().count, 1)
    }

    /// reading-v8의 어절 안 미상 조각 잇기는 그대로다.
    func testSubwordJoinIsUnchanged() throws {
        XCTAssertEqual(try blocks([("그", 100, 200, "x"), ("래", 200, 300, "x")]).map(\.text), ["그래"])
    }
}

import Foundation
import XCTest
@testable import DamaCore

/// correction-turn-isolation: Turn 단위 검증 격리 · `rejectedTurns` 저장. 합성 문장만 쓰고 외부 호출은 없다.
final class CorrectionTurnIsolationTests: XCTestCase {
    static func fixtureScript() throws -> LibraryScript {
        var repo = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { repo.deleteLastPathComponent() }
        let model = try JSONDecoder().decode(TranscriptDocument.self, from: Data(contentsOf: repo.appendingPathComponent("fixtures/normalized-transcript.json")))
        return try LibraryScript(transcript: model, title: "합성", recordedAt: nil, dateSource: "합성", input: ConversionNotes(context: "합성 맥락", reference: ""))
    }
    static func legacyEdit(_ turnID: String, original: String) -> CorrectionEdit {
        CorrectionEdit(turnID: turnID, original: original, text: "합성 후보", reason: "합성 보류", applied: false)
    }
    private var sorted: JSONEncoder { let value = JSONEncoder(); value.outputFormatting = [.sortedKeys]; return value }

    // MARK: AC-05 저장 (D-02 · 스펙 §02-3)

    /// ⓐ nil이면 키가 없다 · ⓑ 현행 형태로 고정한 기존 기록은 해독·재인코딩 바이트가 같다.
    func testLegacyCorrectionBytesSurviveWithoutRejectedTurnsKey() throws {
        // usage-bundle2까지의 저장 형태(키 정렬, rejectedTurns 없음). 2026-11-07 고정.
        let literal = #"{"completedAt":800000100,"completedChunks":1,"edits":[{"applied":false,"original":"합성 원문","reason":"합성 보류","text":"합성 후보","turnID":"t1"}],"engine":"synthetic context-correction-6","id":"6F1C2E2A-0000-4000-8000-000000000001","input":{"context":"합성 맥락","reference":""},"nameEvidence":{"SPEAKER_00":"t1: 저는 김가상입니다"},"speakerNames":{"SPEAKER_00":"김가상"},"startedAt":800000000,"state":"completed","totalChunks":1}"#
        let decoded = try JSONDecoder().decode(ScriptCorrection.self, from: Data(literal.utf8))
        XCTAssertNil(decoded.rejectedTurns)
        XCTAssertEqual(String(decoding: try sorted.encode(decoded), as: UTF8.self), literal)

        var script = try Self.fixtureScript()
        var correction = ScriptCorrection(input: script.input, engine: "synthetic", state: .completed)
        correction.edits = [Self.legacyEdit("t1", original: script.text(for: script.transcript.turns[0]))]
        script.correction = correction
        let first = try sorted.encode(script)
        XCTAssertFalse(String(decoding: first, as: UTF8.self).contains("rejectedTurns"))
        XCTAssertEqual(try sorted.encode(JSONDecoder().decode(LibraryScript.self, from: first)), first)
        correction.rejectedTurns = [.init(turnID: "t3", rule: .quote)]
        script.correction = correction
        let withKey = String(decoding: try sorted.encode(script), as: UTF8.self)
        XCTAssertEqual(withKey.components(separatedBy: #""rejectedTurns""#).count - 1, 1)
        XCTAssertTrue(withKey.contains(#""rejectedTurns":[{"rule":"quote","turnID":"t3"}]"#))
    }

    /// ⓒ 저장 검증 위반 4종 → 손상. ⓔ AI 겹은 transcript를 바꾸지 않는다.
    func testRejectedTurnsStorageValidation() throws {
        let script = try Self.fixtureScript()
        XCTAssertEqual(script.transcript.turns.map(\.id), ["t1", "t-marker", "t2", "t3"])
        let transcriptBytes = try sorted.encode(script.transcript)
        func correction(_ rejected: [CorrectionRejectedTurn]) -> ScriptCorrection {
            var value = ScriptCorrection(input: script.input, engine: "synthetic", state: .completed)
            value.edits = [Self.legacyEdit("t1", original: script.text(for: script.transcript.turns[0]))]
            value.rejectedTurns = rejected
            return value
        }
        XCTAssertNoThrow(try correction([.init(turnID: "t3", rule: .quote), .init(turnID: "t2", rule: .other)]).validate(transcript: script.transcript))
        let invalid: [[CorrectionRejectedTurn]] = [
            [.init(turnID: "t-marker", rule: .quote)],                               // (1) 발화 밖 (missingSpeech)
            [.init(turnID: "t3", rule: .quote), .init(turnID: "t3", rule: .text)],  // (2) 중복
            [.init(turnID: "t1", rule: .limit)],                                     // (3) 편집 기록과 겹침
        ]
        for rejected in invalid {
            XCTAssertThrowsError(try correction(rejected).validate(transcript: script.transcript)) {
                XCTAssertEqual($0 as? LibraryFailure, .invalidScript)
            }
            var candidate = script; candidate.correction = correction(rejected)
            XCTAssertThrowsError(try candidate.validate())
        }
        // (4) 모르는 규칙 → 해독 실패.
        var stored = script; stored.correction = correction([.init(turnID: "t3", rule: .quote)])
        var json = try JSONSerialization.jsonObject(with: sorted.encode(stored)) as! [String: Any]
        var object = json["correction"] as! [String: Any]
        object["rejectedTurns"] = [["turnID": "t3", "rule": "bogus"]]
        json["correction"] = object
        XCTAssertThrowsError(try JSONDecoder().decode(LibraryScript.self, from: JSONSerialization.data(withJSONObject: json)))
        XCTAssertEqual(try sorted.encode(stored.transcript), transcriptBytes)
        XCTAssertEqual(CorrectionRejectionRule.allCases.map(\.rawValue), ["quote", "overlap", "text", "limit", "reason", "other"])
    }

    func testRejectedCountCountsOnlyListedTurns() throws {
        var correction = ScriptCorrection(input: ConversionNotes(), engine: "synthetic", state: .completed)
        XCTAssertEqual(correction.rejectedCount(in: ["t1", "t2"]), 0)
        correction.rejectedTurns = [.init(turnID: "t2", rule: .quote), .init(turnID: "t3", rule: .text)]
        XCTAssertEqual(correction.rejectedCount(in: ["t1", "t2"]), 1)
        XCTAssertEqual(correction.rejectedCount(in: ["t2", "t3", "t4"]), 2)
    }
}

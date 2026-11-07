import Foundation
import XCTest
@testable import DamaCore

/// usage-bundle1 AC-12: 의미 보호 context-correction-6. 합성 문장만 쓴다.
final class MeaningGuardTests: XCTestCase {
    /// 스펙 §02-4 표 11쌍 = `notes/usage-bundle1/measure-b1.py --selftest` 세트 (보류 7 · 통과 4).
    private let pairs: [(quote: String, replacement: String, classes: [MeaningClass]?)] = [
        ("삼십억", "30억", [.number]), ("1.5배", "15배", [.number]), ("30억원", "30억 달러", [.unit]), ("10%", "10퍼센트", [.unit]),
        ("안 됩니다", "됩니다", [.negation]), ("할 수 없다", "할 수 있다", [.negation]), ("하면 된다", "하고 된다", [.condition]),
        ("1 ,000억", "1,000억", nil), ("에스엠알", "SMR", nil), ("안 되니까", "안되니까", nil), ("측면", "측면에서", nil)]

    func testElevenPairsMatchPythonSelfTest() {
        var matched = 0
        for pair in pairs {
            // Python 판정과 같은 자: 형식 동등이 아니고 표식이 하나라도 다르면 보류.
            let format = ContextCorrection.canonicalFormat(pair.quote) == ContextCorrection.canonicalFormat(pair.replacement)
            let classes = format ? [] : MeaningGuard.changedClasses(quote: pair.quote, replacement: pair.replacement)
            XCTAssertEqual(classes, pair.classes ?? [], "\(pair.quote) → \(pair.replacement)")
            if classes.isEmpty == (pair.classes == nil) { matched += 1 }
        }
        XCTAssertEqual(matched, 11)
        XCTAssertEqual(pairs.filter { $0.classes != nil }.count, 7)
    }

    func testSignaturesFollowTheReferenceDefinitions() {
        XCTAssertEqual(MeaningGuard.numberSignature("1, 234.5억 원"), "1234.5억")
        XCTAssertEqual(MeaningGuard.numberSignature("v.2 . 끝."), "2")
        // Python isdigit과 같이 전각 숫자 사이의 점도 센다(전각 숫자 자체는 0–9 목록에 없음, QA C D-1).
        XCTAssertEqual(MeaningGuard.numberSignature("１.５배"), ".")
        XCTAssertEqual(MeaningGuard.numberSignature("１５배"), "")
        XCTAssertEqual(MeaningGuard.changedClasses(quote: "１.５배", replacement: "１５배"), [.number])
        XCTAssertEqual(MeaningGuard.unitSignature("30 KWh와 10kw 그리고 5"), ["kwh", "kw", ""])
        XCTAssertEqual(MeaningGuard.unitSignature("3개월 3개"), ["개월", "개"])
        XCTAssertEqual(MeaningGuard.negationSignature("안 하면 안돼, not now"), ["word-start-an": 2, "en:not": 1])
        XCTAssertEqual(MeaningGuard.negationSignature("편안하다"), [:]) // 낱말 안의 «안»은 세지 않는다.
        XCTAssertEqual(MeaningGuard.conditionSignature("If 3명 이상이면"), ["이상": 1, "면": 1, "en:if": 1])
        XCTAssertEqual(MeaningGuard.basis([.number, .unit]), "숫자·단위 표현이 바뀌는 수정이라 자동 반영하지 않았습니다. 원음으로 확인해 주세요.")
    }

    private func change(_ quote: String, _ replacement: String, certain: Bool = true, occurrence: Int = 0) -> CorrectionChange {
        CorrectionChange(quote: quote, occurrence: occurrence, replacement: replacement, certain: certain, reason: "합성", termID: nil)
    }
    private func source(_ text: String) -> CorrectionTurn { CorrectionTurn(id: "t1", speakerID: nil, startUs: 0, endUs: 1, text: text) }
    private func reply(_ source: String, _ changes: [CorrectionChange]) -> CorrectionReply.Turn {
        let text = CorrectionSpans.compose(source: source, changes: changes,
            ranges: try! CorrectionSpans.ranges(changes, source: source), accepted: changes.map { _ in true })
        return CorrectionReply.Turn(id: "t1", text: text, certain: true, reason: "", changes: changes, unresolved: [])
    }

    func testDecisionOrderUncertainFormatMeaningThenApply() throws {
        let text = "매출 30억원 계획 안 됩니다 에스엠알 1 ,000억"
        let changes = [change("30억원", "40억 달러"), change("안 됩니다", "됩니다", certain: false),
                       change("에스엠알", "SMR"), change("1 ,000억", "1,000억")]
        let edit = try XCTUnwrap(CorrectionSpans.validated(reply(text, changes), source: source(text), input: ConversionNotes()))
        let decisions = try XCTUnwrap(edit.changes)
        XCTAssertEqual(decisions.map(\.applied), [false, false, true, true])
        // ③ 의미 보호: 바뀐 분류를 «·»로 이은 근거 (문구 20).
        XCTAssertEqual(decisions[0].basis, "숫자·단위 표현이 바뀌는 수정이라 자동 반영하지 않았습니다. 원음으로 확인해 주세요.")
        // ① 불확실이 의미 보호보다 먼저.
        XCTAssertEqual(decisions[1].basis, "이 수정 범위가 불확실해 원문을 유지했습니다.")
        // ④ 표식 변화 없음 → 반영. ② 형식 동등 → 반영.
        XCTAssertEqual(decisions[2].basis, "AI가 확실한 문맥 교정으로 제안했고 원문 수정 위치를 확인했습니다.")
        XCTAssertEqual(decisions[3].basis, "원문 위치와 제한 형식 동등성을 확인했습니다.")
        XCTAssertEqual(edit.appliedText, "매출 30억원 계획 안 됩니다 SMR 1,000억")
        XCTAssertFalse(edit.applied)
        XCTAssertEqual(ContextCorrection.version, "context-correction-7")
    }

    /// «저장된 AI 교정 반영»(재검증)도 같은 규칙. 열기·조회만으로는 판정이 바뀌지 않는다.
    func testReapplicationHoldsMeaningChangesWithBasis() throws {
        var repo = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { repo.deleteLastPathComponent() }
        let model = try JSONDecoder().decode(TranscriptDocument.self, from: Data(contentsOf: repo.appendingPathComponent("fixtures/normalized-transcript.json")))
        var script = try LibraryScript(transcript: model, title: "합성", recordedAt: nil, dateSource: "합성", input: ConversionNotes())
        let sources = try ContextCorrection.chunks(script).flatMap(\.turns).prefix(2)
        XCTAssertEqual(sources.count, 2)
        // 이전 버전이 보류한 확실한 후보 2개: 첫째는 숫자를 새로 넣고(보류 유지), 둘째는 표식 변화가 없다(반영).
        let replacements = ["합성 교정 0", "합성 교정 나"]
        var old = ScriptCorrection(input: script.input, engine: "synthetic context-correction-5", state: .completed)
        old.edits = try sources.enumerated().map { index, source in
            let object: [String: Any] = ["turnID": source.id, "original": source.text, "text": replacements[index],
                "reason": "이전 보류", "applied": false, "appliedText": source.text, "unresolved": [],
                "changes": [["applied": false, "basis": "이전 보류", "change": [
                    "quote": source.text, "occurrence": 0, "replacement": replacements[index], "certain": true, "reason": "합성"]]]]
            return try JSONDecoder().decode(CorrectionEdit.self, from: JSONSerialization.data(withJSONObject: object))
        }
        script.correction = old
        let stored = try JSONEncoder().encode(script)
        _ = try JSONDecoder().decode(LibraryScript.self, from: stored).blocks() // 열기만으로는 판정이 바뀌지 않는다.
        XCTAssertEqual(try JSONDecoder().decode(LibraryScript.self, from: stored).correction?.edits.map(\.applied), [false, false])
        let result = try XCTUnwrap(ContextCorrection.reapplyingPending(in: script))
        // 보류가 유지된 수정은 재반영이 기존 기록을 그대로 둔다(현행: 바뀐 것만 새 판정으로 교체).
        XCTAssertEqual(result.edits[0].changes?.first?.applied, false)
        XCTAssertEqual(result.edits[0].changes?.first?.basis, "이전 보류")
        // 같은 후보를 재반영 경로와 같은 입력으로 다시 판정하면 의미 보호 근거가 붙는다.
        let first = try XCTUnwrap(sources.first)
        let recheck = try XCTUnwrap(CorrectionSpans.validated(
            CorrectionReply.Turn(id: first.id, text: replacements[0], certain: true, reason: "",
                                 changes: old.edits[0].changes?.map(\.change), unresolved: []),
            source: first, input: script.input))
        XCTAssertEqual(recheck.changes?.first?.applied, false)
        // 숫자가 새로 생기면 숫자 묶음 수도 달라져 단위 표식(묶음별 단위 목록)도 바뀐다 (measure-b1.py unit_sig와 같음).
        XCTAssertEqual(recheck.changes?.first?.basis, "숫자·단위 표현이 바뀌는 수정이라 자동 반영하지 않았습니다. 원음으로 확인해 주세요.")
        XCTAssertEqual(result.edits[1].changes?.first?.applied, true)
        XCTAssertTrue(result.engine.hasSuffix("저장 후보 반영 context-correction-7"))
    }
}

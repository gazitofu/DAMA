import Foundation
import XCTest
@testable import DamaCore

final class ContextCorrectionTests: XCTestCase {
    func testIndependentSpanCorrectionAndUnresolvedRoundTripJourney() throws {
        var script = try makeScript(["원자로 에스엠알 30억원 추정", "다음 발화"])
        let input = ConversionNotes(context: "원자로 검토", reference: "용어 | 원자로 | 에스엠알 | SMR")
        let term = try XCTUnwrap(CorrectionTerms.entries(input: input).first)
        let chunk = try XCTUnwrap(ContextCorrection.chunks(script).first), source = chunk.turns[0]
        let changes: [CorrectionChange] = [
            .init(quote: "에스엠알", occurrence: 0, replacement: "SMR", certain: true, reason: "명시적 대응", termID: term.id),
            .init(quote: "30억원", occurrence: 0, replacement: "30억 원", certain: true, reason: "단위 공백", termID: nil),
            .init(quote: "추정", occurrence: 0, replacement: "확정", certain: true, reason: "모델 주장", termID: nil)]
        let unresolved = [CorrectionUnresolved(quote: "추정", occurrence: 0, reason: "원음 확인")]
        let reply = CorrectionReply(turns: [
            .init(id: source.id, text: "원자로 SMR 30억 원 확정", certain: false, reason: "주장 확인",
                  changes: changes, unresolved: unresolved),
            .init(id: chunk.turns[1].id, text: chunk.turns[1].text, certain: true, reason: "", changes: [], unresolved: [])], names: [])
        let result = try ContextCorrection.validated(reply, chunk: chunk, input: input)
        let edit = try XCTUnwrap(result.edits.first)
        XCTAssertEqual(edit.changes?.map(\.applied), [true, true, false]); XCTAssertFalse(edit.applied)
        XCTAssertEqual(edit.appliedText, "원자로 SMR 30억 원 추정")
        XCTAssertEqual(edit.unresolved, unresolved)
        var correction = ScriptCorrection(input: input, engine: ContextCorrection.version, state: .completed)
        correction.edits = result.edits; script.correction = correction
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let normalized = try encoder.encode(script.transcript)
        var loaded = try JSONDecoder().decode(LibraryScript.self, from: encoder.encode(script)); try loaded.validate()
        XCTAssertEqual(loaded.text(for: loaded.transcript.turns[0]), edit.appliedText)
        XCTAssertTrue(loaded.blocks()[0].text.contains("원자로 SMR 30억 원 추정"))
        let md = String(decoding: try loaded.markdown(), as: UTF8.self)
        XCTAssertTrue(md.contains("수정 반영: 에스엠알 → SMR")); XCTAssertTrue(md.contains("미해결: 추정"))
        XCTAssertTrue(md.contains(term.id)); XCTAssertTrue(md.contains("일부 반영"))
        loaded.showsOriginal = true
        XCTAssertEqual(loaded.text(for: loaded.transcript.turns[0]), source.text)
        loaded.showsOriginal = false
        try loaded.editText(source.id, text: "  사람이 수정한 원자로  ")
        XCTAssertEqual(loaded.text(for: loaded.transcript.turns[0]), "  사람이 수정한 원자로  ")
        XCTAssertEqual(try encoder.encode(loaded.transcript), normalized)
    }

    func testSpanAnchorsRejectFabricationOverlapAndUnexplainedChanges() throws {
        let source = CorrectionTurn(id: "t", speakerID: nil, startUs: 850_000, endUs: 850_000, text: "🙂 30억원 30억원")
        let chunk = CorrectionChunk(turns: [source], contextBefore: [], contextAfter: [])
        func change(_ quote: String = "30억원", _ occurrence: Int = 1) -> CorrectionChange {
            .init(quote: quote, occurrence: occurrence, replacement: "30억 원", certain: true, reason: "공백", termID: nil)
        }
        func check(_ changes: [CorrectionChange], _ text: String) throws -> CorrectionEdit? {
            try ContextCorrection.validated(.init(turns: [.init(id: "t", text: text, certain: true, reason: "", changes: changes, unresolved: [])], names: []), chunk: chunk, input: ConversionNotes()).edits.first
        }
        XCTAssertEqual(try check([change()], "🙂 30억원 30억 원")?.effectiveText, "🙂 30억원 30억 원")
        for changes in [[change("없음")], [change("30억원", -1)], [change("30억원", 2)],
                        [change(), change()], [change("30억원 30억원", 0), change()]] {
            XCTAssertThrowsError(try check(changes, "🙂 30억원 30억 원"))
        }
        XCTAssertThrowsError(try check([change()], "🙂 30억원 30억 원."))
        var edit = try XCTUnwrap(check([change()], "🙂 30억원 30억 원"))
        edit.appliedText = "🙂 50억원"
        XCTAssertThrowsError(try CorrectionSpans.validateStored(edit))
        XCTAssertEqual(source.startUs, 850_000); XCTAssertEqual(source.endUs, 850_000)
    }

    func testTermEvidenceRequiresExplicitMappingScopeAndExactSource() throws {
        let input = ConversionNotes(context: "원자로 검토", reference: "용어 | 원자로 | 에스엠알 | SMR")
        let term = try XCTUnwrap(CorrectionTerms.entries(input: input).first)
        func apply(_ before: String, _ after: String, _ id: String?, _ notes: ConversionNotes = input,
                   unresolved: [CorrectionUnresolved] = []) throws -> Bool {
            let chunk = CorrectionChunk(turns: [.init(id: "t", speakerID: nil, startUs: 0, endUs: 1, text: before)], contextBefore: [], contextAfter: [])
            let changes = [CorrectionChange(quote: "에스엠알", occurrence: 0, replacement: "SMR", certain: true, reason: "확실함", termID: id)]
            return try ContextCorrection.validated(.init(turns: [.init(id: "t", text: after, certain: true, reason: "", changes: changes, unresolved: unresolved)], names: []), chunk: chunk, input: notes).edits.first?.changes?.first?.applied == true
        }
        XCTAssertTrue(try apply("원자로 에스엠알", "원자로 SMR", term.id))
        XCTAssertFalse(try apply("원자로 에스엠알", "원자로 SMR", nil))
        XCTAssertFalse(try apply("원자로 에스엠알", "원자로 SMR", "invented"))
        XCTAssertFalse(try apply("다른주제 에스엠알", "다른주제 SMR", term.id))
        XCTAssertFalse(try apply("원자로 에스엠알파", "원자로 SMR파", term.id))
        XCTAssertFalse(try apply("원자로 에스엠알", "원자로 SMR", term.id, unresolved: [.init(quote: "에스엠알", occurrence: 0, reason: "용어 불확실")]))
        XCTAssertFalse(try apply("원자로 에스엠알", "원자로 SMR", term.id, ConversionNotes(context: input.context, reference: input.reference + "\n변경된 입력")))
        XCTAssertTrue(CorrectionTerms.entries(input: ConversionNotes(context: "다른 주제", reference: input.reference)).isEmpty)
        XCTAssertTrue(CorrectionTerms.entries(input: ConversionNotes(context: input.context, reference: input.reference + "\n용어 | 원자로 | 에스엠알 | SMX")).isEmpty)
        XCTAssertTrue(CorrectionTerms.entries(input: ConversionNotes(context: input.context, referenceExcerpts: [.init(name: "terms.md", sha256: "hash", text: input.reference)])).isEmpty)
        for (from, to) in [("30억", "50억"), ("kW", "kWh"), ("있다", "없다")] {
            XCTAssertTrue(CorrectionTerms.entries(input: ConversionNotes(context: "원자로", reference: "용어 | 원자로 | \(from) | \(to)")).isEmpty)
        }
    }

    func testIndependentUncertaintyCannotDisappearThroughNoOpOrEmptyDetails() throws {
        let chunk = CorrectionChunk(turns: [.init(id: "t", speakerID: nil, startUs: nil, endUs: nil, text: "30억원 추정")], contextBefore: [], contextAfter: [])
        let reply = CorrectionReply(turns: [.init(id: "t", text: "30억원 추정", certain: false, reason: "전체 불확실", changes: [], unresolved: [])], names: [])
        let edit = try XCTUnwrap(ContextCorrection.validated(reply, chunk: chunk, input: ConversionNotes()).edits.first)
        XCTAssertFalse(edit.applied); XCTAssertEqual(edit.unresolved?.first?.quote, chunk.turns[0].text)
        let partial = CorrectionReply(turns: [.init(id: "t", text: "30억원 추정", certain: false, reason: "", changes: [], unresolved: nil)], names: [])
        XCTAssertThrowsError(try ContextCorrection.validated(partial, chunk: chunk, input: ConversionNotes()))
        let schema = try JSONSerialization.jsonObject(with: ContextCorrection.outputSchema) as! [String: Any]
        let properties = schema["properties"] as! [String: Any]
        let turns = properties["turns"] as! [String: Any], items = turns["items"] as! [String: Any]
        XCTAssertTrue((items["required"] as! [String]).contains("changes")); XCTAssertTrue((items["required"] as! [String]).contains("unresolved"))
    }

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
        var script = try makeScript(["예시 회사를 논의합니다", "매출은 30억원이 아닙니다", "확인 필요", "예산은 30억원입니다"])
        let original = try JSONEncoder().encode(script.transcript)
        let chunk = try XCTUnwrap(ContextCorrection.chunks(script).first)
        let response = CorrectionReply(turns: [
            .init(id: chunk.turns[0].id, text: "예시회사를 논의합니다.", certain: true, reason: "회사명 표기"),
            .init(id: chunk.turns[1].id, text: "매출은 50억원입니다", certain: true, reason: "참고 문서"),
            .init(id: chunk.turns[2].id, text: "확인 필요", certain: false, reason: "원음 확인"),
            .init(id: chunk.turns[3].id, text: "예산은 30억 원입니다", certain: true, reason: "단위 띄어쓰기")], names: [])
        let result = try ContextCorrection.validated(response, chunk: chunk, input: script.input)
        // Previously accepted company/period inference is now a candidate; explicit format stays automatic.
        XCTAssertEqual(result.edits.map(\.applied), [false, false, false, true])
        var correction = ScriptCorrection(input: script.input, engine: "synthetic", state: .completed)
        correction.edits = result.edits; script.correction = correction
        XCTAssertEqual(script.text(for: script.transcript.turns[0]), "예시 회사를 논의합니다")
        XCTAssertTrue(script.blocks()[0].text.contains("예시 회사를"))
        XCTAssertEqual(script.text(for: script.transcript.turns[3]), "예산은 30억 원입니다")
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
    func testFormattingAllowlistRejectsConsequentialChangesEvenWithModelCertainty() throws {
        let rejected: [(String, String)] = [
            ("-3", "3"), ("3 kW", "3 kWh"), ("3억 이상", "3억 이하"),
            ("3억에서 5억", "3억과 5억"), ("안되니까", "되니까"),
            ("투자하면", "투자하고"), ("가능할 것 같다", "가능하다"), ("네네네네", "네"),
            ("30억", "3억"), ("없다", "있다"), ("가나다", "XYZ"),
            ("검토 대상", "검토대상입니다"), ("64억 70억", "64억, 70억"),
            ("맞아요?", "맞아요."), ("3 ,40억", "3,40억"), ("1 ,0000억", "1,0000억"),
            ("1,000억", "1000억"), ("안해도 되거든 걸린건", "안 해도 되거든. 걸린 건"),
            ("안되니까 30억", "안 되니까 3억"), ("아버지가방", "아버지가 방"),
            ("안되니까", ""), ("안되니까", "   ")
        ]
        let allowed: [(String, String)] = [
            ("1 ,000억", "1,000억"), ("안되니까.", "안 되니까."),
            ("안되는데", "안 되는데"), ("안해도", "안 해도"),
            ("30억원", "30억 원"), ("-1 ,000억원", "-1,000억 원")
        ]
        for (cases, expected) in [(rejected, false), (allowed, true)] {
            for (before, after) in cases {
                let chunk = CorrectionChunk(turns: [.init(id: "t", speakerID: nil, startUs: 0, endUs: 850_000, text: before)],
                                            contextBefore: [], contextAfter: [])
                let reply = CorrectionReply(turns: [.init(id: "t", text: after, certain: true, reason: "확실함 · 참고 근거")], names: [])
                let result = try ContextCorrection.validated(reply, chunk: chunk, input: ConversionNotes(reference: after))
                let edit = try XCTUnwrap(result.edits.first, before)
                XCTAssertEqual(edit.applied, expected, "\(before) → \(after)")
                XCTAssertEqual(edit.text, after)
                XCTAssertEqual(chunk.turns[0].endUs, 850_000)
            }
        }
    }
    func testWhitespaceHistorySuppressionPreservesUncertaintyLegacyDataAndSourceIssues() throws {
        var script = try makeScript(["  확인  ", "  불확실  "])
        let first = script.transcript.turns[0]
        var model = script.transcript
        model.reviewIssues.append(ReviewIssue(id: "i-test", kind: .invalid_timestamp,
            startUs: first.startUs, endUs: first.endUs, severity: .warning, status: .open,
            wordIds: first.wordIds, sourceIntervalIds: []))
        script = try LibraryScript(transcript: model, title: script.title, recordedAt: nil, dateSource: "합성", input: script.input)
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let original = try encoder.encode(script.transcript)
        let chunk = try XCTUnwrap(ContextCorrection.chunks(script).first)
        let reply = CorrectionReply(turns: [
            .init(id: first.id, text: "확인", certain: true, reason: "공백"),
            .init(id: chunk.turns[1].id, text: "불확실", certain: false, reason: "원음 확인")], names: [])
        let result = try ContextCorrection.validated(reply, chunk: chunk, input: script.input)
        XCTAssertEqual(result.edits.count, 1)
        XCTAssertFalse(result.edits[0].applied)
        XCTAssertEqual(result.edits[0].text, chunk.turns[1].text)
        var correction = ScriptCorrection(input: script.input, engine: "legacy", state: .completed)
        correction.edits = [.init(turnID: first.id, original: chunk.turns[0].text, text: "확인", reason: "공백", applied: true)] + result.edits
        script.correction = correction
        let loaded = try JSONDecoder().decode(LibraryScript.self, from: encoder.encode(script))
        XCTAssertEqual(loaded.correction?.edits.count, 2) // Old stored entries aren't erased.
        XCTAssertEqual(loaded.correction?.visibleEdits.count, 1)
        XCTAssertEqual(loaded.blocks()[0].text, "확인")
        XCTAssertEqual(loaded.blocks().flatMap(\.openIssues).map(\.id), ["i-test"])
        XCTAssertEqual(try encoder.encode(loaded.transcript), original)
        let md = String(decoding: try loaded.markdown(), as: UTF8.self)
        XCTAssertFalse(md.contains("> AI 교정: 공백"))
        XCTAssertTrue(md.contains("원음 확인"))
        XCTAssertTrue(md.contains("invalid\\_timestamp"))
        script.showsOriginal = true
        XCTAssertEqual(script.blocks()[0].text, "확인")
        XCTAssertEqual(script.originalText(for: first), "  확인  ")
        try script.editText(first.id, text: "  사람이 남긴 공백  ")
        XCTAssertEqual(script.blocks()[0].text, "  사람이 남긴 공백  ")
        model.words[0].editedText = "  예전 검수에서 남긴 공백  "
        model.words[0].timingOrigin = .inheritedUnaligned
        let legacy = try LibraryScript(transcript: model, title: "이전 검수", recordedAt: nil, dateSource: "합성", input: script.input)
        XCTAssertEqual(legacy.blocks()[0].text, "  예전 검수에서 남긴 공백  ")
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

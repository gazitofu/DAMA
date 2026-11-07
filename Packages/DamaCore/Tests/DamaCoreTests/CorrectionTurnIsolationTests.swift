import CryptoKit
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

    // MARK: AC-02 Turn 격리 · AC-03 청크 실패 유지 (스펙 §02-1 · §02-2)

    static let turnA = CorrectionTurn(id: "a", speakerID: "SPEAKER_00", startUs: 0, endUs: 1_000_000, text: "디마 앱 검토")
    static let turnB = CorrectionTurn(id: "b", speakerID: "SPEAKER_01", startUs: 1_000_000, endUs: 2_000_000, text: "저는 김가상입니다")
    static let names = [CorrectionReply.Name(speakerID: "SPEAKER_01", name: "김가상", evidenceTurnID: "b", quote: "저는 김가상입니다")]
    static let input = ConversionNotes(participants: "김가상 · 개발")
    static func change(_ quote: String, _ replacement: String) -> CorrectionChange {
        CorrectionChange(quote: quote, occurrence: 0, replacement: replacement, certain: true, reason: "합성", termID: nil)
    }
    static func reply(_ id: String, _ text: String, certain: Bool = true, changes: [CorrectionChange]? = [],
                      unresolved: [CorrectionUnresolved]? = []) -> CorrectionReply.Turn {
        CorrectionReply.Turn(id: id, text: text, certain: certain, reason: certain ? "" : "합성 불확실", changes: changes, unresolved: unresolved)
    }
    /// A = 확실한 수정 1개(반영) · B = 수정 없음(자기소개 이름 근거) · C = 사례별.
    static func validate(c source: String, _ candidate: CorrectionReply.Turn, a: CorrectionReply.Turn? = nil, b: CorrectionReply.Turn? = nil) throws
        -> (edits: [CorrectionEdit], names: [String: String], evidence: [String: String], rejected: [CorrectionRejectedTurn]) {
        let c = CorrectionTurn(id: "c", speakerID: "SPEAKER_00", startUs: 2_000_000, endUs: 3_000_000, text: source)
        let chunk = CorrectionChunk(turns: [turnA, turnB, c], contextBefore: [], contextAfter: [])
        let replyA = a ?? reply("a", "DAMA 앱 검토", changes: [change("디마", "DAMA")])
        return try ContextCorrection.validated(.init(turns: [replyA, b ?? reply("b", turnB.text), candidate], names: names), chunk: chunk, input: input)
    }

    func testOneFailingTurnIsKeptAsOriginalWhileOthersAreJudged() throws {
        let base = "가나다 라마바"
        let cases: [(String, String, CorrectionReply.Turn, [CorrectionRejectedTurn])] = [
            ("limit", base, Self.reply("c", String(repeating: "가", count: 257)), [.init(turnID: "c", rule: .limit)]),
            ("quote", base, Self.reply("c", "가나다 라마사", changes: [Self.change("없는말", "라마사")]), [.init(turnID: "c", rule: .quote)]),
            ("overlap", base, Self.reply("c", base, changes: [Self.change("가나다 라", "X"), Self.change("라마바", "Y")]), [.init(turnID: "c", rule: .overlap)]),
            ("text", base, Self.reply("c", base, changes: [Self.change("라마바", "라마사")]), [.init(turnID: "c", rule: .text)]),
            ("reason", base, Self.reply("c", base, unresolved: [.init(quote: "라마바", occurrence: 0, reason: "  ")]), [.init(turnID: "c", rule: .reason)]),
            ("other", "", Self.reply("c", "", certain: false), [.init(turnID: "c", rule: .other)]),
            ("none", base, Self.reply("c", base), []),
        ]
        let expectedA = try XCTUnwrap(CorrectionSpans.validated(Self.reply("a", "DAMA 앱 검토", changes: [Self.change("디마", "DAMA")]),
                                                               source: Self.turnA, input: Self.input))
        XCTAssertTrue(expectedA.applied)
        let reference = try Self.validate(c: base, Self.reply("c", base))
        XCTAssertEqual(reference.names, ["SPEAKER_01": "김가상"])
        for (label, source, candidate, rejected) in cases {
            // 사례마다 따로 판정한다(한 사례의 throw가 나머지 사례를 가리지 않게).
            let result: (edits: [CorrectionEdit], names: [String: String], evidence: [String: String], rejected: [CorrectionRejectedTurn])
            do { result = try Self.validate(c: source, candidate) } catch { XCTFail("\(label): \(error)"); continue }
            XCTAssertEqual(result.rejected, rejected, label)
            XCTAssertEqual(result.edits, [expectedA], label)   // B·C 편집 없음, A는 단독 판정과 같다.
            XCTAssertEqual(result.names, reference.names, label)
            XCTAssertEqual(result.evidence, reference.evidence, label)
        }
    }

    func testFirstFailingRuleWinsAndAllFailingChunkStillSucceeds() throws {
        let base = "가나다 라마바"
        // 길이 상한이 인용 검사보다 먼저.
        XCTAssertEqual(try Self.validate(c: base, Self.reply("c", String(repeating: "가", count: 257), changes: [Self.change("없는말", "라마사")])).rejected,
                       [.init(turnID: "c", rule: .limit)])
        // 미해결 이유가 미해결 인용보다 먼저.
        XCTAssertEqual(try Self.validate(c: base, Self.reply("c", base, unresolved: [.init(quote: "없는말", occurrence: 0, reason: "  ")])).rejected,
                       [.init(turnID: "c", rule: .reason)])
        // 청크 안 Turn이 전부 실패해도 청크는 성공이다. 이름 검증은 원문 Turn으로 따로 한다.
        let all: (edits: [CorrectionEdit], names: [String: String], evidence: [String: String], rejected: [CorrectionRejectedTurn])
        do {
            all = try Self.validate(c: base, Self.reply("c", base, changes: [Self.change("없는말", "X")]),
                                    a: Self.reply("a", "X", changes: [Self.change("없는말", "X")]),
                                    b: Self.reply("b", "X", changes: [Self.change("없는말", "X")]))
        } catch { return XCTFail("all failing: \(error)") }
        XCTAssertEqual(all.rejected, ["a", "b", "c"].map { CorrectionRejectedTurn(turnID: $0, rule: .quote) })
        XCTAssertTrue(all.edits.isEmpty)
        XCTAssertEqual(all.names, ["SPEAKER_01": "김가상"])
    }

    /// ContextCorrectionTests.testSpanAnchors…의 이동 6사례가 편집 기록을 만들지 않는다(이동 단정과 분리한 신규 단정, QA A D-1).
    func testMovedGuardCasesLeaveNoEdit() throws {
        let source = CorrectionTurn(id: "t", speakerID: nil, startUs: 850_000, endUs: 850_000, text: "🙂 30억원 30억원")
        let chunk = CorrectionChunk(turns: [source], contextBefore: [], contextAfter: [])
        func change(_ quote: String = "30억원", _ occurrence: Int = 1) -> CorrectionChange {
            .init(quote: quote, occurrence: occurrence, replacement: "30억 원", certain: true, reason: "공백", termID: nil)
        }
        let cases: [([CorrectionChange], String)] = [
            ([change("없음")], "🙂 30억원 30억 원"), ([change("30억원", -1)], "🙂 30억원 30억 원"), ([change("30억원", 2)], "🙂 30억원 30억 원"),
            ([change(), change()], "🙂 30억원 30억 원"), ([change("30억원 30억원", 0), change()], "🙂 30억원 30억 원"), ([change()], "🙂 30억원 30억 원."),
        ]
        for (index, (changes, text)) in cases.enumerated() {
            let reply = CorrectionReply(turns: [.init(id: "t", text: text, certain: true, reason: "", changes: changes, unresolved: [])], names: [])
            do { XCTAssertTrue(try ContextCorrection.validated(reply, chunk: chunk, input: ConversionNotes()).edits.isEmpty, "case \(index)") }
            catch { XCTFail("case \(index): \(error)") }
        }
    }

    func testUnpairableReplyRemainsChunkFailure() throws {
        let base = "가나다 라마바"
        let c = CorrectionTurn(id: "c", speakerID: "SPEAKER_00", startUs: 2_000_000, endUs: 3_000_000, text: base)
        let chunk = CorrectionChunk(turns: [Self.turnA, Self.turnB, c], contextBefore: [], contextAfter: [])
        let a = Self.reply("a", Self.turnA.text), b = Self.reply("b", Self.turnB.text), ok = Self.reply("c", base)
        let replies: [[CorrectionReply.Turn]] = [
            [b, a, ok],                                                     // id 순서 뒤바뀜
            [a, b],                                                         // id 1개 빠짐
            [a, b, Self.reply("c", base, unresolved: nil)],                 // 필수 배열 하나 누락
            [Self.reply("a", "X", changes: [Self.change("없는말", "X")]), b, Self.reply("c", base, unresolved: nil)], // 누락이 Turn 실패보다 먼저
        ]
        for turns in replies {
            XCTAssertThrowsError(try ContextCorrection.validated(.init(turns: turns, names: []), chunk: chunk, input: Self.input)) {
                XCTAssertEqual($0 as? LibraryFailure, .invalidScript)
            }
        }
    }

    // MARK: AC-07 재반영 · 오류 형식 (스펙 §02-3)

    /// MeaningGuardTests.testReapplicationHoldsMeaningChangesWithBasis와 같은 구성 + 버린 Turn 1개.
    func testReapplicationCarriesRejectedTurnsUnchanged() throws {
        var script = try Self.fixtureScript()
        let sources = try ContextCorrection.chunks(script).flatMap(\.turns).prefix(2)
        XCTAssertEqual(sources.map(\.id), ["t1", "t2"])
        let replacements = ["합성 교정 0", "합성 교정 나"]
        var old = ScriptCorrection(input: script.input, engine: "synthetic context-correction-6", state: .completed)
        old.edits = try sources.enumerated().map { index, source in
            let object: [String: Any] = ["turnID": source.id, "original": source.text, "text": replacements[index],
                "reason": "이전 보류", "applied": false, "appliedText": source.text, "unresolved": [],
                "changes": [["applied": false, "basis": "이전 보류", "change": [
                    "quote": source.text, "occurrence": 0, "replacement": replacements[index], "certain": true, "reason": "합성"]]]]
            return try JSONDecoder().decode(CorrectionEdit.self, from: JSONSerialization.data(withJSONObject: object))
        }
        old.rejectedTurns = [.init(turnID: "t3", rule: .quote)]
        script.correction = old
        let result = try XCTUnwrap(ContextCorrection.reapplyingPending(in: script))
        XCTAssertEqual(result.rejectedTurns, [.init(turnID: "t3", rule: .quote)])
        XCTAssertEqual(result.edits[0].changes?.first?.applied, false)   // 숫자 보호로 보류 유지(현행).
        XCTAssertEqual(result.edits[1].changes?.first?.applied, true)    // 표식 변화 없음 → 반영(현행).
        XCTAssertTrue(result.engine.hasSuffix("저장 후보 반영 context-correction-7"))
        XCTAssertNoThrow(try result.validate(transcript: script.transcript))
        // 바뀔 후보가 없으면 새 결과를 만들지 않는다(현행).
        var nothing = ScriptCorrection(input: script.input, engine: "synthetic", state: .completed)
        nothing.rejectedTurns = [.init(turnID: "t3", rule: .quote)]
        script.correction = nothing
        XCTAssertNil(try ContextCorrection.reapplyingPending(in: script))
    }

    /// 저장 검증·재반영이 밖으로 내는 오류는 현행 `LibraryFailure.invalidScript`뿐이다(내부 규칙 오류 형식이 새지 않는다).
    func testStoredValidationAndReapplicationKeepLibraryFailureForm() throws {
        let source = CorrectionTurn(id: "t", speakerID: nil, startUs: 0, endUs: 1, text: "🙂 30억원 30억원")
        let chunk = CorrectionChunk(turns: [source], contextBefore: [], contextAfter: [])
        let change = CorrectionChange(quote: "30억원", occurrence: 1, replacement: "30억 원", certain: true, reason: "공백", termID: nil)
        var edit = try XCTUnwrap(ContextCorrection.validated(.init(turns: [.init(id: "t", text: "🙂 30억원 30억 원", certain: true, reason: "",
            changes: [change], unresolved: [])], names: []), chunk: chunk, input: ConversionNotes()).edits.first)
        edit.appliedText = "🙂 50억원"                                          // ContextCorrectionTests:76 같은 변조
        XCTAssertThrowsError(try CorrectionSpans.validateStored(edit)) { XCTAssertEqual($0 as? LibraryFailure, .invalidScript) }
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(XCTUnwrap(ContextCorrection.validated(.init(turns: [.init(id: "t",
            text: "🙂 30억원 30억 원", certain: true, reason: "", changes: [change], unresolved: [])], names: []), chunk: chunk, input: ConversionNotes()).edits.first))) as! [String: Any]
        var decisions = json["changes"] as! [[String: Any]]
        var tampered = decisions[0]["change"] as! [String: Any]
        tampered["quote"] = "없는말"                                            // 인용 변조 → 내부에서는 quote 규칙
        decisions[0]["change"] = tampered; json["changes"] = decisions
        let quoteTampered = try JSONDecoder().decode(CorrectionEdit.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertThrowsError(try CorrectionSpans.validateStored(quoteTampered)) { XCTAssertEqual($0 as? LibraryFailure, .invalidScript) }
        // 재반영도 같은 형식: 변조된 저장 후보가 있는 스크립트.
        var script = try Self.fixtureScript()
        let first = try XCTUnwrap(ContextCorrection.chunks(script).flatMap(\.turns).first)
        let object: [String: Any] = ["turnID": first.id, "original": first.text, "text": "합성 교정 나", "reason": "이전 보류",
            "applied": false, "appliedText": first.text, "unresolved": [],
            "changes": [["applied": false, "basis": "이전 보류", "change": [
                "quote": "없는말", "occurrence": 0, "replacement": "합성 교정 나", "certain": true, "reason": "합성"]]]]
        var old = ScriptCorrection(input: script.input, engine: "synthetic", state: .completed)
        old.edits = [try JSONDecoder().decode(CorrectionEdit.self, from: JSONSerialization.data(withJSONObject: object))]
        script.correction = old
        XCTAssertThrowsError(try ContextCorrection.reapplyingPending(in: script)) { XCTAssertEqual($0 as? LibraryFailure, .invalidScript) }
    }

    // MARK: AC-08 문구·Markdown (스펙 §03 · §04 문구표)

    /// 기대 문자열은 `ssot/tone/correction-turn-isolation.md` 표에서 옮겼다(코드와 독립).
    func testRejectionTextMatchesToneTable() {
        let note = "AI 응답이 이 문단의 원문과 맞지 않아 쓰지 않았습니다."
        let current = "AI 보정 결과를 저장했습니다. 다른 결과 보기에서 이전 버전을 확인할 수 있습니다." // App/CorrectionWorkspace.swift:151 @7b59b85
        XCTAssertEqual(CorrectionRejectionText.inspectorTitle, "원문 유지 · AI 응답 검증 실패")
        XCTAssertEqual(CorrectionRejectionText.paragraphNote(count: 1), note)
        XCTAssertEqual(CorrectionRejectionText.paragraphNote(count: 2), note + " (2개 원구간)")
        XCTAssertEqual(CorrectionRejectionText.paragraphNote(count: 3), note + " (3개 원구간)")
        XCTAssertEqual(Data(CorrectionRejectionText.completionMessage(rejectedCount: 0).utf8), Data(current.utf8))
        XCTAssertEqual(CorrectionRejectionText.completionMessage(rejectedCount: 1), current + " AI 응답이 원문과 맞지 않은 1개 원구간은 원문을 유지했습니다.")
        XCTAssertEqual(CorrectionRejectionText.completionMessage(rejectedCount: 12), current + " AI 응답이 원문과 맞지 않은 12개 원구간은 원문을 유지했습니다.")
        XCTAssertEqual(CorrectionRejectionText.markdownSummary(count: 1), "- 검증 실패로 원문 유지: 1개 원구간")
        XCTAssertEqual(CorrectionRejectionText.markdownSummary(count: 12), "- 검증 실패로 원문 유지: 12개 원구간")
        XCTAssertEqual(CorrectionRejectionText.markdownPrefix, "> AI 검증 실패: ")
    }

    /// 시각·revision을 고정한 합성 스크립트(fixture 문단 = [t1, t2] · [t3]).
    static func markdownScript(editT1: Bool = true, rejected: [CorrectionRejectedTurn]?) throws -> LibraryScript {
        var repo = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { repo.deleteLastPathComponent() }
        let model = try JSONDecoder().decode(TranscriptDocument.self, from: Data(contentsOf: repo.appendingPathComponent("fixtures/normalized-transcript.json")))
        var script = try LibraryScript(transcript: model, title: "합성", recordedAt: nil, dateSource: "합성", timeZoneID: "Asia/Seoul",
                                       input: ConversionNotes(context: "합성 맥락", reference: ""), createdAt: Date(timeIntervalSinceReferenceDate: 800_000_000))
        script.revisionID = "00000000-0000-4000-8000-000000000001"
        var correction = ScriptCorrection(input: script.input, engine: "synthetic", state: .completed)
        correction.id = "00000000-0000-4000-8000-000000000002"
        if editT1 { correction.edits = [legacyEdit("t1", original: script.text(for: script.transcript.turns[0]))] }
        correction.rejectedTurns = rejected
        script.correction = correction
        return script
    }
    static func sha(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    func testMarkdownAddsLinesOnlyForRejectedTurns() throws {
        let baselineSHA = "5dc04eb6a97e4749f81224038cfd1742d9e86cab9783897a77f60ec0173e1e8d" // T-06 착수 전 현행 코드 실측 (HEAD 6267108, 1,564 B)
        let none = try Self.markdownScript(rejected: nil).markdown()
        XCTAssertEqual(none.count, 1_564)
        XCTAssertEqual(Self.sha(none), baselineSHA)
        XCTAssertEqual(try Self.markdownScript(rejected: []).markdown(), none)

        let note = "> AI 검증 실패: AI 응답이 이 문단의 원문과 맞지 않아 쓰지 않았습니다."
        let summary = "- 검증 실패로 원문 유지: 1개 원구간"
        // t3 문단 1개: 머리 줄 1 · t3 문단 줄 1 · 다른 문단 0. 두 줄(+빈 줄)을 빼면 기준선과 바이트가 같다.
        let lines = String(decoding: try Self.markdownScript(rejected: [.init(turnID: "t3", rule: .quote)]).markdown(), as: UTF8.self)
            .components(separatedBy: "\n")
        XCTAssertEqual(lines.filter { $0 == summary }.count, 1)
        XCTAssertEqual(lines.filter { $0.hasPrefix("> AI 검증 실패: ") }, [note])
        let summaryAt = try XCTUnwrap(lines.firstIndex(of: summary))
        XCTAssertTrue(lines[summaryAt - 1].hasPrefix("- 원문·시간·화자 경계 보존."))
        let noteAt = try XCTUnwrap(lines.firstIndex(of: note))
        let headers = lines.indices.filter { lines[$0].hasPrefix("### [") }
        XCTAssertEqual(headers.count, 2)
        XCTAssertGreaterThan(noteAt, headers[1])                                   // t3 문단 안
        XCTAssertEqual(lines[noteAt + 1], "")
        var stripped = lines; stripped.remove(at: noteAt + 1); stripped.remove(at: noteAt); stripped.remove(at: summaryAt)
        XCTAssertEqual(Self.sha(Data(stripped.joined(separator: "\n").utf8)), baselineSHA)

        // 같은 문단의 AI 교정 줄 다음에 붙는다(t1 편집 · t2 버림).
        let mixed = String(decoding: try Self.markdownScript(rejected: [.init(turnID: "t2", rule: .text)]).markdown(), as: UTF8.self)
            .components(separatedBy: "\n")
        let mixedNote = try XCTUnwrap(mixed.firstIndex(of: note))
        let candidate = try XCTUnwrap(mixed.firstIndex(of: "> 교정안: 합성 후보"))
        let mixedHeaders = mixed.indices.filter { mixed[$0].hasPrefix("### [") }
        XCTAssertGreaterThan(mixedNote, candidate)
        XCTAssertLessThan(mixedNote, mixedHeaders[1])

        // 한 문단에 버린 원구간 2개 → 문구 2a.
        let two = String(decoding: try Self.markdownScript(editT1: false, rejected: [.init(turnID: "t1", rule: .quote), .init(turnID: "t2", rule: .limit)]).markdown(), as: UTF8.self)
            .components(separatedBy: "\n")
        XCTAssertEqual(two.filter { $0.hasPrefix("> AI 검증 실패: ") }, [note + " (2개 원구간)"])
        XCTAssertEqual(two.filter { $0 == "- 검증 실패로 원문 유지: 2개 원구간" }.count, 1)
    }

    func testRejectedCountCountsOnlyListedTurns() throws {
        var correction = ScriptCorrection(input: ConversionNotes(), engine: "synthetic", state: .completed)
        XCTAssertEqual(correction.rejectedCount(in: ["t1", "t2"]), 0)
        correction.rejectedTurns = [.init(turnID: "t2", rule: .quote), .init(turnID: "t3", rule: .text)]
        XCTAssertEqual(correction.rejectedCount(in: ["t1", "t2"]), 1)
        XCTAssertEqual(correction.rejectedCount(in: ["t2", "t3", "t4"]), 2)
    }
}

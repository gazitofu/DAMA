import Foundation
import XCTest
@testable import DamaCore
@testable import DamaManaged

/// 묶음 3 ① 진단(notes/usage-review/correction-measure.md): 교정 청크 하나를 앱과 같은 인자로 Codex에 보내 응답을 메모리에서만 검사한다.
/// 환경변수가 있을 때만 메인이 돌린다. 실행마다 청크 원문·참석자·맥락·참고 발췌가 OpenAI로 전송되므로 사용자 승인 뒤에만 쓴다.
/// DAMA_PROBE_SCRIPTS = Scripts 폴더, DAMA_PROBE_SCRIPT = 스크립트 ID 앞부분, DAMA_PROBE_ROOT = 내부 저장소(시도 기록 읽기),
/// DAMA_PROBE_CODEX = codex 실행 파일, DAMA_PROBE_OUT = 결과 JSON(개수·규칙 이름만), DAMA_PROBE_RUNS = 반복 수(기본 1), DAMA_PROBE_CHUNK = 청크 번호(기본 0).
/// 원문·응답 내용은 어디에도 남기지 않는다(임시 폴더 0700, 끝나면 삭제). 실데이터에 쓰지 않는다.
final class CorrectionFormatProbeTests: XCTestCase {
    func testCorrectionChunkReplyAgainstValidationRules() throws {
        let env = ProcessInfo.processInfo.environment
        guard let scriptsPath = env["DAMA_PROBE_SCRIPTS"], let prefix = env["DAMA_PROBE_SCRIPT"], let rootPath = env["DAMA_PROBE_ROOT"],
              let codexPath = env["DAMA_PROBE_CODEX"], let outPath = env["DAMA_PROBE_OUT"] else {
            throw XCTSkip("교정 형식 진단은 DAMA_PROBE_* 환경변수가 있을 때만 메인이 돌린다(외부 전송).")
        }
        let runs = max(1, Int(env["DAMA_PROBE_RUNS"] ?? "1") ?? 1), chunkIndex = Int(env["DAMA_PROBE_CHUNK"] ?? "0") ?? 0
        var found: [LibraryScript] = []
        for url in try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: scriptsPath), includingPropertiesForKeys: nil)
        where url.lastPathComponent.hasSuffix(".dama.json") {
            guard let script = try? JSONDecoder().decode(LibraryScript.self, from: Data(contentsOf: url)) else { continue }
            if script.id.uppercased().hasPrefix(prefix.uppercased()) { found.append(script) }
        }
        XCTAssertEqual(found.count, 1)
        guard let script = found.first else { return }
        let attempt = try XCTUnwrap(try CorrectionAttemptStore(root: URL(fileURLWithPath: rootPath)).load(scriptID: script.id))
        let chunks = try CorrectionPlan.chunks(for: script)
        XCTAssertTrue(chunks.indices.contains(chunkIndex))
        let chunk = chunks[chunkIndex]
        var report: [String: Any] = [
            "script": String(script.id.prefix(8)), "engine": attempt.engine, "chunk": chunkIndex, "chunks": chunks.count,
            "planMatchesAttempt": try CorrectionPlan.sha256(chunks) == attempt.planSHA256,
            "chunkTurns": chunk.turns.count, "chunkChars": chunk.turns.map(\.text.count).reduce(0, +),
            "chunkTurnsEmptyText": chunk.turns.filter { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count,
            "contextBefore": chunk.contextBefore.count, "contextAfter": chunk.contextAfter.count,
            "humanParagraphs": chunk.humanParagraphs?.count ?? 0,
        ]
        var results: [[String: Any]] = []
        for run in 1...runs {
            results.append(try probe(run: run, chunk: chunk, input: attempt.input, codex: URL(fileURLWithPath: codexPath)))
        }
        report["runs"] = results
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: outPath), options: .withoutOverwriting)
    }

    private func probe(run: Int, chunk: CorrectionChunk, input: ConversionNotes, codex: URL) throws -> [String: Any] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("dama-probe-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = directory.appendingPathComponent("schema.json"), output = directory.appendingPathComponent("result.json")
        let prompt = directory.appendingPathComponent("input.json")
        try ContextCorrection.outputSchema.write(to: schema)
        try ContextCorrection.prompt(chunk: chunk, input: input).write(to: prompt)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: prompt.path)
        let stdin = try FileHandle(forReadingFrom: prompt)
        defer { try? stdin.close() }
        let process = Process()
        process.executableURL = codex; process.currentDirectoryURL = directory
        process.arguments = CodexCorrectionClient.arguments(directory: directory, schema: schema, output: output)
        process.standardInput = stdin
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        let started = Date()
        try process.run()
        while process.isRunning && Date().timeIntervalSince(started) < 300 { Thread.sleep(forTimeInterval: 0.2) }
        var r: [String: Any] = ["run": run]
        if process.isRunning { process.terminate(); process.waitUntilExit(); r["timedOut"] = true }
        r["exitCode"] = Int(process.terminationStatus)
        r["elapsedMs"] = Int(Date().timeIntervalSince(started) * 1000)
        guard let bytes = try? Data(contentsOf: output) else { r["outputFile"] = false; return r }
        r["outputBytes"] = bytes.count

        let reply: CorrectionReply
        do { reply = try JSONDecoder().decode(CorrectionReply.self, from: bytes) } catch {
            r["decode"] = false
            r["decodeError"] = Self.describe(error)
            if let object = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] {
                r["topKeys"] = object.keys.sorted()
                if let turns = object["turns"] as? [[String: Any]] {
                    r["rawTurns"] = turns.count
                    for key in ["id", "text", "certain", "reason", "changes", "unresolved"] {
                        r["rawTurnsMissing_" + key] = turns.filter { $0[key] == nil || $0[key] is NSNull }.count
                    }
                }
            } else { r["json"] = false }
            return r
        }
        r["decode"] = true
        r["replyTurns"] = reply.turns.count
        r["names"] = reply.names.count
        r["turnsMissingChanges"] = reply.turns.filter { $0.changes == nil }.count
        r["turnsMissingUnresolved"] = reply.turns.filter { $0.unresolved == nil }.count
        let expected = chunk.turns.map(\.id), got = reply.turns.map(\.id)
        r["idsEqual"] = expected == got
        r["idsMissing"] = Set(expected).subtracting(got).count
        r["idsExtra"] = Set(got).subtracting(expected).count
        r["idsDuplicated"] = got.count - Set(got).count
        r["firstIdMismatch"] = zip(expected, got).enumerated().first { $0.element.0 != $0.element.1 }?.offset
            ?? (expected.count == got.count ? -1 : min(expected.count, got.count))
        let sources = Dictionary(chunk.turns.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var rules: [String: Int] = [:], whitespaceOnly = 0, changeCount = 0, unresolvedCount = 0
        for candidate in reply.turns {
            guard let source = sources[candidate.id] else { continue }
            changeCount += candidate.changes?.count ?? 0
            unresolvedCount += candidate.unresolved?.count ?? 0
            rules[Self.classify(candidate, source: source, input: input, whitespaceOnly: &whitespaceOnly), default: 0] += 1
        }
        r["turnRule"] = rules
        r["textMismatchWhitespaceOnly"] = whitespaceOnly
        r["changes"] = changeCount
        r["unresolved"] = unresolvedCount
        if let validated = try? ContextCorrection.validated(reply, chunk: chunk, input: input) {
            r["validated"] = true
            let decisions = validated.edits.flatMap { $0.changes ?? [] }
            r["applied"] = decisions.filter(\.applied).count
            r["held"] = decisions.filter { !$0.applied }.count
        } else { r["validated"] = false }
        return r
    }

    /// 분류기 자기 검증(합성, 외부 전송 없음, 상시): 규칙마다 양성 1개와 통과하는 음성 1개.
    func testProbeClassifierNamesTheFirstFailingRule() {
        let source = CorrectionTurn(id: "t1", speakerID: "SPEAKER_00", startUs: 0, endUs: 1_000_000, text: "가나다 라마바")
        func turn(_ text: String, changes: [CorrectionChange]? = [], unresolved: [CorrectionUnresolved]? = []) -> CorrectionReply.Turn {
            CorrectionReply.Turn(id: "t1", text: text, certain: true, reason: "합성", changes: changes, unresolved: unresolved)
        }
        func change(_ quote: String, _ replacement: String) -> CorrectionChange {
            CorrectionChange(quote: quote, occurrence: 0, replacement: replacement, certain: true, reason: "합성", termID: nil)
        }
        var whitespace = 0
        let cases: [(CorrectionReply.Turn, String)] = [
            (turn("가나다 라마바"), "ok"),
            (turn("가나다 라마사", changes: [change("라마바", "라마사")]), "ok"),
            (turn("가나다 라마바", changes: nil), "missingArrays"),
            (turn("가나다 라마사"), "textChangedWithoutChanges"),
            (turn("가나다 라마사", changes: [change("없는말", "라마사")]), "changeQuoteNotFound"),
            (turn("가나다 라마바", changes: [change("라마바", "라마사")]), "textNotEqualChanges"),
            (turn("가나다 라마바", changes: [change("가나다 라", "X"), change("라마바", "Y")]), "changesOverlap"),
            (turn("가나다 라마바", unresolved: [CorrectionUnresolved(quote: "없는말", occurrence: 0, reason: "합성")]), "unresolvedQuoteNotFound"),
        ]
        for (candidate, expected) in cases {
            XCTAssertEqual(Self.classify(candidate, source: source, input: ConversionNotes(), whitespaceOnly: &whitespace), expected)
        }
        XCTAssertEqual(whitespace, 0)
        XCTAssertEqual(Self.classify(turn("가나다라마바"), source: source, input: ConversionNotes(), whitespaceOnly: &whitespace), "textChangedWithoutChanges")
        XCTAssertEqual(whitespace, 1)
    }

    /// `ContextCorrection.validated` · `CorrectionSpans.validated`의 검사 순서를 따라 Turn 하나가 처음 걸리는 규칙 이름.
    static func classify(_ candidate: CorrectionReply.Turn, source: CorrectionTurn, input: ConversionNotes, whitespaceOnly: inout Int) -> String {
        if candidate.text.count > max(256, source.text.count * 3) { return "textTooLong" }
        if candidate.reason.count > 600 { return "reasonTooLong" }
        guard let changes = candidate.changes, let unresolved = candidate.unresolved else { return "missingArrays" }
        if unresolved.count > 100 { return "unresolvedOver100" }
        if changes.count > 100 { return "changesOver100" }
        for change in changes {
            if change.reason.count > 600 || change.replacement.count > max(256, source.text.count * 3) { return "changeTooLong" }
            if (try? CorrectionSpans.range(quote: change.quote, occurrence: change.occurrence, in: source.text)) == nil { return "changeQuoteNotFound" }
        }
        guard let anchors = try? CorrectionSpans.ranges(changes, source: source.text) else { return "changesOverlap" }
        let proposed = CorrectionSpans.compose(source: source.text, changes: changes, ranges: anchors, accepted: changes.map { _ in true })
        if proposed != candidate.text {
            if proposed.filter({ !$0.isWhitespace }) == candidate.text.filter({ !$0.isWhitespace }) { whitespaceOnly += 1 }
            return changes.isEmpty ? "textChangedWithoutChanges" : "textNotEqualChanges"
        }
        for item in unresolved {
            if item.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || item.reason.count > 600 { return "unresolvedReason" }
            if (try? CorrectionSpans.range(quote: item.quote, occurrence: item.occurrence, in: source.text)) == nil { return "unresolvedQuoteNotFound" }
        }
        // `try?`는 «편집 없음(nil 반환)»과 «검증 실패(throw)»를 구분하지 못하므로 do/catch로 본다.
        do { _ = try CorrectionSpans.validated(candidate, source: source, input: input) } catch { return "otherSpanFailure" }
        return "ok"
    }

    /// 해독 오류의 종류와 필드 경로만(값은 담지 않는다).
    private static func describe(_ error: Error) -> String {
        func path(_ context: DecodingError.Context) -> String { context.codingPath.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }.joined(separator: ".") }
        switch error {
        case DecodingError.keyNotFound(let key, let context): return "keyNotFound \(key.stringValue) at \(path(context))"
        case DecodingError.typeMismatch(_, let context): return "typeMismatch at \(path(context))"
        case DecodingError.valueNotFound(_, let context): return "valueNotFound at \(path(context))"
        case DecodingError.dataCorrupted(let context): return "dataCorrupted at \(path(context))"
        default: return "other"
        }
    }
}

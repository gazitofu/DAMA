import DamaAudio
import DamaCore
import Foundation
import XCTest
@testable import DamaManaged

/// usage-bundle1 AC-14: 시도 기록·이어서 교정. 가짜 Codex CLI(합성 응답)만 쓰고 실제 호출·네트워크는 없다.
final class CorrectionRunnerTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// 가짜 CLI: stdin 프롬프트 끝의 JSON에서 청크 원구간을 읽어 모든 원구간에 «.»를 붙이는 확실한 수정과
    /// 자기소개 이름을 돌려준다. 같은 폴더의 `count`에 호출을 한 줄씩 남기고, `fail-at`의 번째 호출이면
    /// 고유 표식을 stderr에 쓰고 exit 1. correction-turn-isolation: 같은 폴더의 `mode` 파일이 있으면 응답을 바꾼다
    /// (reject = 첫 원구간 수정의 인용을 «없는말»로 · garbage = 출력 «{» · swap = 앞 두 원구간 순서 · drop = 끝 원구간 뺌 ·
    /// missing = 첫 원구간 `unresolved` 키 뺌).
    private func fake(in folder: URL, marker: String) throws -> URL {
        let url = folder.appendingPathComponent("fake-codex")
        let script = """
        #!/usr/bin/python3 -I
        import json, os, sys
        here = os.path.dirname(os.path.abspath(sys.argv[0]))
        args = sys.argv[1:]
        result = args[args.index("--output-last-message") + 1]
        data = sys.stdin.read()
        with open(os.path.join(here, "count"), "a") as f: f.write("x\\n")
        with open(os.path.join(here, "count")) as f: count = len(f.read().splitlines())
        fail = os.path.join(here, "fail-at")
        if os.path.exists(fail) and int(open(fail).read()) == count:
            sys.stderr.write("\(marker)\\n"); sys.exit(1)
        payload = json.loads([l for l in data.splitlines() if l.startswith("{")][-1])
        turns, names = [], []
        for t in payload["chunk"]["turns"]:
            text = t["text"]
            changes = [{"quote": text, "occurrence": 0, "replacement": text + ".", "certain": True, "reason": "합성 구두점", "termID": None}] if text else []
            turns.append({"id": t["id"], "text": text + "." if text else text, "certain": True, "reason": "", "changes": changes, "unresolved": []})
            if "저는 김가상입니다" in text:
                names.append({"speakerID": t["speakerID"], "name": "김가상", "evidenceTurnID": t["id"], "quote": "저는 김가상입니다"})
        mode_path = os.path.join(here, "mode")
        mode = open(mode_path).read().strip() if os.path.exists(mode_path) else ""
        if mode == "garbage":
            open(result, "w").write("{"); sys.exit(0)
        if mode == "reject" and turns and turns[0]["changes"]: turns[0]["changes"][0]["quote"] = "없는말"
        if mode == "swap" and len(turns) > 1: turns[0], turns[1] = turns[1], turns[0]
        if mode == "drop": turns = turns[:-1]
        if mode == "missing" and turns: del turns[0]["unresolved"]
        with open(result, "w") as f: json.dump({"turns": turns, "names": names}, f, ensure_ascii=False)
        """
        try Data(script.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }
    /// 폴더 아래 모든 일반 파일 수와 `marker`가 든 파일 수.
    private func search(_ folders: [URL], for marker: String) throws -> (files: Int, hits: Int) {
        var files = 0, hits = 0
        for folder in folders {
            let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey])!
            while let url = walker.nextObject() as? URL {
                guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
                files += 1
                if String(decoding: try Data(contentsOf: url), as: UTF8.self).contains(marker) { hits += 1 }
            }
        }
        return (files, hits)
    }
    private func calls(_ folder: URL) -> Int {
        ((try? String(contentsOf: folder.appendingPathComponent("count"), encoding: .utf8)) ?? "").split(separator: "\n").count
    }

    /// 1,200 원구간(화자 A·B 번갈아) = 100원구간 청크 12개. 2번째·9번째 청크에 자기소개.
    private func script() throws -> LibraryScript {
        let count = 1_200
        let intervals: [[String: Any]] = (0..<count).map { ["start": Double($0 * 2), "end": Double($0 * 2 + 1), "speaker": $0 % 2 == 0 ? "A" : "B"] }
        let words: [[String: Any]] = (0..<count).map { i in
            ["start": Double(i * 2), "end": Double(i * 2) + 0.8, "speaker": i % 2 == 0 ? "A" : "B",
             "text": [150, 850].contains(i) ? "저는 김가상입니다" : "대사\(i)"]
        }
        let bytes = try JSONSerialization.data(withJSONObject: ["jobId": "synthetic", "status": "succeeded", "output":
            ["diarization": intervals, "exclusiveDiarization": intervals, "wordLevelTranscription": words]])
        let model = try ManagedNormalizer.normalize(bytes, sessionID: "synthetic", runID: "synthetic-runner", durationUs: Int64(count * 2_000_000),
            audioSHA256: String(repeating: "a", count: 64), synthetic: true, createdAt: "2026-11-05T00:00:00Z")
        var notes = ConversionNotes(); notes.participants = "김가상 · 개발"; notes.context = "합성 교정 검증"
        return try LibraryScript(transcript: model, title: "합성 교정", recordedAt: nil, dateSource: "합성", input: notes)
    }

    func testFailAtFifthThenResumeSendsOnlyRemainingAndMatchesOneShot() async throws {
        let script = try script()
        XCTAssertEqual(try CorrectionPlan.chunks(for: script).count, 12)
        let marker = "DAMA-STDERR-MARKER-" + UUID().uuidString
        // 한 번에 끝낸 기준선.
        let baseFolder = try directory(), baseRoot = try directory()
        let base = CorrectionRunner(store: CorrectionAttemptStore(root: baseRoot), executable: try fake(in: baseFolder, marker: marker), timeout: .seconds(30))
        let (baseAttempt, baseChunks) = try base.begin(script: script, input: script.input)
        guard case .completed(let oneShot) = await base.run(baseAttempt, chunks: baseChunks) else { return XCTFail("baseline") }
        XCTAssertEqual(calls(baseFolder), 12)
        let expected = oneShot.merged()
        XCTAssertEqual(expected.edits.count, 1_200)
        XCTAssertEqual(expected.names.count, 1)
        // 5번째 호출에서 실패.
        let folder = try directory(), root = try directory()
        let executable = try fake(in: folder, marker: marker)
        try Data("5".utf8).write(to: folder.appendingPathComponent("fail-at"))
        let store = CorrectionAttemptStore(root: root)
        let runner = CorrectionRunner(store: store, executable: executable, timeout: .seconds(30))
        let (attempt, chunks) = try runner.begin(script: script, input: script.input)
        guard case .failed(let failed, let error) = await runner.run(attempt, chunks: chunks) else { return XCTFail("expected failure") }
        XCTAssertEqual(error.kind, .unclassified)
        XCTAssertEqual(failed.completedChunks, 4)
        XCTAssertEqual(failed.remainingChunks, Array(4..<12))
        XCTAssertEqual(failed.lastFailure?.chunkIndex, 4)
        XCTAssertEqual(failed.lastFailure?.exitCode, 1)
        XCTAssertGreaterThan(failed.lastFailure?.stderrBytes ?? 0, 0) // 양성 대조: stderr는 왔다.
        XCTAssertEqual(try store.load(scriptID: script.id), failed) // 앱 재시작 뒤에도 파일로 남는다.
        XCTAssertEqual(runner.resumeState(for: script), .available(completed: 4, total: 12, lastFailure: failed.lastFailure))
        // 이어서 교정: 남은 8개만.
        try FileManager.default.removeItem(at: folder.appendingPathComponent("fail-at"))
        let (resume, again) = try runner.prepareResume(script: script)
        XCTAssertEqual(resume.input, script.input) // 기록된 입력 스냅숏.
        guard case .completed(let finished) = await runner.run(resume, chunks: again) else { return XCTFail("resume") }
        XCTAssertEqual(calls(folder), 13) // 5 + 8.
        let merged = finished.merged()
        XCTAssertEqual(merged.edits, expected.edits)
        XCTAssertEqual(merged.names, expected.names)
        XCTAssertEqual(merged.evidence, expected.evidence)
        // 원문 미기록: 앱의 최종 저장까지 흉내 낸 임시 내부 저장소·임시 Scripts 전수에서 stderr 표식 0.
        let scripts = try directory()
        let library = FolderLibraryStore(root: root)
        let file = try await library.saveScript(script, to: scripts.appendingPathComponent("s.dama.json"), expectedHash: nil)
        var correction = ScriptCorrection(input: script.input, engine: CorrectionRunner.engine, state: .completed)
        correction.edits = merged.edits; correction.speakerNames = merged.names; correction.nameEvidence = merged.evidence
        _ = try await library.saveCorrection(correction, for: file)
        let (files, hits) = try search([root, scripts], for: marker)
        XCTAssertGreaterThan(files, 2)
        XCTAssertEqual(hits, 0)
        XCTAssertEqual(try String(contentsOf: executable, encoding: .utf8).contains(marker), true) // 양성 대조: 검색 문자열은 실재한다.
        // 성공 저장 직후 기록 삭제.
        try runner.discard(scriptID: script.id)
        XCTAssertNil(try store.load(scriptID: script.id))
        XCTAssertEqual(runner.resumeState(for: script), .none)
    }

    func testPlanOrEngineChangeBlocksResumeAndNewStartDiscardsRecord() async throws {
        var script = try script()
        let folder = try directory(), root = try directory()
        let runner = CorrectionRunner(store: CorrectionAttemptStore(root: root), executable: try fake(in: folder, marker: "M"), timeout: .seconds(30))
        try Data("1".utf8).write(to: folder.appendingPathComponent("fail-at"))
        let (attempt, chunks) = try runner.begin(script: script, input: script.input)
        guard case .failed(let failed, _) = await runner.run(attempt, chunks: chunks) else { return XCTFail() }
        // 0개 완료 → «같은 입력으로 다시 시도» (completed 0).
        XCTAssertEqual(runner.resumeState(for: script), .available(completed: 0, total: 12, lastFailure: failed.lastFailure))
        // 엔진이 다르면 이어서 교정 불가.
        XCTAssertEqual(runner.resumeState(for: script, engine: "Codex CLI · 다른 모델 · context-correction-6"),
                       .planChanged(completed: 0, total: 12, lastFailure: failed.lastFailure))
        // 문단 1개 수정 → 청크 계획이 바뀐다.
        let first = try XCTUnwrap(script.transcript.turns.first { $0.kind == .speech })
        try script.editText(first.id, text: "사람이 고친 문장")
        XCTAssertEqual(runner.resumeState(for: script), .planChanged(completed: 0, total: 12, lastFailure: failed.lastFailure))
        XCTAssertThrowsError(try runner.prepareResume(script: script))
        // 새 교정 시작 → 기록 버림.
        let (fresh, _) = try runner.begin(script: script, input: script.input)
        XCTAssertNotEqual(fresh.attemptID, failed.attemptID)
        XCTAssertTrue(fresh.failures.isEmpty)
        XCTAssertEqual(try runner.store.load(scriptID: script.id)?.attemptID, fresh.attemptID)
    }

    func testMissingExitCodeIsStoredAsExplicitNull() throws {
        let record = CorrectionFailureRecord(chunkIndex: 0, totalChunks: 1, kind: .timeout, exitCode: nil, elapsedMs: 300_000, stderrBytes: 0)
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as! [String: Any]
        XCTAssertTrue(object.keys.contains("exitCode")) // QA C D-3: 키 생략이 아니라 null.
        XCTAssertTrue(object["exitCode"] is NSNull)
        XCTAssertEqual(try JSONDecoder().decode(CorrectionFailureRecord.self, from: JSONEncoder().encode(record)), record)
        let coded = CorrectionFailureRecord(chunkIndex: 0, totalChunks: 1, kind: .auth, exitCode: 1, elapsedMs: 5, stderrBytes: 9)
        XCTAssertEqual((try JSONSerialization.jsonObject(with: JSONEncoder().encode(coded)) as! [String: Any])["exitCode"] as? Int, 1)
    }

    func testFailureHistoryKeepsLatestTwentyAndUnsafeIDsAreRejected() throws {
        var attempt = CorrectionAttempt(scriptID: "s", engine: "e", input: ConversionNotes(), planSHA256: "p", chunkSHA256s: ["a", "b"])
        for i in 0..<25 {
            attempt.record(CorrectionFailureRecord(chunkIndex: 0, totalChunks: 2, kind: .timeout, exitCode: nil, elapsedMs: Int64(i), stderrBytes: 0))
        }
        XCTAssertEqual(attempt.failures.count, 20)
        XCTAssertEqual(attempt.failures.first?.elapsedMs, 5)
        let store = CorrectionAttemptStore(root: try directory())
        XCTAssertThrowsError(try store.save(CorrectionAttempt(scriptID: "../x", engine: "e", input: ConversionNotes(), planSHA256: "p", chunkSHA256s: [])))
        XCTAssertThrowsError(try store.load(scriptID: ""))
        try store.save(attempt)
        XCTAssertEqual(try store.load(scriptID: "s"), attempt)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.folder.appendingPathComponent("s.json").path))
    }

    // MARK: correction-turn-isolation AC-06 · AC-03 (가짜 CLI, 실제 호출 없음)

    private func runner(mode: String, failAt: Int? = nil) throws -> (CorrectionRunner, URL) {
        let folder = try directory(), root = try directory()
        try Data(mode.utf8).write(to: folder.appendingPathComponent("mode"))
        if let failAt { try Data(String(failAt).utf8).write(to: folder.appendingPathComponent("fail-at")) }
        let runner = CorrectionRunner(store: CorrectionAttemptStore(root: root), executable: try fake(in: folder, marker: "M"), timeout: .seconds(30))
        return (runner, folder)
    }

    /// 청크마다 첫 원구간이 검증 실패 → 청크는 성공, 버린 Turn은 청크 결과에 남고 합칠 때 청크 순서로 모인다.
    func testRejectedTurnsAreRecordedPerChunkAndMergedInOrder() async throws {
        let script = try script()
        let chunks = try CorrectionPlan.chunks(for: script)
        let (runner, folder) = try runner(mode: "reject")
        let (attempt, planned) = try runner.begin(script: script, input: script.input)
        guard case .completed(let finished) = await runner.run(attempt, chunks: planned) else { return XCTFail("reject mode") }
        XCTAssertEqual(calls(folder), 12)
        XCTAssertEqual(finished.results.map(\.rejected), chunks.map { [CorrectionRejectedTurn(turnID: $0.turns[0].id, rule: .quote)] })
        let merged = finished.merged()
        XCTAssertEqual(merged.rejected, chunks.map { CorrectionRejectedTurn(turnID: $0.turns[0].id, rule: .quote) })
        XCTAssertEqual(merged.edits.count, 1_188) // 기준선 1,200 − 버린 12.
        XCTAssertEqual(merged.names.count, 1)
        XCTAssertTrue(Set(merged.edits.map(\.turnID)).isDisjoint(with: merged.rejected.map(\.turnID)))
    }

    /// 이어서 교정은 끝난 청크(버린 Turn 포함)를 다시 보내지 않고, 합친 결과는 한 번에 끝낸 것과 같다.
    func testResumeKeepsRejectedTurnsOfFinishedChunks() async throws {
        let script = try script()
        let (base, _) = try runner(mode: "reject")
        let (baseAttempt, baseChunks) = try base.begin(script: script, input: script.input)
        guard case .completed(let oneShot) = await base.run(baseAttempt, chunks: baseChunks) else { return XCTFail("baseline") }
        let (runner, folder) = try runner(mode: "reject", failAt: 5)
        let (attempt, chunks) = try runner.begin(script: script, input: script.input)
        guard case .failed(let failed, _) = await runner.run(attempt, chunks: chunks) else { return XCTFail("expected failure") }
        XCTAssertEqual(failed.completedChunks, 4)
        XCTAssertEqual(failed.results.compactMap(\.rejected).map(\.count), [1, 1, 1, 1])
        XCTAssertEqual(try runner.store.load(scriptID: script.id), failed) // 시도 기록 파일에 그대로 남는다.
        try FileManager.default.removeItem(at: folder.appendingPathComponent("fail-at"))
        let (resume, again) = try runner.prepareResume(script: script)
        guard case .completed(let finished) = await runner.run(resume, chunks: again) else { return XCTFail("resume") }
        XCTAssertEqual(calls(folder), 13) // 5 + 8.
        XCTAssertEqual(finished.merged().rejected, oneShot.merged().rejected)
        XCTAssertEqual(finished.merged().rejected.count, 12)
        XCTAssertEqual(finished.merged().edits, oneShot.merged().edits)
    }

    /// 응답을 입력과 짝지을 수 없으면 지금처럼 청크 실패(형식), 결과 기록 없음.
    func testUnpairableRepliesRemainFormatFailures() async throws {
        let script = try script()
        for mode in ["garbage", "swap", "drop", "missing"] {
            let (runner, folder) = try runner(mode: mode)
            let (attempt, chunks) = try runner.begin(script: script, input: script.input)
            guard case .failed(let failed, let error) = await runner.run(attempt, chunks: chunks) else { XCTFail(mode); continue }
            XCTAssertEqual(error.kind, .format, mode)
            XCTAssertEqual(error.exitCode, 0, mode)
            XCTAssertEqual(failed.lastFailure?.kind, .format, mode)
            XCTAssertTrue(failed.results.isEmpty, mode)
            XCTAssertEqual(calls(folder), 1, mode)
        }
    }

    /// 선택 필드가 없는 기존 시도 기록(usage-bundle1 형식 1)은 그대로 해독되고 다시 써도 바이트가 같다.
    func testLegacyAttemptWithoutRejectedDecodesByteForByte() throws {
        let literal = #"{"attemptID":"A1","chunkSHA256s":["c0","c1"],"engine":"Codex CLI · 합성 · context-correction-6","failures":[],"formatVersion":1,"input":{"context":"","reference":""},"planSHA256":"p","results":[{"chunkIndex":0,"edits":[{"applied":false,"original":"합성 원문","reason":"합성 보류","text":"합성 후보","turnID":"t1"}],"evidence":{},"names":{}}],"scriptID":"S1","startedAt":800000000}"#
        let store = CorrectionAttemptStore(root: try directory())
        try FileManager.default.createDirectory(at: store.folder, withIntermediateDirectories: true)
        let url = store.folder.appendingPathComponent("S1.json")
        try Data(literal.utf8).write(to: url)
        let attempt = try XCTUnwrap(try store.load(scriptID: "S1"))
        XCTAssertNil(attempt.results.first?.rejected)
        XCTAssertEqual(attempt.merged().rejected, [])
        try store.save(attempt)
        XCTAssertEqual(String(decoding: try Data(contentsOf: url), as: UTF8.self), literal)
    }
}

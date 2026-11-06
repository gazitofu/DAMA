import Foundation
import XCTest
import DamaCore
@testable import DamaAudio

final class ScriptVersionTests: XCTestCase {
    private func script() throws -> LibraryScript {
        var repo = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { repo.deleteLastPathComponent() }
        let model = try JSONDecoder().decode(TranscriptDocument.self, from: Data(contentsOf: repo.appendingPathComponent("fixtures/normalized-transcript.json")))
        return try LibraryScript(transcript: model, title: "합성 제목", recordedAt: nil, dateSource: "합성", input: ConversionNotes())
    }
    func testSavedCandidatesApplyOnceWithHumanEditsAndImmutableHistory() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let root = folder.appendingPathComponent("internal"), url = folder.appendingPathComponent("script.dama.json")
        let store = FolderLibraryStore(root: root)
        let first = try await store.saveScript(script(), to: url, expectedHash: nil)
        let allSources = try ContextCorrection.chunks(first.script).flatMap(\.turns)
        let sources = try first.reading.blocks.filter(\.isSpeech).prefix(2).map { block in
            try XCTUnwrap(allSources.first { block.turnIDs.contains($0.id) })
        }
        var old = ScriptCorrection(input: first.script.input, engine: "synthetic context-correction-4", state: .completed)
        // Construct persisted v4 decisions through Codable, as if loaded from disk.
        // usage-bundle1: 대체 문자열에 숫자를 넣지 않는다(«합성 교정 0»은 context-correction-6 숫자 보호에 걸림).
        // 숫자를 새로 넣는 저장 후보의 보류는 MeaningGuardTests.testReapplicationHoldsMeaningChangesWithBasis가 따로 단정한다.
        let labels = ["가", "나"]
        old.edits = try sources.prefix(2).enumerated().map { index, source in
            let object: [String: Any] = ["turnID": source.id, "original": source.text, "text": "합성 교정 \(labels[index])",
                "reason": "이전 용어 제한", "applied": false, "appliedText": source.text, "unresolved": [],
                "changes": [["applied": false, "basis": "이전 용어 제한", "change": [
                    "quote": source.text, "occurrence": 0, "replacement": "합성 교정 \(labels[index])", "certain": true, "reason": "합성 표기 교정"]]]]
            return try JSONDecoder().decode(CorrectionEdit.self, from: JSONSerialization.data(withJSONObject: object))
        }
        XCTAssertEqual(old.edits.count, 2)
        let previous = try await store.saveCorrection(old, for: first)
        let version = try XCTUnwrap(previous.script.versions?.last)
        let history = try await store.readVersion(version, for: previous)
        let historyBytes = try Data(contentsOf: history.url)
        let owned = try XCTUnwrap(previous.reading.blocks.first { $0.turnIDs.contains(sources[1].id) })
        _ = try await store.saveParagraph(owned, text: "사람 수정 유지", for: previous)
        let applied = try await store.applyPendingCorrection(for: previous)
        XCTAssertEqual(applied.script.text(for: applied.script.transcript.turns.first { $0.id == sources[0].id }!), "합성 교정 가")
        XCTAssertTrue(applied.reading.blocks.contains { $0.text == "사람 수정 유지" })
        XCTAssertEqual(applied.script.correction?.edits[1].applied, false)
        XCTAssertEqual(applied.script.versions?.map(\.number), [0, 1, 2])
        XCTAssertNotEqual(applied.script.correction?.id, old.id)
        XCTAssertEqual(try Data(contentsOf: history.url), historyBytes)
        XCTAssertEqual(try applied.script.sourceFingerprint(), try first.script.sourceFingerprint())
        let again = try await store.applyPendingCorrection(for: applied)
        XCTAssertEqual(again.hash, applied.hash)
        do { _ = try await store.applyPendingCorrection(for: previous); XCTFail("stale correction") }
        catch { XCTAssertTrue(error is LibraryFailure) }
        do { _ = try await store.applyPendingCorrection(for: history); XCTFail("read-only history") }
        catch { XCTAssertTrue(error is LibraryFailure) }
        let reopened = FolderLibraryStore(root: root)
        let files = try await reopened.scripts(in: folder)
        let loaded = try XCTUnwrap(files.first)
        XCTAssertEqual(loaded.reading.blocks.map(\.text), applied.reading.blocks.map(\.text))
        let export = folder.appendingPathComponent("corrected.md")
        try await reopened.exportMarkdown(loaded, to: export)
        let md = try String(contentsOf: export, encoding: .utf8)
        XCTAssertTrue(md.contains("합성 교정 가")); XCTAssertTrue(md.contains("사람 수정 유지"))
        try Data("external mutation".utf8).write(to: loaded.url)
        do { _ = try await reopened.applyPendingCorrection(for: loaded); XCTFail("external conflict") }
        catch { XCTAssertTrue(error is LibraryFailure) }
    }
    func testSerialFieldMergeImmutableVersionsAndReadOnlyExport() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = FolderLibraryStore(root: folder.appendingPathComponent("internal"))
        let first = try await store.saveScript(script(), to: folder.appendingPathComponent("script.dama.json"), expectedHash: nil)
        let block = try XCTUnwrap(first.reading.blocks.first(where: \.isSpeech))
        _ = try await store.saveParagraph(block, text: "사람의 문단 전체", for: first)
        let title = try await store.saveTitle("자동 저장 제목", for: first)
        XCTAssertEqual(title.reading.blocks.first(where: \.isSpeech)?.text, "사람의 문단 전체")
        var correction = ScriptCorrection(input: first.script.input, engine: "synthetic", state: .completed)
        correction.completedAt = Date()
        let completed = try await store.saveCorrection(correction, for: first)
        XCTAssertEqual(completed.script.title, "자동 저장 제목")
        XCTAssertEqual(completed.script.versions?.map(\.number), [0, 1])
        let again = try await store.saveCorrection(correction, for: first)
        XCTAssertEqual(again.hash, completed.hash)
        let versions = try XCTUnwrap(completed.script.versions)
        let before = try await store.readVersion(versions[0], for: completed)
        let after = try await store.readVersion(versions[1], for: completed)
        XCTAssertNil(before.script.correction)
        XCTAssertEqual(after.script.correction?.id, correction.id)
        XCTAssertEqual(before.script.title, "자동 저장 제목")
        XCTAssertEqual(before.reading.blocks.first(where: \.isSpeech)?.text, "사람의 문단 전체")
        let oldBytes = try Data(contentsOf: after.url)
        let renamed = try await store.saveTitle("현재만 새 제목", for: completed)
        let second = ScriptCorrection(input: first.script.input, engine: "synthetic-2", state: .completed)
        let latest = try await store.saveCorrection(second, for: renamed)
        XCTAssertEqual(latest.script.versions?.map(\.number), [0, 1, 2])
        XCTAssertEqual(try Data(contentsOf: after.url), oldBytes)
        var failed = second; failed.state = .failed
        let kept = try await store.saveCorrection(failed, for: latest)
        XCTAssertEqual(kept.hash, latest.hash)
        let export = folder.appendingPathComponent("history.md")
        try await store.exportMarkdown(after, to: export)
        let markdown = try String(contentsOf: export, encoding: .utf8)
        XCTAssertTrue(markdown.contains("자동 저장 제목"))
        XCTAssertTrue(markdown.contains("AI 보정 1"))
        do { _ = try await store.saveTitle("과거 덮어쓰기", for: after); XCTFail("read only") }
        catch { XCTAssertTrue(error is LibraryFailure) }
        do { _ = try await store.saveScript(after.script, to: after.url, expectedHash: after.hash); XCTFail("immutable") }
        catch { XCTAssertTrue(error is LibraryFailure) }
        // usage-bundle2 가드 이동: 평문 변조 → (1) 압축 파일 1바이트 변조 (2) 풀어서 1바이트 변조 후 다시 압축.
        XCTAssertTrue(after.url.lastPathComponent.hasSuffix(".dama.json.deflate"))
        let stored = try Data(contentsOf: after.url)
        var flipped = stored; flipped[flipped.count / 2] ^= 0xFF
        try flipped.write(to: after.url)
        do { _ = try await store.readVersion(versions[1], for: latest); XCTFail("tampered compressed snapshot") }
        catch { XCTAssertTrue(error is LibraryFailure) }
        let plain = try XCTUnwrap(String(data: RevisionCodec.inflate(stored), encoding: .utf8))
        let forged = plain.replacingOccurrences(of: #""title":"자동 저장 제목""#, with: #""title":"자동 저장 변조""#)
        XCTAssertNotEqual(forged, plain)   // 유효한 JSON·검증을 통과하는 내용 변조: 해시 검사만 잡는다.
        try RevisionCodec.deflate(Data(forged.utf8)).write(to: after.url)
        do { _ = try await store.readVersion(versions[1], for: latest); XCTFail("tampered snapshot content") }
        catch { XCTAssertTrue(error is LibraryFailure) }
        XCTAssertEqual(try AudioFiles.hash(latest.url), latest.hash)
    }
    func testStaleTitleUnknownExternalEditsAndFailedAttemptCannotInventHistory() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = FolderLibraryStore(root: folder.appendingPathComponent("internal"))
        let first = try await store.saveScript(script(), to: folder.appendingPathComponent("script.dama.json"), expectedHash: nil)
        let failed = ScriptCorrection(input: first.script.input, engine: "synthetic", state: .failed)
        let unsuccessful = try await store.saveCorrection(failed, for: first)
        XCTAssertNil(unsuccessful.script.versions)
        let renamed = try await store.saveTitle("새 제목", for: first)
        do { _ = try await store.saveTitle("늦게 온 이전 제목", for: first); XCTFail("stale title") }
        catch { XCTAssertTrue(error is LibraryFailure) }
        var external = renamed.script; try external.renameTitle("외부 수정")
        try JSONEncoder().encode(external).write(to: renamed.url, options: .atomic)
        let bytes = try Data(contentsOf: renamed.url)
        _ = try await store.scanScripts(in: folder)
        // Reading an external revision does not make it a locally committed merge base.
        do { _ = try await store.saveTitle("앱의 이전 draft", for: renamed); XCTFail("foreign bytes") }
        catch { XCTAssertTrue(error is LibraryFailure) }
        do { _ = try await store.saveCorrection(failed, for: first); XCTFail("foreign bytes") }
        catch { XCTAssertTrue(error is LibraryFailure) }
        XCTAssertEqual(try Data(contentsOf: renamed.url), bytes)
    }
    func testRegisteredPeopleAndDeletionSurviveReopenCorrectionAndVersionIsolation() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let root = folder.appendingPathComponent("internal"), url = folder.appendingPathComponent("script.dama.json")
        let store = FolderLibraryStore(root: root)
        let original = try await store.saveScript(script(), to: url, expectedHash: nil)
        let fingerprint = try original.script.sourceFingerprint()
        var edit = original.script
        try edit.rename(edit.blocks()[0], name: "등록 인물", scope: .all)
        let toDelete = edit.blocks()[1]
        try edit.deleteParagraph(toDelete)
        let saved = try await store.saveScript(edit, to: url, expectedHash: original.hash)
        let correction = ScriptCorrection(input: original.script.input, engine: "synthetic", state: .completed)
        let completed = try await store.saveCorrection(correction, for: original)
        XCTAssertEqual(completed.script.deletedParagraphs, saved.script.deletedParagraphs)
        XCTAssertEqual(completed.script.registeredSpeakers, saved.script.registeredSpeakers)
        XCTAssertEqual(completed.script.turnSpeakerIDs, saved.script.turnSpeakerIDs)
        let version = try XCTUnwrap(completed.script.versions?.last)
        let history = try await store.readVersion(version, for: completed)
        let historyBytes = try Data(contentsOf: history.url)
        let reopened = FolderLibraryStore(root: root)
        let files = try await reopened.scripts(in: folder)
        let current = try XCTUnwrap(files.first)
        XCTAssertEqual(current.reading.blocks.map(\.text), completed.reading.blocks.map(\.text))
        XCTAssertEqual(current.script.registeredSpeakers, saved.script.registeredSpeakers)
        let export = folder.appendingPathComponent("result.md")
        try await reopened.exportMarkdown(current, to: export)
        XCTAssertTrue(try String(contentsOf: export, encoding: .utf8).contains("등록 인물"))
        var restored = current.script
        try restored.undoParagraphDeletion()
        let restoredFile = try await reopened.saveScript(restored, to: url, expectedHash: current.hash)
        XCTAssertTrue(restoredFile.reading.blocks.contains { $0.turnIDs == toDelete.turnIDs })
        XCTAssertEqual(try Data(contentsOf: history.url), historyBytes)
        XCTAssertEqual(try restoredFile.script.sourceFingerprint(), fingerprint)
        do { _ = try await reopened.saveScript(edit, to: url, expectedHash: saved.hash); XCTFail("stale deletion must not replace restored content") }
        catch { XCTAssertTrue(error is LibraryFailure) }
        XCTAssertEqual(try AudioFiles.hash(url), restoredFile.hash)
    }
}

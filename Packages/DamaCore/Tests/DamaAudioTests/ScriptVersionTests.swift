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
        try Data("손상".utf8).write(to: after.url)
        do { _ = try await store.readVersion(versions[1], for: latest); XCTFail("tampered snapshot") }
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
}

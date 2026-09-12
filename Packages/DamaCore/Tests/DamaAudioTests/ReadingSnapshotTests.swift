import Foundation
import XCTest
import DamaCore
@testable import DamaAudio

final class ReadingSnapshotTests: XCTestCase {
    private func setup() throws -> (URL, FolderLibraryStore, LibraryScript) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: folder) }
        var fixture = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { fixture.deleteLastPathComponent() }
        let model = try JSONDecoder().decode(TranscriptDocument.self, from: Data(contentsOf: fixture.appendingPathComponent("fixtures/normalized-transcript.json")))
        let script = try LibraryScript(transcript: model, title: "합성 캐시 검증", recordedAt: nil, dateSource: "합성", input: ConversionNotes())
        return (folder, FolderLibraryStore(root: folder.appendingPathComponent("internal")), script)
    }

    private func assertProjection(_ file: LibraryScriptFile, line: UInt = #line) throws {
        let expected = file.script.blocks(), actual = file.reading.blocks
        XCTAssertEqual(actual.map(\.text), expected.map(\.text), line: line)
        XCTAssertEqual(actual.map(\.name), expected.map(\.name), line: line)
        XCTAssertEqual(actual.map(\.colorIndex), expected.map(\.colorIndex), line: line)
        XCTAssertEqual(actual.map(\.edited), expected.map(\.edited), line: line)
        XCTAssertEqual(try JSONEncoder().encode(actual.map(\.turns)), try JSONEncoder().encode(expected.map(\.turns)), line: line)
        XCTAssertEqual(actual.map { $0.issues.map(\.id) }, expected.map { $0.issues.map(\.id) }, line: line)
        XCTAssertEqual(file.reading.reviewEvents.map { $0.issues.map(\.id) },
                       ScriptReviewEvent.forListening(file.script.transcript.reviewIssues.filter { $0.status == .open }).map { $0.issues.map(\.id) }, line: line)
    }

    func testReuseAndExternalChangesWithUnchangedRevisionInvalidateSnapshot() async throws {
        let (folder, store, script) = try setup(), url = folder.appendingPathComponent("script.dama.json")
        let saved = try await store.saveScript(script, to: url, expectedHash: nil)
        let first = try await store.scripts(in: folder)
        let second = try await store.scripts(in: folder)
        XCTAssertTrue(saved.reading === first[0].reading)
        XCTAssertTrue(first[0].reading === second[0].reading)
        let original = try NormalizedTranscriptCodec.encode(script.transcript)

        // An external editor need not follow our revision convention.
        var external = script
        external.turnTexts["t1"] = "외부 수정"
        external.turnNames["t1"] = "외부 이름"
        external.paragraphBreaks = ["t2": true]
        XCTAssertEqual(external.revisionID, script.revisionID)
        try JSONEncoder().encode(external).write(to: url, options: .atomic)
        let changed = try await store.scripts(in: folder)[0]
        XCTAssertFalse(saved.reading === changed.reading)
        XCTAssertNotEqual(changed.hash, saved.hash)
        XCTAssertTrue(changed.reading.blocks.contains { $0.text == "외부 수정" && $0.name == "외부 이름" })
        try assertProjection(changed)
        XCTAssertEqual(try NormalizedTranscriptCodec.encode(changed.script.transcript), original)
        do { _ = try await store.saveScript(script, to: url, expectedHash: saved.hash); XCTFail("stale save") }
        catch LibraryFailure.changedFile {}
        do { try await store.exportMarkdown(saved, to: folder.appendingPathComponent("stale.md")); XCTFail("stale export") }
        catch LibraryFailure.changedFile {}
        let reopened = try await FolderLibraryStore(root: folder.appendingPathComponent("internal")).scripts(in: folder)[0]
        try assertProjection(reopened)
        XCTAssertEqual(reopened.reading.blocks.map(\.text), changed.reading.blocks.map(\.text))

        // Warm cache must not mask duplicate IDs, malformed bytes, or a folder switch.
        let duplicate = folder.appendingPathComponent("duplicate.dama.json")
        try FileManager.default.copyItem(at: url, to: duplicate)
        do { _ = try await store.scripts(in: folder); XCTFail("duplicate") } catch LibraryFailure.invalidScript {}
        try FileManager.default.removeItem(at: duplicate)
        try Data("invalid".utf8).write(to: url)
        do { _ = try await store.scripts(in: folder); XCTFail("malformed") } catch is DecodingError {}
        try JSONEncoder().encode(external).write(to: url)
        let other = folder.appendingPathComponent("Other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let empty = try await store.scripts(in: other)
        XCTAssertTrue(empty.isEmpty)
        let returned = try await store.scripts(in: folder)[0]
        XCTAssertFalse(changed.reading === returned.reading)
        try assertProjection(returned)
    }

    func testSavedEditsCorrectionOriginalViewAndManualBoundaryReplaceSnapshot() async throws {
        let (folder, store, script) = try setup(), url = folder.appendingPathComponent("script.dama.json")
        var file = try await store.saveScript(script, to: url, expectedHash: nil)
        let source = file
        let original = try NormalizedTranscriptCodec.encode(script.transcript)
        for change: (inout LibraryScript) throws -> Void in [
            { try $0.editText("t1", text: "사람이 수정한 말") },
            { try $0.rename("t1", name: "새 이름", scope: .all) },
            { try $0.setParagraphBreak(before: "t2", split: true) },
            { try $0.setParagraphBreak(before: "t2", split: nil) }
        ] {
            var candidate = file.script; try change(&candidate)
            let saved = try await store.saveScript(candidate, to: url, expectedHash: file.hash)
            XCTAssertFalse(saved.reading === file.reading)
            try assertProjection(saved); file = saved
        }
        // A correction arriving from the pre-edit file must merge into the latest human layer.
        var correction = ScriptCorrection(input: script.input, engine: "synthetic", state: .completed)
        correction.speakerNames = [script.transcript.turns[1].speakerId!: "AI 이름"]
        let merged = try await store.saveCorrection(correction, for: source)
        XCTAssertEqual(merged.script.turnTexts["t1"], "사람이 수정한 말")
        XCTAssertTrue(merged.reading.blocks.contains { $0.name == "AI 이름" })
        try assertProjection(merged)
        var shown = merged.script; shown.showsOriginal = true; shown.revisionID = UUID().uuidString
        let originalView = try await store.saveScript(shown, to: url, expectedHash: merged.hash)
        XCTAssertFalse(originalView.reading.blocks.contains { $0.name == "AI 이름" })
        XCTAssertTrue(originalView.reading.blocks.contains { $0.name == "새 이름" && $0.text == "사람이 수정한 말" })
        try assertProjection(originalView)
        XCTAssertEqual(try NormalizedTranscriptCodec.encode(originalView.script.transcript), original)
        let markdown = folder.appendingPathComponent("current.md")
        try await store.exportMarkdown(originalView, to: markdown)
        XCTAssertEqual(try Data(contentsOf: markdown), try originalView.script.markdown())
    }
}

import CryptoKit
import Foundation
import XCTest
@testable import DamaCore
@testable import DamaAudio

/// library-loading AC-03/04: persistent Script summaries and lazy Script loading.
final class ScriptSummaryCacheTests: XCTestCase {
    private func setup() throws -> (folder: URL, root: URL, model: TranscriptDocument) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        var fixture = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { fixture.deleteLastPathComponent() }
        let model = try JSONDecoder().decode(TranscriptDocument.self,
            from: Data(contentsOf: fixture.appendingPathComponent("fixtures/normalized-transcript.json")))
        return (folder, folder.appendingPathComponent("internal"), model)
    }

    private func script(_ model: TranscriptDocument, title: String) throws -> LibraryScript {
        var transcript = model
        transcript.runId = UUID().uuidString; transcript.revision.sourceRunId = transcript.runId
        return try LibraryScript(transcript: transcript, title: title, recordedAt: nil, dateSource: "합성", input: ConversionNotes())
    }

    private func hashes(_ folder: URL) throws -> [String: String] {
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasSuffix(".dama.json") }
        return try Dictionary(uniqueKeysWithValues: files.map {
            ($0.lastPathComponent, SHA256.hash(data: try Data(contentsOf: $0)).map { String(format: "%02x", $0) }.joined())
        })
    }

    private func twoScripts() async throws -> (folder: URL, root: URL, model: TranscriptDocument, a: LibraryScriptFile, b: LibraryScriptFile) {
        let (folder, root, model) = try setup()
        let writer = FolderLibraryStore(root: root)
        let a = try await writer.saveScript(try script(model, title: "가"), to: folder.appendingPathComponent("a.dama.json"), expectedHash: nil)
        let b = try await writer.saveScript(try script(model, title: "나"), to: folder.appendingPathComponent("b.dama.json"), expectedHash: nil)
        _ = try await writer.scanScriptSummaries(in: folder)
        return (folder, root, model, a, b)
    }

    func testNewStoreListsUnchangedScriptsWithoutDecoding() async throws {
        let (folder, root, _, a, b) = try await twoScripts()
        let store = FolderLibraryStore(root: root)
        let scan = try await store.scanScriptSummaries(in: folder)
        XCTAssertEqual(scan.issues.count, 0)
        XCTAssertEqual(Set(scan.items.map(\.id)), [a.id, b.id])
        XCTAssertEqual(scan.items.first { $0.id == a.id }?.hash, a.hash)
        XCTAssertEqual(scan.items.first { $0.id == a.id }?.title, "가")
        let decodes = await store.scriptDecodeCount
        XCTAssertEqual(decodes, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("library-script-summaries.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("library-script-summaries.json").path))
    }

    func testChangedBytesAreDecodedOnceAndCached() async throws {
        let (folder, root, _, a, _) = try await twoScripts()
        var external = a.script
        external.turnTexts["t1"] = "외부 수정"   // same revisionID, different bytes
        try JSONEncoder().encode(external).write(to: a.url, options: .atomic)
        let first = FolderLibraryStore(root: root)
        let scan = try await first.scanScriptSummaries(in: folder)
        let firstDecodes = await first.scriptDecodeCount
        XCTAssertEqual(firstDecodes, 1)
        XCTAssertNotEqual(scan.items.first { $0.id == a.id }?.hash, a.hash)
        let second = FolderLibraryStore(root: root)
        _ = try await second.scanScriptSummaries(in: folder)
        let secondDecodes = await second.scriptDecodeCount
        XCTAssertEqual(secondDecodes, 0)
    }

    func testCorruptOrOlderCacheIsIgnoredAndRebuilt() async throws {
        let (folder, root, _, _, _) = try await twoScripts()
        let cache = root.appendingPathComponent("library-script-summaries.json")
        for bytes in [Data("garbage".utf8), Data(#"{"version":0,"entries":[]}"#.utf8)] {
            try bytes.write(to: cache)
            let store = FolderLibraryStore(root: root)
            let scan = try await store.scanScriptSummaries(in: folder)
            let decodes = await store.scriptDecodeCount
            XCTAssertEqual(scan.items.count, 2)
            XCTAssertEqual(decodes, 2)
            let rebuilt = FolderLibraryStore(root: root)
            _ = try await rebuilt.scanScriptSummaries(in: folder)
            let rebuiltDecodes = await rebuilt.scriptDecodeCount
            XCTAssertEqual(rebuiltDecodes, 0)
        }
    }

    func testDuplicateMalformedAndSymlinkedFilesAreStillReported() async throws {
        let (folder, root, _, a, _) = try await twoScripts()
        let store = FolderLibraryStore(root: root)
        let duplicate = folder.appendingPathComponent("dup.dama.json")
        try FileManager.default.copyItem(at: a.url, to: duplicate)
        var scan = try await store.scanScriptSummaries(in: folder)
        XCTAssertFalse(scan.items.contains { $0.id == a.id })
        XCTAssertEqual(scan.issues.filter { $0.reason == .duplicateIdentity }.count, 2)
        try FileManager.default.removeItem(at: duplicate)

        try Data("invalid".utf8).write(to: folder.appendingPathComponent("bad.dama.json"))
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("link.dama.json"), withDestinationURL: a.url)
        scan = try await store.scanScriptSummaries(in: folder)
        XCTAssertEqual(scan.items.count, 2)
        XCTAssertEqual(Set(scan.issues.map(\.url.lastPathComponent)), ["bad.dama.json", "link.dama.json"])
    }

    func testLoadScriptRehashesAndRejectsChangedBytes() async throws {
        let (folder, root, _, a, _) = try await twoScripts()
        let store = FolderLibraryStore(root: root)
        let listed = try await store.scanScriptSummaries(in: folder).items
        let summary = try XCTUnwrap(listed.first { $0.id == a.id })
        let loaded = try await store.loadScript(summary)
        XCTAssertEqual(loaded.hash, a.hash)
        XCTAssertEqual(loaded.script.title, "가")
        _ = try await store.loadScript(summary)
        let decodes = await store.scriptDecodeCount
        XCTAssertEqual(decodes, 1, "second load reuses the opened file")

        var external = a.script; external.turnTexts["t1"] = "외부 수정"
        try JSONEncoder().encode(external).write(to: a.url, options: .atomic)
        do { _ = try await store.loadScript(summary); XCTFail("stale summary") } catch LibraryFailure.changedFile {}
    }

    func testScansNeverModifyScriptBytes() async throws {
        let (folder, root, _, _, _) = try await twoScripts()
        let before = try hashes(folder)
        for _ in 0..<2 { _ = try await FolderLibraryStore(root: root).scanScriptSummaries(in: folder) }
        XCTAssertEqual(try hashes(folder), before)
    }

    func testMergeSaveDoesNotDecodeOtherScripts() async throws {
        let (folder, root, _, a, b) = try await twoScripts()
        let store = FolderLibraryStore(root: root)
        let listed = try await store.scanScriptSummaries(in: folder).items
        let summary = try XCTUnwrap(listed.first { $0.id == a.id })
        let opened = try await store.loadScript(summary)
        let afterOpen = await store.scriptDecodeCount
        let renamed = try await store.saveTitle("가 수정", for: opened)
        XCTAssertEqual(renamed.script.title, "가 수정")
        let afterSave = await store.scriptDecodeCount
        XCTAssertEqual(afterSave, afterOpen, "the unopened Script \(b.id) is listed from its summary")
        let next = try await FolderLibraryStore(root: root).scanScriptSummaries(in: folder)
        XCTAssertEqual(next.items.first { $0.id == a.id }?.title, "가 수정")
    }

    func testCreateScriptReturnsExistingResultFromSummary() async throws {
        let (folder, root, model) = try setup()
        let store = FolderLibraryStore(root: root)
        let speech = LibrarySpeech(id: model.sessionId, fileURL: folder.appendingPathComponent("s.m4a"), sourceHash: "x",
                                   title: "합성", recordedAt: nil, dateSource: "합성", durationUs: model.durationUs, notes: ConversionNotes())
        let created = try await store.createScript(model, speech: speech, input: ConversionNotes(), in: folder)
        let again = try await FolderLibraryStore(root: root).createScript(model, speech: speech, input: ConversionNotes(), in: folder)
        XCTAssertEqual(again.id, created.id)
        XCTAssertEqual(again.hash, created.hash)
        XCTAssertEqual(try hashes(folder).count, 1)
    }

    /// usage-bundle2 AC-07: 결과 보관 정리는 새 파일을 만든 경우에만 일어난다(기존 파일을 다시 열면 created = false).
    func testCreateScriptReportsWhetherItCreatedANewFile() async throws {
        let (folder, root, model) = try setup()
        let speech = LibrarySpeech(id: model.sessionId, fileURL: folder.appendingPathComponent("s.m4a"), sourceHash: "x",
                                   title: "합성", recordedAt: nil, dateSource: "합성", durationUs: model.durationUs, notes: ConversionNotes())
        let first = try await FolderLibraryStore(root: root).createScriptReportingNew(model, speech: speech, input: ConversionNotes(), in: folder)
        let second = try await FolderLibraryStore(root: root).createScriptReportingNew(model, speech: speech, input: ConversionNotes(), in: folder)
        XCTAssertTrue(first.created)
        XCTAssertFalse(second.created)
        XCTAssertEqual(second.file.hash, first.file.hash)
    }

    /// usage-bundle2 AC-03: summaryVersion 1 → 2 (hasHumanEdits 추가). 구 버전 캐시는 한 번 전량 해독한다.
    func testVersionOneCacheIsRebuiltOnceAndCarriesHumanEdits() async throws {
        let (folder, root, _, a, b) = try await twoScripts()
        var edited = a.script
        edited.revisionID = UUID().uuidString
        edited.turnNames[try XCTUnwrap(edited.transcript.turns.first?.id)] = "사람 이름"
        let writer = FolderLibraryStore(root: root)
        let saved = try await writer.saveScript(edited, to: a.url, expectedHash: a.hash)
        _ = try await writer.scanScriptSummaries(in: folder)
        XCTAssertEqual(FolderLibraryStore.summaryVersion, 2)
        let cache = root.appendingPathComponent("library-script-summaries.json")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: cache)) as? [String: Any])
        json["version"] = 1
        try JSONSerialization.data(withJSONObject: json).write(to: cache)
        let store = FolderLibraryStore(root: root)
        let scan = try await store.scanScriptSummaries(in: folder)
        let decodes = await store.scriptDecodeCount
        XCTAssertEqual(decodes, 2)
        XCTAssertEqual(scan.items.first { $0.id == saved.id }?.hasHumanEdits, true)
        XCTAssertEqual(scan.items.first { $0.id == b.id }?.hasHumanEdits, false)
        let again = FolderLibraryStore(root: root)
        let cached = try await again.scanScriptSummaries(in: folder)
        let againDecodes = await again.scriptDecodeCount
        XCTAssertEqual(againDecodes, 0)
        XCTAssertEqual(cached.items.first { $0.id == saved.id }?.hasHumanEdits, true)
    }
}

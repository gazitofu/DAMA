import CryptoKit
import DamaCore
import Foundation
import os
import XCTest
@testable import DamaAudio

/// usage-bundle2 AC-06: 결과 하나를 지우는 순서와 동반 정리.
final class ScriptRemovalTests: XCTestCase {
    private func setup() throws -> (folder: URL, root: URL, trash: URL, model: TranscriptDocument) {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = base.appendingPathComponent("Scripts"), trash = base.appendingPathComponent("Trash")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: base) }
        var repo = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { repo.deleteLastPathComponent() }
        let model = try JSONDecoder().decode(TranscriptDocument.self,
            from: Data(contentsOf: repo.appendingPathComponent("fixtures/normalized-transcript.json")))
        return (folder, base.appendingPathComponent("internal"), trash, model)
    }
    private func manifest(_ folder: URL) -> [String: String] {
        var result: [String: String] = [:]
        let base = folder.standardizedFileURL.resolvingSymlinksInPath().path
        let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey])
        while let url = walker?.nextObject() as? URL {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true, let data = try? Data(contentsOf: url) else { continue }
            result[String(url.standardizedFileURL.resolvingSymlinksInPath().path.dropFirst(base.count))] =
                SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
        return result
    }
    private func two(_ folder: URL, _ root: URL, _ trash: URL, _ model: TranscriptDocument) async throws
        -> (store: FolderLibraryStore, a: LibraryScriptFile, b: LibraryScriptFile) {
        let store = FolderLibraryStore(root: root) { url in
            try FileManager.default.moveItem(at: url, to: trash.appendingPathComponent(url.lastPathComponent))
        }
        func make(_ name: String) async throws -> LibraryScriptFile {
            var transcript = model
            transcript.runId = UUID().uuidString; transcript.revision.sourceRunId = transcript.runId
            let script = try LibraryScript(transcript: transcript, title: name, recordedAt: nil, dateSource: "합성", input: ConversionNotes())
            let saved = try await store.saveScript(script, to: folder.appendingPathComponent(name + ".dama.json"), expectedHash: nil)
            let title = try await store.saveTitle(name + " 2", for: saved)   // 이력 2개
            try Data(#"{"synthetic":true}"#.utf8).write(to: try InternalStoragePaths.correctionAttemptURL(root: root, scriptID: title.id).creatingFolder())
            return title
        }
        return (store, try await make("a"), try await make("b"))
    }

    func testRemovalOrderTrashThenChildRegistrationThenHistoryAndAttempt() async throws {
        let (folder, root, trash, model) = try setup()
        let (store, a, b) = try await two(folder, root, trash, model)
        let sessions = root.appendingPathComponent("Sessions/x"); try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try Data("run".utf8).write(to: sessions.appendingPathComponent("state.json"))
        let otherBefore = manifest(root.appendingPathComponent("LibraryRevisions/\(b.id)"))
        let sessionsBefore = manifest(root.appendingPathComponent("Sessions"))
        XCTAssertEqual(otherBefore.count, 2)
        let log = OSAllocatedUnfairLock(initialState: [String]())
        let historyFolder = root.appendingPathComponent("LibraryRevisions/\(a.id)")
        let attempt = try InternalStoragePaths.correctionAttemptURL(root: root, scriptID: a.id)
        let summary = LibraryScriptSummary(try await store.loadScript(LibraryScriptSummary(a)))
        let removal = await store.removeScript(summary, in: folder, isChildResult: true) { id in
            // 등록 시점: 휴지통 이동은 끝났고 이력은 아직 있다.
            log.withLock { $0.append("register \(id) trashed=\(!FileManager.default.fileExists(atPath: a.url.path)) history=\(FileManager.default.fileExists(atPath: historyFolder.path))") }
        }
        XCTAssertEqual(removal, .removed)
        XCTAssertEqual(log.withLock { $0 }, ["register \(a.id) trashed=true history=true"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: historyFolder.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: attempt.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: trash.appendingPathComponent(a.url.lastPathComponent).path))
        XCTAssertEqual(manifest(root.appendingPathComponent("LibraryRevisions/\(b.id)")), otherBefore)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try InternalStoragePaths.correctionAttemptURL(root: root, scriptID: b.id).path))
        XCTAssertEqual(manifest(root.appendingPathComponent("Sessions")), sessionsBefore)
    }

    func testTrashFailureLeavesHistoryAttemptAndRegistrationUntouched() async throws {
        let (folder, root, trash, model) = try setup()
        let (store, a, _) = try await two(folder, root, trash, model)
        let stale = LibraryScriptSummary(a)
        try Data("외부 변경".utf8).write(to: a.url)   // 목록을 읽은 때와 해시가 다르다.
        let before = manifest(root)
        let removal = await store.removeScript(stale, in: folder, isChildResult: true) { _ in XCTFail("must not register") }
        XCTAssertEqual(removal, .trashFailed)
        XCTAssertEqual(manifest(root), before)
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.url.path))
    }

    func testNonChildIsNotRegistered() async throws {
        let (folder, root, trash, model) = try setup()
        let (store, a, _) = try await two(folder, root, trash, model)
        let removal = await store.removeScript(LibraryScriptSummary(a), in: folder, isChildResult: false) { _ in XCTFail("not a child") }
        XCTAssertEqual(removal, .removed)
    }

    func testAttemptPathRuleIsShared() throws {
        let root = URL(fileURLWithPath: "/tmp/dama-root")
        XCTAssertEqual(try InternalStoragePaths.correctionAttemptURL(root: root, scriptID: "ABC-1").path, "/tmp/dama-root/CorrectionAttempts/ABC-1.json")
        XCTAssertThrowsError(try InternalStoragePaths.correctionAttemptURL(root: root, scriptID: "../x"))
    }
}

private extension URL {
    func creatingFolder() throws -> URL {
        try FileManager.default.createDirectory(at: deletingLastPathComponent(), withIntermediateDirectories: true)
        return self
    }
}

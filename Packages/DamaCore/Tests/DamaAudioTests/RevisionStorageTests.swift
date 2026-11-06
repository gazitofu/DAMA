import CryptoKit
import DamaCore
import Foundation
import XCTest
@testable import DamaAudio

/// usage-bundle2 AC-05: 수정 이력 새 배치·raw DEFLATE·구 배치 읽기.
final class RevisionStorageTests: XCTestCase {
    private func setup() throws -> (folder: URL, root: URL, model: TranscriptDocument) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        var repo = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { repo.deleteLastPathComponent() }
        let model = try JSONDecoder().decode(TranscriptDocument.self,
            from: Data(contentsOf: repo.appendingPathComponent("fixtures/normalized-transcript.json")))
        return (folder, folder.appendingPathComponent("internal"), model)
    }
    private func files(_ folder: URL) -> [String] {
        let base = folder.standardizedFileURL.resolvingSymlinksInPath().path
        let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey])
        var result: [String] = []
        while let url = walker?.nextObject() as? URL {
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                result.append(String(url.standardizedFileURL.resolvingSymlinksInPath().path.dropFirst(base.count)))
            }
        }
        return result.sorted()
    }
    private func sha(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    func testSaveWritesOneCompressedRevisionPerScriptFolderAndPlainActiveFile() async throws {
        let (folder, root, model) = try setup()
        let script = try LibraryScript(transcript: model, title: "합성", recordedAt: nil, dateSource: "합성", input: ConversionNotes())
        let saved = try await FolderLibraryStore(root: root).saveScript(script, to: folder.appendingPathComponent("a.dama.json"), expectedHash: nil)
        let revisions = files(root.appendingPathComponent("LibraryRevisions"))
        XCTAssertEqual(revisions, ["/\(script.id)/\(script.revisionID).dama.json.deflate"])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let sorted = try encoder.encode(script)
        XCTAssertEqual(try Data(contentsOf: saved.url), sorted)   // Scripts 활성 파일은 압축하지 않는다.
        let stored = try Data(contentsOf: root.appendingPathComponent("LibraryRevisions\(revisions[0])"))
        XCTAssertEqual(try RevisionCodec.inflate(stored), sorted)
        XCTAssertLessThan(stored.count, sorted.count)
    }

    /// 단위 고정: raw DEFLATE(zlib 머리 0x78 없음), 왕복 동일.
    func testRawDeflateRoundTripHasNoZlibHeader() throws {
        let bytes = Data(String(repeating: #"{"text":"합성 이력","n":1}"#, count: 200).utf8)
        let stored = try RevisionCodec.deflate(bytes)
        XCTAssertNotEqual(stored.first, 0x78)
        XCTAssertEqual(try RevisionCodec.inflate(stored), bytes)
        XCTAssertThrowsError(try RevisionCodec.inflate(Data("not deflate at all".utf8))) { XCTAssertTrue($0 is LibraryFailure) }
    }

    func testRevisionPathsRequireUUIDs() async throws {
        let (_, root, _) = try setup()
        let store = FolderLibraryStore(root: root)
        let id = UUID().uuidString
        // 스크립트 ID = 경로 안전 문자 규칙(InternalStoragePaths), revisionID = UUID.
        let fixtureID = try await store.revisionURL(scriptID: "run-fixture-001", revisionID: id)
        XCTAssertEqual(fixtureID.deletingLastPathComponent().lastPathComponent, "run-fixture-001")
        for (script, revision) in [("../escape", id), ("a/b", id), ("", id), (id, "../escape"), (id, "not-a-uuid")] {
            do { _ = try await store.revisionURL(scriptID: script, revisionID: revision); XCTFail("unsafe") }
            catch { XCTAssertEqual(error as? LibraryFailure, .unsafePath) }
        }
        do { _ = try await store.legacyRevisionURL("x"); XCTFail("unsafe") }
        catch { XCTAssertEqual(error as? LibraryFailure, .unsafePath) }
    }

    func testNewFileIsCreatedWithoutOverwritingAndLeavesNoTemporaryFile() throws {
        let (folder, _, _) = try setup()
        let target = folder.appendingPathComponent("x/y.dama.json.deflate")
        try RevisionCodec.writeNew(Data("first".utf8), to: target)
        XCTAssertThrowsError(try RevisionCodec.writeNew(Data("second".utf8), to: target))
        XCTAssertEqual(try Data(contentsOf: target), Data("first".utf8))
        XCTAssertEqual(files(folder.appendingPathComponent("x")), ["/y.dama.json.deflate"])
    }

    func testSameRevisionIDWithDifferentBytesIsRejectedInBothLayouts() async throws {
        let (folder, root, model) = try setup()
        let store = FolderLibraryStore(root: root)
        let script = try LibraryScript(transcript: model, title: "합성", recordedAt: nil, dateSource: "합성", input: ConversionNotes())
        let saved = try await store.saveScript(script, to: folder.appendingPathComponent("a.dama.json"), expectedHash: nil)
        var conflicting = saved.script; conflicting.title = "같은 revisionID 다른 내용"
        do { _ = try await store.saveScript(conflicting, to: saved.url, expectedHash: saved.hash); XCTFail("new layout conflict") }
        catch { XCTAssertEqual(error as? LibraryFailure, .changedFile) }
        // 구 배치에만 있는 같은 revisionID도 같은 검사를 받는다.
        let newURL = try await store.revisionURL(scriptID: script.id, revisionID: script.revisionID)
        let legacyURL = try await store.legacyRevisionURL(script.revisionID)
        try RevisionCodec.inflate(Data(contentsOf: newURL)).write(to: legacyURL)
        try FileManager.default.removeItem(at: newURL)
        do { _ = try await store.saveScript(conflicting, to: saved.url, expectedHash: saved.hash); XCTFail("legacy conflict") }
        catch { XCTAssertEqual(error as? LibraryFailure, .changedFile) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: newURL.path))
    }

    /// 구 배치로 만든 AI 버전은 새 배치로 옮긴 뒤에도 같은 sha256로 열린다(Scripts 파일 무변경).
    func testLegacyVersionReadsBeforeAndAfterMigrationWithSameFingerprint() async throws {
        let (folder, root, model) = try setup()
        let store = FolderLibraryStore(root: root)
        let first = try await store.saveScript(try LibraryScript(transcript: model, title: "합성", recordedAt: nil, dateSource: "합성",
                                                                 input: ConversionNotes()), to: folder.appendingPathComponent("a.dama.json"), expectedHash: nil)
        var correction = ScriptCorrection(input: first.script.input, engine: "synthetic", state: .completed)
        correction.completedAt = Date()
        let completed = try await store.saveCorrection(correction, for: first)
        let version = try XCTUnwrap(completed.script.versions?.last)
        let activeBytes = try Data(contentsOf: completed.url)
        let newURL = try await store.revisionURL(scriptID: completed.id, revisionID: version.revisionID)
        let legacyURL = try await store.legacyRevisionURL(version.revisionID)
        let plain = try RevisionCodec.inflate(Data(contentsOf: newURL))
        XCTAssertEqual(sha(plain), version.sha256)          // sha256 = 압축을 푼 바이트
        // 구 배치 상태로 되돌린다(이 유닛 전 저장분과 같은 모양).
        try plain.write(to: legacyURL); try FileManager.default.removeItem(at: newURL)
        let fromLegacy = try await store.readVersion(version, for: completed)
        XCTAssertEqual(fromLegacy.url.standardizedFileURL, legacyURL.standardizedFileURL)
        XCTAssertEqual(fromLegacy.hash, version.sha256)
        // 새 배치가 있으면 새 배치를 먼저 읽는다.
        try RevisionCodec.writeNew(RevisionCodec.deflate(plain), to: newURL)
        let fromNew = try await store.readVersion(version, for: completed)
        XCTAssertEqual(fromNew.url.standardizedFileURL, newURL.standardizedFileURL)
        XCTAssertEqual(fromNew.script.revisionID, version.revisionID)
        // 둘 다 없으면 오류이며 현재 내용으로 대체하지 않는다.
        try FileManager.default.removeItem(at: newURL); try FileManager.default.removeItem(at: legacyURL)
        do { _ = try await store.readVersion(version, for: completed); XCTFail("missing") } catch {}
        XCTAssertEqual(try Data(contentsOf: completed.url), activeBytes)
    }
}

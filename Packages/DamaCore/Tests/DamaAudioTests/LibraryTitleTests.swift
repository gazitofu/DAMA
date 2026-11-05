import CryptoKit
import DamaCore
import Foundation
import XCTest
@testable import DamaAudio

/// usage-bundle1 AC-05·AC-06: 녹음 표시 제목 데이터·해석. 합성 저장소만 쓴다.
final class LibraryTitleTests: XCTestCase {
    private func setup() throws -> (folder: URL, root: URL, model: TranscriptDocument) {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = base.appendingPathComponent("Scripts"), root = base.appendingPathComponent("internal")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: base) }
        var fixture = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { fixture.deleteLastPathComponent() }
        let model = try JSONDecoder().decode(TranscriptDocument.self,
            from: Data(contentsOf: fixture.appendingPathComponent("fixtures/normalized-transcript.json")))
        return (folder, root, model)
    }
    private func speech(_ id: String, title: String = "자동 제목", display: String? = nil, file: String = "missing.m4a") -> LibrarySpeech {
        var value = LibrarySpeech(id: id, fileURL: URL(fileURLWithPath: "/nonexistent/\(file)"), sourceHash: "h-\(id)", title: title,
                                  recordedAt: Date(timeIntervalSince1970: 0), dateSource: "합성", durationUs: 1_000_000, notes: ConversionNotes())
        value.displayTitle = display
        return value
    }
    private func writeIndex(_ entries: [LibrarySpeech], root: URL) throws {
        try JSONEncoder().encode(entries).write(to: root.appendingPathComponent("library-index.json"))
    }
    /// 폴더 아래 모든 파일의 상대 경로 → SHA256.
    private func manifest(_ folder: URL) throws -> [String: String] {
        var result: [String: String] = [:]
        let base = folder.standardizedFileURL.resolvingSymlinksInPath().path
        let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey])!
        for case let url as URL in walker where (try url.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true {
            let path = url.standardizedFileURL.resolvingSymlinksInPath().path
            result[String(path.dropFirst(base.count))] = SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
        }
        return result
    }
    private func changed(_ before: [String: String], _ after: [String: String]) -> [String] {
        Set(before.keys).union(after.keys).filter { before[$0] != after[$0] }.sorted()
    }

    func testOldIndexEntryDecodesWithoutDisplayTitleAndRoundTripsBytes() throws {
        // 인덱스 쓰기(JSONEncoder 기본)는 키 순서가 실행마다 달라 바이트 비교 자로 쓸 수 없다. 키 정렬 인코더로 왕복 바이트를 본다.
        let canonical = JSONEncoder(); canonical.outputFormatting = [.sortedKeys]
        let old = try canonical.encode([speech("a")])
        let keys = try XCTUnwrap((try JSONSerialization.jsonObject(with: old) as? [[String: Any]])?.first?.keys)
        XCTAssertEqual(Set(keys), ["dateSource", "durationUs", "fileURL", "id", "notes", "recordedAt", "sourceHash", "title"])
        let decoded = try JSONDecoder().decode([LibrarySpeech].self, from: old)
        XCTAssertNil(decoded[0].displayTitle)
        XCTAssertEqual(try canonical.encode(decoded), old)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(decoded), as: UTF8.self).contains("displayTitle"))
        let titled = try JSONEncoder().encode([speech("a", display: "표시")])
        let titledKeys = try XCTUnwrap((try JSONSerialization.jsonObject(with: titled) as? [[String: Any]])?.first?.keys)
        XCTAssertEqual(titledKeys.count, 9)
        XCTAssertEqual(try JSONDecoder().decode([LibrarySpeech].self, from: titled)[0].displayTitle, "표시")
    }

    func testSaveDisplayTitleUpdatesEverySameIDEntryAndKeepsInputAsIs() async throws {
        let (_, root, _) = try setup()
        try writeIndex([speech("a", file: "a1.m4a"), speech("b"), speech("a", file: "a2.m4a")], root: root)
        let store = FolderLibraryStore(root: root)
        let saved = try await store.saveDisplayTitle("  투자 검토 회의 ", speechID: "a")
        XCTAssertEqual(saved.displayTitle, "  투자 검토 회의 ")
        let index = try JSONDecoder().decode([LibrarySpeech].self, from: Data(contentsOf: root.appendingPathComponent("library-index.json")))
        XCTAssertEqual(index.map(\.displayTitle), ["  투자 검토 회의 ", nil, "  투자 검토 회의 "])
        XCTAssertEqual(index.map(\.title), ["자동 제목", "자동 제목", "자동 제목"])
        do { _ = try await store.saveDisplayTitle(" \n ", speechID: "a"); XCTFail("blank") }
        catch { XCTAssertEqual(error as? LibraryFailure, .invalidInput) }
        do { _ = try await store.saveDisplayTitle("제목", speechID: "zzz"); XCTFail("missing") }
        catch { XCTAssertEqual(error as? LibraryFailure, .missingFile) }
        let titles = try await store.displayTitles()
        XCTAssertEqual(titles, ["a": "  투자 검토 회의 "])
    }

    func testDisplayTitleWritesOnlyTheIndexWhileScriptTitleWritesFileAndRevision() async throws {
        let (folder, root, model) = try setup()
        let entry = speech(model.sessionId)
        try writeIndex([entry], root: root)
        let store = FolderLibraryStore(root: root)
        let created = try await store.createScript(model, speech: entry, input: ConversionNotes(), in: folder)
        let before = (try manifest(root), try manifest(folder))
        _ = try await store.saveDisplayTitle("녹음 제목", speechID: model.sessionId)
        let after = (try manifest(root), try manifest(folder))
        XCTAssertEqual(changed(before.0, after.0), ["/library-index.json"])
        XCTAssertEqual(changed(before.1, after.1), [])
        XCTAssertTrue(before.0.keys.contains { $0.hasPrefix("/LibraryRevisions/") }) // 양성 대조: 사본 폴더가 모집단에 있다.
        // 기준선: 현행 스크립트 제목 저장 1회 = 스크립트 파일 1 + 사본 1.
        _ = try await store.saveTitle("파일 제목", for: created)
        let titled = (try manifest(root), try manifest(folder))
        XCTAssertEqual(changed(after.1, titled.1).count, 1)
        XCTAssertEqual(changed(after.0, titled.0).filter { $0.hasPrefix("/LibraryRevisions/") }.count, 1)
        XCTAssertEqual(changed(after.0, titled.0).filter { !$0.hasPrefix("/LibraryRevisions/") }, ["/library-script-summaries.json"]) // 목록 캐시
    }

    func testDisplayTitlesIncludeIndexEntriesWhoseFilesAreMissing() async throws {
        let (_, root, _) = try setup()
        try writeIndex([speech("trashed", display: "휴지통 녹음"), speech("plain")], root: root)
        let titles = try await FolderLibraryStore(root: root).displayTitles()
        XCTAssertEqual(titles, ["trashed": "휴지통 녹음"])
    }

    func testIndexedIDsCoverUntitledEntriesAndMarkdownExportUsesResolvedTitle() async throws {
        let (folder, root, model) = try setup()
        try writeIndex([speech(model.sessionId), speech("trashed", display: "휴지통")], root: root)
        let store = FolderLibraryStore(root: root)
        let ids = try await store.indexedSpeechIDs()
        XCTAssertEqual(ids, [model.sessionId, "trashed"])
        let file = try await store.createScript(model, speech: speech(model.sessionId), input: ConversionNotes(), in: folder)
        let out = folder.deletingLastPathComponent().appendingPathComponent("out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try await store.exportMarkdown(file, title: "해석한 제목", to: out.appendingPathComponent("a.md"))
        try await store.exportMarkdown(file, to: out.appendingPathComponent("b.md"))
        let first = { (name: String) in String(decoding: try Data(contentsOf: out.appendingPathComponent(name)), as: UTF8.self).components(separatedBy: "\n").first }
        XCTAssertEqual(try first("a.md"), "# 해석한 제목")
        XCTAssertEqual(try first("b.md"), "# 자동 제목")
    }

    func testResolutionCases() throws {
        let (_, _, model) = try setup()
        let titles = ["linked": "녹음 표시 제목", "trashed": "휴지통 녹음 제목"]
        // 녹음 쪽.
        XCTAssertEqual(LibraryTitles.speech(speech("linked", display: "녹음 표시 제목")), "녹음 표시 제목")
        XCTAssertEqual(LibraryTitles.speech(speech("none")), "자동 제목")
        // 1. 연결 + displayTitle.
        XCTAssertEqual(LibraryTitles.script(fileTitle: "파일 제목", sessionID: "linked", displayTitles: titles), "녹음 표시 제목")
        // 2. 연결 + displayTitle 없음 (인덱스 항목은 있으나 표시 제목 없음) → 파일 제목.
        XCTAssertEqual(LibraryTitles.script(fileTitle: "파일 제목", sessionID: "none", displayTitles: titles), "파일 제목")
        // 3. 미연결 → 파일 제목.
        XCTAssertEqual(LibraryTitles.script(fileTitle: "파일 제목", sessionID: "other", displayTitles: [:]), "파일 제목")
        // 4. Speech 휴지통(인덱스만 있음) → 표시 제목.
        XCTAssertEqual(LibraryTitles.script(fileTitle: "파일 제목", sessionID: "trashed", displayTitles: titles), "휴지통 녹음 제목")
        // 5. AI 버전 보기 → 스냅숏 파일 제목 그대로.
        var transcript = model; transcript.sessionId = "linked"
        var script = try LibraryScript(transcript: transcript, title: "당시 제목", recordedAt: nil, dateSource: "합성", input: ConversionNotes())
        XCTAssertEqual(LibraryTitles.script(script, displayTitles: titles), "녹음 표시 제목")
        script.snapshotTitle = "AI 보정 1"
        XCTAssertEqual(LibraryTitles.script(script, displayTitles: titles), "당시 제목")
    }

    func testCreateScriptUsesResolvedSpeechTitle() async throws {
        let (folder, root, model) = try setup()
        let store = FolderLibraryStore(root: root)
        let titled = try await store.createScript(model, speech: speech(model.sessionId, display: "녹음 표시 제목"), input: ConversionNotes(), in: folder)
        XCTAssertEqual(titled.script.title, "녹음 표시 제목")
        var second = model; second.runId = UUID().uuidString; second.revision.sourceRunId = second.runId
        let plain = try await store.createScript(second, speech: speech(model.sessionId), input: ConversionNotes(), in: folder)
        XCTAssertEqual(plain.script.title, "자동 제목")
    }
}

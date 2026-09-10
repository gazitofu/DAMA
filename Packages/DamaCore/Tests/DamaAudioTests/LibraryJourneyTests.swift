import AVFoundation
import DamaCore
import XCTest
@testable import DamaAudio

final class LibraryJourneyTests: XCTestCase {
    func testABACAScopeUsesIdentityNotDisplayName() throws {
        let labels = ["SPEAKER_00", "SPEAKER_01", "SPEAKER_00", "SPEAKER_02", "SPEAKER_00"]
        let intervals: [[String: Any]] = labels.enumerated().map { ["start": Double($0.offset), "end": Double($0.offset + 1), "speaker": $0.element] }
        let words: [[String: Any]] = labels.enumerated().map { ["start": Double($0.offset), "end": Double($0.offset) + 0.8, "speaker": $0.element, "text": "대사\($0.offset)"] }
        let bytes = try JSONSerialization.data(withJSONObject: ["jobId":"synthetic", "status":"succeeded", "output":["diarization":intervals, "exclusiveDiarization":intervals, "wordLevelTranscription":words]])
        let document = try ManagedNormalizer.normalize(bytes, sessionID: "synthetic", runID: "synthetic", durationUs: 5_000_000,
            audioSHA256: String(repeating: "a", count: 64), synthetic: true, createdAt: "2026-09-10T00:00:00Z")
        var script = try LibraryScript(transcript: document, title: "합성", recordedAt: nil, dateSource: "미확인", input: ConversionNotes())
        let turns = document.turns.filter { $0.kind == .speech }
        XCTAssertEqual(turns.count, 5)
        let id = turns[2].id
        XCTAssertEqual(script.affectedTurns(id, scope: .one), [id])
        XCTAssertEqual(script.affectedTurns(id, scope: .from), [id, turns[4].id])
        XCTAssertEqual(script.affectedTurns(id, scope: .all), [turns[0].id, id, turns[4].id])
        try script.rename(turns[1].id, name: "동명", scope: .all)
        try script.rename(id, name: "동명", scope: .one)
        try script.rename(id, name: "새 이름", scope: .all)
        XCTAssertEqual(script.name(for: turns[1]), "동명")
        XCTAssertEqual(script.name(for: turns[4]), "새 이름")
        XCTAssertTrue(String(decoding: try script.markdown(), as: UTF8.self).contains("자동 (미입력)"))
    }
    private func root() throws -> URL {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: path) }
        return path
    }
    private func fixture() throws -> TranscriptDocument {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return try JSONDecoder().decode(TranscriptDocument.self, from: Data(contentsOf: url.appendingPathComponent("fixtures/normalized-transcript.json")))
    }
    func testScopedNamesTextTitleRoundtripAndMarkdown() async throws {
        let directory = try root(), model = try fixture()
        let raw = try JSONEncoder().encode(model)
        var script = try LibraryScript(transcript: model, title: "대화", recordedAt: Date(timeIntervalSince1970: 0),
            dateSource: "테스트 녹음", timeZoneID: "Asia/Seoul",
            input: ConversionNotes(speakerCount: 3, context: "제품 *논의*", reference: "용어\n[링크](test)"))
        XCTAssertEqual(script.affectedTurns("t2", scope: .one), ["t2"])
        XCTAssertEqual(script.affectedTurns("t2", scope: .from), ["t2"])
        XCTAssertEqual(script.affectedTurns("t2", scope: .all), ["t1", "t2"])
        try script.rename("t2", name: "민수", scope: .one)
        XCTAssertNil(script.turnNames["t1"])
        try script.rename("t1", name: "지수", scope: .from)
        XCTAssertEqual(script.turnNames, ["t1":"지수", "t2":"지수"])
        XCTAssertEqual(script.affectedTurns("t3", scope: .all), ["t3"])
        try script.renameTitle("수정 제목 #1")
        try script.editText("t2", text: "바뀐 말\n다음 줄")
        let store = FolderLibraryStore(root: directory.appendingPathComponent("internal"))
        let url = directory.appendingPathComponent("script.dama.json")
        let saved = try await store.saveScript(script, to: url, expectedHash: nil)
        let loaded = try await store.scripts(in: directory)
        XCTAssertEqual(loaded.count, 1)
        let duplicate = directory.appendingPathComponent("duplicate.dama.json")
        try FileManager.default.copyItem(at: url, to: duplicate)
        do { _ = try await store.scripts(in: directory); XCTFail("ambiguous duplicate script IDs must not select an arbitrary file") } catch {}
        try FileManager.default.removeItem(at: duplicate)
        XCTAssertEqual(loaded[0].script.turnTexts["t2"], "바뀐 말\n다음 줄")
        // Compare semantic raw model fields without relying on JSON dictionary key ordering.
        XCTAssertEqual(try JSONSerialization.jsonObject(with: raw) as? NSDictionary,
                       try JSONSerialization.jsonObject(with: JSONEncoder().encode(loaded[0].script.transcript)) as? NSDictionary)
        let md = directory.appendingPathComponent("export.md")
        try await store.exportMarkdown(saved, to: md)
        let text = try String(contentsOf: md, encoding: .utf8)
        for value in ["수정 제목 \\#1", "1970-01-01 09:00:00 +09:00", "Asia/Seoul", "참여 화자 수: 3", "제품 \\*논의\\*", "용어\n\\[링크\\]", "지수", "바뀐 말\n다음 줄", "전사 누락"] { XCTAssertTrue(text.contains(value), value) }
        XCTAssertEqual(LibraryScript.timestamp(850_000), "00:00:00.850")
        XCTAssertEqual(LibraryScript.timestamp(nil), "시간 미확인")
        try Data("external edit".utf8).write(to: url)
        do { _ = try await store.saveScript(script, to: url, expectedHash: saved.hash); XCTFail("must preserve external edits") } catch {}
    }
    func testFolderImportSortNotesAndReopen() async throws {
        let directory = try root(), folder = directory.appendingPathComponent("Speeches")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000)!
        pcm.frameLength = 16_000; pcm.floatChannelData![0].initialize(repeating: 0, count: 16_000)
        for (name, time) in [("older", 100.0), ("newer", 200.0)] {
            let url = folder.appendingPathComponent(name + ".wav")
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: pcm); file.close()
            try FileManager.default.setAttributes([.creationDate: Date(timeIntervalSince1970: time)], ofItemAtPath: url.path)
        }
        let internalRoot = directory.appendingPathComponent("internal")
        let store = FolderLibraryStore(root: internalRoot)
        let first = try await store.speeches(in: folder)
        XCTAssertEqual(first.map(\.title), ["newer", "older"])
        let notes = ConversionNotes(speakerCount: nil, context: "맥락", reference: "참고")
        try await store.saveNotes(notes, speechID: first[0].id)
        let next = try await FolderLibraryStore(root: internalRoot).speeches(in: folder)
        XCTAssertEqual(next[0].id, first[0].id)
        XCTAssertEqual(next[0].notes, notes)
        XCTAssertEqual(next[0].durationUs, 1_000_000)
        XCTAssertThrowsError(try FolderLibraryStore.validateFolder(folder, other: folder, internalRoot: internalRoot))
        XCTAssertThrowsError(try ConversionNotes(speakerCount: 0).validate())
    }
}

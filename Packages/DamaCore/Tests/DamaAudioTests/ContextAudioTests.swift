import Foundation
import XCTest
import DamaCore
@testable import DamaAudio

final class ContextAudioTests: XCTestCase {
    @MainActor func testZeroLengthAndEventContextListeningKeepsOriginalRangeContract() throws {
        XCTAssertEqual(try SegmentPlayback.listeningRange(startUs: 850_000, endUs: 3_000_000, duration: 10), 0.85...3)
        XCTAssertEqual(try SegmentPlayback.listeningRange(startUs: 5_000_000, endUs: 5_000_000, duration: 10), 3...7)
        XCTAssertEqual(try SegmentPlayback.listeningRange(startUs: 0, endUs: 0, duration: 10), 0...2)
        XCTAssertEqual(try SegmentPlayback.listeningRange(startUs: 10_000_000, endUs: 10_000_000, duration: 10), 8...10)
        XCTAssertEqual(try SegmentPlayback.listeningRange(startUs: 850_000, endUs: 3_000_000, duration: 4, context: true), 0...4)
        XCTAssertThrowsError(try SegmentPlayback.listeningRange(startUs: nil, endUs: 0, duration: 10))
        XCTAssertThrowsError(try SegmentPlayback.listeningRange(startUs: 2, endUs: 1, duration: 10))
        XCTAssertThrowsError(try SegmentPlayback.listeningRange(startUs: 11_000_000, endUs: 11_000_000, duration: 10))
        XCTAssertThrowsError(try SegmentPlayback.listeningRange(startUs: 0, endUs: 0, duration: 0))
        XCTAssertThrowsError(try SegmentPlayback.range(startUs: 5_000_000, endUs: 5_000_000, duration: 10))
    }
    func testCorrectionDiskSaveMergesHumanChangesAndDetectsChangedSource() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var fixture = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { fixture.deleteLastPathComponent() }
        let model = try JSONDecoder().decode(TranscriptDocument.self, from: Data(contentsOf: fixture.appendingPathComponent("fixtures/normalized-transcript.json")))
        var script = try LibraryScript(transcript: model, title: "합성 저장", recordedAt: nil, dateSource: "합성", input: ConversionNotes())
        let store = FolderLibraryStore(root: directory.appendingPathComponent("internal"))
        let file = try await store.saveScript(script, to: directory.appendingPathComponent("script.dama.json"), expectedHash: nil)
        let chunk = try XCTUnwrap(ContextCorrection.chunks(script).first)
        let reply = try JSONDecoder().decode(CorrectionReply.self, from: JSONSerialization.data(withJSONObject: [
            "turns": chunk.turns.map { ["id": $0.id, "text": $0.text + ".", "certain": true, "reason": "합성 구두점 교정"] as [String: Any] }, "names": []]))
        var correction = ScriptCorrection(input: script.input, engine: "synthetic", state: .completed)
        correction.edits = try ContextCorrection.validated(reply, chunk: chunk, input: script.input).edits
        try script.editText(chunk.turns[0].id, text: "교정 작업 중 사람이 수정한 내용")
        _ = try await store.saveScript(script, to: file.url, expectedHash: file.hash)
        let merged = try await store.saveCorrection(correction, for: file)
        XCTAssertEqual(merged.script.turnTexts[chunk.turns[0].id], "교정 작업 중 사람이 수정한 내용")
        let reopened = try await FolderLibraryStore(root: directory.appendingPathComponent("internal")).scripts(in: directory)
        XCTAssertEqual(reopened[0].script.correction?.edits.count, correction.edits.count)
        let exported = directory.appendingPathComponent("export.md")
        try await store.exportMarkdown(merged, to: exported)
        XCTAssertTrue(try String(contentsOf: exported, encoding: .utf8).contains("교정 작업 중 사람이 수정한 내용"))
        var changedModel = model; changedModel.durationUs += 1
        let changed = try LibraryScript(transcript: changedModel, title: "바뀐 원문", recordedAt: nil, dateSource: "합성", input: ConversionNotes())
        _ = try await store.saveScript(changed, to: file.url, expectedHash: merged.hash)
        do { _ = try await store.saveCorrection(correction, for: file); XCTFail("changed normalized source must not receive an old correction") }
        catch { XCTAssertTrue(error is LibraryFailure) }
    }
    func testSelectedReferenceFolderLimitsAndSymlinkExclusion() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("예시회사 고유명사 정의\n\n프로젝트 단어장".utf8).write(to: folder.appendingPathComponent("glossary.md"))
        try Data("비밀".utf8).write(to: folder.appendingPathComponent(".hidden.txt"))
        try Data("실행하지 말 것".utf8).write(to: folder.appendingPathComponent("script.sh"))
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("linked.txt"), withDestinationURL: folder.appendingPathComponent("glossary.md"))
        try Data(repeating: 65, count: 200_001).write(to: folder.appendingPathComponent("large.md"))
        let result = try await ReferenceFolder().excerpts(in: folder, query: "예시회사")
        XCTAssertEqual(result.map(\.name), ["glossary.md"])
        XCTAssertEqual(result[0].sha256.count, 64); XCTAssertTrue(result[0].text.contains("고유명사"))
    }
    @MainActor func testPlaybackRangeAndStopWithoutRecordingOrAudioOutput() throws {
        XCTAssertEqual(try SegmentPlayback.range(startUs: 850_000, endUs: 3_000_000, duration: 2), 0.85...2)
        XCTAssertThrowsError(try SegmentPlayback.range(startUs: nil, endUs: 2, duration: 3))
        XCTAssertThrowsError(try SegmentPlayback.range(startUs: 3_000_000, endUs: 3_000_000, duration: 3))
        let playback = SegmentPlayback(); playback.stop(); XCTAssertNil(playback.playingID)
    }
}

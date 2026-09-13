import Foundation
import XCTest
@testable import DamaCore

final class ScriptPeopleAndDeletionTests: XCTestCase {
    private func source() throws -> LibraryScript {
        let tokens: [[String: Any]] = [("첫 발화", "C"), (" 다른 발화", "B"), (" 다시 발화", "C"), (" 미배정", ""), (" 별개 미배정", "")].enumerated().map { i, item in
            ["text": item.0, "speaker": item.1.isEmpty ? NSNull() : item.1 as Any, "start_ms": i * 1000, "end_ms": i * 1000 + 500]
        }
        let data = try JSONSerialization.data(withJSONObject: ["id": "j", "text": tokens.map { $0["text"] as! String }.joined(), "tokens": tokens])
        let model = try SonioxNormalizer.normalize(data, jobID: "j", sessionID: "s", runID: UUID().uuidString,
            durationUs: 6_000_000, audioSHA256: String(repeating: "a", count: 64), synthetic: true, createdAt: "2026-09-13T00:00:00Z")
        return try LibraryScript(transcript: model, title: "합성 화자·삭제", recordedAt: nil, dateSource: "합성", input: ConversionNotes())
    }
    private func roundtrip(_ script: LibraryScript) throws -> LibraryScript {
        let loaded = try JSONDecoder().decode(LibraryScript.self, from: JSONEncoder().encode(script))
        try loaded.validate(); return loaded
    }
    func testRegisteredSpeakerCanBeSelectedForUnknownWithSameIdentityAndColor() throws {
        var script = try source()
        let fingerprint = try script.sourceFingerprint(), original = script.blocks()
        try script.rename(original[0], name: "이석훈 상무", scope: .all)
        let person = try XCTUnwrap(script.availableSpeakers.first)
        XCTAssertEqual(script.blocks()[2].name, person.name)
        let unknown = script.blocks()[3]
        try script.rename(unknown, name: person.name, scope: .one)
        let loaded = try roundtrip(script), blocks = loaded.blocks()
        XCTAssertEqual(loaded.registeredSpeakers?.count, 1)
        XCTAssertEqual(loaded.registeredSpeaker(for: blocks[0].speakerTurnID)?.id, loaded.registeredSpeaker(for: blocks[3].speakerTurnID)?.id)
        XCTAssertEqual(blocks[0].name, blocks[3].name)
        XCTAssertEqual(blocks[0].colorIndex, blocks[3].colorIndex)
        XCTAssertNil(blocks[3].speakerID)
        XCTAssertNil(loaded.registeredSpeaker(for: blocks[4].speakerTurnID))
        XCTAssertEqual(try loaded.sourceFingerprint(), fingerprint)
        XCTAssertTrue(String(decoding: try loaded.markdown(), as: UTF8.self).contains("이석훈 상무"))
        XCTAssertTrue(try source().availableSpeakers.isEmpty)
    }
    func testRegisteredScopeIncludesManuallyAssignedUnknownAndPreservesSourceBoundaries() throws {
        var script = try source()
        try script.rename(script.blocks()[0], name: "동일 인물", scope: .all)
        try script.rename(script.blocks()[3], name: "동일 인물", scope: .one)
        XCTAssertEqual(script.blocks().count, 5)
        try script.rename(script.blocks()[3], name: "수정 이름", scope: .all)
        XCTAssertEqual(script.blocks().map(\.name), ["수정 이름", "Speaker B", "수정 이름", "수정 이름", "화자 미확정"])
        try script.rename(script.blocks()[2], name: "부분 이름", scope: .from)
        XCTAssertEqual(script.blocks()[0].name, "수정 이름")
        XCTAssertEqual(script.blocks()[3].name, "부분 이름")
        XCTAssertEqual(script.blocks()[4].name, "화자 미확정")
        try script.validate()
    }
    func testLegacyNamesAreSelectableAndMalformedRegistryIsRejected() throws {
        var script = try source()
        let first = script.blocks()[0], unknown = script.blocks()[3]
        try script.rename(first.speakerTurnID, name: "기존 이름", scope: .all)
        XCTAssertNil(script.registeredSpeakers)
        XCTAssertEqual(script.availableSpeakers.map(\.name), ["기존 이름"])
        try script.rename(unknown, name: "기존 이름", scope: .one)
        XCTAssertEqual(script.registeredSpeaker(for: first.speakerTurnID)?.id, script.registeredSpeaker(for: unknown.speakerTurnID)?.id)
        var invalid = script
        invalid.turnSpeakerIDs?[first.speakerTurnID] = UUID().uuidString
        XCTAssertThrowsError(try invalid.validate())
        invalid = script; invalid.registeredSpeakers! += invalid.registeredSpeakers!
        XCTAssertThrowsError(try invalid.validate())
        invalid = script; invalid.deletedParagraphs = [ScriptDeletedParagraph(id: UUID().uuidString, turnIDs: [first.turnIDs[0], unknown.turnIDs[0]])]
        XCTAssertThrowsError(try invalid.validate())
    }
    func testDeleteAfterManualMergePersistsAndUndoRestoresHumanTextWithoutJoiningNeighbors() throws {
        var script = try source()
        let fingerprint = try script.sourceFingerprint()
        try script.editParagraph(script.blocks()[1], text: "삭제할 사람이 수정한 문장")
        let removed = script.blocks()[1], removedIDs = Set(removed.turnIDs)
        try script.editParagraph(script.blocks()[0], text: "사용자가 합친 문장 전체")
        try script.deleteParagraph(removed)
        var loaded = try roundtrip(script)
        XCTAssertEqual(loaded.blocks().count, 4)
        XCTAssertEqual(loaded.blocks()[0].text, "사용자가 합친 문장 전체")
        XCTAssertEqual(loaded.blocks()[1].text, "다시 발화")
        XCTAssertEqual(loaded.deletedTurnIDs, removedIDs)
        let markdown = String(decoding: try loaded.markdown(), as: UTF8.self)
        XCTAssertFalse(markdown.contains("삭제할 사람이"))
        for chunk in try ContextCorrection.chunks(loaded) {
            XCTAssertTrue(removedIDs.isDisjoint(with: chunk.turns.map(\.id)))
            XCTAssertTrue(removedIDs.isDisjoint(with: (chunk.humanParagraphs ?? []).flatMap(\.turnIDs)))
            XCTAssertTrue(removedIDs.isDisjoint(with: chunk.contextBefore.map(\.id) + chunk.contextAfter.map(\.id)))
        }
        try loaded.undoParagraphDeletion()
        XCTAssertEqual(loaded.blocks()[1].text, removed.text)
        XCTAssertEqual(loaded.blocks()[0].text, "사용자가 합친 문장 전체")
        XCTAssertEqual(try loaded.sourceFingerprint(), fingerprint)
    }
    func testAllDeletedCanBeRestoredAndHistoricalOrStaleDeletionFails() throws {
        var script = try source()
        let original = script.blocks(), old = original[0]
        try script.rename(old, name: "변경됨", scope: .one)
        XCTAssertThrowsError(try script.deleteParagraph(old))
        for block in script.blocks() { try script.deleteParagraph(block) }
        var loaded = try roundtrip(script)
        XCTAssertTrue(loaded.blocks().isEmpty)
        XCTAssertTrue(try ContextCorrection.chunks(loaded).isEmpty)
        XCTAssertFalse(String(decoding: try loaded.markdown(), as: UTF8.self).contains("첫 발화"))
        while loaded.deletedParagraphs?.isEmpty == false { try loaded.undoParagraphDeletion() }
        XCTAssertEqual(loaded.blocks().map(\.text), original.map(\.text))
        loaded.snapshotTitle = "과거 결과"
        XCTAssertThrowsError(try loaded.deleteParagraph(loaded.blocks()[0]))
    }
}

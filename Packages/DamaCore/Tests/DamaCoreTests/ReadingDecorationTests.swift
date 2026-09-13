import Foundation
import XCTest
@testable import DamaCore

final class ReadingDecorationTests: XCTestCase {
    private func script(_ items: [(String, Int, Int, String?)]) throws -> LibraryScript {
        let tokens: [[String: Any]] = items.map { ["text": $0.0, "start_ms": $0.1, "end_ms": $0.2, "speaker": $0.3 as Any? ?? NSNull()] }
        let raw = try JSONSerialization.data(withJSONObject: ["id": "job", "text": items.map(\.0).joined(), "tokens": tokens])
        var doc = try SonioxNormalizer.normalize(raw, jobID: "job", sessionID: "s", runID: "r", durationUs: 4_000_000,
            audioSHA256: String(repeating: "a", count: 64), synthetic: true, createdAt: "2026-09-13T00:00:00Z")
        doc.turns = doc.words.enumerated().map { i, w in TranscriptTurn(id: "t\(i)", kind: .speech,
            startUs: w.startUs, endUs: w.endUs, speakerId: w.speakerId, wordIds: [w.id], markerText: nil,
            reviewed: false, reviewIssueIds: w.reviewIssueIds) }
        return try LibraryScript(transcript: doc, title: "합성 부호", recordedAt: nil, dateSource: "합성", input: ConversionNotes())
    }

    func testUnknownSubwordAndPeriodFormOneEditableWordWithoutAttribution() throws {
        var value = try script([("이", 30, 30, nil), ("거", 90, 150, nil), (".", 150, 210, nil), (" 다음", 510, 600, "B")])
        let original = try value.sourceFingerprint(), blocks = value.blocks()
        XCTAssertEqual(blocks.map(\.text), ["이거.", "다음"])
        XCTAssertNil(blocks[0].speakerID)
        XCTAssertEqual(blocks[0].endUs, 150_000)
        try value.editParagraph(blocks[0], text: "사람 수정")
        let loaded = try JSONDecoder().decode(LibraryScript.self, from: JSONEncoder().encode(value))
        try loaded.validate()
        XCTAssertEqual(loaded.blocks()[0].text, "사람 수정")
        XCTAssertEqual(try loaded.sourceFingerprint(), original)
        XCTAssertTrue(String(decoding: try loaded.markdown(), as: UTF8.self).contains("사람 수정"))
        XCTAssertTrue(loaded.transcript.words.prefix(3).allSatisfy { $0.speakerId == nil })
    }

    func testPunctuationTimingAndLabelCannotCreateSpeechOrMoveItsPlaybackRange() throws {
        let value = try script([("질문", 100, 500, "A"), ("?", 1500, 1560, "B"), (" 답", 1000, 1200, "B")])
        XCTAssertEqual(value.blocks().map(\.text), ["질문?", "답"])
        XCTAssertEqual(value.blocks().map(\.startUs), [100_000, 1_000_000])
        XCTAssertEqual(value.blocks().map(\.endUs), [500_000, 1_200_000])
        XCTAssertNotEqual(value.blocks()[0].speakerID, value.blocks()[1].speakerID)
        XCTAssertEqual(value.transcript.words[1].startUs, 1_500_000)
    }

    func testOpeningAndClosingMarksUseLexicalAnchorForRenameAndHumanAIContext() throws {
        var value = try script([("(", 0, 0, nil), ("본문", 100, 300, "A"), (")", 300, 400, "B"), (" 답", 500, 600, "B")])
        let block = value.blocks()[0]
        XCTAssertEqual(value.blocks().map(\.text), ["(본문)", "답"])
        XCTAssertEqual(block.speakerTurnID, "t1")
        XCTAssertEqual(block.speakerID, value.transcript.words[1].speakerId)
        XCTAssertEqual(value.affectedTurns(in: block, scope: .all), ["t0", "t1", "t2"])
        try value.rename(block, name: "사람 이름", scope: .all)
        try value.editParagraph(value.blocks()[0], text: "확정 문단")
        try value.validate()
        let context = try ContextCorrection.chunks(value).first?.humanParagraphs?.first
        XCTAssertEqual(context?.speakerID, block.speakerID)
        XCTAssertEqual(value.blocks()[0].name, "사람 이름")
    }

    func testUnknownWordsAndRealSpeakerChangesStillHaveBoundaries() throws {
        let value = try script([("가", 0, 60, nil), ("나", 60, 120, nil), (" 다", 120, 180, nil),
                                (" A", 200, 300, "A"), (".", 300, 360, nil), (" B", 400, 500, "B"), (" A", 600, 700, "A")])
        XCTAssertEqual(value.blocks().map(\.text), ["가나", "다", "A.", "B", "A"])
        XCTAssertThrowsError(try { var s = value; try s.setParagraphBreak(before: "t2", split: false) }())
        let reversed = try script([("가", 500, 600, nil), ("나", 100, 200, nil)])
        XCTAssertEqual(reversed.blocks().count, 2)
    }

    func testExplicitHumanPunctuationAndParagraphOwnershipArePreserved() throws {
        var value = try script([("본문", 0, 100, "A"), (".", 100, 160, nil), (" 다음", 200, 300, "A")])
        try value.setParagraphBreak(before: "t1", split: true)
        try value.setParagraphBreak(before: "t2", split: true)
        XCTAssertEqual(value.blocks().map(\.text), ["본문", ".", "다음"])
        try value.editParagraph(value.blocks()[1], text: "사용자 별도 입력")
        let loaded = try JSONDecoder().decode(LibraryScript.self, from: JSONEncoder().encode(value))
        try loaded.validate()
        XCTAssertEqual(loaded.blocks().map(\.text), ["본문", "사용자 별도 입력", "다음"])
        let punctuationOnly = try script([(".", 0, 60, nil), ("?", 60, 120, nil)])
        XCTAssertTrue(punctuationOnly.blocks().isEmpty)
        XCTAssertEqual(punctuationOnly.transcript.words.count, 2)
    }
}

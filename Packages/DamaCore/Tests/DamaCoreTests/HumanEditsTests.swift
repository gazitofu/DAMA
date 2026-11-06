import Foundation
import XCTest
@testable import DamaCore

/// usage-bundle2 AC-03: 결과 보관의 «사람 수정 판정» (library-script.md «결과 보관»).
final class HumanEditsTests: XCTestCase {
    private func source(_ edit: (inout TranscriptDocument) -> Void = { _ in }) throws -> LibraryScript {
        let tokens: [[String: Any]] = [("첫 발화", "A"), (" 다른 발화", "B"), (" 다시 발화", "A")].enumerated().map { i, item in
            ["text": item.0, "speaker": item.1, "start_ms": i * 1000, "end_ms": i * 1000 + 500]
        }
        let data = try JSONSerialization.data(withJSONObject: ["id": "j", "text": tokens.map { $0["text"] as! String }.joined(), "tokens": tokens])
        let model = try SonioxNormalizer.normalize(data, jobID: "j", sessionID: "s", runID: UUID().uuidString,
            durationUs: 4_000_000, audioSHA256: String(repeating: "a", count: 64), synthetic: true, createdAt: "2026-11-06T00:00:00Z")
        var transcript = model
        edit(&transcript)
        return try LibraryScript(transcript: transcript, title: "합성 사람 수정", recordedAt: nil, dateSource: "합성", input: ConversionNotes())
    }

    func testEachOfNineFieldsAndLegacyMarkersCountAsHumanEdits() throws {
        let base = try source()
        let turn = try XCTUnwrap(base.transcript.turns.first { $0.kind == .speech })
        XCTAssertFalse(base.hasHumanEdits)
        let cases: [(String, (inout LibraryScript) -> Void)] = [
            ("turnTexts", { $0.turnTexts[turn.id] = "사람 문장" }),
            ("turnNames", { $0.turnNames[turn.id] = "사람 이름" }),
            ("turnSpeakerIDs", { $0.turnSpeakerIDs = [turn.id: "p1"] }),
            ("registeredSpeakers", { $0.registeredSpeakers = [ScriptSpeaker(id: "p1", name: "등록", colorIndex: 0)] }),
            ("nameHistory", { $0.nameHistory = [ScriptNameChange(id: "h1", name: "이름", turnIDs: [turn.id], previousNames: [:],
                                                                  previousSpeakerIDs: [:], addedSpeakerID: nil)] }),
            ("deletedParagraphs", { $0.deletedParagraphs = [ScriptDeletedParagraph(id: "d1", turnIDs: [turn.id])] }),
            ("paragraphBreaks", { $0.paragraphBreaks = [turn.id: true] }),
            ("paragraphEdits", { $0.paragraphEdits = [ScriptParagraphEdit(id: "e1", turnIDs: [turn.id], sourceSHA256: String(repeating: "b", count: 64),
                                                                          baseRevisionID: UUID().uuidString, baseTextSHA256: String(repeating: "c", count: 64), text: "편집")] }),
            ("reviewRecords", { script in
                let before = script
                try? script.recordReview(before: before, turnIDs: [turn.id])
            }),
        ]
        for (name, apply) in cases {
            var script = base
            apply(&script)
            XCTAssertTrue(script.hasHumanEdits, name)
        }
        XCTAssertTrue(try source { $0.revision.humanEdited = true }.hasHumanEdits, "revision.humanEdited")
        XCTAssertTrue(try source { $0.words[0].editedText = "고친 단어"; $0.words[0].timingOrigin = .inheritedUnaligned }.hasHumanEdits, "word.editedText")
        XCTAssertEqual(cases.count, 9)
    }

    func testTitleOriginalToggleAndAICorrectionAloneAreNotHumanEdits() throws {
        let base = try source()
        var titled = base; titled.title = "제목만 바꿈"
        var toggled = base; toggled.showsOriginal = true
        var corrected = base; corrected.correction = ScriptCorrection(input: base.input, engine: "synthetic", state: .completed)
        var emptied = base
        emptied.turnSpeakerIDs = [:]; emptied.registeredSpeakers = []; emptied.nameHistory = []; emptied.deletedParagraphs = []
        emptied.paragraphBreaks = [:]; emptied.paragraphEdits = []; emptied.reviewRecords = []
        for (name, script) in [("none", base), ("title", titled), ("showsOriginal", toggled), ("correction", corrected), ("empty collections", emptied)] {
            XCTAssertFalse(script.hasHumanEdits, name)
        }
    }
}

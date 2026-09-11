import Foundation
import XCTest
@testable import DamaCore

final class LibraryPresentationTests: XCTestCase {
    func testExplicitSentenceEndDoesNotTreatEllipsisOrDecimalAsCompletion() {
        for text in ["완료했습니다.", "완료했습니다.\"  ", "맞습니까?", "네!", "끝。"] {
            XCTAssertTrue(ScriptReadingPolicy.endsSentence(text), text)
        }
        for text in ["회사는", "그리고...", "음…", "3.", "", " "] {
            XCTAssertFalse(ScriptReadingPolicy.endsSentence(text), text)
        }
    }
    func testContinuousOverlapReadEditAndExportPreservesSpeakerTransitions() throws {
        let intervals: [[String: Any]] = [
            ["start": 0.0, "end": 1.5, "speaker": "A"],
            ["start": 0.0, "end": 0.95, "speaker": "B"],
            ["start": 1.0, "end": 1.1, "speaker": "B"]]
        let words: [[String: Any]] = [
            ["start": 0.2, "end": 0.4, "speaker": "A", "text": "첫"],
            ["start": 0.45, "end": 0.7, "speaker": "A", "text": "겹말"],
            ["start": 0.8, "end": 0.9, "speaker": "A", "text": "계속"],
            ["start": 1.0, "end": 1.1, "speaker": "B", "text": "네"],
            ["start": 1.2, "end": 1.4, "speaker": "A", "text": "다음"]]
        let exclusive: [[String: Any]] = [["start": 0.0, "end": 1.0, "speaker": "A"],
            ["start": 1.0, "end": 1.1, "speaker": "B"], ["start": 1.1, "end": 1.5, "speaker": "A"]]
        let bytes = try JSONSerialization.data(withJSONObject: ["jobId": "synthetic", "status": "succeeded", "output":
            ["diarization": intervals, "exclusiveDiarization": exclusive, "wordLevelTranscription": words]])
        let model = try ManagedNormalizer.normalize(bytes, sessionID: "synthetic", runID: "synthetic", durationUs: 2_000_000,
            audioSHA256: String(repeating: "a", count: 64), synthetic: true, createdAt: "2026-09-10T00:00:00Z")
        var script = try LibraryScript(transcript: model, title: "합성 겹말", recordedAt: nil, dateSource: "합성", input: ConversionNotes())
        let baseline = try JSONEncoder().encode(model)
        let blocks = script.blocks()
        XCTAssertEqual(blocks.map { $0.turns.count }, [3, 1, 1])
        XCTAssertEqual(blocks[0].text, "첫 겹말 계속")
        XCTAssertFalse(blocks[0].reviewEvents.isEmpty)
        XCTAssertEqual(blocks.flatMap { $0.turns.flatMap(\.wordIds) }, model.words.map(\.id))
        try script.rename(blocks[0], name: "합성 이름", scope: .one)
        try script.editText(blocks[0].turnIDs[1], text: "겹말 수정")
        let loaded = try JSONDecoder().decode(LibraryScript.self, from: JSONEncoder().encode(script))
        XCTAssertEqual(try JSONSerialization.jsonObject(with: JSONEncoder().encode(loaded.transcript)) as? NSDictionary,
                       try JSONSerialization.jsonObject(with: baseline) as? NSDictionary)
        let md = String(decoding: try loaded.markdown(), as: UTF8.self)
        XCTAssertTrue(md.contains("첫 겹말 수정 계속"))
        XCTAssertTrue(md.contains("overlapping\\_speech"))
        // B ending inside A's word is not a new intervening turn. Keep its warning.
        var ended = model
        ended.diarization[1].endUs = 600_000
        let changed = try LibraryScript(transcript: ended, title: "종료 경계", recordedAt: nil, dateSource: "합성", input: ConversionNotes())
        XCTAssertEqual(changed.blocks()[0].turns.count, 3)
        XCTAssertFalse(changed.blocks()[0].reviewEvents.isEmpty)
    }
    func testUnfinishedSentenceContinuesBeyondOldDurationAndPauseLimits() throws {
        let long = try script(Array(repeating: "A", count: 40))
        let blocks = long.blocks()
        XCTAssertEqual(blocks.map { $0.turns.count }, [40])
        XCTAssertEqual(blocks[0].endUs! - blocks[0].startUs!, 78_800_000)
        XCTAssertEqual(blocks.flatMap { $0.turns.flatMap(\.wordIds) }, long.transcript.words.map(\.id))
        var paused = try script(["A", "A"]).transcript
        paused.durationUs = 10_000_000
        paused.turns[1].startUs = 4_800_000; paused.turns[1].endUs = 5_600_000
        paused.words[1].startUs = 4_800_000; paused.words[1].endUs = 5_600_000
        let result = try LibraryScript(transcript: paused, title: "휴지", recordedAt: nil, dateSource: "합성", input: ConversionNotes())
        XCTAssertEqual(result.blocks().count, 1)
        XCTAssertEqual(result.blocks()[0].endUs, 5_600_000)
    }
    func testSentenceEndAndSpeakerChangeDriveReadAndExportBoundaries() throws {
        var value = try script(["A", "A", "A", "A", "B", "A"])
        let texts = ["이번에", "검토할 회사는", "다마입니다.", "다음으로", "네", "설명하겠습니다."]
        for i in texts.indices { try value.editText(value.transcript.turns[i].id, text: texts[i]) }
        let blocks = value.blocks()
        XCTAssertEqual(blocks.map(\.text), ["이번에 검토할 회사는 다마입니다.", "다음으로", "네", "설명하겠습니다."])
        XCTAssertEqual(blocks.map { $0.turns.count }, [3, 1, 1, 1])
        let loaded = try JSONDecoder().decode(LibraryScript.self, from: JSONEncoder().encode(value))
        let markdown = String(decoding: try loaded.markdown(), as: UTF8.self)
        XCTAssertTrue(markdown.contains("이번에 검토할 회사는 다마입니다\\."))
        XCTAssertEqual(markdown.components(separatedBy: "### [").count - 1, 4)
        XCTAssertEqual(loaded.blocks().flatMap { $0.turns.flatMap(\.wordIds) }, value.transcript.words.map(\.id))
    }
    func testSameSpeakerOverlappingWordTimesJoinWithoutChangingTiming() throws {
        var model = try script(["A", "A"]).transcript
        model.turns[1].startUs = 700_000; model.turns[1].endUs = 1_400_000
        model.words[1].startUs = 700_000; model.words[1].endUs = 1_400_000
        let value = try LibraryScript(transcript: model, title: "합성", recordedAt: nil, dateSource: "합성", input: ConversionNotes())
        XCTAssertEqual(value.blocks().count, 1)
        XCTAssertEqual(value.blocks()[0].endUs, 1_400_000)
        XCTAssertEqual(value.blocks()[0].turns.map(\.startUs), [0, 700_000])
    }
    func testReviewEventsCoalesceSharedRangesWithoutDroppingKindsOrUnknownTimes() {
        func issue(_ id: String, _ kind: IssueKind, _ start: Int64?, _ end: Int64?) -> ReviewIssue {
            ReviewIssue(id: id, kind: kind, startUs: start, endUs: end, severity: .warning, status: .open, wordIds: [], sourceIntervalIds: [])
        }
        let issues = [issue("a", .boundary_conflict, 0, 100), issue("b", .overlapping_speech, 0, 100),
                      issue("c", .invalid_timestamp, 100, 100), issue("d", .missing_speech, 200, 300),
                      issue("e", .partial_result, nil, nil)]
        let events = ScriptReviewEvent.grouped(issues.reversed())
        XCTAssertEqual(events.map { $0.issues.count }, [3, 1, 1])
        XCTAssertEqual(events[0].kinds.count, 3)
        XCTAssertEqual(events.flatMap(\.issues).map(\.id), issues.map(\.id))
        XCTAssertEqual(events[0].startUs, 0); XCTAssertEqual(events[0].endUs, 100)
        XCTAssertNil(events.last!.startUs)
    }
    private func script(_ labels: [String] = ["A", "A", "A", "B", "A"]) throws -> LibraryScript {
        let intervals: [[String: Any]] = labels.enumerated().map {
            ["start": Double($0.offset * 2), "end": Double($0.offset * 2 + 1), "speaker": $0.element]
        }
        let words: [[String: Any]] = labels.enumerated().map {
            ["start": Double($0.offset * 2), "end": Double($0.offset * 2) + 0.8, "speaker": $0.element, "text": "대사\($0.offset)"]
        }
        let bytes = try JSONSerialization.data(withJSONObject: ["jobId": "synthetic", "status": "succeeded", "output":
            ["diarization": intervals, "exclusiveDiarization": intervals, "wordLevelTranscription": words]])
        let model = try ManagedNormalizer.normalize(bytes, sessionID: "synthetic", runID: "synthetic", durationUs: Int64(labels.count * 2_000_000),
            audioSHA256: String(repeating: "a", count: 64), synthetic: true, createdAt: "2026-09-10T00:00:00Z")
        return try LibraryScript(transcript: model, title: "합성 묶음", recordedAt: nil, dateSource: "합성", input: ConversionNotes())
    }
    func testGroupedReadEditRenameRoundtripAndMarkdownJourney() throws {
        var script = try script()
        XCTAssertEqual(script.transcript.turns.count, 5)
        let original = try JSONSerialization.jsonObject(with: JSONEncoder().encode(script.transcript)) as! NSDictionary
        let blocks = script.blocks()
        XCTAssertEqual(blocks.map { $0.turns.count }, [3, 1, 1])
        XCTAssertEqual(blocks[0].startUs, 0); XCTAssertEqual(blocks[0].endUs, 4_800_000)
        XCTAssertEqual(blocks[0].text, "대사0 대사1 대사2")
        XCTAssertEqual(script.affectedTurns(in: blocks[0], scope: .one).count, 3)
        XCTAssertEqual(script.affectedTurns(in: blocks[0], scope: .all).count, 4)
        XCTAssertEqual(script.affectedTurns(in: blocks[2], scope: .from), blocks[2].turnIDs)
        let color = blocks[0].colorIndex
        try script.rename(blocks[0], name: "민수", scope: .one)
        XCTAssertEqual(script.blocks()[0].colorIndex, color)
        XCTAssertNotEqual(script.blocks()[2].name, "민수")
        try script.editText(blocks[0].turnIDs[1], text: "수정한 말")
        let loaded = try JSONDecoder().decode(LibraryScript.self, from: JSONEncoder().encode(script))
        let md = String(decoding: try loaded.markdown(), as: UTF8.self)
        XCTAssertTrue(md.contains("[00:00:00.000 – 00:00:04.800] 민수"))
        XCTAssertTrue(md.contains("대사0 수정한 말 대사2"))
        XCTAssertEqual(md.components(separatedBy: "### [").count - 1, 3)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: JSONEncoder().encode(loaded.transcript)) as? NSDictionary, original)
    }
    func testGroupingPreservesOtherSpeakerMissingUnknownTimeAndHumanBarriers() throws {
        let source = try script()
        func wrapped(_ model: TranscriptDocument) throws -> LibraryScript {
            try LibraryScript(transcript: model, title: "합성", recordedAt: nil, dateSource: "합성", input: ConversionNotes())
        }
        var model = source.transcript
        let b = model.speakers.first { $0.providerId == "B" }!.id
        // No B text or marker exists in this gap; the diarization itself must block A→A.
        model.diarization.append(DiarizationInterval(id: "hidden-b", startUs: 1_000_000, endUs: 1_100_000, speakerId: b, confidence: nil))
        XCTAssertEqual(try wrapped(model).blocks().map { $0.turns.count }, [1, 2, 1, 1])
        model = source.transcript
        model.turns.insert(TranscriptTurn(id: "missing", kind: .missingSpeech, startUs: 1_000_000, endUs: 1_100_000, speakerId: b,
            wordIds: [], markerText: "[누락]", reviewed: false, reviewIssueIds: []), at: 1)
        XCTAssertEqual(try wrapped(model).blocks().map { $0.turns.count }, [1, 1, 2, 1, 1])
        model = source.transcript
        model.turns[1].speakerId = nil
        model.words[1].speakerId = nil
        XCTAssertEqual(try wrapped(model).blocks().map { $0.turns.count }, [1, 1, 1, 1, 1])
        model = source.transcript
        model.turns[1].startUs = nil; model.turns[1].endUs = nil
        model.words[1].startUs = nil; model.words[1].endUs = nil; model.words[1].timingOrigin = .none
        XCTAssertEqual(try wrapped(model).blocks().count, 5)
        model = source.transcript; model.revision.humanEdited = true
        XCTAssertEqual(try wrapped(model).blocks().count, 5)
        var renamed = source
        try renamed.rename(source.transcript.turns[1].id, name: "별도 이름", scope: .one)
        XCTAssertEqual(renamed.blocks().count, 5)
    }
    func testTenStableColorsAndOnlyOpenEventIndicators() throws {
        var script = try script((0..<10).map { "speaker-\($0)" })
        XCTAssertEqual(Set(script.blocks().compactMap(\.colorIndex)).count, 10)
        XCTAssertNil(script.colorIndex(for: nil))
        let first = script.blocks()[0]
        try script.rename(first, name: "같은 이름", scope: .all)
        XCTAssertEqual(script.blocks()[0].colorIndex, first.colorIndex)
        var model = script.transcript
        model.reviewIssues.append(ReviewIssue(id: "event", kind: .capture_interrupted, startUs: nil, endUs: nil,
            severity: .warning, status: .open, wordIds: [], sourceIntervalIds: []))
        script = try LibraryScript(transcript: model, title: "합성", recordedAt: nil, dateSource: "합성", input: ConversionNotes())
        XCTAssertEqual(script.blocks().flatMap(\.openIssues).map(\.id), ["event"])
        model.reviewIssues[0].status = .acknowledged
        script = try LibraryScript(transcript: model, title: "합성", recordedAt: nil, dateSource: "합성", input: ConversionNotes())
        XCTAssertTrue(script.blocks().flatMap(\.openIssues).isEmpty)
        XCTAssertTrue(String(decoding: try script.markdown(), as: UTF8.self).contains("capture\\_interrupted"))
        model.reviewIssues[0].status = .open
        model.reviewIssues[0].startUs = model.durationUs; model.reviewIssues[0].endUs = model.durationUs
        script = try LibraryScript(transcript: model, title: "합성", recordedAt: nil, dateSource: "합성", input: ConversionNotes())
        XCTAssertTrue(script.blocks().first!.openIssues.isEmpty)
        XCTAssertEqual(script.blocks().last!.openIssues.map(\.id), ["event"])
    }
}

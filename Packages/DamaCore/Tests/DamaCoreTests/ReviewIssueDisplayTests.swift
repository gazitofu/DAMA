import Foundation
import XCTest
@testable import DamaCore

/// usage-bundle1 AC-02·AC-03: 자동 경고 분류, 문단 요약, Markdown 머리말·문단 줄. 전부 합성 데이터.
final class ReviewIssueDisplayTests: XCTestCase {
    private let autoKinds: [IssueKind] = [.ambiguous_speaker, .overlapping_speech, .missing_speech, .provider_disagreement,
                                          .boundary_conflict, .unrepresented_speaker, .invalid_timestamp, .low_confidence]

    /// 화자 A·B·C·D 네 문단. 두 번째 문단은 미배정(null)이다.
    private func base() throws -> TranscriptDocument {
        let labels = ["A", "B", "C", "D"]
        let intervals: [[String: Any]] = labels.enumerated().map {
            ["start": Double($0.offset * 2), "end": Double($0.offset * 2 + 1), "speaker": $0.element]
        }
        let words: [[String: Any]] = labels.enumerated().map {
            ["start": Double($0.offset * 2), "end": Double($0.offset * 2) + 0.8, "speaker": $0.element, "text": "대사\($0.offset)"]
        }
        let bytes = try JSONSerialization.data(withJSONObject: ["jobId": "synthetic", "status": "succeeded", "output":
            ["diarization": intervals, "exclusiveDiarization": intervals, "wordLevelTranscription": words]])
        var model = try ManagedNormalizer.normalize(bytes, sessionID: "synthetic", runID: "synthetic", durationUs: 8_000_000,
            audioSHA256: String(repeating: "a", count: 64), synthetic: true, createdAt: "2026-11-05T00:00:00Z")
        model.reviewIssues = []
        for index in model.turns.indices { model.turns[index].reviewIssueIds = [] }
        for index in model.words.indices { model.words[index].reviewIssueIds = [] }
        model.turns[1].speakerId = nil
        model.words[1].speakerId = nil
        return model
    }

    private func attach(_ model: inout TranscriptDocument, turn: Int, _ kind: IssueKind, status: IssueStatus = .open, id: String? = nil) {
        let issueID = id ?? "i-\(model.reviewIssues.count)"
        model.reviewIssues.append(ReviewIssue(id: issueID, kind: kind, startUs: model.turns[turn].startUs, endUs: model.turns[turn].endUs,
            severity: .warning, status: status, wordIds: [], sourceIntervalIds: []))
        model.turns[turn].reviewIssueIds.append(issueID)
    }

    /// 합성 Script 1개: 자동 경고 8종 · 녹음 중단 · 일부 결과 · 미배정 · acknowledged 1 · resolved 1.
    private func fixture() throws -> LibraryScript {
        var model = try base()
        // 문단 0: 8종 각 1건 + boundary 1 추가 (open 9).
        for kind in autoKinds { attach(&model, turn: 0, kind) }
        attach(&model, turn: 0, .boundary_conflict)
        // 문단 1 (미배정): overlapping 2 · boundary 2 (같은 건수) + acknowledged overlapping 1 + resolved boundary 1.
        attach(&model, turn: 1, .overlapping_speech); attach(&model, turn: 1, .overlapping_speech)
        attach(&model, turn: 1, .boundary_conflict); attach(&model, turn: 1, .boundary_conflict)
        attach(&model, turn: 1, .overlapping_speech, status: .acknowledged)
        attach(&model, turn: 1, .boundary_conflict, status: .resolved)
        // 문단 2: 녹음 중단 · 일부 결과만.
        attach(&model, turn: 2, .capture_interrupted, id: "cut"); attach(&model, turn: 2, .partial_result, id: "part")
        // 문단 3: 경고 없음.
        return try LibraryScript(transcript: model, title: "합성 경고", recordedAt: nil, dateSource: "합성", input: ConversionNotes())
    }

    func testAutoWarningClassificationIsEightKinds() {
        XCTAssertEqual(autoKinds.filter(\.isAutoWarning).count, 8)
        XCTAssertFalse(IssueKind.capture_interrupted.isAutoWarning)
        XCTAssertFalse(IssueKind.partial_result.isAutoWarning)
        XCTAssertEqual(Set(autoKinds.compactMap(\.markdownShortName)).count, 8)
        XCTAssertNil(IssueKind.capture_interrupted.markdownShortName)
        XCTAssertNil(IssueKind.overlapping_speech.persistentWarningText)
    }

    func testBlockSummaryCountsOpenAutoWarningsInOrder() throws {
        let blocks = try fixture().blocks()
        XCTAssertEqual(blocks.count, 4)
        XCTAssertNil(blocks[1].speakerID)
        // 문단 0: boundary 2가 맨 앞, 나머지 1건 종류는 rawValue 오름차순.
        XCTAssertEqual(blocks[0].autoWarningSummary.map(\.kind), [.boundary_conflict, .ambiguous_speaker, .invalid_timestamp,
            .low_confidence, .missing_speech, .overlapping_speech, .provider_disagreement, .unrepresented_speaker])
        XCTAssertEqual(blocks[0].autoWarningSummary.map(\.count), [2, 1, 1, 1, 1, 1, 1, 1])
        // 고정 사례: 같은 건수 2종 → boundary_conflict가 overlapping_speech보다 앞. acknowledged·resolved는 세지 않는다.
        XCTAssertEqual(blocks[1].autoWarningSummary.map(\.kind), [.boundary_conflict, .overlapping_speech])
        XCTAssertEqual(blocks[1].autoWarningSummary.map(\.count), [2, 2])
        for block in blocks {
            XCTAssertEqual(block.autoWarningSummary.reduce(0) { $0 + $1.count },
                           block.openIssues.filter(\.kind.isAutoWarning).count)
        }
        XCTAssertTrue(blocks[2].autoWarningSummary.isEmpty)
        XCTAssertTrue(blocks[3].autoWarningSummary.isEmpty)
        XCTAssertEqual(blocks[2].persistentWarnings.map(\.id), ["cut", "part"])
        XCTAssertTrue(blocks[0].persistentWarnings.isEmpty)
    }

    func testPersistentWarningsAreOpenOnly() throws {
        var model = try fixture().transcript
        model.reviewIssues[model.reviewIssues.firstIndex { $0.id == "cut" }!].status = .acknowledged
        let script = try LibraryScript(transcript: model, title: "합성", recordedAt: nil, dateSource: "합성", input: ConversionNotes())
        XCTAssertEqual(script.blocks()[2].persistentWarnings.map(\.id), ["part"])
        // Markdown은 상태와 무관하게 남긴다.
        let md = String(decoding: try script.markdown(), as: UTF8.self)
        XCTAssertEqual(md.components(separatedBy: "\n").filter { $0.hasPrefix("> 녹음 중단: ") }.count, 1)
    }

    func testGroupingIsLocaleFree() {
        XCTAssertEqual(ReviewIssueFormat.grouped(0), "0")
        XCTAssertEqual(ReviewIssueFormat.grouped(999), "999")
        XCTAssertEqual(ReviewIssueFormat.grouped(1_000), "1,000")
        XCTAssertEqual(ReviewIssueFormat.grouped(1_402), "1,402")
        XCTAssertEqual(ReviewIssueFormat.grouped(54_221), "54,221")
        XCTAssertEqual(ReviewIssueFormat.grouped(1_234_567), "1,234,567")
    }

    func testMarkdownHeaderParagraphLinesAndTitle() throws {
        let script = try fixture()
        let md = String(decoding: try script.markdown(), as: UTF8.self)
        let lines = md.components(separatedBy: "\n")
        XCTAssertEqual(lines.filter { $0.hasPrefix("> 검수:") }.count, 0)
        // 총수 = 8종 전부(상태 무관) = 문단0 9 + 문단1 open 4 + acknowledged 1 + resolved 1 = 15 (boundary 2+2+1, overlap 1+2+1).
        XCTAssertEqual(lines.first { $0.hasPrefix("- 검수: ") },
            "- 검수: 자동 화자 분리 결과이며 사람이 원음으로 검수하지 않음. 자동 경고 15건(화자 경계 걸침 5, 겹침 4, 화자 미확정 1, 시간 불명 1, 낮은 화자 점수 1, 누락 의심 1, 제공자 화자 불일치 1, 본문에 없는 화자 1)은 생략")
        XCTAssertEqual(lines.filter { $0.hasPrefix("- 녹음 중단: ") }, ["- 녹음 중단: 녹음이 중단되어 이후 구간이 녹음되지 않았을 수 있습니다."])
        XCTAssertEqual(lines.filter { $0.hasPrefix("- 일부 결과: ") }, ["- 일부 결과: 일부 전사 결과를 받지 못했습니다."])
        XCTAssertEqual(lines.filter { $0.hasPrefix("> 녹음 중단: ") }.count, 1)
        XCTAssertEqual(lines.filter { $0.hasPrefix("> 일부 결과: ") }.count, 1)
        // 머리말 순서: 검수 → 녹음 중단 → 일부 결과 → 화자 수.
        let review = try XCTUnwrap(lines.firstIndex { $0.hasPrefix("- 검수: ") })
        XCTAssertTrue(lines[review + 1].hasPrefix("- 녹음 중단: "))
        XCTAssertTrue(lines[review + 2].hasPrefix("- 일부 결과: "))
        XCTAssertTrue(lines[review + 3].hasPrefix("- 화자 수: "))
        // 중단 줄은 그 문단 본문 아래에 온다.
        // 중단 줄은 세 번째 문단(이슈가 붙은 문단) 본문 아래, 네 번째 문단 머리 앞에 온다.
        let headings = lines.indices.filter { lines[$0].hasPrefix("### [") }
        XCTAssertEqual(headings.count, 4)
        let cut = try XCTUnwrap(lines.firstIndex { $0.hasPrefix("> 녹음 중단: ") })
        XCTAssertTrue(headings[2] < cut && cut < headings[3])
        // 제목: nil이면 파일 제목, 주면 해석 제목.
        XCTAssertEqual(lines.first, "# 합성 경고")
        let titled = String(decoding: try script.markdown(title: "녹음 표시 제목"), as: UTF8.self)
        XCTAssertEqual(titled.components(separatedBy: "\n").first, "# 녹음 표시 제목")
    }

    func testMarkdownZeroWarningAndAudioCheckedForms() throws {
        var model = try base()
        attach(&model, turn: 0, .capture_interrupted)
        var script = try LibraryScript(transcript: model, title: "합성", recordedAt: nil, dateSource: "합성", input: ConversionNotes())
        var lines = String(decoding: try script.markdown(), as: UTF8.self).components(separatedBy: "\n")
        XCTAssertEqual(lines.first { $0.hasPrefix("- 검수: ") },
            "- 검수: 자동 화자 분리 결과이며 사람이 원음으로 검수하지 않음. 자동 경고 0건 (경고 없음이 정확도를 보장하지 않음)")
        XCTAssertEqual(lines.filter { $0.hasPrefix("- 녹음 중단: ") }.count, 1)
        XCTAssertEqual(lines.filter { $0.hasPrefix("- 일부 결과: ") }.count, 0)
        // 원음 확인 1건 이상: 현행 요약 뒤에 생략 문장.
        attach(&model, turn: 1, .overlapping_speech)
        script = try LibraryScript(transcript: model, title: "합성", recordedAt: nil, dateSource: "합성", input: ConversionNotes())
        let before = script
        try script.recordReview(before: before, turnIDs: [model.turns[0].id], audioChecked: true, error: .noError,
                                sample: .random, activeSeconds: 30)
        lines = String(decoding: try script.markdown(), as: UTF8.self).components(separatedBy: "\n")
        XCTAssertEqual(lines.first { $0.hasPrefix("- 검수: ") },
            "- 검수: 검수 기록 1건 · 원음 확인 1건 · 능동 시간 0.5분 (1건 측정). 자동 경고 1건(겹침 1)은 생략")
    }

    func testDeletedParagraphWarningsStayInHeaderOnlyAndDataIsUnchanged() throws {
        var script = try fixture()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let original = try encoder.encode(script.transcript)
        let interruptedBlock = script.blocks()[2]
        try script.deleteParagraph(interruptedBlock)
        let lines = String(decoding: try script.markdown(), as: UTF8.self).components(separatedBy: "\n")
        XCTAssertEqual(lines.filter { $0.hasPrefix("- 녹음 중단: ") }.count, 1)
        XCTAssertEqual(lines.filter { $0.hasPrefix("> 녹음 중단: ") }.count, 0)
        XCTAssertTrue(lines.contains { $0.contains("자동 경고 15건") }) // 삭제 문단 여부와 무관.
        XCTAssertEqual(try encoder.encode(script.transcript), original)
        // 평가 JSON의 reviewIssues 수 = 원본 수.
        let evaluation = try JSONSerialization.jsonObject(with: script.evaluationData()) as! [String: Any]
        let transcript = (evaluation["script"] as! [String: Any])["transcript"] as! [String: Any]
        XCTAssertEqual((transcript["reviewIssues"] as! [Any]).count, script.transcript.reviewIssues.count)
        XCTAssertEqual(script.transcript.reviewIssues.count, 17)
    }
}

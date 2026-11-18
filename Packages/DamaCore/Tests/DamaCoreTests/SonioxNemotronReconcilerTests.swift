import Foundation
import XCTest
@testable import DamaCore

final class SonioxNemotronReconcilerTests: XCTestCase {
    private let runID = "00000000-0000-4000-8000-00000000e001"
    private let duration: Int64 = 3_000_000

    private func token(_ text: String, _ start: Int, _ end: Int, _ speaker: String = "one") -> [String: Any] {
        ["text": text, "start_ms": start, "end_ms": end, "speaker": speaker, "confidence": 0.9]
    }
    /// 10 ms frames over 3 s, 8 channels; `on` = (channel, ms range, probability).
    private func probabilities(_ on: [(channel: Int, ms: Range<Int>, value: Float)]) -> (Data, Int) {
        let frames = 300
        var p = [Float](repeating: 0.02, count: frames * 8)
        for item in on { for f in (item.ms.lowerBound / 10)..<(item.ms.upperBound / 10) { p[f * 8 + item.channel] = item.value } }
        var data = Data()
        for value in p { withUnsafeBytes(of: value.bitPattern.littleEndian) { data.append(contentsOf: $0) } }
        return (data, frames)
    }
    private func normalize(_ tokens: [[String: Any]], _ on: [(channel: Int, ms: Range<Int>, value: Float)],
                           runID: String? = nil, version: SonioxNemotronReconciler.Version = SonioxNemotronReconciler.currentVersion) throws -> TranscriptDocument {
        let asr = try JSONSerialization.data(withJSONObject: ["id": "job", "text": tokens.map { $0["text"] as! String }.joined(), "tokens": tokens])
        let (data, frames) = probabilities(on)
        return try SonioxNemotronReconciler.normalize(soniox: asr, probabilities: data, frameCount: frames, channels: 8,
            sonioxJobID: "job", sessionID: "s", runID: runID ?? self.runID, durationUs: duration,
            audioSHA256: String(repeating: "a", count: 64), model: "stt-async-v5", createdAt: "2026-10-30T00:00:00Z", synthetic: true,
            version: version)
    }
    private var a: String { "\(runID)-nm-0" }
    private var b: String { "\(runID)-nm-1" }

    // A 1 s -> B 30 ms -> A 1 s (RC-01).
    private let aba: [(channel: Int, ms: Range<Int>, value: Float)] = [(0, 0..<1000, 0.9), (1, 1000..<1030, 0.9), (0, 1030..<2030, 0.9)]

    func testShortInterjectionStaysSeparateTurnBetweenSameSpeaker() throws {
        let doc = try normalize([token("다음", 100, 900), token(" 네", 1000, 1030), token(" 안 합니다", 1100, 1900)], aba)
        XCTAssertEqual(doc.diarization.map(\.speakerId), [a, b, a])
        XCTAssertEqual(doc.words.map(\.speakerId), [a, b, a])
        let speech = doc.turns.filter { $0.kind == .speech }
        XCTAssertEqual(speech.map(\.speakerId), [a, b, a])
    }

    func testMissingShortSpeakerTextLeavesMarkerAndBarrier() throws {
        let doc = try normalize([token("그래서", 100, 900), token(" 이어서", 1100, 1900)], aba)
        XCTAssertEqual(doc.turns.map(\.kind), [.speech, .missingSpeech, .speech])
        XCTAssertTrue(doc.reviewIssues.contains { $0.kind == .missing_speech })
        XCTAssertEqual(doc.words.map(\.speakerId), [a, a])
    }

    func testHalfProbabilityShortSpeakerIsNotDetected() throws {
        let control: [(channel: Int, ms: Range<Int>, value: Float)] = [(0, 0..<1000, 0.9), (1, 1000..<1030, 0.5), (0, 1030..<2030, 0.9)]
        let doc = try normalize([token("그래서", 100, 900), token(" 이어서", 1100, 1900)], control)
        XCTAssertEqual(doc.speakers.map(\.id), [a])
        XCTAssertFalse(doc.diarization.contains { $0.speakerId == b })
    }

    func testV1LeavesOverlapWordsUnassignedButFlagged() throws {
        let doc = try normalize([token("동시에", 1100, 1300)], [(0, 0..<2000, 0.9), (1, 1000..<1500, 0.8)], version: .v1)
        XCTAssertEqual(doc.provenance.algorithmVersion, "soniox-nemotron-word-v1")
        XCTAssertEqual(doc.diarization.count, 2)
        XCTAssertFalse(doc.exclusiveDiarization.contains { $0.startUs < 1_500_000 && $0.endUs > 1_000_000 })
        XCTAssertNil(doc.words[0].speakerId)
        XCTAssertTrue(doc.words[0].overlap)
        XCTAssertTrue(doc.reviewIssues.contains { $0.kind == .overlapping_speech && $0.wordIds == [doc.words[0].id] })
    }

    func testV2AssignsOverlapWordsToTheMostProbableChannelAndKeepsTheOverlapIssue() throws {
        let doc = try normalize([token("동시에", 1100, 1300)], [(0, 0..<2000, 0.9), (1, 1000..<1500, 0.8)])
        XCTAssertEqual(doc.diarization.count, 2)
        XCTAssertEqual(doc.words[0].speakerId, a)
        XCTAssertTrue(doc.words[0].overlap)
        XCTAssertTrue(doc.reviewIssues.contains { $0.kind == .overlapping_speech && $0.wordIds == [doc.words[0].id] })
        let swapped = try normalize([token("동시에", 1100, 1300)], [(0, 0..<2000, 0.8), (1, 1000..<1500, 0.9)])
        XCTAssertEqual(swapped.words[0].speakerId, b)
    }

    func testAdjacentSpeakersDoNotOverlap() throws {
        let doc = try normalize([token("앞", 200, 800), token(" 뒤", 1200, 1800)], [(0, 0..<1000, 0.9), (1, 1000..<2000, 0.9)])
        XCTAssertFalse(doc.reviewIssues.contains { $0.kind == .overlapping_speech })
        XCTAssertEqual(doc.words.map(\.speakerId), [a, b])
    }

    func testProvenanceIdsAndNullConfidence() throws {
        let doc = try normalize([token("다음", 100, 900, "x"), token(" 네", 1000, 1030, "y")], aba)
        XCTAssertEqual(doc.provenance.engine, .hybridSonioxNemotron)
        XCTAssertEqual(doc.provenance.diarizationModel, "nemotron-3-diarization-coreml-offline")
        XCTAssertEqual(doc.provenance.algorithmVersion, "soniox-nemotron-word-v4")
        XCTAssertEqual(doc.speakers.map(\.providerId), ["channel-0", "channel-1"])
        XCTAssertEqual(doc.speakers.map(\.displayName), ["화자 1", "화자 2"])
        XCTAssertEqual(doc.diarization.map(\.id), ["d0", "d1", "d2"])
        XCTAssertTrue(doc.exclusiveDiarization.allSatisfy { $0.id.hasPrefix("e") })
        XCTAssertTrue((doc.diarization + doc.exclusiveDiarization).allSatisfy { $0.confidence == nil })
        XCTAssertFalse(doc.reviewIssues.contains { $0.kind == .low_confidence })
        try TranscriptValidator().validate(doc)
    }

    func testSonioxTokensAreUnchanged() throws {
        let tokens = [token("다음", 100, 900, "x"), token(" 네", 1000, 1030, "y"), token(" 안 합니다", 1100, 1900, "x")]
        let doc = try normalize(tokens, aba)
        let asr = try JSONSerialization.data(withJSONObject: ["id": "job", "text": tokens.map { $0["text"] as! String }.joined(), "tokens": tokens])
        let soniox = try SonioxNormalizer.normalize(asr, jobID: "job", sessionID: "s", runID: runID, durationUs: duration,
            audioSHA256: String(repeating: "a", count: 64), model: "stt-async-v5", synthetic: true, createdAt: "2026-10-30T00:00:00Z")
        XCTAssertEqual(doc.words.map(\.text), soniox.words.map(\.text))
        XCTAssertEqual(doc.words.map(\.prefix), soniox.words.map(\.prefix))
        XCTAssertEqual(doc.words.map(\.ordinal), soniox.words.map(\.ordinal))
        XCTAssertEqual(doc.words.map(\.startUs), soniox.words.map(\.startUs))
        XCTAssertEqual(doc.words.map(\.endUs), soniox.words.map(\.endUs))
        XCTAssertEqual(doc.words.map(\.asrConfidence), soniox.words.map(\.asrConfidence))
        XCTAssertEqual(doc.words.map(\.language), soniox.words.map(\.language))
        XCTAssertEqual(doc.words.map(\.asrSpeakerLabel), ["x", "y", "x"])
    }

    func testScriptPresentationTreatsNemotronAsSonioxCombined() throws {
        let doc = try normalize([token("다음", 100, 900), token(" 네", 1000, 1030), token(" 안 합니다", 1100, 1900)], aba)
        var input = ConversionNotes(); input.speakerCount = 3; input.sonioxContext = true; input.sonioxSpeakerCountHint = 3
        let hinted = try LibraryScript(transcript: doc, title: "synthetic", recordedAt: nil, dateSource: "synthetic", input: input)
        XCTAssertEqual(hinted.speakerCountApplication, "Nemotron 3 화자 수 지정 없음 · Soniox에 3명 힌트 전송 · 강제 지정 아님")
        XCTAssertEqual(hinted.speakerCountSummary, "예상 3명 · 감지 2명 · 화자 구분 검수 필요")
        input.sonioxContext = false
        let plain = try LibraryScript(transcript: doc, title: "synthetic", recordedAt: nil, dateSource: "synthetic", input: input)
        XCTAssertEqual(plain.speakerCountApplication, "Nemotron 3 화자 수 지정 없음 · Soniox 화자 수 힌트 미전송")
        XCTAssertEqual(EngineKind.hybridSonioxNemotron.title, "Soniox + Nemotron 3")
        XCTAssertEqual(plain.blocks().map(\.text), ["다음", "네", "안 합니다"])
    }

    func testOperatingSelectionMigratesRetiredChoices() {
        XCTAssertEqual(TranscriptionProvider.selectable, [.sonioxNemotron, .soniox])
        for stored in ["sonioxPrecision", "qwen", "pyannote", "precision", "nemotron", "unknown", nil] as [String?] {
            XCTAssertEqual(TranscriptionProvider.operatingSelection(stored: stored), .sonioxNemotron, stored ?? "nil")
        }
        XCTAssertEqual(TranscriptionProvider.operatingSelection(stored: "soniox"), .soniox)
        XCTAssertEqual(TranscriptionProvider.operatingSelection(stored: "sonioxNemotron"), .sonioxNemotron)
        XCTAssertEqual(TranscriptionProvider.sonioxNemotron.title, "Soniox + Nemotron 3 (운영)")
        XCTAssertEqual(TranscriptionProvider.soniox.title, "Soniox 단독 (비교)")
    }

    // r3 어절 안 화자 맞춤 (AC-16). A = 채널 0, B = 채널 1.
    private func word(_ doc: TranscriptDocument, _ text: String) -> TranscriptWord? {
        doc.words.first { $0.text.trimmingCharacters(in: .whitespaces) == text }
    }
    private func speakers(_ doc: TranscriptDocument, _ texts: [String]) -> [String?] { texts.map { word(doc, $0)?.speakerId } }

    func testSplitWordTakesTheSpeakerOfItsSameSentenceNeighbour() throws {
        let tokens = [token("연락", 100, 400), token(" 왔", 500, 600), token("어", 600, 700), token("요", 700, 780), token("?", 780, 800),
                      token(" 네", 1100, 1300)]
        let on: [(channel: Int, ms: Range<Int>, value: Float)] = [(0, 0..<800, 0.9), (1, 600..<800, 0.95), (1, 1000..<2000, 0.9)]
        let v2 = try normalize(tokens, on, version: .v2)
        XCTAssertEqual(speakers(v2, ["왔", "어", "요"]), [a, b, b])
        let doc = try normalize(tokens, on)
        // ① 앞 이웃 «연락»으로 맞춤 · ③ «요?»로 문장이 끝나 뒤 «네»(B)는 보지 않음 · ⑪ 닫는 부호도 따름.
        XCTAssertEqual(speakers(doc, ["왔", "어", "요", "?", "네"]), [a, a, a, a, b])
        // ⑩ 바꾼 토큰: 근거 = 자기 ∪ 이웃, coverage 없음, 겹침 이슈 유지.
        let changed = try XCTUnwrap(word(doc, "어")), before = try XCTUnwrap(word(v2, "어"))
        let neighbour = try XCTUnwrap(word(doc, "연락"))
        XCTAssertEqual(changed.sourceIntervalIds, Array(Set(before.sourceIntervalIds + neighbour.sourceIntervalIds)).sorted())
        XCTAssertNil(changed.alignmentScore)
        XCTAssertTrue(changed.overlap)
        XCTAssertTrue(doc.reviewIssues.contains { $0.kind == .overlapping_speech && $0.wordIds == [changed.id] })
        XCTAssertEqual(try XCTUnwrap(word(doc, "왔")).sourceIntervalIds, try XCTUnwrap(word(v2, "왔")).sourceIntervalIds)
        try TranscriptValidator().validate(doc)
    }

    func testSentenceEndBeforeTheWordLeavesOnlyTheNextNeighbour() throws {
        // ② 앞 어절이 «.»로 끝나므로 앞(A)은 보지 않고 뒤 «이제»(B)로 맞춤.
        let tokens = [token("끝났어요", 100, 400), token(".", 400, 410), token(" 그", 600, 700), token("래서", 700, 900), token(" 이제", 1000, 1300)]
        let on: [(channel: Int, ms: Range<Int>, value: Float)] = [(0, 0..<1000, 0.9), (1, 600..<700, 0.95), (1, 1000..<2000, 0.9)]
        XCTAssertEqual(speakers(try normalize(tokens, on, version: .v2), ["그", "래서"]), [b, a])
        XCTAssertEqual(speakers(try normalize(tokens, on), ["끝났어요", "그", "래서", "이제"]), [a, b, b, b])
    }

    func testNeighboursThatDisagreeOrAreNotEligibleLeaveTheWordSplit() throws {
        // ④ 앞(A)과 뒤(B) 이웃이 다름.
        let both = try normalize([token("앞", 100, 400), token(" 왔", 500, 600), token("어", 600, 700), token(" 뒤", 1000, 1300)],
                                 [(0, 0..<700, 0.9), (1, 600..<700, 0.95), (1, 1000..<2000, 0.9)])
        XCTAssertEqual(speakers(both, ["왔", "어"]), [a, b])
        // ⑤ 앞 이웃의 Soniox 후보가 다름.
        let label = try normalize([token("연락", 100, 400, "two"), token(" 왔", 500, 600), token("어", 600, 700), token("요?", 700, 800)],
                                  [(0, 0..<800, 0.9), (1, 600..<800, 0.95)])
        XCTAssertEqual(speakers(label, ["왔", "어", "요?"]), [a, b, b])
        // ⑥ 앞 이웃 자체가 두 화자로 갈림.
        let mixed = try normalize([token("연", 100, 200), token("락", 200, 300), token(" 왔", 500, 600), token("어", 600, 700), token("요?", 700, 800)],
                                  [(0, 0..<800, 0.9), (1, 200..<300, 0.95), (1, 600..<800, 0.95)])
        XCTAssertEqual(speakers(mixed, ["연", "락", "왔", "어", "요?"]), [a, b, a, b, b])
    }

    func testOneWordIslandAndUnassignedFragmentsStay() throws {
        // ⑦ 어절 하나 섬 A [B] A는 그대로.
        let island = try normalize([token("다음", 100, 900), token(" 네", 1000, 1030), token(" 안 합니다", 1100, 1900)], aba)
        XCTAssertEqual(island.words.map(\.speakerId), [a, b, a])
        // ⑧ 맞추는 어절 안의 미배정 조각(«이», A·B 동률)은 null 유지.
        let tokens = [token("연락", 100, 400), token(" 같", 900, 1000), token("이", 1100, 1300), token("요", 1300, 1400), token("?", 1400, 1410)]
        let on: [(channel: Int, ms: Range<Int>, value: Float)] = [(0, 0..<1500, 0.8), (1, 1000..<1300, 0.8), (1, 1300..<1400, 0.9)]
        XCTAssertEqual(speakers(try normalize(tokens, on, version: .v2), ["같", "이", "요"]), [a, nil, b])
        // turn-continuity G-08: 기본 버전 v4는 D-01로 «이»를 어절의 단일 화자로 맞춘다. v3 저장 Run 재현은 null 유지.
        XCTAssertEqual(speakers(try normalize(tokens, on), ["같", "이", "요"]), [a, a, a])
        XCTAssertEqual(speakers(try normalize(tokens, on, version: .v3), ["같", "이", "요"]), [a, nil, a])
    }

    func testConsecutiveSplitWordsAreJudgedFromTheSameSnapshot() throws {
        // ⑨ «가나»는 앞(A)으로, «다라»는 직전 배정에서 앞 이웃이 갈려 있어 뒤(B)로 맞춤. 순차 적용이면 «다라»는 A·B 충돌로 남는다.
        let tokens = [token("앞", 100, 400), token(" 가", 500, 600), token("나", 600, 700), token(" 다", 800, 900), token("라", 900, 1000),
                      token(" 뒤", 1200, 1500)]
        let on: [(channel: Int, ms: Range<Int>, value: Float)] = [(0, 0..<1000, 0.9), (1, 600..<700, 0.95), (1, 900..<1500, 0.95)]
        XCTAssertEqual(speakers(try normalize(tokens, on, version: .v2), ["가", "나", "다", "라"]), [a, b, a, b])
        XCTAssertEqual(speakers(try normalize(tokens, on), ["가", "나", "다", "라"]), [a, a, b, b])
    }

    func testSpeakerIdsAreScopedToRun() throws {
        let other = "00000000-0000-4000-8000-00000000e002"
        let first = try normalize([token("다음", 100, 900)], aba)
        let second = try normalize([token("다음", 100, 900)], aba, runID: other)
        XCTAssertTrue(Set(first.speakers.map(\.id)).isDisjoint(with: second.speakers.map(\.id)))
    }

    // MARK: turn-continuity AC-04 (D-01 어절 안 미상 조각) · AC-05 (D-03 Turn 구성)

    private func speech(_ doc: TranscriptDocument) -> [TranscriptTurn] { doc.turns.filter { $0.kind == .speech } }
    private func texts(_ doc: TranscriptDocument, _ turn: TranscriptTurn) -> String {
        turn.wordIds.compactMap { id in doc.words.first { $0.id == id } }.map { $0.prefix + $0.text }.joined()
    }

    /// ① 한 화자 + 미상 조각 → 맞춤. 근거 = 자기 ∪ 같은 어절 배정 근거, coverage 없음, «화자 미확정» 이슈 없음.
    func testV4FillsUnknownFragmentOfASingleSpeakerWord() throws {
        let tokens = [token("연락", 100, 400), token(" 같", 900, 1000), token("이", 1100, 1300), token("요", 1300, 1400), token("?", 1400, 1410)]
        let on: [(channel: Int, ms: Range<Int>, value: Float)] = [(0, 0..<1500, 0.8), (1, 1000..<1300, 0.8), (1, 1300..<1400, 0.9)]
        let v3 = try normalize(tokens, on, version: .v3), v4 = try normalize(tokens, on, version: .v4)
        XCTAssertEqual(v4.provenance.algorithmVersion, "soniox-nemotron-word-v4")
        XCTAssertEqual(speakers(v4, ["같", "이", "요", "?"]), [a, a, a, a])
        let filled = try XCTUnwrap(word(v4, "이")), before = try XCTUnwrap(word(v3, "이"))
        let support = try ["같", "요"].map { try XCTUnwrap(word(v3, $0)).sourceIntervalIds }.flatMap { $0 }
        XCTAssertEqual(filled.sourceIntervalIds, Array(Set(before.sourceIntervalIds + support)).sorted())
        XCTAssertNil(filled.alignmentScore)
        XCTAssertEqual(filled.assignmentSource, .reconciled)
        XCTAssertFalse(v4.reviewIssues.contains { $0.kind == .ambiguous_speaker && $0.wordIds.contains(filled.id) })
        XCTAssertTrue(v3.reviewIssues.contains { $0.kind == .ambiguous_speaker && $0.wordIds.contains(before.id) })
        // 맞추지 않은 토큰의 근거·점수는 v3와 같다.
        XCTAssertEqual(try XCTUnwrap(word(v4, "같")).sourceIntervalIds, try XCTUnwrap(word(v3, "같")).sourceIntervalIds)
        XCTAssertEqual(try XCTUnwrap(word(v4, "같")).alignmentScore, try XCTUnwrap(word(v3, "같")).alignmentScore)
        try TranscriptValidator().validate(v4)
    }

    /// ② 배정 화자가 둘인 갈린 어절의 미상 조각은 null 그대로.
    func testV4LeavesUnknownFragmentOfASplitWord() throws {
        let tokens = [token("앞", 100, 400), token(" 왔", 500, 600), token("어", 600, 700), token("요", 700, 800), token(" 뒤", 1000, 1300)]
        let on: [(channel: Int, ms: Range<Int>, value: Float)] = [(0, 0..<700, 0.9), (1, 600..<700, 0.95), (1, 1000..<2000, 0.9)]
        XCTAssertEqual(speakers(try normalize(tokens, on, version: .v3), ["왔", "어", "요"]), [a, b, nil])
        XCTAssertEqual(speakers(try normalize(tokens, on, version: .v4), ["왔", "어", "요"]), [a, b, nil])
    }

    /// ③ 어절 전체가 미상이면 전부 null, «화자 미확정» 이슈 유지.
    func testV4LeavesFullyUnknownWord() throws {
        let tokens = [token("연락", 100, 400), token(" 그", 2100, 2200), token("래", 2200, 2300)]
        let doc = try normalize(tokens, [(0, 0..<1000, 0.9)], version: .v4)
        XCTAssertEqual(speakers(doc, ["연락", "그", "래"]), [a, nil, nil])
        for text in ["그", "래"] {
            let id = try XCTUnwrap(word(doc, text)).id
            XCTAssertTrue(doc.reviewIssues.contains { $0.kind == .ambiguous_speaker && $0.wordIds == [id] }, text)
        }
    }

    /// ④ 0길이 미상 조각도 맞춘다. 시간 이슈는 그대로 남는다.
    func testV4FillsZeroLengthFragment() throws {
        let tokens = [token("연락", 100, 400), token(" 왔", 500, 600), token("어", 1500, 1500)]
        let on: [(channel: Int, ms: Range<Int>, value: Float)] = [(0, 0..<1000, 0.9), (1, 1100..<1300, 0.9)]
        let v3 = try normalize(tokens, on, version: .v3), v4 = try normalize(tokens, on, version: .v4)
        XCTAssertEqual(speakers(v3, ["왔", "어"]), [a, nil])
        XCTAssertEqual(speakers(v4, ["왔", "어"]), [a, a])
        let filled = try XCTUnwrap(word(v4, "어"))
        XCTAssertNil(filled.alignmentScore)
        XCTAssertTrue(Set(try XCTUnwrap(word(v4, "왔")).sourceIntervalIds).isSubset(of: filled.sourceIntervalIds))
        XCTAssertTrue(v4.reviewIssues.contains { $0.kind == .invalid_timestamp && $0.wordIds == [filled.id] })
        try TranscriptValidator().validate(v4)
    }

    /// AC-05 ① 어절 안 같은 화자 사이 틈에 다른 화자 일반 구간 → v4 한 Turn, v3 두 Turn (단어 화자는 같음).
    func testV4JoinsSameSpeakerAcrossAnotherSpeakersIntervalInsideOneWord() throws {
        let tokens = [token("왔", 500, 600), token("어", 700, 800)]
        let on: [(channel: Int, ms: Range<Int>, value: Float)] = [(0, 0..<1000, 0.9), (1, 550..<750, 0.8)]
        let v3 = try normalize(tokens, on, version: .v3), v4 = try normalize(tokens, on, version: .v4)
        XCTAssertFalse(v4.turns.contains { $0.kind == .missingSpeech })
        XCTAssertEqual(v3.words.map(\.speakerId), [a, a])
        XCTAssertEqual(v4.words.map(\.speakerId), [a, a])
        XCTAssertEqual(speech(v3).count, 2)
        XCTAssertEqual(speech(v4).count, 1)
        XCTAssertEqual(speech(v4)[0].wordIds, v4.words.map(\.id))
        XCTAssertEqual(speech(v4)[0].startUs, 500_000); XCTAssertEqual(speech(v4)[0].endUs, 800_000)
        try TranscriptValidator().validate(v4)
    }

    /// AC-05 ② 어절 사이 A → B → A는 v4에서도 세 Turn (RC-01), 어절 사이 같은 화자는 다른 화자 구간에서 끊긴다.
    func testV4KeepsBarriersBetweenWords() throws {
        let doc = try normalize([token("다음", 100, 900), token(" 네", 1000, 1030), token(" 안 합니다", 1100, 1900)], aba, version: .v4)
        XCTAssertEqual(speech(doc).map(\.speakerId), [a, b, a])
        let across = try normalize([token("왔", 500, 600), token(" 어", 700, 800)], [(0, 0..<1000, 0.9), (1, 550..<750, 0.8)], version: .v4)
        XCTAssertEqual(across.words.map(\.speakerId), [a, a])
        XCTAssertEqual(speech(across).count, 2)
    }

    /// AC-05 ④ 어절 안 누락 marker는 v4에서도 장벽이다 (RC-03).
    func testV4MissingMarkerInsideAWordStillSplits() throws {
        let tokens = [token("왔", 500, 600), token("어", 900, 1000)]
        let on: [(channel: Int, ms: Range<Int>, value: Float)] = [(0, 0..<600, 0.9), (1, 650..<750, 0.9), (0, 800..<1100, 0.9)]
        let doc = try normalize(tokens, on, version: .v4)
        XCTAssertEqual(doc.words.map(\.speakerId), [a, a])
        XCTAssertEqual(doc.turns.map(\.kind), [.speech, .missingSpeech, .speech])
    }

    /// AC-05 ⑤ 어절 안 녹음 중단 구간도 장벽이다. 정상 경로의 중단 이슈는 녹음 끝 한 점이라, 결과 문서에 구간 이슈를 넣고 다시 결합한다.
    func testV4CaptureInterruptionInsideAWordStillSplits() throws {
        let tokens = [token("왔", 500, 600), token("어", 700, 800)]
        let on: [(channel: Int, ms: Range<Int>, value: Float)] = [(0, 0..<1000, 0.9), (1, 550..<750, 0.8)]
        var base = try normalize(tokens, on, version: .v4)
        XCTAssertEqual(speech(base).count, 1)
        base.reviewIssues.append(ReviewIssue(id: "cut", kind: .capture_interrupted, startUs: 620_000, endUs: 680_000, severity: .warning,
            status: .open, wordIds: [], sourceIntervalIds: []))
        let doc = try SonioxPrecisionReconciler.applying(base, runID: runID, createdAt: "2026-10-30T00:00:00Z", policy: .wordRepair,
            version: "soniox-nemotron-word-v4", keepsSpeakerIDs: true, unifiesSplitWords: true,
            fillsWordFragments: true, continuesWithinWords: true)
        XCTAssertTrue(doc.reviewIssues.contains { $0.kind == .capture_interrupted })
        XCTAssertEqual(speech(doc).count, 2)
    }

    /// AC-05 ⑥ ⑦ ⑧ 미상 조각: 같은 어절 · 같은 라벨 → 한 Turn, 라벨 다름 → 따로, 다른 어절 → 따로 (INV-05).
    func testV4JoinsUnknownPiecesOnlyWithinOneWordAndOneLabel() throws {
        let none: [(channel: Int, ms: Range<Int>, value: Float)] = [(0, 2000..<2900, 0.9)]
        let same = try normalize([token("그", 100, 200), token("래", 200, 300), token("요", 300, 400)], none, version: .v4)
        XCTAssertEqual(same.words.map(\.speakerId), [nil, nil, nil])
        XCTAssertEqual(speech(same).count, 1)
        XCTAssertEqual(texts(same, speech(same)[0]), "그래요")
        XCTAssertEqual(speech(try normalize([token("그", 100, 200), token("래", 200, 300)], none, version: .v3)).count, 2)
        let labels = try normalize([token("그", 100, 200, "x"), token("래", 200, 300, "y")], none, version: .v4)
        XCTAssertEqual(speech(labels).count, 2)
        let words = try normalize([token("그", 100, 200), token(" 래", 200, 300)], none, version: .v4)
        XCTAssertEqual(speech(words).count, 2)
        for doc in [same, labels, words] { try TranscriptValidator().validate(doc) }
    }
}

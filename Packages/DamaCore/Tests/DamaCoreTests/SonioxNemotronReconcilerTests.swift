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
                           runID: String? = nil, version: SonioxNemotronReconciler.Version = .v2) throws -> TranscriptDocument {
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
        XCTAssertEqual(doc.provenance.algorithmVersion, "soniox-nemotron-word-v2")
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

    func testSpeakerIdsAreScopedToRun() throws {
        let other = "00000000-0000-4000-8000-00000000e002"
        let first = try normalize([token("다음", 100, 900)], aba)
        let second = try normalize([token("다음", 100, 900)], aba, runID: other)
        XCTAssertTrue(Set(first.speakers.map(\.id)).isDisjoint(with: second.speakers.map(\.id)))
    }
}

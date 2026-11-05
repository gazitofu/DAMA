import Foundation
import XCTest
@testable import DamaCore

/// library-loading AC-01: the linear-time validator must give the same outcome
/// (pass, or the first error code and path) as the pre-change validator.
/// Times are Int64 µs, intervals half-open `[startUs, endUs)`.
final class TranscriptValidatorEquivalenceTests: XCTestCase {
    private struct Outcome: Equatable { let code: TranscriptContractError.Code?; let path: String? }

    private var fixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("fixtures/normalized-transcript.json")
    }

    private func outcome(_ body: () throws -> Void) -> Outcome {
        do { try body(); return Outcome(code: nil, path: nil) }
        catch let error as TranscriptContractError { return Outcome(code: error.code, path: error.path) }
        catch { return Outcome(code: nil, path: "unexpected \(error)") }
    }

    @discardableResult
    private func assertSame(_ document: TranscriptDocument, _ message: String = "",
                            file: StaticString = #filePath, line: UInt = #line) -> Outcome {
        let reference = outcome { try ReferenceTranscriptValidator().validate(document) }
        let current = outcome { try TranscriptValidator().validate(document) }
        XCTAssertEqual(current, reference, message, file: file, line: line)
        return current
    }

    // MARK: Builder

    private struct Templates {
        let base: TranscriptDocument
        let word: TranscriptWord
        let speech: TranscriptTurn
        let interval: DiarizationInterval
        let issue: ReviewIssue
    }

    private func templates() throws -> Templates {
        let base = try SyntheticTranscriptFixtureLoader.load(from: fixtureURL)
        return Templates(base: base, word: base.words[0], speech: base.turns.first { $0.kind == .speech }!,
                         interval: base.diarization[0], issue: base.reviewIssues[0])
    }

    private func word(_ t: Templates, _ index: Int, _ start: Int64?, _ end: Int64?, speaker: String,
                      model: String?) -> TranscriptWord {
        var value = t.word
        value.id = "w\(index)"; value.ordinal = index; value.startUs = start; value.endUs = end
        value.speakerId = speaker; value.modelSpeakerId = model; value.assignmentSource = .reconciled
        value.reviewIssueIds = []; value.sourceIntervalIds = []; value.editedText = nil; value.timingOrigin = .model
        value.alignmentScore = nil
        return value
    }

    private func speech(_ t: Templates, _ id: String, _ words: [TranscriptWord], speaker: String) -> TranscriptTurn {
        var value = t.speech
        value.id = id; value.kind = .speech; value.speakerId = speaker; value.wordIds = words.map(\.id)
        value.markerText = nil; value.reviewIssueIds = []
        let timed = words.compactMap { w in w.startUs.flatMap { s in w.endUs.map { (s, $0) } } }
        value.startUs = timed.map(\.0).min(); value.endUs = timed.map(\.1).max()
        return value
    }

    private func marker(_ t: Templates, _ id: String, _ start: Int64, _ end: Int64) -> TranscriptTurn {
        var value = t.speech
        value.id = id; value.kind = .missingSpeech; value.speakerId = nil; value.wordIds = []
        value.markerText = "누락 의심"; value.startUs = start; value.endUs = end; value.reviewIssueIds = []
        return value
    }

    private func interval(_ t: Templates, _ id: String, _ start: Int64, _ end: Int64, _ speaker: String) -> DiarizationInterval {
        var value = t.interval
        value.id = id; value.startUs = start; value.endUs = end; value.speakerId = speaker; value.confidence = nil
        return value
    }

    private func interruption(_ t: Templates, _ id: String, _ start: Int64, _ end: Int64) -> ReviewIssue {
        var value = t.issue
        value.id = id; value.kind = .capture_interrupted; value.startUs = start; value.endUs = end
        value.wordIds = []; value.sourceIntervalIds = []
        return value
    }

    private func document(_ t: Templates, words: [TranscriptWord], turns: [TranscriptTurn],
                          diarization: [DiarizationInterval], exclusive: [DiarizationInterval],
                          issues: [ReviewIssue], duration: Int64 = 120_000_000) -> TranscriptDocument {
        var value = t.base
        value.durationUs = duration; value.words = words; value.turns = turns
        value.diarization = diarization; value.exclusiveDiarization = exclusive; value.reviewIssues = issues
        return value
    }

    /// One speech turn (speaker-a) with words w0 [1.0 s, 1.2 s) and w1 [1.5 s, 1.7 s): gap [1.2 s, 1.5 s).
    private func gapDocument(_ t: Templates, diarization extra: [DiarizationInterval] = [],
                             exclusive: [DiarizationInterval]? = nil, markers: [TranscriptTurn] = [],
                             issues: [ReviewIssue] = []) -> TranscriptDocument {
        let words = [word(t, 0, 1_000_000, 1_200_000, speaker: "speaker-a", model: "speaker-a"),
                     word(t, 1, 1_500_000, 1_700_000, speaker: "speaker-a", model: "speaker-a")]
        let base = interval(t, "d0", 900_000, 1_800_000, "speaker-a")
        return document(t, words: words, turns: [speech(t, "t0", words, speaker: "speaker-a")] + markers,
                        diarization: [base] + extra,
                        exclusive: exclusive ?? [interval(t, "e0", 900_000, 1_800_000, "speaker-a")], issues: issues)
    }

    // MARK: Fixed mutations (AC-01 ①–⑦)

    func testFixedBarrierAndExclusiveMutationsMatchReference() throws {
        let t = try templates()
        let pairPath = "$.turns[0].wordIds[1]"
        // ① missing-speech marker inside the gap
        XCTAssertEqual(assertSame(gapDocument(t, markers: [marker(t, "m0", 1_300_000, 1_400_000)])),
                       Outcome(code: .invalidBarrier, path: pairPath))
        // ② capture interruption inside the gap
        XCTAssertEqual(assertSame(gapDocument(t, issues: [interruption(t, "i0", 1_300_000, 1_400_000)])),
                       Outcome(code: .invalidBarrier, path: pairPath))
        // ③ other speaker's regular interval inside the gap
        XCTAssertEqual(assertSame(gapDocument(t, diarization: [interval(t, "d1", 1_300_000, 1_350_000, "speaker-b")])),
                       Outcome(code: .invalidBarrier, path: pairPath))
        // ④ same speaker's interval inside the gap is allowed
        XCTAssertEqual(assertSame(gapDocument(t, diarization: [interval(t, "d1", 1_250_000, 1_450_000, "speaker-a")])),
                       Outcome(code: nil, path: nil))
        // ⑤ other speaker touching the gap edges does not overlap it
        XCTAssertEqual(assertSame(gapDocument(t, diarization: [interval(t, "d1", 1_500_000, 1_600_000, "speaker-b"),
                                                               interval(t, "d2", 1_000_000, 1_200_000, "speaker-b")],
                                              markers: [marker(t, "m0", 1_500_000, 1_600_000), marker(t, "m1", 1_300_000, 1_300_000)],
                                              issues: [interruption(t, "i0", 1_100_000, 1_200_000)])),
                       Outcome(code: nil, path: nil))
        // ⑥ exclusive intervals of different speakers that only touch
        XCTAssertEqual(assertSame(gapDocument(t, exclusive: [interval(t, "e0", 1_000_000, 1_200_000, "speaker-a"),
                                                             interval(t, "e1", 1_200_000, 1_300_000, "speaker-b")])),
                       Outcome(code: nil, path: nil))
        // ⑦ exclusive overlap by 1 µs reports the same right-hand index as the pairwise scan
        XCTAssertEqual(assertSame(gapDocument(t, exclusive: [interval(t, "e0", 1_000_000, 1_200_000, "speaker-a"),
                                                             interval(t, "e1", 1_400_000, 1_500_000, "speaker-a"),
                                                             interval(t, "e2", 1_199_999, 1_300_000, "speaker-b")])),
                       Outcome(code: .invalidValue, path: "$.exclusiveDiarization[2]"))
    }

    func testExistingFixtureMatchesReference() throws {
        let t = try templates()
        XCTAssertEqual(assertSame(t.base), Outcome(code: nil, path: nil))
    }

    // MARK: Generated documents

    private struct SplitMix64 {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        mutating func int(_ range: ClosedRange<Int>) -> Int {
            range.lowerBound + Int(next() % UInt64(range.upperBound - range.lowerBound + 1))
        }
        mutating func chance(_ percent: Int) -> Bool { int(0...99) < percent }
    }

    private func generated(_ t: Templates, seed: UInt64) -> TranscriptDocument {
        var rng = SplitMix64(state: seed)
        let speakers = ["speaker-a", "speaker-b", "speaker-c"]
        var words: [TranscriptWord] = [], turns: [TranscriptTurn] = [], regular: [DiarizationInterval] = []
        var exclusive: [DiarizationInterval] = [], markers: [TranscriptTurn] = [], issues: [ReviewIssue] = []
        var gaps: [(Int64, Int64, String)] = []
        var clock: Int64 = 0
        for turnIndex in 0..<rng.int(2...14) {
            let speaker = speakers[rng.int(0...2)]
            var turnWords: [TranscriptWord] = []
            var previousEnd: Int64?
            for _ in 0..<rng.int(1...8) {
                clock += Int64(rng.int(0...400) * 1_000)
                let length = Int64(rng.int(0...300) * 1_000)
                let timed = !rng.chance(5)
                let model = rng.chance(4) ? speakers[rng.int(0...2)] : (rng.chance(3) ? nil : speaker)
                let next = word(t, words.count, timed ? clock : nil, timed ? clock + length : nil, speaker: speaker, model: model)
                if timed, let previousEnd, previousEnd < clock { gaps.append((previousEnd, clock, speaker)) }
                if timed { previousEnd = clock + length; clock += length }
                words.append(next); turnWords.append(next)
            }
            let turn = speech(t, "t\(turnIndex)", turnWords, speaker: speaker)
            turns.append(turn)
            if let start = turn.startUs, let end = turn.endUs {
                let padded = (max(0, start - 50_000), end + 50_000)
                regular.append(interval(t, "d\(regular.count)", padded.0, max(padded.1, padded.0 + 1), speaker))
                if start < end { exclusive.append(interval(t, "e\(exclusive.count)", start, end, speaker)) }
            }
            clock += Int64(rng.int(100...600) * 1_000)
            if rng.chance(30) { markers.append(marker(t, "m\(markers.count)", clock - 80_000, clock - 20_000)) }
            if rng.chance(20) { issues.append(interruption(t, "i\(issues.count)", clock - 70_000, clock - 30_000)) }
        }
        // Perturbations: each kind may or may not break a rule depending on where it lands.
        for _ in 0..<rng.int(0...3) {
            switch rng.int(0...6) {
            case 0 where !gaps.isEmpty:
                let gap = gaps[rng.int(0...(gaps.count - 1))]
                markers.append(marker(t, "m\(markers.count)", gap.0, gap.0 + Int64(rng.int(0...1)) * (gap.1 - gap.0)))
            case 1 where !gaps.isEmpty:
                let gap = gaps[rng.int(0...(gaps.count - 1))]
                issues.append(interruption(t, "i\(issues.count)", gap.0 + 1, gap.1))
            case 2 where !gaps.isEmpty:
                let gap = gaps[rng.int(0...(gaps.count - 1))]
                let other = speakers.filter { $0 != gap.2 }[rng.int(0...1)]
                regular.append(interval(t, "d\(regular.count)", gap.0 - Int64(rng.int(0...1)), gap.1 + Int64(rng.int(0...1)), other))
            case 3 where !gaps.isEmpty:
                let gap = gaps[rng.int(0...(gaps.count - 1))]
                regular.append(interval(t, "d\(regular.count)", gap.0, gap.1, gap.2))
            case 4 where !exclusive.isEmpty:
                let target = exclusive[rng.int(0...(exclusive.count - 1))]
                let other = speakers.filter { $0 != target.speakerId }[rng.int(0...1)]
                let start = target.endUs - Int64(rng.int(0...1))
                exclusive.append(interval(t, "e\(exclusive.count)", start, start + 10_000, other))
            case 5 where !gaps.isEmpty:
                let gap = gaps[rng.int(0...(gaps.count - 1))]
                regular.append(interval(t, "d\(regular.count)", gap.1, gap.1 + 5_000, speakers[rng.int(0...2)]))
            default:
                if !words.isEmpty { words[rng.int(0...(words.count - 1))].modelSpeakerId = speakers[rng.int(0...2)] }
            }
        }
        return document(t, words: words, turns: turns + markers, diarization: regular, exclusive: exclusive, issues: issues,
                        duration: max(clock + 1_000_000, 1_000_000))
    }

    func testGeneratedDocumentsMatchReference() throws {
        let t = try templates()
        var codes: [String: Int] = [:]
        for seed in 1...400 {
            let result = assertSame(generated(t, seed: UInt64(seed)), "seed \(seed)")
            codes[result.code?.rawValue ?? "pass", default: 0] += 1
        }
        print("generated outcome counts: \(codes.sorted { $0.key < $1.key })")
        // The generator must exercise both outcomes and both rewritten checks (self-check, rule-measurement).
        XCTAssertGreaterThanOrEqual(codes["pass"] ?? 0, 40, "\(codes)")
        XCTAssertGreaterThanOrEqual(codes["invalidBarrier"] ?? 0, 40, "\(codes)")
        XCTAssertGreaterThanOrEqual(codes["invalidValue"] ?? 0, 10, "\(codes)")
    }
}

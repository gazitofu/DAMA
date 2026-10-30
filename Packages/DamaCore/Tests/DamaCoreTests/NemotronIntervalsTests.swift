import Foundation
import XCTest
@testable import DamaCore

final class NemotronIntervalsTests: XCTestCase {
    /// Builds `[frame x channels]` probabilities from per-channel active frame ranges.
    private func probs(frames: Int, channels: Int = 2, _ on: [(channel: Int, frames: Range<Int>, value: Float)]) -> [Float] {
        var p = [Float](repeating: 0, count: frames * channels)
        for item in on { for f in item.frames { p[f * channels + item.channel] = item.value } }
        return p
    }
    private func spans(_ values: [DiarizationInterval]) -> [String] {
        values.map { "\($0.id):\($0.speakerId.split(separator: "-").last!):\($0.startUs)-\($0.endUs)" }
    }

    // Units: input 10 ms frames, internal/output Int64 µs, half-open [start, end).
    func testFrameToMicrosecondMiniAudit() throws {
        let p = probs(frames: 3, [(0, 0..<1, 0.9), (1, 2..<3, 0.9)])
        let e = try NemotronIntervals.derive(probabilities: p, frameCount: 3, channels: 2, durationUs: 25_000, runID: "r")
        XCTAssertEqual(spans(e.regular), ["d0:0:0-10000", "d1:1:20000-25000"])
        XCTAssertEqual(e.regular.map(\.endUs).max(), 25_000)
    }

    func testFramesStartingAtOrAfterDurationAreDropped() throws {
        let p = probs(frames: 4, [(0, 2..<4, 0.9)])
        let e = try NemotronIntervals.derive(probabilities: p, frameCount: 4, channels: 2, durationUs: 20_000, runID: "r")
        XCTAssertTrue(e.regular.isEmpty)
        XCTAssertTrue(e.speakers.isEmpty)
    }

    func testThresholdIsStrictlyGreaterThanHalf() throws {
        let exact = try NemotronIntervals.derive(probabilities: probs(frames: 2, [(0, 0..<2, 0.5)]),
            frameCount: 2, channels: 2, durationUs: 20_000, runID: "r")
        XCTAssertTrue(exact.regular.isEmpty)
        let above = try NemotronIntervals.derive(probabilities: probs(frames: 2, [(0, 0..<1, 0.50001)]),
            frameCount: 2, channels: 2, durationUs: 20_000, runID: "r")
        XCTAssertEqual(spans(above.regular), ["d0:0:0-10000"])
    }

    func testNoMinimumLengthPaddingOrGapFilling() throws {
        let p = probs(frames: 5, [(0, 0..<1, 0.9), (0, 2..<3, 0.9)])
        let e = try NemotronIntervals.derive(probabilities: p, frameCount: 5, channels: 2, durationUs: 50_000, runID: "r")
        XCTAssertEqual(spans(e.regular), ["d0:0:0-10000", "d1:0:20000-30000"])
        XCTAssertEqual(e.regular.map { $0.endUs - $0.startUs }, [10_000, 10_000])
    }

    func testOverlapStaysRegularAndLeavesExclusive() throws {
        // A frames 0..<4, B frames 2..<6: frames 2,3 have two active channels.
        let p = probs(frames: 6, [(0, 0..<4, 0.9), (1, 2..<6, 0.8)])
        let e = try NemotronIntervals.derive(probabilities: p, frameCount: 6, channels: 2, durationUs: 60_000, runID: "r")
        XCTAssertEqual(spans(e.regular), ["d0:0:0-40000", "d1:1:20000-60000"])
        XCTAssertEqual(spans(e.exclusive), ["e0:0:0-20000", "e1:1:40000-60000"])
        XCTAssertTrue(e.regular.allSatisfy { $0.confidence == nil } && e.exclusive.allSatisfy { $0.confidence == nil })
    }

    func testAdjacentSpeakersTouchWithoutOverlap() throws {
        let p = probs(frames: 4, [(0, 0..<2, 0.9), (1, 2..<4, 0.9)])
        let e = try NemotronIntervals.derive(probabilities: p, frameCount: 4, channels: 2, durationUs: 40_000, runID: "r")
        XCTAssertEqual(spans(e.exclusive), ["e0:0:0-20000", "e1:1:20000-40000"])
        XCTAssertEqual(e.regular[0].endUs, e.regular[1].startUs)
    }

    func testSpeakersAreUsedChannelsInArrivalOrderAndScopedToRun() throws {
        let p = probs(frames: 3, channels: 4, [(3, 0..<1, 0.9), (1, 1..<2, 0.9)])
        let e = try NemotronIntervals.derive(probabilities: p, frameCount: 3, channels: 4, durationUs: 30_000, runID: "run-a")
        XCTAssertEqual(e.speakers.map(\.id), ["run-a-nm-1", "run-a-nm-3"])
        XCTAssertEqual(e.speakers.map(\.providerId), ["channel-1", "channel-3"])
        XCTAssertEqual(e.speakers.map(\.displayName), ["화자 1", "화자 2"])
        let other = try NemotronIntervals.derive(probabilities: p, frameCount: 3, channels: 4, durationUs: 30_000, runID: "run-b")
        XCTAssertTrue(Set(other.speakers.map(\.id)).isDisjoint(with: e.speakers.map(\.id)))
    }

    func testRejectsShapeMismatchAndNonFiniteValues() {
        XCTAssertThrowsError(try NemotronIntervals.derive(probabilities: [0.9], frameCount: 1, channels: 2, durationUs: 10_000, runID: "r"))
        XCTAssertThrowsError(try NemotronIntervals.derive(probabilities: [.nan, 0], frameCount: 1, channels: 2, durationUs: 10_000, runID: "r"))
        XCTAssertThrowsError(try NemotronIntervals.decode(f32: Data(count: 7), frameCount: 1, channels: 2))
    }

    func testDecodeReadsLittleEndianRowMajor() throws {
        var data = Data()
        for value: Float in [0.25, 0.75, 1, 0] { withUnsafeBytes(of: value.bitPattern.littleEndian) { data.append(contentsOf: $0) } }
        XCTAssertEqual(try NemotronIntervals.decode(f32: data, frameCount: 2, channels: 2), [0.25, 0.75, 1, 0])
    }
}

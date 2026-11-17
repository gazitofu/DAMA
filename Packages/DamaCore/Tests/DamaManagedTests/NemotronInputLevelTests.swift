import Foundation
import XCTest
@testable import DamaManaged

/// turn-continuity AC-02 · AC-03 ⓔ: 입력 음량 함수의 단위·경계 고정 테스트 (합성 표본, 실음성 없음).
final class NemotronInputLevelTests: XCTestCase {
    /// 창마다 일정 진폭 a = 10^(d/20). 일정 진폭 창의 RMS는 |a|다.
    private func windows(_ decibels: [Double]) -> [Float] {
        decibels.flatMap { [Float](repeating: Float(pow(10, $0 / 20)), count: NemotronInputLevel.windowSamples) }
    }
    private func bytes(_ samples: [Float]) -> Data { samples.withUnsafeBufferPointer { Data(buffer: $0) } }
    private let ascending: [Double] = stride(from: -70.0, through: -25.0, by: 5).map { $0 } // ① 10창

    func testConstants() {
        XCTAssertEqual(NemotronInputLevel.version, "nemotron-input-level-v1")
        XCTAssertEqual(NemotronInputLevel.targetDbfs, -20)
        XCTAssertEqual(NemotronInputLevel.maximumGainDb, 24)
        XCTAssertEqual(NemotronInputLevel.knee, 0.7)
        XCTAssertEqual(NemotronInputLevel.windowSamples, 1_600)
        XCTAssertEqual(NemotronInputLevel.percentile, 0.9)
    }

    /// ① P90 = 선형 보간 (h = 0.9·9 = 8.1 → −30 + 0.1·5 = −29.5) → 이득 9.5 dB, 배율 10^(9.5/20).
    func testLinearPercentileAndGain() {
        XCTAssertEqual(ascending.count, 10)
        var samples = windows(ascending)
        let original = samples
        let record = NemotronInputLevel.apply(&samples)
        XCTAssertEqual(record, NemotronInputLevel.Record(gainDb: 9.5, p90Dbfs: -29.5))
        // dB → 배율: 출력 = 입력 × 10^(9.5/20) (무릎 아래라 리미터 없음).
        let ratio = Float(pow(10, 9.5 / 20))
        XCTAssertEqual(samples[0], original[0] * ratio)
        XCTAssertEqual(samples[samples.count - 1], original[samples.count - 1] * ratio)
        XCTAssertEqual(Double(ratio), 2.98538, accuracy: 1e-4)
        // 창 순서는 P90에 영향이 없다(정렬).
        XCTAssertEqual(NemotronInputLevel.measure(windows(ascending.reversed())), record)
    }

    /// ② 전부 −60 dBFS → −20 − (−60) = 40 → 상한 24 dB.
    func testGainIsCappedAtTwentyFour() {
        var samples = windows([Double](repeating: -60, count: 10))
        let original = samples
        let record = NemotronInputLevel.apply(&samples)
        XCTAssertEqual(record, NemotronInputLevel.Record(gainDb: 24, p90Dbfs: -60))
        XCTAssertEqual(samples[0], original[0] * Float(pow(10, 24.0 / 20)))
        XCTAssertEqual(Double(Float(pow(10, 24.0 / 20))), 15.8489, accuracy: 1e-3)
    }

    /// ③ P90 −18.09 (≥ −20) → 이득 0 → 표본을 건드리지 않는다. 무릎 0.7 위 표본(0.9)도 그대로다.
    func testZeroGainLeavesSamplesByteIdentical() {
        var samples = windows(stride(from: -60.0, through: -20.0, by: 5).map { $0 })
            + [Float](repeating: 0.9, count: NemotronInputLevel.windowSamples)
        let original = bytes(samples)
        let record = NemotronInputLevel.apply(&samples)
        XCTAssertEqual(record, NemotronInputLevel.Record(gainDb: 0, p90Dbfs: -18.09))
        XCTAssertEqual(bytes(samples), original)
    }

    /// ④ 끝 표본(< 1,600)은 측정에서 뺀다. 처리에는 포함된다.
    func testTailIsExcludedFromMeasurementOnly() {
        var samples = windows(ascending) + [Float](repeating: 1.0, count: NemotronInputLevel.windowSamples - 1)
        XCTAssertEqual(NemotronInputLevel.measure(samples), NemotronInputLevel.Record(gainDb: 9.5, p90Dbfs: -29.5))
        NemotronInputLevel.apply(&samples)
        XCTAssertEqual(samples[samples.count - 1], NemotronInputLevel.limit(1.0 * Float(pow(10, 9.5 / 20))))
        XCTAssertLessThan(samples[samples.count - 1], 1.0)
    }

    /// 창이 하나도 없으면 처리 없음, P90 = −180.
    func testNoWindowMeansNoProcessing() {
        var samples = [Float](repeating: 0.001, count: NemotronInputLevel.windowSamples - 1)
        let original = bytes(samples)
        XCTAssertEqual(NemotronInputLevel.apply(&samples), NemotronInputLevel.Record(gainDb: 0, p90Dbfs: -180))
        XCTAssertEqual(bytes(samples), original)
        var empty: [Float] = []
        XCTAssertEqual(NemotronInputLevel.apply(&empty), NemotronInputLevel.Record(gainDb: 0, p90Dbfs: -180))
    }

    /// ⑤ 리미터 경계와 부호.
    func testSoftLimiter() {
        XCTAssertEqual(NemotronInputLevel.limit(0.7), 0.7)
        XCTAssertEqual(NemotronInputLevel.limit(0.5), 0.5)
        XCTAssertEqual(NemotronInputLevel.limit(-0.7), -0.7)
        XCTAssertEqual(NemotronInputLevel.limit(0.8), Float(0.7 + 0.3 * tanh(1.0 / 3)), accuracy: 1e-6)
        XCTAssertEqual(NemotronInputLevel.limit(1.0), 0.928478, accuracy: 1e-6)
        XCTAssertEqual(NemotronInputLevel.limit(0.9), 0.874835, accuracy: 1e-6)
        XCTAssertEqual(NemotronInputLevel.limit(-0.8), -NemotronInputLevel.limit(0.8))
        XCTAssertLessThanOrEqual(NemotronInputLevel.limit(10), 1.0)
        XCTAssertGreaterThanOrEqual(NemotronInputLevel.limit(-10), -1.0)
    }

    /// ⑥ 기록은 소수 2자리, 적용값 = 기록값.
    func testRecordedGainIsTheAppliedGain() {
        // −20 − P90이 소수 셋째 자리를 갖도록 −33.833 dBFS 일정 창 10개.
        var samples = windows([Double](repeating: -33.833, count: 10))
        let original = samples
        let record = NemotronInputLevel.apply(&samples)
        XCTAssertEqual(record.gainDb, 13.83)
        XCTAssertEqual(record.p90Dbfs, -33.83)
        XCTAssertEqual(samples[0], original[0] * Float(pow(10, 13.83 / 20)))
    }

    /// AC-03 ⓔ: 입력 음량 키가 없는 기존 meta(필드 13개)는 그대로 해독되고 다시 써도 바이트가 같다.
    func testLegacyMetaWithoutInputLevelRoundTrips() throws {
        let literal = #"{"audioSHA256":"aa","channels":8,"createdAt":"2026-10-31T00:00:00.000Z","durationSeconds":3,"fluidAudioVersion":"0.18.0","frameCount":300,"frameSeconds":0.01,"modelManifestSHA256":"mm","modelRepo":"FluidInference\/nemotron-3-diarization-coreml","preset":"offline","processingSeconds":0.5,"sampleCount":48000,"sessionID":"S"}"#
        let meta = try JSONDecoder().decode(NemotronMeta.self, from: Data(literal.utf8))
        XCTAssertNil(meta.inputLevel)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        XCTAssertEqual(String(decoding: try encoder.encode(meta), as: UTF8.self), literal)
        var current = meta
        current.inputLevel = NemotronInputLevel.Record(gainDb: 22.97, p90Dbfs: -42.97)
        let text = String(decoding: try encoder.encode(current), as: UTF8.self)
        XCTAssertTrue(text.contains(#""inputLevel":{"gainDb":22.97,"p90Dbfs":-42.97,"version":"nemotron-input-level-v1"}"#), text)
        XCTAssertEqual(try JSONDecoder().decode(NemotronMeta.self, from: Data(text.utf8)), current)
    }
}

import Foundation

/// turn-continuity D-05 `nemotron-input-level-v1`: Nemotron에 넣는 표본만 메모리에서 음량을 맞춘다.
/// 분석 WAV·녹음 원본·Soniox 입력·재생은 바꾸지 않는다. 숫자(−20 · 24 · 0.7 · 90번째 백분위수)는 신규 후보값이다
/// (스펙 §01 표 3 실험 3건). 앱 실행기(`FluidNemotronDiarizer`)와 측정 도구가 이 함수를 같이 쓴다.
///
/// 단위 (mini-audit):
/// - 입력: Float32 선형 진폭(−1…1), 16 kHz 모노 표본.
/// - 측정: 1,600표본(0.1초) 겹치지 않는 창마다 RMS dBFS = 20·log10(√평균(x²) + 1e−9), Double로 누적한다.
///   끝 표본(< 1,600)은 측정에서만 뺀다. P90 = 창 값 오름차순의 선형 보간(h = 0.9·(n−1), numpy 기본과 같음).
/// - 이득: g dB = min(24, max(0, −20 − P90))를 소수 2자리로 반올림한 값. 기록값과 적용값이 같다. 감쇠(음수)는 없다.
/// - 출력: g = 0이면 처리 없음(입력과 바이트 동일). g > 0이면 v = x·10^(g/20), |v| > 0.7이면 부호 유지
///   0.7 + 0.3·tanh((|v| − 0.7)/0.3). Float32.
/// - 창이 하나도 없으면(표본 < 1,600) g = 0, P90 = −180 (무음 창 값 20·log10(1e−9)).
public enum NemotronInputLevel {
    public static let version = "nemotron-input-level-v1"
    public static let targetDbfs = -20.0
    public static let maximumGainDb = 24.0
    public static let knee: Float = 0.7
    public static let windowSamples = 1_600
    public static let percentile = 0.9
    public static let emptyDbfs = -180.0

    /// `nemotron-meta.json`의 `inputLevel`. 이득·P90은 소수 2자리.
    public struct Record: Codable, Sendable, Equatable {
        public let version: String
        public let gainDb: Double
        public let p90Dbfs: Double
        public init(version: String = NemotronInputLevel.version, gainDb: Double, p90Dbfs: Double) {
            self.version = version; self.gainDb = gainDb; self.p90Dbfs = p90Dbfs
        }
    }

    public static func measure(_ samples: [Float]) -> Record {
        let count = samples.count / windowSamples
        guard count > 0 else { return Record(gainDb: 0, p90Dbfs: emptyDbfs) }
        var levels = [Double](repeating: 0, count: count)
        samples.withUnsafeBufferPointer { buffer in
            for window in 0..<count {
                var sum = 0.0
                for i in (window * windowSamples)..<((window + 1) * windowSamples) {
                    let value = Double(buffer[i]); sum += value * value
                }
                levels[window] = 20 * log10((sum / Double(windowSamples)).squareRoot() + 1e-9)
            }
        }
        levels.sort()
        let h = percentile * Double(count - 1), low = Int(h.rounded(.down))
        let p90 = low + 1 < count ? levels[low] + (h - Double(low)) * (levels[low + 1] - levels[low]) : levels[low]
        let gain = min(maximumGainDb, max(0, targetDbfs - p90))
        return Record(gainDb: rounded(gain), p90Dbfs: rounded(p90))
    }

    /// 측정한 이득을 표본에 적용하고 기록을 돌려준다. 이득 0이면 표본을 건드리지 않는다.
    @discardableResult
    public static func apply(_ samples: inout [Float]) -> Record {
        let record = measure(samples)
        guard record.gainDb > 0 else { return record }
        let ratio = Float(pow(10, record.gainDb / 20))
        samples.withUnsafeMutableBufferPointer { buffer in
            for i in buffer.indices { buffer[i] = limit(buffer[i] * ratio) }
        }
        return record
    }

    /// 무릎 0.7 소프트 리미터. |v| ≤ 0.7은 그대로.
    public static func limit(_ value: Float) -> Float {
        let magnitude = abs(value)
        guard magnitude > knee else { return value }
        let headroom = 1 - knee
        let shaped = knee + headroom * tanh((magnitude - knee) / headroom)
        return value < 0 ? -shaped : shaped
    }

    static func rounded(_ value: Double) -> Double { (value * 100).rounded() / 100 }
}

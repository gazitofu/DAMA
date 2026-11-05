import Foundation

/// Nemotron 3 frame probabilities -> diarization evidence (`nemotron-intervals-v2`; v1 kept for reproduction).
/// Input: Float32 `[frame x channel]`, 10 ms frames. Output: Int64 microsecond `[start, end)` intervals.
/// No minimum length, padding or gap filling: a single active frame keeps a short interjection.
public enum NemotronIntervals {
    /// How overlap frames feed the exclusive timeline.
    public enum Rule: String, Sendable, CaseIterable {
        /// Only frames with exactly one active channel (kept to reproduce v1 runs).
        case singleActive = "nemotron-intervals-v1"
        /// The most probable active channel, like the P2 exclusive output; exact ties are left out.
        case mostProbable = "nemotron-intervals-v2"
    }
    /// FluidAudio/NeMo default binarization (`> 0.5`); initial design value, not tuned for Korean.
    public static let threshold: Float = 0.5
    public static let frameUs: Int64 = 10_000
    public static let channels = 8

    public struct Evidence: Sendable {
        public var speakers: [Speaker]
        /// Per-channel activity; different channels may overlap.
        public var regular: [DiarizationInterval]
        /// One channel per frame chosen by `Rule`. App-derived, not a provider exclusive output.
        public var exclusive: [DiarizationInterval]
    }

    /// Little-endian Float32, row-major `[frame x channel]`.
    public static func decode(f32 data: Data, frameCount: Int, channels: Int) throws -> [Float] {
        guard frameCount >= 0, channels > 0, data.count == frameCount * channels * 4 else {
            throw ManagedNormalizationError.invalidIntervals
        }
        return data.withUnsafeBytes { raw in
            (0..<(frameCount * channels)).map {
                Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: $0 * 4, as: UInt32.self)))
            }
        }
    }

    public static func derive(probabilities: [Float], frameCount: Int, channels: Int,
                              durationUs: Int64, runID: String, rule: Rule = .mostProbable) throws -> Evidence {
        guard channels > 0, frameCount >= 0, probabilities.count == frameCount * channels, durationUs > 0,
              !runID.isEmpty, probabilities.allSatisfy(\.isFinite) else { throw ManagedNormalizationError.invalidIntervals }
        // Frames starting at or after the audio end are dropped; the last kept frame ends at durationUs.
        let usable = min(frameCount, Int((durationUs + frameUs - 1) / frameUs))
        func time(_ frame: Int) -> Int64 { min(Int64(frame) * frameUs, durationUs) }
        func active(_ frame: Int, _ channel: Int) -> Bool { probabilities[frame * channels + channel] > threshold }

        var regular: [(start: Int64, end: Int64, channel: Int)] = []
        for channel in 0..<channels {
            var open: Int?
            for frame in 0..<usable {
                if active(frame, channel) { if open == nil { open = frame } }
                else if let start = open { regular.append((time(start), time(frame), channel)); open = nil }
            }
            if let start = open { regular.append((time(start), time(usable), channel)) }
        }
        var exclusive: [(start: Int64, end: Int64, channel: Int)] = []
        var current: (start: Int, channel: Int)?
        for frame in 0...usable {
            var only: Int?
            if frame < usable {
                let on = (0..<channels).filter { active(frame, $0) }
                switch rule {
                case .singleActive: if on.count == 1 { only = on[0] }
                case .mostProbable:
                    let top = on.map { probabilities[frame * channels + $0] }.max()
                    let best = on.filter { probabilities[frame * channels + $0] == top }
                    if best.count == 1 { only = best[0] }
                }
            }
            if let open = current, open.channel != only {
                exclusive.append((time(open.start), time(frame), open.channel)); current = nil
            }
            if current == nil, let channel = only { current = (frame, channel) }
        }

        let used = Set(regular.map(\.channel)).sorted()
        let speakers = used.enumerated().map {
            Speaker(id: "\(runID)-nm-\($0.element)", providerId: "channel-\($0.element)", displayName: "화자 \($0.offset + 1)")
        }
        func intervals(_ source: [(start: Int64, end: Int64, channel: Int)], prefix: String) -> [DiarizationInterval] {
            source.sorted { ($0.start, $0.channel) < ($1.start, $1.channel) }.enumerated().map {
                DiarizationInterval(id: "\(prefix)\($0.offset)", startUs: $0.element.start, endUs: $0.element.end,
                                    speakerId: "\(runID)-nm-\($0.element.channel)", confidence: nil)
            }
        }
        return Evidence(speakers: speakers, regular: intervals(regular, prefix: "d"),
                        exclusive: intervals(exclusive, prefix: "e"))
    }
}

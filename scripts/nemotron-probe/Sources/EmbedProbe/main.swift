// Speaker-embedding check for Nemotron-3 channels (2026-10-30, 1b).
// For each channel, takes spans where only that channel is active and compares voice embeddings
// between channels and between the early/late halves of the same channel. Writes similarities only;
// embedding vectors and transcript text are never written.
// Usage: EmbedProbe <offlineModelDir> <probeOutDir> <sessionDir>...
import AVFoundation
import FluidAudio
import Foundation

let threshold: Float = 0.5      // same binarization as the 1a measurement (FluidAudio/NeMo default)
let minSpanSeconds = 1.0        // analysis choice for this probe, not a tuned value
let maxSecondsPerChannel = 240.0 // cap per channel, spans sampled evenly over the recording
let frameSeconds = 0.01
let channels = 8

struct ChannelReport: Codable {
    var ch: Int
    var soloSpans: Int
    var usedSpans: Int
    var usedSeconds: Double
    var earlyLateCosine: Double?
}
struct SessionReport: Codable {
    var session: String
    var channels: [ChannelReport]
    var cosine: [[Double?]]   // channel-mean cosine, indexed like `channels`
}

enum ProbeError: Error { case usage, unsupportedFormat, bufferAllocation }

func readMono16k(_ url: URL) throws -> [Float] {
    let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
    guard file.processingFormat.sampleRate == 16_000, file.processingFormat.channelCount == 1 else {
        throw ProbeError.unsupportedFormat
    }
    guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
        throw ProbeError.bufferAllocation
    }
    try file.read(into: buffer)
    return Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
}

func normalized(_ v: [Float]) -> [Float] {
    let n = sqrt(v.reduce(0) { $0 + $1 * $1 })
    return n > 0 ? v.map { $0 / n } : v
}
func mean(_ vs: [[Float]]) -> [Float]? {
    guard let first = vs.first else { return nil }
    var acc = [Float](repeating: 0, count: first.count)
    for v in vs { for i in acc.indices { acc[i] += v[i] } }
    return normalized(acc)
}
func cosine(_ a: [Float]?, _ b: [Float]?) -> Double? {
    guard let a, let b else { return nil }
    return Double(zip(a, b).reduce(0) { $0 + $1.0 * $1.1 })
}

/// Contiguous runs where `ch` is the only channel above threshold.
func soloSpans(_ probs: [Float], frames: Int, ch: Int) -> [Range<Double>] {
    var spans: [Range<Double>] = []
    var start: Int?
    for f in 0...frames {
        var solo = false
        if f < frames {
            let base = f * channels
            solo = probs[base + ch] > threshold
                && (0..<channels).allSatisfy { $0 == ch || probs[base + $0] <= threshold }
        }
        if solo, start == nil { start = f }
        if !solo, let s = start {
            let span = Double(s) * frameSeconds..<Double(f) * frameSeconds
            if span.upperBound - span.lowerBound >= minSpanSeconds { spans.append(span) }
            start = nil
        }
    }
    return spans
}

/// Evenly sample spans over the recording until the per-channel cap.
func sample(_ spans: [Range<Double>]) -> [Range<Double>] {
    let total = spans.reduce(0) { $0 + ($1.upperBound - $1.lowerBound) }
    guard total > maxSecondsPerChannel else { return spans }
    let k = Int((total / maxSecondsPerChannel).rounded(.up))
    return spans.enumerated().filter { $0.offset % k == 0 }.map(\.element)
}

let args = CommandLine.arguments
guard args.count >= 4 else { throw ProbeError.usage }
let modelDir = URL(fileURLWithPath: args[1], isDirectory: true)
let probeOut = URL(fileURLWithPath: args[2], isDirectory: true)
let manager = OfflineDiarizerManager()
let loadStart = Date()
try await manager.prepareModels(directory: modelDir)
print("embedding models ready in \(String(format: "%.1f", Date().timeIntervalSince(loadStart))) s")

for path in args.dropFirst(3) {
    let session = URL(fileURLWithPath: path, isDirectory: true)
    let id = session.lastPathComponent
    let dir = probeOut.appendingPathComponent(id, isDirectory: true)
    let probsURL = dir.appendingPathComponent("probs.f32")
    guard FileManager.default.fileExists(atPath: probsURL.path) else { print("\(id.prefix(8)) no probs"); continue }
    let raw = try Data(contentsOf: probsURL)
    let probs = raw.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    let frames = probs.count / channels
    let source = ArrayAudioSampleSource(samples: try readMono16k(session.appendingPathComponent("audio/analysis.wav")))

    var reports: [ChannelReport] = []
    var means: [[Float]?] = []
    let start = Date()
    for ch in 0..<channels {
        let all = soloSpans(probs, frames: frames, ch: ch)
        guard !all.isEmpty else { continue }
        let used = sample(all)
        let vectors = try await manager.embedSpans(audioSource: source, spans: used).map(normalized)
        let half = vectors.count / 2
        let earlyLate = half > 0 ? cosine(mean(Array(vectors[..<half])), mean(Array(vectors[half...]))) : nil
        reports.append(ChannelReport(ch: ch, soloSpans: all.count, usedSpans: used.count,
            usedSeconds: (used.reduce(0) { $0 + ($1.upperBound - $1.lowerBound) } * 10).rounded() / 10,
            earlyLateCosine: earlyLate))
        means.append(mean(vectors))
    }
    let matrix = means.map { a in means.map { b in cosine(a, b).map { ($0 * 1000).rounded() / 1000 } } }
    let report = SessionReport(session: id, channels: reports, cosine: matrix)
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(report).write(to: dir.appendingPathComponent("embedding-check.json"))
    print("\(id.prefix(8)) \(reports.count) channels in \(String(format: "%.1f", Date().timeIntervalSince(start))) s")
}

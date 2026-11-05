// Offline Nemotron-3-Diarization probe (2026-10-30, notes/diarization-research/2026-10-30.md).
// Reads each session's analysis.wav and stores the raw [frames x 8] speaker probabilities.
// No network use except the one-time model download; no transcript text is read or written.
// Usage: NemotronProbe <modelCacheDir> <outDir> <sessionDir>...
import AVFoundation
import CryptoKit
import FluidAudio
import Foundation

struct ProbeMeta: Codable {
    var sessionID: String
    var audioSHA256: String
    var sampleCount: Int
    var durationSeconds: Double
    var frameCount: Int
    var frameSeconds: Double
    var channels: Int
    var preset: String
    var fluidAudioVersion: String
    var modelRepo: String
    var modelBundleSHA256: String
    var processingSeconds: Double
    var createdAt: String
}

enum ProbeError: Error { case usage, unsupportedFormat(String), bufferAllocation }

func hex(_ digest: SHA256.Digest) -> String { digest.map { String(format: "%02x", $0) }.joined() }

func sha256(of url: URL) throws -> String {
    hex(SHA256.hash(data: try Data(contentsOf: url, options: .mappedIfSafe)))
}

func readMono16k(_ url: URL) throws -> [Float] {
    let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
    let format = file.processingFormat
    guard format.sampleRate == 16_000, format.channelCount == 1 else {
        throw ProbeError.unsupportedFormat("\(format.sampleRate) Hz, \(format.channelCount) ch")
    }
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else {
        throw ProbeError.bufferAllocation
    }
    try file.read(into: buffer)
    return Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
}

let args = CommandLine.arguments
guard args.count >= 4 else { throw ProbeError.usage }
let cache = URL(fileURLWithPath: args[1], isDirectory: true)
let out = URL(fileURLWithPath: args[2], isDirectory: true)
let fm = FileManager.default
try fm.createDirectory(at: out, withIntermediateDirectories: true)

let config = Nemotron3Config.offline
let loadStart = Date()
let models = try await Nemotron3Models.loadFromHuggingFace(config: config, cacheDirectory: cache)
print("models loaded in \(String(format: "%.1f", Date().timeIntervalSince(loadStart))) s")
let bundle = try fm.subpathsOfDirectory(atPath: cache.path)
    .first { $0.hasSuffix("Nemotron3Diarizer_offline.mlmodelc/coremldata.bin") }
    .map { try sha256(of: cache.appendingPathComponent($0)) } ?? "unknown"
let diarizer = Nemotron3Diarizer(config: config, models: models)

for path in args.dropFirst(3) {
    let session = URL(fileURLWithPath: path, isDirectory: true)
    let id = session.lastPathComponent
    let dest = out.appendingPathComponent(id, isDirectory: true)
    if fm.fileExists(atPath: dest.appendingPathComponent("meta.json").path) {
        print("\(id.prefix(8)) skip (done)"); continue
    }
    let wav = session.appendingPathComponent("audio/analysis.wav")
    let samples = try readMono16k(wav)
    let start = Date()
    let (probabilities, frameCount) = try diarizer.processComplete(samples)
    let elapsed = Date().timeIntervalSince(start)
    try fm.createDirectory(at: dest, withIntermediateDirectories: true)
    try probabilities.withUnsafeBufferPointer { Data(buffer: $0) }
        .write(to: dest.appendingPathComponent("probs.f32"))
    let meta = ProbeMeta(sessionID: id, audioSHA256: try sha256(of: wav), sampleCount: samples.count,
        durationSeconds: Double(samples.count) / 16_000, frameCount: frameCount, frameSeconds: 0.01,
        channels: config.numSpeakers, preset: "offline", fluidAudioVersion: "0.18.0",
        modelRepo: "FluidInference/nemotron-3-diarization-coreml", modelBundleSHA256: bundle,
        processingSeconds: elapsed, createdAt: ISO8601DateFormatter().string(from: Date()))
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(meta).write(to: dest.appendingPathComponent("meta.json"))
    print("\(id.prefix(8)) \(String(format: "%.0f", meta.durationSeconds)) s audio -> \(frameCount) frames in \(String(format: "%.1f", elapsed)) s")
}

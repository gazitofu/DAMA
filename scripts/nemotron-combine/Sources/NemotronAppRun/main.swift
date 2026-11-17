// Usage: NemotronAppRun <modelsRoot containing nemotron-3-diarization> <analysis.wav> <reference probs.f32> [<out dir>]
// Runs the app's FluidNemotronDiarizer once (local only) after the pinned-file check and compares with the reference output.
// turn-continuity AC-12: the runner now applies `NemotronInputLevel` in memory; with <out dir> it writes `probs.f32` and
// `meta.json` (frames, channels, samples, processing seconds, input level). Reads the WAV only; numbers only on stdout.
import DamaManaged
import DamaNemotron
import Foundation

let args = CommandLine.arguments
guard args.count == 4 || args.count == 5 else { print("usage: NemotronAppRun <modelsRoot> <analysis.wav> <probs.f32> [<out dir>]"); exit(2) }
let store = NemotronModelStore(internalRoot: URL(fileURLWithPath: args[1]).deletingLastPathComponent())
let state = store.state()
print("model state \(state.rawValue) dir \(store.directory.path)")
guard state == .ready else { exit(1) }
let start = Date()
let output = try await FluidNemotronDiarizer().diarize(analysisWAV: URL(fileURLWithPath: args[2]), modelDirectory: store.directory)
let wall = Date().timeIntervalSince(start)
let reference = try Data(contentsOf: URL(fileURLWithPath: args[3]))
print("frames \(output.frameCount) channels \(output.channels) samples \(output.sampleCount) processComplete \(String(format: "%.2f", output.processingSeconds)) s wall \(String(format: "%.2f", wall)) s")
print("input level \(output.inputLevel.version) gain \(output.inputLevel.gainDb) dB p90 \(output.inputLevel.p90Dbfs) dBFS")
print("bytes app \(output.probabilities.count) 1a \(reference.count) equal-size \(output.probabilities.count == reference.count) byte-identical \(output.probabilities == reference)")
if args.count == 5 {
    struct Meta: Encodable { let frameCount: Int; let channels: Int; let sampleCount: Int; let processingSeconds: Double; let inputLevel: NemotronInputLevel.Record; let byteIdenticalToReference: Bool }
    let out = URL(fileURLWithPath: args[4], isDirectory: true)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    try output.probabilities.write(to: out.appendingPathComponent("probs.f32"))
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(Meta(frameCount: output.frameCount, channels: output.channels, sampleCount: output.sampleCount,
        processingSeconds: output.processingSeconds, inputLevel: output.inputLevel, byteIdenticalToReference: output.probabilities == reference))
        .write(to: out.appendingPathComponent("meta.json"))
}
if output.probabilities.count == reference.count {
    func floats(_ d: Data) -> [Float] { d.withUnsafeBytes { raw in (0..<(d.count / 4)).map { Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: $0 * 4, as: UInt32.self))) } } }
    let a = floats(output.probabilities), b = floats(reference)
    var maxDiff: Float = 0, flips = 0
    for i in a.indices { maxDiff = max(maxDiff, abs(a[i] - b[i])); if (a[i] > 0.5) != (b[i] > 0.5) { flips += 1 } }
    var appChannels = Set<Int>(), refChannels = Set<Int>()
    for i in a.indices { if a[i] > 0.5 { appChannels.insert(i % output.channels) }; if b[i] > 0.5 { refChannels.insert(i % output.channels) } }
    print("max |diff| \(maxDiff) threshold flips \(flips) of \(a.count) active channels app \(appChannels.count) 1a \(refChannels.count)")
}

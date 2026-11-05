// Usage: NemotronAppRun <modelsRoot containing nemotron-3-diarization> <analysis.wav> <1a probs.f32>
// Runs the app's FluidNemotronDiarizer once (local only) after the pinned-file check and compares with the 1a output.
import DamaManaged
import DamaNemotron
import Foundation

let args = CommandLine.arguments
guard args.count == 4 else { print("usage: NemotronAppRun <modelsRoot> <analysis.wav> <probs.f32>"); exit(2) }
let store = NemotronModelStore(internalRoot: URL(fileURLWithPath: args[1]).deletingLastPathComponent())
let state = store.state()
print("model state \(state.rawValue) dir \(store.directory.path)")
guard state == .ready else { exit(1) }
let start = Date()
let output = try await FluidNemotronDiarizer().diarize(analysisWAV: URL(fileURLWithPath: args[2]), modelDirectory: store.directory)
let wall = Date().timeIntervalSince(start)
let reference = try Data(contentsOf: URL(fileURLWithPath: args[3]))
print("frames \(output.frameCount) channels \(output.channels) samples \(output.sampleCount) processComplete \(String(format: "%.2f", output.processingSeconds)) s wall \(String(format: "%.2f", wall)) s")
print("bytes app \(output.probabilities.count) 1a \(reference.count) equal-size \(output.probabilities.count == reference.count) byte-identical \(output.probabilities == reference)")
if output.probabilities.count == reference.count {
    func floats(_ d: Data) -> [Float] { d.withUnsafeBytes { raw in (0..<(d.count / 4)).map { Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: $0 * 4, as: UInt32.self))) } } }
    let a = floats(output.probabilities), b = floats(reference)
    var maxDiff: Float = 0, flips = 0
    for i in a.indices { maxDiff = max(maxDiff, abs(a[i] - b[i])); if (a[i] > 0.5) != (b[i] > 0.5) { flips += 1 } }
    var appChannels = Set<Int>(), refChannels = Set<Int>()
    for i in a.indices { if a[i] > 0.5 { appChannels.insert(i % output.channels) }; if b[i] > 0.5 { refChannels.insert(i % output.channels) } }
    print("max |diff| \(maxDiff) threshold flips \(flips) of \(a.count) active channels app \(appChannels.count) 1a \(refChannels.count)")
}

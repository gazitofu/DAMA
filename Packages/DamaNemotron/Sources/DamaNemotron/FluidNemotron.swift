import AVFoundation
import DamaManaged
import FluidAudio
import Foundation

/// Nemotron 3 (FluidAudio 0.18.0, offline preset) on this Mac. Reads only verified local model files;
/// `processComplete` sees the whole analysis WAV once so speaker channels stay consistent across the recording.
public actor FluidNemotronDiarizer: LocalDiarizing {
    public init() {}

    public func diarize(analysisWAV: URL, modelDirectory: URL) async throws -> LocalDiarization {
        let samples = try Self.readMono16k(analysisWAV)
        try Task.checkCancellation()
        var config = Nemotron3Config.offline
        config.modelFileName = NemotronModel.bundlePath
        let models = try await Nemotron3Models.load(config: config, directory: modelDirectory)
        try Task.checkCancellation()
        let diarizer = Nemotron3Diarizer(config: config, models: models)
        let start = Date()
        let (probabilities, frameCount) = try diarizer.processComplete(samples)
        let elapsed = Date().timeIntervalSince(start)
        var data = Data(capacity: probabilities.count * 4)
        for value in probabilities { withUnsafeBytes(of: value.bitPattern.littleEndian) { data.append(contentsOf: $0) } }
        return LocalDiarization(probabilities: data, frameCount: frameCount, channels: config.numSpeakers,
                                sampleCount: samples.count, processingSeconds: elapsed)
    }

    static func readMono16k(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let format = file.processingFormat
        guard format.sampleRate == 16_000, format.channelCount == 1,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw ManagedFailure.sourceChanged
        }
        try file.read(into: buffer)
        return Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
    }
}

/// The one network step: fetch the offline bundle into `cache` the way FluidAudio lays it out.
/// The caller verifies the pinned SHA256 list before the files are used.
public enum FluidNemotronDownloader {
    public static func download(into cache: URL) async throws {
        _ = try await Nemotron3Models.loadFromHuggingFace(config: .offline, cacheDirectory: cache)
    }
}

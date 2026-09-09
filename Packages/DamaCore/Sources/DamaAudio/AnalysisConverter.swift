import AVFoundation
import Foundation

enum AnalysisConverter {
    // Synchronously borrowed only by one AVAudioConverter call, never exposed to another task.
    private final class Input: @unchecked Sendable {
        let urls: [URL]
        let format: AVAudioFormat
        let buffer: AVAudioPCMBuffer
        let mono: AVAudioPCMBuffer
        var file: AVAudioFile?
        var index = 0
        var frames: Int64 = 0
        var energy = 0.0
        var mixedEnergy = 0.0
        var failure: Error?

        init(_ urls: [URL], format: AVAudioFormat) throws {
            self.urls = urls
            self.format = format
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8192),
                  let monoFormat = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 1),
                  let mono = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: 8192) else { throw AudioFailure.invalidFormat }
            self.buffer = buffer
            self.mono = mono
        }

        func next(_ count: AVAudioPacketCount, status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
            do {
                while true {
                    if file == nil {
                        guard index < urls.count else { status.pointee = .endOfStream; return nil }
                        file = try AVAudioFile(forReading: urls[index], commonFormat: .pcmFormatFloat32, interleaved: false)
                        index += 1
                        guard file?.processingFormat == format else { throw AudioFailure.invalidFormat }
                    }
                    if let file, file.framePosition >= file.length { self.file = nil; continue }
                    try file?.read(into: buffer, frameCount: min(count, buffer.frameCapacity))
                    if buffer.frameLength == 0 { file = nil; continue }
                    let n = Int(buffer.frameLength)
                    mono.frameLength = buffer.frameLength
                    guard let channels = buffer.floatChannelData, let out = mono.floatChannelData else { throw AudioFailure.invalidFormat }
                    for i in 0..<n {
                        var sum: Float = 0
                        for c in 0..<Int(format.channelCount) {
                            let x = channels[c][i]
                            guard x.isFinite else { throw AudioFailure.invalidFormat }
                            energy += Double(x) * Double(x) / Double(format.channelCount)
                            sum += x / Float(format.channelCount)
                        }
                        mixedEnergy += Double(sum) * Double(sum)
                        out[0][i] = sum
                    }
                    frames += Int64(n)
                    status.pointee = .haveData
                    return mono
                }
            } catch {
                failure = error
                status.pointee = .endOfStream
                return nil
            }
        }
    }

    static func convert(_ urls: [URL], directory: URL) throws -> AudioSource {
        guard let first = urls.first else { throw AudioFailure.incompleteCapture }
        let format = try AVAudioFile(forReading: first, commonFormat: .pcmFormatFloat32, interleaved: false).processingFormat
        guard (1...2).contains(format.channelCount) else { throw AudioFailure.channelConfirmationRequired }
        let input = try Input(urls, format: format)
        guard let outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: input.mono.format, to: outputFormat),
              let buffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 8192) else { throw AudioFailure.invalidFormat }
        converter.primeMethod = .normal
        let sourceFrames = try urls.reduce(Int64(0)) { $0 + (try AVAudioFile(forReading: $1).length) }
        let expected = Int64((Double(sourceFrames) * 16_000 / format.sampleRate).rounded())
        var emitted: Int64 = 0
        let temporary = directory.appendingPathComponent("analysis-\(UUID().uuidString).partial.wav")
        var output: AVAudioFile? = try AVAudioFile(forWriting: temporary, settings: outputFormat.settings,
                                                  commonFormat: .pcmFormatInt16, interleaved: true)
        defer { output?.close() }
        while true {
            var error: NSError?
            let status = converter.convert(to: buffer, error: &error) { count, state in input.next(count, status: state) }
            if let failure = input.failure { throw failure }
            if let error { throw error }
            guard status != .error else { throw AudioFailure.conversionFailed }
            let produced = buffer.frameLength
            // Drop only converter flush padding beyond the complete source sample timeline.
            buffer.frameLength = UInt32(min(Int64(produced), max(0, expected - emitted)))
            if buffer.frameLength > 0 {
                try output?.write(from: buffer)
                emitted += Int64(buffer.frameLength)
            }
            if status == .endOfStream { break }
            guard produced > 0 else { throw AudioFailure.conversionFailed }
        }
        output?.close()
        output = nil
        // A conservative initial guard, not an accuracy metric. Exact antiphase is rejected.
        if format.channelCount > 1, input.energy > 0, input.mixedEnergy / input.energy < 0.01 {
            throw AudioFailure.phaseCancellation
        }
        let measured = try AudioFiles.inspect(temporary)
        guard input.frames == sourceFrames else { throw AudioFailure.invalidFrames }
        guard abs(measured.frames - expected) <= 1 else { throw AudioFailure.invalidFrames }
        let destination = directory.appendingPathComponent("analysis.wav")
        // Never replace an existing derived file whose manifest write might have failed.
        if FileManager.default.fileExists(atPath: destination.path) {
            guard try AudioFiles.hash(destination) == measured.sha256 else { throw AudioFailure.sourceChanged }
        } else { try FileManager.default.moveItem(at: temporary, to: destination) }
        return AudioSource(filename: "analysis.wav", frames: measured.frames, sampleRate: measured.sampleRate,
                           channels: measured.channels, sha256: measured.sha256, rms: measured.rms)
    }
}

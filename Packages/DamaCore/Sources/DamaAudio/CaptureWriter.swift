import AVFoundation
import Foundation

public actor CaptureWriter {
    public let pool: CaptureBufferPool
    private var manifest: AudioManifest
    private let directory: URL
    private var file: AVAudioFile?
    private var partialURL: URL?
    private var chunkFrames: Int64 = 0
    private var written: Int64 = 0
    private let limit: Int64
    private let scratch: AVAudioPCMBuffer
    private var terminalFailure: AudioFailure?
    private var finished = false
    private var level: Float = 0

    public init(root: URL, pool: CaptureBufferPool, title: String) throws {
        self.pool = pool
        (manifest, directory) = try AudioFiles.newSession(root: root, origin: "microphone", title: title)
        limit = Int64((pool.format.sampleRate * 30).rounded())
        guard let scratch = AVAudioPCMBuffer(pcmFormat: pool.format, frameCapacity: 32_768) else { throw AudioFailure.invalidFormat }
        self.scratch = scratch
        manifest.state = "capturing"
        try AudioFiles.writeManifest(manifest, directory: directory)
    }

    public func snapshot() -> (frames: Int64, level: Float, failure: AudioFailure?) {
        (written, level, terminalFailure ?? pool.failure)
    }

    public func drain() {
        guard !finished, terminalFailure == nil else { return }
        do {
            while try pool.consume({ try append($0) }) {}
        } catch {
            terminalFailure = .writeFailed
            pool.close()
        }
    }

    private func append(_ buffer: AVAudioPCMBuffer) throws {
        var offset = 0
        guard let src = buffer.floatChannelData, let dst = scratch.floatChannelData else { throw AudioFailure.invalidFormat }
        while offset < Int(buffer.frameLength) {
            if file == nil {
                partialURL = directory.appendingPathComponent("source/chunk-\(manifest.sources.count).partial.caf")
                guard let partialURL, !FileManager.default.fileExists(atPath: partialURL.path) else { throw AudioFailure.unsafePath }
                file = try AVAudioFile(forWriting: partialURL, settings: pool.format.settings,
                                       commonFormat: .pcmFormatFloat32, interleaved: false)
            }
            let count = min(Int(buffer.frameLength) - offset, Int(limit - chunkFrames), Int(scratch.frameCapacity))
            scratch.frameLength = UInt32(count)
            var peak: Float = 0
            for c in 0..<Int(pool.format.channelCount) {
                dst[c].update(from: src[c] + offset, count: count)
                for i in 0..<count { peak = max(peak, abs(dst[c][i])) }
            }
            try file?.write(from: scratch)
            chunkFrames += Int64(count)
            written += Int64(count)
            offset += count
            level = peak
            if chunkFrames == limit { try finalizeChunk() }
        }
    }

    private func finalizeChunk() throws {
        guard let partialURL, chunkFrames > 0 else { return }
        file?.close()
        file = nil
        let measured = try AudioFiles.inspect(partialURL)
        guard measured.frames == chunkFrames else { throw AudioFailure.invalidFrames }
        let destination = directory.appendingPathComponent("source/chunk-\(manifest.sources.count).caf")
        try FileManager.default.moveItem(at: partialURL, to: destination)
        manifest.sources.append(AudioSource(filename: destination.lastPathComponent, frames: measured.frames,
                                            sampleRate: measured.sampleRate, channels: measured.channels,
                                            sha256: measured.sha256, rms: measured.rms))
        chunkFrames = 0
        self.partialURL = nil
        try AudioFiles.writeManifest(manifest, directory: directory)
    }

    public func finish(reason: AudioFailure? = nil) async throws -> AudioManifest {
        guard !finished else { return manifest }
        pool.close()
        while pool.isProducerActive { await Task.yield() }
        drain()
        let failure = reason ?? terminalFailure ?? pool.failure
        manifest.state = "finalizing"
        try AudioFiles.writeManifest(manifest, directory: directory)
        // A failed write can have partially changed the current file; preserve it as partial.
        if terminalFailure == nil { try finalizeChunk() } else { file?.close(); file = nil }
        let complete = failure == nil && written > 0 && written == pool.receivedFrames
        manifest.state = complete ? "saved" : "interrupted"
        manifest.interruption = complete ? nil : (failure ?? .incompleteCapture).rawValue
        try AudioFiles.writeManifest(manifest, directory: directory)
        finished = true
        return manifest
    }
}

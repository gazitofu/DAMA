import AVFoundation
import Foundation
import Synchronization

/// One tap producer, one writer consumer. Release/acquire publishes fully copied slots.
/// Only this boundary shares mutable PCM storage. Consumer must finish using a slot before release.
public final class CaptureBufferPool: @unchecked Sendable {
    private let buffers: [AVAudioPCMBuffer]
    private let writeIndex = Atomic<Int>(0)
    private let readIndex = Atomic<Int>(0)
    private let failureCode = Atomic<Int>(0)
    private let received = Atomic<Int64>(0)
    private let accepting = Atomic<Bool>(true)
    private let producerActive = Atomic<Bool>(false)
    private var nextSample: Int64? // producer-owned
    public let format: AVAudioFormat

    public init(format: AVAudioFormat, slots: Int = 32, capacity: AVAudioFrameCount = 32_768) throws {
        guard format.commonFormat == .pcmFormatFloat32, !format.isInterleaved,
              format.sampleRate > 0, format.sampleRate <= 384_000,
              (1...8).contains(format.channelCount), slots > 1, capacity > 0 else { throw AudioFailure.invalidFormat }
        self.format = format
        self.buffers = try (0..<slots).map { _ in
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { throw AudioFailure.invalidFormat }
            // Force storage allocation before the callback.
            guard let channels = buffer.floatChannelData else { throw AudioFailure.invalidFormat }
            for c in 0..<Int(format.channelCount) { channels[c].initialize(repeating: 0, count: Int(capacity)) }
            return buffer
        }
    }

    public var receivedFrames: Int64 { received.load(ordering: .acquiring) }
    public var failure: AudioFailure? {
        switch failureCode.load(ordering: .acquiring) {
        case 1: .queueOverflow
        case 2: .invalidFormat
        case 3: .inputDiscontinuity
        default: nil
        }
    }
    public var isProducerActive: Bool { producerActive.load(ordering: .acquiring) }
    public func close() { accepting.store(false, ordering: .releasing) }

    /// No tasks, allocation of PCM, blocking lock, I/O or logging on the audio callback.
    public func offer(_ source: AVAudioPCMBuffer, sampleTime: Int64?) {
        producerActive.store(true, ordering: .releasing)
        defer { producerActive.store(false, ordering: .releasing) }
        guard accepting.load(ordering: .acquiring), failureCode.load(ordering: .relaxed) == 0 else { return }
        guard source.format.sampleRate == format.sampleRate, source.format.channelCount == format.channelCount,
              source.format.commonFormat == .pcmFormatFloat32, !source.format.isInterleaved,
              source.frameLength <= buffers[0].frameCapacity,
              let src = source.floatChannelData else { failureCode.store(2, ordering: .releasing); return }
        if let sampleTime, let nextSample, sampleTime != nextSample {
            failureCode.store(3, ordering: .releasing); return
        }
        let w = writeIndex.load(ordering: .relaxed)
        guard w - readIndex.load(ordering: .acquiring) < buffers.count else {
            failureCode.store(1, ordering: .releasing); return
        }
        let target = buffers[w % buffers.count]
        target.frameLength = source.frameLength
        guard let dst = target.floatChannelData else { failureCode.store(2, ordering: .releasing); return }
        for c in 0..<Int(format.channelCount) {
            dst[c].update(from: src[c], count: Int(source.frameLength))
        }
        nextSample = sampleTime.map { $0 + Int64(source.frameLength) }
        received.wrappingAdd(Int64(source.frameLength), ordering: .releasing)
        writeIndex.store(w + 1, ordering: .releasing)
    }

    func consume(_ body: (AVAudioPCMBuffer) throws -> Void) rethrows -> Bool {
        let r = readIndex.load(ordering: .relaxed)
        guard r < writeIndex.load(ordering: .acquiring) else { return false }
        try body(buffers[r % buffers.count])
        readIndex.store(r + 1, ordering: .releasing)
        return true
    }
}

import AVFoundation
import Foundation
import XCTest
@testable import DamaAudio

final class AudioJourneyTests: XCTestCase {
    private func temporary() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }
        return url
    }
    private func format(_ channels: UInt32 = 1, rate: Double = 48_000) -> AVAudioFormat {
        AVAudioFormat(standardFormatWithSampleRate: rate, channels: channels)!
    }
    private func pcm(_ format: AVAudioFormat, count: UInt32, antiphase: Bool = false, silence: Bool = false) -> AVAudioPCMBuffer {
        let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count)!
        b.frameLength = count
        for c in 0..<Int(format.channelCount) {
            for i in 0..<Int(count) {
                b.floatChannelData![c][i] = silence ? 0 : Float(sin(Double(i) * 0.1) * 0.25) * (antiphase && c == 1 ? -1 : 1)
            }
        }
        return b
    }
    private func wav(_ root: URL, channels: UInt32 = 1, antiphase: Bool = false, silence: Bool = false) throws -> URL {
        let f = format(channels)
        let url = root.appendingPathComponent(UUID().uuidString + ".wav")
        let file = try AVAudioFile(forWriting: url, settings: f.settings)
        try file.write(from: pcm(f, count: 48_000, antiphase: antiphase, silence: silence))
        file.close()
        return url
    }

    func testStateAndTimeBoundaries() throws {
        XCTAssertEqual(CapturePhase.idle.beginning(), .authorizing)
        for state in [CapturePhase.authorizing, .starting, .recording, .finalizing] { XCTAssertEqual(state.beginning(), state) }
        XCTAssertEqual(CapturePhase.recording.stopping(), .finalizing)
        XCTAssertEqual(CapturePhase.finalizing.stopping(), .finalizing)
        XCTAssertEqual(try AudioFiles.microseconds(frames: 48_000, rate: 48_000), 1_000_000)
        XCTAssertEqual(try AudioFiles.microseconds(frames: 1_440_000, rate: 48_000), 30_000_000)
        XCTAssertThrowsError(try AudioFiles.microseconds(frames: -1, rate: 48_000))
        XCTAssertThrowsError(try AudioFiles.microseconds(frames: 1, rate: .nan))
    }

    func testImportAnalysisReloadPreservesOriginalAndSilence() async throws {
        let root = try temporary()
        let source = try wav(root, silence: true)
        let digest = try AudioFiles.hash(source)
        let library = AudioLibrary(root: root)
        let imported = try await library.importFile(source)
        let prepared = try await library.prepareAnalysis(imported.id)
        XCTAssertEqual(prepared.sources.first?.sha256, digest)
        XCTAssertEqual(prepared.sources.first?.rms, 0)
        XCTAssertEqual(prepared.analysis?.frames, 16_000)
        XCTAssertEqual(prepared.analysis?.sampleRate, 16_000)
        XCTAssertEqual(prepared.analysis?.channels, 1)
        XCTAssertEqual(prepared.durationUs, 1_000_000)
        XCTAssertEqual(try AudioFiles.hash(source), digest)
        let reloaded = try await AudioLibrary(root: root).list(recover: true)
        XCTAssertEqual(reloaded.first?.analysis?.sha256, prepared.analysis?.sha256)
    }

    func testStereoSignalAndAntiphaseGuard() async throws {
        let root = try temporary()
        let library = AudioLibrary(root: root)
        let valid = try await library.importFile(wav(root, channels: 2))
        let output = try await library.prepareAnalysis(valid.id)
        XCTAssertGreaterThan(output.analysis!.rms, 0.1)
        let anti = try await library.importFile(wav(root, channels: 2, antiphase: true))
        do { _ = try await library.prepareAnalysis(anti.id); XCTFail("antiphase must not silently cancel") }
        catch { XCTAssertEqual(error as? AudioFailure, .phaseCancellation) }
        let restored = try await library.list()
        XCTAssertEqual(restored.first { $0.id == anti.id }?.analysisError, "phaseCancellation")
        XCTAssertNil(restored.first { $0.id == anti.id }?.analysis)
        XCTAssertFalse(restored.first { $0.id == anti.id }!.sources.isEmpty)
    }

    func testActualCAFChunkBoundaryDrainAndRecovery() async throws {
        let root = try temporary()
        let f = format()
        let pool = try CaptureBufferPool(format: f)
        let writer = try CaptureWriter(root: root, pool: pool, title: "Synthetic PCM")
        let buffer = pcm(f, count: 16_000)
        for n in 0..<91 {
            pool.offer(buffer, sampleTime: Int64(n * 16_000))
            await writer.drain()
        }
        let manifest = try await writer.finish()
        XCTAssertEqual(manifest.state, "saved")
        XCTAssertEqual(manifest.sources.map(\.frames), [1_440_000, 16_000])
        XCTAssertEqual(pool.receivedFrames, 1_456_000)
        let directory = try AudioFiles.session(manifest.id, root: root).appendingPathComponent("audio")
        let file = try AVAudioFile(forReading: directory.appendingPathComponent("source/chunk-1.caf"))
        let read = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 16_000)!
        var offset = 0
        while file.framePosition < file.length {
            try file.read(into: read)
            for i in 0..<Int(read.frameLength) { XCTAssertEqual(read.floatChannelData![0][i], buffer.floatChannelData![0][offset + i]) }
            offset += Int(read.frameLength)
        }
        XCTAssertEqual(offset, 16_000)
        let library = AudioLibrary(root: root)
        let analyzed = try await library.prepareAnalysis(manifest.id)
        XCTAssertEqual(analyzed.analysis?.frames, Int64((1_456_000.0 / 3).rounded()))
        var interrupted = manifest
        interrupted.state = "capturing"
        try AudioFiles.writeManifest(interrupted, directory: directory)
        let partial = directory.appendingPathComponent("source/chunk-2.partial.caf")
        try Data([1, 2, 3]).write(to: partial)
        let recovered = try await library.list(recover: true)
        XCTAssertEqual(recovered[0].state, "interrupted")
        XCTAssertEqual(recovered[0].sources.map(\.sha256), manifest.sources.map(\.sha256))
        XCTAssertEqual(try Data(contentsOf: partial), Data([1, 2, 3]))
    }

    func testOverflowAndDiscontinuityStopInsteadOfDroppingSilently() async throws {
        let root = try temporary()
        let f = format()
        let pool = try CaptureBufferPool(format: f, slots: 2)
        let writer = try CaptureWriter(root: root, pool: pool, title: "Synthetic overflow")
        let buffer = pcm(f, count: 100)
        pool.offer(buffer, sampleTime: 0)
        pool.offer(buffer, sampleTime: 100)
        pool.offer(buffer, sampleTime: 200)
        XCTAssertEqual(pool.failure, .queueOverflow)
        let final = try await writer.finish()
        XCTAssertEqual(final.state, "interrupted")
        XCTAssertEqual(final.interruption, "queueOverflow")
        XCTAssertEqual(final.sources.first?.frames, 200)
        let gapPool = try CaptureBufferPool(format: f)
        gapPool.offer(buffer, sampleTime: 0)
        gapPool.offer(buffer, sampleTime: 101)
        XCTAssertEqual(gapPool.failure, .inputDiscontinuity)
        XCTAssertEqual(gapPool.receivedFrames, 100)
    }

    func testM4AImportAndUnsupportedInput() async throws {
        let root = try temporary()
        let url = root.appendingPathComponent("synthetic.m4a")
        var file: AVAudioFile? = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 96_000
        ])
        try file?.write(from: pcm(file!.processingFormat, count: 48_000))
        file?.close()
        file = nil
        let library = AudioLibrary(root: root)
        let manifest = try await library.importFile(url)
        XCTAssertEqual(manifest.sources.first?.sha256, try AudioFiles.hash(url))
        let output = try await library.prepareAnalysis(manifest.id)
        XCTAssertLessThanOrEqual(abs(output.analysis!.frames - Int64((Double(manifest.sources[0].frames) / 3).rounded())), 1)
        let invalid = root.appendingPathComponent("bad.wav")
        try Data([0, 1]).write(to: invalid)
        do { _ = try await library.importFile(invalid); XCTFail("invalid media") } catch {}
        let all = try await library.list()
        XCTAssertTrue(all.contains { $0.state == "failed" && $0.sources.isEmpty })
    }
}

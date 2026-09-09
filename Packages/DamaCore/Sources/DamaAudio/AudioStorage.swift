import AVFoundation
import CryptoKit
import Foundation

public enum AudioFailure: String, Error, Sendable {
    case invalidFormat, invalidFrames, unsafePath, sourceChanged, corruptChunk
    case channelConfirmationRequired, phaseCancellation, conversionFailed, incompleteCapture
    case queueOverflow, inputDiscontinuity, inputStopped, deviceChanged, sleep, writeFailed
}

public enum CapturePhase: String, Codable, Sendable {
    case idle, authorizing, starting, recording, finalizing, interrupted, failed
    public var busy: Bool { [.authorizing, .starting, .recording, .finalizing].contains(self) }
    public func beginning() -> Self { busy ? self : .authorizing }
    public func stopping() -> Self { self == .recording || self == .starting ? .finalizing : self }
}

public struct AudioSource: Codable, Sendable {
    public let filename: String
    public let frames: Int64
    public let sampleRate: Double
    public let channels: UInt32
    public let sha256: String
    public let rms: Double
}

public struct AudioManifest: Codable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var createdAt: Date
    public var origin: String
    public var state: String
    public var sources: [AudioSource]
    public var interruption: String?
    public var analysis: AudioSource?
    public var analysisError: String?
    public var conversionVersion: String?
    public var durationUs: Int64 {
        guard let first = sources.first else { return 0 }
        return (try? AudioFiles.microseconds(frames: sources.reduce(0) { $0 + $1.frames }, rate: first.sampleRate)) ?? 0
    }
}

public enum AudioFiles {
    public static func root() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: true)
            .appendingPathComponent("com.gazitofu.Dama", isDirectory: true)
    }

    public static func session(_ id: String, root: URL) throws -> URL {
        guard UUID(uuidString: id) != nil else { throw AudioFailure.unsafePath }
        let url = root.appendingPathComponent("Sessions").appendingPathComponent(id)
        try safe(url, root: root)
        return url
    }

    static func safe(_ url: URL, root: URL) throws {
        let base = root.standardizedFileURL.path
        let lexical = url.standardizedFileURL.path
        guard lexical.hasPrefix(base + "/"),
              url.resolvingSymlinksInPath().path == lexical,
              root.resolvingSymlinksInPath().path == base else { throw AudioFailure.unsafePath }
    }

    public static func microseconds(frames: Int64, rate: Double) throws -> Int64 {
        guard frames >= 0, rate.isFinite, rate > 0 else { throw AudioFailure.invalidFrames }
        let us = (Double(frames) / rate * 1_000_000).rounded()
        guard us.isFinite, us >= 0, us < Double(Int64.max) else { throw AudioFailure.invalidFrames }
        return Int64(us)
    }

    public static func hash(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var digest = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty { digest.update(data: data) }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public static func inspect(_ url: URL) throws -> AudioSource {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let format = file.processingFormat
        guard format.sampleRate.isFinite, format.sampleRate > 0, format.channelCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8192) else { throw AudioFailure.invalidFormat }
        var frames: Int64 = 0
        var energy = 0.0
        while file.framePosition < file.length {
            try file.read(into: buffer)
            let n = Int(buffer.frameLength)
            if n == 0 { break }
            guard let channels = buffer.floatChannelData else { throw AudioFailure.invalidFormat }
            for channel in 0..<Int(format.channelCount) {
                for i in 0..<n {
                    let x = Double(channels[channel][i])
                    guard x.isFinite else { throw AudioFailure.invalidFormat }
                    energy += x * x
                }
            }
            frames += Int64(n)
        }
        guard frames > 0, frames == file.length else { throw AudioFailure.invalidFrames }
        return AudioSource(filename: url.lastPathComponent, frames: frames, sampleRate: format.sampleRate,
                           channels: format.channelCount, sha256: try hash(url),
                           rms: sqrt(energy / Double(frames) / Double(format.channelCount)))
    }

    static func writeManifest(_ manifest: AudioManifest, directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: directory.appendingPathComponent("capture-manifest.json"), options: .atomic)
    }

    static func newSession(root: URL, origin: String, title: String) throws -> (AudioManifest, URL) {
        let id = UUID().uuidString
        let directory = try session(id, root: root).appendingPathComponent("audio")
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("source"), withIntermediateDirectories: true)
        let manifest = AudioManifest(id: id, title: title, createdAt: Date(), origin: origin,
                                     state: "preparing", sources: [])
        try writeManifest(manifest, directory: directory)
        return (manifest, directory)
    }
}

public actor AudioLibrary {
    public let root: URL
    public init(root: URL) { self.root = root.standardizedFileURL }

    public func list(recover: Bool = false) throws -> [AudioManifest] {
        let directory = root.appendingPathComponent("Sessions")
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        var result: [AudioManifest] = []
        for session in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            guard UUID(uuidString: session.lastPathComponent) != nil else { continue }
            let audio = try AudioFiles.session(session.lastPathComponent, root: root).appendingPathComponent("audio")
            let path = audio.appendingPathComponent("capture-manifest.json")
            guard FileManager.default.fileExists(atPath: path.path) else { continue }
            try AudioFiles.safe(path, root: root)
            var manifest = try JSONDecoder().decode(AudioManifest.self, from: Data(contentsOf: path))
            guard manifest.id == session.lastPathComponent else { throw AudioFailure.unsafePath }
            if recover && ["preparing", "capturing", "finalizing"].contains(manifest.state) {
                // Only manifest-committed chunks are recovered. Partial/orphan files remain untouched.
                var verified: [AudioSource] = []
                for source in manifest.sources {
                    guard source.filename == URL(fileURLWithPath: source.filename).lastPathComponent else { break }
                    let url = audio.appendingPathComponent("source").appendingPathComponent(source.filename)
                    try AudioFiles.safe(url, root: root)
                    guard let measured = try? AudioFiles.inspect(url), measured.sha256 == source.sha256,
                          measured.frames == source.frames else { break }
                    verified.append(source)
                }
                manifest.sources = verified
                manifest.state = "interrupted"
                manifest.interruption = "appInterrupted"
                try AudioFiles.writeManifest(manifest, directory: audio)
            }
            result.append(manifest)
        }
        return result.sorted { $0.createdAt > $1.createdAt }
    }

    public func importFile(_ source: URL) throws -> AudioManifest {
        let ext = source.pathExtension.lowercased()
        guard ["wav", "m4a"].contains(ext) else { throw AudioFailure.invalidFormat }
        var (manifest, directory) = try AudioFiles.newSession(root: root, origin: "import", title: source.deletingPathExtension().lastPathComponent)
        do {
            let originalHash = try AudioFiles.hash(source)
            let destination = directory.appendingPathComponent("source/original.\(ext)")
            try FileManager.default.copyItem(at: source, to: destination)
            let measured = try AudioFiles.inspect(destination)
            guard measured.sha256 == originalHash, try AudioFiles.hash(source) == originalHash else { throw AudioFailure.sourceChanged }
            manifest.sources = [measured]
            manifest.state = "saved"
            try AudioFiles.writeManifest(manifest, directory: directory)
            return manifest
        } catch {
            manifest.state = "failed"
            manifest.interruption = "importFailed"
            try? AudioFiles.writeManifest(manifest, directory: directory)
            throw error
        }
    }

    public func prepareAnalysis(_ id: String) throws -> AudioManifest {
        let directory = try AudioFiles.session(id, root: root).appendingPathComponent("audio")
        var manifest = try JSONDecoder().decode(AudioManifest.self, from: Data(contentsOf: directory.appendingPathComponent("capture-manifest.json")))
        guard ["saved", "interrupted"].contains(manifest.state), !manifest.sources.isEmpty else { throw AudioFailure.incompleteCapture }
        if let analysis = manifest.analysis {
            guard try AudioFiles.hash(directory.appendingPathComponent("analysis.wav")) == analysis.sha256 else { throw AudioFailure.sourceChanged }
            return manifest
        }
        do {
            let urls = try manifest.sources.map { source -> URL in
                let url = directory.appendingPathComponent("source").appendingPathComponent(source.filename)
                try AudioFiles.safe(url, root: root)
                guard try AudioFiles.hash(url) == source.sha256 else { throw AudioFailure.sourceChanged }
                return url
            }
            let output = try AnalysisConverter.convert(urls, directory: directory)
            manifest.analysis = output
            manifest.analysisError = nil
            manifest.conversionVersion = "pcm-mono-16k-v1"
            try AudioFiles.writeManifest(manifest, directory: directory)
            return manifest
        } catch {
            manifest.analysisError = (error as? AudioFailure)?.rawValue ?? "conversionFailed"
            try? AudioFiles.writeManifest(manifest, directory: directory)
            throw error
        }
    }
}

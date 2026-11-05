import CryptoKit
import Foundation

/// Pinned Nemotron 3 CoreML files (`FluidInference/nemotron-3-diarization-coreml`, offline preset).
/// Captured 2026-10-30 from the 1a measurement download (FluidAudio 0.18.0). Any mismatch means the model is not used.
public enum NemotronModel {
    public static let repo = "FluidInference/nemotron-3-diarization-coreml"
    public static let fluidAudioVersion = "0.18.0"
    public static let preset = "offline"
    public static let folderName = "nemotron-3-diarization"
    public static let bundlePath = "monolithic/v2/Nemotron3Diarizer_offline.mlmodelc"
    public static let channels = 8
    public static let frameSeconds = 0.01

    public struct File: Sendable, Equatable {
        public let path: String
        public let sha256: String
        public let bytes: Int64
    }
    public static let files: [File] = [
        File(path: ".fluidaudio-nemotron3-weights", sha256: "88a9f21b9c55c00d812de0f079565303fc93cbc3a961c1e96bf223928af4aa72", bytes: 14),
        File(path: "learnable_sil_emb.bin", sha256: "d4417b3c0eabdf7c47032fac2b5b5a7ee83d819a6ddda8fd8eaf74e2b5cc4ac7", bytes: 2_048),
        File(path: "monolithic/v2/Nemotron3Diarizer_offline.mlmodelc/analytics/coremldata.bin", sha256: "491594df92282a4f2cef65e96d236e210a5c4627063e37e822ec858aaaad416d", bytes: 243),
        File(path: "monolithic/v2/Nemotron3Diarizer_offline.mlmodelc/coremldata.bin", sha256: "8b790c919c65744648c17290a26d3371e0e55db655310e7f8445080757b0bf08", bytes: 758),
        File(path: "monolithic/v2/Nemotron3Diarizer_offline.mlmodelc/model.mil", sha256: "ea5673d9e9ec785e7c8fb628acd82f9f86214c46b6584eaacdb6faddcb3f0277", bytes: 505_274),
        File(path: "monolithic/v2/Nemotron3Diarizer_offline.mlmodelc/weights/weight.bin", sha256: "bab76e5f190d0e4a4e174e7fcb1e9beea58c6b2be56e665e2cac8fba6d10f7f1", bytes: 198_654_080),
    ]
    /// Digest of the pinned list; part of the Nemotron reuse key.
    public static var manifestSHA256: String { digest(files) }
    static func digest(_ files: [File]) -> String {
        let text = files.map { "\($0.path) \($0.sha256) \($0.bytes)" }.joined(separator: "\n")
        return SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

public enum NemotronModelState: String, Sendable, Equatable {
    case missing, ready, mismatch
}

public enum NemotronModelError: String, Error, Sendable {
    case mismatch, unsafePath
}

/// Model files live in the app's internal storage (`Models/nemotron-3-diarization`), never in user folders.
public struct NemotronModelStore: Sendable {
    public let modelsRoot: URL
    let files: [NemotronModel.File]
    public init(internalRoot: URL) { self.init(modelsRoot: internalRoot.appendingPathComponent("Models"), files: NemotronModel.files) }
    init(modelsRoot: URL, files: [NemotronModel.File]) { self.modelsRoot = modelsRoot.standardizedFileURL; self.files = files }
    public var directory: URL { modelsRoot.appendingPathComponent(NemotronModel.folderName) }

    /// Hashes every pinned file (about 200MB); call off the main actor.
    public func state() -> NemotronModelState { Self.check(directory, files: files) }

    /// A mismatching copy is removed so the next download starts clean.
    @discardableResult
    public func removeIfMismatched() throws -> NemotronModelState {
        let current = state()
        if current == .mismatch { try FileManager.default.removeItem(at: directory) }
        return current
    }

    /// `download` fills the given cache directory the way FluidAudio lays it out (`<cache>/nemotron-3-diarization/...`).
    /// Files are verified in a staging folder before replacing the installed copy.
    public func install(download: @Sendable (URL) async throws -> Void) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: modelsRoot, withIntermediateDirectories: true)
        let staging = modelsRoot.appendingPathComponent(".staging-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: staging) }
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        try await download(staging)
        let downloaded = staging.appendingPathComponent(NemotronModel.folderName)
        guard Self.check(downloaded, files: files) == .ready else { throw NemotronModelError.mismatch }
        if fm.fileExists(atPath: directory.path) { try fm.removeItem(at: directory) }
        try fm.moveItem(at: downloaded, to: directory)
    }

    static func check(_ root: URL, files: [NemotronModel.File]) -> NemotronModelState {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else { return .missing }
        var present = 0
        for file in files {
            let url = root.appendingPathComponent(file.path)
            guard fm.fileExists(atPath: url.path) else { continue }
            present += 1
            guard url.resolvingSymlinksInPath().path == url.path,
                  (try? fm.attributesOfItem(atPath: url.path)[.size] as? Int64) == file.bytes,
                  (try? sha256(url)) == file.sha256 else { return .mismatch }
        }
        if present == files.count { return .ready }
        return present == 0 ? .missing : .mismatch
    }

    static func sha256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// Raw output of one local diarization pass: little-endian Float32 `[frame x channel]`, 10 ms frames.
public struct LocalDiarization: Sendable {
    public let probabilities: Data
    public let frameCount: Int
    public let channels: Int
    public let sampleCount: Int
    public let processingSeconds: Double
    public init(probabilities: Data, frameCount: Int, channels: Int, sampleCount: Int, processingSeconds: Double) {
        self.probabilities = probabilities; self.frameCount = frameCount; self.channels = channels
        self.sampleCount = sampleCount; self.processingSeconds = processingSeconds
    }
}

/// Runs on this Mac only; implementations must not use the network or the audio callback path.
public protocol LocalDiarizing: Sendable {
    func diarize(analysisWAV: URL, modelDirectory: URL) async throws -> LocalDiarization
}

/// Stored beside the probabilities as `raw/nemotron-meta.json`.
public struct NemotronMeta: Codable, Sendable, Equatable {
    public var sessionID: String
    public var audioSHA256: String
    public var sampleCount: Int
    public var durationSeconds: Double
    public var frameCount: Int
    public var frameSeconds: Double
    public var channels: Int
    public var preset: String
    public var fluidAudioVersion: String
    public var modelRepo: String
    public var modelManifestSHA256: String
    public var processingSeconds: Double
    public var createdAt: String
}

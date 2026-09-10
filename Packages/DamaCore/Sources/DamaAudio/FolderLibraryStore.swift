import DamaCore
import Foundation

public struct LibrarySpeech: Codable, Sendable, Identifiable {
    public let id: String
    public let fileURL: URL
    public let sourceHash: String
    public let title: String
    public let recordedAt: Date?
    public let dateSource: String
    public let durationUs: Int64
    public var notes: ConversionNotes
}
public struct LibraryScriptFile: Sendable, Identifiable {
    public var id: String { script.id }
    public let url: URL
    public let hash: String
    public let script: LibraryScript
}

/// File I/O stays outside MainActor. All caller URLs remain security-scoped for the operation.
public actor FolderLibraryStore {
    private let root: URL
    private var scanning = false
    public init(root: URL) { self.root = root.standardizedFileURL }
    public static func prepareDefaultFolder(_ name: String, home: URL, other: URL?, internalRoot: URL) throws -> URL {
        guard ["Speeches", "Scripts"].contains(name) else { throw LibraryFailure.invalidInput }
        let url = home.appendingPathComponent("DAMA", isDirectory: true).appendingPathComponent(name, isDirectory: true)
        // Never replace an existing file or relocate an existing library.
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try validateFolder(url, other: other, internalRoot: internalRoot)
        return url
    }
    private var indexURL: URL { root.appendingPathComponent("library-index.json") }
    private func readIndex() throws -> [LibrarySpeech] {
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return [] }
        return try JSONDecoder().decode([LibrarySpeech].self, from: Data(contentsOf: indexURL))
    }
    private func writeIndex(_ entries: [LibrarySpeech]) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(entries).write(to: indexURL, options: .atomic)
    }
    public static func validateFolder(_ url: URL, other: URL?, internalRoot: URL) throws {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        for value in [other, internalRoot].compactMap({ $0 }) {
            let otherPath = value.standardizedFileURL.resolvingSymlinksInPath().path
            guard path != otherPath, !path.hasPrefix(otherPath + "/"), !otherPath.hasPrefix(path + "/") else { throw LibraryFailure.unsafePath }
        }
        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory == true else { throw LibraryFailure.unsafePath }
    }
    private func safe(_ url: URL) throws {
        guard url.isFileURL, url.standardizedFileURL.path == url.resolvingSymlinksInPath().path else { throw LibraryFailure.unsafePath }
    }
    public func speeches(in folder: URL) async throws -> [LibrarySpeech] {
        guard !scanning else { throw LibraryFailure.invalidInput }
        scanning = true; defer { scanning = false }
        let folder = folder.standardizedFileURL.resolvingSymlinksInPath()
        var index = try readIndex(), found: [LibrarySpeech] = []
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey, .isRegularFileKey], options: [.skipsHiddenFiles])
        for url in files where ["m4a", "wav", "dama-audio"].contains(url.pathExtension.lowercased()) {
            try Task.checkCancellation()
            try safe(url)
            let isBundle = url.pathExtension == "dama-audio"
            let hashURL = isBundle ? url.appendingPathComponent("capture-manifest.json") : url
            try safe(hashURL)
            let hash = try AudioFiles.hash(hashURL)
            if let known = index.first(where: { $0.fileURL == url && $0.sourceHash == hash }) { found.append(known); continue }
            let audio: AudioManifest
            if isBundle {
                let bytes = try Data(contentsOf: hashURL)
                audio = try JSONDecoder().decode(AudioManifest.self, from: bytes)
                guard UUID(uuidString: audio.id) != nil, !audio.sources.isEmpty else { throw LibraryFailure.invalidInput }
                for source in audio.sources {
                    guard source.filename == URL(fileURLWithPath: source.filename).lastPathComponent else { throw LibraryFailure.unsafePath }
                    let file = url.appendingPathComponent("source").appendingPathComponent(source.filename)
                    try safe(file)
                    guard try AudioFiles.hash(file) == source.sha256 else { throw LibraryFailure.changedFile }
                }
                let destination = try AudioFiles.session(audio.id, root: root).appendingPathComponent("audio")
                if !FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try FileManager.default.copyItem(at: url, to: destination)
                } else {
                    let current = try JSONDecoder().decode(AudioManifest.self, from: Data(contentsOf: destination.appendingPathComponent("capture-manifest.json")))
                    guard current.sources.map(\.sha256) == audio.sources.map(\.sha256) else { throw LibraryFailure.changedFile }
                }
            } else { audio = try await AudioLibrary(root: root).importFile(url) }
            let created = isBundle ? audio.createdAt : try url.resourceValues(forKeys: [.creationDateKey]).creationDate
            let entry = LibrarySpeech(id: audio.id, fileURL: url, sourceHash: hash, title: audio.title,
                recordedAt: created, dateSource: isBundle ? "DAMA 녹음 시작 시각" : "원본 파일 생성 시각 (실제 녹음 시각과 다를 수 있음)",
                durationUs: audio.durationUs, notes: ConversionNotes())
            // Re-read after await so another saved note cannot be overwritten by an older index snapshot.
            index = try readIndex(); index.append(entry); try writeIndex(index); found.append(entry)
        }
        return found.sorted {
            let a = $0.recordedAt ?? .distantPast, b = $1.recordedAt ?? .distantPast
            return a == b ? $0.id < $1.id : a > b
        }
    }
    public func saveNotes(_ notes: ConversionNotes, speechID: String) throws {
        try notes.validate()
        var index = try readIndex()
        guard let i = index.firstIndex(where: { $0.id == speechID }) else { throw LibraryFailure.missingFile }
        index[i].notes = notes; try writeIndex(index)
    }
    public func publishRecording(_ record: AudioManifest, to folder: URL) throws {
        guard ["saved", "interrupted"].contains(record.state), !record.sources.isEmpty else { return }
        let destination = folder.appendingPathComponent(record.id + ".dama-audio")
        try safe(destination)
        if FileManager.default.fileExists(atPath: destination.path) { return }
        let source = try AudioFiles.session(record.id, root: root).appendingPathComponent("audio")
        let temp = folder.appendingPathComponent(".recording-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: false)
        try FileManager.default.copyItem(at: source.appendingPathComponent("source"), to: temp.appendingPathComponent("source"))
        // Analysis is derived internally; external recording bundles preserve only their source.
        var copy = record; copy.analysis = nil; copy.analysisError = nil; copy.conversionVersion = nil
        try JSONEncoder().encode(copy).write(to: temp.appendingPathComponent("capture-manifest.json"), options: .withoutOverwriting)
        try FileManager.default.moveItem(at: temp, to: destination)
    }
    public func scripts(in folder: URL) throws -> [LibraryScriptFile] {
        let urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        var result: [LibraryScriptFile] = []
        for url in urls where url.lastPathComponent.hasSuffix(".dama.json") {
            try safe(url)
            let script = try JSONDecoder().decode(LibraryScript.self, from: Data(contentsOf: url))
            try script.validate()
            result.append(LibraryScriptFile(url: url, hash: try AudioFiles.hash(url), script: script))
        }
        guard Set(result.map(\.id)).count == result.count else { throw LibraryFailure.invalidScript }
        return result.sorted { $0.script.createdAt == $1.script.createdAt ? $0.id < $1.id : $0.script.createdAt > $1.script.createdAt }
    }
    public func createScript(_ document: TranscriptDocument, speech: LibrarySpeech, input: ConversionNotes, in folder: URL) throws -> LibraryScriptFile {
        // Resume from existing saved file, never replace a user's edited result.
        if let existing = try scripts(in: folder).first(where: { $0.script.transcript.runId == document.runId }) { return existing }
        let script = try LibraryScript(transcript: document, title: speech.title, recordedAt: speech.recordedAt,
            dateSource: speech.dateSource, input: input)
        let url = folder.appendingPathComponent(UUID().uuidString + ".dama.json")
        return try saveScript(script, to: url, expectedHash: nil)
    }
    public func saveScript(_ script: LibraryScript, to url: URL, expectedHash: String?) throws -> LibraryScriptFile {
        try safe(url); try script.validate()
        if let expectedHash {
            guard try AudioFiles.hash(url) == expectedHash else { throw LibraryFailure.changedFile }
        } else if FileManager.default.fileExists(atPath: url.path) { throw LibraryFailure.changedFile }
        let bytes = try JSONEncoder().encode(script)
        // Immutable local revisions precede the replaceable external active file.
        let history = root.appendingPathComponent("LibraryRevisions").appendingPathComponent(script.revisionID + ".dama.json")
        try FileManager.default.createDirectory(at: history.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: history.path) { try bytes.write(to: history, options: .withoutOverwriting) }
        try bytes.write(to: url, options: .atomic)
        return LibraryScriptFile(url: url, hash: try AudioFiles.hash(url), script: script)
    }
    public func saveCorrection(_ correction: ScriptCorrection, for source: LibraryScriptFile) throws -> LibraryScriptFile {
        let path = source.url.standardizedFileURL.resolvingSymlinksInPath().path
        guard let latest = try scripts(in: source.url.deletingLastPathComponent()).first(where: {
            $0.id == source.id && $0.url.standardizedFileURL.resolvingSymlinksInPath().path == path
        }) else { throw LibraryFailure.changedFile }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard try encoder.encode(latest.script.transcript) == encoder.encode(source.script.transcript) else { throw LibraryFailure.changedFile }
        var candidate = latest.script
        candidate.correction = correction; candidate.revisionID = UUID().uuidString
        return try saveScript(candidate, to: latest.url, expectedHash: latest.hash)
    }
    public func exportMarkdown(_ file: LibraryScriptFile, to destination: URL) throws {
        try safe(destination)
        guard destination.pathExtension.lowercased() == "md",
              !destination.path.hasPrefix(root.path + "/"),
              try AudioFiles.hash(file.url) == file.hash else { throw LibraryFailure.changedFile }
        try TranscriptExporter().write(file.script.markdown(), to: destination)
    }
}

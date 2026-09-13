import DamaCore
import CryptoKit
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
    public let reading: ScriptReadingSnapshot

    init(url: URL, hash: String, script: LibraryScript) {
        self.url = url; self.hash = hash; self.script = script
        reading = ScriptReadingSnapshot(script: script)
    }
}

/// File I/O stays outside MainActor. All caller URLs remain security-scoped for the operation.
public actor FolderLibraryStore {
    private let root: URL
    private let trash: @Sendable (URL) throws -> Void
    private var scanning = false
    private var scriptCache: [String: LibraryScriptFile] = [:]
    private var committedScriptHashes: [String: String] = [:]
    public init(root: URL, trash: @escaping @Sendable (URL) throws -> Void = {
        try FileManager.default.trashItem(at: $0, resultingItemURL: nil)
    }) { self.root = root.standardizedFileURL; self.trash = trash }
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
        let scan = try await scanSpeeches(in: folder)
        guard scan.issues.isEmpty else { throw LibraryFailure.invalidInput }
        return scan.items
    }
    public func scanSpeeches(in folder: URL) async throws -> FileScanResult<LibrarySpeech> {
        guard !scanning else { throw LibraryFailure.invalidInput }
        scanning = true; defer { scanning = false }
        let folder = folder.standardizedFileURL.resolvingSymlinksInPath()
        var index = try readIndex(), found: [LibrarySpeech] = [], issues: [FileScanIssue] = []
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey, .isRegularFileKey], options: [.skipsHiddenFiles])
        for url in files where ["m4a", "wav", "dama-audio"].contains(url.pathExtension.lowercased()) {
            try Task.checkCancellation()
            do {
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
                } else {
                    // Reject malformed audio before import creates an internal session on every refresh.
                    _ = try AudioFiles.inspect(url)
                    audio = try await AudioLibrary(root: root).importFile(url)
                }
                let created = isBundle ? audio.createdAt : try url.resourceValues(forKeys: [.creationDateKey]).creationDate
                let entry = LibrarySpeech(id: audio.id, fileURL: url, sourceHash: hash, title: audio.title,
                    recordedAt: created, dateSource: isBundle ? "DAMA 녹음 시작 시각" : "원본 파일 생성 시각 (실제 녹음 시각과 다를 수 있음)",
                    durationUs: audio.durationUs, notes: ConversionNotes())
                // Re-read after await so another saved note cannot be overwritten by an older index snapshot.
                index = try readIndex(); index.append(entry); try writeIndex(index); found.append(entry)
            } catch is CancellationError { throw CancellationError() }
            catch { issues.append(Self.issue(url, error: error)) }
        }
        let duplicateIDs = Set(Dictionary(grouping: found, by: \.id).filter { $0.value.count > 1 }.keys)
        for entry in found where duplicateIDs.contains(entry.id) {
            issues.append(FileScanIssue(url: entry.fileURL, reason: .duplicateIdentity))
        }
        return FileScanResult(items: found.filter { !duplicateIDs.contains($0.id) }.sorted {
            let a = $0.recordedAt ?? .distantPast, b = $1.recordedAt ?? .distantPast
            return a == b ? $0.id < $1.id : a > b
        }, issues: issues.sorted { $0.id < $1.id })
    }
    public func saveNotes(_ notes: ConversionNotes, speechID: String) throws {
        try notes.validate()
        var index = try readIndex()
        guard let i = index.firstIndex(where: { $0.id == speechID }) else { throw LibraryFailure.missingFile }
        index[i].notes = notes; try writeIndex(index)
    }
    public func storedSpeech(_ id: String) throws -> LibrarySpeech? { try readIndex().first { $0.id == id } }
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
        let scan = try scanScripts(in: folder)
        guard scan.issues.isEmpty else { throw LibraryFailure.invalidScript }
        return scan.items
    }
    public func scanScripts(in folder: URL) throws -> FileScanResult<LibraryScriptFile> {
        let urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        var result: [LibraryScriptFile] = [], issues: [FileScanIssue] = []
        for url in urls where url.lastPathComponent.hasSuffix(".dama.json") {
            try Task.checkCancellation()
            do {
                try safe(url)
                // Read once: the hash and displayed value must describe the same bytes.
                let bytes = try Data(contentsOf: url), hash = Self.hash(bytes)
                if let cached = scriptCache[url.standardizedFileURL.path], cached.hash == hash { result.append(cached) }
                else {
                    let script = try JSONDecoder().decode(LibraryScript.self, from: bytes)
                    try script.validate()
                    result.append(LibraryScriptFile(url: url, hash: hash, script: script))
                }
            } catch is CancellationError { throw CancellationError() }
            catch { issues.append(Self.issue(url, error: error)) }
        }
        let duplicateIDs = Set(Dictionary(grouping: result, by: \.id).filter { $0.value.count > 1 }.keys)
        for file in result where duplicateIDs.contains(file.id) {
            issues.append(FileScanIssue(url: file.url, reason: .duplicateIdentity, itemID: file.id))
        }
        result.removeAll { duplicateIDs.contains($0.id) }
        // Only current, validated, unambiguous files remain cached.
        scriptCache = Dictionary(uniqueKeysWithValues: result.map { ($0.url.standardizedFileURL.path, $0) })
        return FileScanResult(items: result.sorted { $0.script.createdAt == $1.script.createdAt ? $0.id < $1.id : $0.script.createdAt > $1.script.createdAt },
                              issues: issues.sorted { $0.id < $1.id })
    }
    private static func issue(_ url: URL, error: Error) -> FileScanIssue {
        let reason: FileScanIssue.Reason
        switch error {
        case LibraryFailure.unsafePath: reason = .unsafePath
        case LibraryFailure.changedFile: reason = .changedFile
        default: reason = .unreadable
        }
        return FileScanIssue(url: url, reason: reason)
    }
    public func createScript(_ document: TranscriptDocument, speech: LibrarySpeech, input: ConversionNotes, in folder: URL) throws -> LibraryScriptFile {
        // Resume from existing saved file, never replace a user's edited result.
        let scan = try scanScripts(in: folder)
        // A duplicate identity must be resolved before creating another copy.
        guard !scan.issues.contains(where: { $0.itemID == document.runId }) else { throw LibraryFailure.invalidScript }
        if let existing = scan.items.first(where: { $0.script.transcript.runId == document.runId }) { return existing }
        let script = try LibraryScript(transcript: document, title: speech.title, recordedAt: speech.recordedAt,
            dateSource: speech.dateSource, input: input)
        let url = folder.appendingPathComponent(UUID().uuidString + ".dama.json")
        return try saveScript(script, to: url, expectedHash: nil)
    }
    public func saveScript(_ script: LibraryScript, to url: URL, expectedHash: String?) throws -> LibraryScriptFile {
        try safe(url); try script.validate()
        guard script.snapshotTitle == nil, !url.standardizedFileURL.path.hasPrefix(revisionFolder.path + "/") else { throw LibraryFailure.unsafePath }
        if let expectedHash {
            guard try AudioFiles.hash(url) == expectedHash else { throw LibraryFailure.changedFile }
        } else if FileManager.default.fileExists(atPath: url.path) { throw LibraryFailure.changedFile }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(script)
        // Immutable local revisions precede the replaceable external active file.
        _ = try writeRevision(script, bytes: bytes)
        if let expectedHash { guard try AudioFiles.hash(url) == expectedHash else { throw LibraryFailure.changedFile } }
        try bytes.write(to: url, options: .atomic)
        let result = LibraryScriptFile(url: url, hash: Self.hash(bytes), script: script)
        scriptCache[url.standardizedFileURL.path] = result
        committedScriptHashes[url.standardizedFileURL.path] = result.hash
        return result
    }
    private static func hash(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
    private var revisionFolder: URL { root.appendingPathComponent("LibraryRevisions") }
    private func revisionURL(_ id: String) throws -> URL {
        guard UUID(uuidString: id) != nil else { throw LibraryFailure.unsafePath }
        let url = revisionFolder.appendingPathComponent(id + ".dama.json")
        try safe(url); return url
    }
    private func writeRevision(_ script: LibraryScript, bytes: Data) throws -> Data {
        let url = try revisionURL(script.revisionID)
        try FileManager.default.createDirectory(at: revisionFolder, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path) {
            let previous = try Data(contentsOf: url)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            guard try encoder.encode(JSONDecoder().decode(LibraryScript.self, from: previous)) == bytes else {
                throw LibraryFailure.changedFile
            }
            return previous
        }
        try bytes.write(to: url, options: .withoutOverwriting)
        return bytes
    }
    /// Merge only changes committed by this actor (or the exact caller bytes). Unknown external edits fail closed.
    private func latestForMerge(_ source: LibraryScriptFile) throws -> LibraryScriptFile {
        try safe(source.url)
        guard source.script.snapshotTitle == nil, !source.url.path.hasPrefix(revisionFolder.path + "/") else { throw LibraryFailure.unsafePath }
        let bytes = try Data(contentsOf: source.url), hash = Self.hash(bytes)
        guard hash == source.hash || committedScriptHashes[source.url.standardizedFileURL.path] == hash else { throw LibraryFailure.changedFile }
        let scan = try scanScripts(in: source.url.deletingLastPathComponent())
        guard scan.items.contains(where: { $0.id == source.id && $0.url.standardizedFileURL == source.url.standardizedFileURL && $0.hash == hash })
        else { throw LibraryFailure.changedFile }
        let latest = try JSONDecoder().decode(LibraryScript.self, from: bytes)
        try latest.validate()
        guard latest.id == source.id, latest.snapshotTitle == nil,
              try latest.sourceFingerprint() == source.script.sourceFingerprint() else { throw LibraryFailure.changedFile }
        return LibraryScriptFile(url: source.url, hash: hash, script: latest)
    }
    public func saveTitle(_ title: String, for source: LibraryScriptFile) throws -> LibraryScriptFile {
        let latest = try latestForMerge(source)
        guard latest.script.title == source.script.title || latest.script.title == title else { throw LibraryFailure.changedFile }
        guard latest.script.title != title else { return latest }
        var candidate = latest.script; try candidate.renameTitle(title)
        return try saveScript(candidate, to: latest.url, expectedHash: latest.hash)
    }
    public func validateCurrent(_ source: LibraryScriptFile) throws {
        guard try latestForMerge(source).hash == source.hash else { throw LibraryFailure.changedFile }
    }
    public func saveParagraph(_ block: ScriptBlock, text: String, for source: LibraryScriptFile) throws -> LibraryScriptFile {
        let latest = try latestForMerge(source)
        var candidate = latest.script; try candidate.editParagraph(block, text: text)
        guard candidate.revisionID != latest.script.revisionID else { return latest }
        return try saveScript(candidate, to: latest.url, expectedHash: latest.hash)
    }
    public func applyPendingCorrection(for source: LibraryScriptFile) throws -> LibraryScriptFile {
        let latest = try latestForMerge(source)
        guard latest.script.correction?.id == source.script.correction?.id else { throw LibraryFailure.changedFile }
        guard let correction = try ContextCorrection.reapplyingPending(in: latest.script) else { return latest }
        return try saveCorrection(correction, for: latest)
    }
    public func saveCorrection(_ correction: ScriptCorrection, for source: LibraryScriptFile) throws -> LibraryScriptFile {
        let latest = try latestForMerge(source)
        try correction.validate(transcript: latest.script.transcript)
        var candidate = latest.script
        if correction.state == .completed {
            // Legacy results remain readable, but only new, identified completions create history.
            if let completionID = correction.id {
                if (candidate.versions ?? []).contains(where: { $0.number > 0 && $0.correctionID == completionID }) { return latest }
                var versions = candidate.versions ?? []
                if versions.isEmpty {
                    var before = candidate
                    if before.correction?.state != .completed { before.correction = nil }
                    versions.append(try snapshot(before, number: 0, completionID: completionID, date: correction.startedAt))
                }
                candidate.correction = correction; candidate.showsOriginal = nil
                versions.append(try snapshot(candidate, number: versions.count, completionID: completionID, date: correction.completedAt ?? correction.startedAt))
                candidate.versions = versions
            } else { candidate.correction = correction }
        } else {
            // A later failed/cancelled attempt cannot erase a completed result.
            if candidate.correction?.state == .completed { return latest }
            candidate.correction = correction
        }
        candidate.revisionID = UUID().uuidString
        return try saveScript(candidate, to: latest.url, expectedHash: latest.hash)
    }
    private func snapshot(_ source: LibraryScript, number: Int, completionID: String, date: Date) throws -> ScriptVersion {
        var snapshot = source; snapshot.revisionID = UUID().uuidString; snapshot.versions = nil
        snapshot.snapshotTitle = number == 0 ? "AI 보정 전" : "AI 보정 \(number)"
        try snapshot.validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try writeRevision(snapshot, bytes: encoder.encode(snapshot))
        return ScriptVersion(revisionID: snapshot.revisionID, sha256: Self.hash(bytes), number: number,
            correctionID: completionID, createdAt: date)
    }
    public func readVersion(_ version: ScriptVersion, for current: LibraryScriptFile) throws -> LibraryScriptFile {
        try version.validate()
        guard current.script.snapshotTitle == nil, current.script.versions?.contains(version) == true,
              try AudioFiles.hash(current.url) == current.hash else { throw LibraryFailure.changedFile }
        let url = try revisionURL(version.revisionID), bytes = try Data(contentsOf: url)
        guard Self.hash(bytes) == version.sha256 else { throw LibraryFailure.changedFile }
        let script = try JSONDecoder().decode(LibraryScript.self, from: bytes)
        try script.validate()
        guard script.id == current.id, script.revisionID == version.revisionID, script.snapshotTitle == version.title,
              try script.sourceFingerprint() == current.script.sourceFingerprint() else { throw LibraryFailure.invalidScript }
        return LibraryScriptFile(url: url, hash: version.sha256, script: script)
    }
    public func exportMarkdown(_ file: LibraryScriptFile, to destination: URL) throws {
        try safe(destination)
        guard destination.pathExtension.lowercased() == "md",
              !destination.path.hasPrefix(root.path + "/"),
              try AudioFiles.hash(file.url) == file.hash else { throw LibraryFailure.changedFile }
        try TranscriptExporter().write(file.script.markdown(), to: destination)
    }

    public func exportEvaluation(_ file: LibraryScriptFile, cost: MonthlyOperatingCost,
                                 protectedSpeechURLs: [URL], to destination: URL) async throws {
        try safe(destination); try safe(file.url)
        try await FileSessionRepository(rootURL: root).validateExportDestination(destination)
        let path = destination.standardizedFileURL.path
        guard destination.pathExtension.lowercased() == "json",
              !destination.lastPathComponent.lowercased().hasSuffix(".dama.json"),
              !protectedSpeechURLs.contains(where: {
                  let source = $0.standardizedFileURL.resolvingSymlinksInPath().path
                  return path == source || path.hasPrefix(source + "/")
              }),
              try AudioFiles.hash(file.url) == file.hash else { throw LibraryFailure.changedFile }
        try TranscriptExporter().write(file.script.evaluationData(cost: cost), to: destination)
    }

    private func validateDeletion(_ url: URL, in folder: URL) throws {
        guard !scanning else { throw LibraryFailure.invalidInput }
        try safe(url)
        let folder = folder.standardizedFileURL.resolvingSymlinksInPath()
        try Self.validateFolder(folder, other: nil, internalRoot: root)
        guard url.standardizedFileURL.deletingLastPathComponent() == folder else { throw LibraryFailure.unsafePath }
    }
    public func trashScript(_ file: LibraryScriptFile, in folder: URL) throws {
        try validateDeletion(file.url, in: folder)
        guard file.url.lastPathComponent.hasSuffix(".dama.json"),
              try AudioFiles.hash(file.url) == file.hash else { throw LibraryFailure.changedFile }
        try trash(file.url)
        scriptCache.removeValue(forKey: file.url.standardizedFileURL.path)
    }
    public func trashSpeech(_ speech: LibrarySpeech, in folder: URL) throws {
        try validateDeletion(speech.fileURL, in: folder)
        let bundle = speech.fileURL.pathExtension == "dama-audio"
        let hashURL = bundle ? speech.fileURL.appendingPathComponent("capture-manifest.json") : speech.fileURL
        try safe(hashURL)
        guard try AudioFiles.hash(hashURL) == speech.sourceHash else { throw LibraryFailure.changedFile }
        if bundle {
            let record = try JSONDecoder().decode(AudioManifest.self, from: Data(contentsOf: hashURL))
            guard record.id == speech.id, !record.sources.isEmpty else { throw LibraryFailure.changedFile }
            for source in record.sources {
                guard source.filename == URL(fileURLWithPath: source.filename).lastPathComponent else { throw LibraryFailure.unsafePath }
                let url = speech.fileURL.appendingPathComponent("source").appendingPathComponent(source.filename)
                try safe(url)
                guard try AudioFiles.hash(url) == source.sha256 else { throw LibraryFailure.changedFile }
            }
        }
        // Keep internal audio, run results, index identity and revisions for connected Scripts/recovery.
        try trash(speech.fileURL)
    }
}

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
    /// usage-bundle1 녹음 표시 제목. 구 인덱스(키 8)는 nil로 읽고, nil이면 인코드 시 키를 쓰지 않는다.
    public var displayTitle: String? = nil
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

/// List-level fields of one Script file, taken from bytes that were decoded and validated
/// (library-script.md "읽기 계산·파일 I/O"). Opening the Script still re-reads and re-hashes the file.
public struct LibraryScriptSummary: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public private(set) var url: URL
    public let hash: String
    public let title: String
    public let createdAt: Date
    public let sessionId: String
    public let engine: EngineKind
    public let sourceAudioSHA256: String?
    /// usage-bundle2 결과 보관: 사람이 고친 결과인가(`LibraryScript.hasHumanEdits`).
    public let hasHumanEdits: Bool

    init(url: URL, hash: String, script: LibraryScript) {
        id = script.id; self.url = url; self.hash = hash; title = script.title; createdAt = script.createdAt
        sessionId = script.transcript.sessionId; engine = script.transcript.provenance.engine
        sourceAudioSHA256 = script.transcript.provenance.sourceAudioSHA256
        hasHumanEdits = script.hasHumanEdits
    }
    public init(_ file: LibraryScriptFile) { self.init(url: file.url, hash: file.hash, script: file.script) }

    /// The cached entry, addressed by the URL of the current folder listing.
    func at(_ url: URL) -> LibraryScriptSummary { var copy = self; copy.url = url; return copy }
}

/// Fields that decide how results are grouped and ordered in the library.
public protocol ScriptListing: Identifiable where ID == String {
    var createdAt: Date { get }
    var sessionId: String { get }
    var engine: EngineKind { get }
}
extension LibraryScriptSummary: ScriptListing {}
extension LibraryScriptFile: ScriptListing {
    public var createdAt: Date { script.createdAt }
    public var sessionId: String { script.transcript.sessionId }
    public var engine: EngineKind { script.transcript.provenance.engine }
}

/// Collapses multiple processing results for one Speech into one library row.
/// All files remain available to the reader's "다른 결과 보기" menu.
/// usage-bundle2 대표 결과: createdAt이 가장 늦은 것, 같으면 id 사전순 앞. 엔진 등급은 보지 않는다.
public enum ScriptResultPresentation {
    public static func primaryFiles<T: ScriptListing>(in files: [T]) -> [T] {
        Dictionary(grouping: files, by: \.sessionId).values
            .compactMap(primaryFile)
            .sorted(by: newestFirst)
    }

    public static func primaryFile<T: ScriptListing>(in files: [T]) -> T? {
        files.max { lhs, rhs in
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id > rhs.id
        }
    }

    private static func newestFirst<T: ScriptListing>(_ lhs: T, _ rhs: T) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        return lhs.id < rhs.id
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
    /// usage-bundle1: 녹음 표시 제목을 인덱스에만 쓴다(같은 id 항목 전부, 원자 쓰기). 스크립트 파일·사본은 쓰지 않는다.
    /// 입력은 다듬지 않는다. 빈값·공백뿐이면 invalidInput, 없는 id면 missingFile.
    public func saveDisplayTitle(_ title: String, speechID: String) throws -> LibrarySpeech {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LibraryFailure.invalidInput }
        var index = try readIndex()
        let positions = index.indices.filter { index[$0].id == speechID }
        guard let first = positions.first else { throw LibraryFailure.missingFile }
        for i in positions { index[i].displayTitle = title }
        try writeIndex(index)
        return index[first]
    }
    /// 인덱스 전체(찾지 못한 파일·휴지통 항목 포함)의 녹음 id. 스크립트 연결 판정(sessionId == id)에 쓴다.
    public func indexedSpeechIDs() throws -> Set<String> { Set(try readIndex().map(\.id)) }
    /// 인덱스 전체(찾지 못한 파일·휴지통 항목 포함)의 표시 제목. id → displayTitle.
    public func displayTitles() throws -> [String: String] {
        Dictionary(try readIndex().compactMap { entry in entry.displayTitle.map { (entry.id, $0) } }, uniquingKeysWith: { first, _ in first })
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
    /// Bump when the summary fields or the meaning of `LibraryScript.validate()` change:
    /// cached entries then stop counting as validated and every file is decoded again once.
    static let summaryVersion = 2
    private struct SummaryCache: Codable { var version: Int; var entries: [LibraryScriptSummary] }
    private var summaryCacheURL: URL { root.appendingPathComponent("library-script-summaries.json") }
    /// Decodes performed by summary scans and `loadScript` (test probe for cache use).
    private(set) var scriptDecodeCount = 0

    /// A missing, unreadable or older cache is an empty cache; the files stay the source of truth.
    private func readSummaryCache() -> [String: LibraryScriptSummary] {
        guard let data = try? Data(contentsOf: summaryCacheURL),
              let cache = try? JSONDecoder().decode(SummaryCache.self, from: data),
              cache.version == Self.summaryVersion else { return [:] }
        return Dictionary(cache.entries.map { ($0.url.standardizedFileURL.path, $0) }, uniquingKeysWith: { first, _ in first })
    }
    private func writeSummaryCache(_ entries: [LibraryScriptSummary]) {
        // A failed cache write only costs a decode on the next launch.
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try? JSONEncoder().encode(SummaryCache(version: Self.summaryVersion, entries: entries))
            .write(to: summaryCacheURL, options: .atomic)
    }

    /// Lists Scripts without decoding files whose bytes match a summary that was validated before.
    /// Every file is still read and hashed; changed or new files are decoded and validated here.
    public func scanScriptSummaries(in folder: URL) throws -> FileScanResult<LibraryScriptSummary> {
        let urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        let cached = readSummaryCache()
        var result: [LibraryScriptSummary] = [], issues: [FileScanIssue] = []
        for url in urls where url.lastPathComponent.hasSuffix(".dama.json") {
            try Task.checkCancellation()
            do {
                try safe(url)
                let bytes = try Data(contentsOf: url), hash = Self.hash(bytes), key = url.standardizedFileURL.path
                if let hit = cached[key], hit.hash == hash { result.append(hit.at(url)); continue }
                if let open = scriptCache[key], open.hash == hash { result.append(LibraryScriptSummary(open).at(url)); continue }
                scriptDecodeCount += 1
                let script = try JSONDecoder().decode(LibraryScript.self, from: bytes)
                try script.validate()
                result.append(LibraryScriptSummary(url: url, hash: hash, script: script))
            } catch is CancellationError { throw CancellationError() }
            catch { issues.append(Self.issue(url, error: error)) }
        }
        let duplicateIDs = Set(Dictionary(grouping: result, by: \.id).filter { $0.value.count > 1 }.keys)
        for summary in result where duplicateIDs.contains(summary.id) {
            issues.append(FileScanIssue(url: summary.url, reason: .duplicateIdentity, itemID: summary.id))
        }
        result.removeAll { duplicateIDs.contains($0.id) }
        // Opened files stay cached only while their path and bytes are still listed.
        let listed = Dictionary(result.map { ($0.url.standardizedFileURL.path, $0.hash) }, uniquingKeysWith: { first, _ in first })
        scriptCache = scriptCache.filter { listed[$0.key] == $0.value.hash }
        // The cache mirrors this folder's valid listing; rewrite only when it changed.
        let byPath: (LibraryScriptSummary, LibraryScriptSummary) -> Bool = { $0.url.path < $1.url.path }
        let entries = result.map { $0.at($0.url.standardizedFileURL) }.sorted(by: byPath)
        if entries != cached.values.sorted(by: byPath) { writeSummaryCache(entries) }
        return FileScanResult(items: result.sorted { $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt > $1.createdAt },
                              issues: issues.sorted { $0.id < $1.id })
    }

    /// Reads one listed Script. Bytes that no longer match the listing are `changedFile`; the caller rescans.
    public func loadScript(_ summary: LibraryScriptSummary) throws -> LibraryScriptFile {
        try safe(summary.url)
        let key = summary.url.standardizedFileURL.path
        let bytes = try Data(contentsOf: summary.url), hash = Self.hash(bytes)
        guard hash == summary.hash else { throw LibraryFailure.changedFile }
        if let open = scriptCache[key], open.hash == hash { return open }
        scriptDecodeCount += 1
        let script = try JSONDecoder().decode(LibraryScript.self, from: bytes)
        try script.validate()
        guard script.id == summary.id else { throw LibraryFailure.changedFile }
        let file = LibraryScriptFile(url: summary.url, hash: hash, script: script)
        scriptCache[key] = file
        return file
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
        let scan = try scanScriptSummaries(in: folder)
        // A duplicate identity must be resolved before creating another copy.
        guard !scan.issues.contains(where: { $0.itemID == document.runId }) else { throw LibraryFailure.invalidScript }
        // A Script's id is its transcript runId (LibraryScript.validate).
        if let existing = scan.items.first(where: { $0.id == document.runId }) { return try loadScript(existing) }
        let script = try LibraryScript(transcript: document, title: LibraryTitles.speech(speech), recordedAt: speech.recordedAt,
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
    var revisionFolder: URL { root.appendingPathComponent("LibraryRevisions") }
    /// usage-bundle2 새 배치 `LibraryRevisions/<스크립트 ID>/<revisionID>.dama.json.deflate` (raw DEFLATE).
    func revisionURL(scriptID: String, revisionID: String) throws -> URL {
        guard InternalStoragePaths.isSafeScriptID(scriptID), UUID(uuidString: revisionID) != nil else { throw LibraryFailure.unsafePath }
        let url = revisionFolder.appendingPathComponent(scriptID, isDirectory: true)
            .appendingPathComponent(revisionID + RevisionCodec.compressedSuffix)
        try safe(url); return url
    }
    /// 구 배치 `LibraryRevisions/<revisionID>.dama.json`. 읽기와 정리 이전에만 쓴다.
    func legacyRevisionURL(_ revisionID: String) throws -> URL {
        guard UUID(uuidString: revisionID) != nil else { throw LibraryFailure.unsafePath }
        let url = revisionFolder.appendingPathComponent(revisionID + RevisionCodec.legacySuffix)
        try safe(url); return url
    }
    /// 같은 폴더 임시 이름에 쓴 뒤 덮어쓰기 없는 이동으로만 만든다(대상이 있으면 실패). 부분 기록 파일은 보이지 않는다.
    /// 이력 파일 쓰기는 이 actor 안에서만 한다(usage-bundle2 AC-06).
    func writeNewRevision(_ stored: Data, to url: URL) throws {
        let folder = url.deletingLastPathComponent()
        try safe(url)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let temporary = folder.appendingPathComponent(".tmp-\(UUID().uuidString)")
        try stored.write(to: temporary, options: .withoutOverwriting)
        do { try FileManager.default.moveItem(at: temporary, to: url) }
        catch {
            try? FileManager.default.removeItem(at: temporary)
            if FileManager.default.fileExists(atPath: url.path) { throw LibraryFailure.changedFile }
            throw error
        }
    }
    /// 압축을 푼 이력 바이트와 그 파일. 새 배치를 먼저 찾고 없으면 구 배치. 풀 수 없으면 손상(`invalidScript`).
    func readRevision(scriptID: String, revisionID: String) throws -> (url: URL, fileBytes: Data, bytes: Data) {
        let url = try revisionURL(scriptID: scriptID, revisionID: revisionID)
        if FileManager.default.fileExists(atPath: url.path) {
            let stored = try Data(contentsOf: url)
            return (url, stored, try RevisionCodec.inflate(stored))
        }
        let legacy = try legacyRevisionURL(revisionID)
        let stored = try Data(contentsOf: legacy)
        return (legacy, stored, stored)
    }
    /// 같은 바이트가 이미 있으면 그대로 두고, 없으면 압축해 임시 이름에 쓴 뒤 덮어쓰기 없이 옮긴다.
    /// 반환값은 압축을 푼 바이트(ScriptVersion.sha256의 대상).
    private func writeRevision(_ script: LibraryScript, bytes: Data) throws -> Data {
        let url = try revisionURL(scriptID: script.id, revisionID: script.revisionID)
        let legacy = try legacyRevisionURL(script.revisionID)
        // 같은 revisionID가 새·구 배치 어디에 있든(둘 다 있으면 둘 다) 같은 내용이어야 한다.
        var previous: Data?
        for existing in [url, legacy] where FileManager.default.fileExists(atPath: existing.path) {
            let stored = try Data(contentsOf: existing)
            let plain = existing == url ? try RevisionCodec.inflate(stored) : stored
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            guard try encoder.encode(JSONDecoder().decode(LibraryScript.self, from: plain)) == bytes else {
                throw LibraryFailure.changedFile
            }
            previous = previous ?? plain
        }
        if let previous { return previous }
        try writeNewRevision(try RevisionCodec.deflate(bytes), to: url)
        return bytes
    }
    /// Merge only changes committed by this actor (or the exact caller bytes). Unknown external edits fail closed.
    private func latestForMerge(_ source: LibraryScriptFile) throws -> LibraryScriptFile {
        try safe(source.url)
        guard source.script.snapshotTitle == nil, !source.url.path.hasPrefix(revisionFolder.path + "/") else { throw LibraryFailure.unsafePath }
        let bytes = try Data(contentsOf: source.url), hash = Self.hash(bytes)
        guard hash == source.hash || committedScriptHashes[source.url.standardizedFileURL.path] == hash else { throw LibraryFailure.changedFile }
        let scan = try scanScriptSummaries(in: source.url.deletingLastPathComponent())
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
        let (url, fileBytes, bytes) = try readRevision(scriptID: current.id, revisionID: version.revisionID)
        // sha256 = 압축을 푼 바이트(usage-bundle2). 구 배치는 파일 바이트와 같다.
        guard Self.hash(bytes) == version.sha256 else { throw LibraryFailure.changedFile }
        let script = try JSONDecoder().decode(LibraryScript.self, from: bytes)
        try script.validate()
        guard script.id == current.id, script.revisionID == version.revisionID, script.snapshotTitle == version.title,
              try script.sourceFingerprint() == current.script.sourceFingerprint() else { throw LibraryFailure.invalidScript }
        // LibraryScriptFile.hash = 그 파일 바이트의 해시(내보내기 전 변경 검사용).
        return LibraryScriptFile(url: url, hash: Self.hash(fileBytes), script: script)
    }
    /// `title` = 해석한 표시 제목(usage-bundle1). nil이면 파일 제목.
    public func exportMarkdown(_ file: LibraryScriptFile, title: String? = nil, to destination: URL) throws {
        try safe(destination)
        guard destination.pathExtension.lowercased() == "md",
              !destination.path.hasPrefix(root.path + "/"),
              try AudioFiles.hash(file.url) == file.hash else { throw LibraryFailure.changedFile }
        try TranscriptExporter().write(file.script.markdown(title: title), to: destination)
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
        try trashScript(url: file.url, hash: file.hash, in: folder)
    }
    public func trashScript(_ summary: LibraryScriptSummary, in folder: URL) throws {
        try trashScript(url: summary.url, hash: summary.hash, in: folder)
    }
    private func trashScript(url: URL, hash: String, in folder: URL) throws {
        try validateDeletion(url, in: folder)
        guard url.lastPathComponent.hasSuffix(".dama.json"),
              try AudioFiles.hash(url) == hash else { throw LibraryFailure.changedFile }
        try trash(url)
        scriptCache.removeValue(forKey: url.standardizedFileURL.path)
    }
    /// usage-bundle2: 그 스크립트의 내부 수정 이력 폴더와 교정 시도 기록을 지운다. 구 배치 파일은 저장 공간 정리에서 지운다.
    public func removeScriptHistory(scriptID: String) throws {
        guard InternalStoragePaths.isSafeScriptID(scriptID) else { throw LibraryFailure.unsafePath }
        let history = revisionFolder.appendingPathComponent(scriptID, isDirectory: true)
        try safe(history)
        if FileManager.default.fileExists(atPath: history.path) { try FileManager.default.removeItem(at: history) }
        let attempt = try InternalStoragePaths.correctionAttemptURL(root: root, scriptID: scriptID)
        try safe(attempt)
        if FileManager.default.fileExists(atPath: attempt.path) { try FileManager.default.removeItem(at: attempt) }
    }

    public enum ScriptRemoval: Sendable, Equatable { case trashFailed, removed, historyNotRemoved }
    /// usage-bundle2 결과 하나를 지우는 순서: 휴지통 이동(실패하면 멈춤) → 자식 결과면 `registerSavedSource`
    /// (`library.savedSourceRuns`) → 내부 수정 이력 폴더 → 교정 시도 기록. «Script 삭제…»와 결과 보관 정리가 함께 쓴다.
    public func removeScript(_ summary: LibraryScriptSummary, in folder: URL, isChildResult: Bool,
                             registerSavedSource: @Sendable (String) -> Void) -> ScriptRemoval {
        do { try trashScript(summary, in: folder) } catch { return .trashFailed }
        if isChildResult { registerSavedSource(summary.id) }
        do { try removeScriptHistory(scriptID: summary.id); return .removed } catch { return .historyNotRemoved }
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

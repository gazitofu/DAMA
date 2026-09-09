import Darwin
import Foundation

public enum SessionRepositoryFaultStage: String, Sendable {
    case afterPartialTemporaryRevisionWrite
    case afterFinalRevisionInstallation
}

public typealias SessionRepositoryFaultInjector = @Sendable (SessionRepositoryFaultStage) throws -> Void

public struct SessionRepositoryError: Error, Equatable, Sendable, CustomStringConvertible {
    public enum Code: String, Sendable {
        case applicationSupportUnavailable
        case invalidIdentifier
        case unsafePath
        case invalidSyntheticImport
        case identityConflict
        case immutableEvidenceChanged
        case staleBaseRevision
        case conflictingRevision
        case revisionNotFound
        case invalidRevision
        case noValidRevision
        case ioFailure
        case storedStateUncertain
    }

    public let code: Code
    public let context: String

    public init(code: Code, context: String) {
        self.code = code
        self.context = context
    }

    public var description: String {
        "Session repository error \(code.rawValue) for \(context)"
    }
}

public enum SessionRecoveryReason: String, Sendable {
    case activePointerMissing
    case activePointerCorrupt
    case activeRevisionInvalid
}

public struct SessionRecoveryNotice: Sendable {
    public let sessionId: String
    public let recoveredRunId: String
    public let recoveredRevisionId: String
    public let reason: SessionRecoveryReason

    public init(
        sessionId: String,
        recoveredRunId: String,
        recoveredRevisionId: String,
        reason: SessionRecoveryReason
    ) {
        self.sessionId = sessionId
        self.recoveredRunId = recoveredRunId
        self.recoveredRevisionId = recoveredRevisionId
        self.reason = reason
    }
}

public struct SessionLoadResult: Sendable {
    public let document: TranscriptDocument
    public let recoveryNotice: SessionRecoveryNotice?

    public init(document: TranscriptDocument, recoveryNotice: SessionRecoveryNotice?) {
        self.document = document
        self.recoveryNotice = recoveryNotice
    }
}

public struct SessionListing: Sendable {
    public let sessionId: String
    public let activeRunId: String
    public let activeRevisionId: String
    public let recoveryNotice: SessionRecoveryNotice?

    public init(
        sessionId: String,
        activeRunId: String,
        activeRevisionId: String,
        recoveryNotice: SessionRecoveryNotice?
    ) {
        self.sessionId = sessionId
        self.activeRunId = activeRunId
        self.activeRevisionId = activeRevisionId
        self.recoveryNotice = recoveryNotice
    }
}

public struct SyntheticTranscriptImportResult: Sendable {
    public let sessionId: String
    public let runId: String
    public let modelRevisionId: String
    public let activeRevisionId: String
    public let installedNewData: Bool

    public init(
        sessionId: String,
        runId: String,
        modelRevisionId: String,
        activeRevisionId: String,
        installedNewData: Bool
    ) {
        self.sessionId = sessionId
        self.runId = runId
        self.modelRevisionId = modelRevisionId
        self.activeRevisionId = activeRevisionId
        self.installedNewData = installedNewData
    }
}

/// File-backed, immutable transcript storage.
///
/// The actor serializes operations performed through one repository instance. Immutable files are
/// installed with an exclusive hard link and the active pointer is renamed atomically last. This
/// does not fsync directory metadata and does not claim power-loss durability. Independent processes
/// may also race between path validation and access; exclusive installation prevents replacement of
/// immutable evidence, while cross-process writer coordination remains a later production concern.
public actor FileSessionRepository: TranscriptRepository {
    private struct SessionPointer: Codable {
        let sessionId: String
        let activeRunId: String
        let activeRevisionId: String
    }

    private enum PointerState {
        case valid(SessionPointer)
        case missing
        case corrupt
        case activeRevisionInvalid
    }

    private struct RevisionCandidate {
        let document: TranscriptDocument
        let savedAt: Date
    }

    private let rootURL: URL
    private let faultInjector: SessionRepositoryFaultInjector?
    private var notices: [SessionRecoveryNotice] = []

    public init(rootURL: URL, faultInjector: SessionRepositoryFaultInjector? = nil) {
        self.rootURL = rootURL.standardizedFileURL
        self.faultInjector = faultInjector
    }

    public static func applicationSupport(
        faultInjector: SessionRepositoryFaultInjector? = nil
    ) throws -> FileSessionRepository {
        guard let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw SessionRepositoryError(
                code: .applicationSupportUnavailable,
                context: "application-support"
            )
        }
        return FileSessionRepository(
            rootURL: base.appendingPathComponent("com.gazitofu.Dama", isDirectory: true),
            faultInjector: faultInjector
        )
    }

    public func importSyntheticTranscript(_ sourceData: Data) async throws
        -> SyntheticTranscriptImportResult
    {
        let document: TranscriptDocument
        do {
            document = try SyntheticTranscriptFixtureLoader.load(data: sourceData)
        } catch let error as TranscriptContractError where error.code == .notSynthetic {
            throw SessionRepositoryError(code: .invalidSyntheticImport, context: "synthetic-input")
        }
        try validateIdentifiers(in: document)
        guard document.revision.baseRevisionId == nil, !document.revision.humanEdited else {
            throw SessionRepositoryError(code: .invalidSyntheticImport, context: "model-revision")
        }

        let session = try sessionURL(document.sessionId)
        let run = try runURL(sessionId: document.sessionId, runId: document.runId)
        let raw = run
            .appendingPathComponent("raw", isDirectory: true)
            .appendingPathComponent("synthetic-normalized-input.json")
        let model = run
            .appendingPathComponent("normalized", isDirectory: true)
            .appendingPathComponent("model.json")
        let revisions = session.appendingPathComponent("revisions", isDirectory: true)
        let revision = revisions.appendingPathComponent("\(document.revision.id).json")
        let isFirstInitialization = try !itemExists(session)

        try ensureDirectory(raw.deletingLastPathComponent(), context: "synthetic-input-directory")
        try ensureDirectory(model.deletingLastPathComponent(), context: "model-directory")
        try ensureDirectory(revisions, context: "revisions-directory")

        let modelData = try NormalizedTranscriptCodec.encode(document)
        try preflightImmutable(sourceData, at: raw, context: "synthetic-input")
        try preflightImmutable(modelData, at: model, context: "model")
        try preflightImmutable(modelData, at: revision, context: "revision", revisionId: document.revision.id)
        var installed = false
        installed = try installImmutable(sourceData, at: raw, context: "synthetic-input") || installed
        installed = try installImmutable(modelData, at: model, context: "model") || installed

        if try itemExists(revision) {
            let existing = try readData(revision, context: "revision")
            guard existing == modelData else {
                throw SessionRepositoryError(
                    code: .conflictingRevision,
                    context: document.revision.id
                )
            }
        } else {
            try installRevision(
                data: modelData,
                document: document,
                model: document,
                revisionsDirectory: revisions
            )
            installed = true
            try faultInjector?(.afterFinalRevisionInstallation)
        }

        let active: SessionLoadResult
        switch try pointerState(sessionId: document.sessionId) {
        case let .valid(pointer):
            active = SessionLoadResult(
                document: try explicitRevision(
                    sessionId: document.sessionId,
                    revisionId: pointer.activeRevisionId
                ),
                recoveryNotice: nil
            )
        case .missing where isFirstInitialization:
            let pointer = SessionPointer(
                sessionId: document.sessionId,
                activeRunId: document.runId,
                activeRevisionId: document.revision.id
            )
            try writePointer(pointer)
            active = SessionLoadResult(document: document, recoveryNotice: nil)
        case .missing, .corrupt, .activeRevisionInvalid:
            active = try recoverActive(sessionId: document.sessionId)
        }

        return SyntheticTranscriptImportResult(
            sessionId: document.sessionId,
            runId: document.runId,
            modelRevisionId: document.revision.id,
            activeRevisionId: active.document.revision.id,
            installedNewData: installed
        )
    }

    public func load(sessionId: String, revisionId: String?) async throws -> TranscriptDocument {
        try await loadWithRecovery(sessionId: sessionId, revisionId: revisionId).document
    }

    public func loadWithRecovery(
        sessionId: String,
        revisionId: String? = nil
    ) async throws -> SessionLoadResult {
        try validateIdentifier(sessionId, context: "session-id")
        if let revisionId {
            try validateIdentifier(revisionId, context: "revision-id")
            return SessionLoadResult(
                document: try explicitRevision(sessionId: sessionId, revisionId: revisionId),
                recoveryNotice: nil
            )
        }

        switch try pointerState(sessionId: sessionId) {
        case let .valid(pointer):
            return SessionLoadResult(
                document: try explicitRevision(
                    sessionId: sessionId,
                    revisionId: pointer.activeRevisionId
                ),
                recoveryNotice: nil
            )
        case .missing, .corrupt, .activeRevisionInvalid:
            return try recoverActive(sessionId: sessionId)
        }
    }

    public func loadModel(sessionId: String, runId: String) async throws -> TranscriptDocument {
        try validateIdentifier(sessionId, context: "session-id")
        try validateIdentifier(runId, context: "run-id")
        return try modelDocument(sessionId: sessionId, runId: runId)
    }

    public func commitRevision(_ document: TranscriptDocument) async throws {
        try TranscriptValidator().validate(document)
        try validateIdentifiers(in: document)
        guard let baseRevisionId = document.revision.baseRevisionId,
              baseRevisionId != document.revision.id else {
            throw SessionRepositoryError(code: .staleBaseRevision, context: "base-revision")
        }

        let active = try await loadWithRecovery(sessionId: document.sessionId).document
        guard active.revision.id == baseRevisionId, active.runId == document.runId else {
            throw SessionRepositoryError(code: .staleBaseRevision, context: baseRevisionId)
        }
        let model = try modelDocument(sessionId: document.sessionId, runId: document.runId)
        try validateImmutableEvidence(document, against: model)

        let data = try NormalizedTranscriptCodec.encode(document)
        let revisions = try sessionURL(document.sessionId)
            .appendingPathComponent("revisions", isDirectory: true)
        try ensureDirectory(revisions, context: "revisions-directory")
        try installRevision(
            data: data,
            document: document,
            model: model,
            revisionsDirectory: revisions
        )
        try faultInjector?(.afterFinalRevisionInstallation)

        let pointer = SessionPointer(
            sessionId: document.sessionId,
            activeRunId: document.runId,
            activeRevisionId: document.revision.id
        )
        do {
            try writePointer(pointer)
            let confirmed = try pointerState(sessionId: document.sessionId)
            guard case let .valid(stored) = confirmed,
                  stored.activeRevisionId == document.revision.id,
                  stored.activeRunId == document.runId else {
                throw SessionRepositoryError(
                    code: .storedStateUncertain,
                    context: "active-pointer"
                )
            }
        } catch {
            throw SessionRepositoryError(code: .storedStateUncertain, context: "active-pointer")
        }
    }

    public func listSessions() async throws -> [SessionListing] {
        let sessions = rootURL.appendingPathComponent("Sessions", isDirectory: true)
        try ensureContained(sessions, context: "sessions-directory")
        guard try itemExists(sessions) else { return [] }

        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(
                at: sessions,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw SessionRepositoryError(code: .ioFailure, context: "sessions-directory")
        }

        var result: [SessionListing] = []
        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let sessionId = url.lastPathComponent
            guard isValidIdentifier(sessionId) else { continue }
            do {
                try ensureContained(url, context: "session-directory")
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values.isDirectory == true, values.isSymbolicLink != true else { continue }
                let loaded = try await loadWithRecovery(sessionId: sessionId)
                result.append(SessionListing(
                    sessionId: sessionId,
                    activeRunId: loaded.document.runId,
                    activeRevisionId: loaded.document.revision.id,
                    recoveryNotice: loaded.recoveryNotice
                ))
            } catch let error as SessionRepositoryError
                where error.code == .noValidRevision || error.code == .unsafePath
            {
                continue
            } catch {
                throw error
            }
        }
        return result
    }

    /// Install a managed model into a recording's existing session, preserving any edited active run.
    public func importManagedTranscript(_ document: TranscriptDocument, rawData: Data) async throws {
        try TranscriptValidator().validate(document)
        try validateIdentifiers(in: document)
        guard document.provenance.engine == .managedPyannoteWhisper,
              !document.revision.humanEdited, document.revision.baseRevisionId == nil else {
            throw SessionRepositoryError(code: .identityConflict, context: "managed-model")
        }
        let run = try runURL(sessionId: document.sessionId, runId: document.runId)
        let raw = run.appendingPathComponent("raw/pyannote-response.json")
        let model = run.appendingPathComponent("normalized/model.json")
        let revisions = try sessionURL(document.sessionId).appendingPathComponent("revisions")
        try ensureDirectory(raw.deletingLastPathComponent(), context: "raw-directory")
        try ensureDirectory(model.deletingLastPathComponent(), context: "model-directory")
        try ensureDirectory(revisions, context: "revisions-directory")
        let bytes = try NormalizedTranscriptCodec.encode(document)
        _ = try installImmutable(rawData, at: raw, context: "managed-raw")
        _ = try installImmutable(bytes, at: model, context: "managed-model")
        try installRevision(data: bytes, document: document, model: document, revisionsDirectory: revisions)
        if case .missing = try pointerState(sessionId: document.sessionId) {
            try writePointer(SessionPointer(sessionId: document.sessionId, activeRunId: document.runId,
                                            activeRevisionId: document.revision.id))
        }
    }

    public func recoveryNotices() -> [SessionRecoveryNotice] {
        notices
    }

    /// Rejects export destinations that could replace repository-owned state, including symlink
    /// aliases into the injected/Application Support root. The caller still chooses the destination.
    public func validateExportDestination(_ destinationURL: URL) throws {
        guard destinationURL.isFileURL, destinationURL.path.hasPrefix("/") else {
            throw SessionRepositoryError(code: .unsafePath, context: "export-destination")
        }
        let lexicalRoot = rootURL.standardizedFileURL.path
        let lexicalDestination = destinationURL.standardizedFileURL.path
        let resolvedRoot = try resolvedPathFollowingExistingAncestors(rootURL)
        let resolvedDestination = try resolvedPathFollowingExistingAncestors(destinationURL)
        guard !isContained(lexicalDestination, by: lexicalRoot),
              !isContained(resolvedDestination, by: resolvedRoot) else {
            throw SessionRepositoryError(code: .unsafePath, context: "export-destination")
        }
    }

    private func validateIdentifiers(in document: TranscriptDocument) throws {
        try validateIdentifier(document.sessionId, context: "session-id")
        try validateIdentifier(document.runId, context: "run-id")
        try validateIdentifier(document.revision.id, context: "revision-id")
        if let base = document.revision.baseRevisionId {
            try validateIdentifier(base, context: "base-revision-id")
        }
        try validateIdentifier(document.revision.sourceRunId, context: "source-run-id")
        guard document.revision.sourceRunId == document.runId else {
            throw SessionRepositoryError(code: .identityConflict, context: "source-run")
        }
    }

    private func isValidIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 128, value.utf8.first != 46,
              value != ".", value != ".." else {
            return false
        }
        return value.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte) ||
                byte == 45 || byte == 46 || byte == 95
        }
    }

    private func validateIdentifier(_ value: String, context: String) throws {
        guard isValidIdentifier(value) else {
            throw SessionRepositoryError(code: .invalidIdentifier, context: context)
        }
    }

    private func sessionURL(_ sessionId: String) throws -> URL {
        try validateIdentifier(sessionId, context: "session-id")
        let url = rootURL
            .appendingPathComponent("Sessions", isDirectory: true)
            .appendingPathComponent(sessionId, isDirectory: true)
        try ensureContained(url, context: "session-directory")
        return url
    }

    private func runURL(sessionId: String, runId: String) throws -> URL {
        try validateIdentifier(runId, context: "run-id")
        let url = try sessionURL(sessionId)
            .appendingPathComponent("runs", isDirectory: true)
            .appendingPathComponent(runId, isDirectory: true)
        try ensureContained(url, context: "run-directory")
        return url
    }

    private func ensureContained(_ url: URL, context: String) throws {
        guard rootURL.isFileURL, rootURL.path.hasPrefix("/") else {
            throw SessionRepositoryError(code: .unsafePath, context: "storage-root")
        }
        let resolvedRoot = try resolvedPathFollowingExistingAncestors(rootURL)
        let resolved = try resolvedPathFollowingExistingAncestors(url)
        guard resolved == resolvedRoot || resolved.hasPrefix(resolvedRoot + "/") else {
            throw SessionRepositoryError(code: .unsafePath, context: context)
        }
    }

    private func isContained(_ candidate: String, by root: String) -> Bool {
        candidate == root || candidate.hasPrefix(root + "/")
    }

    private func resolvedPathFollowingExistingAncestors(_ input: URL) throws -> String {
        var ancestor = input.standardizedFileURL
        var missingComponents: [String] = []
        while true {
            var information = stat()
            if lstat(ancestor.path, &information) == 0 { break }
            let statError = errno
            guard statError == ENOENT || statError == ENOTDIR,
                  ancestor.path != "/" else {
                throw SessionRepositoryError(code: .ioFailure, context: "stored-path")
            }
            missingComponents.append(ancestor.lastPathComponent)
            ancestor.deleteLastPathComponent()
        }
        var resolved = ancestor.resolvingSymlinksInPath().standardizedFileURL
        for component in missingComponents.reversed() {
            resolved.appendPathComponent(component)
        }
        return resolved.standardizedFileURL.path
    }

    private func ensureDirectory(_ url: URL, context: String) throws {
        try ensureContained(url, context: context)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw SessionRepositoryError(code: .ioFailure, context: context)
        }
        try ensureContained(url, context: context)
    }

    private func itemExists(_ url: URL) throws -> Bool {
        try ensureContained(url, context: "stored-item")
        do {
            _ = try FileManager.default.attributesOfItem(atPath: url.path)
            return true
        } catch {
            let cocoa = error as NSError
            if cocoa.domain == NSCocoaErrorDomain,
               cocoa.code == NSFileNoSuchFileError || cocoa.code == NSFileReadNoSuchFileError {
                return false
            }
            throw SessionRepositoryError(code: .ioFailure, context: "stored-item")
        }
    }

    private func readData(_ url: URL, context: String) throws -> Data {
        try ensureContained(url, context: context)
        do {
            return try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw SessionRepositoryError(code: .ioFailure, context: context)
        }
    }

    @discardableResult
    private func installImmutable(_ data: Data, at destination: URL, context: String) throws -> Bool {
        try ensureContained(destination, context: context)
        if try itemExists(destination) {
            guard try readData(destination, context: context) == data else {
                throw SessionRepositoryError(code: .identityConflict, context: context)
            }
            return false
        }

        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).tmp-\(UUID().uuidString)")
        try ensureContained(temporary, context: context)
        do {
            try data.write(to: temporary)
            let result = exclusiveLink(from: temporary, to: destination)
            let linkError = errno
            try? FileManager.default.removeItem(at: temporary)
            if result == 0 { return true }
            if linkError == EEXIST {
                guard try readData(destination, context: context) == data else {
                    throw SessionRepositoryError(code: .identityConflict, context: context)
                }
                return false
            }
            throw SessionRepositoryError(code: .ioFailure, context: context)
        } catch let error as SessionRepositoryError {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw SessionRepositoryError(code: .ioFailure, context: context)
        }
    }

    private func preflightImmutable(
        _ data: Data,
        at destination: URL,
        context: String,
        revisionId: String? = nil
    ) throws {
        guard try itemExists(destination) else { return }
        guard try readData(destination, context: context) == data else {
            if let revisionId {
                throw SessionRepositoryError(code: .conflictingRevision, context: revisionId)
            }
            throw SessionRepositoryError(code: .identityConflict, context: context)
        }
    }

    private func installRevision(
        data: Data,
        document: TranscriptDocument,
        model: TranscriptDocument,
        revisionsDirectory: URL
    ) throws {
        let destination = revisionsDirectory.appendingPathComponent("\(document.revision.id).json")
        let temporary = revisionsDirectory
            .appendingPathComponent(".\(document.revision.id).tmp-\(UUID().uuidString)")
        try ensureContained(destination, context: "revision")
        try ensureContained(temporary, context: "temporary-revision")

        let split = max(1, data.count / 2)
        do {
            try Data(data.prefix(split)).write(to: temporary)
            try faultInjector?(.afterPartialTemporaryRevisionWrite)
            let handle = try FileHandle(forWritingTo: temporary)
            try handle.seekToEnd()
            try handle.write(contentsOf: data.dropFirst(split))
            try handle.close()

            let verifiedBytes = try readData(temporary, context: "temporary-revision")
            guard verifiedBytes == data else {
                throw SessionRepositoryError(code: .ioFailure, context: "temporary-revision")
            }
            let verified = try NormalizedTranscriptCodec.decode(verifiedBytes)
            try validateIdentifiers(in: verified)
            try validateImmutableEvidence(verified, against: model)
            guard verified.sessionId == document.sessionId,
                  verified.runId == document.runId,
                  verified.revision.id == document.revision.id,
                  verified.revision.baseRevisionId == document.revision.baseRevisionId else {
                throw SessionRepositoryError(code: .identityConflict, context: "revision")
            }

            let result = exclusiveLink(from: temporary, to: destination)
            if result == 0 {
                try? FileManager.default.removeItem(at: temporary)
                return
            }
            if errno == EEXIST {
                let existing = try readData(destination, context: "revision")
                guard existing == data else {
                    throw SessionRepositoryError(
                        code: .conflictingRevision,
                        context: document.revision.id
                    )
                }
                try? FileManager.default.removeItem(at: temporary)
                return
            }
            throw SessionRepositoryError(code: .ioFailure, context: "revision")
        } catch {
            // A partial temp file is intentionally left for crash/fault recovery tests. It cannot
            // be selected because only <safe-id>.json final names are scanned.
            throw error
        }
    }

    private func exclusiveLink(from source: URL, to destination: URL) -> Int32 {
        source.withUnsafeFileSystemRepresentation { sourcePath in
            destination.withUnsafeFileSystemRepresentation { destinationPath in
                guard let sourcePath, let destinationPath else { return -1 }
                return Darwin.link(sourcePath, destinationPath)
            }
        }
    }

    private func modelDocument(sessionId: String, runId: String) throws -> TranscriptDocument {
        let url = try runURL(sessionId: sessionId, runId: runId)
            .appendingPathComponent("normalized", isDirectory: true)
            .appendingPathComponent("model.json")
        guard try itemExists(url) else {
            throw SessionRepositoryError(code: .identityConflict, context: "model")
        }
        do {
            let document = try NormalizedTranscriptCodec.decode(readData(url, context: "model"))
            guard document.sessionId == sessionId, document.runId == runId else {
                throw SessionRepositoryError(code: .identityConflict, context: "model")
            }
            try validateIdentifiers(in: document)
            guard document.revision.baseRevisionId == nil, !document.revision.humanEdited else {
                throw SessionRepositoryError(code: .invalidRevision, context: "model")
            }
            return document
        } catch let error as SessionRepositoryError {
            throw error
        } catch {
            throw SessionRepositoryError(code: .invalidRevision, context: "model")
        }
    }

    private func explicitRevision(sessionId: String, revisionId: String) throws -> TranscriptDocument {
        let candidates = try validRevisionCandidates(sessionId: sessionId)
        guard let candidate = candidates[revisionId] else {
            let url = try sessionURL(sessionId)
                .appendingPathComponent("revisions", isDirectory: true)
                .appendingPathComponent("\(revisionId).json")
            if try itemExists(url) {
                throw SessionRepositoryError(code: .invalidRevision, context: revisionId)
            }
            throw SessionRepositoryError(code: .revisionNotFound, context: revisionId)
        }
        return candidate.document
    }

    private func validRevisionCandidates(sessionId: String) throws -> [String: RevisionCandidate] {
        let revisions = try sessionURL(sessionId)
            .appendingPathComponent("revisions", isDirectory: true)
        guard try itemExists(revisions) else { return [:] }
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(
                at: revisions,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw SessionRepositoryError(code: .ioFailure, context: "revisions-directory")
        }

        var decoded: [String: RevisionCandidate] = [:]
        for url in urls where url.pathExtension == "json" {
            let revisionId = url.deletingPathExtension().lastPathComponent
            guard isValidIdentifier(revisionId) else { continue }
            do {
                try ensureContained(url, context: "revision")
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
                let document = try NormalizedTranscriptCodec.decode(readData(url, context: "revision"))
                try validateIdentifiers(in: document)
                guard document.sessionId == sessionId, document.revision.id == revisionId else {
                    continue
                }
                let model = try modelDocument(sessionId: sessionId, runId: document.runId)
                try validateImmutableEvidence(document, against: model)
                guard let date = Self.iso8601Date(document.revision.savedAt) else { continue }
                decoded[revisionId] = RevisionCandidate(document: document, savedAt: date)
            } catch is TranscriptContractError {
                continue
            } catch let error as SessionRepositoryError where
                error.code == .invalidIdentifier ||
                error.code == .identityConflict ||
                error.code == .immutableEvidenceChanged ||
                error.code == .unsafePath ||
                error.code == .invalidRevision
            {
                continue
            } catch {
                throw error
            }
        }

        var validity: [String: Bool] = [:]
        var visiting = Set<String>()
        func isChainValid(_ id: String) -> Bool {
            if let cached = validity[id] { return cached }
            guard let candidate = decoded[id], visiting.insert(id).inserted else {
                validity[id] = false
                return false
            }
            defer { visiting.remove(id) }
            let document = candidate.document
            let valid: Bool
            if let base = document.revision.baseRevisionId {
                valid = decoded[base]?.document.runId == document.runId && isChainValid(base)
            } else {
                valid = (try? modelDocument(
                    sessionId: sessionId,
                    runId: document.runId
                ).revision.id) == document.revision.id
            }
            validity[id] = valid
            return valid
        }
        return decoded.filter { isChainValid($0.key) }
    }

    private func pointerState(sessionId: String) throws -> PointerState {
        let pointerURL = try sessionURL(sessionId).appendingPathComponent("session.json")
        guard try itemExists(pointerURL) else { return .missing }
        let data = try readData(pointerURL, context: "active-pointer")
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(raw.keys) == Set(["sessionId", "activeRunId", "activeRevisionId"]),
              let pointer = try? JSONDecoder().decode(SessionPointer.self, from: data),
              isValidIdentifier(pointer.sessionId),
              isValidIdentifier(pointer.activeRunId),
              isValidIdentifier(pointer.activeRevisionId),
              pointer.sessionId == sessionId else {
            return .corrupt
        }
        guard let candidate = try validRevisionCandidates(sessionId: sessionId)[pointer.activeRevisionId],
              candidate.document.runId == pointer.activeRunId else {
            return .activeRevisionInvalid
        }
        return .valid(pointer)
    }

    private func recoverActive(sessionId: String) throws -> SessionLoadResult {
        let initialState = try pointerStateForRecoveryReason(sessionId: sessionId)
        let candidates = try validRevisionCandidates(sessionId: sessionId)
        guard let selected = candidates.values.max(by: { left, right in
            if left.savedAt != right.savedAt { return left.savedAt < right.savedAt }
            return left.document.revision.id < right.document.revision.id
        }) else {
            throw SessionRepositoryError(code: .noValidRevision, context: sessionId)
        }
        let pointer = SessionPointer(
            sessionId: sessionId,
            activeRunId: selected.document.runId,
            activeRevisionId: selected.document.revision.id
        )
        try writePointer(pointer)
        let notice = SessionRecoveryNotice(
            sessionId: sessionId,
            recoveredRunId: selected.document.runId,
            recoveredRevisionId: selected.document.revision.id,
            reason: initialState
        )
        notices.append(notice)
        return SessionLoadResult(document: selected.document, recoveryNotice: notice)
    }

    private func pointerStateForRecoveryReason(sessionId: String) throws -> SessionRecoveryReason {
        switch try pointerState(sessionId: sessionId) {
        case .missing: return .activePointerMissing
        case .corrupt: return .activePointerCorrupt
        case .activeRevisionInvalid: return .activeRevisionInvalid
        case .valid:
            return .activeRevisionInvalid
        }
    }

    private func writePointer(_ pointer: SessionPointer) throws {
        let session = try sessionURL(pointer.sessionId)
        try ensureDirectory(session, context: "session-directory")
        let destination = session.appendingPathComponent("session.json")
        let temporary = session.appendingPathComponent(".session.tmp-\(UUID().uuidString)")
        try ensureContained(destination, context: "active-pointer")
        try ensureContained(temporary, context: "active-pointer")
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(pointer)
            try data.write(to: temporary)
            let check = try JSONDecoder().decode(
                SessionPointer.self,
                from: readData(temporary, context: "active-pointer")
            )
            guard check.sessionId == pointer.sessionId,
                  check.activeRunId == pointer.activeRunId,
                  check.activeRevisionId == pointer.activeRevisionId else {
                throw SessionRepositoryError(code: .ioFailure, context: "active-pointer")
            }
            let result: Int32 = temporary.withUnsafeFileSystemRepresentation { sourcePath in
                destination.withUnsafeFileSystemRepresentation { destinationPath -> Int32 in
                    guard let sourcePath, let destinationPath else { return -1 }
                    return Darwin.rename(sourcePath, destinationPath)
                }
            }
            guard result == 0 else {
                throw SessionRepositoryError(code: .storedStateUncertain, context: "active-pointer")
            }
        } catch let error as SessionRepositoryError {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw SessionRepositoryError(code: .ioFailure, context: "active-pointer")
        }
    }

    private func validateImmutableEvidence(
        _ document: TranscriptDocument,
        against model: TranscriptDocument
    ) throws {
        guard document.schemaVersion == model.schemaVersion,
              document.sessionId == model.sessionId,
              document.runId == model.runId,
              document.durationUs == model.durationUs,
              document.language == model.language,
              sameProvenance(document.provenance, model.provenance),
              sameSpeakers(document.speakers, model.speakers),
              sameIntervals(document.diarization, model.diarization),
              sameIntervals(document.exclusiveDiarization, model.exclusiveDiarization),
              sameWords(document.words, model.words),
              sameIssues(document.reviewIssues, model.reviewIssues),
              sameTurnEvidence(document.turns, model.turns) else {
            throw SessionRepositoryError(
                code: .immutableEvidenceChanged,
                context: "normalized-evidence"
            )
        }
    }

    private func sameProvenance(_ left: TranscriptProvenance, _ right: TranscriptProvenance) -> Bool {
        left.engine == right.engine &&
            left.diarizationModel == right.diarizationModel &&
            left.asrModel == right.asrModel &&
            left.createdAt == right.createdAt &&
            left.algorithmVersion == right.algorithmVersion &&
            left.sourceAudioSHA256 == right.sourceAudioSHA256 &&
            left.sampleRateHz == right.sampleRateHz &&
            left.isSynthetic == right.isSynthetic
    }

    private func sameSpeakers(_ left: [Speaker], _ right: [Speaker]) -> Bool {
        guard left.count == right.count else { return false }
        return zip(left, right).allSatisfy {
            $0.id == $1.id && $0.providerId == $1.providerId
        }
    }

    private func sameIntervals(
        _ left: [DiarizationInterval],
        _ right: [DiarizationInterval]
    ) -> Bool {
        guard left.count == right.count else { return false }
        return zip(left, right).allSatisfy {
            $0.id == $1.id && $0.startUs == $1.startUs && $0.endUs == $1.endUs &&
                $0.speakerId == $1.speakerId && $0.confidence == $1.confidence
        }
    }

    private func sameWords(_ left: [TranscriptWord], _ right: [TranscriptWord]) -> Bool {
        guard left.count == right.count else { return false }
        return zip(left, right).allSatisfy {
            $0.id == $1.id && $0.ordinal == $1.ordinal && $0.text == $1.text &&
                $0.prefix == $1.prefix && $0.startUs == $1.startUs && $0.endUs == $1.endUs &&
                $0.modelSpeakerId == $1.modelSpeakerId && $0.alignmentScore == $1.alignmentScore &&
                $0.overlap == $1.overlap && $0.reviewIssueIds == $1.reviewIssueIds &&
                $0.sourceIntervalIds == $1.sourceIntervalIds && $0.tokenKind == $1.tokenKind
        }
    }

    private func sameIssues(_ left: [ReviewIssue], _ right: [ReviewIssue]) -> Bool {
        guard left.count == right.count else { return false }
        return zip(left, right).allSatisfy {
            $0.id == $1.id && $0.kind == $1.kind && $0.startUs == $1.startUs &&
                $0.endUs == $1.endUs && $0.severity == $1.severity &&
                $0.wordIds == $1.wordIds && $0.sourceIntervalIds == $1.sourceIntervalIds
        }
    }

    private func sameTurnEvidence(
        _ current: [TranscriptTurn],
        _ model: [TranscriptTurn]
    ) -> Bool {
        let currentMarkers = current.filter { $0.kind == .missingSpeech }
        let modelMarkers = model.filter { $0.kind == .missingSpeech }
        guard currentMarkers.count == modelMarkers.count,
              zip(currentMarkers, modelMarkers).allSatisfy({ left, right in
                  left.id == right.id && left.kind == right.kind &&
                      left.startUs == right.startUs && left.endUs == right.endUs &&
                      left.speakerId == right.speakerId && left.wordIds == right.wordIds &&
                      left.markerText == right.markerText && left.reviewed == right.reviewed &&
                      left.reviewIssueIds == right.reviewIssueIds
              }) else {
            return false
        }

        var modelTurnByWord: [String: String] = [:]
        var modelPositionByTurn: [String: Int] = [:]
        for (position, turn) in model.enumerated() {
            modelPositionByTurn[turn.id] = position
            guard turn.kind == .speech else { continue }
            for wordId in turn.wordIds {
                modelTurnByWord[wordId] = turn.id
            }
        }

        let modelWordOrder = model
            .filter { $0.kind == .speech }
            .flatMap(\.wordIds)
        let currentWordOrder = current
            .filter { $0.kind == .speech }
            .flatMap(\.wordIds)
        guard currentWordOrder == modelWordOrder else { return false }

        var previousPosition: Int?
        for turn in current {
            let position: Int?
            if turn.kind == .missingSpeech {
                position = modelPositionByTurn[turn.id]
            } else {
                let sourceTurns = Set(turn.wordIds.compactMap { modelTurnByWord[$0] })
                guard sourceTurns.count == 1, let sourceTurn = sourceTurns.first else {
                    return false
                }
                position = modelPositionByTurn[sourceTurn]
            }
            guard let position else { return false }
            if let previousPosition, position < previousPosition { return false }
            previousPosition = position
        }
        return true
    }

    private static func iso8601Date(_ value: String) -> Date? {
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        if let date = basic.date(from: value) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value)
    }
}

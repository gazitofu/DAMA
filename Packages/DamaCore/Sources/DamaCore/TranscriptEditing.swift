import Foundation

public enum TranscriptEditOperation: Sendable {
    case assignWords(wordIds: [String], speakerId: String?)
    case renameSpeaker(speakerId: String, displayName: String)
    case replaceWordText(wordId: String, editedText: String)
    case revertWordText(wordId: String)
    case splitTurn(turnId: String, beforeWordId: String)
    case acknowledgeIssue(issueId: String)
    case reopenIssue(issueId: String)
}

public struct TranscriptEditingError: Error, Equatable, Sendable, CustomStringConvertible {
    public enum Code: String, Sendable {
        case invalidSelection
        case unknownWord
        case unknownSpeaker
        case invalidDisplayName
        case unknownTurn
        case invalidSplit
        case unknownIssue
        case noChange
        case busy
        case pendingSaveFailure
        case noUndo
        case noRedo
        case noFailedSave
        case storageFailure
        case stateConflict
    }

    public let code: Code
    public let context: String

    public init(code: Code, context: String) {
        self.code = code
        self.context = context
    }

    public var description: String {
        "Transcript editing error \(code.rawValue) for \(context)"
    }
}

public struct TranscriptEditor: Sendable {
    public init() {}

    public func applying(
        _ operation: TranscriptEditOperation,
        to document: TranscriptDocument,
        model: TranscriptDocument
    ) throws -> TranscriptDocument {
        do {
            try TranscriptValidator().validate(document)
            try TranscriptValidator().validate(model)
        } catch {
            throw TranscriptEditingError(code: .stateConflict, context: "invalid-input")
        }
        guard document.sessionId == model.sessionId, document.runId == model.runId else {
            throw TranscriptEditingError(code: .stateConflict, context: "model-identity")
        }
        var edited = document
        switch operation {
        case let .assignWords(wordIds, speakerId):
            try assign(wordIds: wordIds, speakerId: speakerId, in: &edited)
        case let .renameSpeaker(speakerId, displayName):
            try rename(speakerId: speakerId, displayName: displayName, in: &edited)
        case let .replaceWordText(wordId, editedText):
            try replaceText(wordId: wordId, editedText: editedText, in: &edited)
        case let .revertWordText(wordId):
            try revertText(wordId: wordId, in: &edited, model: model)
        case let .splitTurn(turnId, beforeWordId):
            try split(turnId: turnId, beforeWordId: beforeWordId, in: &edited)
        case let .acknowledgeIssue(issueId):
            try setIssue(issueId: issueId, status: .acknowledged, in: &edited)
        case let .reopenIssue(issueId):
            try setIssue(issueId: issueId, status: .open, in: &edited)
        }
        try TranscriptValidator().validate(edited)
        return edited
    }

    private func assign(
        wordIds: [String],
        speakerId: String?,
        in document: inout TranscriptDocument
    ) throws {
        guard !wordIds.isEmpty, Set(wordIds).count == wordIds.count else {
            throw TranscriptEditingError(code: .invalidSelection, context: "word-selection")
        }
        if let speakerId, !document.speakers.contains(where: { $0.id == speakerId }) {
            throw TranscriptEditingError(code: .unknownSpeaker, context: "speaker-id")
        }
        let selected = Set(wordIds)
        guard selected.allSatisfy({ id in document.words.contains(where: { $0.id == id }) }) else {
            throw TranscriptEditingError(code: .unknownWord, context: "word-selection")
        }

        var changed = false
        for index in document.words.indices where selected.contains(document.words[index].id) {
            let source: AssignmentSource = speakerId == nil ? .unknown : .user
            if document.words[index].speakerId != speakerId ||
                document.words[index].assignmentSource != source {
                changed = true
            }
            document.words[index].speakerId = speakerId
            document.words[index].assignmentSource = source
        }
        guard changed else {
            throw TranscriptEditingError(code: .noChange, context: "word-assignment")
        }
        document.turns = subdividingTurns(document.turns, words: document.words)
    }

    private func rename(
        speakerId: String,
        displayName: String,
        in document: inout TranscriptDocument
    ) throws {
        guard !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranscriptEditingError(code: .invalidDisplayName, context: "display-name")
        }
        guard let index = document.speakers.firstIndex(where: { $0.id == speakerId }) else {
            throw TranscriptEditingError(code: .unknownSpeaker, context: "speaker-id")
        }
        guard document.speakers[index].displayName != displayName else {
            throw TranscriptEditingError(code: .noChange, context: "display-name")
        }
        document.speakers[index].displayName = displayName
    }

    private func replaceText(
        wordId: String,
        editedText: String,
        in document: inout TranscriptDocument
    ) throws {
        guard let index = document.words.firstIndex(where: { $0.id == wordId }) else {
            throw TranscriptEditingError(code: .unknownWord, context: "word-id")
        }
        guard document.words[index].editedText != editedText ||
                document.words[index].timingOrigin != .inheritedUnaligned else {
            throw TranscriptEditingError(code: .noChange, context: "edited-text")
        }
        document.words[index].editedText = editedText
        document.words[index].timingOrigin = .inheritedUnaligned
    }

    private func revertText(
        wordId: String,
        in document: inout TranscriptDocument,
        model: TranscriptDocument
    ) throws {
        guard let index = document.words.firstIndex(where: { $0.id == wordId }) else {
            throw TranscriptEditingError(code: .unknownWord, context: "word-id")
        }
        guard let modelWord = model.words.first(where: { $0.id == wordId }) else {
            throw TranscriptEditingError(code: .stateConflict, context: "model-word")
        }
        guard document.words[index].editedText != nil ||
                document.words[index].timingOrigin != modelWord.timingOrigin else {
            throw TranscriptEditingError(code: .noChange, context: "edited-text")
        }
        document.words[index].editedText = nil
        document.words[index].timingOrigin = modelWord.timingOrigin
    }

    private func split(
        turnId: String,
        beforeWordId: String,
        in document: inout TranscriptDocument
    ) throws {
        guard let turnIndex = document.turns.firstIndex(where: { $0.id == turnId }) else {
            throw TranscriptEditingError(code: .unknownTurn, context: "turn-id")
        }
        let original = document.turns[turnIndex]
        guard original.kind == .speech,
              let boundary = original.wordIds.firstIndex(of: beforeWordId),
              boundary > 0 else {
            throw TranscriptEditingError(code: .invalidSplit, context: "turn-boundary")
        }
        let leftWordIDs = Array(original.wordIds[..<boundary])
        let rightWordIDs = Array(original.wordIds[boundary...])
        guard !rightWordIDs.isEmpty else {
            throw TranscriptEditingError(code: .invalidSplit, context: "turn-boundary")
        }
        let words = Dictionary(uniqueKeysWithValues: document.words.map { ($0.id, $0) })
        var left = original
        left.wordIds = leftWordIDs
        (left.startUs, left.endUs) = segmentRange(wordIds: leftWordIDs, words: words)
        var right = original
        right.id = uniqueSplitID(base: original.id, firstWordId: beforeWordId, in: document.turns)
        right.wordIds = rightWordIDs
        (right.startUs, right.endUs) = segmentRange(wordIds: rightWordIDs, words: words)
        document.turns.replaceSubrange(turnIndex...turnIndex, with: [left, right])
    }

    private func setIssue(
        issueId: String,
        status: IssueStatus,
        in document: inout TranscriptDocument
    ) throws {
        guard let index = document.reviewIssues.firstIndex(where: { $0.id == issueId }) else {
            throw TranscriptEditingError(code: .unknownIssue, context: "issue-id")
        }
        guard document.reviewIssues[index].status != status else {
            throw TranscriptEditingError(code: .noChange, context: "issue-status")
        }
        document.reviewIssues[index].status = status
    }

    private func subdividingTurns(
        _ turns: [TranscriptTurn],
        words: [TranscriptWord]
    ) -> [TranscriptTurn] {
        let wordsByID = Dictionary(uniqueKeysWithValues: words.map { ($0.id, $0) })
        var result: [TranscriptTurn] = []
        for turn in turns {
            guard turn.kind == .speech else {
                result.append(turn)
                continue
            }
            var groups: [[String]] = []
            for wordId in turn.wordIds {
                if let lastId = groups.last?.last,
                   wordsByID[lastId]?.speakerId == wordsByID[wordId]?.speakerId {
                    groups[groups.count - 1].append(wordId)
                } else {
                    groups.append([wordId])
                }
            }
            for (index, group) in groups.enumerated() {
                var segment = turn
                if index > 0 {
                    segment.id = uniqueSplitID(
                        base: turn.id,
                        firstWordId: group[0],
                        in: turns + result
                    )
                }
                segment.wordIds = group
                segment.speakerId = wordsByID[group[0]]?.speakerId
                if groups.count > 1 {
                    (segment.startUs, segment.endUs) = segmentRange(
                        wordIds: group,
                        words: wordsByID
                    )
                }
                result.append(segment)
            }
        }
        return result
    }

    private func segmentRange(
        wordIds: [String],
        words: [String: TranscriptWord]
    ) -> (Microseconds?, Microseconds?) {
        let timed = wordIds.compactMap { id -> (Microseconds, Microseconds)? in
            guard let word = words[id], let start = word.startUs, let end = word.endUs else {
                return nil
            }
            return (start, end)
        }
        guard !timed.isEmpty else { return (nil, nil) }
        return (
            timed.map(\.0).min(),
            timed.map(\.1).max()
        )
    }

    private func uniqueSplitID(
        base: String,
        firstWordId: String,
        in turns: [TranscriptTurn]
    ) -> String {
        let existing = Set(turns.map(\.id))
        let stem = "\(base).split.\(firstWordId)"
        if !existing.contains(stem) { return stem }
        var suffix = 2
        while existing.contains("\(stem).\(suffix)") { suffix += 1 }
        return "\(stem).\(suffix)"
    }
}

public enum TranscriptIssueOrdering {
    public static func openIssues(in document: TranscriptDocument) -> [ReviewIssue] {
        document.reviewIssues
            .filter { $0.status == .open }
            .sorted(by: { (left: ReviewIssue, right: ReviewIssue) -> Bool in
                switch (left.startUs, right.startUs) {
                case let (leftTime?, rightTime?):
                    return leftTime == rightTime ? left.id < right.id : leftTime < rightTime
                case (.some, .none): return true
                case (.none, .some): return false
                case (.none, .none): return left.id < right.id
                }
            })
    }

    public static func nextOpenIssue(
        after issueId: String?,
        in document: TranscriptDocument
    ) throws -> ReviewIssue? {
        let ordered = openIssues(in: document)
        guard let issueId else { return ordered.first }
        guard let index = ordered.firstIndex(where: { $0.id == issueId }) else {
            throw TranscriptEditingError(code: .unknownIssue, context: "issue-id")
        }
        let next = ordered.index(after: index)
        return next < ordered.endIndex ? ordered[next] : nil
    }
}

public struct EditingRevisionIdentity: Sendable {
    public let id: String
    public let savedAt: String

    public init(id: String, savedAt: String) {
        self.id = id
        self.savedAt = savedAt
    }
}

public typealias EditingRevisionFactory = @Sendable () -> EditingRevisionIdentity

public struct TranscriptEditingFailure: Sendable {
    public let code: TranscriptEditingError.Code
    public let context: String

    public init(code: TranscriptEditingError.Code, context: String) {
        self.code = code
        self.context = context
    }
}

public struct TranscriptEditingState: Sendable {
    public let committed: TranscriptDocument
    public let draft: TranscriptDocument
    public let isDirty: Bool
    public let isSaving: Bool
    public let isExporting: Bool
    public let failure: TranscriptEditingFailure?
    public let canUndo: Bool
    public let canRedo: Bool
    public let canExport: Bool
}

public actor TranscriptEditingSession {
    private struct HistoryEntry: Sendable {
        let before: TranscriptDocument
        let after: TranscriptDocument
    }

    private enum PendingTransition: Sendable {
        case operation(HistoryEntry)
        case undo(HistoryEntry)
        case redo(HistoryEntry)
    }

    private let repository: any TranscriptRepository
    private let model: TranscriptDocument
    private let revisionFactory: EditingRevisionFactory
    private let beforeSave: @Sendable () async -> Void
    private let beforeExport: @Sendable () async -> Void
    private let exportDestinationValidator: @Sendable (URL) async throws -> Void
    private var committed: TranscriptDocument
    private var draft: TranscriptDocument
    private var undoStack: [HistoryEntry] = []
    private var redoStack: [HistoryEntry] = []
    private var pending: PendingTransition?
    private var pendingCancellation: TranscriptDocument?
    private var isSaving = false
    private var isExporting = false
    private var failure: TranscriptEditingFailure?

    public static func open(
        repository: FileSessionRepository,
        sessionId: String,
        revisionFactory: @escaping EditingRevisionFactory = TranscriptEditingSession.defaultRevisionFactory
    ) async throws -> TranscriptEditingSession {
        let loaded = try await repository.loadWithRecovery(sessionId: sessionId)
        let model = try await repository.loadModel(
            sessionId: loaded.document.sessionId,
            runId: loaded.document.runId
        )
        return TranscriptEditingSession(
            repository: repository,
            committed: loaded.document,
            model: model,
            revisionFactory: revisionFactory,
            exportDestinationValidator: { destinationURL in
                try await repository.validateExportDestination(destinationURL)
            }
        )
    }

    init(
        repository: any TranscriptRepository,
        committed: TranscriptDocument,
        model: TranscriptDocument,
        revisionFactory: @escaping EditingRevisionFactory = TranscriptEditingSession.defaultRevisionFactory,
        beforeSave: @escaping @Sendable () async -> Void = {},
        beforeExport: @escaping @Sendable () async -> Void = {},
        exportDestinationValidator: @escaping @Sendable (URL) async throws -> Void = { _ in }
    ) {
        self.repository = repository
        self.committed = committed
        self.draft = committed
        self.model = model
        self.revisionFactory = revisionFactory
        self.beforeSave = beforeSave
        self.beforeExport = beforeExport
        self.exportDestinationValidator = exportDestinationValidator
    }

    public func state() -> TranscriptEditingState {
        TranscriptEditingState(
            committed: committed,
            draft: draft,
            isDirty: pending != nil,
            isSaving: isSaving,
            isExporting: isExporting,
            failure: failure,
            canUndo: !isSaving && !isExporting && pending == nil && !undoStack.isEmpty,
            canRedo: !isSaving && !isExporting && pending == nil && !redoStack.isEmpty,
            canExport: !isSaving && !isExporting && pending == nil && failure == nil
        )
    }

    public func export(
        selection: TranscriptExportSelection,
        format: TranscriptExportFormat,
        to destinationURL: URL,
        exporter: TranscriptExporter = TranscriptExporter()
    ) async throws -> TranscriptExportResult {
        guard !isSaving, !isExporting else {
            throw TranscriptEditingError(code: .busy, context: "export")
        }
        guard pending == nil, failure == nil else {
            throw TranscriptEditingError(code: .pendingSaveFailure, context: "export")
        }
        let document: TranscriptDocument
        switch selection.version {
        case .automatic:
            document = model
        case .current:
            document = committed
        }
        guard selection.sessionId == document.sessionId,
              selection.runId == document.runId,
              selection.revisionId == document.revision.id else {
            throw TranscriptExportError(code: .invalidSelection, context: "displayed-version")
        }

        isExporting = true
        defer { isExporting = false }
        await beforeExport()
        do {
            try await exportDestinationValidator(destinationURL)
        } catch let error as TranscriptExportError {
            throw error
        } catch {
            throw TranscriptExportError(code: .unsafeDestination, context: "repository-storage")
        }
        let data = try exporter.data(for: document, selection: selection, format: format)
        try exporter.write(data, to: destinationURL)
        return TranscriptExportResult(selection: selection, format: format)
    }

    public func apply(_ operation: TranscriptEditOperation) async throws {
        try availableForNewTransition()
        let edited = try TranscriptEditor().applying(operation, to: committed, model: model)
        let intended = stamped(edited, baseRevisionId: committed.revision.id)
        let transition = PendingTransition.operation(
            HistoryEntry(before: committed, after: intended)
        )
        try await save(intended, transition: transition)
    }

    public func undo() async throws {
        try availableForNewTransition()
        guard let entry = undoStack.last else {
            throw TranscriptEditingError(code: .noUndo, context: "undo")
        }
        let intended = stamped(entry.before, baseRevisionId: committed.revision.id)
        try await save(intended, transition: .undo(entry))
    }

    public func redo() async throws {
        try availableForNewTransition()
        guard let entry = redoStack.last else {
            throw TranscriptEditingError(code: .noRedo, context: "redo")
        }
        let intended = stamped(entry.after, baseRevisionId: committed.revision.id)
        try await save(intended, transition: .redo(entry))
    }

    public func retry() async throws {
        guard !isSaving, !isExporting else {
            throw TranscriptEditingError(code: .busy, context: isExporting ? "export" : "save")
        }
        guard let pending else {
            throw TranscriptEditingError(code: .noFailedSave, context: "retry")
        }
        failure = nil
        isSaving = true
        await beforeSave()
        do {
            if let restoration = pendingCancellation {
                try await reconcileCancellation(restoration)
                return
            }
            let active = try await repository.load(sessionId: draft.sessionId, revisionId: nil)
            if active.revision.id == draft.revision.id {
                let activeBytes = try NormalizedTranscriptCodec.encode(active)
                let draftBytes = try NormalizedTranscriptCodec.encode(draft)
                guard activeBytes == draftBytes else {
                    throw TranscriptEditingError(code: .stateConflict, context: "retry-revision")
                }
            } else if active.revision.id == committed.revision.id {
                try await repository.commitRevision(draft)
            } else {
                throw TranscriptEditingError(code: .stateConflict, context: "active-revision")
            }
            finish(pending)
        } catch {
            isSaving = false
            failure = TranscriptEditingFailure(code: .storageFailure, context: "retry")
            throw error
        }
    }

    public func cancelFailedSave() async throws {
        guard !isSaving, !isExporting else {
            throw TranscriptEditingError(code: .busy, context: isExporting ? "export" : "save")
        }
        guard pending != nil else {
            throw TranscriptEditingError(code: .noFailedSave, context: "cancel")
        }
        isSaving = true
        do {
            if let restoration = pendingCancellation {
                try await reconcileCancellation(restoration)
                return
            }
            let active = try await repository.load(sessionId: draft.sessionId, revisionId: nil)
            if active.revision.id == draft.revision.id {
                let activeBytes = try NormalizedTranscriptCodec.encode(active)
                let draftBytes = try NormalizedTranscriptCodec.encode(draft)
                guard activeBytes == draftBytes else {
                    throw TranscriptEditingError(code: .stateConflict, context: "cancel-revision")
                }
                let restoration = stamped(committed, baseRevisionId: active.revision.id)
                pendingCancellation = restoration
                draft = restoration
                try await repository.commitRevision(restoration)
                finishCancellation(restoration)
                return
            } else if active.revision.id != committed.revision.id {
                throw TranscriptEditingError(code: .stateConflict, context: "active-revision")
            }
            draft = committed
            pending = nil
            failure = nil
            isSaving = false
        } catch {
            isSaving = false
            failure = TranscriptEditingFailure(code: .storageFailure, context: "cancel")
            throw error
        }
    }

    private func availableForNewTransition() throws {
        guard !isSaving, !isExporting else {
            throw TranscriptEditingError(code: .busy, context: isExporting ? "export" : "save")
        }
        guard pending == nil else {
            throw TranscriptEditingError(code: .pendingSaveFailure, context: "save")
        }
    }

    private func save(
        _ intended: TranscriptDocument,
        transition: PendingTransition
    ) async throws {
        draft = intended
        pending = transition
        failure = nil
        isSaving = true
        await beforeSave()
        do {
            try await repository.commitRevision(intended)
            finish(transition)
        } catch {
            isSaving = false
            failure = TranscriptEditingFailure(code: .storageFailure, context: "save")
            throw error
        }
    }

    private func reconcileCancellation(_ restoration: TranscriptDocument) async throws {
        let active = try await repository.load(sessionId: restoration.sessionId, revisionId: nil)
        if active.revision.id == restoration.revision.id {
            let activeBytes = try NormalizedTranscriptCodec.encode(active)
            let restorationBytes = try NormalizedTranscriptCodec.encode(restoration)
            guard activeBytes == restorationBytes else {
                throw TranscriptEditingError(code: .stateConflict, context: "restoration-revision")
            }
        } else if active.revision.id == restoration.revision.baseRevisionId {
            try await repository.commitRevision(restoration)
        } else {
            throw TranscriptEditingError(code: .stateConflict, context: "active-revision")
        }
        finishCancellation(restoration)
    }

    private func finishCancellation(_ restoration: TranscriptDocument) {
        committed = restoration
        draft = restoration
        pending = nil
        pendingCancellation = nil
        failure = nil
        isSaving = false
    }

    private func finish(_ transition: PendingTransition) {
        switch transition {
        case let .operation(entry):
            undoStack.append(entry)
            redoStack.removeAll()
        case let .undo(entry):
            _ = undoStack.popLast()
            redoStack.append(entry)
        case let .redo(entry):
            _ = redoStack.popLast()
            undoStack.append(entry)
        }
        committed = draft
        pending = nil
        pendingCancellation = nil
        failure = nil
        isSaving = false
    }

    private func stamped(
        _ document: TranscriptDocument,
        baseRevisionId: String
    ) -> TranscriptDocument {
        var document = document
        let identity = revisionFactory()
        document.revision.id = identity.id
        document.revision.baseRevisionId = baseRevisionId
        document.revision.sourceRunId = document.runId
        document.revision.humanEdited = true
        document.revision.savedAt = identity.savedAt
        return document
    }

    public static func defaultRevisionFactory() -> EditingRevisionIdentity {
        EditingRevisionIdentity(
            id: "revision-\(UUID().uuidString.lowercased())",
            savedAt: ISO8601DateFormatter().string(from: Date())
        )
    }
}

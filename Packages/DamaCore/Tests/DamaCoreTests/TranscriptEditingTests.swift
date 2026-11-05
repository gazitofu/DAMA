import Foundation
import XCTest
@testable import DamaCore

final class TranscriptEditingTests: XCTestCase {
    private struct WordTimes: Equatable {
        let id: String
        let startUs: Microseconds?
        let endUs: Microseconds?

        init(_ value: (String, Microseconds?, Microseconds?)) {
            (id, startUs, endUs) = value
        }
    }

    private enum TestFault: Error {
        case injected
    }

    private actor SaveGate {
        private var saveContinuation: CheckedContinuation<Void, Never>?
        private var enteredContinuation: CheckedContinuation<Void, Never>?
        private var entered = false
        private var releasedPermit = false

        func wait() async {
            entered = true
            enteredContinuation?.resume()
            enteredContinuation = nil
            if releasedPermit {
                releasedPermit = false
                return
            }
            await withCheckedContinuation { saveContinuation = $0 }
        }

        func waitUntilEntered() async {
            if entered { return }
            await withCheckedContinuation { enteredContinuation = $0 }
        }

        func release() {
            if let saveContinuation {
                saveContinuation.resume()
                self.saveContinuation = nil
            } else {
                releasedPermit = true
            }
        }
    }

    private actor PersistThenThrowRepository: TranscriptRepository {
        private let base: FileSessionRepository
        private var shouldThrow = true

        init(base: FileSessionRepository) {
            self.base = base
        }

        func load(sessionId: String, revisionId: String?) async throws -> TranscriptDocument {
            try await base.load(sessionId: sessionId, revisionId: revisionId)
        }

        func commitRevision(_ document: TranscriptDocument) async throws {
            try await base.commitRevision(document)
            if shouldThrow {
                shouldThrow = false
                throw TestFault.injected
            }
        }
    }

    private enum RestorationFailurePoint: Sendable {
        case beforeCommit
        case afterCommit
    }

    private actor RestorationFailureRepository: TranscriptRepository {
        private let base: FileSessionRepository
        private let failurePoint: RestorationFailurePoint
        private var commitCount = 0

        init(base: FileSessionRepository, failurePoint: RestorationFailurePoint) {
            self.base = base
            self.failurePoint = failurePoint
        }

        func load(sessionId: String, revisionId: String?) async throws -> TranscriptDocument {
            try await base.load(sessionId: sessionId, revisionId: revisionId)
        }

        func commitRevision(_ document: TranscriptDocument) async throws {
            commitCount += 1
            if commitCount == 2, failurePoint == .beforeCommit {
                throw TestFault.injected
            }
            try await base.commitRevision(document)
            if commitCount == 1 || (commitCount == 2 && failurePoint == .afterCommit) {
                throw TestFault.injected
            }
        }
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private var normalizedURL: URL {
        repositoryRoot.appendingPathComponent("fixtures/normalized-transcript.json")
    }

    private func fixtureData() throws -> Data { try Data(contentsOf: normalizedURL) }

    private func fixture() throws -> TranscriptDocument {
        try SyntheticTranscriptFixtureLoader.load(data: fixtureData())
    }

    private func temporaryRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DamaEditingTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func editingError(
        _ operation: () throws -> Void
    ) -> TranscriptEditingError? {
        do {
            try operation()
            XCTFail("Expected TranscriptEditingError")
            return nil
        } catch let error as TranscriptEditingError {
            return error
        } catch {
            XCTFail("Unexpected error type: \(type(of: error))")
            return nil
        }
    }

    private func asyncEditingError(
        _ operation: () async throws -> Void
    ) async -> TranscriptEditingError? {
        do {
            try await operation()
            XCTFail("Expected TranscriptEditingError")
            return nil
        } catch let error as TranscriptEditingError {
            return error
        } catch {
            XCTFail("Unexpected error type: \(type(of: error))")
            return nil
        }
    }

    func testAssignmentPreservesModelEvidenceAndOnlySubdividesExistingTurns() throws {
        let model = try fixture()
        let editor = TranscriptEditor()
        let assignedUnknown = try editor.applying(
            .assignWords(wordIds: ["w5"], speakerId: "speaker-c"),
            to: model,
            model: model
        )
        XCTAssertEqual(assignedUnknown.words[4].speakerId, "speaker-c")
        XCTAssertEqual(assignedUnknown.words[4].assignmentSource, .user)
        XCTAssertEqual(assignedUnknown.words[4].text, "네")
        XCTAssertEqual(assignedUnknown.words[4].modelSpeakerId, "speaker-b")
        XCTAssertTrue(assignedUnknown.words[4].overlap)
        XCTAssertEqual(assignedUnknown.turns[3].speakerId, "speaker-c")

        let subdivided = try editor.applying(
            .assignWords(wordIds: ["w1"], speakerId: "speaker-c"),
            to: assignedUnknown,
            model: model
        )
        XCTAssertEqual(subdivided.turns.count, 5)
        XCTAssertEqual(subdivided.turns[0].wordIds, ["w1"])
        XCTAssertEqual(subdivided.turns[1].wordIds, ["w2"])
        XCTAssertEqual(subdivided.turns[2].id, "t-marker")
        let stillSeparate = try editor.applying(
            .assignWords(wordIds: ["w2"], speakerId: "speaker-c"),
            to: subdivided,
            model: model
        )
        XCTAssertEqual(stillSeparate.turns.count, 5)
        XCTAssertEqual(stillSeparate.turns[0].wordIds, ["w1"])
        XCTAssertEqual(stillSeparate.turns[1].wordIds, ["w2"])
        XCTAssertEqual(stillSeparate.turns[2].id, "t-marker")

        let cleared = try editor.applying(
            .assignWords(wordIds: ["w5"], speakerId: nil),
            to: assignedUnknown,
            model: model
        )
        XCTAssertNil(cleared.words[4].speakerId)
        XCTAssertEqual(cleared.words[4].assignmentSource, .unknown)
    }

    func testRenameAndTextEditAreScopedAndReversionUsesModelTimingOrigin() throws {
        let model = try fixture()
        let editor = TranscriptEditor()
        let renamed = try editor.applying(
            .renameSpeaker(speakerId: "speaker-a", displayName: "김담아"),
            to: model,
            model: model
        )
        XCTAssertEqual(renamed.speakers.map(\.displayName), ["김담아", "화자 B", "화자 C"])
        XCTAssertEqual(renamed.speakers.map(\.providerId), model.speakers.map(\.providerId))
        XCTAssertEqual(model.speakers[0].displayName, "화자 A")

        let textEdited = try editor.applying(
            .replaceWordText(wordId: "w1", editedText: "저희는"),
            to: renamed,
            model: model
        )
        XCTAssertEqual(textEdited.words[0].editedText, "저희는")
        XCTAssertEqual(textEdited.words[0].timingOrigin, .inheritedUnaligned)
        XCTAssertEqual(textEdited.words[0].text, "저희가")
        XCTAssertEqual(textEdited.words[0].prefix, "")
        let reverted = try editor.applying(
            .revertWordText(wordId: "w1"),
            to: textEdited,
            model: model
        )
        XCTAssertNil(reverted.words[0].editedText)
        XCTAssertEqual(reverted.words[0].timingOrigin, model.words[0].timingOrigin)

        var nonModelTiming = model
        nonModelTiming.words[0].timingOrigin = .userSelected
        var editedNonModelTiming = nonModelTiming
        editedNonModelTiming.words[0].editedText = "다른 수정"
        editedNonModelTiming.words[0].timingOrigin = .inheritedUnaligned
        let revertedToRecordedOrigin = try editor.applying(
            .revertWordText(wordId: "w1"),
            to: editedNonModelTiming,
            model: nonModelTiming
        )
        XCTAssertEqual(revertedToRecordedOrigin.words[0].timingOrigin, .userSelected)
    }

    func testPersistedRunRenameDoesNotAffectSeparatePersistedRun() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = FileSessionRepository(rootURL: root)
        let firstData = try fixtureData()
        _ = try await repository.importSyntheticTranscript(firstData)
        var second = try fixture()
        second.sessionId = "session-fixture-002"
        second.runId = "run-fixture-002"
        second.revision.id = "revision-fixture-002"
        second.revision.sourceRunId = second.runId
        _ = try await repository.importSyntheticTranscript(
            NormalizedTranscriptCodec.encode(second)
        )

        let firstSession = try await TranscriptEditingSession.open(
            repository: repository,
            sessionId: "session-fixture-001"
        )
        try await firstSession.apply(
            .renameSpeaker(speakerId: "speaker-a", displayName: "첫 Run 이름")
        )
        let reopenedSecond = try await TranscriptEditingSession.open(
            repository: FileSessionRepository(rootURL: root),
            sessionId: second.sessionId
        )
        let secondState = await reopenedSecond.state()
        XCTAssertEqual(secondState.committed.speakers.map(\.displayName),
                       ["화자 A", "화자 B", "화자 C"])
        XCTAssertEqual(secondState.committed.speakers.map(\.providerId),
                       second.speakers.map(\.providerId))
        XCTAssertEqual(secondState.committed.words.map(\.text), second.words.map(\.text))
        XCTAssertEqual(secondState.committed.provenance.engine, second.provenance.engine)
    }

    func testExplicitSplitAndIssueStatusTouchOnlyRequestedEvidence() throws {
        let model = try fixture()
        let editor = TranscriptEditor()
        let split = try editor.applying(
            .splitTurn(turnId: "t1", beforeWordId: "w2"),
            to: model,
            model: model
        )
        XCTAssertEqual(split.turns.count, 5)
        XCTAssertEqual(split.turns[0].wordIds, ["w1"])
        XCTAssertEqual(split.turns[1].wordIds, ["w2"])
        XCTAssertEqual(split.turns[2].id, "t-marker")

        let acknowledged = try editor.applying(
            .acknowledgeIssue(issueId: "i1"),
            to: split,
            model: model
        )
        XCTAssertEqual(acknowledged.reviewIssues[0].status, .acknowledged)
        XCTAssertEqual(acknowledged.reviewIssues[1].status, .open)
        XCTAssertNil(acknowledged.words[4].speakerId)
        XCTAssertEqual(acknowledged.turns[2].id, "t-marker")
        XCTAssertEqual(acknowledged.turns[2].reviewed, model.turns[1].reviewed)
        let reopened = try editor.applying(
            .reopenIssue(issueId: "i1"),
            to: acknowledged,
            model: model
        )
        XCTAssertEqual(reopened.reviewIssues[0].status, .open)
    }

    func testInvalidOperationsThrowWithoutChangingInput() throws {
        let model = try fixture()
        let before = try NormalizedTranscriptCodec.encode(model)
        let editor = TranscriptEditor()
        XCTAssertEqual(editingError {
            _ = try editor.applying(.assignWords(wordIds: [], speakerId: "speaker-a"),
                                    to: model, model: model)
        }?.code, .invalidSelection)
        XCTAssertEqual(editingError {
            _ = try editor.applying(.assignWords(wordIds: ["missing"], speakerId: "speaker-a"),
                                    to: model, model: model)
        }?.code, .unknownWord)
        XCTAssertEqual(editingError {
            _ = try editor.applying(.assignWords(wordIds: ["w1"], speakerId: "missing"),
                                    to: model, model: model)
        }?.code, .unknownSpeaker)
        XCTAssertEqual(editingError {
            _ = try editor.applying(.renameSpeaker(speakerId: "speaker-a", displayName: "  "),
                                    to: model, model: model)
        }?.code, .invalidDisplayName)
        XCTAssertEqual(editingError {
            _ = try editor.applying(.splitTurn(turnId: "t1", beforeWordId: "w1"),
                                    to: model, model: model)
        }?.code, .invalidSplit)
        XCTAssertEqual(editingError {
            _ = try editor.applying(.splitTurn(turnId: "t-marker", beforeWordId: "w1"),
                                    to: model, model: model)
        }?.code, .invalidSplit)
        XCTAssertEqual(editingError {
            _ = try editor.applying(.acknowledgeIssue(issueId: "missing"),
                                    to: model, model: model)
        }?.code, .unknownIssue)
        XCTAssertEqual(try NormalizedTranscriptCodec.encode(model), before)

        var duplicate = model
        duplicate.words[1].id = duplicate.words[0].id
        let duplicateIDs = duplicate.words.map(\.id)
        XCTAssertEqual(editingError {
            _ = try editor.applying(.renameSpeaker(speakerId: "speaker-a", displayName: "안전"),
                                    to: duplicate, model: model)
        }?.code, .stateConflict)
        XCTAssertEqual(duplicate.words.map(\.id), duplicateIDs)
    }

    func testUntimedWordSplitAssignmentAndReversionPersistUnknownRange() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        var source = try fixture()
        source.sessionId = "session-untimed"
        source.runId = "run-untimed"
        source.revision.id = "revision-untimed-model"
        source.revision.sourceRunId = source.runId
        source.words[0].startUs = nil
        source.words[0].endUs = nil
        source.words[0].timingOrigin = .none
        let sourceData = try NormalizedTranscriptCodec.encode(source)
        let repository = FileSessionRepository(rootURL: root)
        _ = try await repository.importSyntheticTranscript(sourceData)
        let session = try await TranscriptEditingSession.open(
            repository: repository,
            sessionId: source.sessionId
        )

        try await session.apply(.splitTurn(turnId: "t1", beforeWordId: "w2"))
        let split = await session.state()
        XCTAssertNil(split.committed.turns[0].startUs)
        XCTAssertNil(split.committed.turns[0].endUs)
        XCTAssertEqual(split.committed.turns[1].startUs, 400_000)
        XCTAssertEqual(split.committed.turns[1].endUs, 700_000)
        XCTAssertNil(split.committed.words[0].startUs)
        XCTAssertNil(split.committed.words[0].endUs)
        XCTAssertEqual(split.committed.words[0].timingOrigin, .none)
        XCTAssertEqual(split.committed.words[0].text, source.words[0].text)
        XCTAssertEqual(split.committed.words[0].prefix, source.words[0].prefix)
        XCTAssertEqual(split.committed.words[0].modelSpeakerId, source.words[0].modelSpeakerId)
        XCTAssertEqual(split.committed.words[0].alignmentScore, source.words[0].alignmentScore)
        XCTAssertEqual(split.committed.words[0].overlap, source.words[0].overlap)
        XCTAssertEqual(split.committed.words[0].sourceIntervalIds, source.words[0].sourceIntervalIds)
        let splitReloaded = try await FileSessionRepository(rootURL: root).load(
            sessionId: source.sessionId,
            revisionId: nil
        )
        XCTAssertNil(splitReloaded.turns[0].startUs)
        XCTAssertEqual(splitReloaded.turns[1].startUs, 400_000)

        try await session.undo()
        try await session.apply(.assignWords(wordIds: ["w1"], speakerId: "speaker-c"))
        let assigned = await session.state()
        XCTAssertNil(assigned.committed.turns[0].startUs)
        XCTAssertNil(assigned.committed.turns[0].endUs)
        XCTAssertEqual(assigned.committed.turns[1].startUs, 400_000)
        XCTAssertEqual(assigned.committed.turns[1].endUs, 700_000)
        try await session.apply(.replaceWordText(wordId: "w1", editedText: "수정"))
        try await session.apply(.revertWordText(wordId: "w1"))
        let reverted = await session.state()
        XCTAssertNil(reverted.committed.words[0].editedText)
        XCTAssertEqual(reverted.committed.words[0].timingOrigin, .none)
        XCTAssertNil(reverted.committed.words[0].startUs)
        let reopened = try await TranscriptEditingSession.open(
            repository: FileSessionRepository(rootURL: root),
            sessionId: source.sessionId
        )
        let reopenedState = await reopened.state()
        XCTAssertEqual(reopenedState.committed.words[0].timingOrigin, .none)
        XCTAssertNil(reopenedState.committed.turns[0].startUs)
        XCTAssertEqual(reopenedState.committed.turns[1].startUs, 400_000)
    }

    func testSegmentRangeEnclosesOverlappingTimedWordsUsingMinAndMaxBounds() throws {
        var model = try fixture()
        model.words[0].endUs = 700_000
        model.words[1].endUs = 500_000
        var third = model.words[1]
        third.id = "w-extra"
        third.ordinal = 2
        third.text = "추가"
        third.prefix = " "
        third.startUs = 750_000
        third.endUs = 800_000
        for index in 2..<model.words.count { model.words[index].ordinal += 1 }
        model.words.insert(third, at: 2)
        model.turns[0].wordIds.append(third.id)
        model.turns[0].endUs = third.endUs
        try TranscriptValidator().validate(model)
        let originalTimes = model.words.map { ($0.id, $0.startUs, $0.endUs) }

        let split = try TranscriptEditor().applying(
            .splitTurn(turnId: "t1", beforeWordId: third.id),
            to: model,
            model: model
        )

        XCTAssertEqual(split.turns[0].startUs, 100_000)
        XCTAssertEqual(split.turns[0].endUs, 700_000)
        XCTAssertEqual(split.turns[1].startUs, 750_000)
        XCTAssertEqual(split.turns[1].endUs, 800_000)
        XCTAssertEqual(split.words.map { ($0.id, $0.startUs, $0.endUs) }.map(WordTimes.init),
                       originalTimes.map(WordTimes.init))
        XCTAssertNoThrow(try TranscriptValidator().validate(split))
    }

    func testFreshEditorOpenLeavesRecoveryNoticeAvailableFromRepository() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = FileSessionRepository(rootURL: root)
        _ = try await repository.importSyntheticTranscript(fixtureData())
        let pointer = root.appendingPathComponent(
            "Sessions/session-fixture-001/session.json"
        )
        try FileManager.default.removeItem(at: pointer)

        _ = try await TranscriptEditingSession.open(
            repository: repository,
            sessionId: "session-fixture-001"
        )
        let notices = await repository.recoveryNotices()
        XCTAssertEqual(notices.count, 1)
        XCTAssertEqual(notices[0].reason, .activePointerMissing)
        XCTAssertEqual(notices[0].recoveredRevisionId, "revision-fixture-001")
    }

    func testIssueOrderingTimedTieNullAndTerminalBehavior() throws {
        var document = try fixture()
        var timedLater = document.reviewIssues[0]
        timedLater.id = "issue-b"
        timedLater.startUs = 2_100_000
        timedLater.endUs = 2_200_000
        timedLater.status = .open
        var timedTie = timedLater
        timedTie.id = "issue-a"
        var untimed = timedLater
        untimed.id = "issue-null"
        untimed.startUs = nil
        untimed.endUs = nil
        document.reviewIssues = [untimed, timedLater, document.reviewIssues[0], timedTie]

        let ordered = TranscriptIssueOrdering.openIssues(in: document)
        XCTAssertEqual(ordered.map(\.id), ["i1", "issue-a", "issue-b", "issue-null"])
        XCTAssertEqual(
            try TranscriptIssueOrdering.nextOpenIssue(after: nil, in: document)?.id,
            "i1"
        )
        XCTAssertEqual(
            try TranscriptIssueOrdering.nextOpenIssue(after: "i1", in: document)?.id,
            "issue-a"
        )
        XCTAssertNil(try TranscriptIssueOrdering.nextOpenIssue(after: "issue-null", in: document))
        XCTAssertEqual(editingError {
            _ = try TranscriptIssueOrdering.nextOpenIssue(after: "missing", in: document)
        }?.code, .unknownIssue)
        document.reviewIssues.indices.forEach { document.reviewIssues[$0].status = .acknowledged }
        XCTAssertNil(try TranscriptIssueOrdering.nextOpenIssue(after: nil, in: document))
    }

    func testSessionUndoRedoSplitAndReopenPersistEverySnapshot() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = FileSessionRepository(rootURL: root)
        _ = try await repository.importSyntheticTranscript(fixtureData())
        let session = try await TranscriptEditingSession.open(
            repository: repository,
            sessionId: "session-fixture-001"
        )

        try await session.apply(.splitTurn(turnId: "t1", beforeWordId: "w2"))
        let splitState = await session.state()
        XCTAssertEqual(splitState.committed.turns.count, 5)
        XCTAssertTrue(splitState.canUndo)
        XCTAssertTrue(splitState.canExport)
        XCTAssertEqual(splitState.committed.revision.baseRevisionId, "revision-fixture-001")

        try await session.undo()
        let undoneSplit = await session.state()
        XCTAssertEqual(undoneSplit.committed.turns.count, 4)
        XCTAssertTrue(undoneSplit.canRedo)
        XCTAssertEqual(undoneSplit.committed.revision.baseRevisionId, splitState.committed.revision.id)
        try await session.redo()
        let redoneSplit = await session.state()
        XCTAssertEqual(redoneSplit.committed.turns.count, 5)

        try await session.apply(.assignWords(wordIds: ["w5"], speakerId: "speaker-c"))
        try await session.undo()
        let undoneAssignment = await session.state()
        XCTAssertEqual(undoneAssignment.committed.turns.count, 5)
        XCTAssertNil(undoneAssignment.committed.words[4].speakerId)
        try await session.redo()
        let redone = await session.state()
        XCTAssertEqual(redone.committed.turns.count, 5)
        XCTAssertEqual(redone.committed.words[4].speakerId, "speaker-c")
        XCTAssertEqual(redone.committed.words[4].modelSpeakerId, "speaker-b")
        XCTAssertEqual(redone.committed.words[4].text, "네")

        let reopened = try await TranscriptEditingSession.open(
            repository: FileSessionRepository(rootURL: root),
            sessionId: "session-fixture-001"
        )
        let reopenedState = await reopened.state()
        XCTAssertEqual(reopenedState.committed.revision.id, redone.committed.revision.id)
        XCTAssertEqual(reopenedState.committed.turns.count, 5)
        XCTAssertEqual(reopenedState.committed.words[4].speakerId, "speaker-c")
        XCTAssertFalse(reopenedState.canUndo)
        XCTAssertFalse(reopenedState.canRedo)

        let reopenedRepository = FileSessionRepository(rootURL: root)
        let persistedSplit = try await reopenedRepository.load(
            sessionId: "session-fixture-001",
            revisionId: splitState.committed.revision.id
        )
        let persistedUndo = try await reopenedRepository.load(
            sessionId: "session-fixture-001",
            revisionId: undoneSplit.committed.revision.id
        )
        XCTAssertEqual(persistedSplit.turns.count, 5)
        XCTAssertEqual(persistedUndo.turns.count, 4)
    }

    func testTextEditUndoRedoAndIssueAcknowledgePersistOriginalEvidence() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = FileSessionRepository(rootURL: root)
        _ = try await repository.importSyntheticTranscript(fixtureData())
        let session = try await TranscriptEditingSession.open(
            repository: repository,
            sessionId: "session-fixture-001"
        )
        try await session.apply(.replaceWordText(wordId: "w1", editedText: "저희는"))
        let edited = await session.state()
        XCTAssertEqual(edited.committed.words[0].timingOrigin, .inheritedUnaligned)
        try await session.undo()
        let undone = await session.state()
        XCTAssertNil(undone.committed.words[0].editedText)
        XCTAssertEqual(undone.committed.words[0].timingOrigin, .model)
        XCTAssertEqual(undone.committed.words[0].text, "저희가")
        try await session.redo()
        let redone = await session.state()
        XCTAssertEqual(redone.committed.words[0].editedText, "저희는")
        try await session.apply(.acknowledgeIssue(issueId: "i1"))
        let acknowledged = await session.state()
        XCTAssertEqual(acknowledged.committed.reviewIssues[0].status, .acknowledged)
        XCTAssertEqual(acknowledged.committed.reviewIssues[1].status, .open)
        XCTAssertNil(acknowledged.committed.words[4].speakerId)
        XCTAssertEqual(acknowledged.committed.turns[1].id, "t-marker")
        XCTAssertFalse(acknowledged.committed.turns[1].reviewed)
    }

    func testFailedSaveKeepsDraftRetryCommitsSameRevisionAndCancelRestoresCommitted() async throws {
        let retryRoot = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: retryRoot) }
        let setup = FileSessionRepository(rootURL: retryRoot)
        _ = try await setup.importSyntheticTranscript(fixtureData())
        let faultMarker = retryRoot.appendingPathComponent(".faulted-once")
        let failing = FileSessionRepository(rootURL: retryRoot) { stage in
            if stage == .afterFinalRevisionInstallation,
               !FileManager.default.fileExists(atPath: faultMarker.path) {
                try Data().write(to: faultMarker)
                throw TestFault.injected
            }
        }
        let retrySession = try await TranscriptEditingSession.open(
            repository: failing,
            sessionId: "session-fixture-001"
        )
        do {
            try await retrySession.apply(.renameSpeaker(speakerId: "speaker-a", displayName: "재시도"))
            XCTFail("Expected injected save failure")
        } catch TestFault.injected {}
        let failed = await retrySession.state()
        XCTAssertTrue(failed.isDirty)
        XCTAssertFalse(failed.isSaving)
        XCTAssertNotNil(failed.failure)
        XCTAssertFalse(failed.canExport)
        XCTAssertEqual(failed.committed.speakers[0].displayName, "화자 A")
        XCTAssertEqual(failed.draft.speakers[0].displayName, "재시도")
        let intendedRevision = failed.draft.revision.id
        try await retrySession.retry()
        let retried = await retrySession.state()
        XCTAssertFalse(retried.isDirty)
        XCTAssertNil(retried.failure)
        XCTAssertTrue(retried.canExport)
        XCTAssertEqual(retried.committed.revision.id, intendedRevision)
        XCTAssertEqual(retried.committed.speakers[0].displayName, "재시도")

        let revisionBeforeInvalid = retried.committed.revision.id
        let invalid = await asyncEditingError {
            try await retrySession.apply(.assignWords(wordIds: [], speakerId: "speaker-a"))
        }
        XCTAssertEqual(invalid?.code, .invalidSelection)
        let afterInvalid = await retrySession.state()
        XCTAssertEqual(afterInvalid.committed.revision.id, revisionBeforeInvalid)
        XCTAssertFalse(afterInvalid.isDirty)
        let persistedAfterInvalid = try await failing.load(
            sessionId: afterInvalid.committed.sessionId,
            revisionId: nil
        )
        XCTAssertEqual(persistedAfterInvalid.revision.id, revisionBeforeInvalid)

        let cancelRoot = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: cancelRoot) }
        let cancelSetup = FileSessionRepository(rootURL: cancelRoot)
        _ = try await cancelSetup.importSyntheticTranscript(fixtureData())
        let cancelRepository = FileSessionRepository(rootURL: cancelRoot) { stage in
            if stage == .afterPartialTemporaryRevisionWrite { throw TestFault.injected }
        }
        let cancelSession = try await TranscriptEditingSession.open(
            repository: cancelRepository,
            sessionId: "session-fixture-001"
        )
        do {
            try await cancelSession.apply(.renameSpeaker(speakerId: "speaker-a", displayName: "취소"))
            XCTFail("Expected injected save failure")
        } catch TestFault.injected {}
        try await cancelSession.cancelFailedSave()
        let cancelled = await cancelSession.state()
        XCTAssertFalse(cancelled.isDirty)
        XCTAssertNil(cancelled.failure)
        XCTAssertEqual(cancelled.draft.speakers[0].displayName, "화자 A")
        XCTAssertEqual(cancelled.committed.speakers[0].displayName, "화자 A")
        let reopened = try await FileSessionRepository(rootURL: cancelRoot).load(
            sessionId: "session-fixture-001",
            revisionId: nil
        )
        XCTAssertEqual(reopened.speakers[0].displayName, "화자 A")
    }

    func testCancelAfterAmbiguousWritePersistsRestorationBeforeClaimingSaved() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let baseRepository = FileSessionRepository(rootURL: root)
        _ = try await baseRepository.importSyntheticTranscript(fixtureData())
        let committed = try await baseRepository.load(
            sessionId: "session-fixture-001",
            revisionId: nil
        )
        let model = try await baseRepository.loadModel(
            sessionId: committed.sessionId,
            runId: committed.runId
        )
        let ambiguous = PersistThenThrowRepository(base: baseRepository)
        let session = TranscriptEditingSession(
            repository: ambiguous,
            committed: committed,
            model: model
        )
        do {
            try await session.apply(.renameSpeaker(speakerId: "speaker-a", displayName: "모호한 저장"))
            XCTFail("Expected post-commit injected failure")
        } catch TestFault.injected {}
        let failed = await session.state()
        XCTAssertEqual(failed.committed.speakers[0].displayName, "화자 A")
        XCTAssertEqual(failed.draft.speakers[0].displayName, "모호한 저장")
        XCTAssertTrue(failed.isDirty)
        XCTAssertFalse(failed.canExport)
        let persistedIntended = try await baseRepository.load(
            sessionId: committed.sessionId,
            revisionId: nil
        )
        XCTAssertEqual(persistedIntended.revision.id, failed.draft.revision.id)

        try await session.cancelFailedSave()
        let cancelled = await session.state()
        XCTAssertFalse(cancelled.isDirty)
        XCTAssertNil(cancelled.failure)
        XCTAssertTrue(cancelled.canExport)
        XCTAssertEqual(cancelled.committed.speakers[0].displayName, "화자 A")
        XCTAssertNotEqual(cancelled.committed.revision.id, committed.revision.id)
        XCTAssertEqual(cancelled.committed.revision.baseRevisionId, persistedIntended.revision.id)
        let restarted = try await FileSessionRepository(rootURL: root).load(
            sessionId: committed.sessionId,
            revisionId: nil
        )
        XCTAssertEqual(restarted.revision.id, cancelled.committed.revision.id)
        XCTAssertEqual(restarted.speakers[0].displayName, "화자 A")
    }

    func testRetryReconcilesRestorationThatPersistedBeforeFailure() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let base = FileSessionRepository(rootURL: root)
        _ = try await base.importSyntheticTranscript(fixtureData())
        let original = try await base.load(sessionId: "session-fixture-001", revisionId: nil)
        let model = try await base.loadModel(sessionId: original.sessionId, runId: original.runId)
        let repository = RestorationFailureRepository(base: base, failurePoint: .afterCommit)
        let session = TranscriptEditingSession(repository: repository, committed: original, model: model)

        do {
            try await session.apply(.renameSpeaker(speakerId: "speaker-a", displayName: "저장된 편집"))
            XCTFail("Expected failure after edit commit")
        } catch TestFault.injected {}
        let editFailure = await session.state()
        let editRevisionID = editFailure.draft.revision.id

        do {
            try await session.cancelFailedSave()
            XCTFail("Expected failure after restoration commit")
        } catch TestFault.injected {}
        let restorationFailure = await session.state()
        let restorationRevisionID = restorationFailure.draft.revision.id
        XCTAssertTrue(restorationFailure.isDirty)
        XCTAssertFalse(restorationFailure.canExport)
        XCTAssertEqual(restorationFailure.draft.speakers[0].displayName, "화자 A")
        XCTAssertFalse(restorationFailure.canUndo)
        XCTAssertFalse(restorationFailure.canRedo)
        let activeRestoration = try await base.load(sessionId: original.sessionId, revisionId: nil)
        XCTAssertEqual(activeRestoration.revision.id, restorationRevisionID)

        try await session.retry()
        let reconciled = await session.state()
        XCTAssertFalse(reconciled.isDirty)
        XCTAssertNil(reconciled.failure)
        XCTAssertTrue(reconciled.canExport)
        XCTAssertEqual(reconciled.committed.revision.id, restorationRevisionID)
        XCTAssertEqual(reconciled.committed.speakers[0].displayName, "화자 A")
        XCTAssertFalse(reconciled.canUndo)
        XCTAssertFalse(reconciled.canRedo)
        _ = try await base.load(sessionId: original.sessionId, revisionId: editRevisionID)
        _ = try await base.load(sessionId: original.sessionId, revisionId: restorationRevisionID)
    }

    func testCancelRetriesSameRestorationAfterFailureBeforeCommit() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let base = FileSessionRepository(rootURL: root)
        _ = try await base.importSyntheticTranscript(fixtureData())
        let original = try await base.load(sessionId: "session-fixture-001", revisionId: nil)
        let model = try await base.loadModel(sessionId: original.sessionId, runId: original.runId)
        let repository = RestorationFailureRepository(base: base, failurePoint: .beforeCommit)
        let session = TranscriptEditingSession(repository: repository, committed: original, model: model)

        do {
            try await session.apply(.renameSpeaker(speakerId: "speaker-a", displayName: "저장된 편집"))
            XCTFail("Expected failure after edit commit")
        } catch TestFault.injected {}
        let editFailure = await session.state()
        let editRevisionID = editFailure.draft.revision.id

        do {
            try await session.cancelFailedSave()
            XCTFail("Expected failure before restoration commit")
        } catch TestFault.injected {}
        let restorationFailure = await session.state()
        let restorationRevisionID = restorationFailure.draft.revision.id
        XCTAssertTrue(restorationFailure.isDirty)
        XCTAssertFalse(restorationFailure.canExport)
        XCTAssertEqual(restorationFailure.draft.speakers[0].displayName, "화자 A")
        let stillEdited = try await base.load(sessionId: original.sessionId, revisionId: nil)
        XCTAssertEqual(stillEdited.revision.id, editRevisionID)

        try await session.cancelFailedSave()
        let cancelled = await session.state()
        XCTAssertFalse(cancelled.isDirty)
        XCTAssertNil(cancelled.failure)
        XCTAssertTrue(cancelled.canExport)
        XCTAssertEqual(cancelled.committed.revision.id, restorationRevisionID)
        XCTAssertEqual(cancelled.committed.speakers[0].displayName, "화자 A")
        XCTAssertFalse(cancelled.canUndo)
        XCTAssertFalse(cancelled.canRedo)
        _ = try await base.load(sessionId: original.sessionId, revisionId: editRevisionID)
        let persistedRestoration = try await base.load(
            sessionId: original.sessionId,
            revisionId: restorationRevisionID
        )
        XCTAssertEqual(persistedRestoration.speakers[0].displayName, "화자 A")
    }

    func testOverlappingCommandIsRejectedWhileRealRepositorySaveIsSuspended() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = FileSessionRepository(rootURL: root)
        _ = try await repository.importSyntheticTranscript(fixtureData())
        let committed = try await repository.load(sessionId: "session-fixture-001", revisionId: nil)
        let model = try await repository.loadModel(
            sessionId: committed.sessionId,
            runId: committed.runId
        )
        let gate = SaveGate()
        let session = TranscriptEditingSession(
            repository: repository,
            committed: committed,
            model: model,
            beforeSave: { await gate.wait() }
        )
        let first = Task {
            try await session.apply(.renameSpeaker(speakerId: "speaker-a", displayName: "저장 중"))
        }
        await gate.waitUntilEntered()
        let saving = await session.state()
        XCTAssertTrue(saving.isSaving)
        XCTAssertFalse(saving.canExport)
        let overlap = await asyncEditingError {
            try await session.apply(.acknowledgeIssue(issueId: "i1"))
        }
        XCTAssertEqual(overlap?.code, .busy)
        await gate.release()
        try await first.value
        let finished = await session.state()
        XCTAssertEqual(finished.committed.speakers[0].displayName, "저장 중")
    }
}

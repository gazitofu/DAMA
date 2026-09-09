import CryptoKit
import Foundation
import XCTest
@testable import DamaCore

final class FileSessionRepositoryTests: XCTestCase {
    private enum TestFault: Error {
        case injected
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

    private func fixtureData() throws -> Data {
        try Data(contentsOf: normalizedURL)
    }

    private func temporaryRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DamaCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func sessionURL(_ root: URL, _ sessionId: String = "session-fixture-001") -> URL {
        root.appendingPathComponent("Sessions", isDirectory: true)
            .appendingPathComponent(sessionId, isDirectory: true)
    }

    private func rawURL(
        _ root: URL,
        sessionId: String = "session-fixture-001",
        runId: String = "run-fixture-001"
    ) -> URL {
        sessionURL(root, sessionId)
            .appendingPathComponent("runs/\(runId)/raw/synthetic-normalized-input.json")
    }

    private func modelURL(
        _ root: URL,
        sessionId: String = "session-fixture-001",
        runId: String = "run-fixture-001"
    ) -> URL {
        sessionURL(root, sessionId)
            .appendingPathComponent("runs/\(runId)/normalized/model.json")
    }

    private func revisionURL(
        _ root: URL,
        _ revisionId: String,
        sessionId: String = "session-fixture-001"
    ) -> URL {
        sessionURL(root, sessionId)
            .appendingPathComponent("revisions/\(revisionId).json")
    }

    private func pointerURL(_ root: URL, sessionId: String = "session-fixture-001") -> URL {
        sessionURL(root, sessionId).appendingPathComponent("session.json")
    }

    private func digest(_ url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }

    private func edited(
        _ base: TranscriptDocument,
        revisionId: String,
        savedAt: String,
        displayName: String = "검수자 A"
    ) -> TranscriptDocument {
        var document = base
        document.speakers[0].displayName = displayName
        document.words[4].speakerId = "speaker-c"
        document.words[4].assignmentSource = .user
        document.turns[3].speakerId = "speaker-c"
        document.reviewIssues[0].status = .acknowledged
        document.revision.id = revisionId
        document.revision.baseRevisionId = base.revision.id
        document.revision.humanEdited = true
        document.revision.savedAt = savedAt
        return document
    }

    private func repositoryError(
        _ operation: () async throws -> Void
    ) async -> SessionRepositoryError? {
        do {
            try await operation()
            XCTFail("Expected SessionRepositoryError")
            return nil
        } catch let error as SessionRepositoryError {
            return error
        } catch {
            XCTFail("Unexpected error type: \(type(of: error))")
            return nil
        }
    }

    func testSyntheticImportPreservesSourceModelAndListsSession() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try fixtureData()
        let repository = FileSessionRepository(rootURL: root)

        let imported = try await repository.importSyntheticTranscript(source)

        XCTAssertTrue(imported.installedNewData)
        let initialNotices = await repository.recoveryNotices()
        XCTAssertTrue(initialNotices.isEmpty)
        XCTAssertEqual(try Data(contentsOf: rawURL(root)), source)
        let model = try await repository.loadModel(
            sessionId: imported.sessionId,
            runId: imported.runId
        )
        XCTAssertTrue(model.provenance.isSynthetic)
        XCTAssertEqual(model.provenance.engine, .hybridPyannoteWhisperKit)
        XCTAssertEqual(model.revision.id, "revision-fixture-001")
        let active = try await repository.load(sessionId: imported.sessionId, revisionId: nil)
        XCTAssertEqual(active.revision.id, "revision-fixture-001")
        let sessions = try await repository.listSessions()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].activeRunId, "run-fixture-001")
        XCTAssertTrue(FileManager.default.fileExists(atPath: rawURL(root).path))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: sessionURL(root).appendingPathComponent(
                    "runs/run-fixture-001/raw/pyannote-response.json"
                ).path
            )
        )
    }

    func testPartialTemporaryWritePreservesAllPriorHashesAndActive() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try fixtureData()
        let setup = FileSessionRepository(rootURL: root)
        _ = try await setup.importSyntheticTranscript(source)
        let base = try await setup.load(sessionId: "session-fixture-001", revisionId: nil)
        let before = try [
            digest(rawURL(root)),
            digest(modelURL(root)),
            digest(revisionURL(root, base.revision.id))
        ]
        let repository = FileSessionRepository(rootURL: root) { stage in
            if stage == .afterPartialTemporaryRevisionWrite { throw TestFault.injected }
        }

        do {
            try await repository.commitRevision(edited(
                base,
                revisionId: "revision-partial",
                savedAt: "2026-09-09T01:00:00Z"
            ))
            XCTFail("Expected injected failure")
        } catch TestFault.injected {}

        let after = try [
            digest(rawURL(root)),
            digest(modelURL(root)),
            digest(revisionURL(root, base.revision.id))
        ]
        XCTAssertEqual(after, before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: revisionURL(root, "revision-partial").path))
        let reloaded = try await FileSessionRepository(rootURL: root).load(
            sessionId: base.sessionId,
            revisionId: nil
        )
        XCTAssertEqual(reloaded.revision.id, base.revision.id)
    }

    func testInstalledOrphanDoesNotOverrideValidPointerAndRetrySucceeds() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try fixtureData()
        let setup = FileSessionRepository(rootURL: root)
        _ = try await setup.importSyntheticTranscript(source)
        let base = try await setup.load(sessionId: "session-fixture-001", revisionId: nil)
        let before = try [
            digest(rawURL(root)),
            digest(modelURL(root)),
            digest(revisionURL(root, base.revision.id))
        ]
        let next = edited(
            base,
            revisionId: "revision-orphan-retry",
            savedAt: "2026-09-09T02:00:00Z"
        )
        let failing = FileSessionRepository(rootURL: root) { stage in
            if stage == .afterFinalRevisionInstallation { throw TestFault.injected }
        }

        do {
            try await failing.commitRevision(next)
            XCTFail("Expected injected failure")
        } catch TestFault.injected {}

        XCTAssertEqual(try [
            digest(rawURL(root)),
            digest(modelURL(root)),
            digest(revisionURL(root, base.revision.id))
        ], before)
        XCTAssertTrue(FileManager.default.fileExists(atPath: revisionURL(root, next.revision.id).path))
        let restarted = FileSessionRepository(rootURL: root)
        let stillActive = try await restarted.loadWithRecovery(sessionId: base.sessionId)
        XCTAssertEqual(stillActive.document.revision.id, base.revision.id)
        XCTAssertNil(stillActive.recoveryNotice)

        try await restarted.commitRevision(next)
        let committed = try await FileSessionRepository(rootURL: root).load(
            sessionId: base.sessionId,
            revisionId: nil
        )
        XCTAssertEqual(committed.revision.id, next.revision.id)
        XCTAssertEqual(committed.words[4].speakerId, "speaker-c")
        XCTAssertEqual(committed.words[4].modelSpeakerId, "speaker-b")
        XCTAssertEqual(committed.words[4].text, "네")
    }

    func testCorruptPointerRecoversLatestValidAndIgnoresMalformedCandidate() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = FileSessionRepository(rootURL: root)
        _ = try await repository.importSyntheticTranscript(fixtureData())
        let base = try await repository.load(sessionId: "session-fixture-001", revisionId: nil)
        let next = edited(
            base,
            revisionId: "revision-valid-latest",
            savedAt: "2026-09-09T03:00:00Z"
        )
        try await repository.commitRevision(next)
        let protectedHashes = try [
            digest(rawURL(root)),
            digest(modelURL(root)),
            digest(revisionURL(root, base.revision.id))
        ]
        try Data("{truncated".utf8).write(to: revisionURL(root, "revision-malformed"))
        try Data("not a pointer".utf8).write(to: pointerURL(root))

        let restarted = FileSessionRepository(rootURL: root)
        let loaded = try await restarted.loadWithRecovery(sessionId: base.sessionId)

        XCTAssertEqual(loaded.document.revision.id, next.revision.id)
        XCTAssertEqual(loaded.recoveryNotice?.reason, .activePointerCorrupt)
        XCTAssertEqual(loaded.recoveryNotice?.recoveredRevisionId, next.revision.id)
        let notices = await restarted.recoveryNotices()
        XCTAssertEqual(notices.count, 1)
        XCTAssertEqual(try [
            digest(rawURL(root)),
            digest(modelURL(root)),
            digest(revisionURL(root, base.revision.id))
        ], protectedHashes)

        try FileManager.default.removeItem(at: pointerURL(root))
        let missingPointerReload = try await FileSessionRepository(rootURL: root)
            .loadWithRecovery(sessionId: base.sessionId)
        XCTAssertEqual(missingPointerReload.document.revision.id, next.revision.id)
        XCTAssertEqual(missingPointerReload.recoveryNotice?.reason, .activePointerMissing)
    }

    func testStaleBaseAndConflictingExistingRevisionAreRejected() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = FileSessionRepository(rootURL: root)
        _ = try await repository.importSyntheticTranscript(fixtureData())
        let base = try await repository.load(sessionId: "session-fixture-001", revisionId: nil)
        let first = edited(base, revisionId: "revision-first", savedAt: "2026-09-09T04:00:00Z")
        try await repository.commitRevision(first)
        let stale = edited(base, revisionId: "revision-stale", savedAt: "2026-09-09T05:00:00Z")
        let staleError = await repositoryError { try await repository.commitRevision(stale) }
        XCTAssertEqual(staleError?.code, .staleBaseRevision)

        let conflictRoot = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: conflictRoot) }
        let conflictSetup = FileSessionRepository(rootURL: conflictRoot)
        _ = try await conflictSetup.importSyntheticTranscript(fixtureData())
        let conflictBase = try await conflictSetup.load(
            sessionId: "session-fixture-001",
            revisionId: nil
        )
        let installed = edited(
            conflictBase,
            revisionId: "revision-conflict",
            savedAt: "2026-09-09T06:00:00Z",
            displayName: "first bytes"
        )
        let failing = FileSessionRepository(rootURL: conflictRoot) { stage in
            if stage == .afterFinalRevisionInstallation { throw TestFault.injected }
        }
        do {
            try await failing.commitRevision(installed)
            XCTFail("Expected injected failure")
        } catch TestFault.injected {}

        let different = edited(
            conflictBase,
            revisionId: "revision-conflict",
            savedAt: "2026-09-09T06:00:00Z",
            displayName: "different bytes"
        )
        let retry = FileSessionRepository(rootURL: conflictRoot)
        let conflictError = await repositoryError { try await retry.commitRevision(different) }
        XCTAssertEqual(conflictError?.code, .conflictingRevision)
    }

    func testUnsafeIdentifiersAndSymlinkEscapeAreRejectedBeforeStorageAccess() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        var unsafe = try SyntheticTranscriptFixtureLoader.load(data: fixtureData())
        unsafe.sessionId = "../escape"
        let unsafeData = try NormalizedTranscriptCodec.encode(unsafe)
        let repository = FileSessionRepository(rootURL: root)
        let unsafeError = await repositoryError {
            _ = try await repository.importSyntheticTranscript(unsafeData)
        }
        XCTAssertEqual(unsafeError?.code, .invalidIdentifier)

        let outside = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: outside) }
        let sessions = root.appendingPathComponent("Sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: sessions.appendingPathComponent("linked-session"),
            withDestinationURL: outside
        )
        var linked = try SyntheticTranscriptFixtureLoader.load(data: fixtureData())
        linked.sessionId = "linked-session"
        linked.revision.id = "revision-linked"
        let linkedData = try NormalizedTranscriptCodec.encode(linked)
        let linkedError = await repositoryError {
            _ = try await repository.importSyntheticTranscript(linkedData)
        }
        XCTAssertEqual(linkedError?.code, .unsafePath)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outside.path), [])
    }

    func testLeadingDotSessionAndRevisionIdentifiersAreRejected() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = FileSessionRepository(rootURL: root)
        var hiddenSession = try SyntheticTranscriptFixtureLoader.load(data: fixtureData())
        hiddenSession.sessionId = ".hidden-session"
        let hiddenSessionError = await repositoryError {
            _ = try await repository.importSyntheticTranscript(
                NormalizedTranscriptCodec.encode(hiddenSession)
            )
        }
        XCTAssertEqual(hiddenSessionError?.code, .invalidIdentifier)

        var hiddenRevision = try SyntheticTranscriptFixtureLoader.load(data: fixtureData())
        hiddenRevision.revision.id = ".hidden-revision"
        let hiddenRevisionError = await repositoryError {
            _ = try await repository.importSyntheticTranscript(
                NormalizedTranscriptCodec.encode(hiddenRevision)
            )
        }
        XCTAssertEqual(hiddenRevisionError?.code, .invalidIdentifier)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Sessions").path))
    }

    func testUnreadableStorageShapeThrowsInsteadOfReturningEmptyHistory() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("not a directory".utf8).write(to: root.appendingPathComponent("Sessions"))
        let repository = FileSessionRepository(rootURL: root)
        let error = await repositoryError { _ = try await repository.listSessions() }
        XCTAssertEqual(error?.code, .ioFailure)
    }

    func testModelMarkerAndOriginalSpeechTurnBoundariesRemainEvidence() async throws {
        let markerRoot = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: markerRoot) }
        let markerRepository = FileSessionRepository(rootURL: markerRoot)
        _ = try await markerRepository.importSyntheticTranscript(fixtureData())
        let markerBase = try await markerRepository.load(
            sessionId: "session-fixture-001",
            revisionId: nil
        )
        let protected = try [
            digest(rawURL(markerRoot)),
            digest(modelURL(markerRoot)),
            digest(revisionURL(markerRoot, markerBase.revision.id)),
            digest(pointerURL(markerRoot))
        ]
        var removedMarker = edited(
            markerBase,
            revisionId: "revision-without-marker",
            savedAt: "2026-09-09T10:30:00Z"
        )
        removedMarker.turns.removeAll { $0.id == "t-marker" }
        XCTAssertNoThrow(try TranscriptValidator().validate(removedMarker))
        let markerError = await repositoryError {
            try await markerRepository.commitRevision(removedMarker)
        }
        XCTAssertEqual(markerError?.code, .immutableEvidenceChanged)
        XCTAssertEqual(try [
            digest(rawURL(markerRoot)),
            digest(modelURL(markerRoot)),
            digest(revisionURL(markerRoot, markerBase.revision.id)),
            digest(pointerURL(markerRoot))
        ], protected)
        let activeAfterRejection = try await markerRepository.load(
            sessionId: markerBase.sessionId,
            revisionId: nil
        )
        XCTAssertEqual(activeAfterRejection.revision.id, markerBase.revision.id)

        let boundaryRoot = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: boundaryRoot) }
        var splitModel = try SyntheticTranscriptFixtureLoader.load(data: fixtureData())
        splitModel.sessionId = "session-boundary"
        splitModel.runId = "run-boundary"
        splitModel.revision.id = "revision-boundary-model"
        splitModel.revision.sourceRunId = splitModel.runId
        var second = splitModel.turns[0]
        splitModel.turns[0].id = "t1-first"
        splitModel.turns[0].endUs = splitModel.words[0].endUs
        splitModel.turns[0].wordIds = ["w1"]
        second.id = "t1-second"
        second.startUs = splitModel.words[1].startUs
        second.wordIds = ["w2"]
        splitModel.turns.insert(second, at: 1)
        let boundaryRepository = FileSessionRepository(rootURL: boundaryRoot)
        _ = try await boundaryRepository.importSyntheticTranscript(
            NormalizedTranscriptCodec.encode(splitModel)
        )
        let boundaryBase = try await boundaryRepository.load(
            sessionId: splitModel.sessionId,
            revisionId: nil
        )
        var merged = boundaryBase
        merged.turns[0].endUs = merged.turns[1].endUs
        merged.turns[0].wordIds = ["w1", "w2"]
        merged.turns.remove(at: 1)
        merged.revision.id = "revision-cross-model-merge"
        merged.revision.baseRevisionId = boundaryBase.revision.id
        merged.revision.humanEdited = true
        merged.revision.savedAt = "2026-09-09T10:31:00Z"
        XCTAssertNoThrow(try TranscriptValidator().validate(merged))
        let mergeError = await repositoryError {
            try await boundaryRepository.commitRevision(merged)
        }
        XCTAssertEqual(mergeError?.code, .immutableEvidenceChanged)
    }

    func testRecoveryOrdersDifferingOffsetsByInstant() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = FileSessionRepository(rootURL: root)
        _ = try await repository.importSyntheticTranscript(fixtureData())
        let base = try await repository.load(sessionId: "session-fixture-001", revisionId: nil)
        let lexicallyLaterButEarlierInstant = edited(
            base,
            revisionId: "revision-offset-earlier",
            savedAt: "2026-09-09T10:00:00+09:00"
        )
        try await repository.commitRevision(lexicallyLaterButEarlierInstant)
        let chronologicallyLater = edited(
            lexicallyLaterButEarlierInstant,
            revisionId: "revision-offset-later",
            savedAt: "2026-09-09T02:00:00Z"
        )
        try await repository.commitRevision(chronologicallyLater)
        try FileManager.default.removeItem(at: pointerURL(root))

        let recovered = try await FileSessionRepository(rootURL: root)
            .loadWithRecovery(sessionId: base.sessionId)
        XCTAssertEqual(recovered.document.revision.id, chronologicallyLater.revision.id)
        XCTAssertEqual(recovered.recoveryNotice?.reason, .activePointerMissing)
    }

    func testSyntheticModelRevisionMustBeUneditedAndRooted() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = FileSessionRepository(rootURL: root)
        var humanEdited = try SyntheticTranscriptFixtureLoader.load(data: fixtureData())
        humanEdited.revision.humanEdited = true
        let humanEditedError = await repositoryError {
            _ = try await repository.importSyntheticTranscript(
                NormalizedTranscriptCodec.encode(humanEdited)
            )
        }
        XCTAssertEqual(humanEditedError?.code, .invalidSyntheticImport)

        var based = try SyntheticTranscriptFixtureLoader.load(data: fixtureData())
        based.revision.baseRevisionId = "another-revision"
        let basedError = await repositoryError {
            _ = try await repository.importSyntheticTranscript(NormalizedTranscriptCodec.encode(based))
        }
        XCTAssertEqual(basedError?.code, .invalidSyntheticImport)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Sessions").path))
    }

    func testRepeatImportIsIdempotentWithoutResettingEditsAndConflictThrows() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try fixtureData()
        let repository = FileSessionRepository(rootURL: root)
        _ = try await repository.importSyntheticTranscript(source)
        let base = try await repository.load(sessionId: "session-fixture-001", revisionId: nil)
        let next = edited(base, revisionId: "revision-kept", savedAt: "2026-09-09T07:00:00Z")
        try await repository.commitRevision(next)
        let repeated = try await repository.importSyntheticTranscript(source)
        XCTAssertFalse(repeated.installedNewData)
        XCTAssertEqual(repeated.activeRevisionId, next.revision.id)
        let activeAfterRepeat = try await repository.load(sessionId: base.sessionId, revisionId: nil)
        XCTAssertEqual(activeAfterRepeat.speakers[0].displayName, "검수자 A")

        var conflicting = try JSONSerialization.jsonObject(with: source) as! [String: Any]
        var speakers = conflicting["speakers"] as! [[String: Any]]
        speakers[0]["displayName"] = "same identity, different source"
        conflicting["speakers"] = speakers
        let conflictingData = try JSONSerialization.data(withJSONObject: conflicting, options: [.sortedKeys])
        let importConflict = await repositoryError {
            _ = try await repository.importSyntheticTranscript(conflictingData)
        }
        XCTAssertEqual(importConflict?.code, .identityConflict)
    }

    func testSeparateRunsWithIdenticalProviderLabelsRemainIndependent() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = FileSessionRepository(rootURL: root)
        let source = try fixtureData()
        _ = try await repository.importSyntheticTranscript(source)
        let base = try await repository.load(sessionId: "session-fixture-001", revisionId: nil)
        let editedRunOne = edited(
            base,
            revisionId: "revision-run-one-edit",
            savedAt: "2026-09-09T08:00:00Z",
            displayName: "Run one name"
        )
        try await repository.commitRevision(editedRunOne)

        var runTwo = try SyntheticTranscriptFixtureLoader.load(data: source)
        runTwo.runId = "run-fixture-002"
        runTwo.revision.id = "revision-run-two-model"
        runTwo.revision.sourceRunId = runTwo.runId
        runTwo.revision.savedAt = "2026-09-09T09:00:00Z"
        let runTwoData = try NormalizedTranscriptCodec.encode(runTwo)
        let imported = try await repository.importSyntheticTranscript(runTwoData)

        XCTAssertEqual(imported.activeRevisionId, editedRunOne.revision.id)
        let modelOne = try await repository.loadModel(
            sessionId: base.sessionId,
            runId: base.runId
        )
        let modelTwo = try await repository.loadModel(
            sessionId: base.sessionId,
            runId: runTwo.runId
        )
        XCTAssertEqual(modelOne.speakers.map(\.providerId), modelTwo.speakers.map(\.providerId))
        XCTAssertEqual(modelOne.speakers[0].displayName, "화자 A")
        XCTAssertEqual(modelTwo.speakers[0].displayName, "화자 A")
        let activeRunOne = try await repository.load(sessionId: base.sessionId, revisionId: nil)
        XCTAssertEqual(activeRunOne.speakers[0].displayName, "Run one name")
        XCTAssertEqual(try Data(contentsOf: rawURL(root, runId: runTwo.runId)), runTwoData)
    }

    func testImportingDifferentRunRecoversExistingSessionInsteadOfReinitializing() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = FileSessionRepository(rootURL: root)
        let source = try fixtureData()
        _ = try await repository.importSyntheticTranscript(source)
        let base = try await repository.load(sessionId: "session-fixture-001", revisionId: nil)
        let runOneEdit = edited(
            base,
            revisionId: "revision-run-one-newer",
            savedAt: "2026-09-09T12:00:00Z",
            displayName: "Recovered Run one"
        )
        try await repository.commitRevision(runOneEdit)
        try FileManager.default.removeItem(at: pointerURL(root))

        var runTwo = try SyntheticTranscriptFixtureLoader.load(data: source)
        runTwo.runId = "run-fixture-older"
        runTwo.revision.id = "revision-run-two-older"
        runTwo.revision.sourceRunId = runTwo.runId
        runTwo.revision.savedAt = "2026-09-09T01:00:00Z"
        let result = try await repository.importSyntheticTranscript(
            NormalizedTranscriptCodec.encode(runTwo)
        )

        XCTAssertEqual(result.activeRevisionId, runOneEdit.revision.id)
        let active = try await repository.load(sessionId: base.sessionId, revisionId: nil)
        XCTAssertEqual(active.runId, base.runId)
        XCTAssertEqual(active.speakers[0].displayName, "Recovered Run one")
        let notices = await repository.recoveryNotices()
        XCTAssertEqual(notices.count, 1)
        XCTAssertEqual(notices[0].reason, .activePointerMissing)
        XCTAssertEqual(notices[0].recoveredRevisionId, runOneEdit.revision.id)
    }

    func testTurnOrderAndMarkerPositionAreImmutableWhileSubdivisionCanBeUndone() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = FileSessionRepository(rootURL: root)
        _ = try await repository.importSyntheticTranscript(fixtureData())
        let base = try await repository.load(sessionId: "session-fixture-001", revisionId: nil)
        let activeHash = try digest(revisionURL(root, base.revision.id))
        let pointerHash = try digest(pointerURL(root))

        var movedMarker = base
        let marker = movedMarker.turns.remove(at: 1)
        movedMarker.turns.insert(marker, at: 0)
        movedMarker.revision.id = "revision-marker-reordered"
        movedMarker.revision.baseRevisionId = base.revision.id
        movedMarker.revision.humanEdited = true
        movedMarker.revision.savedAt = "2026-09-09T13:00:00Z"
        XCTAssertNoThrow(try TranscriptValidator().validate(movedMarker))
        let markerError = await repositoryError {
            try await repository.commitRevision(movedMarker)
        }
        XCTAssertEqual(markerError?.code, .immutableEvidenceChanged)

        var swappedSpeech = base
        swappedSpeech.turns.swapAt(0, 2)
        swappedSpeech.revision.id = "revision-speech-reordered"
        swappedSpeech.revision.baseRevisionId = base.revision.id
        swappedSpeech.revision.humanEdited = true
        swappedSpeech.revision.savedAt = "2026-09-09T13:01:00Z"
        XCTAssertNoThrow(try TranscriptValidator().validate(swappedSpeech))
        let swapError = await repositoryError {
            try await repository.commitRevision(swappedSpeech)
        }
        XCTAssertEqual(swapError?.code, .immutableEvidenceChanged)
        XCTAssertEqual(try digest(revisionURL(root, base.revision.id)), activeHash)
        XCTAssertEqual(try digest(pointerURL(root)), pointerHash)

        var subdivision = base
        var secondHalf = subdivision.turns[0]
        subdivision.turns[0].id = "t1-user-first"
        subdivision.turns[0].endUs = subdivision.words[0].endUs
        subdivision.turns[0].wordIds = ["w1"]
        secondHalf.id = "t1-user-second"
        secondHalf.startUs = subdivision.words[1].startUs
        secondHalf.wordIds = ["w2"]
        subdivision.turns.insert(secondHalf, at: 1)
        subdivision.revision.id = "revision-subdivision"
        subdivision.revision.baseRevisionId = base.revision.id
        subdivision.revision.humanEdited = true
        subdivision.revision.savedAt = "2026-09-09T13:02:00Z"
        try await repository.commitRevision(subdivision)

        var restored = base
        restored.revision.id = "revision-subdivision-undone"
        restored.revision.baseRevisionId = subdivision.revision.id
        restored.revision.humanEdited = true
        restored.revision.savedAt = "2026-09-09T13:03:00Z"
        try await repository.commitRevision(restored)
        let activeRestored = try await repository.load(sessionId: base.sessionId, revisionId: nil)
        XCTAssertEqual(activeRestored.revision.id, restored.revision.id)
        XCTAssertEqual(activeRestored.turns.map(\.id), base.turns.map(\.id))
    }

    func testStoredModelRejectsEditedOrBasedRevisionMetadata() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = FileSessionRepository(rootURL: root)
        _ = try await repository.importSyntheticTranscript(fixtureData())
        let original = try await repository.loadModel(
            sessionId: "session-fixture-001",
            runId: "run-fixture-001"
        )

        var humanEdited = original
        humanEdited.revision.humanEdited = true
        try NormalizedTranscriptCodec.encode(humanEdited).write(to: modelURL(root))
        let humanEditedError = await repositoryError {
            _ = try await repository.loadModel(
                sessionId: original.sessionId,
                runId: original.runId
            )
        }
        XCTAssertEqual(humanEditedError?.code, .invalidRevision)

        var based = original
        based.revision.baseRevisionId = "revision-unexpected-base"
        try NormalizedTranscriptCodec.encode(based).write(to: modelURL(root))
        let basedError = await repositoryError {
            _ = try await repository.loadModel(
                sessionId: original.sessionId,
                runId: original.runId
            )
        }
        XCTAssertEqual(basedError?.code, .invalidRevision)
    }

    func testImmutableEvidenceChangeAndExplicitMissingRevisionNeverFallback() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = FileSessionRepository(rootURL: root)
        _ = try await repository.importSyntheticTranscript(fixtureData())
        let base = try await repository.load(sessionId: "session-fixture-001", revisionId: nil)
        var changed = edited(base, revisionId: "revision-bad-evidence", savedAt: "2026-09-09T10:00:00Z")
        changed.words[0].text = "changed original"
        let immutableError = await repositoryError {
            try await repository.commitRevision(changed)
        }
        XCTAssertEqual(immutableError?.code, .immutableEvidenceChanged)

        let missing = await repositoryError {
            _ = try await repository.load(sessionId: base.sessionId, revisionId: "missing-revision")
        }
        XCTAssertEqual(missing?.code, .revisionNotFound)
        XCTAssertFalse(missing?.description.contains(root.path) ?? true)
        let active = try await repository.load(sessionId: base.sessionId, revisionId: nil)
        XCTAssertEqual(active.revision.id, base.revision.id)
    }

    func testNoValidRevisionReportsSanitizedActionableError() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let revisions = sessionURL(root, "empty-session")
            .appendingPathComponent("revisions", isDirectory: true)
        try FileManager.default.createDirectory(at: revisions, withIntermediateDirectories: true)
        try Data("private transcript content".utf8)
            .write(to: revisions.appendingPathComponent("broken.json"))
        let repository = FileSessionRepository(rootURL: root)

        let error = await repositoryError {
            _ = try await repository.loadWithRecovery(sessionId: "empty-session")
        }

        XCTAssertEqual(error?.code, .noValidRevision)
        XCTAssertFalse(error?.description.contains(root.path) ?? true)
        XCTAssertFalse(error?.description.contains("private transcript content") ?? true)
    }

    func testNonexistentSessionBelowEscapingSessionsSymlinkIsRejectedBeforeCreation() async throws {
        let root = try temporaryRoot()
        let outside = try temporaryRoot()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("Sessions"),
            withDestinationURL: outside
        )
        let repository = FileSessionRepository(rootURL: root)

        let error = await repositoryError {
            _ = try await repository.importSyntheticTranscript(self.fixtureData())
        }

        XCTAssertEqual(error?.code, .unsafePath)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: outside.appendingPathComponent("session-fixture-001").path
            )
        )
    }
}

import Foundation
import XCTest
@testable import DamaCore

final class TranscriptExportingTests: XCTestCase {
    private enum TestFault: Error { case injected }

    private actor Gate {
        private var entered = false
        private var enteredContinuation: CheckedContinuation<Void, Never>?
        private var releaseContinuation: CheckedContinuation<Void, Never>?
        private var released = false

        func wait() async {
            entered = true
            enteredContinuation?.resume()
            enteredContinuation = nil
            if released { return }
            await withCheckedContinuation { releaseContinuation = $0 }
        }

        func waitUntilEntered() async {
            if entered { return }
            await withCheckedContinuation { enteredContinuation = $0 }
        }

        func release() {
            released = true
            releaseContinuation?.resume()
            releaseContinuation = nil
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

    private func temporaryRoot(label: String = "Export") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Dama\(label)Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func selection(
        _ version: TranscriptExportVersion,
        document: TranscriptDocument
    ) -> TranscriptExportSelection {
        TranscriptExportSelection(
            version: version,
            sessionId: document.sessionId,
            runId: document.runId,
            revisionId: document.revision.id
        )
    }

    func testAutomaticAndCurrentJSONAndTextExportsRemainIndependent() async throws {
        let root = try temporaryRoot(label: "FourFormats")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = FileSessionRepository(rootURL: root.appendingPathComponent("storage"))
        _ = try await repository.importSyntheticTranscript(fixtureData())
        let session = try await TranscriptEditingSession.open(
            repository: repository,
            sessionId: "session-fixture-001"
        )
        try await session.apply(.renameSpeaker(speakerId: "speaker-a", displayName: "김담아"))
        try await session.apply(.replaceWordText(wordId: "w1", editedText: "저희는"))
        try await session.apply(.acknowledgeIssue(issueId: "i2"))
        let current = await session.state().committed
        let automatic = try await repository.loadModel(
            sessionId: current.sessionId,
            runId: current.runId
        )
        let cases: [(TranscriptExportVersion, TranscriptExportFormat, TranscriptDocument, String)] = [
            (.automatic, .json, automatic, "automatic.json"),
            (.automatic, .text, automatic, "automatic.txt"),
            (.current, .json, current, "current.json"),
            (.current, .text, current, "current.txt")
        ]

        for (version, format, document, filename) in cases {
            let selected = selection(version, document: document)
            let result = try await session.export(
                selection: selected,
                format: format,
                to: root.appendingPathComponent(filename)
            )
            XCTAssertEqual(result.selection, selected)
            XCTAssertEqual(result.format, format)
        }

        let automaticJSON = try NormalizedTranscriptCodec.decode(
            Data(contentsOf: root.appendingPathComponent("automatic.json"))
        )
        let currentJSON = try NormalizedTranscriptCodec.decode(
            Data(contentsOf: root.appendingPathComponent("current.json"))
        )
        XCTAssertEqual(automaticJSON.revision.id, automatic.revision.id)
        XCTAssertFalse(automaticJSON.revision.humanEdited)
        XCTAssertNil(automaticJSON.words[0].editedText)
        XCTAssertEqual(automaticJSON.speakers[0].displayName, "화자 A")
        XCTAssertEqual(currentJSON.revision.id, current.revision.id)
        XCTAssertTrue(currentJSON.revision.humanEdited)
        XCTAssertEqual(currentJSON.words[0].editedText, "저희는")
        XCTAssertEqual(currentJSON.words[0].text, "저희가")
        XCTAssertEqual(currentJSON.speakers[0].displayName, "김담아")
        XCTAssertEqual(currentJSON.reviewIssues[1].status, .acknowledged)
        XCTAssertEqual(currentJSON.provenance.engine, automatic.provenance.engine)
        XCTAssertTrue(currentJSON.provenance.isSynthetic)
        XCTAssertEqual(currentJSON.diarization[3].confidence?["SPEAKER_01"], 65)
        XCTAssertEqual(currentJSON.diarization[3].confidence?["SPEAKER_02"], 60)
        XCTAssertNil(currentJSON.diarization[4].confidence)
        XCTAssertNil(currentJSON.words[4].speakerId)

        let automaticText = try String(
            contentsOf: root.appendingPathComponent("automatic.txt"),
            encoding: .utf8
        )
        let currentText = try String(
            contentsOf: root.appendingPathComponent("current.txt"),
            encoding: .utf8
        )
        XCTAssertTrue(automaticText.contains("# 선택 버전: 자동본"))
        XCTAssertTrue(currentText.contains("# 선택 버전: 현재 수정본"))
        XCTAssertTrue(automaticText.contains("# 데이터: 합성 테스트 데이터"))
        XCTAssertTrue(automaticText.contains("[00:00:00.850–00:00:00.990] 화자 B\n[음성 감지 / 전사 누락 의심]"))
        XCTAssertTrue(automaticText.contains("[00:00:02.100–00:00:02.300] 화자 미확정\n네"))
        XCTAssertTrue(automaticText.contains("불확실성: overlapping_speech (open)"))
        XCTAssertTrue(currentText.contains("불확실성: overlapping_speech (acknowledged)"))
        XCTAssertTrue(currentText.contains("불확실성: 겹침 감지"))
        XCTAssertTrue(currentText.contains("불확실성: 화자 미확정"))
        XCTAssertTrue(currentText.contains("근거 구간 d2 [00:00:00.850–00:00:00.990] 일반 — 공급자 화자 점수: SPEAKER_00=10.0, SPEAKER_01=74.0"))
        XCTAssertTrue(currentText.contains("근거 구간 d4 [00:00:02.050–00:00:02.400] 일반 — 공급자 화자 점수: SPEAKER_01=65.0, SPEAKER_02=60.0"))
        XCTAssertTrue(currentText.contains("근거 구간 d5 [00:00:02.100–00:00:02.400] 일반 — 공급자 화자 점수: 미제공"))
        XCTAssertTrue(currentText.contains("시간 재정렬 안 됨"))
        XCTAssertFalse(automaticText.contains("시간 재정렬 안 됨"))
        XCTAssertTrue(currentText.contains("# 주의: 공급자 화자 점수와 시간 정렬 점수는 정답 확률이 아닙니다."))
        XCTAssertFalse(currentText.contains("%"))
        XCTAssertFalse(currentText.contains("65%"))
        XCTAssertFalse(currentText.contains("60%"))
        XCTAssertTrue(automaticText.contains("저희가 내년에"))
        XCTAssertTrue(currentText.contains("저희는 내년에"))
        XCTAssertFalse(automaticText.contains("저희는"))

        let markerRange = automaticText.range(of: "[음성 감지 / 전사 누락 의심]")!
        let firstARange = automaticText.range(of: "저희가 내년에")!
        let secondARange = automaticText.range(of: "양산을 시작합니다.")!
        XCTAssertLessThan(firstARange.lowerBound, markerRange.lowerBound)
        XCTAssertLessThan(markerRange.lowerBound, secondARange.lowerBound)
    }

    func testTextPreservesUnknownTimeRepeatedWordsAndDoesNotMutateTimes() throws {
        var document = try fixture()
        document.words[0].text = "네"
        document.words[1].text = "네"
        document.words[0].startUs = nil
        document.words[0].endUs = nil
        document.words[0].timingOrigin = .none
        document.words[1].startUs = nil
        document.words[1].endUs = nil
        document.words[1].timingOrigin = .none
        document.turns[0].startUs = nil
        document.turns[0].endUs = nil
        try TranscriptValidator().validate(document)
        let before = document.words.map { ($0.startUs, $0.endUs) }

        let data = try TranscriptExporter().data(
            for: document,
            selection: selection(.automatic, document: document),
            format: .text
        )
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("[시간 미확인] 화자 A\n네 네"))
        for (index, word) in document.words.enumerated() {
            XCTAssertEqual(word.startUs, before[index].0)
            XCTAssertEqual(word.endUs, before[index].1)
        }
    }

    func testStaleOrMismatchedDisplayedVersionIsRejectedBeforeWriting() async throws {
        let root = try temporaryRoot(label: "Selection")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = FileSessionRepository(rootURL: root.appendingPathComponent("storage"))
        _ = try await repository.importSyntheticTranscript(fixtureData())
        let session = try await TranscriptEditingSession.open(
            repository: repository,
            sessionId: "session-fixture-001"
        )
        let state = await session.state()
        let destination = root.appendingPathComponent("must-not-exist.txt")
        let stale = TranscriptExportSelection(
            version: .current,
            sessionId: state.committed.sessionId,
            runId: state.committed.runId,
            revisionId: "revision-stale"
        )
        do {
            _ = try await session.export(selection: stale, format: .text, to: destination)
            XCTFail("Expected stale selection rejection")
        } catch let error as TranscriptExportError {
            XCTAssertEqual(error.code, .invalidSelection)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testFailedDirtySaveBlocksBothVersionsUntilRetryCompletes() async throws {
        let root = try temporaryRoot(label: "DirtyExport")
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = root.appendingPathComponent("storage")
        let marker = root.appendingPathComponent("fault-used")
        let setup = FileSessionRepository(rootURL: storage)
        _ = try await setup.importSyntheticTranscript(fixtureData())
        let repository = FileSessionRepository(rootURL: storage) { stage in
            if stage == .afterFinalRevisionInstallation,
               !FileManager.default.fileExists(atPath: marker.path) {
                try Data().write(to: marker)
                throw TestFault.injected
            }
        }
        let session = try await TranscriptEditingSession.open(
            repository: repository,
            sessionId: "session-fixture-001"
        )
        do {
            try await session.apply(.renameSpeaker(speakerId: "speaker-a", displayName: "재시도 후"))
            XCTFail("Expected injected save failure")
        } catch TestFault.injected {}
        let failed = await session.state()
        XCTAssertTrue(failed.isDirty)
        XCTAssertNotNil(failed.failure)
        XCTAssertFalse(failed.canExport)
        let model = try await repository.loadModel(
            sessionId: failed.committed.sessionId,
            runId: failed.committed.runId
        )
        let blocked: [(TranscriptExportSelection, TranscriptExportFormat, URL)] = [
            (selection(.automatic, document: model), .json, root.appendingPathComponent("blocked-model.json")),
            (selection(.current, document: failed.committed), .text, root.appendingPathComponent("blocked-current.txt"))
        ]
        for (selected, format, destination) in blocked {
            do {
                _ = try await session.export(selection: selected, format: format, to: destination)
                XCTFail("Expected dirty export rejection")
            } catch let error as TranscriptEditingError {
                XCTAssertEqual(error.code, .pendingSaveFailure)
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        }

        try await session.retry()
        let saved = await session.state()
        XCTAssertFalse(saved.isDirty)
        XCTAssertNil(saved.failure)
        XCTAssertTrue(saved.canExport)
        _ = try await session.export(
            selection: selection(.automatic, document: model),
            format: .json,
            to: root.appendingPathComponent("model.json")
        )
        _ = try await session.export(
            selection: selection(.current, document: saved.committed),
            format: .text,
            to: root.appendingPathComponent("current.txt")
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("model.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("current.txt").path))
    }

    func testRepositoryDestinationsAndSymlinkAliasesAreRejectedBeforeWrite() async throws {
        let root = try temporaryRoot(label: "Destination")
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = root.appendingPathComponent("storage", isDirectory: true)
        let repository = FileSessionRepository(rootURL: storage)
        _ = try await repository.importSyntheticTranscript(fixtureData())
        let session = try await TranscriptEditingSession.open(
            repository: repository,
            sessionId: "session-fixture-001"
        )
        let state = await session.state()
        let selected = selection(.current, document: state.committed)
        let direct = storage.appendingPathComponent("Sessions/forbidden.txt")

        do {
            _ = try await session.export(selection: selected, format: .text, to: direct)
            XCTFail("Expected repository destination rejection")
        } catch let error as TranscriptExportError {
            XCTAssertEqual(error.code, .unsafeDestination)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: direct.path))

        let alias = root.appendingPathComponent("storage-alias", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: storage)
        let indirect = alias.appendingPathComponent("Sessions/aliased-forbidden.txt")
        do {
            _ = try await session.export(selection: selected, format: .json, to: indirect)
            XCTFail("Expected symlink repository destination rejection")
        } catch let error as TranscriptExportError {
            XCTAssertEqual(error.code, .unsafeDestination)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: indirect.path))

        let repositoryModel = storage.appendingPathComponent(
            "Sessions/session-fixture-001/runs/run-fixture-001/normalized/model.json"
        )
        let finalAlias = root.appendingPathComponent("final-alias.json")
        try FileManager.default.createSymbolicLink(
            at: finalAlias,
            withDestinationURL: repositoryModel
        )
        do {
            _ = try await session.export(selection: selected, format: .json, to: finalAlias)
            XCTFail("Expected final symlink destination rejection")
        } catch let error as TranscriptExportError {
            XCTAssertEqual(error.code, .unsafeDestination)
        }
        XCTAssertEqual(
            try Data(contentsOf: repositoryModel),
            try NormalizedTranscriptCodec.encode(try fixture())
        )
    }

    func testAtomicWriteFailuresPreserveExistingDestinationAndErrorsAreSanitized() throws {
        let root = try temporaryRoot(label: "Atomic")
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("existing.txt")
        let prior = Data("prior destination".utf8)
        try prior.write(to: destination)
        let successfulReplacement = Data("successful replacement".utf8)
        try TranscriptExporter().write(successfulReplacement, to: destination)
        XCTAssertEqual(try Data(contentsOf: destination), successfulReplacement)
        try prior.write(to: destination)
        let exporter = TranscriptExporter { stage in
            if stage == .beforeDestinationReplacement { throw TestFault.injected }
        }
        do {
            try exporter.write(Data("replacement".utf8), to: destination)
            XCTFail("Expected injected replacement failure")
        } catch let error as TranscriptExportError {
            XCTAssertEqual(error.code, .writeFailure)
            XCTAssertFalse(error.description.contains(root.path))
            XCTAssertFalse(error.description.contains("replacement"))
        }
        XCTAssertEqual(try Data(contentsOf: destination), prior)

        let directoryDestination = root.appendingPathComponent("real-failure", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryDestination, withIntermediateDirectories: false)
        let sentinel = directoryDestination.appendingPathComponent("prior.txt")
        try prior.write(to: sentinel)
        XCTAssertThrowsError(
            try TranscriptExporter().write(Data("replacement".utf8), to: directoryDestination)
        ) { error in
            XCTAssertEqual((error as? TranscriptExportError)?.code, .writeFailure)
        }
        XCTAssertEqual(try Data(contentsOf: sentinel), prior)
    }

    func testOutputDoesNotIncludeActualStorageOrDestinationButKeepsTranscriptWords() async throws {
        let root = try temporaryRoot(label: "DO_NOT_LEAK_STORAGE_PATH")
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = root.appendingPathComponent("internal-storage-DO_NOT_LEAK")
        let repository = FileSessionRepository(rootURL: storage)
        _ = try await repository.importSyntheticTranscript(fixtureData())
        let session = try await TranscriptEditingSession.open(
            repository: repository,
            sessionId: "session-fixture-001"
        )
        try await session.apply(
            .replaceWordText(wordId: "w1", editedText: "Authorization=사용자 발화")
        )
        let document = await session.state().committed
        let selected = selection(.current, document: document)
        for format in [TranscriptExportFormat.json, .text] {
            let destination = root.appendingPathComponent(
                "selected-destination-DO_NOT_LEAK.\(format.rawValue)"
            )
            _ = try await session.export(
                selection: selected,
                format: format,
                to: destination
            )
            let output = String(decoding: try Data(contentsOf: destination), as: UTF8.self)
            XCTAssertFalse(output.contains(root.path))
            XCTAssertFalse(output.contains(storage.path))
            XCTAssertFalse(output.contains(destination.path))
            XCTAssertTrue(output.contains("Authorization=사용자 발화"))
        }
    }

    func testExportAndSaveRejectEachOtherWhileSuspended() async throws {
        let root = try temporaryRoot(label: "Coordination")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = FileSessionRepository(rootURL: root.appendingPathComponent("storage"))
        _ = try await repository.importSyntheticTranscript(fixtureData())
        let committed = try await repository.load(sessionId: "session-fixture-001", revisionId: nil)
        let model = try await repository.loadModel(sessionId: committed.sessionId, runId: committed.runId)
        let exportGate = Gate()
        let exportSession = TranscriptEditingSession(
            repository: repository,
            committed: committed,
            model: model,
            beforeExport: { await exportGate.wait() },
            exportDestinationValidator: { url in
                try await repository.validateExportDestination(url)
            }
        )
        let selected = selection(.current, document: committed)
        let exportDestination = root.appendingPathComponent("coordinated.txt")
        let exportTask = Task {
            try await exportSession.export(
                selection: selected,
                format: .text,
                to: exportDestination
            )
        }
        await exportGate.waitUntilEntered()
        let exportingState = await exportSession.state()
        XCTAssertTrue(exportingState.isExporting)
        XCTAssertFalse(exportingState.isSaving)
        XCTAssertFalse(exportingState.canExport)
        do {
            try await exportSession.apply(
                .renameSpeaker(speakerId: "speaker-a", displayName: "경합 금지")
            )
            XCTFail("Expected edit rejection during export")
        } catch let error as TranscriptEditingError {
            XCTAssertEqual(error.code, .busy)
            XCTAssertEqual(error.context, "export")
        }
        await exportGate.release()
        _ = try await exportTask.value

        let saveGate = Gate()
        let saveSession = TranscriptEditingSession(
            repository: repository,
            committed: committed,
            model: model,
            beforeSave: { await saveGate.wait() },
            exportDestinationValidator: { url in
                try await repository.validateExportDestination(url)
            }
        )
        let saveTask = Task {
            try await saveSession.apply(
                .renameSpeaker(speakerId: "speaker-a", displayName: "저장 중")
            )
        }
        await saveGate.waitUntilEntered()
        let blockedDestination = root.appendingPathComponent("blocked.txt")
        do {
            _ = try await saveSession.export(
                selection: selected,
                format: .text,
                to: blockedDestination
            )
            XCTFail("Expected export rejection during save")
        } catch let error as TranscriptEditingError {
            XCTAssertEqual(error.code, .busy)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: blockedDestination.path))
        await saveGate.release()
        try await saveTask.value
    }
}

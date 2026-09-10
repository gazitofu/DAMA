import AVFoundation
import DamaAudio
import DamaCore
import Foundation
import Synchronization
import XCTest
@testable import DamaManaged

final class ManagedJourneyTests: XCTestCase {
    func testConversionInputSnapshotSurvivesCredentialResume() async throws {
        let root = try root(), record = try await recording(root)
        let fake = FakeTransport(final: try fixture())
        let processor = ManagedProcessor(root: root, transport: fake, sleep: { _ in })
        let notes = ConversionNotes(speakerCount: 3, context: "local context", reference: "local reference")
        let waiting = try await processor.begin(sessionID: record.id, confirmed: true, key: "", input: notes)
        XCTAssertEqual(waiting.input, notes)
        let resumed = try await ManagedProcessor(root: root, transport: fake, sleep: { _ in }).resume(waiting.id, key: "test-only")
        XCTAssertEqual(resumed.input, notes)
        XCTAssertNotNil(resumed.lastServerCheckAt)
        let body = await fake.lastSubmission
        let payload = try JSONSerialization.jsonObject(with: XCTUnwrap(body)) as! [String: Any]
        XCTAssertEqual(payload["numSpeakers"] as? Int, 3)
        XCTAssertNil(payload["context"]); XCTAssertNil(payload["reference"])
        XCTAssertFalse(String(decoding: try XCTUnwrap(body), as: UTF8.self).contains("local context"))
    }
    func testFolderToMockProcessingScriptEditAndMarkdownJourney() async throws {
        let base = try root(), root = base.appendingPathComponent("internal")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let speeches = base.appendingPathComponent("Speeches"), scripts = base.appendingPathComponent("Scripts")
        try FileManager.default.createDirectory(at: speeches, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
        _ = try await recording(root)
        try FileManager.default.copyItem(at: root.appendingPathComponent("synthetic.wav"), to: speeches.appendingPathComponent("example.wav"))
        let storage = FolderLibraryStore(root: root)
        let entries = try await storage.speeches(in: speeches)
        let speech = try XCTUnwrap(entries.first)
        let input = ConversionNotes(context: "before conversion", reference: "special term")
        let fake = FakeTransport(final: try fixture())
        let run = try await ManagedProcessor(root: root, transport: fake, sleep: { _ in }).begin(sessionID: speech.id, confirmed: true, key: "test-only", input: input)
        let document = try await FileSessionRepository(rootURL: root).load(sessionId: speech.id, revisionId: nil)
        let file = try await storage.createScript(document, speech: speech, input: try XCTUnwrap(run.input), in: scripts)
        var edited = file.script
        try edited.renameTitle("edited title")
        try edited.rename(document.turns[0].id, name: "민수", scope: .all)
        let saved = try await storage.saveScript(edited, to: file.url, expectedHash: file.hash)
        // A completed-run recovery must not replace existing user edits or metadata.
        let again = try await storage.createScript(document, speech: speech, input: ConversionNotes(context: "later note"), in: scripts)
        XCTAssertEqual(again.hash, saved.hash)
        XCTAssertEqual(again.script.input, input)
        try await storage.exportMarkdown(again, to: scripts.appendingPathComponent("export.md"))
        let markdown = try String(contentsOf: scripts.appendingPathComponent("export.md"), encoding: .utf8)
        XCTAssertTrue(markdown.contains("edited title")); XCTAssertTrue(markdown.contains("before conversion"))
        let submitted = await fake.lastSubmission
        let payload = try JSONSerialization.jsonObject(with: XCTUnwrap(submitted)) as! [String: Any]
        XCTAssertNil(payload["numSpeakers"])
    }
    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }
        return url
    }
    private func fixture() throws -> Data {
        var path = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { path.deleteLastPathComponent() }
        return try Data(contentsOf: path.appendingPathComponent("fixtures/pyannote-job-succeeded.synthetic.json"))
    }
    private func recording(_ root: URL) async throws -> AudioManifest {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000)!
        pcm.frameLength = 48_000
        pcm.floatChannelData![0].initialize(repeating: 0, count: 48_000)
        let path = root.appendingPathComponent("synthetic.wav")
        let file = try AVAudioFile(forWriting: path, settings: format.settings)
        try file.write(from: pcm)
        file.close()
        return try await AudioLibrary(root: root).importFile(path)
    }

    func testNormalizerPreservesWordsMarkerConfidenceAndInvalidTime() throws {
        let bytes = try fixture()
        func normalize(_ data: Data) throws -> TranscriptDocument {
            try ManagedNormalizer.normalize(data, sessionID: "session", runID: "run", durationUs: 3_000_000,
                audioSHA256: String(repeating: "a", count: 64), synthetic: true, createdAt: "2026-09-09T00:00:00Z")
        }
        let model = try normalize(bytes)
        XCTAssertEqual(model.words.map(\.text), ["저희가", "내년에", "양산을", "시작합니다."])
        XCTAssertEqual(model.turns.map(\.kind), [.speech, .missingSpeech, .speech])
        XCTAssertEqual(model.turns[1].startUs, 850_000)
        XCTAssertEqual(model.turns[1].endUs, 990_000)
        XCTAssertEqual(model.diarization[0].confidence?["SPEAKER_00"], 94)
        XCTAssertNil(model.diarization[2].confidence)
        XCTAssertTrue(model.words.allSatisfy { $0.alignmentScore == nil && !$0.overlap })
        var object = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
        var output = object["output"] as! [String: Any]
        var words = output["wordLevelTranscription"] as! [[String: Any]]
        words[0]["start"] = -1
        words[1]["speaker"] = "not-known"
        words[1]["text"] = "네"
        words[2]["text"] = "네"
        output["wordLevelTranscription"] = words
        object["output"] = output
        let invalid = try normalize(JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(invalid.words[0].startUs)
        XCTAssertNil(invalid.words[0].endUs)
        XCTAssertNil(invalid.words[1].speakerId)
        XCTAssertEqual(invalid.words.filter { $0.text == "네" }.count, 2)
        XCTAssertTrue(invalid.reviewIssues.contains { $0.kind == .invalid_timestamp })
        output["wordLevelTranscription"] = []
        object["output"] = output
        XCTAssertThrowsError(try normalize(JSONSerialization.data(withJSONObject: object)))
    }

    func testMockTransferToImmutableReviewAndExport() async throws {
        let root = try root()
        let record = try await recording(root)
        let fake = FakeTransport(final: try fixture())
        let processor = ManagedProcessor(root: root, transport: fake, sleep: { _ in })
        do { _ = try await processor.begin(sessionID: record.id, confirmed: false, key: "test-only"); XCTFail("consent") } catch {}
        let before = await fake.calls
        XCTAssertEqual(before.count, 0)
        let run = try await processor.begin(sessionID: record.id, confirmed: true, key: "test-only")
        XCTAssertEqual(run.stage, "readyForReview")
        let calls = await fake.calls
        XCTAssertEqual(calls, ["POST /v1/media/input", "PUT", "POST /v1/diarize", "GET /v1/jobs/11111111-1111-4111-8111-111111111111"])
        let repository = FileSessionRepository(rootURL: root)
        let loaded = try await repository.load(sessionId: record.id, revisionId: nil)
        XCTAssertEqual(loaded.turns.count, 3)
        let editing = try await TranscriptEditingSession.open(repository: repository, sessionId: record.id)
        let state = await editing.state()
        XCTAssertTrue(state.canExport)
        let reloaded = try await ManagedProcessor(root: root, transport: fake).runs(recover: true)
        XCTAssertEqual(reloaded.first?.jobID, run.jobID)
        let rawURL = root.appendingPathComponent("Sessions/\(record.id)/runs/\(run.id)/raw/pyannote-response.json")
        XCTAssertEqual(try Data(contentsOf: rawURL), try fixture())
        let storedState = try String(contentsOf: rawURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("state.json"), encoding: .utf8)
        XCTAssertFalse(storedState.contains("test-only"))
        XCTAssertFalse(storedState.contains("signed"))
        var edited = loaded
        edited.speakers[0].displayName = "검수 이름"
        edited.revision.id = "edited-revision"
        edited.revision.baseRevisionId = loaded.revision.id
        edited.revision.humanEdited = true
        edited.revision.savedAt = "2026-09-09T23:59:00Z"
        try await repository.commitRevision(edited)
        let second = try ManagedNormalizer.normalize(fixture(), sessionID: record.id, runID: UUID().uuidString,
            durationUs: 3_000_000, audioSHA256: loaded.provenance.sourceAudioSHA256!, synthetic: true, createdAt: run.createdAt)
        try await repository.importManagedTranscript(second, rawData: fixture())
        let preserved = try await repository.load(sessionId: record.id, revisionId: nil)
        XCTAssertEqual(preserved.revision.id, "edited-revision")
        XCTAssertEqual(preserved.speakers[0].displayName, "검수 이름")
        XCTAssertNotEqual(second.speakers[0].id, loaded.speakers[0].id)
        XCTAssertEqual(try Data(contentsOf: rawURL), try fixture())
    }

    func testOverlapBoundaryAndDuplicateIntervalsAreDifferentEvidence() throws {
        var json = try JSONSerialization.jsonObject(with: fixture()) as! [String: Any]
        var output = json["output"] as! [String: Any]
        var regular = output["diarization"] as! [[String: Any]]
        let a = regular[0]
        regular.append(a)
        output["diarization"] = regular
        json["output"] = output
        func model() throws -> TranscriptDocument {
            try ManagedNormalizer.normalize(JSONSerialization.data(withJSONObject: json), sessionID: "session", runID: "run",
                durationUs: 3_000_000, audioSHA256: String(repeating: "a", count: 64), synthetic: true, createdAt: "2026-09-09T00:00:00Z")
        }
        XCTAssertFalse(try model().words[0].overlap)
        regular[1]["start"] = 0.2
        regular[1]["end"] = 0.6
        output["diarization"] = regular
        json["output"] = output
        let simultaneous = try model()
        XCTAssertTrue(simultaneous.words[0].overlap)
        XCTAssertEqual(simultaneous.words[0].speakerId, simultaneous.words[0].modelSpeakerId)
        regular[0]["end"] = 0.2
        regular[3]["end"] = 0.2
        output["diarization"] = regular
        json["output"] = output
        let boundary = try model()
        XCTAssertFalse(boundary.words[0].overlap)
        XCTAssertTrue(boundary.reviewIssues.contains { $0.kind == .boundary_conflict && $0.wordIds.contains("w0") })
    }

    func testConsentSurvivesMissingKeyAndTimeoutPreservesUncertainState() async throws {
        let root = try root()
        let record = try await recording(root)
        let fake = FakeTransport(final: try fixture(), submitStatus: -1)
        let processor = ManagedProcessor(root: root, transport: fake, sleep: { _ in })
        let waiting = try await processor.begin(sessionID: record.id, confirmed: true, key: "")
        XCTAssertEqual(waiting.stage, "waitingForCredentials")
        XCTAssertTrue(waiting.consent)
        let before = await fake.calls
        XCTAssertTrue(before.isEmpty)
        let uncertain = try await processor.resume(waiting.id, key: "test-only")
        XCTAssertEqual(uncertain.stage, "submissionUncertain")
        XCTAssertEqual(uncertain.id, waiting.id)
    }

    func testSubmissionUncertainNeverAutomaticallyResubmits() async throws {
        let root = try root()
        let record = try await recording(root)
        let fake = FakeTransport(final: try fixture(), submitStatus: 503)
        let processor = ManagedProcessor(root: root, transport: fake, sleep: { _ in })
        let run = try await processor.begin(sessionID: record.id, confirmed: true, key: "test-only")
        XCTAssertEqual(run.stage, "submissionUncertain")
        XCTAssertNotNil(run.attemptID)
        XCTAssertEqual(run.requestHash?.count, 64)
        let restarted = ManagedProcessor(root: root, transport: fake, sleep: { _ in })
        do { _ = try await restarted.resume(run.id, key: "test-only"); XCTFail("must not resubmit") } catch {}
        let submits = await fake.calls.filter { $0 == "POST /v1/diarize" }.count
        XCTAssertEqual(submits, 1)
        var crashed = run
        crashed.stage = "submitting"
        try JSONEncoder().encode(crashed).write(to: root.appendingPathComponent("Sessions/\(run.sessionID)/runs/\(run.id)/state.json"))
        let recovered = try await restarted.runs(recover: true)
        XCTAssertEqual(recovered[0].stage, "submissionUncertain")
    }

    func testHTTPFailuresAndLocalOnly() async throws {
        for (code, expected) in [(400,"failed"), (401,"waitingForCredentials"), (402,"waitingForBilling"), (429,"waitingForNetwork")] {
            let root = try root()
            let record = try await recording(root)
            let fake = FakeTransport(final: try fixture(), submitStatus: code)
            let processor = ManagedProcessor(root: root, transport: fake, sleep: { _ in })
            let run = try await processor.begin(sessionID: record.id, confirmed: true, key: "test-only")
            XCTAssertEqual(run.stage, expected)
            XCTAssertNil(run.jobID)
        }
        let root = try root()
        let record = try await recording(root)
        let fake = FakeTransport(final: try fixture())
        let processor = ManagedProcessor(root: root, transport: fake)
        try await processor.setLocalOnly(record.id)
        do { _ = try await processor.begin(sessionID: record.id, confirmed: true, key: "test-only"); XCTFail("never overrides consent") } catch {}
        let calls = await fake.calls
        XCTAssertTrue(calls.isEmpty)
    }

    func testGETRetryRetainsJobAndRetryAfter() async throws {
        let root = try root()
        let record = try await recording(root)
        let fake = FakeTransport(final: try fixture(), getFailureCount: 2)
        let processor = ManagedProcessor(root: root, transport: fake, sleep: { _ in })
        let run = try await processor.begin(sessionID: record.id, confirmed: true, key: "test-only")
        XCTAssertEqual(run.stage, "readyForReview")
        let gets = await fake.calls.filter { $0.hasPrefix("GET") }
        XCTAssertEqual(gets.count, 3)
        XCTAssertEqual(Set(gets).count, 1)
        XCTAssertEqual(PollDelay.seconds(retryAfter: "91", attempt: 0), 91)
        XCTAssertEqual(PollDelay.seconds(retryAfter: "Thu, 01 Jan 1970 00:01:00 GMT", attempt: 0, now: Date(timeIntervalSince1970: 0)), 60)
        XCTAssertEqual(PollDelay.seconds(retryAfter: nil, attempt: 0), 10)
    }

    func testURLProtocolUsesAPIAuthAndSeparatePUTWithoutAuth() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HTTPMock.self]
        let session = URLSession(configuration: configuration, delegate: RejectRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let client = PyannoteTransport(apiSession: session, uploadSession: session)
        let reply = try await client.api(path: "/v1/diarize", method: "POST", body: Data("{}".utf8), key: "test-only")
        XCTAssertEqual(reply.status, 401)
        let put = try PyannoteTransport.uploadRequest(URL(string: "https://storage.example/upload?signed=example")!)
        XCTAssertNil(put.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(put.httpMethod, "PUT")
        XCTAssertThrowsError(try PyannoteTransport.uploadRequest(URL(string: "http://storage.example")!))
        let redirected = URLRequest(url: URL(string: "https://other.example")!)
        let task = session.dataTask(with: URL(string: "https://api.pyannote.ai")!)
        let completed = expectation(description: "redirect rejected")
        RejectRedirects().urlSession(session, task: task, willPerformHTTPRedirection: HTTPURLResponse(url: task.originalRequest!.url!, statusCode: 302, httpVersion: nil, headerFields: nil)!, newRequest: redirected) { next in
            XCTAssertNil(next); completed.fulfill()
        }
        await fulfillment(of: [completed], timeout: 1)
    }
}

private actor FakeTransport: ManagedTransport {
    let final: Data
    let submitStatus: Int
    var getFailureCount: Int
    var calls: [String] = []
    var lastSubmission: Data?
    init(final: Data, submitStatus: Int = 200, getFailureCount: Int = 0) {
        self.final = final; self.submitStatus = submitStatus; self.getFailureCount = getFailureCount
    }
    func api(path: String, method: String, body: Data?, key: String) async throws -> HTTPReply {
        calls.append(method + " " + path)
        if path == "/v1/media/input" { return HTTPReply(data: Data("{\"url\":\"https://storage.example/signed\"}".utf8), status: 201) }
        if path == "/v1/diarize" {
            lastSubmission = body
            if submitStatus == -1 { throw URLError(.timedOut) }
            let json = try JSONSerialization.jsonObject(with: body!) as! [String: Any]
            XCTAssertEqual(json["model"] as? String, "precision-2")
            XCTAssertEqual((json["transcriptionConfig"] as? [String: String])?["model"], "faster-whisper-large-v3-turbo")
            XCTAssertNil((json["transcriptionConfig"] as? [String: String])?["language"])
            return HTTPReply(data: Data("{\"jobId\":\"11111111-1111-4111-8111-111111111111\"}".utf8), status: submitStatus)
        }
        if getFailureCount > 0 { getFailureCount -= 1; return HTTPReply(data: Data(), status: 503) }
        return HTTPReply(data: final, status: 200)
    }
    func upload(file: URL, to url: URL) async throws -> HTTPReply {
        calls.append("PUT")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        return HTTPReply(data: Data(), status: 200)
    }
}

private final class HTTPMock: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-only")
        let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: [:])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

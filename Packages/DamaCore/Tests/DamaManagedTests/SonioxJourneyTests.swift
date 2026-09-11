import AVFoundation
import DamaAudio
import DamaCore
import Foundation
import XCTest
@testable import DamaManaged

@MainActor final class SonioxJourneyTests: XCTestCase {
    private func setup() async throws -> (URL, AudioManifest) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000)!
        pcm.frameLength = 48_000; pcm.floatChannelData![0].initialize(repeating: 0, count: 48_000)
        let path = root.appendingPathComponent("synthetic.wav")
        let file = try AVAudioFile(forWriting: path, settings: format.settings)
        try file.write(from: pcm); file.close()
        return (root, try await AudioLibrary(root: root).importFile(path))
    }
    private var notes: ConversionNotes {
        var value = ConversionNotes(context: "local only", aiCorrection: false)
        value.transcriptionProvider = .soniox
        return value
    }
    func testConsentCredentialResumeWholeFileAndImmutableRetranscription() async throws {
        let (root, audio) = try await setup(), fake = SonioxFake(), forbidden = ForbiddenPyannote()
        let processor = ManagedProcessor(root: root, transport: forbidden, soniox: fake, sleep: { _ in })
        do { _ = try await processor.begin(sessionID: audio.id, confirmed: false, key: "synthetic", input: notes); XCTFail() } catch {}
        let waiting = try await processor.begin(sessionID: audio.id, confirmed: true, key: "", input: notes)
        let before = await fake.calls; XCTAssertTrue(before.isEmpty)
        XCTAssertEqual(waiting.stage, "waitingForCredentials")
        let restarted = ManagedProcessor(root: root, transport: forbidden, soniox: fake, sleep: { _ in })
        let run = try await restarted.resume(waiting.id, key: "synthetic")
        XCTAssertEqual(run.stage, "readyForReview"); XCTAssertEqual(run.provider, .soniox)
        XCTAssertEqual(run.reportedModel, "stt-async-v5"); XCTAssertNotNil(run.sourceAudioSHA256)
        let repository = FileSessionRepository(rootURL: root)
        let doc = try await repository.load(sessionId: audio.id, revisionId: nil)
        XCTAssertEqual(doc.provenance.engine, .managedSoniox)
        let runDir = root.appendingPathComponent("Sessions/\(audio.id)/runs/\(run.id)")
        let raw = try Data(contentsOf: runDir.appendingPathComponent("raw/soniox-response.json"))
        let expectedRaw = try await fake.transcript(); XCTAssertEqual(raw, expectedRaw)
        let original = try Data(contentsOf: runDir.appendingPathComponent("normalized/model.json"))
        let scripts = root.appendingPathComponent("exports")
        var script = try LibraryScript(transcript: doc, title: "comparison", recordedAt: nil, dateSource: "synthetic", input: notes)
        try script.editText(doc.turns[0].id, text: "human edit")
        let originalScript = try JSONEncoder().encode(script)
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
        try originalScript.write(to: scripts.appendingPathComponent("first.json"))
        var fixturePath = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { fixturePath.deleteLastPathComponent() }
        let pyannote = SyntheticPyannote(final: try Data(contentsOf: fixturePath.appendingPathComponent("fixtures/pyannote-job-succeeded.synthetic.json")))
        let second = try await ManagedProcessor(root: root, transport: pyannote, soniox: fake, sleep: { _ in })
            .begin(sessionID: audio.id, confirmed: true, key: "synthetic", input: ConversionNotes(), retranscribing: true)
        XCTAssertEqual(second.stage, "readyForReview"); XCTAssertNotEqual(second.id, run.id)
        XCTAssertEqual(second.provider, .pyannote)
        XCTAssertEqual(second.sourceAudioSHA256, run.sourceAudioSHA256)
        XCTAssertEqual(try Data(contentsOf: runDir.appendingPathComponent("normalized/model.json")), original)
        XCTAssertEqual(try Data(contentsOf: scripts.appendingPathComponent("first.json")), originalScript)
        let calls = await fake.calls
        XCTAssertEqual(calls.filter { $0 == "upload" }.count, 1)
        XCTAssertEqual(calls.filter { $0 == "POST /v1/transcriptions" }.count, 1)
        let unexpected = await forbidden.calls; XCTAssertEqual(unexpected, 0)
    }
    func testUncertainPOSTAndInterruptedUploadNeverAutomaticallyRetry() async throws {
        for fault in ["uploadTimeout", "submitTimeout", "badAcceptedID"] {
            let (root, audio) = try await setup(), fake = SonioxFake(fault: fault)
            let processor = ManagedProcessor(root: root, soniox: fake, sleep: { _ in })
            let run = try await processor.begin(sessionID: audio.id, confirmed: true, key: "synthetic", input: notes)
            XCTAssertEqual(run.stage, "submissionUncertain", fault)
            let calls = await fake.calls
            do { _ = try await ManagedProcessor(root: root, soniox: fake).resume(run.id, key: "synthetic"); XCTFail() } catch {}
            let after = await fake.calls; XCTAssertEqual(after, calls)
        }
    }
    func testHTTPFailuresResumeExistingFileAndJob() async throws {
        for (fault, expected) in [("submit401", "waitingForCredentials"), ("submit402", "waitingForBilling"),
                                  ("submit429", "waitingForNetwork"), ("submit500", "submissionUncertain"),
                                  ("poll503", "waitingForNetwork"), ("transcript503", "waitingForNetwork"),
                                  ("transcript404", "resultExpired"), ("unknown", "unknownRemoteStatus"), ("error", "failed")] {
            let (root, audio) = try await setup(), fake = SonioxFake(fault: fault)
            let processor = ManagedProcessor(root: root, soniox: fake, sleep: { _ in })
            let run = try await processor.begin(sessionID: audio.id, confirmed: true, key: "synthetic", input: notes)
            XCTAssertEqual(run.stage, expected, fault)
            if expected.hasPrefix("waiting") {
                await fake.clearFault()
                let resumed = try await processor.resume(run.id, key: "synthetic")
                XCTAssertEqual(resumed.stage, "readyForReview", fault)
                let calls = await fake.calls
                XCTAssertEqual(calls.filter { $0 == "upload" }.count, 1, fault)
                if run.jobID != nil { XCTAssertEqual(calls.filter { $0 == "POST /v1/transcriptions" }.count, 1, fault) }
            }
        }
    }
    func testTransportMultipartAuthAndPathConfinement() async throws {
        let (root, _) = try await setup(), path = "/v1/transcriptions/\(UUID().uuidString)/transcript"
        let request = try SonioxTransport.request(path: path, method: "GET", body: nil, key: "synthetic")
        XCTAssertEqual(request.url?.host, "api.soniox.com")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic")
        for bad in ["https://evil.example", "/v1/transcriptions/../files", path + "?x=1", path + "/extra"] {
            XCTAssertThrowsError(try SonioxTransport.request(path: bad, method: "GET", body: nil, key: "synthetic"))
        }
        XCTAssertThrowsError(try SonioxTransport.request(path: "/v1/files", method: "DELETE", body: nil, key: "synthetic"))
        let source = root.appendingPathComponent("synthetic.wav"), body = root.appendingPathComponent("multipart")
        try SonioxTransport.multipart(file: source, destination: body, boundary: "synthetic-boundary")
        let bytes = try Data(contentsOf: body), audio = try Data(contentsOf: source)
        let head = Data("--synthetic-boundary\r\nContent-Disposition: form-data; name=\"file\"; filename=\"analysis.wav\"\r\nContent-Type: audio/wav\r\n\r\n".utf8)
        let tail = Data("\r\n--synthetic-boundary--\r\n".utf8)
        XCTAssertEqual(bytes, head + audio + tail)
    }
}

private actor ForbiddenPyannote: ManagedTransport {
    var calls = 0
    func api(path: String, method: String, body: Data?, key: String) throws -> HTTPReply { calls += 1; throw ManagedFailure.invalidURL }
    func upload(file: URL, to url: URL) throws -> HTTPReply { calls += 1; throw ManagedFailure.invalidURL }
}
private struct SyntheticPyannote: ManagedTransport {
    let final: Data
    func api(path: String, method: String, body: Data?, key: String) throws -> HTTPReply {
        if path == "/v1/media/input" { return HTTPReply(data: Data("{\"url\":\"https://synthetic.example/audio\"}".utf8), status: 201) }
        if path == "/v1/diarize" {
            return HTTPReply(data: Data("{\"jobId\":\"11111111-1111-4111-8111-111111111111\"}".utf8), status: 201)
        }
        return HTTPReply(data: final, status: 200)
    }
    func upload(file: URL, to url: URL) -> HTTPReply { HTTPReply(data: Data(), status: 200) }
}
private actor SonioxFake: SonioxTransporting {
    let job = UUID().uuidString, file = UUID().uuidString
    var fault: String
    var calls: [String] = []
    init(fault: String = "") { self.fault = fault }
    func clearFault() { fault = "" }
    func transcript() throws -> Data {
        try JSONSerialization.data(withJSONObject: ["id": job, "text": "안녕하세요.", "tokens": [
            ["text": "안녕", "start_ms": 0, "end_ms": 300, "speaker": "1", "confidence": 0.9],
            ["text": "하세요.", "start_ms": 300, "end_ms": 800, "speaker": "1", "confidence": 0.9]]], options: [.sortedKeys])
    }
    func upload(file: URL, key: String) throws -> HTTPReply {
        calls.append("upload")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        if fault == "uploadTimeout" { throw URLError(.timedOut) }
        return HTTPReply(data: try JSONSerialization.data(withJSONObject: ["id": self.file]), status: 201)
    }
    func api(path: String, method: String, body: Data?, key: String) throws -> HTTPReply {
        calls.append(method + " " + path)
        if method == "POST" {
            if fault == "submitTimeout" { throw URLError(.timedOut) }
            if fault.hasPrefix("submit"), let code = Int(fault.dropFirst(6)) { return HTTPReply(data: Data(), status: code, retryAfter: "0") }
            let payload = try JSONSerialization.jsonObject(with: body!) as! [String: Any]
            XCTAssertEqual(payload["file_id"] as? String, file); XCTAssertNil(payload["context"])
            XCTAssertEqual(payload["enable_speaker_diarization"] as? Bool, true)
            return HTTPReply(data: try JSONSerialization.data(withJSONObject: ["id": fault == "badAcceptedID" ? "../bad" : job,
                "status": "queued", "model": "stt-async-v5"]), status: 201)
        }
        if path.hasSuffix("/transcript") {
            if fault.hasPrefix("transcript"), let code = Int(fault.dropFirst(10)) { return HTTPReply(data: Data(), status: code) }
            return HTTPReply(data: try transcript(), status: 200)
        }
        if fault == "poll503" { return HTTPReply(data: Data(), status: 503) }
        return HTTPReply(data: try JSONSerialization.data(withJSONObject: ["id": job,
            "status": fault == "unknown" ? "futureStatus" : fault == "error" ? "error" : "completed",
            "model": "stt-async-v5", "audio_duration_ms": 3_000]), status: 200)
    }
}

import AVFoundation
import DamaAudio
import DamaCore
import Foundation
import XCTest
@testable import DamaManaged

@MainActor final class NemotronJourneyTests: XCTestCase {
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
    /// Tiny stand-in model files with a matching pinned list.
    private func models(_ root: URL, corrupt: Bool = false) throws -> NemotronModelStore {
        let modelsRoot = root.appendingPathComponent("Models")
        let dir = modelsRoot.appendingPathComponent(NemotronModel.folderName)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let bytes = Data("synthetic model".utf8)
        try bytes.write(to: dir.appendingPathComponent("weight.bin"))
        let pinned = NemotronModel.File(path: "weight.bin", sha256: try NemotronModelStore.sha256(dir.appendingPathComponent("weight.bin")),
                                        bytes: Int64(bytes.count))
        if corrupt { try Data("other model 0000".utf8).write(to: dir.appendingPathComponent("weight.bin")) }
        return NemotronModelStore(modelsRoot: modelsRoot, files: [pinned])
    }
    private var notes: ConversionNotes {
        var value = ConversionNotes(context: "local only", aiCorrection: false)
        value.transcriptionProvider = .sonioxNemotron
        return value
    }
    private func runDir(_ root: URL, _ session: String, _ run: String) -> URL {
        root.appendingPathComponent("Sessions/\(session)/runs/\(run)")
    }

    func testNewRunDiarizesLocallyAndNeverCallsPyannote() async throws {
        let (root, audio) = try await setup(), soniox = NmSoniox(), p2 = NoPyannote(), diarizer = FakeDiarizer()
        let processor = ManagedProcessor(root: root, transport: p2, soniox: soniox, diarizer: diarizer,
            nemotronModels: try models(root), allowsPyannote: false, sleep: { _ in })
        let done = try await processor.begin(sessionID: audio.id, confirmed: true, key: "", input: notes, sonioxKey: "soniox-key")
        XCTAssertEqual(done.stage, "readyForReview")
        XCTAssertEqual(done.combinationAlgorithmVersion, "soniox-nemotron-word-v3")
        let doc = try await FileSessionRepository(rootURL: root).loadModel(sessionId: audio.id, runId: done.id)
        XCTAssertEqual(doc.provenance.engine, .hybridSonioxNemotron)
        XCTAssertEqual(doc.provenance.algorithmVersion, "soniox-nemotron-word-v3")
        XCTAssertEqual(doc.words.compactMap(\.speakerId), ["\(done.id)-nm-0", "\(done.id)-nm-0"])
        for name in ["soniox-response.json", "nemotron-probabilities.f32", "nemotron-meta.json"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: runDir(root, audio.id, done.id).appendingPathComponent("raw/\(name)").path), name)
        }
        let childID = try XCTUnwrap(done.nemotronRunID)
        let meta = try JSONDecoder().decode(NemotronMeta.self, from: Data(contentsOf:
            runDir(root, audio.id, childID).appendingPathComponent("raw/nemotron-meta.json")))
        XCTAssertEqual(meta.fluidAudioVersion, "0.18.0"); XCTAssertEqual(meta.preset, "offline")
        XCTAssertEqual(meta.channels, 8); XCTAssertEqual(meta.frameCount, 300); XCTAssertEqual(meta.sampleCount, 48_000)
        XCTAssertEqual(meta.audioSHA256, done.sourceAudioSHA256); XCTAssertEqual(meta.modelManifestSHA256, NemotronModel.manifestSHA256)
        let calls = await p2.calls; XCTAssertEqual(calls, 0)
        let diarized = await diarizer.calls; XCTAssertEqual(diarized, 1)
        let posts = await soniox.posts; XCTAssertEqual(posts, 1)
        let runs = try await processor.runs()
        XCTAssertFalse(runs.contains { $0.stage == "submissionUncertain" })
        XCTAssertEqual(runs.first { $0.id == childID }?.stage, "readyForReview")
        XCTAssertEqual(runs.first { $0.id == childID }?.parentRunID, done.id)

        // Same audio and pinned model: both sources are reused, nothing runs again.
        var again = notes
        again.sonioxSourceRunID = try await processor.reusableSoniox(sessionID: audio.id, audioHash: done.sourceAudioSHA256!, input: again)
        again.nemotronSourceRunID = try await processor.reusableNemotron(sessionID: audio.id, audioHash: done.sourceAudioSHA256!)
        XCTAssertEqual(again.nemotronSourceRunID, childID)
        let reused = try await processor.begin(sessionID: audio.id, confirmed: true, key: "", input: again,
                                               retranscribing: true, sonioxKey: "")
        XCTAssertEqual(reused.stage, "readyForReview")
        XCTAssertNotEqual(reused.id, done.id)
        let diarizedAgain = await diarizer.calls; XCTAssertEqual(diarizedAgain, 1)
        let postsAgain = await soniox.posts; XCTAssertEqual(postsAgain, 1)
        let callsAgain = await p2.calls; XCTAssertEqual(callsAgain, 0)
    }

    func testReuseKeyRejectsEachChangedField() async throws {
        let (root, audio) = try await setup(), diarizer = FakeDiarizer()
        let processor = ManagedProcessor(root: root, transport: NoPyannote(), soniox: NmSoniox(), diarizer: diarizer,
            nemotronModels: try models(root), allowsPyannote: false, sleep: { _ in })
        let done = try await processor.begin(sessionID: audio.id, confirmed: true, key: "", input: notes, sonioxKey: "soniox-key")
        let hash = try XCTUnwrap(done.sourceAudioSHA256), childID = try XCTUnwrap(done.nemotronRunID)
        let raw = runDir(root, audio.id, childID).appendingPathComponent("raw")
        let metaURL = raw.appendingPathComponent("nemotron-meta.json")
        let original = try Data(contentsOf: metaURL)
        let reusable = try await processor.reusableNemotron(sessionID: audio.id, audioHash: hash)
        XCTAssertEqual(reusable, childID)
        let otherHash = try await processor.reusableNemotron(sessionID: audio.id, audioHash: String(repeating: "b", count: 64))
        XCTAssertNil(otherHash)
        let changes: [(String, (inout NemotronMeta) -> Void)] = [
            ("fluidAudioVersion", { $0.fluidAudioVersion = "0.18.1" }),
            ("preset", { $0.preset = "low" }),
            ("modelManifestSHA256", { $0.modelManifestSHA256 = String(repeating: "0", count: 64) }),
            ("audioSHA256", { $0.audioSHA256 = String(repeating: "c", count: 64) }),
            ("channels", { $0.channels = 4 }),
            ("frameCount", { $0.frameCount += 1 }),
        ]
        for (name, change) in changes {
            var meta = try JSONDecoder().decode(NemotronMeta.self, from: original)
            change(&meta)
            try FileManager.default.removeItem(at: metaURL)
            try JSONEncoder().encode(meta).write(to: metaURL)
            let found = try await processor.reusableNemotron(sessionID: audio.id, audioHash: hash)
            XCTAssertNil(found, name)
        }
        try FileManager.default.removeItem(at: metaURL)
        try original.write(to: metaURL)
        let restored = try await processor.reusableNemotron(sessionID: audio.id, audioHash: hash)
        XCTAssertEqual(restored, childID)
    }

    func testFailedDiarizationResumesWithoutNewSonioxRequest() async throws {
        let (root, audio) = try await setup(), soniox = NmSoniox(), diarizer = FakeDiarizer(failures: 1)
        let processor = ManagedProcessor(root: root, transport: NoPyannote(), soniox: soniox, diarizer: diarizer,
            nemotronModels: try models(root), allowsPyannote: false, sleep: { _ in })
        let failed = try await processor.begin(sessionID: audio.id, confirmed: true, key: "", input: notes, sonioxKey: "soniox-key")
        XCTAssertEqual(failed.stage, "failed")
        XCTAssertEqual(failed.failure, "localDiarizationFailed")
        XCTAssertTrue(failed.resumesLocalDiarization)
        let child = try await processor.runs().first { $0.id == failed.nemotronRunID }
        XCTAssertEqual(child?.stage, "failed")
        let done = try await processor.resume(failed.id, key: "", sonioxKey: "")
        XCTAssertEqual(done.stage, "readyForReview")
        let diarized = await diarizer.calls; XCTAssertEqual(diarized, 2)
        let posts = await soniox.posts; XCTAssertEqual(posts, 1)
    }

    func testMismatchedOrMissingModelFailsWithoutRunning() async throws {
        let (root, audio) = try await setup(), diarizer = FakeDiarizer()
        let processor = ManagedProcessor(root: root, transport: NoPyannote(), soniox: NmSoniox(), diarizer: diarizer,
            nemotronModels: try models(root, corrupt: true), allowsPyannote: false, sleep: { _ in })
        let failed = try await processor.begin(sessionID: audio.id, confirmed: true, key: "", input: notes, sonioxKey: "soniox-key")
        XCTAssertEqual(failed.stage, "failed")
        XCTAssertEqual(failed.failure, "modelUnavailable")
        let diarized = await diarizer.calls; XCTAssertEqual(diarized, 0)
        let noModel = ManagedProcessor(root: root, transport: NoPyannote(), soniox: NmSoniox(), diarizer: diarizer,
            nemotronModels: nil, allowsPyannote: false, sleep: { _ in })
        let stillFailed = try await noModel.resume(failed.id, key: "", sonioxKey: "")
        XCTAssertEqual(stillFailed.failure, "modelUnavailable")
        let diarizedAfter = await diarizer.calls; XCTAssertEqual(diarizedAfter, 0)
    }

    func testRecordingGateAndCancellationLeaveRunQueuedWithoutProbabilities() async throws {
        let (root, audio) = try await setup(), diarizer = FakeDiarizer()
        let store = try models(root)
        let gated = ManagedProcessor(root: root, transport: NoPyannote(), soniox: NmSoniox(), diarizer: diarizer,
            nemotronModels: store, admitsLocalInference: { false }, allowsPyannote: false, sleep: { _ in })
        let queued = try await gated.begin(sessionID: audio.id, confirmed: true, key: "", input: notes, sonioxKey: "soniox-key")
        XCTAssertEqual(queued.stage, "queued")
        let diarized = await diarizer.calls; XCTAssertEqual(diarized, 0)
        let childID = try XCTUnwrap(queued.nemotronRunID)
        let gatedChild = try await gated.runs().first { $0.id == childID }
        XCTAssertEqual(gatedChild?.stage, "queued")

        let cancelling = FakeDiarizer(cancels: true)
        let cancelled = try await ManagedProcessor(root: root, transport: NoPyannote(), soniox: NmSoniox(), diarizer: cancelling,
            nemotronModels: store, allowsPyannote: false, sleep: { _ in }).resume(queued.id, key: "", sonioxKey: "")
        XCTAssertEqual(cancelled.stage, "queued")
        let probabilities = runDir(root, audio.id, childID).appendingPathComponent("raw/nemotron-probabilities.f32")
        XCTAssertFalse(FileManager.default.fileExists(atPath: probabilities.path))

        let done = try await ManagedProcessor(root: root, transport: NoPyannote(), soniox: NmSoniox(), diarizer: diarizer,
            nemotronModels: store, allowsPyannote: false, sleep: { _ in }).resume(queued.id, key: "", sonioxKey: "")
        XCTAssertEqual(done.stage, "readyForReview")
        XCTAssertTrue(FileManager.default.fileExists(atPath: probabilities.path))
    }

    func testStoredVersionIsKeptOnResumeAndUnknownVersionsFail() async throws {
        let (root, audio) = try await setup(), store = try models(root)
        let gated = ManagedProcessor(root: root, transport: NoPyannote(), soniox: NmSoniox(), diarizer: FakeDiarizer(),
            nemotronModels: store, admitsLocalInference: { false }, allowsPyannote: false, sleep: { _ in })
        let queued = try await gated.begin(sessionID: audio.id, confirmed: true, key: "", input: notes, sonioxKey: "soniox-key")
        XCTAssertEqual(queued.combinationAlgorithmVersion, "soniox-nemotron-word-v3")
        let stateURL = runDir(root, audio.id, queued.id).appendingPathComponent("state.json")
        func setVersion(_ value: String) throws {
            var run = try JSONDecoder().decode(ManagedRun.self, from: Data(contentsOf: stateURL))
            run.combinationAlgorithmVersion = value; run.stage = "queued"; run.failure = nil
            try JSONEncoder().encode(run).write(to: stateURL)
        }
        let open = ManagedProcessor(root: root, transport: NoPyannote(), soniox: NmSoniox(), diarizer: FakeDiarizer(),
            nemotronModels: store, allowsPyannote: false, sleep: { _ in })
        try setVersion("soniox-nemotron-word-v9")
        let unknown = try await open.resume(queued.id, key: "", sonioxKey: "")
        XCTAssertEqual(unknown.stage, "failed")
        XCTAssertEqual(unknown.combinationAlgorithmVersion, "soniox-nemotron-word-v9")
        try setVersion("soniox-nemotron-word-v1")
        let done = try await open.resume(queued.id, key: "", sonioxKey: "")
        XCTAssertEqual(done.stage, "readyForReview")
        XCTAssertEqual(done.combinationAlgorithmVersion, "soniox-nemotron-word-v1")
        let doc = try await FileSessionRepository(rootURL: root).loadModel(sessionId: audio.id, runId: done.id)
        XCTAssertEqual(doc.provenance.algorithmVersion, "soniox-nemotron-word-v1")
    }

    func testQueuedRunStoredAsV2KeepsV2() async throws {
        // r3: v3 is only for new runs; a run stored as v2 resumes with v2.
        let (root, audio) = try await setup(), store = try models(root)
        let gated = ManagedProcessor(root: root, transport: NoPyannote(), soniox: NmSoniox(), diarizer: FakeDiarizer(),
            nemotronModels: store, admitsLocalInference: { false }, allowsPyannote: false, sleep: { _ in })
        let queued = try await gated.begin(sessionID: audio.id, confirmed: true, key: "", input: notes, sonioxKey: "soniox-key")
        let stateURL = runDir(root, audio.id, queued.id).appendingPathComponent("state.json")
        var run = try JSONDecoder().decode(ManagedRun.self, from: Data(contentsOf: stateURL))
        run.combinationAlgorithmVersion = "soniox-nemotron-word-v2"
        try JSONEncoder().encode(run).write(to: stateURL)
        let done = try await ManagedProcessor(root: root, transport: NoPyannote(), soniox: NmSoniox(), diarizer: FakeDiarizer(),
            nemotronModels: store, allowsPyannote: false, sleep: { _ in }).resume(queued.id, key: "", sonioxKey: "")
        XCTAssertEqual(done.stage, "readyForReview")
        XCTAssertEqual(done.combinationAlgorithmVersion, "soniox-nemotron-word-v2")
        let doc = try await FileSessionRepository(rootURL: root).loadModel(sessionId: audio.id, runId: done.id)
        XCTAssertEqual(doc.provenance.algorithmVersion, "soniox-nemotron-word-v2")
    }

    func testRetiredPyannotePathsAreRefusedWithoutTouchingState() async throws {
        let (root, audio) = try await setup(), p2 = NoPyannote()
        let processor = ManagedProcessor(root: root, transport: p2, soniox: NmSoniox(), allowsPyannote: false, sleep: { _ in })
        for provider in [TranscriptionProvider.pyannote, .precision, .qwen, .sonioxPrecision] {
            var input = notes; input.transcriptionProvider = provider
            do { _ = try await processor.begin(sessionID: audio.id, confirmed: true, key: "k", input: input, sonioxKey: "s"); XCTFail("\(provider)") }
            catch { XCTAssertEqual(error as? ManagedFailure, .providerRetired, "\(provider)") }
        }
        // A stalled Soniox + Precision-2 parent whose P2 child hit HTTP 402 (same shape as B460D5A5).
        var p2Notes = notes; p2Notes.transcriptionProvider = .precision
        var parentNotes = notes; parentNotes.transcriptionProvider = .sonioxPrecision
        let child = ManagedRun(id: UUID().uuidString, sessionID: audio.id, createdAt: "2026-10-12T00:00:00Z", consent: true,
                               stage: "waitingForBilling", input: p2Notes)
        var parent = ManagedRun(id: UUID().uuidString, sessionID: audio.id, createdAt: "2026-10-12T00:00:00Z", consent: true,
                                stage: "waitingForBilling", input: parentNotes)
        parent.precisionRunID = child.id
        var withParent = child; withParent.parentRunID = parent.id; withParent.failure = "http402"
        for run in [parent, withParent] {
            let dir = runDir(root, audio.id, run.id)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try JSONEncoder().encode(run).write(to: dir.appendingPathComponent("state.json"))
        }
        let before = try Data(contentsOf: runDir(root, audio.id, parent.id).appendingPathComponent("state.json"))
        XCTAssertTrue(parent.needsPyannote(among: [parent, withParent]))
        do { _ = try await processor.resume(parent.id, key: "pyannote-key", sonioxKey: "s"); XCTFail("resumed") }
        catch { XCTAssertEqual(error as? ManagedFailure, .providerRetired) }
        XCTAssertEqual(try Data(contentsOf: runDir(root, audio.id, parent.id).appendingPathComponent("state.json")), before)
        let calls = await p2.calls; XCTAssertEqual(calls, 0)
        // Retranscribing the stalled speech starts a new local run despite the retired parent.
        let soniox = NmSoniox(), diarizer = FakeDiarizer()
        let fresh = ManagedProcessor(root: root, transport: p2, soniox: soniox, diarizer: diarizer,
            nemotronModels: try models(root), allowsPyannote: false, sleep: { _ in })
        let replaced = try await fresh.begin(sessionID: audio.id, confirmed: true, key: "", input: notes,
                                             retranscribing: true, sonioxKey: "soniox-key")
        XCTAssertEqual(replaced.stage, "readyForReview")
        let callsAfter = await p2.calls; XCTAssertEqual(callsAfter, 0)
        XCTAssertEqual(try Data(contentsOf: runDir(root, audio.id, parent.id).appendingPathComponent("state.json")), before)
        // Completed P2 or a reused P2 source keeps the old path local.
        var readyChild = withParent; readyChild.stage = "readyForReview"
        XCTAssertFalse(parent.needsPyannote(among: [parent, readyChild]))
        var reusedQwen = notes; reusedQwen.transcriptionProvider = .qwen; reusedQwen.qwenDiarizationRunID = "reused"
        XCTAssertFalse(ManagedRun.needsPyannote(reusedQwen))
    }
}

private actor FakeDiarizer: LocalDiarizing {
    var calls = 0
    var failures: Int
    let cancels: Bool
    init(failures: Int = 0, cancels: Bool = false) { self.failures = failures; self.cancels = cancels }
    func diarize(analysisWAV: URL, modelDirectory: URL) throws -> LocalDiarization {
        calls += 1
        XCTAssertTrue(FileManager.default.fileExists(atPath: analysisWAV.path))
        if cancels { throw CancellationError() }
        if failures > 0 { failures -= 1; throw URLError(.cannotDecodeContentData) }
        // 3 s at 10 ms: channel 0 active for the first second.
        var values = [Float](repeating: 0.01, count: 300 * 8)
        for frame in 0..<100 { values[frame * 8] = 0.95 }
        var data = Data()
        for value in values { withUnsafeBytes(of: value.bitPattern.littleEndian) { data.append(contentsOf: $0) } }
        return LocalDiarization(probabilities: data, frameCount: 300, channels: 8, sampleCount: 48_000, processingSeconds: 0.01)
    }
}

private actor NoPyannote: ManagedTransport {
    var calls = 0
    func api(path: String, method: String, body: Data?, key: String) -> HTTPReply {
        calls += 1; XCTFail("pyannote called: \(method) \(path)")
        return HTTPReply(data: Data(), status: 500)
    }
    func upload(file: URL, to url: URL) -> HTTPReply { calls += 1; XCTFail("pyannote upload"); return HTTPReply(data: Data(), status: 500) }
}

private actor NmSoniox: SonioxTransporting {
    let job = UUID().uuidString, file = UUID().uuidString
    var posts = 0
    func upload(file: URL, key: String) throws -> HTTPReply {
        HTTPReply(data: try JSONSerialization.data(withJSONObject: ["id": self.file]), status: 201)
    }
    func api(path: String, method: String, body: Data?, key: String) throws -> HTTPReply {
        if method == "POST" {
            posts += 1
            return HTTPReply(data: try JSONSerialization.data(withJSONObject: ["id": job, "status": "queued", "model": "stt-async-v5"]), status: 201)
        }
        if path.hasSuffix("/transcript") {
            return HTTPReply(data: try JSONSerialization.data(withJSONObject: ["id": job, "text": "안녕하세요.", "tokens": [
                ["text": "안녕", "start_ms": 0, "end_ms": 300, "speaker": "1", "confidence": 0.9],
                ["text": "하세요.", "start_ms": 300, "end_ms": 800, "speaker": "1", "confidence": 0.9]]], options: [.sortedKeys]), status: 200)
        }
        return HTTPReply(data: try JSONSerialization.data(withJSONObject: ["id": job, "status": "completed",
            "model": "stt-async-v5", "audio_duration_ms": 3_000]), status: 200)
    }
}

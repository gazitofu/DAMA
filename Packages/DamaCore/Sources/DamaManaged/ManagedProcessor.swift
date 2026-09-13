import CryptoKit
import DamaAudio
import DamaCore
import Foundation

public struct ManagedRun: Codable, Sendable, Identifiable {
    public let id: String
    public let sessionID: String
    public let createdAt: String
    public let consent: Bool
    public var stage: String
    public var attemptID: String?
    public var requestHash: String?
    public var jobID: String?
    public var remoteStatus: String?
    public var retryAt: Date?
    public var failure: String?
    public var input: ConversionNotes?
    public var lastServerCheckAt: Date?
    public var uploadedFileID: String?
    public var reportedModel: String?
    public var sourceAudioSHA256: String?
    public var parentRunID: String?
    public var sonioxRunID: String?
    public var precisionRunID: String?
    // Missing in older persisted runs: retain v2 when resuming those runs.
    public var combinationAlgorithmVersion: String? = nil
    public var provider: TranscriptionProvider { input?.provider ?? .pyannote }

    public var canRetranscribe: Bool {
        ["readyForReview", "failed", "partialResult", "resultExpired", "submissionUncertain"].contains(stage)
    }
    public var creationDate: Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: createdAt) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: createdAt) ?? .distantPast
    }
}

public actor ManagedProcessor {
    private let root: URL
    private let transport: any ManagedTransport
    private let soniox: any SonioxTransporting
    private let qwen: any QwenRunning
    private let sleep: @Sendable (Double) async throws -> Void
    private var active = false
    public init(root: URL, transport: any ManagedTransport = PyannoteTransport(),
                soniox: any SonioxTransporting = SonioxTransport(),
                qwen: any QwenRunning = QwenRunner(),
                sleep: @escaping @Sendable (Double) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }) {
        self.root = root.standardizedFileURL
        self.transport = transport
        self.soniox = soniox
        self.qwen = qwen
        self.sleep = sleep
    }

    private func directory(_ run: ManagedRun) throws -> URL {
        guard UUID(uuidString: run.id) != nil else { throw ManagedFailure.unsafePath }
        let directory = try AudioFiles.session(run.sessionID, root: root).appendingPathComponent("runs/\(run.id)")
        guard directory.resolvingSymlinksInPath().path == directory.path else { throw ManagedFailure.unsafePath }
        return directory
    }
    private func persist(_ run: ManagedRun) throws {
        let directory = try directory(run)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("state.json")
        guard file.resolvingSymlinksInPath().path == file.path else { throw ManagedFailure.unsafePath }
        try JSONEncoder().encode(run).write(to: file, options: .atomic)
    }
    private func immutable(_ data: Data, to url: URL) throws {
        guard url.resolvingSymlinksInPath().path == url.path else { throw ManagedFailure.unsafePath }
        if FileManager.default.fileExists(atPath: url.path) {
            guard try Data(contentsOf: url) == data else { throw ManagedFailure.localStorage }
        } else {
            let temporary = url.deletingLastPathComponent().appendingPathComponent(".install-\(UUID().uuidString)")
            try data.write(to: temporary, options: .withoutOverwriting)
            defer { try? FileManager.default.removeItem(at: temporary) }
            try FileManager.default.linkItem(at: temporary, to: url)
        }
    }
    public func runs(recover: Bool = false) throws -> [ManagedRun] {
        let scan = try scanRuns(recover: recover)
        guard scan.issues.isEmpty else { throw ManagedFailure.localStorage }
        return scan.items
    }

    /// Partial results are for display. Executing/reusing a run requires its complete session history.
    public func scanRuns(recover: Bool = false) throws -> FileScanResult<ManagedRun> {
        let sessions = root.appendingPathComponent("Sessions")
        guard sessions.resolvingSymlinksInPath().path == sessions.path else { throw ManagedFailure.unsafePath }
        guard FileManager.default.fileExists(atPath: sessions.path) else { return FileScanResult() }
        var result: [ManagedRun] = [], issues: [FileScanIssue] = []
        for session in try FileManager.default.contentsOfDirectory(at: sessions, includingPropertiesForKeys: nil) {
            try Task.checkCancellation()
            guard UUID(uuidString: session.lastPathComponent) != nil else { continue }
            let sessionID = session.lastPathComponent
            do {
                let runs = try AudioFiles.session(sessionID, root: root).appendingPathComponent("runs")
                guard runs.resolvingSymlinksInPath().path == runs.path else { throw ManagedFailure.unsafePath }
                guard FileManager.default.fileExists(atPath: runs.path) else { continue }
                for directory in try FileManager.default.contentsOfDirectory(at: runs, includingPropertiesForKeys: nil) {
                    guard UUID(uuidString: directory.lastPathComponent) != nil else { continue }
                    let file = directory.appendingPathComponent("state.json").standardizedFileURL
                    do {
                        guard file.resolvingSymlinksInPath().path == file.path else { throw ManagedFailure.unsafePath }
                        let run = try JSONDecoder().decode(ManagedRun.self, from: Data(contentsOf: file))
                        guard run.id == directory.lastPathComponent, run.sessionID == sessionID else { throw ManagedFailure.unsafePath }
                        try run.input?.validate()
                        guard Self.knownStages.contains(run.stage) else { throw ManagedFailure.localStorage }
                        result.append(run)
                    } catch {
                        issues.append(FileScanIssue(url: file, reason: error as? ManagedFailure == .unsafePath ? .unsafePath : .unreadable,
                                                    sessionID: sessionID, itemID: directory.lastPathComponent))
                    }
                }
            } catch is CancellationError { throw CancellationError() }
            catch {
                issues.append(FileScanIssue(url: session, reason: (error as? ManagedFailure == .unsafePath || error as? AudioFailure == .unsafePath) ? .unsafePath : .unreadable, sessionID: sessionID))
            }
        }
        let duplicates = Set(Dictionary(grouping: result, by: \.id).filter { $0.value.count > 1 }.keys)
        var valid: [ManagedRun] = []
        for var run in result {
            try Task.checkCancellation()
            let file = try directory(run).appendingPathComponent("state.json")
            if duplicates.contains(run.id) {
                issues.append(FileScanIssue(url: file, reason: .duplicateIdentity, sessionID: run.sessionID, itemID: run.id))
                continue
            }
            if recover && !active && ((run.stage == "submitting" && run.jobID == nil) ||
                (run.stage == "uploadSubmitting" && run.uploadedFileID == nil)) {
                run.stage = "submissionUncertain"
                do { try persist(run) }
                catch { issues.append(FileScanIssue(url: file, sessionID: run.sessionID, itemID: run.id)); continue }
            }
            valid.append(run)
        }
        return FileScanResult(items: valid.sorted { $0.creationDate == $1.creationDate ? $0.id > $1.id : $0.creationDate > $1.creationDate },
                              issues: issues.sorted { $0.id < $1.id })
    }
    private static let knownStages: Set<String> = [
        "queued", "uploading", "uploadSubmitting", "uploaded", "submitting", "submissionUncertain",
        "waitingForCredentials", "waitingForBilling", "waitingForNetwork", "remotePending",
        "unknownRemoteStatus", "resultExpired", "normalizing", "localTranscribing", "paused",
        "readyForReview", "failed", "partialResult"
    ]
    private func runsForSession(_ sessionID: String, recover: Bool = false) throws -> [ManagedRun] {
        let scan = try scanRuns(recover: recover)
        guard !scan.issues.contains(where: { $0.sessionID == sessionID }) else { throw ManagedFailure.localStorage }
        return scan.items.filter { $0.sessionID == sessionID }
    }
    public func isLocalOnly(_ sessionID: String) throws -> Bool {
        let file = try AudioFiles.session(sessionID, root: root).appendingPathComponent("audio/never-upload.json")
        guard file.resolvingSymlinksInPath().path == file.path else { throw ManagedFailure.unsafePath }
        return FileManager.default.fileExists(atPath: file.path)
    }

    public func reusableDiarization(sessionID: String, audioHash: String, speakerCount: Int?) throws -> String? {
        for run in try runsForSession(sessionID) where [.pyannote, .qwen, .precision].contains(run.provider) && run.stage=="readyForReview" && run.sourceAudioSHA256==audioHash {
            let dir=try directory(run)
            guard let data=try? Data(contentsOf:dir.appendingPathComponent("request.json")),
                  let request=try JSONSerialization.jsonObject(with:data) as? [String:Any],
                  request["model"] as? String=="precision-2",request["exclusive"] as? Bool==true,
                  request["turnLevelConfidence"] as? Bool==true,
                  (request["numSpeakers"] as? Int)==speakerCount,
                  request["minSpeakers"] == nil, request["maxSpeakers"] == nil,
                  let raw=try? Data(contentsOf:dir.appendingPathComponent("raw/pyannote-response.json")),
                  let job=try? JSONDecoder().decode(PyannoteJobDTO.self,from:raw),job.status=="succeeded",
                  job.output?.error==nil,job.output?.exclusiveDiarization != nil else { continue }
            return run.id
        }
        return nil
    }
    public func reusableSoniox(sessionID: String, audioHash: String, input: ConversionNotes) throws -> String? {
        let wanted = try SonioxRequest.context(input)
        for run in try runsForSession(sessionID) where run.provider == .soniox &&
            run.stage == "readyForReview" && run.sourceAudioSHA256 == audioHash {
            let dir = try directory(run)
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("request.json")),
                  let request = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  request["model"] as? String == input.provider.model,
                  request["language_hints"] as? [String] == ["ko", "en"],
                  request["enable_speaker_diarization"] as? Bool == true,
                  request["enable_language_identification"] as? Bool == true,
                  request["translation"] == nil,
                  FileManager.default.fileExists(atPath: dir.appendingPathComponent("raw/soniox-response.json").path) else { continue }
            let context = try request["context"].map { try JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys, .withoutEscapingSlashes]) }
            if context == wanted { return run.id }
        }
        return nil
    }
    public func setLocalOnly(_ sessionID: String) throws {
        guard !active, try runsForSession(sessionID).isEmpty else { throw ManagedFailure.busy }
        let file = try AudioFiles.session(sessionID, root: root).appendingPathComponent("audio/never-upload.json")
        try immutable(Data("{\"neverUpload\":true}".utf8), to: file)
    }

    public func begin(sessionID: String, confirmed: Bool, key: String, input: ConversionNotes = ConversionNotes(), retranscribing: Bool = false, sonioxKey: String = "") async throws -> ManagedRun {
        try input.validate()
        guard confirmed, try !isLocalOnly(sessionID) else { throw ManagedFailure.consentRequired }
        guard !active else { throw ManagedFailure.busy }
        let previous = try runsForSession(sessionID, recover: true).filter { $0.parentRunID == nil && (input.provider == .qwen || $0.provider != .qwen) }
        guard previous.isEmpty || (retranscribing && previous.allSatisfy(\.canRetranscribe)) else { throw ManagedFailure.existingRun }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let run = ManagedRun(id: UUID().uuidString, sessionID: sessionID,
                             createdAt: formatter.string(from: Date()), consent: true, stage: "queued", input: input,
                             combinationAlgorithmVersion: input.provider == .sonioxPrecision ? SonioxPrecisionComparison.wordRepair.rawValue : nil)
        try persist(run)
        return try await execute(run, key: key, sonioxKey: sonioxKey)
    }
    public func resume(_ id: String, key: String, sonioxKey: String = "") async throws -> ManagedRun {
        guard !active else { throw ManagedFailure.busy }
        let scan = try scanRuns(recover: true)
        guard let run = scan.items.first(where: { $0.id == id }),
              !scan.issues.contains(where: { $0.sessionID == run.sessionID }),
              !["submissionUncertain", "readyForReview", "failed", "partialResult", "resultExpired", "unknownRemoteStatus"].contains(run.stage)
        else { throw ManagedFailure.existingRun }
        return try await execute(run, key: key, sonioxKey: sonioxKey)
    }

    private func execute(_ input: ManagedRun, key: String, sonioxKey: String = "") async throws -> ManagedRun {
        guard input.consent, try !isLocalOnly(input.sessionID) else { throw ManagedFailure.consentRequired }
        let alreadyActive = active
        active = true
        defer { active = alreadyActive }
        var run = input
        do {
            if run.provider == .sonioxPrecision {
                let version = run.combinationAlgorithmVersion ?? SonioxPrecisionNormalizer.version
                guard [SonioxPrecisionNormalizer.version, SonioxPrecisionComparison.wordRepair.rawValue].contains(version)
                else { throw ManagedFailure.invalidResponse }
                run.combinationAlgorithmVersion = version
                try persist(run)
            }
            if run.provider == .qwen { try qwen.validateReady() }
            if let retryAt = run.retryAt, retryAt > Date() { try await sleep(retryAt.timeIntervalSinceNow) }
            let library = AudioLibrary(root: root)
            let audio = try await library.prepareAnalysis(run.sessionID)
            guard let analysis = audio.analysis else { throw ManagedFailure.sourceChanged }
            let audioDir = try AudioFiles.session(run.sessionID, root: root).appendingPathComponent("audio")
            for source in audio.sources {
                let sourceURL = audioDir.appendingPathComponent("source").appendingPathComponent(source.filename)
                guard sourceURL.resolvingSymlinksInPath().path == sourceURL.path,
                      try AudioFiles.hash(sourceURL) == source.sha256 else { throw ManagedFailure.sourceChanged }
            }
            let file = audioDir.appendingPathComponent("analysis.wav")
            guard try AudioFiles.hash(file) == analysis.sha256 else { throw ManagedFailure.sourceChanged }
            if let saved = run.sourceAudioSHA256, saved != analysis.sha256 { throw ManagedFailure.sourceChanged }
            run.sourceAudioSHA256 = analysis.sha256
            if run.provider == .sonioxPrecision {
                return try await executeCombined(&run, audio: audio, key: key, sonioxKey: sonioxKey)
            }
            let dir = try directory(run)
            let rawDir = dir.appendingPathComponent("raw")
            try FileManager.default.createDirectory(at: rawDir, withIntermediateDirectories: true)
            let rawURL = rawDir.appendingPathComponent(run.provider.rawFilename)
            if run.provider == .qwen,let sourceID=run.input?.qwenDiarizationRunID,
               !FileManager.default.fileExists(atPath:rawURL.path) {
                guard try reusableDiarization(sessionID:run.sessionID,audioHash:analysis.sha256,speakerCount:run.input?.speakerCount)==sourceID,
                      let source=try runsForSession(run.sessionID).first(where:{$0.id==sourceID}) else { throw ManagedFailure.sourceChanged }
                let bytes=try Data(contentsOf:directory(source).appendingPathComponent("raw/pyannote-response.json"))
                try immutable(bytes,to:rawURL)
                run.jobID=source.jobID;run.remoteStatus="succeeded (reused)";try persist(run)
            }
            if FileManager.default.fileExists(atPath: rawURL.path) {
                return try await normalize(&run, audio: audio, bytes: Data(contentsOf: rawURL))
            }
            guard !key.isEmpty else { run.stage="waitingForCredentials";try persist(run);return run }
            if run.provider == .soniox {
                return try await executeSoniox(&run, audio: audio, file: file, dir: dir, rawDir: rawDir, key: key)
            }
            if run.jobID == nil {
                run.stage = "uploading"; run.retryAt = nil; try persist(run)
                let media = "media://dama/\(run.sessionID)/\(run.id).wav"
                let uploadReply = try await transport.api(path: "/v1/media/input", method: "POST",
                    body: JSONSerialization.data(withJSONObject: ["url": media]), key: key)
                guard (200..<300).contains(uploadReply.status) else { return try httpFailure(uploadReply, run: run, submitting: false) }
                struct Upload: Decodable { let url: URL }
                let signedURL = try JSONDecoder().decode(Upload.self, from: uploadReply.data).url
                _ = try PyannoteTransport.uploadRequest(signedURL)
                let uploaded = try await transport.upload(file: file, to: signedURL)
                guard (200..<300).contains(uploaded.status) else { return try httpFailure(uploaded, run: run, submitting: false) }
                var payload: [String: Any] = [
                    "url": media, "model": "precision-2", "exclusive": true, "turnLevelConfidence": true,
                    "transcription": true, "transcriptionConfig": ["model": "faster-whisper-large-v3-turbo"]
                ]
                if run.provider == .qwen || run.provider == .precision { payload["transcription"]=false;payload.removeValue(forKey:"transcriptionConfig") }
                if let count = run.input?.speakerCount { payload["numSpeakers"] = count }
                let request = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
                try immutable(request, to: dir.appendingPathComponent("request.json"))
                run.attemptID = UUID().uuidString
                run.requestHash = SHA256.hash(data: request).map { String(format: "%02x", $0) }.joined()
                run.stage = "submitting"; try persist(run)
                let accepted = try await transport.api(path: "/v1/diarize", method: "POST", body: request, key: key)
                guard (200..<300).contains(accepted.status) else { return try httpFailure(accepted, run: run, submitting: true) }
                struct Accepted: Decodable { let jobId: String }
                let response = try JSONDecoder().decode(Accepted.self, from: accepted.data)
                guard !response.jobId.isEmpty, response.jobId.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 })
                else { throw ManagedFailure.invalidResponse }
                run.jobID = response.jobId
                run.stage = "remotePending"; try persist(run)
            }
            var attempt = 0
            var failures = 0
            while !Task.isCancelled {
                guard let jobID = run.jobID else { throw ManagedFailure.invalidResponse }
                run.stage = "remotePending"; try persist(run)
                let reply: HTTPReply
                do { reply = try await transport.api(path: "/v1/jobs/\(jobID)", method: "GET", body: nil, key: key) }
                catch {
                    failures += 1
                    if failures >= 3 { run.stage = "waitingForNetwork"; try persist(run); return run }
                    try await sleep(PollDelay.seconds(retryAfter: nil, attempt: failures)); continue
                }
                if reply.status == 429 || reply.status >= 500 {
                    failures += 1
                    if failures >= 3 { return try httpFailure(reply, run: run, submitting: false) }
                    try await sleep(PollDelay.seconds(retryAfter: reply.retryAfter, attempt: failures)); continue
                }
                if reply.status == 404 || reply.status == 410 {
                    run.stage = "resultExpired"; try persist(run); return run
                }
                guard (200..<300).contains(reply.status) else { return try httpFailure(reply, run: run, submitting: false) }
                // Preserve response bytes before parsing, even if the provider changed its schema.
                try immutable(reply.data, to: rawDir.appendingPathComponent("poll-\(UUID().uuidString).json"))
                struct Status: Decodable { let jobId: String; let status: String }
                let remote = try JSONDecoder().decode(Status.self, from: reply.data)
                guard remote.jobId == jobID else { throw ManagedFailure.invalidResponse }
                run.remoteStatus = remote.status
                run.lastServerCheckAt = Date()
                failures = 0
                if remote.status == "succeeded" {
                    try immutable(reply.data, to: rawURL)
                    return try await normalize(&run, audio: audio, bytes: reply.data)
                }
                if ["failed", "canceled"].contains(remote.status) { run.stage = "failed"; try persist(run); return run }
                guard ["pending", "created", "running"].contains(remote.status) else {
                    run.stage = "unknownRemoteStatus"; try persist(run); return run
                }
                try persist(run)
                try await sleep(PollDelay.seconds(retryAfter: reply.retryAfter, attempt: attempt, jitter: Double.random(in: 0.8...1.2)))
                attempt += 1
            }
            throw CancellationError()
        } catch {
            if (run.stage == "submitting" && run.jobID == nil) || (run.stage == "uploadSubmitting" && run.uploadedFileID == nil) { run.stage = "submissionUncertain" }
            else if error is CancellationError || error is QwenFailure { run.stage = "paused" }
            else if error is ManagedNormalizationError || error is TranscriptContractError || error is DecodingError { run.stage = "partialResult" }
            else if error is URLError { run.stage = "waitingForNetwork" }
            else { run.stage = "failed" }
            run.failure = (error as? QwenFailure)?.rawValue ?? (error as? ManagedFailure)?.rawValue ?? (error as? AudioFailure)?.rawValue ?? "operationFailed"
            try persist(run)
            return run
        }
    }

    private func normalize(_ run: inout ManagedRun, audio: AudioManifest, bytes: Data) async throws -> ManagedRun {
        run.stage = "normalizing"; try persist(run)
        guard let analysis = audio.analysis else { throw ManagedFailure.sourceChanged }
        let duration = try AudioFiles.microseconds(frames: analysis.frames, rate: analysis.sampleRate)
        if run.provider == .precision {
            let job = try JSONDecoder().decode(PyannoteJobDTO.self, from: bytes)
            guard job.status == "succeeded", job.output?.error == nil, job.output?.exclusiveDiarization != nil else {
                throw ManagedNormalizationError.partialResult
            }
            run.stage = "readyForReview"; run.failure = nil; run.reportedModel = "precision-2"; try persist(run)
            return run
        }
        let document: TranscriptDocument
        if run.provider == .qwen {
            run.stage="localTranscribing";try persist(run)
            let dir=try directory(run)
            let file=try AudioFiles.session(run.sessionID,root:root).appendingPathComponent("audio/analysis.wav")
            let localURL=dir.appendingPathComponent("raw/qwen-response.json")
            let local: Data
            if FileManager.default.fileExists(atPath:localURL.path) { local=try Data(contentsOf:localURL) }
            else {
                local=try await qwen.transcribe(audio:file,work:dir.appendingPathComponent("qwen"),
                    input:run.input ?? ConversionNotes(),audioHash:analysis.sha256,durationUs:duration)
                try immutable(local,to:localURL)
            }
            document=try QwenNormalizer.normalize(local,diarization:bytes,sessionID:run.sessionID,runID:run.id,
                durationUs:duration,audioSHA256:analysis.sha256,createdAt:run.createdAt,captureInterrupted:audio.interruption != nil)
        } else if run.provider == .soniox {
            guard let jobID = run.jobID else { throw ManagedFailure.invalidResponse }
            document = try SonioxNormalizer.normalize(bytes, jobID: jobID, sessionID: run.sessionID, runID: run.id,
                durationUs: duration, audioSHA256: analysis.sha256, model: run.reportedModel ?? run.provider.model,
                captureInterrupted: audio.interruption != nil, createdAt: run.createdAt)
        } else {
            document = try ManagedNormalizer.normalize(bytes, sessionID: run.sessionID, runID: run.id,
                durationUs: duration, audioSHA256: analysis.sha256, captureInterrupted: audio.interruption != nil,
                createdAt: run.createdAt)
        }
        try await FileSessionRepository(rootURL: root).importManagedTranscript(document, rawData: bytes)
        run.stage = "readyForReview"; run.failure = nil; try persist(run)
        return run
    }

    private func executeCombined(_ run: inout ManagedRun, audio: AudioManifest, key: String, sonioxKey: String) async throws -> ManagedRun {
        guard let analysis = audio.analysis, var input = run.input else { throw ManagedFailure.sourceChanged }
        let dir = try directory(run), repository = FileSessionRepository(rootURL: root)
        func source(_ id: String, provider: TranscriptionProvider) throws -> ManagedRun {
            guard let result = try runsForSession(run.sessionID).first(where: { $0.id == id }), result.sessionID == run.sessionID,
                  result.provider == provider || (provider == .precision && [.pyannote, .qwen].contains(result.provider)),
                  result.sourceAudioSHA256 == nil || result.sourceAudioSHA256 == analysis.sha256 else { throw ManagedFailure.sourceChanged }
            return result
        }
        func child(_ provider: TranscriptionProvider) throws -> ManagedRun {
            var notes = input; notes.transcriptionProvider = provider; notes.aiCorrection = false
            notes.sonioxSourceRunID = nil; notes.precisionSourceRunID = nil
            let value = ManagedRun(id: UUID().uuidString, sessionID: run.sessionID, createdAt: run.createdAt,
                consent: true, stage: "queued", input: notes, parentRunID: run.id)
            try persist(value)
            return value
        }
        var asr: ManagedRun
        if let id = run.sonioxRunID { asr = try source(id, provider: .soniox) }
        else if let id = input.sonioxSourceRunID {
            guard try reusableSoniox(sessionID: run.sessionID, audioHash: analysis.sha256, input: input) == id else { throw ManagedFailure.sourceChanged }
            asr = try source(id, provider: .soniox)
        } else { asr = try child(.soniox) }
        run.sonioxRunID = asr.id; try persist(run)
        if asr.stage != "readyForReview" {
            guard !["submissionUncertain", "failed", "partialResult", "resultExpired", "unknownRemoteStatus"].contains(asr.stage) else {
                run.stage = asr.stage; run.failure = asr.failure; try persist(run); return run
            }
            asr = try await execute(asr, key: sonioxKey)
        }
        guard asr.stage == "readyForReview" else { run.stage = asr.stage; run.failure = asr.failure; try persist(run); return run }
        try Task.checkCancellation()
        var p2: ManagedRun
        if let id = run.precisionRunID { p2 = try source(id, provider: .precision) }
        else if let id = input.precisionSourceRunID {
            guard try reusableDiarization(sessionID: run.sessionID, audioHash: analysis.sha256, speakerCount: input.speakerCount) == id else { throw ManagedFailure.sourceChanged }
            p2 = try source(id, provider: .precision)
        } else { p2 = try child(.precision) }
        run.precisionRunID = p2.id; try persist(run)
        if p2.stage != "readyForReview" {
            guard !["submissionUncertain", "failed", "partialResult", "resultExpired", "unknownRemoteStatus"].contains(p2.stage) else {
                run.stage = p2.stage; run.failure = p2.failure; try persist(run); return run
            }
            p2 = try await execute(p2, key: key)
        }
        guard p2.stage == "readyForReview" else { run.stage = p2.stage; run.failure = p2.failure; try persist(run); return run }
        guard asr.sourceAudioSHA256 == analysis.sha256, p2.sourceAudioSHA256 == analysis.sha256,
              let jobID = asr.jobID else { throw ManagedFailure.sourceChanged }
        let asrDir = try directory(asr), p2Dir = try directory(p2)
        let asrBytes = try Data(contentsOf: asrDir.appendingPathComponent("raw/soniox-response.json"))
        let p2Bytes = try Data(contentsOf: p2Dir.appendingPathComponent("raw/pyannote-response.json"))
        let rawDir = dir.appendingPathComponent("raw")
        try FileManager.default.createDirectory(at: rawDir, withIntermediateDirectories: true)
        try immutable(asrBytes, to: rawDir.appendingPathComponent("soniox-response.json"))
        try immutable(p2Bytes, to: rawDir.appendingPathComponent("pyannote-response.json"))
        // Source requests are retained independently, including requested/reported model and context.
        for (name, sourceDir) in [("soniox-request.json", asrDir), ("precision-request.json", p2Dir)] {
            if let request = try? Data(contentsOf: sourceDir.appendingPathComponent("request.json")) { try immutable(request, to: dir.appendingPathComponent(name)) }
        }
        input.sonioxSourceRunID = asr.id; input.precisionSourceRunID = p2.id; run.input = input
        run.stage = "normalizing"; run.reportedModel = asr.reportedModel; try persist(run)
        let duration = try AudioFiles.microseconds(frames: analysis.frames, rate: analysis.sampleRate)
        try Task.checkCancellation()
        let document: TranscriptDocument
        if run.combinationAlgorithmVersion == SonioxPrecisionComparison.wordRepair.rawValue {
            document = try SonioxPrecisionReconciler.normalize(soniox: asrBytes, diarization: p2Bytes,
                sonioxJobID: jobID, sessionID: run.sessionID, runID: run.id, durationUs: duration,
                audioSHA256: analysis.sha256, model: asr.reportedModel ?? asr.provider.model,
                createdAt: run.createdAt, captureInterrupted: audio.interruption != nil)
        } else {
            document = try SonioxPrecisionNormalizer.normalize(soniox: asrBytes, diarization: p2Bytes,
                sonioxJobID: jobID, sessionID: run.sessionID, runID: run.id, durationUs: duration,
                audioSHA256: analysis.sha256, model: asr.reportedModel ?? asr.provider.model,
                createdAt: run.createdAt, captureInterrupted: audio.interruption != nil)
        }
        try Task.checkCancellation()
        try await repository.importManagedTranscript(document, rawData: asrBytes)
        run.stage = "readyForReview"; run.failure = nil; try persist(run)
        return run
    }
    private func executeSoniox(_ run: inout ManagedRun, audio: AudioManifest, file: URL,
                               dir: URL, rawDir: URL, key: String) async throws -> ManagedRun {
        guard audio.durationUs <= SonioxRequest.maximumDurationUs else { throw ManagedFailure.audioTooLong }
        struct Remote: Decodable { let id: String; let status: String; let model: String? }
        if run.jobID == nil {
            if run.uploadedFileID == nil {
                run.stage = "uploadSubmitting"; run.retryAt = nil; try persist(run)
                let upload = try await soniox.upload(file: file, key: key)
                try immutable(upload.data, to: rawDir.appendingPathComponent("upload-\(UUID().uuidString).json"))
                guard (200..<300).contains(upload.status) else { return try httpFailure(upload, run: run, submitting: true) }
                struct Uploaded: Decodable { let id: String }
                let uploaded = try JSONDecoder().decode(Uploaded.self, from: upload.data)
                guard UUID(uuidString: uploaded.id) != nil else { throw ManagedFailure.invalidResponse }
                run.uploadedFileID = uploaded.id; run.stage = "uploaded"; try persist(run)
            }
            guard let fileID = run.uploadedFileID else { throw ManagedFailure.invalidResponse }
            let request = try SonioxRequest.payload(fileID: fileID, runID: run.id, input: run.input ?? ConversionNotes())
            try immutable(request, to: dir.appendingPathComponent("request.json"))
            run.attemptID = UUID().uuidString
            run.requestHash = SHA256.hash(data: request).map { String(format: "%02x", $0) }.joined()
            run.stage = "submitting"; try persist(run)
            let accepted = try await soniox.api(path: "/v1/transcriptions", method: "POST", body: request, key: key)
            try immutable(accepted.data, to: rawDir.appendingPathComponent("submission-\(UUID().uuidString).json"))
            guard (200..<300).contains(accepted.status) else { return try httpFailure(accepted, run: run, submitting: true) }
            let remote = try JSONDecoder().decode(Remote.self, from: accepted.data)
            guard UUID(uuidString: remote.id) != nil else { throw ManagedFailure.invalidResponse }
            run.jobID = remote.id; run.reportedModel = remote.model; run.remoteStatus = remote.status
            run.stage = "remotePending"; try persist(run)
        }
        var attempt = 0, failures = 0
        while !Task.isCancelled {
            guard let jobID = run.jobID, UUID(uuidString: jobID) != nil else { throw ManagedFailure.invalidResponse }
            run.stage = "remotePending"; try persist(run)
            let reply: HTTPReply
            do { reply = try await soniox.api(path: "/v1/transcriptions/\(jobID)", method: "GET", body: nil, key: key) }
            catch {
                if error is CancellationError { throw error }
                failures += 1
                if failures >= 3 { run.stage = "waitingForNetwork"; try persist(run); return run }
                try await sleep(PollDelay.seconds(retryAfter: nil, attempt: failures)); continue
            }
            if reply.status == 429 || reply.status >= 500 {
                failures += 1
                if failures >= 3 { return try httpFailure(reply, run: run, submitting: false) }
                try await sleep(PollDelay.seconds(retryAfter: reply.retryAfter, attempt: failures)); continue
            }
            if reply.status == 404 || reply.status == 410 { run.stage = "resultExpired"; try persist(run); return run }
            guard (200..<300).contains(reply.status) else { return try httpFailure(reply, run: run, submitting: false) }
            try immutable(reply.data, to: rawDir.appendingPathComponent("poll-\(UUID().uuidString).json"))
            let remote = try JSONDecoder().decode(Remote.self, from: reply.data)
            guard remote.id == jobID else { throw ManagedFailure.invalidResponse }
            run.remoteStatus = remote.status; run.lastServerCheckAt = Date()
            if let model = remote.model { run.reportedModel = model }
            failures = 0
            try persist(run)
            switch remote.status {
            case "completed":
                let transcript = try await soniox.api(path: "/v1/transcriptions/\(jobID)/transcript", method: "GET", body: nil, key: key)
                if transcript.status == 404 || transcript.status == 410 { run.stage = "resultExpired"; try persist(run); return run }
                guard (200..<300).contains(transcript.status) else { return try httpFailure(transcript, run: run, submitting: false) }
                try immutable(transcript.data, to: rawDir.appendingPathComponent(run.provider.rawFilename))
                return try await normalize(&run, audio: audio, bytes: transcript.data)
            case "error": run.stage = "failed"; try persist(run); return run
            case "queued", "processing": break
            default: run.stage = "unknownRemoteStatus"; try persist(run); return run
            }
            try await sleep(PollDelay.seconds(retryAfter: reply.retryAfter, attempt: attempt))
            attempt += 1
        }
        throw CancellationError()
    }
    private func httpFailure(_ reply: HTTPReply, run original: ManagedRun, submitting: Bool) throws -> ManagedRun {
        var run = original
        switch reply.status {
        case 401, 403: run.stage = "waitingForCredentials"
        case 402: run.stage = "waitingForBilling"
        case 429: run.stage = "waitingForNetwork"
        case 400: run.stage = "failed"
        default: run.stage = submitting ? "submissionUncertain" : "waitingForNetwork"
        }
        run.failure = "http\(reply.status)"
        if reply.status == 429 { run.retryAt = Date().addingTimeInterval(PollDelay.seconds(retryAfter: reply.retryAfter, attempt: 0)) }
        try persist(run)
        return run
    }
}

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
    private let sleep: @Sendable (Double) async throws -> Void
    private var active = false
    public init(root: URL, transport: any ManagedTransport = PyannoteTransport(),
                sleep: @escaping @Sendable (Double) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }) {
        self.root = root.standardizedFileURL
        self.transport = transport
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
        try JSONEncoder().encode(run).write(to: directory.appendingPathComponent("state.json"), options: .atomic)
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
        let sessions = root.appendingPathComponent("Sessions")
        guard FileManager.default.fileExists(atPath: sessions.path) else { return [] }
        var result: [ManagedRun] = []
        for session in try FileManager.default.contentsOfDirectory(at: sessions, includingPropertiesForKeys: nil) {
            guard UUID(uuidString: session.lastPathComponent) != nil else { continue }
            let runs = try AudioFiles.session(session.lastPathComponent, root: root).appendingPathComponent("runs")
            guard FileManager.default.fileExists(atPath: runs.path) else { continue }
            for directory in try FileManager.default.contentsOfDirectory(at: runs, includingPropertiesForKeys: nil) {
                guard UUID(uuidString: directory.lastPathComponent) != nil else { continue }
                let file = directory.appendingPathComponent("state.json").standardizedFileURL
                guard file.resolvingSymlinksInPath().path == file.path else { throw ManagedFailure.unsafePath }
                guard FileManager.default.fileExists(atPath: file.path) else { continue }
                var run = try JSONDecoder().decode(ManagedRun.self, from: Data(contentsOf: file))
                guard run.id == directory.lastPathComponent, run.sessionID == session.lastPathComponent else { throw ManagedFailure.unsafePath }
                if recover && !active && run.stage == "submitting" && run.jobID == nil {
                    run.stage = "submissionUncertain"
                    try persist(run)
                }
                result.append(run)
            }
        }
        return result.sorted { $0.creationDate == $1.creationDate ? $0.id > $1.id : $0.creationDate > $1.creationDate }
    }
    public func isLocalOnly(_ sessionID: String) throws -> Bool {
        let file = try AudioFiles.session(sessionID, root: root).appendingPathComponent("audio/never-upload.json")
        guard file.resolvingSymlinksInPath().path == file.path else { throw ManagedFailure.unsafePath }
        return FileManager.default.fileExists(atPath: file.path)
    }
    public func setLocalOnly(_ sessionID: String) throws {
        guard !active, try !runs().contains(where: { $0.sessionID == sessionID }) else { throw ManagedFailure.busy }
        let file = try AudioFiles.session(sessionID, root: root).appendingPathComponent("audio/never-upload.json")
        try immutable(Data("{\"neverUpload\":true}".utf8), to: file)
    }

    public func begin(sessionID: String, confirmed: Bool, key: String, input: ConversionNotes = ConversionNotes(), retranscribing: Bool = false) async throws -> ManagedRun {
        try input.validate()
        guard confirmed, try !isLocalOnly(sessionID) else { throw ManagedFailure.consentRequired }
        guard !active else { throw ManagedFailure.busy }
        let previous = try runs(recover: true).filter { $0.sessionID == sessionID }
        guard previous.isEmpty || (retranscribing && previous.allSatisfy(\.canRetranscribe)) else { throw ManagedFailure.existingRun }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let run = ManagedRun(id: UUID().uuidString, sessionID: sessionID,
                             createdAt: formatter.string(from: Date()), consent: true, stage: "queued", input: input)
        try persist(run)
        return try await execute(run, key: key)
    }
    public func resume(_ id: String, key: String) async throws -> ManagedRun {
        guard !active else { throw ManagedFailure.busy }
        guard let run = try runs(recover: true).first(where: { $0.id == id }),
              !["submissionUncertain", "readyForReview", "failed", "partialResult", "resultExpired", "unknownRemoteStatus"].contains(run.stage)
        else { throw ManagedFailure.existingRun }
        return try await execute(run, key: key)
    }

    private func execute(_ input: ManagedRun, key: String) async throws -> ManagedRun {
        guard input.consent, try !isLocalOnly(input.sessionID) else { throw ManagedFailure.consentRequired }
        active = true
        defer { active = false }
        var run = input
        guard !key.isEmpty else { run.stage = "waitingForCredentials"; try persist(run); return run }
        do {
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
            let dir = try directory(run)
            let rawDir = dir.appendingPathComponent("raw")
            try FileManager.default.createDirectory(at: rawDir, withIntermediateDirectories: true)
            let rawURL = rawDir.appendingPathComponent("pyannote-response.json")
            if FileManager.default.fileExists(atPath: rawURL.path) {
                return try await normalize(&run, audio: audio, bytes: Data(contentsOf: rawURL))
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
            if run.stage == "submitting" && run.jobID == nil { run.stage = "submissionUncertain" }
            else if error is CancellationError { run.stage = "paused" }
            else if error is ManagedNormalizationError || error is TranscriptContractError || error is DecodingError { run.stage = "partialResult" }
            else if error is URLError { run.stage = "waitingForNetwork" }
            else { run.stage = "failed" }
            run.failure = (error as? ManagedFailure)?.rawValue ?? (error as? AudioFailure)?.rawValue ?? "operationFailed"
            try persist(run)
            return run
        }
    }

    private func normalize(_ run: inout ManagedRun, audio: AudioManifest, bytes: Data) async throws -> ManagedRun {
        run.stage = "normalizing"; try persist(run)
        guard let analysis = audio.analysis else { throw ManagedFailure.sourceChanged }
        let duration = try AudioFiles.microseconds(frames: analysis.frames, rate: analysis.sampleRate)
        let document = try ManagedNormalizer.normalize(bytes, sessionID: run.sessionID, runID: run.id,
            durationUs: duration, audioSHA256: analysis.sha256, captureInterrupted: audio.interruption != nil,
            createdAt: run.createdAt)
        try await FileSessionRepository(rootURL: root).importManagedTranscript(document, rawData: bytes)
        run.stage = "readyForReview"; run.failure = nil; try persist(run)
        return run
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

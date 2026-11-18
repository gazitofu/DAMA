import DamaCore
import Foundation

/// usage-bundle1 교정 시도 기록 저장소: `<내부 root>/CorrectionAttempts/<scriptID>.json`, 원자 쓰기.
/// 경로 규칙은 `InternalStoragePaths`(DamaCore)와 같다. 스크립트를 지우면 `FolderLibraryStore`가 함께 지운다(usage-bundle2).
public struct CorrectionAttemptStore: Sendable {
    public let root: URL
    public init(root: URL) { self.root = root.standardizedFileURL }
    public var folder: URL { root.appendingPathComponent(InternalStoragePaths.correctionAttemptsFolder, isDirectory: true) }

    func url(_ scriptID: String) throws -> URL {
        try InternalStoragePaths.correctionAttemptURL(root: root, scriptID: scriptID)
    }
    public func load(scriptID: String) throws -> CorrectionAttempt? {
        let url = try url(scriptID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let attempt = try JSONDecoder().decode(CorrectionAttempt.self, from: Data(contentsOf: url))
        guard attempt.formatVersion == CorrectionAttempt.currentFormatVersion, attempt.scriptID == scriptID else { throw LibraryFailure.invalidScript }
        return attempt
    }
    public func save(_ attempt: CorrectionAttempt) throws {
        let url = try url(attempt.scriptID)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(attempt).write(to: url, options: .atomic)
    }
    public func delete(scriptID: String) throws {
        let url = try url(scriptID)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}

/// 교정 실행 (usage-bundle1 · turn-continuity context-correction-8): 청크를 순서대로 보내고 성공마다 시도 기록에 더한다.
/// 실패마다 실패 기록을 더한다. 형식은 바로, 시간 초과·네트워크·미분류는 5초 뒤 같은 청크를 최대 2회 다시 보내고(확인창 없음,
/// 시작 때 확인한 같은 입력), 그래도 실패한 청크는 건너뛰고 다음 청크로 간다. 인증·설정·실행 불가·취소, 연속 2개 청크 건너뜀이면
/// 멈춘다(건너뛴 청크는 남은 청크로 남아 이어서 교정이 다시 보낸다). 끝까지 가면 건너뛴 청크마다 원문 유지 결과(`chunk`)를
/// 반환 기록에만 더한다(저장소에는 쓰지 않는다). 앱(`CorrectionWorkspace`)은 이것을 부른다.
public struct CorrectionRunner: Sendable {
    /// 엔진 문자열 = Codex CLI · 모델 · 교정 반영 정책 버전. 이어서 교정은 이 값이 같을 때만.
    public static var engine: String { "Codex CLI · \(CodexCorrectionClient.modelTitle) · " + ContextCorrection.version }
    /// 재시도 값 (turn-continuity 신규 후보값): 청크당 최대 2회 · 형식 외 5초 대기 · 연속 2개 청크 건너뜀이면 멈춤.
    public static let maximumRetries = 2
    public static let retryDelay: Duration = .seconds(5)
    public static let consecutiveSkipLimit = 2

    public enum Resume: Equatable, Sendable {
        /// 시도 기록 없음 또는 남은 청크 없음.
        case none
        /// 이어서 교정 가능. completed == 0이면 «같은 입력으로 다시 시도».
        case available(completed: Int, total: Int, lastFailure: CorrectionFailureRecord?)
        /// 청크 계획·엔진 불일치(문구 16). 기록은 새 교정을 시작할 때까지 남는다.
        case planChanged(completed: Int, total: Int, lastFailure: CorrectionFailureRecord?)
    }
    public enum Outcome: Sendable {
        case completed(CorrectionAttempt)
        case failed(CorrectionAttempt, CodexCorrectionError)
    }

    public let store: CorrectionAttemptStore
    public let executable: URL
    public let timeout: Duration
    private let client: CodexCorrectionClient
    /// 재시도 전 대기. 테스트는 기록용으로 바꾼다. throw하면 취소로 멈춘다.
    private let wait: @Sendable (Duration) async throws -> Void
    public init(store: CorrectionAttemptStore, executable: URL, timeout: Duration = .seconds(300), client: CodexCorrectionClient = CodexCorrectionClient(),
                wait: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.store = store; self.executable = executable; self.timeout = timeout; self.client = client; self.wait = wait
    }

    /// 새 교정: 기존 시도 기록을 버리고 새 시도를 만든다(문구 19 고지는 화면 몫).
    public func begin(script: LibraryScript, input: ConversionNotes, engine: String = Self.engine) throws -> (CorrectionAttempt, [CorrectionChunk]) {
        let chunks = try CorrectionPlan.chunks(for: script)
        guard !chunks.isEmpty else { throw LibraryFailure.invalidInput }
        try store.delete(scriptID: script.id)
        let attempt = CorrectionAttempt(scriptID: script.id, engine: engine, input: input,
            planSHA256: try CorrectionPlan.sha256(chunks), chunkSHA256s: try CorrectionPlan.chunkSHA256s(chunks))
        try store.save(attempt)
        return (attempt, chunks)
    }

    /// 모든 청크 결과를 스크립트에 저장한 직후 기록을 지운다.
    public func discard(scriptID: String) throws { try store.delete(scriptID: scriptID) }

    /// 지금 스크립트로 다시 만든 청크 계획과 엔진이 기록과 같은지 본다.
    public func resumeState(for script: LibraryScript, engine: String = Self.engine) -> Resume {
        guard let attempt = try? store.load(scriptID: script.id), !attempt.remainingChunks.isEmpty else { return .none }
        let completed = attempt.completedChunks, total = attempt.totalChunks, last = attempt.lastFailure
        guard attempt.engine == engine, let chunks = try? CorrectionPlan.chunks(for: script),
              (try? CorrectionPlan.sha256(chunks)) == attempt.planSHA256 else { return .planChanged(completed: completed, total: total, lastFailure: last) }
        return .available(completed: completed, total: total, lastFailure: last)
    }

    /// 이어서 교정 준비: 계획·엔진이 같을 때만. 입력은 기록된 스냅숏이다.
    public func prepareResume(script: LibraryScript, engine: String = Self.engine) throws -> (CorrectionAttempt, [CorrectionChunk]) {
        guard let attempt = try store.load(scriptID: script.id), !attempt.remainingChunks.isEmpty, attempt.engine == engine else {
            throw LibraryFailure.invalidInput
        }
        let chunks = try CorrectionPlan.chunks(for: script)
        guard try CorrectionPlan.sha256(chunks) == attempt.planSHA256 else { throw LibraryFailure.changedFile }
        return (attempt, chunks)
    }

    /// 남은 청크만 순서대로 보낸다. `progress`는 끝난 청크 수(기록된 성공 + 이번에 건너뛴 청크)를 받는다.
    /// `retrying`은 같은 청크를 다시 보내기 직전에 재시도 차수(1 · 2)를, 그 청크가 끝나면 nil을 받는다.
    public func run(_ start: CorrectionAttempt, chunks: [CorrectionChunk],
                    progress: @Sendable (Int) async -> Void = { _ in },
                    retrying: @Sendable (Int?) async -> Void = { _ in }) async -> Outcome {
        var attempt = start
        var skipped: [Int] = [], consecutive = 0, lastError: CodexCorrectionError?
        func record(_ error: CodexCorrectionError, chunk index: Int, retry: Int) {
            attempt.record(CorrectionFailureRecord(chunkIndex: index, totalChunks: attempt.totalChunks, kind: error.kind,
                exitCode: error.exitCode, elapsedMs: error.elapsedMs, stderrBytes: error.stderrBytes, retry: retry,
                detail: error.detail, expectedTurns: error.expectedTurns, returnedTurns: error.returnedTurns))
            try? store.save(attempt)
        }
        for index in attempt.remainingChunks {
            guard chunks.indices.contains(index) else {
                let error = CodexCorrectionError(kind: .unclassified)
                record(error, chunk: index, retry: 0); return .failed(attempt, error)
            }
            var retry = 0
            sending: while true {
                switch await send(chunks[index], index: index, input: attempt.input) {
                case .success(let result):
                    attempt.record(result)
                    do { try store.save(attempt) } catch {
                        let error = CodexCorrectionError(kind: .unclassified)
                        record(error, chunk: index, retry: retry)
                        if retry > 0 { await retrying(nil) }
                        return .failed(attempt, error)
                    }
                    consecutive = 0
                    if retry > 0 { await retrying(nil) }
                    await progress(attempt.completedChunks + skipped.count)
                    break sending
                case .failure(let error):
                    record(error, chunk: index, retry: retry); lastError = error
                    guard ![.cancelled, .unavailable, .auth, .config].contains(error.kind) else {
                        if retry > 0 { await retrying(nil) }
                        return .failed(attempt, error)
                    }
                    if retry < Self.maximumRetries {
                        retry += 1
                        await retrying(retry)
                        if error.kind != .format {
                            do { try await wait(Self.retryDelay) } catch {
                                let cancelled = CodexCorrectionError(kind: .cancelled)
                                record(cancelled, chunk: index, retry: retry); await retrying(nil)
                                return .failed(attempt, cancelled)
                            }
                        }
                        continue sending
                    }
                    await retrying(nil)
                    skipped.append(index); consecutive += 1
                    await progress(attempt.completedChunks + skipped.count)
                    if consecutive >= Self.consecutiveSkipLimit { return .failed(attempt, error) }
                    break sending
                }
            }
        }
        guard !skipped.isEmpty else { return .completed(attempt) }
        // 성공한 청크가 하나도 없으면 실패다(시도 기록에는 건너뛴 청크를 끝난 청크로 쓰지 않았다).
        guard !attempt.results.isEmpty else { return .failed(attempt, lastError ?? CodexCorrectionError(kind: .unclassified)) }
        for index in skipped {
            attempt.record(CorrectionChunkResult(chunkIndex: index, edits: [], names: [:], evidence: [:],
                rejected: chunks[index].turns.map { CorrectionRejectedTurn(turnID: $0.id, rule: .chunk) }))
        }
        return .completed(attempt)
    }

    /// 청크 1회 전송과 응답 짝짓기·검증. 짝지을 수 없으면 형식 실패(세부 포함).
    private func send(_ chunk: CorrectionChunk, index: Int, input: ConversionNotes) async -> Result<CorrectionChunkResult, CodexCorrectionError> {
        if Task.isCancelled { return .failure(CodexCorrectionError(kind: .cancelled)) }
        do {
            let result = try await client.correct(chunk: chunk, input: input, executable: executable, timeout: timeout)
            func format(_ detail: CorrectionFormatDetail?) -> CodexCorrectionError {
                let ids: Set<CorrectionFormatDetail> = [.idDuplicate, .idUnknown, .idOrder, .idTooFew]
                let counted = detail.map(ids.contains) ?? false
                return CodexCorrectionError(kind: .format, exitCode: 0, elapsedMs: result.elapsedMs, stderrBytes: result.stderrBytes,
                    detail: detail, expectedTurns: counted ? chunk.turns.count : nil, returnedTurns: counted ? result.reply.turns.count : nil)
            }
            if let detail = ContextCorrection.replyMismatch(result.reply, chunk: chunk) { return .failure(format(detail)) }
            guard let validated = try? ContextCorrection.validated(result.reply, chunk: chunk, input: input) else { return .failure(format(nil)) }
            return .success(CorrectionChunkResult(chunkIndex: index, edits: validated.edits, names: validated.names,
                                                  evidence: validated.evidence, rejected: validated.rejected))
        } catch let error as CodexCorrectionError {
            return .failure(error)
        } catch {
            return .failure(CodexCorrectionError(kind: .unclassified))
        }
    }
}

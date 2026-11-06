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

/// usage-bundle1 교정 실행: 청크를 순서대로 보내고, 성공마다 시도 기록에 더하며, 실패하면 실패 기록을 더하고 멈춘다.
/// 자동 재시도는 없다. 이어서 교정은 사용자가 확인창을 거쳐 부른다. 앱(`CorrectionWorkspace`)은 이것을 부른다.
public struct CorrectionRunner: Sendable {
    /// 엔진 문자열 = Codex CLI · 모델 · 교정 반영 정책 버전. 이어서 교정은 이 값이 같을 때만.
    public static var engine: String { "Codex CLI · \(CodexCorrectionClient.modelTitle) · " + ContextCorrection.version }

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
    public init(store: CorrectionAttemptStore, executable: URL, timeout: Duration = .seconds(300), client: CodexCorrectionClient = CodexCorrectionClient()) {
        self.store = store; self.executable = executable; self.timeout = timeout; self.client = client
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

    /// 남은 청크만 순서대로 보낸다. `progress`는 끝난 청크 수(기록 포함)를 받는다.
    public func run(_ start: CorrectionAttempt, chunks: [CorrectionChunk],
                    progress: @Sendable (Int) async -> Void = { _ in }) async -> Outcome {
        var attempt = start
        for index in attempt.remainingChunks {
            func fail(_ error: CodexCorrectionError) -> Outcome {
                attempt.record(CorrectionFailureRecord(chunkIndex: index, totalChunks: attempt.totalChunks, kind: error.kind,
                    exitCode: error.exitCode, elapsedMs: error.elapsedMs, stderrBytes: error.stderrBytes))
                try? store.save(attempt)
                return .failed(attempt, error)
            }
            guard chunks.indices.contains(index) else { return fail(CodexCorrectionError(kind: .unclassified)) }
            if Task.isCancelled { return fail(CodexCorrectionError(kind: .cancelled)) }
            do {
                let result = try await client.correct(chunk: chunks[index], input: attempt.input, executable: executable, timeout: timeout)
                guard let validated = try? ContextCorrection.validated(result.reply, chunk: chunks[index], input: attempt.input) else {
                    // 응답 검증(ContextCorrection.validated) 실패 = 형식.
                    return fail(CodexCorrectionError(kind: .format, exitCode: 0, elapsedMs: result.elapsedMs, stderrBytes: result.stderrBytes))
                }
                attempt.record(CorrectionChunkResult(chunkIndex: index, edits: validated.edits, names: validated.names, evidence: validated.evidence))
                do { try store.save(attempt) } catch { return fail(CodexCorrectionError(kind: .unclassified)) }
                await progress(attempt.completedChunks)
            } catch let error as CodexCorrectionError {
                return fail(error)
            } catch {
                return fail(CodexCorrectionError(kind: .unclassified))
            }
        }
        return .completed(attempt)
    }
}

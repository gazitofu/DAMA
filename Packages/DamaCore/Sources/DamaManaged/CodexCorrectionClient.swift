import Foundation
import DamaCore
import Darwin

/// usage-bundle1 교정 실패 1건. 원문·stderr 내용·프롬프트는 담지 않는다(분류·종료 코드·경과·바이트 수만).
public struct CodexCorrectionError: Error, Sendable, Equatable {
    public let kind: CorrectionFailureKind
    /// 프로세스 종료 코드(신호 종료면 신호 번호). 시간 초과·실행 불가·취소는 nil.
    public let exitCode: Int32?
    public let signaled: Bool
    /// 청크 시작부터 실패 판정까지 경과 ms (절삭, 0 이상).
    public let elapsedMs: Int64
    /// stderr 전체 바이트 수.
    public let stderrBytes: Int
    public init(kind: CorrectionFailureKind, exitCode: Int32? = nil, signaled: Bool = false, elapsedMs: Int64 = 0, stderrBytes: Int = 0) {
        self.kind = kind; self.exitCode = exitCode; self.signaled = signaled; self.elapsedMs = elapsedMs; self.stderrBytes = stderrBytes
    }
}

/// 성공한 청크 1회. 응답과 측정값.
public struct CodexCorrectionResult: Sendable {
    public let reply: CorrectionReply
    public let elapsedMs: Int64
    public let stderrBytes: Int
}

/// stderr 줄 단위 분류 표식 대조 (D-02 ⓐ). 줄 시작이 `ERROR: `·`error: `인 줄만 보고, 줄 버퍼는 64 KiB에서 자르며
/// 대조 직후 버린다. 내용은 어디에도 남기지 않는다. 표식은 Codex CLI 0.166.0 실측(plan 실측 1·4·5·7).
struct StderrScan: Sendable, Equatable {
    static let lineLimit = 65_536
    private(set) var bytes = 0
    private(set) var auth = false
    private(set) var network = false
    private(set) var unsupportedModel = false
    private(set) var unexpectedArgument = false
    private var line: [UInt8] = []

    mutating func consume<S: Sequence>(_ chunk: S) where S.Element == UInt8 {
        for byte in chunk {
            bytes += 1
            if byte == 0x0A { endLine() } else if line.count < Self.lineLimit { line.append(byte) }
        }
    }
    mutating func finish() { if !line.isEmpty { endLine() } }
    private mutating func endLine() {
        defer { line.removeAll(keepingCapacity: true) }
        if line.last == 0x0D { line.removeLast() }
        let text = String(decoding: line, as: UTF8.self)
        if text.hasPrefix("ERROR: ") {
            if text.contains("401 Unauthorized") { auth = true }
            if text.contains("Reconnecting... waiting for network") { network = true }
            if text.contains("model is not supported") { unsupportedModel = true }
        } else if text.hasPrefix("error: unexpected argument") {
            unexpectedArgument = true
        }
    }

    /// 분류 (스펙 §02-3 표 순서, D-01 ⓐ 예외 1줄). 취소·실행 불가·형식은 호출자가 정한다.
    static func classify(timedOut: Bool, exitStatus: Int32?, signaled: Bool, scan: StderrScan) -> CorrectionFailureKind {
        if timedOut { return scan.network ? .network : .timeout }
        guard !signaled, let status = exitStatus, status != 0 else { return .unclassified }
        if scan.auth { return .auth }
        if scan.network { return .network }
        if (status == 2 && scan.unexpectedArgument) || scan.unsupportedModel { return .config }
        return .unclassified
    }
}

/// stderr를 끝까지 읽어 바이트 수를 세고 줄을 대조하는 별도 스레드. 상태는 잠금 안에서만 바꾼다.
final class StderrMonitor: @unchecked Sendable {
    private let lock = NSLock()
    private var scan = StderrScan()
    private var done = false
    init(_ handle: FileHandle) {
        // 읽기 스레드가 핸들을 소유하고 EOF·오류 뒤에 닫는다(다른 스레드가 읽는 중에 닫지 않는다).
        // POSIX read는 쌓인 만큼 바로 돌려준다(FileHandle.read(upToCount:)는 개수를 채우거나 EOF까지 기다림).
        let thread = Thread { [self] in
            let fd = handle.fileDescriptor
            var buffer = [UInt8](repeating: 0, count: 65_536)
            while true {
                let count = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
                if count > 0 { lock.withLock { scan.consume(buffer[0..<count]) } }
                else if count < 0 && errno == EINTR { continue }
                else { break }
            }
            try? handle.close()
            lock.withLock { scan.finish(); done = true }
        }
        thread.qualityOfService = .utility
        thread.start()
    }
    var snapshot: StderrScan { lock.withLock { scan } }
    var finished: Bool { lock.withLock { done } }
    /// EOF까지 기다린다. `deadline`이 지나거나 취소되면 false (그때까지 센 값은 `snapshot`).
    /// 정상 종료 경로는 청크 제한 시각까지 기다려 바이트를 끝까지 센다(QA C D-2). 강제 종료 경로만 짧게 기다린다.
    func settle(until deadline: ContinuousClock.Instant) async -> Bool {
        while !finished {
            if ContinuousClock.now >= deadline || Task.isCancelled { return false }
            await Task.detached { try? await Task.sleep(for: .milliseconds(20)) }.value
        }
        return true
    }
}

/// A product adapter, never an implementation/delegation agent. No shell interpolation.
public actor CodexCorrectionClient {
    public static let model = "gpt-5.6-luna"
    public static let modelTitle = "GPT-5.6 Luna"
    public init() {}
    public static func arguments(directory: URL, schema: URL, output: URL) -> [String] {
        var args = ["exec", "--ignore-user-config", "--ignore-rules", "--ephemeral", "--sandbox", "read-only",
                    "--skip-git-repo-check", "--cd", directory.path, "--color", "never",
                    "--model", model, "--output-schema", schema.path, "--output-last-message", output.path]
        for config in ["approval_policy=\"never\"", "model_reasoning_effort=\"medium\"", "web_search=\"disabled\"", "project_doc_max_bytes=0",
                       "features.shell_tool=false", "features.unified_exec=false", "features.apps=false",
                       "features.multi_agent=false", "features.hooks=false", "features.memories=false",
                       "features.plugins=false", "features.skill_search=false", "features.skill_mcp_dependency_install=false",
                       "features.shell_snapshot=false", "features.goals=false", "features.view_image=false",
                       "features.skip_host_skill_discovery=true",
                       "features.code_mode=false", "features.code_mode_host=false", "features.image_generation=false",
                       "history.persistence=\"none\"", "mcp_servers={}"] {
            args += ["-c", config]
        }
        return args + ["-"]
    }
    /// Duration → ms (절삭, 0 이상). 단위: 내부 Duration(초+아토초) → Int64 ms.
    public static func milliseconds(_ duration: Duration) -> Int64 {
        let parts = duration.components
        return max(0, parts.seconds * 1_000 + parts.attoseconds / 1_000_000_000_000_000)
    }
    public func correct(chunk: CorrectionChunk, input: ConversionNotes, executable: URL,
                        timeout: Duration = .seconds(300)) async throws -> CodexCorrectionResult {
        let started = ContinuousClock.now
        func failure(_ kind: CorrectionFailureKind, exitCode: Int32? = nil, signaled: Bool = false, stderrBytes: Int = 0) -> CodexCorrectionError {
            CodexCorrectionError(kind: kind, exitCode: exitCode, signaled: signaled,
                                 elapsedMs: Self.milliseconds(started.duration(to: .now)), stderrBytes: stderrBytes)
        }
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw failure(.unavailable) }
        guard !Task.isCancelled else { throw failure(.cancelled) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("dama-correction-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = directory.appendingPathComponent("schema.json"), output = directory.appendingPathComponent("result.json")
        let prompt = directory.appendingPathComponent("input.json")
        try ContextCorrection.outputSchema.write(to: schema)
        try ContextCorrection.prompt(chunk: chunk, input: input).write(to: prompt)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: prompt.path)
        let stdin = try FileHandle(forReadingFrom: prompt)
        defer { try? stdin.close() }
        let process = Process()
        process.executableURL = executable; process.currentDirectoryURL = directory
        process.arguments = Self.arguments(directory: directory, schema: schema, output: output)
        process.standardInput = stdin
        // stdout은 버린다. stderr는 파이프로 끝까지 읽어 바이트 수와 분류 표식만 메모리에서 보고 버린다(로그·파일·화면 없음).
        let errors = Pipe()
        process.standardOutput = FileHandle.nullDevice; process.standardError = errors
        do { try process.run() } catch {
            try? errors.fileHandleForWriting.close(); try? errors.fileHandleForReading.close()
            throw failure(.unavailable)
        }
        try? errors.fileHandleForWriting.close()
        let monitor = StderrMonitor(errors.fileHandleForReading)
        let deadline = ContinuousClock.now + timeout
        var stop: CorrectionFailureKind?
        while process.isRunning {
            if Task.isCancelled { stop = .cancelled; break }
            if ContinuousClock.now >= deadline { stop = .timeout; break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        if let stop {
            if process.isRunning { process.terminate() }
            for _ in 0..<10 where process.isRunning {
                await Task.detached { try? await Task.sleep(for: .milliseconds(100)) }.value
            }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            // 강제 종료 뒤에는 2초만 기다린다(자식이 stderr를 붙잡아도 취소·시간 초과 보고를 늦추지 않는다).
            _ = await monitor.settle(until: .now + .seconds(2))
            let scan = monitor.snapshot
            if stop == .cancelled { throw failure(.cancelled, stderrBytes: scan.bytes) }
            throw failure(StderrScan.classify(timedOut: true, exitStatus: nil, signaled: false, scan: scan), stderrBytes: scan.bytes)
        }
        // 프로세스가 끝나도 stderr를 붙잡은 자식이 있으면 EOF가 늦다. 청크 제한 시각까지 끝까지 읽는다.
        guard await monitor.settle(until: deadline) else {
            let scan = monitor.snapshot
            if Task.isCancelled { throw failure(.cancelled, stderrBytes: scan.bytes) }
            throw failure(StderrScan.classify(timedOut: true, exitStatus: nil, signaled: false, scan: scan), stderrBytes: scan.bytes)
        }
        let scan = monitor.snapshot
        let signaled = process.terminationReason == .uncaughtSignal, status = process.terminationStatus
        guard !signaled, status == 0 else {
            throw failure(StderrScan.classify(timedOut: false, exitStatus: status, signaled: signaled, scan: scan),
                          exitCode: status, signaled: signaled, stderrBytes: scan.bytes)
        }
        guard let handle = try? FileHandle(forReadingFrom: output) else { throw failure(.format, exitCode: 0, stderrBytes: scan.bytes) }
        defer { try? handle.close() }
        guard let bytes = try? handle.read(upToCount: 2_000_001), bytes.count <= 2_000_000,
              let reply = try? JSONDecoder().decode(CorrectionReply.self, from: bytes),
              reply.turns.allSatisfy({ $0.changes != nil && $0.unresolved != nil }) else { throw failure(.format, exitCode: 0, stderrBytes: scan.bytes) }
        return CodexCorrectionResult(reply: reply, elapsedMs: Self.milliseconds(started.duration(to: .now)), stderrBytes: scan.bytes)
    }
}

import Foundation
import DamaCore
import Darwin

public enum CodexCorrectionFailure: Error, Sendable { case unavailable, failed, timeout, invalidResponse }

/// A product adapter, never an implementation/delegation agent. No shell interpolation.
public actor CodexCorrectionClient {
    public init() {}
    public static func arguments(directory: URL, schema: URL, output: URL) -> [String] {
        var args = ["exec", "--ignore-user-config", "--ignore-rules", "--ephemeral", "--sandbox", "read-only",
                    "--skip-git-repo-check", "--cd", directory.path, "--color", "never",
                    "--output-schema", schema.path, "--output-last-message", output.path]
        for config in ["approval_policy=\"never\"", "web_search=\"disabled\"", "project_doc_max_bytes=0",
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
    public func correct(chunk: CorrectionChunk, input: ConversionNotes, executable: URL,
                        timeout: Duration = .seconds(300)) async throws -> CorrectionReply {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw CodexCorrectionFailure.unavailable }
        try Task.checkCancellation()
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
        // Codex diagnostic streams can contain source text/credentials; never forward them to application logs.
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { throw CodexCorrectionFailure.unavailable }
        let deadline = ContinuousClock.now + timeout
        do {
            while process.isRunning {
                try Task.checkCancellation()
                guard ContinuousClock.now < deadline else { throw CodexCorrectionFailure.timeout }
                try await Task.sleep(for: .milliseconds(100))
            }
        } catch {
            if process.isRunning { process.terminate() }
            for _ in 0..<10 where process.isRunning {
                await Task.detached { try? await Task.sleep(for: .milliseconds(100)) }.value
            }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            throw error
        }
        guard process.terminationReason == .exit, process.terminationStatus == 0 else { throw CodexCorrectionFailure.failed }
        guard let handle = try? FileHandle(forReadingFrom: output) else { throw CodexCorrectionFailure.invalidResponse }
        defer { try? handle.close() }
        guard let bytes = try handle.read(upToCount: 2_000_001), bytes.count <= 2_000_000,
              let reply = try? JSONDecoder().decode(CorrectionReply.self, from: bytes),
              reply.turns.allSatisfy({ $0.changes != nil && $0.unresolved != nil }) else { throw CodexCorrectionFailure.invalidResponse }
        return reply
    }
}

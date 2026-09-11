import Darwin
import Foundation
import XCTest
import DamaCore
@testable import DamaManaged

@MainActor final class QwenRunnerCancellationTests: XCTestCase {
    private func setup() throws -> (QwenRunner, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        let worker = root.appendingPathComponent("fixture.py")
        try Data("""
        import os, signal, time
        from pathlib import Path
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        work = Path(__file__).parent
        (work / 'checkpoint.json').write_text('{"synthetic":true}')
        (work / 'started').write_text(str(os.getpid()))
        while True:
            time.sleep(0.02)
        """.utf8).write(to: worker)
        try Data("{}".utf8).write(to: root.appendingPathComponent("config.json"))
        let runtime = root.appendingPathComponent("runtime.json")
        let model: (String) -> [String: String] = { ["id": $0, "path": root.path, "revision": "synthetic"] }
        try JSONSerialization.data(withJSONObject: ["version": 1, "python": "/usr/bin/python3", "worker": worker.path,
            "upstreamCommit": "1e28932dac8e2c68b34c29f32e2be338ffc1c852",
            "models": ["asr": model("Qwen/Qwen3-ASR-1.7B"), "aligner": model("Qwen/Qwen3-ForcedAligner-0.6B")]])
            .write(to: runtime)
        return (QwenRunner(runtimeURL: runtime), root.appendingPathComponent("work"))
    }

    func testUnresponsiveChildIsGoneBeforeCancellationReturnsAndCheckpointSurvives() async throws {
        let (runner, work) = try setup()
        let task = Task { try await runner.transcribe(audio: work.appendingPathComponent("unused.wav"), work: work,
            input: ConversionNotes(), audioHash: String(repeating: "a", count: 64), durationUs: 1_000_000) }
        let started = work.appendingPathComponent("started"), deadline = ContinuousClock.now + .seconds(8)
        while !FileManager.default.fileExists(atPath: started.path) && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        guard let data = try? String(contentsOf: started, encoding: .utf8), let pid = Int32(data) else {
            task.cancel(); _ = try? await task.value
            XCTFail("synthetic child did not start"); return
        }
        let checkpoint = work.appendingPathComponent("checkpoint.json")
        let before = try Data(contentsOf: checkpoint)
        task.cancel()
        do { _ = try await task.value; XCTFail("cancellation expected") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(kill(pid, 0), -1)
        XCTAssertEqual(errno, ESRCH)
        XCTAssertEqual(try Data(contentsOf: checkpoint), before)
        XCTAssertTrue(FileManager.default.fileExists(atPath: work.appendingPathComponent("request.json").path))
    }

    func testCancelledBeforeEntryNeverStartsChildOrCreatesWork() async throws {
        let (runner, work) = try setup()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await runner.transcribe(audio: work, work: work, input: ConversionNotes(),
                audioHash: String(repeating: "a", count: 64), durationUs: 1_000_000)
        }
        do { _ = try await task.value; XCTFail("cancellation expected") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: work.path))
    }
}

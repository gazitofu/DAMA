import Foundation
import XCTest
import DamaCore
@testable import DamaManaged

final class CodexCorrectionTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func chunk() throws -> CorrectionChunk {
        try JSONDecoder().decode(CorrectionChunk.self, from: Data(#"{"turns":[{"id":"t1","text":"합성 대사"}],"contextBefore":[],"contextAfter":[]}"#.utf8))
    }
    private func fake(_ source: String, at directory: URL) throws -> URL {
        let url = directory.appendingPathComponent("fake-codex")
        try Data(("#!/bin/sh\n" + source).utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }
    func testStructuredProcessJourneyWithoutCloudCall() async throws {
        let directory = try directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let executable = try fake("""
        while [ "$#" -gt 0 ]; do
          if [ "$1" = "--output-last-message" ]; then shift; result="$1"; fi
          shift
        done
        cat >/dev/null
        printf '%s' '{"turns":[{"id":"t1","text":"합성 대사.","certain":true,"reason":"구두점","changes":[{"quote":"대사","occurrence":0,"replacement":"대사.","certain":true,"reason":"구두점","termID":null}],"unresolved":[]}],"names":[]}' > "$result"
        """, at: directory)
        let chunk = try chunk()
        let reply = try await CodexCorrectionClient().correct(chunk: chunk, input: ConversionNotes(), executable: executable).reply
        XCTAssertEqual(try ContextCorrection.validated(reply, chunk: chunk, input: ConversionNotes()).edits.first?.text, "합성 대사.")
        XCTAssertEqual(reply.turns[0].changes?.count, 1)
        XCTAssertTrue(try XCTUnwrap(ContextCorrection.validated(reply, chunk: chunk, input: ConversionNotes()).edits.first).applied)
        let args = CodexCorrectionClient.arguments(directory: directory, schema: directory, output: directory)
        XCTAssertTrue(args.contains("--ignore-user-config")); XCTAssertTrue(args.contains("features.shell_tool=false"))
        XCTAssertEqual(args[args.firstIndex(of: "--model")! + 1], "gpt-5.6-luna")
        XCTAssertTrue(args.contains("model_reasoning_effort=\"medium\""))
        XCTAssertTrue(args.contains("web_search=\"disabled\"")); XCTAssertFalse(args.contains("--dangerously-bypass-approvals-and-sandbox"))
    }
    func testNewProcessReplyCannotOmitSpanContract() async throws {
        let directory = try directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let executable = try fake("""
        while [ "$#" -gt 0 ]; do
          if [ "$1" = "--output-last-message" ]; then shift; result="$1"; fi
          shift
        done
        cat >/dev/null
        printf '%s' '{"turns":[{"id":"t1","text":"합성 대사","certain":true,"reason":""}],"names":[]}' > "$result"
        """, at: directory)
        do { _ = try await CodexCorrectionClient().correct(chunk: chunk(), input: ConversionNotes(), executable: executable); XCTFail("new process must return span contract") }
        catch { XCTAssertEqual((error as? CodexCorrectionError)?.kind, .format) } // usage-bundle1 가드 이동: 이전 CodexCorrectionFailure
    }
    func testProcessFailureAndTimeoutDoNotRetry() async throws {
        let directory = try directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let executable = try fake("exit 1", at: directory)
        do { _ = try await CodexCorrectionClient().correct(chunk: chunk(), input: ConversionNotes(), executable: executable); XCTFail() }
        catch { XCTAssertEqual((error as? CodexCorrectionError)?.kind, .unclassified) } // 이전 CodexCorrectionFailure
        let sleeping = try fake("exec /bin/sleep 20", at: directory)
        let began = ContinuousClock.now
        do { _ = try await CodexCorrectionClient().correct(chunk: chunk(), input: ConversionNotes(), executable: sleeping, timeout: .milliseconds(150)); XCTFail() }
        catch { XCTAssertEqual((error as? CodexCorrectionError)?.kind, .timeout) } // 이전 CodexCorrectionFailure
        XCTAssertLessThan(began.duration(to: .now), .seconds(5))
    }
    func testCancellationStopsOwnedProcess() async throws {
        let directory = try directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let executable = try fake("exec /bin/sleep 20", at: directory)
        let chunk = try chunk()
        let task = Task { try await CodexCorrectionClient().correct(chunk: chunk, input: ConversionNotes(), executable: executable) }
        try await Task.sleep(for: .milliseconds(200))
        task.cancel()
        do { _ = try await task.value; XCTFail() } catch { XCTAssertEqual((error as? CodexCorrectionError)?.kind, .cancelled) } // 이전 CancellationError
    }
}

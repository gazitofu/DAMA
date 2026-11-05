import Foundation
import XCTest
import DamaCore
@testable import DamaManaged

/// usage-bundle1 AC-13: 가짜 Codex CLI로 실패 분류 8종을 하나씩 일으킨다. 실제 Codex·네트워크 호출 없음.
/// 표식 문장은 plan의 Codex CLI 0.166.0 실측(1·4·5·7)과 같은 형태의 합성 문자열이다.
final class CorrectionFailureTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    private func chunk() throws -> CorrectionChunk {
        try JSONDecoder().decode(CorrectionChunk.self, from: Data(#"{"turns":[{"id":"t1","text":"합성 대사"}],"contextBefore":[],"contextAfter":[]}"#.utf8))
    }
    private func fake(_ body: String, at directory: URL) throws -> URL {
        let url = directory.appendingPathComponent("fake-codex-" + UUID().uuidString)
        try Data(("#!/bin/sh\n" + body).utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }
    /// 결과 파일 경로를 잡는 머리말과 정상 응답 쓰기.
    private let readArgs = """
    while [ "$#" -gt 0 ]; do
      if [ "$1" = "--output-last-message" ]; then shift; result="$1"; fi
      shift
    done
    cat >/dev/null

    """
    private let writeReply = #"printf '%s' '{"turns":[{"id":"t1","text":"합성 대사","certain":true,"reason":"","changes":[],"unresolved":[]}],"names":[]}' > "$result""#

    private func failure(_ body: String, timeout: Duration = .seconds(30), executable: URL? = nil) async throws -> CodexCorrectionError {
        let dir = try directory()
        let exe = try executable ?? fake(body, at: dir)
        do {
            _ = try await CodexCorrectionClient().correct(chunk: chunk(), input: ConversionNotes(), executable: exe, timeout: timeout)
            XCTFail("expected failure"); throw CodexCorrectionError(kind: .unclassified)
        } catch let error as CodexCorrectionError { return error }
    }

    func testEightKindsOneEach() async throws {
        var seen: [CorrectionFailureKind: CodexCorrectionError] = [:]
        // 취소.
        let dir = try directory(), sleeper = try fake("exec /bin/sleep 20", at: dir), chunk = try chunk()
        let task = Task { try await CodexCorrectionClient().correct(chunk: chunk, input: ConversionNotes(), executable: sleeper) }
        try await Task.sleep(for: .milliseconds(200)); task.cancel()
        do { _ = try await task.value; XCTFail() } catch let error as CodexCorrectionError { seen[error.kind] = error }
        // 실행 불가: 실행 권한 없는 파일.
        let plain = dir.appendingPathComponent("not-executable"); try Data("x".utf8).write(to: plain)
        seen[.unavailable] = try await failure("", executable: plain)
        // 시간 초과 (주입한 짧은 timeout).
        seen[.timeout] = try await failure("exec /bin/sleep 20", timeout: .milliseconds(200))
        // 인증 (실측 1 형태).
        seen[.auth] = try await failure("echo 'ERROR: unexpected status 401 Unauthorized: Missing bearer or basic authentication in header' >&2; exit 1")
        // 네트워크 (종료 코드 0 아님 + 표식).
        seen[.network] = try await failure("echo 'ERROR: Reconnecting... waiting for network' >&2; exit 1")
        // 설정 (실측 4: exit 2 + error: unexpected argument).
        seen[.config] = try await failure("echo \"error: unexpected argument '--dama-probe' found\" >&2; exit 2")
        // 형식: 종료 코드 0인데 결과 파일 없음.
        seen[.format] = try await failure(readArgs + "exit 0")
        // 미분류: 표식 없는 비정상 종료.
        seen[.unclassified] = try await failure("echo 'something else' >&2; exit 1")
        XCTAssertEqual(Set(seen.keys), Set(CorrectionFailureKind.allCases))
        XCTAssertEqual(seen[.auth]?.exitCode, 1)
        XCTAssertEqual(seen[.config]?.exitCode, 2)
        XCTAssertEqual(seen[.format]?.exitCode, 0)
        XCTAssertEqual(seen[.unclassified]?.exitCode, 1)
        for kind in [CorrectionFailureKind.cancelled, .unavailable, .timeout] { XCTAssertNil(seen[kind]?.exitCode, kind.rawValue) }
        XCTAssertGreaterThan(seen[.auth]?.stderrBytes ?? 0, 0)
        XCTAssertEqual(seen[.unavailable]?.stderrBytes, 0)
        XCTAssertGreaterThanOrEqual(seen[.timeout]?.elapsedMs ?? 0, 200)
    }

    func testNetworkMarkerDuringTimeoutIsNetworkAndOtherConfigMarker() async throws {
        // D-01 ⓐ: 끝나지 않고 재연결을 반복하다 시간 초과 → 네트워크.
        let looping = try await failure("while true; do echo 'ERROR: Reconnecting... waiting for network' >&2; sleep 0.05; done", timeout: .milliseconds(400))
        XCTAssertEqual(looping.kind, .network)
        XCTAssertNil(looping.exitCode)
        // 실측 7: 모르는 모델.
        let model = try await failure("echo \"ERROR: The 'dama-probe' model is not supported when using Codex with a ChatGPT account.\" >&2; exit 1")
        XCTAssertEqual(model.kind, .config)
        // exit 2가 아니면 unexpected argument 줄만으로는 설정이 아니다.
        let notTwo = try await failure("echo \"error: unexpected argument '--x' found\" >&2; exit 1")
        XCTAssertEqual(notTwo.kind, .unclassified)
        // 신호 종료 → 미분류.
        let signaled = try await failure("kill -9 $$")
        XCTAssertEqual(signaled.kind, .unclassified)
        XCTAssertTrue(signaled.signaled)
        XCTAssertEqual(signaled.exitCode, 9)
    }

    func testPromptEchoDoesNotContaminateClassification() async throws {
        // stdin 프롬프트처럼 전사 낱말이 든 한 줄 JSON이 stderr 맨 앞에 찍혀도 줄 시작이 «{»라 대조하지 않는다.
        let echoed = try await failure("""
        echo '{"turns":[{"text":"Unauthorized 401 Unauthorized waiting for network model is not supported"}]}' >&2
        echo 'user' >&2
        echo 'note: ERROR: 401 Unauthorized' >&2
        exit 1
        """)
        XCTAssertEqual(echoed.kind, .unclassified)
        XCTAssertGreaterThan(echoed.stderrBytes, 0)
    }

    func testLongLineIsCutAt64KiBAndLargeStderrDoesNotBlock() async throws {
        let dir = try directory()
        // 1 MiB를 stderr에 쓰고 exit 0 → 시간 초과 없이 정상, 바이트 수 전부 셈.
        let noisy = try fake(readArgs + "head -c 1048576 /dev/zero | tr '\\000' 'x' >&2\n" + writeReply + "\nexit 0", at: dir)
        let result = try await CodexCorrectionClient().correct(chunk: chunk(), input: ConversionNotes(), executable: noisy, timeout: .seconds(20))
        XCTAssertEqual(result.stderrBytes, 1_048_576)
        // 64 KiB를 넘는 한 줄: 표식이 64 KiB 뒤에 있으면 보지 않는다(미분류), 앞에 있으면 본다(인증).
        let tail = try await failure("{ printf 'ERROR: '; head -c 70000 /dev/zero | tr '\\000' 'x'; echo ' 401 Unauthorized'; } >&2; exit 1")
        XCTAssertEqual(tail.kind, .unclassified)
        XCTAssertEqual(tail.stderrBytes, 7 + 70_000 + 18)
        let head = try await failure("{ printf 'ERROR: 401 Unauthorized '; head -c 70000 /dev/zero | tr '\\000' 'x'; echo; } >&2; exit 1")
        XCTAssertEqual(head.kind, .auth)
    }

    func testStderrIsCountedToEOFEvenAfterTheProcessExits() async throws {
        let dir = try directory()
        // 부모는 바로 끝나고, stderr를 물려받은 자식이 2.5초 뒤에 더 쓴다 → EOF까지 기다려 전부 센다 (QA C D-2).
        let late = try fake(readArgs + writeReply + "\n( sleep 2.5; echo late >&2 ) &\necho early >&2\nexit 0", at: dir)
        let result = try await CodexCorrectionClient().correct(chunk: chunk(), input: ConversionNotes(), executable: late, timeout: .seconds(20))
        XCTAssertEqual(result.stderrBytes, 6 + 5)
        // 제한 시각까지 stderr가 닫히지 않으면 시간 초과로 끝난다(무한 대기 없음).
        let began = ContinuousClock.now
        let held = try await failure(readArgs + writeReply + "\n( sleep 6; echo held >&2 ) &\nexit 0", timeout: .seconds(1))
        XCTAssertEqual(held.kind, .timeout)
        XCTAssertLessThan(began.duration(to: .now), .seconds(4))
    }

    func testScanAndClassifyPure() {
        var scan = StderrScan()
        scan.consume(Array("ERROR: Reconnecting... waiting for network\r\nERROR: unexpected status 401 Unauthorized".utf8))
        XCTAssertTrue(scan.network); XCTAssertFalse(scan.auth) // 끝 줄은 finish 전까지 판정하지 않는다.
        scan.finish()
        XCTAssertTrue(scan.auth)
        XCTAssertEqual(StderrScan.classify(timedOut: false, exitStatus: 1, signaled: false, scan: scan), .auth) // 인증이 네트워크보다 먼저.
        XCTAssertEqual(StderrScan.classify(timedOut: true, exitStatus: nil, signaled: false, scan: scan), .network)
        XCTAssertEqual(StderrScan.classify(timedOut: true, exitStatus: nil, signaled: false, scan: StderrScan()), .timeout)
        XCTAssertEqual(StderrScan.classify(timedOut: false, exitStatus: 9, signaled: true, scan: scan), .unclassified)
    }

    func testMillisecondsTruncateAndNeverNegative() {
        XCTAssertEqual(CodexCorrectionClient.milliseconds(.milliseconds(1500)), 1500)
        XCTAssertEqual(CodexCorrectionClient.milliseconds(.microseconds(1999)), 1)
        XCTAssertEqual(CodexCorrectionClient.milliseconds(.zero), 0)
        XCTAssertEqual(CodexCorrectionClient.milliseconds(.milliseconds(-5)), 0)
        XCTAssertEqual(CodexCorrectionClient.milliseconds(.seconds(300)), 300_000)
    }

    func testFailureLabelsMatchTone() {
        XCTAssertEqual(CorrectionFailureKind.allCases.map { $0.shortLabel(exitCode: 3) },
            ["취소함", "실행 불가", "시간 초과", "로그인 필요로 보임", "연결 문제로 보임", "설정 거부", "응답 형식 불일치", "원인 미분류 (종료 코드 3)"])
        XCTAssertEqual(CorrectionFailureKind.unclassified.bannerMessage(exitCode: 1, hasCompletedChunks: false),
            "AI 보정을 완료하지 못했습니다. 종료 코드 1. 기존 결과는 유지됩니다.")
        XCTAssertEqual(CorrectionFailureKind.cancelled.bannerMessage(exitCode: nil, hasCompletedChunks: true),
            "AI 보정을 취소했습니다. 기존 결과는 유지됩니다. 완료한 구간은 이어서 교정에 남아 있습니다.")
    }
}

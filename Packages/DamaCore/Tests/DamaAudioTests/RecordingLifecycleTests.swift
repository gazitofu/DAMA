import XCTest
@testable import DamaAudio

@MainActor final class RecordingLifecycleTests: XCTestCase {
    func testRecordingAndFinalizationBlockNewInference() {
        let lifecycle = RecordingLifecycle()
        for phase: CapturePhase in [.authorizing, .starting, .recording, .finalizing] {
            XCTAssertFalse(lifecycle.allowsLocalInference(phase: phase, needsFinalization: false))
        }
        for phase: CapturePhase in [.idle, .interrupted, .failed] {
            XCTAssertTrue(lifecycle.allowsLocalInference(phase: phase, needsFinalization: false))
            XCTAssertFalse(lifecycle.allowsLocalInference(phase: phase, needsFinalization: true))
        }
        XCTAssertTrue(lifecycle.beginShutdown())
        XCTAssertFalse(lifecycle.beginShutdown())
        XCTAssertFalse(lifecycle.allowsLocalInference(phase: .idle, needsFinalization: false))
    }

    func testSuccessfulAndFailedSaveBothWaitForInferenceBeforeShutdownReply() async {
        for saved in [true, false] {
            let lifecycle = RecordingLifecycle()
            XCTAssertTrue(lifecycle.beginShutdown())
            var order: [String] = []
            var release: CheckedContinuation<Void, Never>?
            let task = Task {
                let result = await lifecycle.finishShutdown(saveRecording: {
                    order.append("saved"); return saved
                }, pauseLocalInference: {
                    order.append("stopping")
                    await withCheckedContinuation { release = $0 }
                    order.append("stopped")
                })
                order.append("reply")
                return result
            }
            let deadline = ContinuousClock.now + .seconds(2)
            while release == nil && ContinuousClock.now < deadline { await Task.yield() }
            guard let release else { task.cancel(); XCTFail("inference stop was skipped"); return }
            XCTAssertEqual(order, ["saved", "stopping"])
            XCTAssertTrue(lifecycle.shuttingDown)
            XCTAssertFalse(lifecycle.allowsLocalInference(phase: .idle, needsFinalization: false))
            release.resume()
            let result = await task.value
            XCTAssertEqual(result, saved)
            XCTAssertEqual(order, ["saved", "stopping", "stopped", "reply"])
            XCTAssertFalse(lifecycle.shuttingDown)
        }
    }
}

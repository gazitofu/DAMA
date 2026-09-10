import Foundation
import XCTest
@testable import DamaManaged

final class ProcessingPresentationTests: XCTestCase {
    func testProcessingStagesWaitingAndResumedTrackingJourney() throws {
        var run = ManagedRun(id: "synthetic", sessionID: "synthetic", createdAt: "2026-09-10T00:00:00Z", consent: true, stage: "uploading")
        for (index, stage) in ["uploading", "submitting", "remotePending", "normalizing"].enumerated() {
            run.stage = stage
            let state = ProcessingPresentation(run: run, tracking: true)
            XCTAssertEqual(state.step, index); XCTAssertTrue(state.spinning); XCTAssertFalse(state.completed)
        }
        run.stage = "remotePending"; run.remoteStatus = "pending"
        XCTAssertTrue(ProcessingPresentation(run: run, tracking: true).title.contains("기다리고"))
        run.remoteStatus = "running"
        XCTAssertTrue(ProcessingPresentation(run: run, tracking: true).title.contains("진행 중"))
        let paused = ProcessingPresentation(run: run, tracking: false)
        XCTAssertFalse(paused.spinning); XCTAssertNil(paused.step); XCTAssertTrue(paused.title.contains("멈춰"))
        for stage in ["waitingForNetwork", "waitingForCredentials", "waitingForBilling", "submissionUncertain", "paused", "failed"] {
            run.stage = stage
            XCTAssertFalse(ProcessingPresentation(run: run, tracking: true).spinning, stage)
        }
        run.stage = "readyForReview"
        XCTAssertFalse(ProcessingPresentation(run: run, tracking: false).completed)
        XCTAssertTrue(ProcessingPresentation(run: run, tracking: false, scriptSaved: true).completed)
        XCTAssertFalse(ProcessingPresentation(run: run, tracking: false).spinning)
        XCTAssertTrue(ProcessingPresentation(run: nil, tracking: false, preparing: true).spinning)
        XCTAssertEqual(ProcessingPresentation.elapsed(since: Date(timeIntervalSince1970: 100), now: Date(timeIntervalSince1970: 3761)), "01:01:01")
        XCTAssertEqual(ProcessingPresentation.elapsed(since: Date(timeIntervalSince1970: 100), now: Date(timeIntervalSince1970: 99)), "00:00:00")
    }
    func testOldRunDecodesAndServerCheckRoundtrips() throws {
        let old = Data(#"{"id":"synthetic","sessionID":"synthetic","createdAt":"2026-09-10T00:00:00Z","consent":true,"stage":"remotePending"}"#.utf8)
        var run = try JSONDecoder().decode(ManagedRun.self, from: old)
        XCTAssertNil(run.lastServerCheckAt)
        run.lastServerCheckAt = Date(timeIntervalSince1970: 100)
        let loaded = try JSONDecoder().decode(ManagedRun.self, from: JSONEncoder().encode(run))
        XCTAssertEqual(loaded.lastServerCheckAt, run.lastServerCheckAt)
    }
}

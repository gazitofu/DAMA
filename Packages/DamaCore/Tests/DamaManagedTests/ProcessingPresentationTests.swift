import Foundation
import DamaCore
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
    func testNemotronStagesAndRetiredPyannoteWording() throws {
        var notes = ConversionNotes(); notes.transcriptionProvider = .sonioxNemotron
        var run = ManagedRun(id: "synthetic", sessionID: "synthetic", createdAt: "2026-10-30T00:00:00Z", consent: true,
                             stage: "localDiarizing", input: notes)
        let running = ProcessingPresentation(run: run, tracking: true)
        XCTAssertEqual(running.title, "이 Mac에서 화자를 나누고 있습니다")
        XCTAssertEqual(running.detail, "음성을 전송하지 않습니다. 녹음을 시작하면 멈추고, 변환 재개로 처음부터 다시 실행합니다.")
        XCTAssertEqual(running.step, 2); XCTAssertTrue(running.spinning)
        XCTAssertEqual(ProcessingPresentation.steps[2], "전사·화자 분리")
        run.stage = "failed"; run.failure = "localDiarizationFailed"
        let failed = ProcessingPresentation(run: run, tracking: false)
        XCTAssertEqual(failed.title, "이 Mac에서 화자 분리를 끝내지 못했습니다")
        XCTAssertEqual(failed.detail, "Soniox 결과는 보존되어 있습니다. 변환 재개로 화자 분리만 다시 실행합니다.")
        run.failure = "operationFailed"
        XCTAssertEqual(ProcessingPresentation(run: run, tracking: false).title, "변환 상태를 확인해 주세요")
        notes.transcriptionProvider = .sonioxPrecision
        let stalled = ManagedRun(id: "old", sessionID: "synthetic", createdAt: "2026-10-12T00:00:00Z", consent: true,
                                 stage: "waitingForBilling", input: notes)
        let retired = ProcessingPresentation(run: stalled, tracking: false, retiredProvider: true)
        XCTAssertEqual(retired.title, "pyannote 화자 분리는 더 이상 사용하지 않습니다")
        XCTAssertEqual(retired.detail, "다시 전사하면 저장된 Soniox 결과를 재사용해 Nemotron 3로 결합본을 만듭니다.")
        XCTAssertFalse(retired.spinning)
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

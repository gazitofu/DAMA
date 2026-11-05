import XCTest
@testable import DamaCore

/// usage-bundle1 AC-08·AC-09 ⓐ: 제목 저장 시점과 녹음 직후 입력창 줄 서기. 순수 상태만 본다.
final class TitleEditingTests: XCTestCase {
    func testSaveOnlyOnEnterOrLeaveAndNeverWhileComposing() {
        var draft = TitleDraft(saved: "회의")
        XCTAssertEqual(draft.handle(.edit("회의 2", composing: false)), .none) // 편집만으로는 저장하지 않는다(0.5초 대기 없음).
        XCTAssertTrue(draft.isDirty)
        XCTAssertEqual(draft.handle(.enter), .save("회의 2"))
        XCTAssertEqual(draft.handle(.edit("회의 2차", composing: true)), .none)
        XCTAssertEqual(draft.handle(.enter), .none) // 조합 중 Enter.
        XCTAssertEqual(draft.handle(.leave), .none) // 조합 중 이탈.
        XCTAssertEqual(draft.handle(.edit("회의 2차", composing: false)), .none)
        XCTAssertEqual(draft.handle(.leave), .save("회의 2차"))
    }

    func testUnchangedInputDoesNotSaveAndSuccessUpdatesSavedValue() {
        var draft = TitleDraft(saved: "회의")
        XCTAssertEqual(draft.handle(.enter), .none)
        XCTAssertEqual(draft.handle(.leave), .none)
        _ = draft.handle(.edit("새 제목", composing: false))
        XCTAssertEqual(draft.handle(.enter), .save("새 제목"))
        draft.didSave("새 제목")
        XCTAssertFalse(draft.isDirty)
        XCTAssertEqual(draft.saved, "새 제목")
        XCTAssertEqual(draft.handle(.leave), .none)
    }

    func testEscapeRevertsToLastSavedValue() {
        var draft = TitleDraft(saved: "저장값")
        _ = draft.handle(.edit("고치는 중", composing: false))
        XCTAssertEqual(draft.handle(.escape), .revert("저장값"))
        XCTAssertEqual(draft.text, "저장값")
        XCTAssertFalse(draft.isDirty)
        _ = draft.handle(.edit("조합", composing: true))
        XCTAssertEqual(draft.handle(.escape), .none) // 조합 중 Esc는 입력기 몫.
    }

    func testBlankIsRejectedAndInputIsKeptWhileWhitespaceIsNotTrimmed() {
        var draft = TitleDraft(saved: "회의")
        _ = draft.handle(.edit("  \n ", composing: false))
        XCTAssertEqual(draft.handle(.enter), .reject("제목을 입력해 주세요."))
        XCTAssertEqual(draft.text, "  \n ")
        XCTAssertEqual(draft.handle(.leave), .reject(TitleDraft.emptyMessage))
        _ = draft.handle(.edit("  앞뒤 공백 ", composing: false))
        XCTAssertEqual(draft.handle(.enter), .save("  앞뒤 공백 "))
    }

    func testFailureKeepsInputAndExternalUpdateFollowsOnlyWhenClean() {
        var draft = TitleDraft(saved: "회의")
        _ = draft.handle(.edit("실패할 제목", composing: false))
        XCTAssertEqual(draft.handle(.enter), .save("실패할 제목"))
        // 저장 실패: didSave를 부르지 않는다 → 입력 유지, 다시 Enter면 다시 저장.
        XCTAssertEqual(draft.text, "실패할 제목")
        XCTAssertEqual(draft.handle(.enter), .save("실패할 제목"))
        draft.receive(saved: "다른 창에서 바꿈")
        XCTAssertEqual(draft.text, "실패할 제목")
        var clean = TitleDraft(saved: "회의")
        clean.receive(saved: "다른 창에서 바꿈")
        XCTAssertEqual(clean.text, "다른 창에서 바꿈")
    }

    func testPromptQueueShowsOneAtATimeInFinishOrderAfterIndexConfirmation() {
        var queue = TitlePromptQueue()
        queue.finished("a"); queue.finished("b"); queue.finished("c")
        XCTAssertNil(queue.current) // 인덱스 확인 전에는 보이지 않는다.
        XCTAssertEqual(queue.count, 3)
        queue.confirmed(["c"])
        XCTAssertEqual(queue.current, "c")
        queue.confirmed(["a", "b", "zzz"]) // 보이는 입력창은 바꾸지 않는다.
        XCTAssertEqual(queue.current, "c")
        queue.dismissCurrent()
        XCTAssertEqual(queue.current, "a") // 뒤에 선 것은 끝난 순서.
        queue.dismissCurrent()
        XCTAssertEqual(queue.current, "b")
        queue.dismissCurrent()
        XCTAssertNil(queue.current)
        XCTAssertEqual(queue.count, 0)
    }

    func testPromptQueueIgnoresUnknownIDsDropsFailuresAndTerminateDiscardsAll() {
        var queue = TitlePromptQueue()
        queue.confirmed(["never-finished"])
        XCTAssertNil(queue.current)
        queue.finished("a"); queue.finished("a")
        XCTAssertEqual(queue.count, 1)
        queue.finished("failed")
        queue.drop("failed") // Speeches 저장 실패 → 건너뜀.
        queue.confirmed(["a", "failed"])
        XCTAssertEqual(queue.current, "a")
        XCTAssertEqual(queue.count, 1)
        queue.finished("b"); queue.confirmed(["b"])
        XCTAssertEqual(queue.count, 2)
        queue.terminate()
        XCTAssertNil(queue.current)
        XCTAssertEqual(queue.count, 0)
        queue.confirmed(["a", "b"]) // 종료 뒤 늦은 확인은 아무것도 띄우지 않는다.
        XCTAssertNil(queue.current)
    }
}

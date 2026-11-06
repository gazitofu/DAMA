import Foundation
import XCTest
@testable import DamaAudio

/// usage-bundle2 AC-07 · AC-08: 문구 1–5 조립. 정리 수 0이면 현행 문자열과 바이트 동일.
final class RetentionNoticeTests: XCTestCase {
    /// 현행(usage-bundle2 전) `App/ProcessingWorkspace.swift:206` · `:232` 문자열을 그대로 옮긴 기준선.
    private let currentRetranscribe = "\n\n새 작업으로 처리하며 비용이 다시 발생할 수 있습니다. 기존 스크립트와 사용자 수정은 유지하고 새 스크립트를 만듭니다. 화자 이름과 문장 수정은 새 결과에 자동 복사하지 않습니다."
    private let currentNemotronUsage = "\n\n새 Soniox 요청에만 사용량이 발생합니다. 완료된 결과는 보존하고, Soniox 단독과 결합본을 따로 엽니다. AI 교정 OFF. 화자 충돌·경계·겹말은 검수 대상으로 남습니다.\n\n"

    func testZeroKeepsCurrentTextByteForByte() {
        XCTAssertEqual(Data(RetentionNotice.retranscribeParagraph(0).utf8), Data(currentRetranscribe.utf8))
        XCTAssertEqual(Data(RetentionNotice.nemotronUsageParagraph(0).utf8), Data(currentNemotronUsage.utf8))
        XCTAssertEqual(RetentionNotice.confirmationParagraph(0), "")
        XCTAssertEqual(RetentionNotice.completionSuffix(moved: 0, failed: 0), "")
    }

    func testPositiveCountUsesToneSentences() {
        let tone1 = "완료되면 이 녹음의 이전 결과 스크립트 1개를 휴지통으로 옮깁니다. 최근 결과 2회분과 사람이 고친 스크립트는 남깁니다."
        XCTAssertEqual(RetentionNotice.confirmationParagraph(1), "\n\n" + tone1)
        XCTAssertEqual(RetentionNotice.retranscribeParagraph(1),
                       "\n\n새 작업으로 처리하며 비용이 다시 발생할 수 있습니다. 새 스크립트를 만듭니다. 화자 이름과 문장 수정은 새 결과에 자동 복사하지 않습니다.\n\n" + tone1)
        XCTAssertEqual(RetentionNotice.nemotronUsageParagraph(3),
                       "\n\n새 Soniox 요청에만 사용량이 발생합니다. Soniox 단독과 결합본을 따로 엽니다. AI 교정 OFF. 화자 충돌·경계·겹말은 검수 대상으로 남습니다.\n\n")
        XCTAssertEqual(RetentionNotice.completionSuffix(moved: 2, failed: 0), " 이전 결과 스크립트 2개를 휴지통으로 옮겼습니다.")
        XCTAssertEqual(RetentionNotice.completionSuffix(moved: 0, failed: 1), " 이전 결과 스크립트 1개는 옮기지 못해 그대로 두었습니다.")
        XCTAssertEqual(RetentionNotice.completionSuffix(moved: 1, failed: 1),
                       " 이전 결과 스크립트 1개를 휴지통으로 옮겼습니다. 이전 결과 스크립트 1개는 옮기지 못해 그대로 두었습니다.")
    }
}

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

/// usage-bundle2 AC-09ⓘ · AC-10: 설정 «저장 공간» 확인창 줄 순서와 0줄 생략(문구 13–18, 20–22).
final class StorageCleanupNoticeTests: XCTestCase {
    func testConfirmLinesOrderAndOmitZeroLines() {
        let all = StorageCleanupNotice.Counts(scripts: 2, scriptBytes: 24_800_000, deletions: 62, deletionBytes: 243_100_000,
                                              migrations: 512, migrationBytes: 9_758_900_000, attempts: 1)
        let size = StorageCleanupNotice.size
        XCTAssertEqual(StorageCleanupNotice.confirmLines(all), [
            "이전 결과 스크립트 2개 · \(size(24_800_000))를 휴지통으로 옮깁니다. 녹음마다 최근 결과 2회분과 사람이 고친 스크립트는 남깁니다.",
            "현재 Scripts 폴더에 없는 스크립트의 내부 수정 이력 62개 · \(size(243_100_000))를 지웁니다.",
            "내부 수정 이력 512개 · \(size(9_758_900_000))를 압축합니다. 압축을 푼 내용이 원본과 같을 때만 원본을 지웁니다.",
            "현재 Scripts 폴더에 없는 스크립트의 AI 교정 시도 기록 1개를 지웁니다.",
            "지운 수정 이력은 되돌릴 수 없습니다. 녹음 원음과 전사 원응답은 지우지 않습니다.",
        ])
        XCTAssertEqual(all.total, 2 + 62 + 512 + 1)
        // 지금 데이터 모양: 스크립트 0 · 시도 기록 0 → 문구 13·17 없음.
        let today = StorageCleanupNotice.Counts(deletions: 62, deletionBytes: 243_100_000, migrations: 512, migrationBytes: 9_758_900_000)
        XCTAssertEqual(StorageCleanupNotice.confirmLines(today).count, 3)
        // Scripts 조회 문제: 문구 14·17 대신 문구 15.
        let blocked = StorageCleanupNotice.Counts(skippedOrphans: true, migrations: 3, migrationBytes: 3_000)
        XCTAssertEqual(StorageCleanupNotice.confirmLines(blocked).first, "Scripts 폴더에 읽지 못한 파일이 있어 내부 수정 이력 삭제는 건너뜁니다.")
        XCTAssertEqual(StorageCleanupNotice.Counts().total, 0)
    }
    func testProgressFinishedAndFixedStrings() {
        XCTAssertEqual(StorageCleanupNotice.progress(214, of: 574), "저장 공간을 정리하는 중… (214/574)")
        let size = StorageCleanupNotice.size
        XCTAssertEqual(StorageCleanupNotice.finished(before: 10_002_000_000, after: 651_800_000, scripts: 0, failed: 0),
                       "저장 공간을 정리했습니다. 내부 수정 이력 \(size(10_002_000_000)) → \(size(651_800_000)).")
        XCTAssertEqual(StorageCleanupNotice.finished(before: 2_000, after: 1_000, scripts: 1, failed: 2),
                       "저장 공간을 정리했습니다. 내부 수정 이력 \(size(2_000)) → \(size(1_000)). 이전 결과 스크립트 1개를 휴지통으로 옮겼습니다. 처리하지 못한 파일 2개는 그대로 두었습니다.")
        XCTAssertEqual(StorageCleanupNotice.sizeLine(0), "내부 수정 이력 \(size(0))")
        XCTAssertEqual([StorageCleanupNotice.header, StorageCleanupNotice.button, StorageCleanupNotice.disabled, StorageCleanupNotice.checking,
                        StorageCleanupNotice.confirmTitle, StorageCleanupNotice.nothing, StorageCleanupNotice.checkFailed], [
            "저장 공간", "저장 공간 정리…", "다른 작업이 끝난 뒤 정리할 수 있습니다.", "정리할 항목을 확인하는 중…",
            "저장 공간을 정리할까요?", "정리할 항목이 없습니다.", "정리할 항목을 확인하지 못했습니다. 아무것도 지우지 않았습니다.",
        ])
    }
}

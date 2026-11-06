import Foundation

/// usage-bundle2 결과 보관·저장 공간 정리 문구 조립 (정본 `ssot/tone/usage-bundle2.md`, 번호 = 문구 N).
/// 정리 수가 0이면 현행 문장을 바이트 그대로 돌려준다.
public enum RetentionNotice {
    /// 문구 1 (재전사 확인창 추가 문단). n = 0이면 빈 문자열.
    public static func confirmationParagraph(_ n: Int) -> String {
        n >= 1 ? "\n\n완료되면 이 녹음의 이전 결과 스크립트 \(n)개를 휴지통으로 옮깁니다. 최근 결과 \(ScriptRetention.keptGenerations)회분과 사람이 고친 스크립트는 남깁니다." : ""
    }
    /// 문구 2 (Soniox 단독 재전사 문단의 가운데 문장).
    public static func retranscribeKeepSentence(_ n: Int) -> String {
        n >= 1 ? "새 스크립트를 만듭니다." : "기존 스크립트와 사용자 수정은 유지하고 새 스크립트를 만듭니다."
    }
    /// 문구 3 (Soniox + Nemotron 3 확인창 문단의 둘째 문장).
    public static func combinedOpenSentence(_ n: Int) -> String {
        n >= 1 ? "Soniox 단독과 결합본을 따로 엽니다." : "완료된 결과는 보존하고, Soniox 단독과 결합본을 따로 엽니다."
    }
    /// Soniox 단독 재전사 문단(현행 ProcessingWorkspace 재전사 문단) + 문구 2 + 뒤따르는 문구 1. n = 0이면 현행 그대로.
    public static func retranscribeParagraph(_ n: Int) -> String {
        "\n\n새 작업으로 처리하며 비용이 다시 발생할 수 있습니다. \(retranscribeKeepSentence(n)) 화자 이름과 문장 수정은 새 결과에 자동 복사하지 않습니다."
            + confirmationParagraph(n)
    }
    /// Soniox + Nemotron 3 확인창의 사용량 문단 + 문구 3. n = 0이면 현행 그대로.
    public static func nemotronUsageParagraph(_ n: Int) -> String {
        "\n\n새 Soniox 요청에만 사용량이 발생합니다. \(combinedOpenSentence(n)) AI 교정 OFF. 화자 충돌·경계·겹말은 검수 대상으로 남습니다.\n\n"
    }
    /// 문구 4·5 (결과 저장 메시지 뒤). 0이면 붙이지 않는다.
    public static func completionSuffix(moved: Int, failed: Int) -> String {
        (moved >= 1 ? " 이전 결과 스크립트 \(moved)개를 휴지통으로 옮겼습니다." : "")
            + (failed >= 1 ? " 이전 결과 스크립트 \(failed)개는 옮기지 못해 그대로 두었습니다." : "")
    }
}

/// usage-bundle2 설정 «저장 공간» 문구 (문구 8–23, 19 결번). 크기 표기 = `ByteCountFormatter` `.file`(1000진).
public enum StorageCleanupNotice {
    public static func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
    public static let header = "저장 공간"                                                                   // 8
    public static let description = "스크립트 파일과 내부 수정 이력을 정리합니다. 녹음 원음과 전사 원응답은 지우지 않습니다."  // 9
    public static let button = "저장 공간 정리…"                                                              // 10
    public static func sizeLine(_ bytes: Int64) -> String { "내부 수정 이력 \(size(bytes))" }                  // 10
    public static let disabled = "다른 작업이 끝난 뒤 정리할 수 있습니다."                                         // 11
    public static let checking = "정리할 항목을 확인하는 중…"                                                    // 12
    public static let confirmTitle = "저장 공간을 정리할까요?"                                                   // 12
    public static let cancel = "취소"                                                                       // 18
    public static let confirm = "정리"                                                                      // 18
    public static let nothing = "정리할 항목이 없습니다."                                                        // 22
    public static let checkFailed = "정리할 항목을 확인하지 못했습니다. 아무것도 지우지 않았습니다."                    // 23

    public struct Counts: Sendable, Equatable {
        public var scripts = 0, scriptBytes: Int64 = 0
        public var deletions = 0, deletionBytes: Int64 = 0
        public var skippedOrphans = false
        public var migrations = 0, migrationBytes: Int64 = 0
        public var attempts = 0
        public init(scripts: Int = 0, scriptBytes: Int64 = 0, deletions: Int = 0, deletionBytes: Int64 = 0, skippedOrphans: Bool = false,
                    migrations: Int = 0, migrationBytes: Int64 = 0, attempts: Int = 0) {
            self.scripts = scripts; self.scriptBytes = scriptBytes; self.deletions = deletions; self.deletionBytes = deletionBytes
            self.skippedOrphans = skippedOrphans; self.migrations = migrations; self.migrationBytes = migrationBytes; self.attempts = attempts
        }
        /// 확인창 항목 수 합 = 진행 문구 20의 {N}.
        public var total: Int { scripts + deletions + migrations + attempts }
    }

    /// 확인창 본문 줄: 13 → 14 또는 15 → 16 → 17 → 18. 0인 줄은 뺀다. 전부 0이면 확인창 없이 문구 22.
    public static func confirmLines(_ c: Counts) -> [String] {
        var lines: [String] = []
        if c.scripts >= 1 {
            lines.append("이전 결과 스크립트 \(c.scripts)개 · \(size(c.scriptBytes))를 휴지통으로 옮깁니다. 녹음마다 최근 결과 \(ScriptRetention.keptGenerations)회분과 사람이 고친 스크립트는 남깁니다.")
        }
        if c.skippedOrphans { lines.append("Scripts 폴더에 읽지 못한 파일이 있어 내부 수정 이력 삭제는 건너뜁니다.") }
        else if c.deletions >= 1 { lines.append("현재 Scripts 폴더에 없는 스크립트의 내부 수정 이력 \(c.deletions)개 · \(size(c.deletionBytes))를 지웁니다.") }
        if c.migrations >= 1 {
            lines.append("내부 수정 이력 \(c.migrations)개 · \(size(c.migrationBytes))를 압축합니다. 압축을 푼 내용이 원본과 같을 때만 원본을 지웁니다.")
        }
        if c.attempts >= 1 && !c.skippedOrphans { lines.append("현재 Scripts 폴더에 없는 스크립트의 AI 교정 시도 기록 \(c.attempts)개를 지웁니다.") }
        lines.append("지운 수정 이력은 되돌릴 수 없습니다. 녹음 원음과 전사 원응답은 지우지 않습니다.")
        return lines
    }
    /// 문구 20.
    public static func progress(_ done: Int, of total: Int) -> String { "저장 공간을 정리하는 중… (\(done)/\(total))" }
    /// 문구 21.
    public static func finished(before: Int64, after: Int64, scripts: Int, failed: Int) -> String {
        "저장 공간을 정리했습니다. 내부 수정 이력 \(size(before)) → \(size(after))."
            + (scripts >= 1 ? " 이전 결과 스크립트 \(scripts)개를 휴지통으로 옮겼습니다." : "")
            + (failed >= 1 ? " 처리하지 못한 파일 \(failed)개는 그대로 두었습니다." : "")
    }
}

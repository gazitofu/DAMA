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

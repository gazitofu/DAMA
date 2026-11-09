import Foundation

/// correction-turn-isolation 확정 문구 (`ssot/tone/correction-turn-isolation.md` 1–5 · 2a).
/// 구간 정보·완료 안내 띠·Markdown이 같은 문자열을 쓴다. 버린 원구간이 0개면 아무 문장도 붙지 않는다.
public enum CorrectionRejectionText {
    /// 문구 1: 구간 정보 첫 줄(굵게).
    public static let inspectorTitle = "원문 유지 · AI 응답 검증 실패"
    /// 문구 2, 한 문단의 버린 원구간이 2개 이상이면 문구 2a를 덧붙인다.
    public static func paragraphNote(count: Int) -> String {
        "AI 응답이 이 문단의 원문과 맞지 않아 쓰지 않았습니다." + (count >= 2 ? " (\(count)개 원구간)" : "")
    }
    /// 완료 안내 띠: 현행 문장 + (N ≥ 1이면 공백 + 문구 3). N = 0이면 현행 문장 그대로.
    public static func completionMessage(rejectedCount: Int) -> String {
        "AI 보정 결과를 저장했습니다. 다른 결과 보기에서 이전 버전을 확인할 수 있습니다." + completionSuffix(count: rejectedCount)
    }
    public static func completionSuffix(count: Int) -> String {
        count >= 1 ? " AI 응답이 원문과 맞지 않은 \(count)개 원구간은 원문을 유지했습니다." : ""
    }
    /// 문구 4: Markdown «AI 교정 정보» 목록 줄.
    public static func markdownSummary(count: Int) -> String { "- 검증 실패로 원문 유지: \(count)개 원구간" }
    /// 문구 5: Markdown 문단 줄 접두.
    public static let markdownPrefix = "> AI 검증 실패: "
}

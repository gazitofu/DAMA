import Foundation

/// correction-turn-isolation 확정 문구 (`ssot/tone/correction-turn-isolation.md` 1–5 · 2a, {N} = 검증 실패 6종)와
/// turn-continuity 확정 문구 (`ssot/tone/turn-continuity.md` 6–11, {M} = 응답 없음 `missing` · `chunk`).
/// 구간 정보·완료 안내 띠·Markdown·진행 줄이 같은 문자열을 쓴다. N = M = 0이면 아무 문장도 붙지 않는다.
public enum CorrectionRejectionText {
    /// 문구 1: 구간 정보 첫 줄(굵게).
    public static let inspectorTitle = "원문 유지 · AI 응답 검증 실패"
    /// 문구 2, 한 문단의 버린 원구간이 2개 이상이면 문구 2a를 덧붙인다.
    public static func paragraphNote(count: Int) -> String {
        "AI 응답이 이 문단의 원문과 맞지 않아 쓰지 않았습니다." + (count >= 2 ? " (\(count)개 원구간)" : "")
    }
    /// 완료 안내 띠: 현행 문장 + (N ≥ 1이면 공백 + 문구 3) + (M ≥ 1이면 공백 + 문구 8). N = M = 0이면 현행 문장 그대로.
    public static func completionMessage(rejectedCount: Int, noResponseCount: Int = 0) -> String {
        "AI 보정 결과를 저장했습니다. 다른 결과 보기에서 이전 버전을 확인할 수 있습니다." + completionSuffix(count: rejectedCount)
            + noResponseSuffix(count: noResponseCount)
    }
    public static func completionSuffix(count: Int) -> String {
        count >= 1 ? " AI 응답이 원문과 맞지 않은 \(count)개 원구간은 원문을 유지했습니다." : ""
    }
    /// 문구 4: Markdown «AI 교정 정보» 목록 줄.
    public static func markdownSummary(count: Int) -> String { "- 검증 실패로 원문 유지: \(count)개 원구간" }
    /// 문구 5: Markdown 문단 줄 접두.
    public static let markdownPrefix = "> AI 검증 실패: "

    /// 문구 6: 구간 정보 첫 줄(굵게), 응답 없음.
    public static let noResponseTitle = "원문 유지 · AI 응답 없음"
    /// 문구 7, 한 문단의 응답 없음 원구간이 2개 이상이면 문구 2a를 덧붙인다.
    public static func noResponseNote(count: Int) -> String {
        "AI 응답을 받지 못해 이 문단은 원문을 유지했습니다." + (count >= 2 ? " (\(count)개 원구간)" : "")
    }
    /// 문구 8: 완료 안내 띠 덧붙임 (M ≥ 1, 앞에 공백 하나).
    public static func noResponseSuffix(count: Int) -> String {
        count >= 1 ? " AI 응답을 받지 못한 \(count)개 원구간은 원문을 유지했습니다." : ""
    }
    /// 문구 9: Markdown «AI 교정 정보» 목록 줄.
    public static func markdownNoResponseSummary(count: Int) -> String { "- 응답 없음으로 원문 유지: \(count)개 원구간" }
    /// 문구 10: Markdown 문단 줄 접두.
    public static let markdownNoResponsePrefix = "> AI 응답 없음: "
    /// 문구 11: 진행 줄 덧붙임, 같은 청크를 다시 보내는 동안만 (앞에 공백 하나, {r} = 1 · 2).
    public static func retrySuffix(_ retry: Int) -> String { " · 응답 다시 받는 중 (\(retry)/2)" }
}

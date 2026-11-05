import Foundation

/// usage-bundle1 AI 교정 실패 분류 8종 (스펙 §02-3 표, 위에서부터 처음 맞는 하나).
public enum CorrectionFailureKind: String, Codable, Sendable, CaseIterable {
    case cancelled, unavailable, timeout, auth, network, config, format, unclassified

    /// 하단 미완료 줄의 짧은 원인 (tone 문구 14).
    public func shortLabel(exitCode: Int32?) -> String {
        switch self {
        case .cancelled: "취소함"
        case .unavailable: "실행 불가"
        case .timeout: "시간 초과"
        case .auth: "로그인 필요로 보임"
        case .network: "연결 문제로 보임"
        case .config: "설정 거부"
        case .format: "응답 형식 불일치"
        case .unclassified: "원인 미분류 (종료 코드 \(exitCode.map(String.init) ?? "없음"))"
        }
    }

    /// 실패 순간 안내 띠 (tone 문구 18). `hasCompletedChunks`는 취소 문구 덧붙임에만 쓴다.
    public func bannerMessage(exitCode: Int32?, hasCompletedChunks: Bool) -> String {
        switch self {
        case .unavailable: "Codex를 실행하지 못했습니다. 설정에서 Codex 실행 파일을 확인해 주세요. 기존 결과는 유지됩니다."
        case .auth: "Codex 로그인이 필요해 보입니다. 터미널에서 Codex에 로그인한 뒤 이어서 교정해 주세요. 기존 결과는 유지됩니다."
        case .network: "연결 문제로 보입니다. 네트워크를 확인한 뒤 이어서 교정해 주세요. 기존 결과는 유지됩니다."
        case .config: "Codex가 실행 설정을 받아들이지 않았습니다. Codex 버전이 바뀌었을 수 있습니다. 기존 결과는 유지됩니다."
        case .timeout: "한 구간이 300초 안에 끝나지 않았습니다. 이어서 교정으로 그 구간부터 다시 보낼 수 있습니다. 기존 결과는 유지됩니다."
        case .format: "AI 응답이 요구한 형식과 맞지 않아 쓰지 않았습니다. 이어서 교정으로 그 구간부터 다시 보낼 수 있습니다. 기존 결과는 유지됩니다."
        case .unclassified: "AI 보정을 완료하지 못했습니다. 종료 코드 \(exitCode.map(String.init) ?? "없음"). 기존 결과는 유지됩니다."
        case .cancelled: "AI 보정을 취소했습니다. 기존 결과는 유지됩니다." + (hasCompletedChunks ? " 완료한 구간은 이어서 교정에 남아 있습니다." : "")
        }
    }
}

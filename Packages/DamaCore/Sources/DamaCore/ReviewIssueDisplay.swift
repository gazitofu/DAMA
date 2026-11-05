import Foundation

/// usage-bundle1 검수 이슈 표시. 계약 사본(DomainContracts.swift)은 byte-exact 대상이라 확장은 이 파일에만 둔다.
/// 데이터(`reviewIssues`)·`blocks()`·평가 JSON은 바꾸지 않고 화면·Markdown 표시만 정한다.
extension IssueKind {
    /// 자동 경고 8종. 녹음 중단·일부 결과는 항상 보이는 경고라 제외한다.
    public var isAutoWarning: Bool {
        switch self {
        case .capture_interrupted, .partial_result: return false
        case .ambiguous_speaker, .overlapping_speech, .missing_speech, .provider_disagreement,
             .boundary_conflict, .unrepresented_speaker, .invalid_timestamp, .low_confidence: return true
        }
    }

    /// Markdown 머리말의 종류 짧은 이름 (tone usage-bundle1 문구 8). 자동 경고가 아니면 nil.
    public var markdownShortName: String? {
        switch self {
        case .boundary_conflict: return "화자 경계 걸침"
        case .overlapping_speech: return "겹침"
        case .invalid_timestamp: return "시간 불명"
        case .provider_disagreement: return "제공자 화자 불일치"
        case .missing_speech: return "누락 의심"
        case .unrepresented_speaker: return "본문에 없는 화자"
        case .ambiguous_speaker: return "화자 미확정"
        case .low_confidence: return "낮은 화자 점수"
        case .capture_interrupted, .partial_result: return nil
        }
    }

    /// 항상 보이는 경고의 문장 (tone 문구 1). 자동 경고면 nil.
    public var persistentWarningText: String? {
        switch self {
        case .capture_interrupted: return "녹음이 중단되어 이후 구간이 녹음되지 않았을 수 있습니다."
        case .partial_result: return "일부 전사 결과를 받지 못했습니다."
        default: return nil
        }
    }

    /// Markdown 머리말·문단 줄의 앞 이름 (tone 문구 9).
    public var persistentWarningLabel: String? {
        switch self {
        case .capture_interrupted: return "녹음 중단"
        case .partial_result: return "일부 결과"
        default: return nil
        }
    }

    /// 자동 경고 종류별 건수. 건수 내림차순, 같으면 `rawValue` 오름차순, 0건 종류는 없다.
    /// 상태 필터는 호출자가 정한다(화면 = open만, Markdown 머리말 = 전부).
    public static func autoWarningSummary(_ issues: [ReviewIssue]) -> [(kind: IssueKind, count: Int)] {
        var counts: [IssueKind: Int] = [:]
        for issue in issues where issue.kind.isAutoWarning { counts[issue.kind, default: 0] += 1 }
        return counts.map { (kind: $0.key, count: $0.value) }.sorted {
            $0.count != $1.count ? $0.count > $1.count : $0.kind.rawValue < $1.kind.rawValue
        }
    }
}

extension ScriptBlock {
    /// 이 문단 open 자동 경고의 종류별 건수 (구간 정보 «자동 경고 N건» 접힘).
    public var autoWarningSummary: [(kind: IssueKind, count: Int)] { IssueKind.autoWarningSummary(openIssues) }
    /// 이 문단 open 녹음 중단·일부 결과 (문단 아래·구간 정보 맨 위 경고 줄, 이슈 1건당 1줄).
    public var persistentWarnings: [ReviewIssue] { openIssues.filter { !$0.kind.isAutoWarning } }
}

enum ReviewIssueFormat {
    /// 천 단위 쉼표. 로캘과 무관하게 고정한다 (1402 → "1,402").
    static func grouped(_ value: Int) -> String {
        let digits = String(value.magnitude)
        var result = ""
        for (index, character) in digits.enumerated() {
            if index > 0, (digits.count - index) % 3 == 0 { result.append(",") }
            result.append(character)
        }
        return value < 0 ? "-" + result : result
    }
}

extension LibraryScript {
    /// Markdown 머리말 «- 검수:» 줄 본문 (tone 문구 7). 총수는 `transcript.reviewIssues` 자동 경고 8종 전부이며
    /// 상태·삭제 문단을 따지지 않는다.
    public var markdownReviewLine: String {
        let summary = IssueKind.autoWarningSummary(transcript.reviewIssues)
        let total = summary.reduce(0) { $0 + $1.count }
        let audioChecked = (reviewRecords ?? []).filter(\.audioChecked).count
        let lead = audioChecked == 0 ? "자동 화자 분리 결과이며 사람이 원음으로 검수하지 않음" : reviewSummary
        guard total > 0 else { return "\(lead). 자동 경고 0건 (경고 없음이 정확도를 보장하지 않음)" }
        let kinds = summary.map { "\($0.kind.markdownShortName ?? $0.kind.rawValue) \(ReviewIssueFormat.grouped($0.count))" }
        return "\(lead). 자동 경고 \(ReviewIssueFormat.grouped(total))건(\(kinds.joined(separator: ", ")))은 생략"
    }

    /// Markdown 머리말의 녹음 중단·일부 결과 줄. 종류당 1줄, 있을 때만, 상태와 무관하다.
    public var markdownPersistentHeaderLines: [String] {
        [IssueKind.capture_interrupted, .partial_result].compactMap { kind in
            guard transcript.reviewIssues.contains(where: { $0.kind == kind }),
                  let label = kind.persistentWarningLabel, let text = kind.persistentWarningText else { return nil }
            return "- \(label): \(text)"
        }
    }
}

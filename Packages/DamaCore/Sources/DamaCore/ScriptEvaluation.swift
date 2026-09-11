import Foundation

public enum ReviewError: String, Codable, CaseIterable, Sendable {
    case unclassified, noError, asr, alignment, speakerAttribution, turnBoundary, omission, shortResponse, semantics, reconciliation, presentation, style
    public var title: String {
        switch self {
        case .unclassified: "미분류 / 아직 판단 못함"
        case .noError: "검수 범위에서 오류 없음"
        case .asr: "ASR 오인식"
        case .alignment: "단어 시간 정렬"
        case .speakerAttribution: "E1 · 다른 사람에게 귀속"
        case .turnBoundary: "E2 · 화자 전환·발화 병합"
        case .omission: "발화 누락"
        case .shortResponse: "짧은 응답 손실"
        case .semantics: "핵심 의미 · 용어·숫자·부정·조건"
        case .reconciliation: "결합 규칙"
        case .presentation: "문단 표시"
        case .style: "윤문 / 표현 선호"
        }
    }
}
public enum ReviewSample: String, Codable, CaseIterable, Sendable {
    case unclassified, problem, random
    public var title: String {
        switch self { case .unclassified: "일반 검수"; case .problem: "문제 구간"; case .random: "무작위 표본" }
    }
}
public struct ReviewedTurn: Codable, Sendable, Equatable {
    public let turnID: String
    public let startUs: Int64?
    public let endUs: Int64?
    public let beforeText: String
    public let afterText: String
    public let beforeName: String
    public let afterName: String
}
public struct ScriptReviewRecord: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let recordedAt: Date
    public let baseRevisionID: String
    public let resultRevisionID: String
    public let audioSHA256: String?
    public let turns: [ReviewedTurn]
    public let audioChecked: Bool
    public let error: ReviewError
    public let sample: ReviewSample
    public let activeSeconds: Double?
    public let note: String
    // No record is automatically a training label, including high-confidence or matching models.
    public var eligibleForTextLabelReview: Bool {
        audioChecked && [.asr, .omission, .shortResponse, .semantics].contains(error) &&
        turns.contains { $0.beforeText != $0.afterText }
    }
}
extension LibraryScript {
    public mutating func recordReview(before: LibraryScript, turnIDs: [String], audioChecked: Bool = false,
                                      error: ReviewError = .unclassified, sample: ReviewSample = .unclassified,
                                      activeSeconds: Double? = nil, note: String = "") throws {
        guard before.id == id, !turnIDs.isEmpty, Set(turnIDs).count == turnIDs.count,
              activeSeconds.map({ $0.isFinite && $0 >= 0 }) ?? true,
              error != .noError || audioChecked else { throw LibraryFailure.invalidInput }
        let selected = Set(turnIDs)
        let turns = transcript.turns.filter { selected.contains($0.id) }
        guard turns.count == selected.count else { throw LibraryFailure.invalidInput }
        let base = before.revisionID
        revisionID = UUID().uuidString
        let record = ScriptReviewRecord(id: UUID().uuidString, recordedAt: Date(), baseRevisionID: base,
            resultRevisionID: revisionID, audioSHA256: transcript.provenance.sourceAudioSHA256,
            turns: turns.map { ReviewedTurn(turnID: $0.id, startUs: $0.startUs, endUs: $0.endUs,
                beforeText: before.text(for: $0), afterText: text(for: $0),
                beforeName: before.name(for: $0), afterName: name(for: $0)) },
            audioChecked: audioChecked, error: error, sample: sample, activeSeconds: activeSeconds, note: note)
        reviewRecords = (reviewRecords ?? []) + [record]
    }
    public var reviewSummary: String {
        let records = reviewRecords ?? []
        let measured = records.compactMap(\.activeSeconds)
        let timing = measured.isEmpty ? "수정 시간 미측정" : String(format: "능동 시간 %.1f분 (%d건 측정)", measured.reduce(0, +) / 60, measured.count)
        return "검수 기록 \(records.count)건 · 원음 확인 \(records.filter(\.audioChecked).count)건 · \(timing)"
    }
    public func evaluationData(cost: MonthlyOperatingCost? = nil) throws -> Data {
        try validate(); try cost?.validate()
        struct Report: Encodable {
            let format = "dama-evaluation-1"
            let policy = "operating-baseline-1"
            let measuredAccuracy: Double? = nil
            let caution = "검수는 기록된 표본 범위에 한함. 기록 없음은 오류 0이 아님. 경고 없음도 정답 보증 아님. 학습·승격 자동 적용 없음."
            let script: LibraryScript
            let cost: MonthlyOperatingCost?
            let lexicalTokens: Int
            let unknownLexicalTokens: Int
            let missingSpeechMarkers: Int
            let readingPolicy: String
        }
        let lexical = transcript.words.filter { $0.tokenKind == .lexical }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(Report(script: self, cost: cost, lexicalTokens: lexical.count,
            unknownLexicalTokens: lexical.filter { $0.speakerId == nil }.count,
            missingSpeechMarkers: transcript.turns.filter { $0.kind == .missingSpeech }.count,
            readingPolicy: ScriptReadingPolicy.algorithmVersion))
    }
}

/// Account-entered monthly figures. USD only; unknown values stay nil, including actual free usage.
public struct MonthlyOperatingCost: Codable, Sendable {
    public var month = ""
    public var trialEnds = ""
    public var trialAllowance = ""
    public var normalSubscriptionUSD: Double?
    public var includedCreditUSD: Double?
    public var precisionUsageUSD: Double?
    public var sonioxUsageUSD: Double?
    public var otherCostUSD: Double?
    public var actualBilledUSD: Double?
    public var referenceBillUSD: Double?
    public var evidence = ""
    public init() {}
    public var normalTotalUSD: Double? {
        guard let base = normalSubscriptionUSD, let credit = includedCreditUSD, let p2 = precisionUsageUSD,
              let soniox = sonioxUsageUSD, let other = otherCostUSD else { return nil }
        return base + max(0, p2 - credit) + soniox + other
    }
    public func validate() throws {
        guard [normalSubscriptionUSD, includedCreditUSD, precisionUsageUSD, sonioxUsageUSD,
               otherCostUSD, actualBilledUSD, referenceBillUSD].compactMap({ $0 }).allSatisfy({ $0.isFinite && $0 >= 0 }) else { throw LibraryFailure.invalidInput }
    }
}

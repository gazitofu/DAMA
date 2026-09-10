import Foundation

/// Occurrence counts non-overlapping, literal matches from zero in the immutable request text.
/// It is a text anchor, never an audio offset or a new word timestamp.
public struct CorrectionChange: Codable, Sendable, Equatable {
    public let quote: String
    public let occurrence: Int
    public let replacement: String
    public let certain: Bool
    public let reason: String
    public let termID: String?
}

public struct CorrectionUnresolved: Codable, Sendable, Equatable {
    public let quote: String
    public let occurrence: Int
    public let reason: String
}

public struct CorrectionChangeDecision: Codable, Sendable, Equatable {
    public let change: CorrectionChange
    public let applied: Bool
    public let basis: String
}

enum CorrectionSpans {
    static func range(quote: String, occurrence: Int, in source: String) throws -> Range<String.Index> {
        guard !quote.isEmpty, occurrence >= 0, occurrence <= source.count else { throw LibraryFailure.invalidScript }
        var start = source.startIndex
        for index in 0...occurrence {
            guard let found = source.range(of: quote, options: .literal, range: start..<source.endIndex) else {
                throw LibraryFailure.invalidScript
            }
            if index == occurrence { return found }
            start = found.upperBound
        }
        throw LibraryFailure.invalidScript
    }

    static func ranges(_ changes: [CorrectionChange], source: String) throws -> [Range<String.Index>] {
        guard changes.count <= 100 else { throw LibraryFailure.invalidScript }
        let ranges = try changes.map { change in
            guard change.reason.count <= 600, change.replacement.count <= max(256, source.count * 3) else {
                throw LibraryFailure.invalidScript
            }
            return try range(quote: change.quote, occurrence: change.occurrence, in: source)
        }
        let sorted = ranges.sorted { $0.lowerBound < $1.lowerBound }
        for pair in zip(sorted, sorted.dropFirst()) where pair.0.upperBound > pair.1.lowerBound {
            throw LibraryFailure.invalidScript
        }
        return ranges
    }

    static func compose(source: String, changes: [CorrectionChange], ranges: [Range<String.Index>], accepted: [Bool]) -> String {
        var text = "", cursor = source.startIndex
        for index in changes.indices.sorted(by: { ranges[$0].lowerBound < ranges[$1].lowerBound }) where accepted[index] {
            text += source[cursor..<ranges[index].lowerBound] + changes[index].replacement
            cursor = ranges[index].upperBound
        }
        return text + source[cursor...]
    }

    static func validated(_ candidate: CorrectionReply.Turn, source: CorrectionTurn, input: ConversionNotes) throws -> CorrectionEdit? {
        guard let changes = candidate.changes, var unresolved = candidate.unresolved, unresolved.count <= 100 else {
            throw LibraryFailure.invalidScript
        }
        let anchors = try ranges(changes, source: source.text)
        let proposed = compose(source: source.text, changes: changes, ranges: anchors, accepted: changes.map { _ in true })
        guard proposed == candidate.text else { throw LibraryFailure.invalidScript }
        // A turn-wide uncertainty flag must not disappear if the model omitted its local explanation.
        if !candidate.certain && unresolved.isEmpty && changes.allSatisfy(\.certain) {
            guard !source.text.isEmpty else { throw LibraryFailure.invalidScript }
            unresolved.append(.init(quote: source.text, occurrence: 0,
                                    reason: candidate.reason.isEmpty ? "발화 확인이 필요합니다." : candidate.reason))
        }
        let uncertainRanges = try unresolved.map { item in
            guard !item.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, item.reason.count <= 600 else {
                throw LibraryFailure.invalidScript
            }
            return try range(quote: item.quote, occurrence: item.occurrence, in: source.text)
        }
        var decisions: [CorrectionChangeDecision] = []
        for (index, change) in changes.enumerated() {
            let single = compose(source: source.text, changes: changes, ranges: anchors, accepted: changes.indices.map { $0 == index })
            let format = !single.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                ContextCorrection.canonicalFormat(source.text.trimmingCharacters(in: .whitespacesAndNewlines)) ==
                ContextCorrection.canonicalFormat(single.trimmingCharacters(in: .whitespacesAndNewlines))
            let uncertain = !change.certain || uncertainRanges.contains { $0.overlaps(anchors[index]) }
            let termBasis = CorrectionTerms.basis(change: change, source: source.text, range: anchors[index], input: input)
            let applied = !uncertain && (format || termBasis != nil)
            let basis = uncertain ? "이 수정 범위가 불확실해 원문을 유지했습니다." :
                (format ? "원문 위치와 제한 형식 동등성을 확인했습니다." : termBasis ?? "검증된 용어 대응 근거가 없어 후보로 보존했습니다.")
            decisions.append(.init(change: change, applied: applied, basis: basis))
        }
        let appliedText = compose(source: source.text, changes: changes, ranges: anchors, accepted: decisions.map(\.applied))
        let applied = decisions.allSatisfy(\.applied) && unresolved.isEmpty
        if applied && source.text.trimmingCharacters(in: .whitespacesAndNewlines) == appliedText.trimmingCharacters(in: .whitespacesAndNewlines) {
            return nil
        }
        let reason = (applied ? "수정별 근거를 확인해 반영했습니다." : "확인된 수정만 반영하고 미해결 부분을 보존했습니다.") +
            (candidate.reason.isEmpty ? "" : " " + candidate.reason)
        return CorrectionEdit(turnID: source.id, original: source.text, text: proposed, reason: reason, applied: applied,
                              changes: decisions, unresolved: unresolved, appliedText: appliedText)
    }

    /// New saved records must reproduce both the proposed text and the independently accepted text.
    /// Legacy records have none of these optional fields and retain their previous decisions.
    static func validateStored(_ edit: CorrectionEdit) throws {
        guard edit.changes != nil || edit.unresolved != nil || edit.appliedText != nil else { return }
        guard let decisions = edit.changes, let unresolved = edit.unresolved, let acceptedText = edit.appliedText,
              unresolved.count <= 100 else { throw LibraryFailure.invalidScript }
        let changes = decisions.map(\.change), anchors = try ranges(changes, source: edit.original)
        guard compose(source: edit.original, changes: changes, ranges: anchors, accepted: changes.map { _ in true }) == edit.text,
              compose(source: edit.original, changes: changes, ranges: anchors, accepted: decisions.map(\.applied)) == acceptedText,
              edit.applied == (decisions.allSatisfy(\.applied) && unresolved.isEmpty) else { throw LibraryFailure.invalidScript }
        for item in unresolved {
            guard !item.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, item.reason.count <= 600 else { throw LibraryFailure.invalidScript }
            _ = try range(quote: item.quote, occurrence: item.occurrence, in: edit.original)
        }
    }

    static var outputSchema: Data {
        func object(_ properties: [String: Any]) -> [String: Any] {
            ["type": "object", "properties": properties, "required": properties.keys.sorted(), "additionalProperties": false]
        }
        func array(_ items: [String: Any]) -> [String: Any] { ["type": "array", "items": items] }
        let string: [String: Any] = ["type": "string"]
        let change = object(["quote": string, "occurrence": ["type": "integer", "minimum": 0], "replacement": string,
                             "certain": ["type": "boolean"], "reason": string, "termID": ["type": ["string", "null"]]])
        let unresolved = object(["quote": string, "occurrence": ["type": "integer", "minimum": 0], "reason": string])
        let turn = object(["id": string, "text": string, "certain": ["type": "boolean"], "reason": string,
                           "changes": array(change), "unresolved": array(unresolved)])
        let name = object(["speakerID": string, "name": string, "evidenceTurnID": string, "quote": string])
        return try! JSONSerialization.data(withJSONObject: object(["turns": array(turn), "names": array(name)]), options: [.sortedKeys])
    }
}

import Foundation
import CryptoKit

/// Explicit user-authored spelling mappings, scoped to this recording's context and source turn.
/// Text in external excerpts is never promoted to a user instruction by this parser.
public struct CorrectionTerm: Codable, Sendable, Equatable {
    public let id: String
    public let topic: String
    public let source: String
    public let replacement: String
    public let sourceLine: String
    public let referenceSHA256: String
}

public enum CorrectionTerms {
    /// Reference field syntax: 용어 | 주제 | 원표기 | 표준표기
    /// Exact explicit mappings are authority for spelling, not evidence of what was spoken.
    public static func entries(input: ConversionNotes) -> [CorrectionTerm] {
        let digest = SHA256.hash(data: Data(input.reference.utf8)).map { String(format: "%02x", $0) }.joined()
        let terms = input.reference.components(separatedBy: .newlines).enumerated().compactMap { index, line -> CorrectionTerm? in
            let fields = line.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            guard fields.count == 4, fields[0] == "용어", (2...60).contains(fields[1].count),
                  (2...60).contains(fields[2].count), (2...60).contains(fields[3].count), fields[2] != fields[3],
                  input.context.range(of: fields[1], options: .literal) != nil,
                  spellingOnly(fields[2]), spellingOnly(fields[3]) else { return nil }
            return CorrectionTerm(id: "reference:\(index + 1):\(digest)", topic: fields[1], source: fields[2],
                                  replacement: fields[3], sourceLine: line, referenceSHA256: digest)
        }
        // Conflicting explicit spellings cannot be chosen by model certainty or response order.
        return terms.filter { term in
            Set(terms.filter { $0.source == term.source }.map(\.replacement)).count == 1
        }
    }

    private static func spellingOnly(_ text: String) -> Bool {
        guard text.unicodeScalars.allSatisfy({ CharacterSet.letters.contains($0) || $0 == " " }) else { return false }
        let protected = Set(["안", "못", "않다", "아니다", "없다", "있다", "이상", "이하", "미만", "초과",
                             "억", "만", "천", "백", "조", "원", "kw", "kwh", "mw", "mwh", "gw", "gwh", "kg", "mg", "km"])
        return text.split(separator: " ").allSatisfy { !protected.contains($0.lowercased()) }
    }

    static func basis(change: CorrectionChange, source: String, range: Range<String.Index>, input: ConversionNotes) -> String? {
        guard let id = change.termID,
              let term = entries(input: input).first(where: { $0.id == id }),
              change.quote == term.source, change.replacement == term.replacement,
              let topicRange = source.range(of: term.topic, options: .literal), !topicRange.overlaps(range) else { return nil }
        // Don't replace the interior of another word. Korean suffixes must be part of the explicit mapping.
        if range.lowerBound > source.startIndex {
            let previous = source[source.index(before: range.lowerBound)]
            if previous.isLetter || previous.isNumber { return nil }
        }
        if range.upperBound < source.endIndex {
            let next = source[range.upperBound]
            if next.isLetter || next.isNumber { return nil }
        }
        return "사용자가 지정한 표기 대응·원 발화 주제어 일치: \(term.sourceLine)"
    }
}

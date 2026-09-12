import Foundation

/// Shared time evidence for Qwen+P2 and Soniox+P2. Callers own assignment and issue policy.
enum P2TimeEvidence {
    struct Score: Sendable {
        let speakerID: String
        let coverage: Double
    }
    struct Token: Sendable {
        let regularMatches: [DiarizationInterval]
        let sourceIDs: [String]
        let scores: [Score]
        let overlap: Bool
        let boundary: Bool
        var best: Score? { scores.first }
    }
    static func intervals(_ source: [PyannoteDiarizationDTO], prefix: String,
                          mapping: [String: String], durationUs: Int64) throws -> [DiarizationInterval] {
        try source.enumerated().map { i, value in
            guard value.start.isFinite, value.end.isFinite, value.start >= 0, value.end > value.start,
                  value.end * 1e6 <= Double(durationUs), let speaker = mapping[value.speaker] else {
                throw ManagedNormalizationError.invalidIntervals
            }
            // Preserve source order/IDs and the existing seconds-to-microseconds rounding.
            return DiarizationInterval(id: "\(prefix)\(i)", startUs: Int64((value.start * 1e6).rounded()),
                endUs: Int64((value.end * 1e6).rounded()), speakerId: speaker, confidence: value.confidence)
        }
    }
    static func token(startUs: Int64?, endUs: Int64?, regular: [DiarizationInterval],
                      exclusive: [DiarizationInterval]) -> Token {
        guard let s = startUs, let e = endUs, s < e else {
            return Token(regularMatches: [], sourceIDs: [], scores: [], overlap: false, boundary: false)
        }
        // Half-open ranges: [0,100) and [100,200) do not intersect.
        let matches = regular.filter { max(s, $0.startUs) < min(e, $0.endUs) }
        let candidates = exclusive.filter { max(s, $0.startUs) < min(e, $0.endUs) }
        let overlap = matches.enumerated().contains { i, a in matches.dropFirst(i + 1).contains { b in
            a.speakerId != b.speakerId && max(s, a.startUs, b.startUs) < min(e, a.endUs, b.endUs)
        } }
        var scores: [Score] = []
        for speaker in Set(candidates.map(\.speakerId)) {
            var total: Int64 = 0, edge = s
            for interval in candidates.filter({ $0.speakerId == speaker }).sorted(by: { $0.startUs < $1.startUs }) {
                let a = max(s, interval.startUs, edge), b = min(e, interval.endUs)
                if b > a { total += b - a; edge = b }
            }
            scores.append(Score(speakerID: speaker, coverage: Double(total) / Double(e - s)))
        }
        // B=0.8 precedes A=0.2; for A=B=0.5, A precedes B.
        scores.sort { $0.coverage == $1.coverage ? $0.speakerID < $1.speakerID : $0.coverage > $1.coverage }
        let evidence = matches + candidates
        return Token(regularMatches: matches, sourceIDs: evidence.map(\.id), scores: scores, overlap: overlap,
                     boundary: Set(evidence.map(\.speakerId)).count > 1)
    }
    static func matchingWordIndices(_ words: [TranscriptWord], interval: DiarizationInterval,
                                    lexicalOnly: Bool) -> [Int] {
        words.indices.filter { i in
            guard !lexicalOnly || words[i].tokenKind == .lexical,
                  let s = words[i].startUs, let e = words[i].endUs else { return false }
            return max(s, interval.startUs) < min(e, interval.endUs)
        }
    }
}

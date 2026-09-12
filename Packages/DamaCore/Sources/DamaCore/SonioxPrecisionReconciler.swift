import Foundation

/// Explicit, offline comparison policies. Managed processing still defaults to soniox-p2-v2.
public enum SonioxPrecisionComparison: String, CaseIterable, Sendable {
    case timeline = "soniox-p2-timeline-v3"
    case word = "soniox-p2-word-v3"
}

public enum SonioxPrecisionReconciler {
    private struct Choice {
        var speaker: String?
        var sourceIDs: [String]
        var coverage: Double?
        var overlap: Bool
        var boundary: Bool
    }

    public static func reconcile(_ source: TranscriptDocument, runID: String, createdAt: String,
                                 policy: SonioxPrecisionComparison) throws -> TranscriptDocument {
        try TranscriptValidator().validate(source)
        guard source.provenance.engine == .hybridSonioxPyannote,
              source.provenance.algorithmVersion == SonioxPrecisionNormalizer.version,
              !source.revision.humanEdited, source.words.allSatisfy({ $0.editedText == nil }),
              UUID(uuidString: runID) != nil, runID != source.runId else { throw LibraryFailure.invalidInput }
        var doc = source
        let mapping = Dictionary(uniqueKeysWithValues: source.speakers.enumerated().map { ($0.element.id, "\(runID)-p2-\($0.offset)") })
        doc.runId = runID
        for i in doc.speakers.indices { doc.speakers[i].id = mapping[doc.speakers[i].id]! }
        for i in doc.diarization.indices { doc.diarization[i].speakerId = mapping[doc.diarization[i].speakerId]! }
        for i in doc.exclusiveDiarization.indices { doc.exclusiveDiarization[i].speakerId = mapping[doc.exclusiveDiarization[i].speakerId]! }
        doc.provenance.algorithmVersion = policy.rawValue; doc.provenance.createdAt = createdAt
        doc.revision = RevisionMetadata(id: "model-\(runID)", baseRevisionId: nil,
            sourceRunId: runID, humanEdited: false, savedAt: createdAt)

        var choices = doc.words.map { direct($0, regular: doc.diarization, exclusive: doc.exclusiveDiarization) }
        if policy == .word {
            for group in orthographicGroups(doc.words) {
                shareWordEvidence(group, words: doc.words, choices: &choices,
                    regular: doc.diarization, exclusive: doc.exclusiveDiarization)
            }
        }
        attachClosingPunctuation(words: doc.words, choices: &choices)

        var issues: [ReviewIssue] = []
        func flag(_ kind: IssueKind, _ start: Int64?, _ end: Int64?, _ words: [String], _ intervals: [String]) -> String {
            let id = "i\(issues.count)"
            issues.append(ReviewIssue(id: id, kind: kind, startUs: start, endUs: end, severity: .warning,
                status: .open, wordIds: words, sourceIntervalIds: intervals))
            return id
        }
        for i in doc.words.indices {
            var w = doc.words[i]; let choice = choices[i]
            w.speakerId = choice.speaker; w.modelSpeakerId = choice.speaker
            w.assignmentSource = choice.speaker == nil ? .unknown : .reconciled
            w.alignmentScore = choice.coverage; w.sourceIntervalIds = choice.sourceIDs
            w.overlap = choice.overlap; w.reviewIssueIds = []
            if w.startUs == nil || w.endUs == nil || w.startUs == w.endUs {
                w.reviewIssueIds.append(flag(.invalid_timestamp, w.startUs, w.endUs, [w.id], choice.sourceIDs))
            }
            if choice.speaker == nil { w.reviewIssueIds.append(flag(.ambiguous_speaker, w.startUs, w.endUs, [w.id], choice.sourceIDs)) }
            if choice.boundary { w.reviewIssueIds.append(flag(.boundary_conflict, w.startUs, w.endUs, [w.id], choice.sourceIDs)) }
            if choice.overlap { w.reviewIssueIds.append(flag(.overlapping_speech, w.startUs, w.endUs, [w.id], choice.sourceIDs)) }
            doc.words[i] = w
        }
        var previous: Int?
        for i in doc.words.indices where doc.words[i].tokenKind == .lexical {
            guard let a = doc.words[i].asrSpeakerLabel, let b = doc.words[i].speakerId else { previous = nil; continue }
            if let j = previous, let oldA = doc.words[j].asrSpeakerLabel, let oldB = doc.words[j].speakerId,
               (a != oldA) != (b != oldB) {
                let evidence = Array(Set(doc.words[j].sourceIntervalIds + doc.words[i].sourceIntervalIds)).sorted()
                let id = flag(.provider_disagreement, doc.words[j].startUs, doc.words[i].endUs,
                    [doc.words[j].id, doc.words[i].id], evidence)
                doc.words[j].reviewIssueIds.append(id); doc.words[i].reviewIssueIds.append(id)
            }
            previous = i
        }
        var markers: [TranscriptTurn] = []
        for d in doc.diarization {
            let matches = doc.words.indices.filter { i in
                let w = doc.words[i]
                guard w.tokenKind == .lexical, let s = w.startUs, let e = w.endUs else { return false }
                return s == e ? d.startUs <= s && s < d.endUs : max(s, d.startUs) < min(e, d.endUs)
            }
            if matches.isEmpty {
                let id = flag(.missing_speech, d.startUs, d.endUs, [], [d.id])
                markers.append(TranscriptTurn(id: "m\(markers.count)", kind: .missingSpeech,
                    startUs: d.startUs, endUs: d.endUs, speakerId: d.speakerId, wordIds: [],
                    markerText: "[음성 감지 / 전사 누락 의심]", reviewed: false, reviewIssueIds: [id]))
            } else if !matches.contains(where: { doc.words[$0].speakerId == d.speakerId }) {
                let id = flag(.unrepresented_speaker, d.startUs, d.endUs, matches.map { doc.words[$0].id }, [d.id])
                for i in matches { doc.words[i].reviewIssueIds.append(id) }
            }
        }
        for issue in source.reviewIssues where issue.kind == .capture_interrupted || issue.kind == .partial_result {
            _ = flag(issue.kind, issue.startUs, issue.endUs, issue.wordIds, issue.sourceIntervalIds)
        }
        doc.reviewIssues = issues
        doc.turns = doc.words.enumerated().map { i, w in TranscriptTurn(id: "t\(i)", kind: .speech,
            startUs: w.startUs, endUs: w.endUs, speakerId: w.speakerId, wordIds: [w.id],
            markerText: nil, reviewed: false, reviewIssueIds: w.reviewIssueIds) }
        for marker in markers.sorted(by: { $0.startUs! < $1.startUs! }) {
            doc.turns.insert(marker, at: doc.turns.firstIndex { ($0.startUs ?? Int64.min) >= marker.startUs! } ?? doc.turns.endIndex)
        }
        if policy == .word { doc.turns = speakerTurns(doc) }
        try TranscriptValidator().validate(doc)
        return doc
    }

    private static func direct(_ w: TranscriptWord, regular: [DiarizationInterval], exclusive: [DiarizationInterval]) -> Choice {
        guard let s = w.startUs, let e = w.endUs else {
            return Choice(sourceIDs: [], overlap: false, boundary: false)
        }
        if s == e {
            let candidates = exclusive.filter { $0.startUs <= s && s < $0.endUs }
            let matches = regular.filter { $0.startUs <= s && s < $0.endUs }
            let labels = Set(candidates.map(\.speakerId))
            return Choice(speaker: labels.count == 1 ? labels.first : nil,
                sourceIDs: (matches + candidates).map(\.id), coverage: nil,
                overlap: Set(matches.map(\.speakerId)).count > 1,
                boundary: Set((matches + candidates).map(\.speakerId)).count > 1)
        }
        let evidence = P2TimeEvidence.token(startUs: s, endUs: e, regular: regular, exclusive: exclusive)
        let best = evidence.best
        let tied = evidence.scores.count > 1 && evidence.scores[1].coverage == best?.coverage
        return Choice(speaker: tied ? nil : best?.speakerID, sourceIDs: evidence.sourceIDs,
            coverage: best?.coverage, overlap: evidence.overlap, boundary: evidence.boundary)
    }

    private static func orthographicGroups(_ words: [TranscriptWord]) -> [[Int]] {
        var groups: [[Int]] = [], current: [Int] = []
        for i in words.indices {
            let text = words[i].prefix + words[i].text
            if text.first?.isWhitespace == true || text.contains("\n") {
                if !current.isEmpty { groups.append(current); current = [] }
            }
            current.append(i)
            if text.last?.isWhitespace == true {
                groups.append(current); current = []
            }
        }
        if !current.isEmpty { groups.append(current) }
        return groups
    }

    private static func shareWordEvidence(_ group: [Int], words: [TranscriptWord], choices: inout [Choice],
                                          regular: [DiarizationInterval], exclusive: [DiarizationInterval]) {
        let lexical = group.filter { words[$0].tokenKind == .lexical }
        guard lexical.count > 1,
              lexical.allSatisfy({ words[$0].startUs != nil && words[$0].endUs != nil }),
              let start = lexical.compactMap({ words[$0].startUs }).min(),
              let end = lexical.compactMap({ words[$0].endUs }).max(), start < end else { return }
        let evidence = P2TimeEvidence.token(startUs: start, endUs: end, regular: regular, exclusive: exclusive)
        guard evidence.scores.count == 1, let best = evidence.best else { return }
        for (left, right) in zip(lexical, lexical.dropFirst()) {
            guard words[left].startUs! <= words[right].startUs! else { return }
            let a = words[left].endUs!, b = words[right].startUs!
            if a < b && regular.contains(where: { $0.speakerId != best.speakerID && max(a, $0.startUs) < min(b, $0.endUs) }) { return }
        }
        // A point token at the right edge may already belong to the next speaker.
        guard lexical.allSatisfy({ choices[$0].speaker == nil || choices[$0].speaker == best.speakerID }) else { return }
        for i in lexical where choices[i].speaker == nil {
            choices[i].speaker = best.speakerID
            choices[i].sourceIDs = Array(Set(choices[i].sourceIDs + evidence.sourceIDs)).sorted()
            choices[i].coverage = nil // Word-level support is not this token's coverage.
        }
    }

    private static func attachClosingPunctuation(words: [TranscriptWord], choices: inout [Choice]) {
        let closing = CharacterSet(charactersIn: ".,?!。？！…，、:;\"'”’)]}」』").union(.whitespaces)
        var previousLexical: Int?
        for i in words.indices {
            let text = words[i].prefix + words[i].text
            if text.contains("\n") || text.contains("\r") { previousLexical = nil }
            if words[i].tokenKind == .lexical { previousLexical = i; continue }
            guard !text.isEmpty, text.unicodeScalars.allSatisfy(closing.contains), let j = previousLexical else { continue }
            // Punctuation follows the preceding text; it is not a separate acoustic utterance.
            choices[i].speaker = choices[j].speaker
            choices[i].sourceIDs = Array(Set(choices[i].sourceIDs + choices[j].sourceIDs)).sorted()
            choices[i].coverage = nil
        }
    }

    private static func speakerTurns(_ doc: TranscriptDocument) -> [TranscriptTurn] {
        let words = Dictionary(uniqueKeysWithValues: doc.words.map { ($0.id, $0) })
        let barriers = doc.turns.filter { $0.kind == .missingSpeech }.compactMap { t -> (Int64, Int64)? in
            guard let s = t.startUs, let e = t.endUs else { return nil }; return (s,e)
        } + doc.reviewIssues.filter { $0.kind == .capture_interrupted }.compactMap { issue -> (Int64, Int64)? in
            guard let s = issue.startUs, let e = issue.endUs else { return nil }; return (s,e)
        }
        var result: [TranscriptTurn] = []
        for next in doc.turns {
            if let previous = result.last, previous.kind == .speech, next.kind == .speech,
               let speaker = previous.speakerId, speaker == next.speakerId,
               let leftID = previous.wordIds.last, let rightID = next.wordIds.first,
               let left = words[leftID], let right = words[rightID],
               let a = left.startUs, let b = left.endUs, let c = right.startUs, let d = right.endUs,
               a <= c, left.modelSpeakerId == right.modelSpeakerId,
               !(b <= c && barriers.contains { max(b, $0.0) < min(c, $0.1) }),
               !(b <= c && (doc.diarization + doc.exclusiveDiarization).contains {
                   $0.speakerId != speaker && max(b, $0.startUs) < min(c, $0.endUs)
               }) {
                result[result.count - 1].wordIds += next.wordIds
                result[result.count - 1].endUs = max(previous.endUs!, d)
                result[result.count - 1].reviewIssueIds = Array(Set(previous.reviewIssueIds + next.reviewIssueIds)).sorted()
            } else { result.append(next) }
        }
        return result
    }
}

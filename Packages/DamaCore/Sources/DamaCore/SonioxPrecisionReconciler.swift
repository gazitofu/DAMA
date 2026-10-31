import Foundation

/// Versioned policies; wordRepair is also used by newly created managed runs.
public enum SonioxPrecisionComparison: String, CaseIterable, Sendable {
    case timeline = "soniox-p2-timeline-v3"
    case word = "soniox-p2-word-v3"
    case wordRepair = "soniox-p2-word-v4"
    case wordAtomic = "soniox-p2-word-v5"
}

extension SonioxPrecisionComparison {
    /// v4부터의 어절/문장부호 보완을 쓰는 정책.
    var repairsWords: Bool { self == .wordRepair || self == .wordAtomic }
}

public enum SonioxPrecisionReconciler {
    /// Normalize provider bytes for a new run without creating or saving an intermediate v2 run.
    public static func normalize(soniox: Data, diarization: Data, sonioxJobID: String,
                                 sessionID: String, runID: String, durationUs: Int64,
                                 audioSHA256: String, model: String, createdAt: String,
                                 synthetic: Bool = false, captureInterrupted: Bool = false) throws -> TranscriptDocument {
        guard UUID(uuidString: runID) != nil else { throw LibraryFailure.invalidInput }
        let source = try SonioxPrecisionNormalizer.normalize(soniox: soniox, diarization: diarization,
            sonioxJobID: sonioxJobID, sessionID: sessionID, runID: runID, durationUs: durationUs,
            audioSHA256: audioSHA256, model: model, createdAt: createdAt,
            synthetic: synthetic, captureInterrupted: captureInterrupted)
        return try applying(source, runID: runID, createdAt: createdAt, policy: .wordRepair)
    }

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
        return try applying(source, runID: runID, createdAt: createdAt, policy: policy)
    }

    /// `keepsSpeakerIDs` is for a base already built with this run's IDs (Nemotron); P2 sources are re-mapped.
    static func applying(_ source: TranscriptDocument, runID: String, createdAt: String,
                         policy: SonioxPrecisionComparison, version: String? = nil,
                         keepsSpeakerIDs: Bool = false, unifiesSplitWords: Bool = false) throws -> TranscriptDocument {
        var doc = source
        let mapping = Dictionary(uniqueKeysWithValues: source.speakers.enumerated().map {
            ($0.element.id, keepsSpeakerIDs ? $0.element.id : "\(runID)-p2-\($0.offset)")
        })
        doc.runId = runID
        for i in doc.speakers.indices { doc.speakers[i].id = mapping[doc.speakers[i].id]! }
        for i in doc.diarization.indices { doc.diarization[i].speakerId = mapping[doc.diarization[i].speakerId]! }
        for i in doc.exclusiveDiarization.indices { doc.exclusiveDiarization[i].speakerId = mapping[doc.exclusiveDiarization[i].speakerId]! }
        doc.provenance.algorithmVersion = version ?? policy.rawValue; doc.provenance.createdAt = createdAt
        doc.revision = RevisionMetadata(id: "model-\(runID)", baseRevisionId: nil,
            sourceRunId: runID, humanEdited: false, savedAt: createdAt)

        var choices = doc.words.map {
            policy.repairsWords && $0.tokenKind == .punctuation
                ? Choice(sourceIDs: [], overlap: false, boundary: false)
                : direct($0, regular: doc.diarization, exclusive: doc.exclusiveDiarization)
        }
        if policy != .timeline {
            for group in orthographicGroups(doc.words) {
                shareWordEvidence(group, words: doc.words, choices: &choices,
                    regular: doc.diarization, exclusive: doc.exclusiveDiarization)
            }
        }
        if policy.repairsWords {
            sharePhraseTailEvidence(words: doc.words, choices: &choices,
                regular: doc.diarization, exclusive: doc.exclusiveDiarization)
        }
        if unifiesSplitWords { unifySplitWords(words: doc.words, choices: &choices) }
        if policy == .wordAtomic {
            for group in orthographicGroups(doc.words) {
                resolveWordAtomicity(group, words: doc.words, choices: &choices,
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
            let acoustic = !policy.repairsWords || w.tokenKind == .lexical
            if acoustic && (w.startUs == nil || w.endUs == nil || w.startUs == w.endUs) {
                w.reviewIssueIds.append(flag(.invalid_timestamp, w.startUs, w.endUs, [w.id], choice.sourceIDs))
            }
            if acoustic && choice.speaker == nil { w.reviewIssueIds.append(flag(.ambiguous_speaker, w.startUs, w.endUs, [w.id], choice.sourceIDs)) }
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
        if policy != .timeline { doc.turns = speakerTurns(doc) }
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

    /// 한 어절을 두 사람이 나눠 말할 수는 없다. v4가 어절 안에서 화자를 갈라 둔 경우에만,
    /// 어절 전체 구간의 exclusive coverage 최대 화자로 통일한다. 동률이면 그대로 둔다.
    private static func resolveWordAtomicity(_ group: [Int], words: [TranscriptWord], choices: inout [Choice],
                                             regular: [DiarizationInterval], exclusive: [DiarizationInterval]) {
        let lexical = group.filter { words[$0].tokenKind == .lexical }
        guard lexical.count > 1,
              Set(lexical.map { choices[$0].speaker }).count > 1,
              lexical.allSatisfy({ words[$0].startUs != nil && words[$0].endUs != nil }),
              let start = lexical.compactMap({ words[$0].startUs }).min(),
              let end = lexical.compactMap({ words[$0].endUs }).max(), start < end else { return }
        let evidence = P2TimeEvidence.token(startUs: start, endUs: end, regular: regular, exclusive: exclusive)
        guard let best = evidence.best,
              !(evidence.scores.count > 1 && evidence.scores[1].coverage == best.coverage) else { return }
        for i in lexical {
            choices[i].speaker = best.speakerID
            choices[i].sourceIDs = Array(Set(choices[i].sourceIDs + evidence.sourceIDs)).sorted()
            choices[i].coverage = nil // 어절 단위 근거는 이 토큰의 coverage가 아니다.
        }
    }

    /// 한 어절 안 lexical이 서로 다른 두 화자 이상으로 갈린 어절만, 같은 문장 안에서 Soniox 후보가 같고
    /// 한 화자로 배정된 앞·뒤 이웃 어절의 화자가 하나일 때 그 화자로 맞춘다. 판정은 진입 시점 배정 한 장으로 한다.
    /// 미배정 조각과 어절 하나 섬(A [B] A)은 건드리지 않는다.
    private static func unifySplitWords(words: [TranscriptWord], choices: inout [Choice]) {
        let sentenceEnds = CharacterSet(charactersIn: ".?!。？！…")
        struct Word { let lexical: [Int]; let speaker: String?; let asr: String?; let ends: Bool; let split: Bool }
        let snapshot = choices
        let list: [Word] = orthographicGroups(words).compactMap { group in
            let lexical = group.filter { words[$0].tokenKind == .lexical }
            guard !lexical.isEmpty else { return nil }
            let speakers = Set(lexical.map { snapshot[$0].speaker }), labels = Set(lexical.map { words[$0].asrSpeakerLabel })
            let ends = group.contains { i in
                (words[i].prefix + words[i].text).contains("\n") || words[i].text.unicodeScalars.contains(where: sentenceEnds.contains)
            }
            return Word(lexical: lexical, speaker: speakers.count == 1 ? speakers.first! : nil,
                        asr: labels.count == 1 ? labels.first! : nil, ends: ends,
                        split: Set(lexical.compactMap { snapshot[$0].speaker }).count > 1)
        }
        for (n, word) in list.enumerated() where word.split {
            guard let label = word.asr else { continue }
            var neighbours: [Word] = []
            if n > 0, !list[n - 1].ends { neighbours.append(list[n - 1]) }
            if n + 1 < list.count, !word.ends { neighbours.append(list[n + 1]) }
            let eligible = neighbours.filter { $0.asr == label && $0.speaker != nil }
            let speakers = Set(eligible.compactMap(\.speaker))
            guard speakers.count == 1, let speaker = speakers.first else { continue }
            let support = eligible.flatMap { $0.lexical.flatMap { snapshot[$0].sourceIDs } }
            for i in word.lexical where snapshot[i].speaker != nil && snapshot[i].speaker != speaker {
                choices[i].speaker = speaker
                choices[i].sourceIDs = Array(Set(snapshot[i].sourceIDs + support)).sorted()
                choices[i].coverage = nil // 이웃 어절 근거는 이 토큰의 coverage가 아니다.
            }
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

    /// Initial, deliberately bounded comparison rule, not a measured accuracy threshold.
    private static let maximumTailUs: Int64 = 500_000
    private static func sharePhraseTailEvidence(words: [TranscriptWord], choices: inout [Choice],
                                                 regular: [DiarizationInterval], exclusive: [DiarizationInterval]) {
        var phrases: [[Int]] = [], phrase: [Int] = [], asr: String?
        let boundaries = CharacterSet(charactersIn: ",;:，、；：.!?。？！…—\n\r")
        for i in words.indices {
            let word = words[i], text = word.prefix + word.text
            if text.contains("\n") || text.contains("\r") {
                if !phrase.isEmpty { phrases.append(phrase); phrase = [] }; asr = nil
            }
            if word.tokenKind == .lexical {
                if !phrase.isEmpty && (word.asrSpeakerLabel == nil || word.asrSpeakerLabel != asr) {
                    phrases.append(phrase); phrase = []
                }
                phrase.append(i); asr = word.asrSpeakerLabel
            }
            if text.unicodeScalars.contains(where: boundaries.contains) {
                if !phrase.isEmpty { phrases.append(phrase); phrase = [] }; asr = nil
            }
        }
        if !phrase.isEmpty { phrases.append(phrase) }
        for phrase in phrases {
            guard let firstUnknown = phrase.firstIndex(where: { choices[$0].speaker == nil }), firstUnknown > 0 else { continue }
            let supported = Array(phrase[..<firstUnknown]), tail = Array(phrase[firstUnknown...])
            let speakers = Set(supported.compactMap { choices[$0].speaker })
            guard speakers.count == 1, let speaker = speakers.first,
                  phrase.allSatisfy({ words[$0].asrSpeakerLabel != nil && words[$0].asrSpeakerLabel == words[phrase[0]].asrSpeakerLabel }),
                  tail.allSatisfy({ choices[$0].speaker == nil && choices[$0].sourceIDs.isEmpty }),
                  let anchorEnd = words[supported.last!].endUs, let start = words[tail[0]].startUs,
                  let end = words[tail.last!].endUs,
                  start >= anchorEnd, start - anchorEnd <= maximumTailUs,
                  end >= start, end - start <= maximumTailUs else { continue }
            // Only one trailing orthographic word; never bridge a sentence, comma, or another voice.
            guard zip(tail, tail.dropFirst()).allSatisfy({ left, right in
                let between = words[(left + 1)...right].map { $0.prefix + $0.text }.joined()
                return !between.contains(where: \.isWhitespace)
            }),
            zip(phrase, phrase.dropFirst()).allSatisfy({ left, right in
                guard let a = words[left].startUs, let b = words[right].startUs else { return false }
                return a <= b
            }),
            !(regular + exclusive).contains(where: { $0.speakerId != speaker && max(anchorEnd, $0.startUs) < min(end, $0.endUs) }) else { continue }
            let evidence = Array(Set(supported.flatMap { choices[$0].sourceIDs })).sorted()
            for i in tail {
                choices[i].speaker = speaker; choices[i].sourceIDs = evidence; choices[i].coverage = nil
            }
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

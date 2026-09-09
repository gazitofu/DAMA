import Foundation

public enum ManagedNormalizationError: Error, Sendable {
    case partialResult, invalidIntervals
}

public enum ManagedNormalizer {
    public static func normalize(_ data: Data, sessionID: String, runID: String, durationUs: Int64,
                                 audioSHA256: String, captureInterrupted: Bool = false,
                                 synthetic: Bool = false, createdAt: String) throws -> TranscriptDocument {
        let job = try JSONDecoder().decode(PyannoteJobDTO.self, from: data)
        guard job.status == "succeeded", let output = job.output,
              output.error == nil, let tokens = output.wordLevelTranscription, !tokens.isEmpty else {
            throw ManagedNormalizationError.partialResult
        }
        let rawIntervals = output.diarization + (output.exclusiveDiarization ?? [])
        let labels = Set(rawIntervals.map(\.speaker) + rawIntervals.flatMap { Array(($0.confidence ?? [:]).keys) })
            .filter { !$0.isEmpty }.sorted()
        let speakers = labels.enumerated().map {
            Speaker(id: "\(runID)-speaker-\($0.offset)", providerId: $0.element, displayName: "화자 \($0.offset + 1)")
        }
        let mapping = Dictionary(uniqueKeysWithValues: speakers.map { ($0.providerId, $0.id) })
        func time(_ start: Double, _ end: Double) -> (Int64, Int64)? {
            guard start.isFinite, end.isFinite, start >= 0, end >= start,
                  end * 1_000_000 < Double(Int64.max) else { return nil }
            let s = Int64((start * 1_000_000).rounded()), e = Int64((end * 1_000_000).rounded())
            return e <= durationUs ? (s, e) : nil
        }
        func intervals(_ source: [PyannoteDiarizationDTO], prefix: String) throws -> [DiarizationInterval] {
            try source.enumerated().map { n, value in
                guard let (s, e) = time(value.start, value.end), e > s,
                      let speaker = mapping[value.speaker] else { throw ManagedNormalizationError.invalidIntervals }
                return DiarizationInterval(id: "\(prefix)\(n)", startUs: s, endUs: e, speakerId: speaker, confidence: value.confidence)
            }
        }
        let regular = try intervals(output.diarization, prefix: "d")
        let exclusive = try intervals(output.exclusiveDiarization ?? [], prefix: "e")
        var issues: [ReviewIssue] = []
        @discardableResult func issue(_ kind: IssueKind, start: Int64?, end: Int64?, words: [String], sources: [String], severity: IssueSeverity = .warning) -> String {
            let id = "i\(issues.count)"
            issues.append(ReviewIssue(id: id, kind: kind, startUs: start, endUs: end, severity: severity,
                                      status: .open, wordIds: words, sourceIntervalIds: sources))
            return id
        }
        var words = tokens.enumerated().map { index, token -> TranscriptWord in
            let id = "w\(index)"
            let range = time(token.start, token.end)
            let speaker = mapping[token.speaker]
            var flags: [String] = []
            let matches = regular.filter { interval in
                guard let (s, e) = range else { return false }
                return max(s, interval.startUs) < min(e, interval.endUs)
            }
            let overlapping = matches.enumerated().contains { n, left in
                matches.dropFirst(n + 1).contains { right in
                    guard let (s, e) = range else { return false }
                    return left.speakerId != right.speakerId && max(s, left.startUs, right.startUs) < min(e, left.endUs, right.endUs)
                }
            }
            if range == nil || range?.0 == range?.1 {
                flags.append(issue(.invalid_timestamp, start: range?.0, end: range?.1, words: [id], sources: []))
            }
            if speaker == nil { flags.append(issue(.ambiguous_speaker, start: range?.0, end: range?.1, words: [id], sources: matches.map(\.id))) }
            if overlapping { flags.append(issue(.overlapping_speech, start: range?.0, end: range?.1, words: [id], sources: matches.map(\.id))) }
            if Set(matches.map(\.speakerId)).count > 1 || matches.contains(where: { $0.speakerId != speaker }) {
                flags.append(issue(.boundary_conflict, start: range?.0, end: range?.1, words: [id], sources: matches.map(\.id)))
            }
            let punctuation = !token.text.isEmpty && token.text.unicodeScalars.allSatisfy { CharacterSet.punctuationCharacters.contains($0) || CharacterSet.whitespaces.contains($0) }
            return TranscriptWord(id: id, ordinal: index, text: token.text, editedText: nil,
                prefix: index == 0 || token.text.first?.isWhitespace == true || punctuation ? "" : " ",
                startUs: range?.0, endUs: range?.1, modelSpeakerId: speaker, speakerId: speaker,
                assignmentSource: speaker == nil ? .unknown : .provider, alignmentScore: nil, overlap: overlapping,
                reviewIssueIds: flags, sourceIntervalIds: matches.map(\.id), timingOrigin: range == nil ? .none : .model,
                tokenKind: punctuation ? .punctuation : .lexical)
        }
        var markers: [TranscriptTurn] = []
        for interval in regular {
            let matches = words.indices.filter { i in
                guard words[i].tokenKind == .lexical, let s = words[i].startUs, let e = words[i].endUs else { return false }
                return max(s, interval.startUs) < min(e, interval.endUs)
            }
            if matches.isEmpty {
                let id = issue(.missing_speech, start: interval.startUs, end: interval.endUs, words: [], sources: [interval.id],
                               severity: interval.endUs - interval.startUs >= 150_000 ? .warning : .info)
                markers.append(TranscriptTurn(id: "m\(markers.count)", kind: .missingSpeech, startUs: interval.startUs,
                    endUs: interval.endUs, speakerId: interval.speakerId, wordIds: [],
                    markerText: "[음성 감지 / 전사 누락 의심]", reviewed: false, reviewIssueIds: [id]))
            } else if !matches.contains(where: { words[$0].speakerId == interval.speakerId }) {
                let id = issue(.unrepresented_speaker, start: interval.startUs, end: interval.endUs,
                               words: matches.map { words[$0].id }, sources: [interval.id])
                for i in matches { words[i].reviewIssueIds.append(id) }
            }
        }
        if output.warning != nil || output.exclusiveDiarization == nil {
            issue(.partial_result, start: nil, end: nil, words: [], sources: [])
        }
        if captureInterrupted { issue(.capture_interrupted, start: durationUs, end: durationUs, words: [], sources: []) }
        var turns: [TranscriptTurn] = []
        for word in words {
            if let last = turns.last, let end = last.endUs, let start = word.startUs,
               last.speakerId == word.speakerId, end <= start, start - end <= 300_000,
               word.reviewIssueIds.isEmpty, last.reviewIssueIds.isEmpty,
               !regular.contains(where: { $0.speakerId != word.speakerId && $0.startUs < start && $0.endUs > end }),
               !markers.contains(where: { ($0.startUs ?? 0) < start && ($0.endUs ?? 0) > end }) {
                turns[turns.count - 1].wordIds.append(word.id)
                turns[turns.count - 1].endUs = word.endUs
            } else {
                turns.append(TranscriptTurn(id: "t\(turns.count)", kind: .speech, startUs: word.startUs, endUs: word.endUs,
                    speakerId: word.speakerId, wordIds: [word.id], markerText: nil, reviewed: false, reviewIssueIds: word.reviewIssueIds))
            }
        }
        turns += markers
        turns.sort { ($0.startUs ?? Int64.max, $0.id) < ($1.startUs ?? Int64.max, $1.id) }
        let document = TranscriptDocument(schemaVersion: "1.0", sessionId: sessionID, runId: runID, durationUs: durationUs,
            language: "und", provenance: TranscriptProvenance(engine: .managedPyannoteWhisper,
                diarizationModel: "precision-2", asrModel: "faster-whisper-large-v3-turbo", createdAt: createdAt,
                algorithmVersion: "managed-v1", sourceAudioSHA256: audioSHA256, sampleRateHz: 16_000, isSynthetic: synthetic),
            speakers: speakers, diarization: regular, exclusiveDiarization: exclusive, words: words, turns: turns,
            reviewIssues: issues, revision: RevisionMetadata(id: "model-\(runID)", baseRevisionId: nil, sourceRunId: runID,
                                                           humanEdited: false, savedAt: createdAt))
        try TranscriptValidator().validate(document)
        return document
    }
}

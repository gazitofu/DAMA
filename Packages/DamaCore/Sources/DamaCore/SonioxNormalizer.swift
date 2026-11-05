import Foundation

public struct SonioxTranscriptDTO: Decodable, Sendable {
    public struct Token: Decodable, Sendable {
        public let text: String
        public let start_ms: Int64?
        public let end_ms: Int64?
        public let speaker: String?
        public let confidence: Double?
        public let language: String?
    }
    public let id: String
    public let text: String
    public let tokens: [Token]
}

public enum SonioxNormalizer {
    public static func normalize(_ data: Data, jobID: String, sessionID: String, runID: String,
                                 durationUs: Int64, audioSHA256: String, model: String = "stt-async-v5",
                                 captureInterrupted: Bool = false, synthetic: Bool = false,
                                 createdAt: String) throws -> TranscriptDocument {
        let response = try JSONDecoder().decode(SonioxTranscriptDTO.self, from: data)
        guard response.id == jobID, response.tokens.map(\.text).joined() == response.text else {
            throw ManagedNormalizationError.partialResult
        }
        var labels: [String] = []
        for token in response.tokens {
            if let speaker = token.speaker, !speaker.isEmpty, !labels.contains(speaker) { labels.append(speaker) }
        }
        let speakers = labels.enumerated().map {
            Speaker(id: "\(runID)-speaker-\($0.offset)", providerId: $0.element, displayName: "화자 \($0.offset + 1)")
        }
        let mapping = Dictionary(uniqueKeysWithValues: speakers.map { ($0.providerId, $0.id) })
        var issues: [ReviewIssue] = []
        func issue(_ kind: IssueKind, start: Int64?, end: Int64?, wordIDs: [String]) -> String {
            let id = "i\(issues.count)"
            issues.append(ReviewIssue(id: id, kind: kind, startUs: start, endUs: end, severity: .warning,
                                      status: .open, wordIds: wordIDs, sourceIntervalIds: []))
            return id
        }
        var words = response.tokens.enumerated().map { index, token in
            let id = "w\(index)"
            var range: (Int64, Int64)?
            if let s = token.start_ms, let e = token.end_ms, s >= 0, e >= s, e <= durationUs / 1_000 {
                range = (s * 1_000, e * 1_000)
            }
            let speaker = token.speaker.flatMap { mapping[$0] }
            var flags: [String] = []
            if range == nil || range?.0 == range?.1 {
                flags.append(issue(.invalid_timestamp, start: range?.0, end: range?.1, wordIDs: [id]))
            }
            if speaker == nil { flags.append(issue(.ambiguous_speaker, start: range?.0, end: range?.1, wordIDs: [id])) }
            let punctuation = !token.text.isEmpty && token.text.unicodeScalars.allSatisfy {
                CharacterSet.punctuationCharacters.contains($0) || CharacterSet.whitespacesAndNewlines.contains($0)
            }
            return TranscriptWord(id: id, ordinal: index, text: token.text, editedText: nil, prefix: "",
                startUs: range?.0, endUs: range?.1, modelSpeakerId: speaker, speakerId: speaker,
                assignmentSource: speaker == nil ? .unknown : .provider, alignmentScore: nil, overlap: false,
                reviewIssueIds: flags, sourceIntervalIds: [], timingOrigin: range == nil ? .none : .model,
                tokenKind: punctuation ? .punctuation : .lexical, asrConfidence: token.confidence, language: token.language)
        }
        // Token timing is the available evidence; do not invent independent VAD or exclusive intervals.
        var active: [Int] = []
        var overlapping = Set<Int>()
        for i in words.indices.sorted(by: { (words[$0].startUs ?? Int64.max) < (words[$1].startUs ?? Int64.max) }) {
            guard let start = words[i].startUs, let end = words[i].endUs, start < end else { continue }
            active.removeAll { (words[$0].endUs ?? 0) <= start }
            for j in active where words[j].speakerId != nil && words[i].speakerId != nil && words[j].speakerId != words[i].speakerId {
                overlapping.insert(i); overlapping.insert(j)
            }
            active.append(i)
        }
        for i in overlapping.sorted() {
            words[i].overlap = true
            words[i].reviewIssueIds.append(issue(.overlapping_speech, start: words[i].startUs, end: words[i].endUs, wordIDs: [words[i].id]))
        }
        var turns: [TranscriptTurn] = []
        var text = ""
        var previousStart: Int64?
        for word in words {
            let decimalContinuation = text.last == "." && text.dropLast().last?.isNumber == true && word.text.first?.isNumber == true
            if let last = turns.last, let speaker = word.speakerId, last.speakerId == speaker,
               let start = word.startUs, let end = word.endUs, let previousStart, previousStart <= start,
               last.startUs != nil, last.endUs != nil,
               (!ScriptReadingPolicy.endsSentence(text) || word.tokenKind == .punctuation || decimalContinuation) {
                turns[turns.count - 1].wordIds.append(word.id)
                turns[turns.count - 1].endUs = max(last.endUs!, end)
                turns[turns.count - 1].reviewIssueIds += word.reviewIssueIds
                text += word.text
            } else {
                turns.append(TranscriptTurn(id: "t\(turns.count)", kind: .speech, startUs: word.startUs, endUs: word.endUs,
                    speakerId: word.speakerId, wordIds: [word.id], markerText: nil, reviewed: false, reviewIssueIds: word.reviewIssueIds))
                text = word.text
            }
            previousStart = word.startUs
        }
        if captureInterrupted { _ = issue(.capture_interrupted, start: durationUs, end: durationUs, wordIDs: []) }
        let document = TranscriptDocument(schemaVersion: "1.0", sessionId: sessionID, runId: runID, durationUs: durationUs,
            language: "und", provenance: TranscriptProvenance(engine: .managedSoniox, diarizationModel: model,
                asrModel: model, createdAt: createdAt, algorithmVersion: "soniox-v1", sourceAudioSHA256: audioSHA256,
                sampleRateHz: 16_000, isSynthetic: synthetic), speakers: speakers, diarization: [], exclusiveDiarization: [],
            words: words, turns: turns, reviewIssues: issues,
            revision: RevisionMetadata(id: "model-\(runID)", baseRevisionId: nil, sourceRunId: runID, humanEdited: false, savedAt: createdAt))
        try TranscriptValidator().validate(document)
        return document
    }
}

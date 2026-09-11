import Foundation

/// Uses token time, never a wholesale replacement of Soniox speaker IDs.
public enum SonioxPrecisionNormalizer {
    public static let version = "soniox-p2-v2"
    public static func normalize(soniox: Data, diarization: Data, sonioxJobID: String,
                                 sessionID: String, runID: String, durationUs: Int64,
                                 audioSHA256: String, model: String, createdAt: String,
                                 synthetic: Bool = false, captureInterrupted: Bool = false) throws -> TranscriptDocument {
        let source = try SonioxNormalizer.normalize(soniox, jobID: sonioxJobID, sessionID: sessionID,
            runID: runID, durationUs: durationUs, audioSHA256: audioSHA256, model: model,
            synthetic: synthetic, createdAt: createdAt)
        let job = try JSONDecoder().decode(PyannoteJobDTO.self, from: diarization)
        guard job.status == "succeeded", let output = job.output, output.error == nil,
              let exclusiveSource = output.exclusiveDiarization else { throw ManagedNormalizationError.partialResult }
        let labels = Set((output.diarization + exclusiveSource).map(\.speaker)).sorted()
        let speakers = labels.enumerated().map {
            Speaker(id: "\(runID)-p2-\($0.offset)", providerId: $0.element, displayName: "화자 \($0.offset + 1)")
        }
        let mapping = Dictionary(uniqueKeysWithValues: speakers.map { ($0.providerId, $0.id) })
        func intervals(_ values: [PyannoteDiarizationDTO], _ prefix: String) throws -> [DiarizationInterval] {
            try values.enumerated().map { i, x in
                guard x.start.isFinite, x.end.isFinite, x.start >= 0, x.end > x.start,
                      x.end * 1e6 <= Double(durationUs), let speaker = mapping[x.speaker] else {
                    throw ManagedNormalizationError.invalidIntervals
                }
                return DiarizationInterval(id: "\(prefix)\(i)", startUs: Int64((x.start * 1e6).rounded()),
                    endUs: Int64((x.end * 1e6).rounded()), speakerId: speaker, confidence: x.confidence)
            }
        }
        let regular = try intervals(output.diarization, "d"), exclusive = try intervals(exclusiveSource, "e")
        let originalLabels = Dictionary(uniqueKeysWithValues: source.speakers.map { ($0.id, $0.providerId) })
        var issues: [ReviewIssue] = []
        func flag(_ kind: IssueKind, _ s: Int64?, _ e: Int64?, _ ids: [String], _ evidence: [String]) -> String {
            let id = "i\(issues.count)"
            issues.append(ReviewIssue(id: id, kind: kind, startUs: s, endUs: e, severity: .warning,
                status: .open, wordIds: ids, sourceIntervalIds: evidence))
            return id
        }
        var words = source.words.map { original -> TranscriptWord in
            var w = original
            w.asrSpeakerLabel = original.modelSpeakerId.flatMap { originalLabels[$0] }
            w.speakerId = nil; w.modelSpeakerId = nil; w.assignmentSource = .unknown
            w.alignmentScore = nil; w.sourceIntervalIds = []; w.reviewIssueIds = []; w.overlap = false
            guard let s = w.startUs, let e = w.endUs, s < e else {
                w.reviewIssueIds = [flag(.invalid_timestamp, w.startUs, w.endUs, [w.id], []),
                    flag(.ambiguous_speaker, w.startUs, w.endUs, [w.id], [])]
                return w
            }
            let matches = regular.filter { max(s, $0.startUs) < min(e, $0.endUs) }
            let candidates = exclusive.filter { max(s, $0.startUs) < min(e, $0.endUs) }
            let evidence = (matches + candidates).map(\.id)
            w.sourceIntervalIds = evidence
            w.overlap = matches.enumerated().contains { i, a in matches.dropFirst(i + 1).contains { b in
                a.speakerId != b.speakerId && max(s, a.startUs, b.startUs) < min(e, a.endUs, b.endUs)
            } }
            let boundary = Set((matches + candidates).map(\.speakerId)).count > 1
            var scores: [(String, Double)] = []
            for speaker in Set(candidates.map(\.speakerId)) {
                var total: Int64 = 0, edge = s
                for d in candidates.filter({ $0.speakerId == speaker }).sorted(by: { $0.startUs < $1.startUs }) {
                    let a = max(s, d.startUs, edge), b = min(e, d.endUs)
                    if b > a { total += b - a; edge = b }
                }
                scores.append((speaker, Double(total) / Double(e - s)))
            }
            scores.sort { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 > $1.1 }
            w.modelSpeakerId = scores.first?.0; w.alignmentScore = scores.first?.1
            // Existing provisional coverage threshold, not an accuracy probability.
            if !w.overlap && !boundary && (scores.first?.1 ?? 0) >= 0.60 {
                w.speakerId = scores.first?.0; w.assignmentSource = .reconciled
            }
            if w.speakerId == nil { w.reviewIssueIds.append(flag(.ambiguous_speaker, s, e, [w.id], evidence)) }
            if boundary { w.reviewIssueIds.append(flag(.boundary_conflict, s, e, [w.id], evidence)) }
            if w.overlap { w.reviewIssueIds.append(flag(.overlapping_speech, s, e, [w.id], evidence)) }
            return w
        }
        // Compare changes in the two timelines, not literal IDs or global cluster identity.
        // One disagreement must not turn every word in a large merged cluster into a warning.
        var previous: Int?
        for i in words.indices where words[i].tokenKind == .lexical {
            guard let a = words[i].asrSpeakerLabel, let b = words[i].speakerId else { previous = nil; continue }
            if let j = previous, let oldA = words[j].asrSpeakerLabel, let oldB = words[j].speakerId,
               (a != oldA) != (b != oldB) {
                let evidence = Array(Set(words[j].sourceIntervalIds + words[i].sourceIntervalIds)).sorted()
                let issue = flag(.provider_disagreement, words[j].startUs, words[i].endUs,
                                 [words[j].id, words[i].id], evidence)
                words[j].reviewIssueIds.append(issue); words[i].reviewIssueIds.append(issue)
            }
            previous = i
        }
        var markers: [TranscriptTurn] = []
        for d in regular {
            let matching = words.indices.filter { i in
                guard words[i].tokenKind == .lexical, let s = words[i].startUs, let e = words[i].endUs else { return false }
                return max(s, d.startUs) < min(e, d.endUs)
            }
            if matching.isEmpty {
                let issue = flag(.missing_speech, d.startUs, d.endUs, [], [d.id])
                markers.append(TranscriptTurn(id: "m\(markers.count)", kind: .missingSpeech, startUs: d.startUs,
                    endUs: d.endUs, speakerId: d.speakerId, wordIds: [], markerText: "[음성 감지 / 전사 누락 의심]",
                    reviewed: false, reviewIssueIds: [issue]))
            } else if !matching.contains(where: { words[$0].speakerId == d.speakerId }) {
                let issue = flag(.unrepresented_speaker, d.startUs, d.endUs, matching.map { words[$0].id }, [d.id])
                for i in matching { words[i].reviewIssueIds.append(issue) }
            }
        }
        var turns = words.enumerated().map { i, w in TranscriptTurn(id: "t\(i)", kind: .speech,
            startUs: w.startUs, endUs: w.endUs, speakerId: w.speakerId, wordIds: [w.id], markerText: nil,
            reviewed: false, reviewIssueIds: w.reviewIssueIds) }
        for marker in markers.sorted(by: { $0.startUs! < $1.startUs! }) {
            turns.insert(marker, at: turns.firstIndex { ($0.startUs ?? Int64.min) >= marker.startUs! } ?? turns.endIndex)
        }
        if captureInterrupted { _ = flag(.capture_interrupted, durationUs, durationUs, [], []) }
        if output.warning != nil { _ = flag(.partial_result, nil, nil, [], []) }
        let document = TranscriptDocument(schemaVersion: "1.0", sessionId: sessionID, runId: runID, durationUs: durationUs,
            language: source.language, provenance: TranscriptProvenance(engine: .hybridSonioxPyannote,
                diarizationModel: "precision-2", asrModel: model, createdAt: createdAt, algorithmVersion: version,
                sourceAudioSHA256: audioSHA256, sampleRateHz: 16_000, isSynthetic: synthetic),
            speakers: speakers, diarization: regular, exclusiveDiarization: exclusive, words: words,
            turns: turns, reviewIssues: issues, revision: RevisionMetadata(id: "model-\(runID)", baseRevisionId: nil,
                sourceRunId: runID, humanEdited: false, savedAt: createdAt))
        try TranscriptValidator().validate(document)
        return document
    }
}

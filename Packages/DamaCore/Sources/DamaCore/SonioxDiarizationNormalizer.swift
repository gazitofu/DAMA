import Foundation

/// Soniox tokens + diarization intervals (P2 or Nemotron) -> the v2-shaped base document.
/// Uses token time, never a wholesale replacement of Soniox speaker IDs.
enum SonioxDiarizationNormalizer {
    static func normalize(source: TranscriptDocument, speakers: [Speaker], regular: [DiarizationInterval],
                          exclusive: [DiarizationInterval], engine: EngineKind, diarizationModel: String, version: String,
                          sessionID: String, runID: String, durationUs: Int64, audioSHA256: String, model: String,
                          createdAt: String, synthetic: Bool, captureInterrupted: Bool,
                          providerWarning: Bool) throws -> TranscriptDocument {
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
            let evidence = P2TimeEvidence.token(startUs: s, endUs: e, regular: regular, exclusive: exclusive)
            w.sourceIntervalIds = evidence.sourceIDs; w.overlap = evidence.overlap
            w.modelSpeakerId = evidence.best?.speakerID; w.alignmentScore = evidence.best?.coverage
            // Existing provisional coverage threshold, not an accuracy probability.
            if !w.overlap && !evidence.boundary && (evidence.best?.coverage ?? 0) >= 0.60 {
                w.speakerId = evidence.best?.speakerID; w.assignmentSource = .reconciled
            }
            if w.speakerId == nil { w.reviewIssueIds.append(flag(.ambiguous_speaker, s, e, [w.id], evidence.sourceIDs)) }
            if evidence.boundary { w.reviewIssueIds.append(flag(.boundary_conflict, s, e, [w.id], evidence.sourceIDs)) }
            if w.overlap { w.reviewIssueIds.append(flag(.overlapping_speech, s, e, [w.id], evidence.sourceIDs)) }
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
            let matching = P2TimeEvidence.matchingWordIndices(words, interval: d, lexicalOnly: true)
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
        if providerWarning { _ = flag(.partial_result, nil, nil, [], []) }
        let document = TranscriptDocument(schemaVersion: "1.0", sessionId: sessionID, runId: runID, durationUs: durationUs,
            language: source.language, provenance: TranscriptProvenance(engine: engine,
                diarizationModel: diarizationModel, asrModel: model, createdAt: createdAt, algorithmVersion: version,
                sourceAudioSHA256: audioSHA256, sampleRateHz: 16_000, isSynthetic: synthetic),
            speakers: speakers, diarization: regular, exclusiveDiarization: exclusive, words: words,
            turns: turns, reviewIssues: issues, revision: RevisionMetadata(id: "model-\(runID)", baseRevisionId: nil,
                sourceRunId: runID, humanEdited: false, savedAt: createdAt))
        try TranscriptValidator().validate(document)
        return document
    }
}

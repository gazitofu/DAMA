import Foundation

public struct QwenResult: Decodable, Sendable {
    public struct Word: Decodable, Sendable {
        public let text: String
        public let startUs: Int64?
        public let endUs: Int64?
        public let reason: String?
    }
    public struct Chunk: Decodable, Sendable {
        public let startFrame: Int64
        public let endFrame: Int64
        public let finish_reason: String
        public let truncated: Bool
    }
    public let version: String
    public let status: String
    public let audioSHA256: String
    public let durationUs: Int64
    public let text: String
    public let words: [Word]
    public let chunks: [Chunk]
}

public enum QwenNormalizer {
    public static func normalize(_ data: Data, diarization: Data, sessionID: String, runID: String,
                                 durationUs: Int64, audioSHA256: String, createdAt: String,
                                 captureInterrupted: Bool = false, synthetic: Bool = false) throws -> TranscriptDocument {
        let result = try JSONDecoder().decode(QwenResult.self, from: data)
        let job = try JSONDecoder().decode(PyannoteJobDTO.self, from: diarization)
        guard result.version == "qwen-worker-v1", result.status == "complete",
              result.audioSHA256 == audioSHA256, result.durationUs == durationUs,
              result.words.map(\.text).joined() == result.text, !result.chunks.isEmpty,
              job.status == "succeeded", let output = job.output, output.error == nil,
              let exclusiveSource = output.exclusiveDiarization else { throw ManagedNormalizationError.partialResult }
        var nextFrame: Int64 = 0
        for chunk in result.chunks {
            guard chunk.startFrame == nextFrame, chunk.endFrame > chunk.startFrame,
                  chunk.finish_reason == "eos", !chunk.truncated else { throw ManagedNormalizationError.partialResult }
            nextFrame = chunk.endFrame
        }
        guard nextFrame <= Int64.max / 1_000_000, nextFrame * 1_000_000 / 16_000 == durationUs else {
            throw ManagedNormalizationError.partialResult
        }
        let labels = Set((output.diarization + exclusiveSource).map(\.speaker)).sorted()
        let speakers = labels.enumerated().map { Speaker(id: "\(runID)-speaker-\($0.offset)", providerId: $0.element, displayName: "화자 \($0.offset+1)") }
        let mapping = Dictionary(uniqueKeysWithValues: speakers.map { ($0.providerId,$0.id) })
        let regular = try P2TimeEvidence.intervals(output.diarization, prefix: "d", mapping: mapping, durationUs: durationUs)
        let exclusive = try P2TimeEvidence.intervals(exclusiveSource, prefix: "e", mapping: mapping, durationUs: durationUs)
        var issues: [ReviewIssue] = []
        func issue(_ kind: IssueKind, _ start: Int64?, _ end: Int64?, _ words: [String], _ sources: [String]) -> String {
            let id = "i\(issues.count)"
            issues.append(ReviewIssue(id: id,kind: kind,startUs: start,endUs: end,severity: .warning,
                status: .open,wordIds: words,sourceIntervalIds: sources))
            return id
        }
        var previousStart: Int64 = -1
        var words = result.words.enumerated().map { i,x -> TranscriptWord in
            let id = "w\(i)"
            var s = x.startUs, e = x.endUs
            if let a=s,let b=e,a >= 0,a < b,b <= durationUs,a >= previousStart { previousStart = a }
            else { s=nil; e=nil }
            let evidence = P2TimeEvidence.token(startUs: s, endUs: e, regular: regular, exclusive: exclusive)
            let speaker: String? = !evidence.overlap && !evidence.boundary && (evidence.best?.coverage ?? 0)>=0.60 ? evidence.best?.speakerID : nil
            var flags: [String]=[]
            if s == nil { flags.append(issue(.invalid_timestamp,nil,nil,[id],[])) }
            if speaker == nil { flags.append(issue(.ambiguous_speaker,s,e,[id],evidence.sourceIDs)) }
            if evidence.overlap { flags.append(issue(.overlapping_speech,s,e,[id],evidence.regularMatches.map(\.id))) }
            if evidence.boundary { flags.append(issue(.boundary_conflict,s,e,[id],evidence.sourceIDs)) }
            return TranscriptWord(id:id,ordinal:i,text:x.text,editedText:nil,prefix:"",startUs:s,endUs:e,
                modelSpeakerId:evidence.best?.speakerID,speakerId:speaker,assignmentSource:speaker == nil ? .unknown : .reconciled,
                alignmentScore:evidence.best?.coverage,overlap:evidence.overlap,reviewIssueIds:flags,
                sourceIntervalIds:evidence.sourceIDs,timingOrigin:s == nil ? .none : .model,tokenKind:.lexical)
        }
        var markers: [TranscriptTurn]=[]
        for d in regular {
            let matching = P2TimeEvidence.matchingWordIndices(words, interval: d, lexicalOnly: false)
            if matching.isEmpty {
                let flag=issue(.missing_speech,d.startUs,d.endUs,[],[d.id])
                markers.append(TranscriptTurn(id:"m\(markers.count)",kind:.missingSpeech,startUs:d.startUs,endUs:d.endUs,
                    speakerId:d.speakerId,wordIds:[],markerText:"[음성 감지 / 전사 누락 의심]",reviewed:false,reviewIssueIds:[flag]))
            } else if !matching.contains(where: { words[$0].speakerId == d.speakerId }) {
                let flag=issue(.unrepresented_speaker,d.startUs,d.endUs,matching.map { words[$0].id },[d.id])
                for i in matching { words[i].reviewIssueIds.append(flag) }
            }
        }
        if output.warning != nil { _=issue(.partial_result,nil,nil,[],[]) }
        if captureInterrupted { _=issue(.capture_interrupted,durationUs,durationUs,[],[]) }
        // One underlying Turn per aligned unit: reading-v5 joins only safe boundaries.
        // Keep original word order even for unaligned units, which must not drift to the end.
        var turns = words.enumerated().map { i,w in TranscriptTurn(id:"t\(i)",kind:.speech,
            startUs:w.startUs,endUs:w.endUs,speakerId:w.speakerId,wordIds:[w.id],markerText:nil,reviewed:false,reviewIssueIds:w.reviewIssueIds) }
        for marker in markers.sorted(by: { $0.startUs! < $1.startUs! }) {
            let index=turns.firstIndex { ($0.startUs ?? Int64.min) >= marker.startUs! } ?? turns.endIndex
            turns.insert(marker,at:index)
        }
        let document=TranscriptDocument(schemaVersion:"1.0",sessionId:sessionID,runId:runID,durationUs:durationUs,language:"ko",
            provenance:TranscriptProvenance(engine:.hybridPyannoteQwen,diarizationModel:"precision-2",
                asrModel:"Qwen3-ASR-1.7B + Qwen3-ForcedAligner-0.6B",createdAt:createdAt,
                algorithmVersion:"qwen-p2-v1",sourceAudioSHA256:audioSHA256,sampleRateHz:16000,isSynthetic:synthetic),
            speakers:speakers,diarization:regular,exclusiveDiarization:exclusive,words:words,turns:turns,reviewIssues:issues,
            revision:RevisionMetadata(id:"model-\(runID)",baseRevisionId:nil,sourceRunId:runID,humanEdited:false,savedAt:createdAt))
        try TranscriptValidator().validate(document)
        return document
    }
}

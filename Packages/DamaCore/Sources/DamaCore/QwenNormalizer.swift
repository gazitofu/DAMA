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
        func intervals(_ source: [PyannoteDiarizationDTO], prefix: String) throws -> [DiarizationInterval] {
            try source.enumerated().map { i,x in
                guard x.start.isFinite, x.end.isFinite, x.start >= 0, x.end > x.start,
                      x.end*1e6 <= Double(durationUs), let speaker = mapping[x.speaker] else {
                    throw ManagedNormalizationError.invalidIntervals
                }
                return DiarizationInterval(id: "\(prefix)\(i)",startUs: Int64((x.start*1e6).rounded()),
                    endUs: Int64((x.end*1e6).rounded()),speakerId: speaker,confidence: x.confidence)
            }
        }
        let regular = try intervals(output.diarization,prefix: "d")
        let exclusive = try intervals(exclusiveSource,prefix: "e")
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
            let matches = regular.filter { d in s.map { max($0,d.startUs) < min(e!,d.endUs) } ?? false }
            let candidates = exclusive.filter { d in s.map { max($0,d.startUs) < min(e!,d.endUs) } ?? false }
            let overlap = matches.enumerated().contains { n,a in matches.dropFirst(n+1).contains { b in
                a.speakerId != b.speakerId && max(s!,a.startUs,b.startUs) < min(e!,a.endUs,b.endUs)
            } }
            var scores: [(String, Double)] = []
            if let s,let e {
                for speaker in Set(candidates.map(\.speakerId)) {
                    var total: Int64=0, edge=s
                    for d in candidates.filter({ $0.speakerId==speaker }).sorted(by: {$0.startUs<$1.startUs}) {
                        let a=max(s,d.startUs,edge),b=min(e,d.endUs)
                        if b>a { total += b-a; edge=b }
                    }
                    scores.append((speaker,Double(total)/Double(e-s)))
                }
            }
            scores.sort { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 > $1.1 }
            let boundary = Set((matches+candidates).map(\.speakerId)).count>1
            let speaker: String? = !overlap && !boundary && (scores.first?.1 ?? 0)>=0.60 ? scores.first?.0 : nil
            var flags: [String]=[]
            if s == nil { flags.append(issue(.invalid_timestamp,nil,nil,[id],[])) }
            if speaker == nil { flags.append(issue(.ambiguous_speaker,s,e,[id],(matches+candidates).map(\.id))) }
            if overlap { flags.append(issue(.overlapping_speech,s,e,[id],matches.map(\.id))) }
            if boundary { flags.append(issue(.boundary_conflict,s,e,[id],(matches+candidates).map(\.id))) }
            return TranscriptWord(id:id,ordinal:i,text:x.text,editedText:nil,prefix:"",startUs:s,endUs:e,
                modelSpeakerId:scores.first?.0,speakerId:speaker,assignmentSource:speaker == nil ? .unknown : .reconciled,
                alignmentScore:scores.first?.1,overlap:overlap,reviewIssueIds:flags,
                sourceIntervalIds:(matches+candidates).map(\.id),timingOrigin:s == nil ? .none : .model,tokenKind:.lexical)
        }
        var markers: [TranscriptTurn]=[]
        for d in regular {
            let matching=words.indices.filter { i in words[i].startUs.map { max($0,d.startUs)<min(words[i].endUs!,d.endUs) } ?? false }
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

// Build against DamaCore; arguments: SOURCE_SCRIPT INTERNAL_ROOT OUTPUT_DIRECTORY [POLICY].
// This executable reads saved responses only. It never calls managed processing or an API.
import Foundation
import CryptoKit
import DamaCore

@main struct CompareSonioxPrecision {
    static func main() throws {
        guard (4...5).contains(CommandLine.arguments.count) else { throw LibraryFailure.invalidInput }
        let policies: [SonioxPrecisionComparison]
        if CommandLine.arguments.count == 5 {
            guard let policy = SonioxPrecisionComparison(rawValue: CommandLine.arguments[4]) else { throw LibraryFailure.invalidInput }
            policies = [policy]
        } else { policies = [.timeline, .word] }
        let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let root = URL(fileURLWithPath: CommandLine.arguments[2])
        let output = URL(fileURLWithPath: CommandLine.arguments[3])
        var sourceHashes: [String: String] = [:]
        func hash(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
        func read(_ url: URL) throws -> Data {
            let bytes = try Data(contentsOf: url); sourceHashes[url.path] = hash(bytes); return bytes
        }
        func write(_ bytes: Data, _ url: URL) throws {
            try bytes.write(to: url, options: .withoutOverwriting)
        }
        let bytes = try read(sourceURL)
        let script = try JSONDecoder().decode(LibraryScript.self, from: bytes)
        try script.validate()
        let original = script.transcript
        guard UUID(uuidString: original.sessionId) != nil, UUID(uuidString: original.runId) != nil,
              let sonioxID = script.input.sonioxSourceRunID, UUID(uuidString: sonioxID) != nil,
              let p2ID = script.input.precisionSourceRunID, UUID(uuidString: p2ID) != nil,
              !original.provenance.isSynthetic else { throw LibraryFailure.invalidInput }
        let session = root.appendingPathComponent("Sessions").appendingPathComponent(original.sessionId)
        let runs = session.appendingPathComponent("runs")
        let base = runs.appendingPathComponent(original.runId)
        let soniox = try read(base.appendingPathComponent("raw/soniox-response.json"))
        let p2 = try read(base.appendingPathComponent("raw/pyannote-response.json"))
        guard try read(runs.appendingPathComponent(sonioxID).appendingPathComponent("raw/soniox-response.json")) == soniox,
              try read(runs.appendingPathComponent(p2ID).appendingPathComponent("raw/pyannote-response.json")) == p2,
              hash(try read(session.appendingPathComponent("audio/analysis.wav"))) == original.provenance.sourceAudioSHA256
        else { throw LibraryFailure.changedFile }
        let sonioxRequest = try read(base.appendingPathComponent("soniox-request.json"))
        let p2Request = try read(base.appendingPathComponent("precision-request.json"))
        let response = try JSONDecoder().decode(SonioxTranscriptDTO.self, from: soniox)
        func rebuild(_ runID: String) throws -> TranscriptDocument {
            try SonioxPrecisionNormalizer.normalize(soniox: soniox, diarization: p2,
                sonioxJobID: response.id, sessionID: original.sessionId, runID: runID,
                durationUs: original.durationUs, audioSHA256: original.provenance.sourceAudioSHA256!,
                model: original.provenance.asrModel, createdAt: original.provenance.createdAt,
                captureInterrupted: original.reviewIssues.contains { $0.kind == .capture_interrupted })
        }
        // 원본이 v2 정규화본이면 그대로, 이미 정책이 적용된 결과이면 같은 raw로 기반본을 다시 만들고
        // 기록된 정책을 재적용해 현재 파일과 완전히 같은지 확인한 뒤 그 기반본을 비교 입력으로 쓴다.
        let sourceDocument: TranscriptDocument
        if original.provenance.algorithmVersion == SonioxPrecisionNormalizer.version {
            guard try NormalizedTranscriptCodec.encode(rebuild(original.runId)) == NormalizedTranscriptCodec.encode(original)
            else { throw LibraryFailure.changedFile }
            sourceDocument = original
        } else {
            guard let recorded = SonioxPrecisionComparison(rawValue: original.provenance.algorithmVersion)
            else { throw LibraryFailure.invalidInput }
            let rebased = try rebuild(UUID().uuidString)
            let replay = try SonioxPrecisionReconciler.reconcile(rebased, runID: original.runId,
                createdAt: original.provenance.createdAt, policy: recorded)
            guard try NormalizedTranscriptCodec.encode(replay) == NormalizedTranscriptCodec.encode(original)
            else { throw LibraryFailure.changedFile }
            sourceDocument = rebased
        }

        func metrics(_ value: LibraryScript) -> [String: Any] {
            let t = value.transcript, blocks = value.blocks().filter(\.isSpeech)
            let unknown = t.words.filter { $0.speakerId == nil }
            let words = Dictionary(uniqueKeysWithValues: t.words.map { ($0.id, $0) })
            return ["tokens": t.words.count, "unknownTokens": unknown.count,
                "unknownLexical": unknown.filter { $0.tokenKind == .lexical }.count,
                "speechBlocks": blocks.count, "missingSpeechMarkers": t.turns.filter { $0.kind == .missingSpeech }.count,
                "punctuationOnlyBlocks": blocks.filter { block in
                    block.turns.flatMap(\.wordIds).compactMap { words[$0] }.allSatisfy { $0.tokenKind == .punctuation }
                }.count]
        }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
        let evidence = output.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: false)
        try write(bytes, evidence.appendingPathComponent("source-script.json"))
        try write(soniox, evidence.appendingPathComponent("soniox-response.json"))
        try write(p2, evidence.appendingPathComponent("pyannote-response.json"))
        try write(sonioxRequest, evidence.appendingPathComponent("soniox-request.json"))
        try write(p2Request, evidence.appendingPathComponent("precision-request.json"))
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let now = Date(), createdAt = ISO8601DateFormatter().string(from: now)
        var artifacts: [[String: Any]] = []
        for policy in policies {
            let runID = UUID().uuidString
            let doc = try SonioxPrecisionReconciler.reconcile(sourceDocument, runID: runID, createdAt: createdAt, policy: policy)
            guard doc.words.count == original.words.count else { throw LibraryFailure.invalidScript }
            for (a,b) in zip(original.words,doc.words) {
                guard a.id == b.id, a.ordinal == b.ordinal, a.text == b.text, a.prefix == b.prefix,
                      a.startUs == b.startUs, a.endUs == b.endUs, a.tokenKind == b.tokenKind,
                      a.asrConfidence == b.asrConfidence, a.language == b.language,
                      a.asrSpeakerLabel == b.asrSpeakerLabel else { throw LibraryFailure.invalidScript }
            }
            var input = script.input; input.aiCorrection = false
            let label: String
            switch policy {
            case .timeline: label = "비교 A · P2 시간표"
            case .word: label = "비교 B · P2 화자별 원문"
            case .wordRepair: label = "비교 B2 · 문단 보완"
            case .wordAtomic: label = script.title + " · 비교 C(어절 원자성)"
            }
            let candidate = try LibraryScript(transcript: doc, title: label,
                recordedAt: script.recordedAt, dateSource: script.dateSource,
                timeZoneID: script.timeZoneID, input: input, createdAt: now)
            try candidate.validate()
            let data = try encoder.encode(candidate)
            let decoded = try JSONDecoder().decode(LibraryScript.self, from: data)
            try decoded.validate()
            let filename = runID + ".dama.json"
            try write(data, output.appendingPathComponent(filename))
            try write(NormalizedTranscriptCodec.encode(doc), evidence.appendingPathComponent(runID + "-normalized.json"))
            try write(candidate.markdown(), evidence.appendingPathComponent(runID + ".md"))
            var entry = metrics(candidate)
            entry["policy"] = policy.rawValue; entry["runID"] = runID; entry["filename"] = filename
            entry["sha256"] = hash(data); entry["rawTextAndTimesPreserved"] = true
            artifacts.append(entry)
        }
        for (path, expected) in sourceHashes {
            guard try hash(Data(contentsOf: URL(fileURLWithPath: path))) == expected else { throw LibraryFailure.changedFile }
        }
        let manifest: [String: Any] = ["createdAt": createdAt, "baseRunID": original.runId,
            "sonioxSourceRunID": sonioxID, "precisionSourceRunID": p2ID,
            "sourceAudioSHA256": original.provenance.sourceAudioSHA256!, "inputHashes": sourceHashes,
            "baseline": metrics(script), "artifacts": artifacts,
            "accuracy": "Unmeasured: no reference speaker labels or listening adjudication."]
        try write(JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]), output.appendingPathComponent("manifest.json"))
        print(String(decoding: try JSONSerialization.data(withJSONObject: ["baseline": metrics(script), "artifacts": artifacts], options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}

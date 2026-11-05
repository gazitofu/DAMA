import CryptoKit
import Foundation
#if !GOLDEN_CAPTURE
import DamaCore
#endif

/// Shared synthetic input for both P2 consumers and the unchanged Soniox control.
enum NormalizationFixture {
    struct Fingerprint: Codable, Equatable {
        let normalized: String
        let reading: String
        let markdown: String
    }
    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    static func documents(_ fixture: URL) throws -> [String: TranscriptDocument] {
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as! [String: Any]
        precondition(json["synthetic"] as? Bool == true)
        let duration = json["durationUs"] as! Int64, audioHash = String(repeating: "a", count: 64)
        let created = "2026-09-12T00:00:00Z"
        var documents: [String: TranscriptDocument] = [:]
        for value in json["cases"] as! [[String: Any]] {
            let id = value["id"] as! String, tokens = value["tokens"] as! [[String: Any]]
            let text = tokens.map { $0["text"] as! String }.joined()
            let asr = try JSONSerialization.data(withJSONObject: ["id": "job", "text": text, "tokens": tokens])
            var output: [String: Any] = ["diarization": value["regular"]!, "exclusiveDiarization": value["exclusive"] ?? value["regular"]!]
            output["warning"] = value["warning"]
            let p2 = try JSONSerialization.data(withJSONObject: ["jobId": "p2", "status": "succeeded", "output": output])
            let interrupted = value["captureInterrupted"] as? Bool ?? false
            func microseconds(_ value: Any?) -> Any {
                guard let number = value as? NSNumber else { return NSNull() }
                return number.int64Value * 1_000
            }
            let qwenWords: [[String: Any]] = tokens.map {
                ["text": $0["text"]!, "startUs": microseconds($0["start_ms"]), "endUs": microseconds($0["end_ms"])]
            }
            let qwen = try JSONSerialization.data(withJSONObject: [
                "version": "qwen-worker-v1", "status": "complete", "audioSHA256": audioHash, "durationUs": duration,
                "text": text, "words": qwenWords,
                "chunks": [["startFrame": 0, "endFrame": duration * 16_000 / 1_000_000, "finish_reason": "eos", "truncated": false]]])
            documents[id + "/soniox"] = try SonioxNormalizer.normalize(asr, jobID: "job", sessionID: "synthetic", runID: "golden",
                durationUs: duration, audioSHA256: audioHash, captureInterrupted: interrupted, synthetic: true, createdAt: created)
            documents[id + "/combined"] = try SonioxPrecisionNormalizer.normalize(soniox: asr, diarization: p2, sonioxJobID: "job",
                sessionID: "synthetic", runID: "golden", durationUs: duration, audioSHA256: audioHash, model: "stt-async-v5",
                createdAt: created, synthetic: true, captureInterrupted: interrupted)
            documents[id + "/qwen"] = try QwenNormalizer.normalize(qwen, diarization: p2, sessionID: "synthetic", runID: "golden",
                durationUs: duration, audioSHA256: audioHash, createdAt: created, captureInterrupted: interrupted, synthetic: true)
        }
        return documents
    }
    static func fingerprint(_ document: TranscriptDocument) throws -> Fingerprint {
        struct Block: Encodable {
            let turns: [TranscriptTurn], issues: [ReviewIssue]
            let text: String, name: String, colorIndex: Int?, edited: Bool
        }
        var script = try LibraryScript(transcript: document, title: "합성 동일성 검사", recordedAt: nil,
            dateSource: "synthetic", timeZoneID: "Asia/Seoul", input: ConversionNotes(), createdAt: Date(timeIntervalSince1970: 0))
        script.revisionID = "00000000-0000-4000-8000-000000000001"
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let blocks = script.blocks().map { Block(turns: $0.turns, issues: $0.issues, text: $0.text,
            name: $0.name, colorIndex: $0.colorIndex, edited: $0.edited) }
        return try Fingerprint(normalized: hash(NormalizedTranscriptCodec.encode(document)),
                               reading: hash(encoder.encode(blocks)), markdown: hash(script.markdown()))
    }
}

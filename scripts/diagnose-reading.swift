import Foundation
import CryptoKit

// Compile with the DamaCore source files. No API, model process, or repository writes.
// Arguments: Scripts directory, Application Support root, output JSON,
// combined Run ID, Qwen Run ID. IDs pin the comparison instead of directory order.
@main struct ReadingDiagnostic {
    static func require(_ condition: Bool, _ label: String) throws {
        if !condition { throw NSError(domain: "ReadingDiagnostic", code: 1, userInfo: [NSLocalizedDescriptionKey: label]) }
    }
    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func reason(_ script: LibraryScript, _ index: Int, accumulated: String) -> String {
        let a = script.transcript.turns[index - 1], b = script.transcript.turns[index]
        if script.transcript.revision.humanEdited { return "legacyHumanRevision" }
        if a.kind != .speech || b.kind != .speech { return "missingMarker" }
        if a.speakerId == nil || b.speakerId == nil { return "unknownSpeaker" }
        if a.speakerId != b.speakerId { return "speakerChange" }
        if script.name(for: a) != script.name(for: b) { return "displayNameChange" }
        guard let s = a.startUs, let e = a.endUs, let ns = b.startUs, let ne = b.endUs else { return "missingTime" }
        if s > e || ns > ne || s > ns || e > ne { return "nonmonotonicTime" }
        if !script.canJoinParagraph(before: b.id) { return "interveningSpeaker" }
        if let split = script.paragraphBreaks?[b.id] { return split ? "manualSplit" : "manualJoin" }
        guard ScriptReadingPolicy.completesReadingSentence(accumulated) else { return "joined" }
        let next = script.text(for: b), suffix = next.trimmingCharacters(in: .whitespacesAndNewlines)
        if !suffix.isEmpty && suffix.unicodeScalars.allSatisfy(CharacterSet(charactersIn: ".?!。？！…\"'”’)]}」』").contains) { return "punctuationContinuation" }
        if accumulated.last == ".", accumulated.dropLast().last?.isNumber == true, next.first?.isNumber == true { return "decimalContinuation" }
        return "sentenceEnd"
    }
    static func measure(_ script: LibraryScript) throws -> [String: Any] {
        try script.validate()
        let t = script.transcript
        let before = Date(), blocks = script.blocks(), elapsed = Date().timeIntervalSince(before)
        let starts = Set(blocks.map(\.id))
        var reasons: [String: Int] = [:], unknownReasons: [String: Int] = [:]
        var cumulativeText = t.turns.first.map { script.text(for: $0) } ?? ""
        var missedAccumulatedEnds = 0
        for i in t.turns.indices.dropFirst() {
            let r = reason(script, i, accumulated: cumulativeText)
            reasons[r, default: 0] += 1
            let joined = ["joined", "manualJoin", "punctuationContinuation", "decimalContinuation"].contains(r)
            try require(joined == !starts.contains(t.turns[i].id), "reason-vs-production-blocks")
            if joined {
                if r == "joined" && ScriptReadingPolicy.completesReadingSentence(cumulativeText) { missedAccumulatedEnds += 1 }
                let next = script.text(for: t.turns[i])
                let sourceSpacing = [.hybridSonioxPyannote, .managedSoniox, .hybridPyannoteQwen].contains(t.provenance.engine)
                let space = !sourceSpacing && !cumulativeText.isEmpty && !next.isEmpty && cumulativeText.last?.isWhitespace == false && next.first?.isWhitespace == false
                cumulativeText += (space ? " " : "") + next
            } else { cumulativeText = script.text(for: t.turns[i]) }
        }
        for w in t.words where w.speakerId == nil {
            let r: String
            if w.startUs == nil { r = "missingTime" }
            else if w.startUs == w.endUs { r = w.tokenKind == .punctuation ? "zeroTimePunctuation" : "zeroTimeLexical" }
            else if w.overlap { r = "overlap" }
            else if w.reviewIssueIds.contains(where: { id in t.reviewIssues.contains { $0.id == id && $0.kind == .boundary_conflict } }) { r = "speakerBoundary" }
            else { r = "coverageOrMissingProviderSpeaker" }
            unknownReasons[r, default: 0] += 1
        }
        let md = String(decoding: try script.markdown(), as: UTF8.self)
        let exported = md.components(separatedBy: "### [").count - 1
        try require(exported == blocks.count, "markdown-block-count")
        try require(blocks.flatMap(\.turnIDs) == t.turns.map(\.id), "turn-order-preservation")
        try require(blocks.flatMap { $0.turns.flatMap(\.wordIds) } == t.words.map(\.id), "source-word-order")
        let speech = blocks.filter(\.isSpeech)
        var issueCounts: [String: Int] = [:]
        for issue in t.reviewIssues { issueCounts[issue.kind.rawValue, default: 0] += 1 }
        return ["runID": t.runId, "algorithm": t.provenance.algorithmVersion,
            "readingPolicy": ScriptReadingPolicy.algorithmVersion, "durationUs": t.durationUs,
            "words": t.words.count, "lexical": t.words.filter { $0.tokenKind == .lexical }.count,
            "punctuation": t.words.filter { $0.tokenKind == .punctuation }.count,
            "zeroTimeWords": t.words.filter { $0.startUs != nil && $0.startUs == $0.endUs }.count,
            "nilTimeWords": t.words.filter { $0.startUs == nil }.count,
            "unknownWords": unknownReasons, "turns": t.turns.count,
            "speechTurns": t.turns.filter { $0.kind == .speech }.count,
            "blocks": blocks.count, "blockStartIDs": blocks.map(\.id), "speechBlocks": speech.count,
            "shortSpeechBlocks": speech.filter { b in
                guard let s = b.startUs, let e = b.endUs else { return false }; return e - s < 1_000_000
            }.count,
            "punctuationOnlySpeechBlocks": speech.filter { b in
                let ids = Set(b.turns.flatMap(\.wordIds)); return t.words.filter { ids.contains($0.id) }.allSatisfy { $0.tokenKind == .punctuation }
            }.count,
            "boundaryReasonsExclusive": reasons, "issues": issueCounts,
            "joinedAfterAccumulatedSentenceEnd": missedAccumulatedEnds,
            "humanRevision": t.revision.humanEdited, "textOverrides": script.turnTexts.count,
            "nameOverrides": script.turnNames.count, "manualBoundaries": script.paragraphBreaks?.count ?? 0,
            "reviewRecords": script.reviewRecords?.count ?? 0,
            "markdownBlockCount": exported, "blocksSecondsSingleOptimizedRun": elapsed]
    }
    static func synthetic() throws -> [String: Any] {
        func model(_ texts: [String], _ labels: [String], gap: Bool = false) throws -> LibraryScript {
            let tokens: [[String: Any]] = texts.enumerated().map { i, text in
                ["text": text, "start_ms": i * 200 + 10, "end_ms": i * 200 + 110, "speaker": labels[i]]
            }
            let asr = try JSONSerialization.data(withJSONObject: ["id": "job", "text": texts.joined(), "tokens": tokens])
            let d: [[String: Any]] = gap ? [["speaker": "A", "start": 0.0, "end": 0.12],
                ["speaker": "B", "start": 0.12, "end": 0.20], ["speaker": "A", "start": 0.20, "end": 2.0]] :
                Set(labels).count == 1 ? [["speaker": labels[0], "start": 0.0, "end": 2.0]] :
                    labels.enumerated().map { ["speaker": $0.element, "start": Double($0.offset) * 0.2, "end": Double($0.offset + 1) * 0.2] }
            let p2 = try JSONSerialization.data(withJSONObject: ["jobId": "p2", "status": "succeeded", "output": ["diarization": d, "exclusiveDiarization": d]])
            let t = try SonioxPrecisionNormalizer.normalize(soniox: asr, diarization: p2, sonioxJobID: "job", sessionID: "s", runID: "r", durationUs: 2_000_000, audioSHA256: String(repeating: "a", count: 64), model: "synthetic", createdAt: "2026-09-11T00:00:00Z", synthetic: true)
            return try LibraryScript(transcript: t, title: "synthetic", recordedAt: nil, dateSource: "synthetic", input: ConversionNotes())
        }
        let continuation = try model(["조건을", " 검토하고"], ["A", "A"])
        try require(continuation.blocks().count == 1, "known-speaker-continuation")
        let aba = try model(["조건을", " 네", " 검토하고"], ["A", "B", "A"])
        try require(aba.blocks().count == 3, "short-B-barrier")
        let missing = try model(["조건을", " 검토하고"], ["A", "A"], gap: true)
        try require(missing.blocks().map(\.isSpeech) == [true, false, true], "missing-B-barrier")
        var manual = continuation
        try manual.setParagraphBreak(before: "t1", split: true)
        try require(manual.blocks().count == 2, "manual-split")
        let whole = try model(["완료했습니다.", " 다음입니다."], ["A", "A"])
        let split = try model(["완료했습니다", ".", " 다음입니다", "."], ["A", "A", "A", "A"])
        try require(whole.blocks().count == 2 && split.blocks().count == 2, "split-punctuation-defect-fixed")
        for s in [continuation, aba, missing, manual, whole, split] { _ = try measure(s) }
        return ["controlsPassed": 6, "wholeSentenceBlocks": whole.blocks().count,
                "splitPunctuationBlocks": split.blocks().count, "splitPunctuationDefectFixed": true]
    }
    static func main() throws {
        try require(CommandLine.arguments.count == 6, "arguments")
        let folder = URL(fileURLWithPath: CommandLine.arguments[1]), root = URL(fileURLWithPath: CommandLine.arguments[2])
        let output = URL(fileURLWithPath: CommandLine.arguments[3])
        var evidence: [String: String] = [:]
        func read(_ url: URL) throws -> Data {
            let d = try Data(contentsOf: url); evidence[url.path] = hash(d); return d
        }
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasSuffix(".dama.json") }
        var scripts: [LibraryScript] = []
        for file in files { scripts.append(try JSONDecoder().decode(LibraryScript.self, from: read(file))) }
        try require(Set(scripts.map(\.id)).count == scripts.count, "unique-script-IDs")
        guard let combined = scripts.first(where: { $0.transcript.runId == CommandLine.arguments[4] && $0.transcript.provenance.algorithmVersion == "soniox-p2-v2" }),
              let sourceID = combined.input.sonioxSourceRunID,
              let soniox = scripts.first(where: { $0.id == sourceID }),
              let qwen = scripts.first(where: { $0.transcript.runId == CommandLine.arguments[5] && $0.transcript.sessionId == combined.transcript.sessionId && $0.transcript.provenance.algorithmVersion == "qwen-p2-v1" }) else { throw LibraryFailure.missingFile }
        let selected = [soniox, combined, qwen]
        let session = root.appendingPathComponent("Sessions/" + combined.transcript.sessionId)
        let audioURL = session.appendingPathComponent("audio/analysis.wav")
        let audioHash = hash(try read(audioURL))
        var rows: [[String: Any]] = []
        var p2Hashes: [String] = []
        for script in selected {
            let t = script.transcript, p = t.provenance
            try require(p.sourceAudioSHA256 == audioHash && t.durationUs == combined.transcript.durationUs, "same-audio")
            let run = session.appendingPathComponent("runs/" + t.runId)
            let recreated: TranscriptDocument
            if p.engine == .hybridPyannoteQwen {
                let p2 = try read(run.appendingPathComponent("raw/pyannote-response.json")); p2Hashes.append(hash(p2))
                recreated = try QwenNormalizer.normalize(read(run.appendingPathComponent("raw/qwen-response.json")), diarization: p2, sessionID: t.sessionId, runID: t.runId, durationUs: t.durationUs, audioSHA256: audioHash, createdAt: p.createdAt)
            } else {
                let raw = try read(run.appendingPathComponent("raw/soniox-response.json"))
                let jobID = try JSONDecoder().decode(SonioxTranscriptDTO.self, from: raw).id
                if p.engine == .managedSoniox {
                    recreated = try SonioxNormalizer.normalize(raw, jobID: jobID, sessionID: t.sessionId, runID: t.runId, durationUs: t.durationUs, audioSHA256: audioHash, model: p.asrModel, createdAt: p.createdAt)
                } else {
                    let p2 = try read(run.appendingPathComponent("raw/pyannote-response.json")); p2Hashes.append(hash(p2))
                    recreated = try SonioxPrecisionNormalizer.normalize(soniox: raw, diarization: p2, sonioxJobID: jobID, sessionID: t.sessionId, runID: t.runId, durationUs: t.durationUs, audioSHA256: audioHash, model: p.asrModel, createdAt: p.createdAt)
                }
            }
            try require(try NormalizedTranscriptCodec.encode(recreated) == NormalizedTranscriptCodec.encode(t), "raw-reconstruction-equals-saved-model")
            var row = try measure(script); row["rawReconstructionEqual"] = true
            rows.append(row)
        }
        try require(Set(p2Hashes).count == 1, "same-P2-response")
        for (path, previous) in evidence { try require(hash(Data(contentsOf: URL(fileURLWithPath: path))) == previous, "source-unchanged") }
        let result: [String: Any] = ["format": "dama-reading-diagnostic-v1", "measuredAt": ISO8601DateFormatter().string(from: Date()), "synthetic": try synthetic(), "rows": rows, "inputSHA256": evidence, "sameP2": true, "sourceFilesUnchanged": true]
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: output, options: .withoutOverwriting)
        print("reading diagnostic: raw reconstruction, production blocks, Markdown and source hashes verified; \(rows.count) paths")
    }
}

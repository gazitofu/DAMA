// Usage: NemotronCombine <Sessions dir> <diagnostics/nemotron dir> <output.tsv>
import DamaAudio
import DamaCore
import Foundation

struct ProbeMeta: Decodable { let sessionID: String; let audioSHA256: String; let sampleCount: Int; let frameCount: Int; let channels: Int }
struct Summary: Decodable { let session: String; let nemotronChannels: Int; let expected: Int? }
struct RunState: Decodable { let id: String; let stage: String; let parentRunID: String?; let reportedModel: String?; let createdAt: String
    struct Input: Decodable { let transcriptionProvider: String? }; let input: Input? }

func stats(_ doc: TranscriptDocument, hours: Double) -> (lexical: Int, unassigned: Double, missingPerHour: Double, speakers: Int, assignedSpeakers: Int) {
    let lexical = doc.words.filter { $0.tokenKind == .lexical }
    let unassigned = lexical.filter { $0.speakerId == nil }.count
    let missing = doc.turns.filter { $0.kind == .missingSpeech }.count
    return (lexical.count, lexical.isEmpty ? 0 : 100 * Double(unassigned) / Double(lexical.count), Double(missing) / hours,
            doc.speakers.count, Set(doc.words.compactMap(\.speakerId)).count)
}

let args = CommandLine.arguments
guard args.count == 4 else { print("usage: NemotronCombine <Sessions> <diagnostics/nemotron> <out.tsv>"); exit(2) }
let sessions = URL(fileURLWithPath: args[1], isDirectory: true), diagnostics = URL(fileURLWithPath: args[2], isDirectory: true)
let fm = FileManager.default
let summaries = try JSONDecoder().decode([Summary].self, from: Data(contentsOf: diagnostics.appendingPathComponent("summary.json")))
var lines = ["session\thours\texpected\tchannels1a\tspeakers\tchannelsMatch\tassignedSpeakers\tlexical\tunassignedPct\tmissingPerHour\tp2Speakers\tp2AssignedSpeakers\tp2UnassignedPct\tp2MissingPerHour\tvalid"]
var failures = 0
let probeDirs = try fm.contentsOfDirectory(atPath: diagnostics.path)
for summary in summaries.sorted(by: { $0.session < $1.session }) {
    // summary.json stores the 8-character prefix; directories use the full session UUID.
    let matches = probeDirs.filter { $0.hasPrefix(summary.session) && $0.count == 36 }
    guard matches.count == 1 else { failures += 1; lines.append("\(summary.session)\terror\tprefix matches \(matches.count)"); continue }
    let id = matches[0]
    let probeDir = diagnostics.appendingPathComponent(id)
    do {
        let meta = try JSONDecoder().decode(ProbeMeta.self, from: Data(contentsOf: probeDir.appendingPathComponent("meta.json")))
        let probabilities = try Data(contentsOf: probeDir.appendingPathComponent("probs.f32"))
        let runsDir = sessions.appendingPathComponent(id).appendingPathComponent("runs")
        var soniox: (RunState, URL)?, p2: URL?
        for name in try fm.contentsOfDirectory(atPath: runsDir.path).sorted() {
            let dir = runsDir.appendingPathComponent(name)
            guard let state = try? JSONDecoder().decode(RunState.self, from: Data(contentsOf: dir.appendingPathComponent("state.json"))),
                  state.stage == "readyForReview" else { continue }
            let provider = state.input?.transcriptionProvider ?? "pyannote"
            if provider == "soniox", fm.fileExists(atPath: dir.appendingPathComponent("raw/soniox-response.json").path),
               soniox == nil || state.createdAt > soniox!.0.createdAt { soniox = (state, dir) }
            if provider == "sonioxPrecision", fm.fileExists(atPath: dir.appendingPathComponent("normalized/model.json").path) { p2 = dir }
        }
        guard let (state, dir) = soniox else { print("\(id.prefix(8)) no Soniox raw"); failures += 1; continue }
        let asr = try Data(contentsOf: dir.appendingPathComponent("raw/soniox-response.json"))
        let jobID = try JSONDecoder().decode(SonioxTranscriptDTO.self, from: asr).id
        let durationUs = try AudioFiles.microseconds(frames: Int64(meta.sampleCount), rate: 16_000)
        let runID = UUID().uuidString
        let doc = try SonioxNemotronReconciler.normalize(soniox: asr, probabilities: probabilities, frameCount: meta.frameCount,
            channels: meta.channels, sonioxJobID: jobID, sessionID: id, runID: runID, durationUs: durationUs,
            audioSHA256: meta.audioSHA256, model: state.reportedModel ?? "stt-async-v5", createdAt: "2026-10-30T00:00:00Z")
        try TranscriptValidator().validate(doc)
        let hours = Double(durationUs) / 3_600_000_000
        let s = stats(doc, hours: hours)
        var p2Cols = "-\t-\t-\t-"
        if let p2 {
            let model = try NormalizedTranscriptCodec.decode(Data(contentsOf: p2.appendingPathComponent("normalized/model.json")))
            let t = stats(model, hours: hours)
            p2Cols = "\(t.speakers)\t\(t.assignedSpeakers)\t\(String(format: "%.2f", t.unassigned))\t\(String(format: "%.1f", t.missingPerHour))"
        }
        lines.append("\(id.prefix(8))\t\(String(format: "%.2f", hours))\t\(summary.expected.map(String.init) ?? "-")\t\(summary.nemotronChannels)\t\(s.speakers)\t\(s.speakers == summary.nemotronChannels)\t\(s.assignedSpeakers)\t\(s.lexical)\t\(String(format: "%.2f", s.unassigned))\t\(String(format: "%.1f", s.missingPerHour))\t\(p2Cols)\ttrue")
    } catch {
        failures += 1
        lines.append("\(id.prefix(8))\terror\t\(error)")
    }
}
try (lines.joined(separator: "\n") + "\n").write(to: URL(fileURLWithPath: args[3]), atomically: true, encoding: .utf8)
print(lines.joined(separator: "\n"))
print("failures \(failures)")

// turn-continuity AC-13 · AC-14 (읽기 전용 측정, 네트워크 0). 출력 = 숫자 · ID 앞 8자만. 사용자 데이터에 쓰지 않는다.
// Usage:
//   NemotronV4Check replay  <Sessions> <run8>
//       저장된 Soniox + Nemotron parent를 저장 원응답 · 저장 확률 · 저장 Run ID · 생성 시각 · 저장 버전으로 다시 결합해
//       `normalized/model.json`과 바이트 대조한다.
//   NemotronV4Check measure <Sessions> <run8> <probs dir> <out.json>
//       같은 원응답에 새 확률(<probs dir>/probs.f32 · meta.json)로 v4 결합 → 계약 검증 · 지표. 저장 결과(현행)의 지표도 같이 쓴다.
// 지표: 미배정 lexical % · 발화 Turn · 미상 발화 Turn · 어절 중간 Turn 경계 · 문단 · 화자 미확정 문단 · 어절 중간 문단 경계(미상 · A|B).
// 어절 = 공백·줄바꿈 없이 이어진 토큰 묶음 (`SonioxPrecisionReconciler.orthographicGroups`와 같은 규칙을 여기서 다시 쓴다).
import DamaCore
import Foundation

struct ProbeMeta: Decodable { let frameCount: Int; let channels: Int }
struct Metrics: Encodable {
    let algorithmVersion: String
    let lexical: Int, unassignedLexical: Int, unassignedPct: Double
    let speechTurns: Int, unknownSpeechTurns: Int, inWordTurnBoundaries: Int
    let paragraphs: Int, unknownParagraphs: Int, inWordParagraphBoundaries: Int, inWordParagraphBoundariesUnknown: Int, inWordParagraphBoundariesAB: Int
}

func parentRun(_ sessions: URL, _ run8: String) throws -> URL {
    let fm = FileManager.default
    for session in try fm.contentsOfDirectory(atPath: sessions.path) {
        let runs = sessions.appendingPathComponent(session).appendingPathComponent("runs")
        guard let names = try? fm.contentsOfDirectory(atPath: runs.path) else { continue }
        if let name = names.first(where: { $0.hasPrefix(run8) }) { return runs.appendingPathComponent(name) }
    }
    throw CocoaError(.fileNoSuchFile)
}

func groups(_ words: [TranscriptWord]) -> [String: Int] {
    var result: [String: Int] = [:], group = 0, open = false
    for word in words {
        let text = word.prefix + word.text
        if open && (text.first?.isWhitespace == true || text.contains("\n")) { group += 1 }
        result[word.id] = group; open = true
        if text.last?.isWhitespace == true { group += 1; open = false }
    }
    return result
}

func metrics(_ doc: TranscriptDocument) throws -> Metrics {
    let words = Dictionary(uniqueKeysWithValues: doc.words.map { ($0.id, $0) })
    let group = groups(doc.words)
    let lexical = doc.words.filter { $0.tokenKind == .lexical }
    let unassigned = lexical.filter { $0.speakerId == nil }.count
    let speech = doc.turns.filter { $0.kind == .speech }
    var turnBoundaries = 0
    for (a, b) in zip(speech, speech.dropFirst()) {
        if let l = a.wordIds.last, let r = b.wordIds.first, group[l] != nil, group[l] == group[r] { turnBoundaries += 1 }
    }
    let script = try LibraryScript(transcript: doc, title: "측정", recordedAt: nil, dateSource: "측정", input: ConversionNotes())
    let blocks = script.blocks()
    func lexicalWords(_ block: ScriptBlock) -> [TranscriptWord] {
        block.turns.flatMap(\.wordIds).compactMap { words[$0] }.filter { $0.tokenKind == .lexical }
    }
    var paragraphBoundaries = 0, unknownSide = 0, ab = 0
    for (a, b) in zip(blocks, blocks.dropFirst()) {
        guard let l = lexicalWords(a).max(by: { $0.ordinal < $1.ordinal }), let r = lexicalWords(b).min(by: { $0.ordinal < $1.ordinal }),
              group[l.id] != nil, group[l.id] == group[r.id] else { continue }
        paragraphBoundaries += 1
        if a.speakerID == nil || b.speakerID == nil { unknownSide += 1 } else if a.speakerID != b.speakerID { ab += 1 }
    }
    return Metrics(algorithmVersion: doc.provenance.algorithmVersion, lexical: lexical.count, unassignedLexical: unassigned,
        unassignedPct: lexical.isEmpty ? 0 : (Double(unassigned) * 10_000 / Double(lexical.count)).rounded() / 100,
        speechTurns: speech.count, unknownSpeechTurns: speech.filter { $0.speakerId == nil }.count, inWordTurnBoundaries: turnBoundaries,
        paragraphs: blocks.count, unknownParagraphs: blocks.filter { $0.speakerID == nil }.count,
        inWordParagraphBoundaries: paragraphBoundaries, inWordParagraphBoundariesUnknown: unknownSide, inWordParagraphBoundariesAB: ab)
}

func combine(run: URL, stored: TranscriptDocument, probabilities: Data, frameCount: Int, channels: Int,
             version: SonioxNemotronReconciler.Version) throws -> TranscriptDocument {
    let asr = try Data(contentsOf: run.appendingPathComponent("raw/soniox-response.json"))
    let jobID = try JSONDecoder().decode(SonioxTranscriptDTO.self, from: asr).id
    return try SonioxNemotronReconciler.normalize(soniox: asr, probabilities: probabilities, frameCount: frameCount, channels: channels,
        sonioxJobID: jobID, sessionID: stored.sessionId, runID: stored.runId, durationUs: stored.durationUs,
        audioSHA256: stored.provenance.sourceAudioSHA256 ?? "", model: stored.provenance.asrModel, createdAt: stored.provenance.createdAt,
        synthetic: stored.provenance.isSynthetic, captureInterrupted: stored.reviewIssues.contains { $0.kind == .capture_interrupted },
        version: version)
}

let args = CommandLine.arguments
guard args.count >= 4 else { print("usage: NemotronV4Check replay <Sessions> <run8> | measure <Sessions> <run8> <probs dir> <out.json>"); exit(2) }
let sessions = URL(fileURLWithPath: args[2], isDirectory: true), run8 = args[3]
let run = try parentRun(sessions, run8)
let storedBytes = try Data(contentsOf: run.appendingPathComponent("normalized/model.json"))
let stored = try NormalizedTranscriptCodec.decode(storedBytes)
let storedMeta = try JSONDecoder().decode(ProbeMeta.self, from: Data(contentsOf: run.appendingPathComponent("raw/nemotron-meta.json")))
let storedProbabilities = try Data(contentsOf: run.appendingPathComponent("raw/nemotron-probabilities.f32"))

switch args[1] {
case "replay":
    guard let version = SonioxNemotronReconciler.Version(rawValue: stored.provenance.algorithmVersion) else { print("\(run8) unknown version"); exit(1) }
    let again = try combine(run: run, stored: stored, probabilities: storedProbabilities, frameCount: storedMeta.frameCount,
                            channels: storedMeta.channels, version: version)
    let bytes = try NormalizedTranscriptCodec.encode(again)
    print("\(run8) replay \(version.rawValue) stored \(storedBytes.count) B replayed \(bytes.count) B byte-identical \(bytes == storedBytes)")
    exit(bytes == storedBytes ? 0 : 1)
case "measure":
    guard args.count == 6 else { exit(2) }
    let dir = URL(fileURLWithPath: args[4], isDirectory: true)
    let meta = try JSONDecoder().decode(ProbeMeta.self, from: Data(contentsOf: dir.appendingPathComponent("meta.json")))
    let probabilities = try Data(contentsOf: dir.appendingPathComponent("probs.f32"))
    let v4 = try combine(run: run, stored: stored, probabilities: probabilities, frameCount: meta.frameCount, channels: meta.channels, version: .v4)
    try TranscriptValidator().validate(v4)
    struct Report: Encodable { let run: String; let durationMinutes: Double; let current: Metrics; let v4: Metrics; let contractValid: Bool }
    let report = Report(run: run8, durationMinutes: (Double(stored.durationUs) / 600_000).rounded() / 100,
                        current: try metrics(stored), v4: try metrics(v4), contractValid: true)
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(report).write(to: URL(fileURLWithPath: args[5]))
    print("\(run8) v4 contract valid · speech turns \(report.current.speechTurns) → \(report.v4.speechTurns) · unknown paragraphs \(report.current.unknownParagraphs) → \(report.v4.unknownParagraphs)")
default:
    exit(2)
}

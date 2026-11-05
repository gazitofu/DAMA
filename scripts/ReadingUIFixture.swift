// Synthetic native UI fixture only. No user's libraries, microphones, models or network.
import AVFoundation
import DamaAudio
import DamaCore
import Foundation

@main struct ReadingUIFixture {
    static func main() async throws {
        guard CommandLine.arguments.count == 2 else { fatalError("Expected a fresh /private/tmp/dama-reading-qa-* folder") }
        let folder = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
        guard folder.path.hasPrefix("/private/tmp/dama-reading-qa-"), !FileManager.default.fileExists(atPath: folder.path) else { throw LibraryFailure.unsafePath }
        let speechFolder = folder.appendingPathComponent("Speeches"), scriptFolder = folder.appendingPathComponent("Scripts"), root = folder.appendingPathComponent("internal")
        for path in [speechFolder, scriptFolder, root] { try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true) }
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 480_000)!
        buffer.frameLength = 480_000
        for i in 0..<Int(buffer.frameLength) { buffer.floatChannelData![0][i] = 0 }
        for name in ["제품 검토 회의 · 합성", "변환 전 녹음 · 합성"] {
            let audio = try AVAudioFile(forWriting: speechFolder.appendingPathComponent(name + ".wav"), settings: format.settings)
            try audio.write(from: buffer)
        }
        let store = FolderLibraryStore(root: root)
        let speeches = try await store.speeches(in: speechFolder)
        let speech = speeches.first { $0.title.contains("제품") }!
        _ = try await AudioLibrary(root: root).prepareAnalysis(speech.id)
        let labels = ["A", "A", "A", "B", "C", "C", "B", "A", "B", "C"]
        let text = ["이번 분기에는 사용자가 녹음을 옮기는 과정과", "처음 스크립트를 읽고 수정하는 과정을 함께 살펴보고",
                    "제품의 우선순위를 결정하면 좋겠습니다.", "네, 먼저 화면에서 불편했던 부분부터 이야기하겠습니다.",
                    "여기서는 본문을 직접 수정하고", "제목은 별도 저장 없이 입력하는 방식입니다.", "화자 이름도 눌러서 바꿀 수 있겠네요.",
                    "AI 참고 내용은 마지막 확인 뒤에만 전달합니다.", "이전 결과도 따로 보존하면 좋겠습니다.", "이 파일의 음성과 대사는 모두 합성 검증 자료입니다."]
        let intervals: [[String: Any]] = labels.enumerated().map { ["start": Double($0.offset * 2), "end": Double($0.offset * 2 + 1), "speaker": $0.element] }
        let words: [[String: Any]] = labels.enumerated().map { ["start": Double($0.offset * 2), "end": Double($0.offset * 2) + 0.8, "speaker": $0.element, "text": text[$0.offset]] }
        let payload = try JSONSerialization.data(withJSONObject: ["jobId": "synthetic-ui", "status": "succeeded", "output": ["diarization": intervals, "exclusiveDiarization": intervals, "wordLevelTranscription": words]])
        var model = try ManagedNormalizer.normalize(payload, sessionID: speech.id, runID: UUID().uuidString, durationUs: 30_000_000,
            audioSHA256: speech.sourceHash, synthetic: true, createdAt: "2026-09-12T00:00:00Z")
        model.provenance.engine = .hybridSonioxPyannote
        // Deliberate normalized unknown for the UI journey; no provider accuracy claim.
        model.words[8].speakerId = nil; model.words[8].assignmentSource = .unknown
        for i in model.turns.indices where model.turns[i].wordIds.contains(model.words[8].id) { model.turns[i].speakerId = nil }
        // usage-bundle1 경고 표시 검증용 합성 이슈: 첫 문단 자동 경고 8종(+화자 경계 1), 넷째 원구간 같은 건수 2종,
        // 다섯째 일부 결과, 마지막 녹음 중단. 실제 판정 결과가 아니다.
        func attach(_ turn: Int, _ kind: IssueKind) throws {
            let id = "ui-fixture-issue-\(model.reviewIssues.count)"
            let value: [String: Any] = ["id": id, "kind": kind.rawValue, "startUs": model.turns[turn].startUs ?? NSNull(),
                "endUs": model.turns[turn].endUs ?? NSNull(), "severity": "warning", "status": "open", "wordIds": [], "sourceIntervalIds": []]
            model.reviewIssues.append(try JSONDecoder().decode(ReviewIssue.self, from: JSONSerialization.data(withJSONObject: value)))
            model.turns[turn].reviewIssueIds.append(id)
        }
        for kind in [IssueKind.ambiguous_speaker, .overlapping_speech, .missing_speech, .provider_disagreement, .boundary_conflict,
                     .unrepresented_speaker, .invalid_timestamp, .low_confidence, .boundary_conflict] { try attach(0, kind) }
        for kind in [IssueKind.overlapping_speech, .overlapping_speech, .boundary_conflict, .boundary_conflict] { try attach(3, kind) }
        try attach(4, .partial_result)
        try attach(model.turns.count - 1, .capture_interrupted)
        var notes = ConversionNotes(speakerCount: 3, context: "합성 제품 UI 회의", reference: "외부 전송하지 않는 검증 자료", participants: "김가상 · 개발\n이가상 · 디자인\n박가상 · 운영")
        notes.meetingTerms = "DAMA\n제품 검토"
        try await store.saveNotes(notes, speechID: speech.id)
        let current = try await store.createScript(model, speech: speech, input: notes, in: scriptFolder)
        var ai = ScriptCorrection(input: notes, engine: "합성 UI 검증 · 실제 AI 호출 없음", state: .completed)
        ai.completedAt = Date()
        let versioned = try await store.saveCorrection(ai, for: current)
        _ = try await store.saveTitle("제품 검토 회의", for: versioned)
        var comparison = model
        comparison.runId = UUID().uuidString
        comparison.provenance.engine = .managedSoniox
        comparison.revision.id = "model-\(comparison.runId)"
        comparison.revision.sourceRunId = comparison.runId
        var comparisonInput = notes
        comparisonInput.transcriptionProvider = .soniox
        _ = try await store.createScript(comparison, speech: speech, input: comparisonInput, in: scriptFolder)
        print("Synthetic UI fixture created: 2 speeches, 2 results for 1 Speech, 2 historical snapshots; no external requests.")
    }
}

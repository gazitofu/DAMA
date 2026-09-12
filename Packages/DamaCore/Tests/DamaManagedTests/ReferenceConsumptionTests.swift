import Foundation
import XCTest
import DamaCore
import DamaAudio
@testable import DamaManaged

final class ReferenceConsumptionTests: XCTestCase {
    func testSelectedFolderReachesActualSonioxPayloadAndLocalQwenWorker() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = root.appendingPathComponent("references")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let content = "합성회사 별칭 안내\n\n한빛은 합성회사 HANBIT을 뜻합니다."
        try Data(content.utf8).write(to: folder.appendingPathComponent("glossary.md"))
        try Data("읽지 않는 문서".utf8).write(to: folder.appendingPathComponent("ignored.pdf"))
        var notes = ConversionNotes(speakerCount: 3, context: "합성회사 제품 회의", reference: "별칭 한빛", participants: "김가상 · 합성회사")
        notes.meetingTerms = "HANBIT\n김가상"
        let excerpts = try await ReferenceFolder().excerpts(in: folder, query: notes.context)
        XCTAssertEqual(excerpts.map(\.name), ["glossary.md"])
        let expectedExcerpt = "합성회사 별칭 안내\n\n[…]\n\n한빛은 합성회사 HANBIT을 뜻합니다."
        XCTAssertEqual(excerpts.first?.text, expectedExcerpt)
        var soniox = notes.forTranscription(.sonioxPrecision, sonioxContext: true)
        soniox.referenceExcerpts = excerpts
        let selected = try SonioxRequest.prepare(soniox, includeFolder: true)
        let payload = try JSONSerialization.jsonObject(with: SonioxRequest.payload(fileID: UUID().uuidString, runID: UUID().uuidString, input: selected)) as! [String: Any]
        let context = try XCTUnwrap(payload["context"] as? [String: Any])
        XCTAssertEqual(context["terms"] as? [String], ["HANBIT", "김가상"])
        XCTAssertEqual(context["text"] as? String, "별칭 한빛\n\n" + expectedExcerpt)
        XCTAssertTrue((context["general"] as? [[String: String]])?.contains(["key": "participants", "value": "김가상 · 합성회사"]) == true)
        let noFolder = try SonioxRequest.prepare(soniox, includeFolder: false)
        XCTAssertFalse(String(decoding: try SonioxRequest.context(noFolder)!, as: UTF8.self).contains("HANBIT을 뜻합니다"))
        let disabled = notes.forTranscription(.soniox, sonioxContext: false)
        XCTAssertNil(try SonioxRequest.context(disabled))
        XCTAssertFalse(disabled.provider.consumesContext(sonioxEnabled: false))
        XCTAssertFalse(disabled.provider.consumesSpeakerCount(sonioxEnabled: false))
        let pyannote = notes.forTranscription(.pyannote, sonioxContext: true)
        XCTAssertFalse(pyannote.provider.consumesContext(sonioxEnabled: true))
        XCTAssertEqual(pyannote.context, notes.context) // Hidden notes are preserved.
        XCTAssertEqual(pyannote.aiCorrection, false)

        let worker = root.appendingPathComponent("fixture.py")
        try Data("""
        import json, sys
        from pathlib import Path
        r = json.loads(Path(sys.argv[sys.argv.index('--request') + 1]).read_text())
        w = Path(r['workDirectory'])
        (w / 'consumed-context.txt').write_text(r['context'])
        (w / 'result.json').write_text(json.dumps({'version':'qwen-worker-v1', 'status':'complete',
          'audioSHA256':r['audioSHA256'], 'durationUs':r['durationUs'], 'text':'합성', 'words':[], 'chunks':[]}))
        """.utf8).write(to: worker)
        try Data("{}".utf8).write(to: root.appendingPathComponent("config.json"))
        let runtime = root.appendingPathComponent("runtime.json")
        let model: (String) -> [String: String] = { ["id": $0, "path": root.path, "revision": "synthetic"] }
        try JSONSerialization.data(withJSONObject: ["version": 1, "python": "/usr/bin/python3", "worker": worker.path,
            "upstreamCommit": "1e28932dac8e2c68b34c29f32e2be338ffc1c852", "models": ["asr": model("Qwen/Qwen3-ASR-1.7B"), "aligner": model("Qwen/Qwen3-ForcedAligner-0.6B")]]).write(to: runtime)
        var qwen = notes.forTranscription(.qwen, sonioxContext: false); qwen.referenceExcerpts = excerpts
        let work = root.appendingPathComponent("work")
        _ = try await QwenRunner(runtimeURL: runtime).transcribe(audio: root.appendingPathComponent("unused.wav"), work: work,
            input: qwen, audioHash: String(repeating: "a", count: 64), durationUs: 1_000_000)
        let consumed = try String(contentsOf: work.appendingPathComponent("consumed-context.txt"), encoding: .utf8)
        XCTAssertEqual(consumed, "합성회사 제품 회의\n김가상 · 합성회사\n별칭 한빛\nHANBIT\n김가상\n" + expectedExcerpt)
        XCTAssertTrue(qwen.provider.consumesContext(sonioxEnabled: false))
    }
}

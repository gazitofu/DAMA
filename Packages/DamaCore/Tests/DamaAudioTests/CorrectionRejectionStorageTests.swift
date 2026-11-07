import DamaCore
import Foundation
import XCTest
@testable import DamaAudio

/// correction-turn-isolation AC-05 ⓒ·ⓓ·ⓔ: `rejectedTurns`의 저장 왕복과 폴더 조회의 손상 분류. 합성 fixture만 쓴다.
final class CorrectionRejectionStorageTests: XCTestCase {
    private func setup() throws -> (folder: URL, root: URL, model: TranscriptDocument) {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = base.appendingPathComponent("Scripts")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: base) }
        var repo = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { repo.deleteLastPathComponent() }
        let model = try JSONDecoder().decode(TranscriptDocument.self,
            from: Data(contentsOf: repo.appendingPathComponent("fixtures/normalized-transcript.json")))
        return (folder, base.appendingPathComponent("internal"), model)
    }
    private func correction(for script: LibraryScript, rejected: [CorrectionRejectedTurn]) throws -> ScriptCorrection {
        var value = ScriptCorrection(input: script.input, engine: "synthetic context-correction-7", state: .completed)
        let edit: [String: Any] = ["turnID": "t1", "original": script.text(for: script.transcript.turns[0]), "text": "합성 후보",
                                   "reason": "합성 보류", "applied": false]
        value.edits = [try JSONDecoder().decode(CorrectionEdit.self, from: JSONSerialization.data(withJSONObject: edit))]
        value.rejectedTurns = rejected
        value.completedAt = Date()
        return value
    }

    /// ⓓ 저장 → 다시 열기 = 같은 값, 활성 파일에 키 1개. ⓔ transcript 바이트 불변.
    func testRejectedTurnsRoundTripThroughFolderStore() async throws {
        let (folder, root, model) = try setup()
        let store = FolderLibraryStore(root: root)
        let script = try LibraryScript(transcript: model, title: "합성", recordedAt: nil, dateSource: "합성", input: ConversionNotes())
        let first = try await store.saveScript(script, to: folder.appendingPathComponent("s.dama.json"), expectedHash: nil)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let before = try encoder.encode(first.script.transcript)
        let saved = try await store.saveCorrection(try correction(for: first.script, rejected: [.init(turnID: "t3", rule: .quote)]), for: first)
        let reopened = try await store.scanScripts(in: folder)
        XCTAssertEqual(reopened.issues.count, 0)
        let file = try XCTUnwrap(reopened.items.first)
        XCTAssertEqual(file.script.correction?.rejectedTurns, [.init(turnID: "t3", rule: .quote)])
        XCTAssertEqual(saved.script.correction?.rejectedTurns, [.init(turnID: "t3", rule: .quote)])
        let bytes = String(decoding: try Data(contentsOf: file.url), as: UTF8.self)
        XCTAssertEqual(bytes.components(separatedBy: #""rejectedTurns""#).count - 1, 1)
        XCTAssertEqual(try encoder.encode(file.script.transcript), before)
        XCTAssertEqual(file.script.transcript.turns.map(\.id), model.turns.map(\.id))
    }

    /// ⓒ 위반 4종은 목록에서 빠지고 현행 손상 분류(`.unreadable`)로 보인다. 정상 1개는 목록에 남는다(양성 대조).
    func testInvalidRejectedTurnsAreListedAsUnreadable() async throws {
        let (folder, root, model) = try setup()
        let script = try LibraryScript(transcript: model, title: "합성", recordedAt: nil, dateSource: "합성", input: ConversionNotes())
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        func write(_ name: String, _ rejected: [CorrectionRejectedTurn], rule: String? = nil) throws {
            var value = script; value.correction = try correction(for: script, rejected: rejected)
            var data = try encoder.encode(value)
            if let rule {
                var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
                var object = json["correction"] as! [String: Any]
                object["rejectedTurns"] = [["turnID": "t3", "rule": rule]]
                json["correction"] = object
                data = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
            }
            try data.write(to: folder.appendingPathComponent(name + ".dama.json"))
        }
        try write("ok", [.init(turnID: "t3", rule: .quote)])
        try write("outside", [.init(turnID: "t-marker", rule: .quote)])
        try write("duplicate", [.init(turnID: "t3", rule: .quote), .init(turnID: "t3", rule: .text)])
        try write("edited", [.init(turnID: "t1", rule: .limit)])
        try write("bogus", [.init(turnID: "t3", rule: .quote)], rule: "bogus")
        let result = try await FolderLibraryStore(root: root).scanScripts(in: folder)
        XCTAssertEqual(result.items.map(\.url.lastPathComponent), ["ok.dama.json"])
        XCTAssertEqual(Set(result.issues.map(\.url.lastPathComponent)),
                       ["outside.dama.json", "duplicate.dama.json", "edited.dama.json", "bogus.dama.json"])
        XCTAssertTrue(result.issues.allSatisfy { $0.reason == .unreadable })
    }
}

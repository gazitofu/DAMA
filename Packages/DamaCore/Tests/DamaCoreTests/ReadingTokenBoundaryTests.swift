import Foundation
import XCTest
@testable import DamaCore

final class ReadingTokenBoundaryTests: XCTestCase {
    private func script(_ texts: [String]) throws -> LibraryScript {
        let duration = Double((texts.count + 1) * 200_000) / 1_000_000
        let tokens: [[String: Any]] = texts.enumerated().map {
            ["text": $0.element, "start_ms": $0.offset * 200 + 10, "end_ms": $0.offset * 200 + 110, "speaker": "A"]
        }
        let asr = try JSONSerialization.data(withJSONObject: ["id": "job", "text": texts.joined(), "tokens": tokens])
        let interval: [String: Any] = ["speaker": "A", "start": 0.0, "end": duration]
        let p2 = try JSONSerialization.data(withJSONObject: ["jobId": "p2", "status": "succeeded",
            "output": ["diarization": [interval], "exclusiveDiarization": [interval]]])
        let model = try SonioxPrecisionNormalizer.normalize(soniox: asr, diarization: p2, sonioxJobID: "job",
            sessionID: "s", runID: "r", durationUs: Int64((texts.count + 1) * 200_000),
            audioSHA256: String(repeating: "a", count: 64), model: "synthetic", createdAt: "2026-09-11T00:00:00Z", synthetic: true)
        return try LibraryScript(transcript: model, title: "합성", recordedAt: nil, dateSource: "합성", input: ConversionNotes())
    }

    private func assertReading(_ tokens: [String], _ expected: [String], file: StaticString = #filePath, line: UInt = #line) throws {
        let value = try script(tokens), original = try NormalizedTranscriptCodec.encode(value.transcript)
        let blocks = value.blocks()
        XCTAssertEqual(blocks.map(\.text), expected, file: file, line: line)
        XCTAssertEqual(blocks.flatMap(\.turnIDs), value.transcript.turns.map(\.id), file: file, line: line)
        let loaded = try JSONDecoder().decode(LibraryScript.self, from: JSONEncoder().encode(value))
        XCTAssertEqual(try NormalizedTranscriptCodec.encode(loaded.transcript), original, file: file, line: line)
        XCTAssertEqual(loaded.blocks().map(\.text), expected, file: file, line: line)
        XCTAssertEqual(String(decoding: try loaded.markdown(), as: UTF8.self).components(separatedBy: "### [").count - 1,
                       expected.count, file: file, line: line)
    }

    func testSplitPunctuationAndClosersMatchWholeSentences() throws {
        try assertReading(["완료했습니다.", " 다음입니다."], ["완료했습니다. 다음입니다."])
        try assertReading(["완료했습니다", ".", " 다음입니다", "."], ["완료했습니다. 다음입니다."])
        try assertReading(["완료했습니다", ".", "\"", " 다음입니다", "."], ["완료했습니다.\" 다음입니다."])
        try assertReading(["맞나요", "?", "!", "”", " 다음입니다", "."], ["맞나요?!” 다음입니다."])
    }

    func testFragmentedDecimalEllipsisAndUnfinishedKoreanRemainContinuous() throws {
        try assertReading(["비율은 3", ".", "14", "%", "입니다", ".", " 다음입니다", "."],
                          ["비율은 3.14%입니다. 다음입니다."])
        try assertReading(["검토", ".", ".", ".", " 이어서", " 설명합니다", ".", " 다음입니다", "."],
                          ["검토... 이어서 설명합니다. 다음입니다."])
        try assertReading(["그다음에", ".", " 조건을", ".", " 검토하고", ".", " 정합니다", ".", " 네", "."],
                          ["그다음에. 조건을. 검토하고. 정합니다. 네."])
        try assertReading(["값은 3", ".", " 다음입니다", "."], ["값은 3. 다음입니다."])
    }

    func testManualAndUnknownBoundariesOverridePunctuationAttachment() throws {
        var value = try script(["완료했습니다", ".", " 다음입니다", "."])
        let model = try NormalizedTranscriptCodec.encode(value.transcript)
        try value.setParagraphBreak(before: "t2", split: false)
        XCTAssertEqual(value.blocks().map(\.text), ["완료했습니다. 다음입니다."])
        try value.setParagraphBreak(before: "t2", split: true)
        XCTAssertEqual(value.blocks().map(\.text), ["완료했습니다.", "다음입니다."])
        try value.setParagraphBreak(before: "t2", split: nil)
        XCTAssertEqual(value.blocks().count, 1)
        try value.editText("t0", text: "검토하고")
        XCTAssertEqual(value.blocks().map(\.text), ["검토하고. 다음입니다."])
        XCTAssertEqual(try NormalizedTranscriptCodec.encode(value.transcript), model)

        var unknown = value.transcript
        unknown.words[1].speakerId = nil; unknown.words[1].assignmentSource = .unknown
        unknown.turns[1].speakerId = nil
        let guarded = try LibraryScript(transcript: unknown, title: "합성", recordedAt: nil, dateSource: "합성", input: ConversionNotes())
        XCTAssertEqual(guarded.blocks().map(\.turnIDs), [["t0"], ["t1"], ["t2", "t3"]])
        var manual = guarded
        XCTAssertThrowsError(try manual.setParagraphBreak(before: "t1", split: false))
    }
}

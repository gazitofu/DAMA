import XCTest
@testable import DamaCore

final class QwenNormalizerTests: XCTestCase {
    private let audioHash=String(repeating:"a",count:64)
    private func result(_ words: [[String:Any]], finish: String="eos") throws -> Data {
        try JSONSerialization.data(withJSONObject:["version":"qwen-worker-v1","status":"complete",
            "audioSHA256":audioHash,"durationUs":2_000_000,"text":words.map{$0["text"] as! String}.joined(separator: ""),"words":words,
            "chunks":[["startFrame":0,"endFrame":32000,"finish_reason":finish,"truncated":finish=="length"]]])
    }
    private func normalize(_ words:[[String:Any]], intervals:[[String:Any]], finish:String="eos") throws -> TranscriptDocument {
        let raw=try JSONSerialization.data(withJSONObject:["jobId":"fixture","status":"succeeded","output":
            ["diarization":intervals,"exclusiveDiarization":intervals]])
        return try QwenNormalizer.normalize(result(words,finish:finish),diarization:raw,
            sessionID:"fixture",runID:"new-run",durationUs:2_000_000,audioSHA256:audioHash,createdAt:"2026-09-11T00:00:00Z",synthetic:true)
    }
    private var aba:[[String:Any]] { [["start":0.0,"end":1.0,"speaker":"A"],
        ["start":1.0,"end":1.2,"speaker":"B"],["start":1.2,"end":2.0,"speaker":"A"]] }
    func testMissingShortSpeakerPreventsJoiningAndRoundTrips() throws {
        let doc=try normalize([["text":"H&Q 15.38% 네 ","startUs":200_000,"endUs":800_000],
                              ["text":"네","startUs":1_300_000,"endUs":1_900_000]],intervals:aba)
        XCTAssertEqual(doc.words.map(\.text).joined(separator: ""),"H&Q 15.38% 네 네")
        XCTAssertEqual(doc.words[0].startUs,200_000)
        XCTAssertTrue(doc.turns.contains{$0.kind == .missingSpeech && $0.startUs==1_000_000 && $0.endUs==1_200_000})
        let script=try LibraryScript(transcript:doc,title:"test",recordedAt:nil,dateSource:"fixture",input:ConversionNotes())
        XCTAssertFalse(script.canJoinParagraph(before:"t1"))
        XCTAssertEqual(script.blocks().filter(\.isSpeech).count,2)
        let encoded=try NormalizedTranscriptCodec.encode(doc)
        XCTAssertFalse(encoded.isEmpty)
        XCTAssertEqual(try JSONDecoder().decode(TranscriptDocument.self,from:encoded).provenance.engine,.hybridPyannoteQwen)
    }
    func testBoundaryDoesNotAssignEvenWhenOneSpeakerDominates() throws {
        let doc=try normalize([["text":"네","startUs":100_000,"endUs":1_100_000]],intervals:aba)
        XCTAssertNil(doc.words[0].speakerId); XCTAssertNotNil(doc.words[0].modelSpeakerId)
        XCTAssertEqual(doc.words[0].alignmentScore!,0.9,accuracy:0.00001)
        XCTAssertTrue(doc.reviewIssues.contains{$0.kind == .boundary_conflict})
    }
    func testUnalignedTextAndNoOverlapRemainUnknown() throws {
        let doc=try normalize([["text":"원문 ","startUs":NSNull(),"endUs":NSNull()],
                              ["text":"보존","startUs":100_000,"endUs":200_000]],intervals:[])
        XCTAssertEqual(doc.words.map(\.text).joined(separator: ""),"원문 보존")
        XCTAssertTrue(doc.words.allSatisfy{$0.speakerId == nil})
        XCTAssertEqual(doc.turns.filter{$0.kind == .speech}.flatMap(\.wordIds),["w0","w1"])
    }
    func testIncompleteCannotBeNormalResult() throws {
        for finish in ["length","repetition"] {
            XCTAssertThrowsError(try normalize([["text":"네","startUs":0,"endUs":100_000]],intervals:aba,finish:finish))
        }
    }
    func testReadingDoesNotInsertSpacesBetweenKoreanAlignmentUnits() throws {
        let doc=try normalize([["text":"못하","startUs":100_000,"endUs":200_000],
                              ["text":"고 H&Q 15.38%","startUs":200_000,"endUs":500_000]],
                             intervals:[["start":0.0,"end":2.0,"speaker":"A"]])
        let script=try LibraryScript(transcript:doc,title:"test",recordedAt:nil,dateSource:"fixture",input:ConversionNotes())
        XCTAssertEqual(script.blocks().map(\.text),["못하고 H&Q 15.38%"])
        XCTAssertTrue(String(decoding:try script.markdown(),as:UTF8.self).contains("못하고 H\\&Q 15\\.38%"))
    }
}

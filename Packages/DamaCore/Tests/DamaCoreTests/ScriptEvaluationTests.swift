import Foundation
import XCTest
@testable import DamaCore

final class ScriptEvaluationTests: XCTestCase {
    func testReviewRoundtripPreservesOriginalAndDistinguishesStyleFromLabelCandidate() throws {
        var path = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { path.deleteLastPathComponent() }
        let document = try NormalizedTranscriptCodec.decode(Data(contentsOf: path.appendingPathComponent("fixtures/normalized-transcript.json")))
        let original = try LibraryScript(transcript: document, title: "Synthetic evaluation", recordedAt: nil, dateSource: "fixture", input: ConversionNotes())
        var script = original
        let id = try XCTUnwrap(document.turns.first { $0.kind == .speech }?.id)
        try script.editText(id, text: "synthetic corrected text")
        try script.recordReview(before: original, turnIDs: [id], audioChecked: true, error: .asr,
            sample: .problem, activeSeconds: 12)
        let record = try XCTUnwrap(script.reviewRecords?.first)
        XCTAssertTrue(record.eligibleForTextLabelReview)
        XCTAssertEqual(record.baseRevisionID, original.revisionID)
        XCTAssertEqual(record.turns.first?.afterText, "synthetic corrected text")
        let loaded = try JSONDecoder().decode(LibraryScript.self, from: script.evaluationData().scriptEnvelope())
        XCTAssertEqual(loaded.reviewRecords, script.reviewRecords)
        XCTAssertEqual(try NormalizedTranscriptCodec.encode(loaded.transcript), try NormalizedTranscriptCodec.encode(original.transcript))
        var style = original; try style.editText(id, text: "polished text")
        try style.recordReview(before: original, turnIDs: [id], audioChecked: true, error: .style)
        XCTAssertFalse(style.reviewRecords![0].eligibleForTextLabelReview)
        XCTAssertNil(style.reviewRecords![0].activeSeconds)
        XCTAssertThrowsError(try style.recordReview(before: original, turnIDs: [id], error: .noError))
        XCTAssertThrowsError(try style.recordReview(before: original, turnIDs: [id], activeSeconds: -.infinity))
        XCTAssertThrowsError(try style.recordReview(before: original, turnIDs: ["wrong"]))
        let encoder = JSONEncoder()
        var old = try JSONSerialization.jsonObject(with: encoder.encode(original)) as! [String: Any]
        old.removeValue(forKey: "reviewRecords")
        XCTAssertNil(try JSONDecoder().decode(LibraryScript.self, from: JSONSerialization.data(withJSONObject: old)).reviewRecords)
    }
    func testNormalCostRetainsSubscriptionAndUnknownIsNotFree() throws {
        var cost = MonthlyOperatingCost()
        XCTAssertNil(cost.normalTotalUSD); XCTAssertNil(cost.actualBilledUSD)
        cost.normalSubscriptionUSD = 19; cost.includedCreditUSD = 19; cost.precisionUsageUSD = 13.2
        cost.sonioxUsageUSD = 9.75; cost.otherCostUSD = 0; cost.actualBilledUSD = 0
        XCTAssertEqual(cost.normalTotalUSD, 28.75)
        cost.precisionUsageUSD = 0; XCTAssertEqual(cost.normalTotalUSD, 28.75)
        cost.precisionUsageUSD = 25; XCTAssertEqual(cost.normalTotalUSD, 34.75)
        cost.sonioxUsageUSD = nil; XCTAssertNil(cost.normalTotalUSD)
        cost.precisionUsageUSD = -.infinity; XCTAssertThrowsError(try cost.validate())
    }
}
private extension Data {
    func scriptEnvelope() throws -> Data {
        let object = try JSONSerialization.jsonObject(with: self) as! [String: Any]
        return try JSONSerialization.data(withJSONObject: object["script"]!)
    }
}

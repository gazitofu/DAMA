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
    /// usage-bundle1 가드 이동 (operating-baseline.md:97 새 공식). 이전 단정 28.75·28.75·34.75 → 구 기록 nil · 48.75 · 54.75.
    /// 단위: USD Double 그대로 (배율 없음). 예시 값은 검산용 가정값.
    func testNormalCostRetainsSubscriptionAndUnknownIsNotFree() throws {
        var cost = MonthlyOperatingCost()
        XCTAssertNil(cost.normalTotalUSD); XCTAssertNil(cost.actualBilledUSD)
        cost.normalSubscriptionUSD = 19; cost.includedCreditUSD = 19; cost.precisionUsageUSD = 13.2
        cost.sonioxUsageUSD = 9.75; cost.otherCostUSD = 0; cost.actualBilledUSD = 0
        XCTAssertNil(cost.normalTotalUSD) // 구 기록: AI CLI 구독료 없음 → 미측정 (이전 28.75).
        cost.aiCLISubscriptionUSD = 20; XCTAssertEqual(cost.normalTotalUSD, 48.75) // 29.75 + 19 + max(0, 13.2 − 19).
        cost.precisionUsageUSD = 25; XCTAssertEqual(cost.normalTotalUSD, 54.75) // 29.75 + 19 + 6.
        cost.sonioxUsageUSD = nil; XCTAssertNil(cost.normalTotalUSD)
        cost.precisionUsageUSD = -.infinity; XCTAssertThrowsError(try cost.validate())
    }

    func testMonthlyCostFourCasesAndRetiredItemsAreOptional() throws {
        var cost = MonthlyOperatingCost()
        cost.sonioxUsageUSD = 9.75; cost.aiCLISubscriptionUSD = 20; cost.otherCostUSD = 0
        XCTAssertEqual(cost.normalTotalUSD, 29.75) // 퇴역 3칸 빈칸.
        XCTAssertFalse(cost.retiredPartial)
        cost.normalSubscriptionUSD = 19
        XCTAssertNil(cost.normalTotalUSD) // 퇴역 1칸만 → 미측정.
        XCTAssertTrue(cost.retiredPartial)
        cost.includedCreditUSD = 19
        XCTAssertNil(cost.normalTotalUSD); XCTAssertTrue(cost.retiredPartial) // 2칸.
        cost.precisionUsageUSD = 13.2; XCTAssertEqual(cost.normalTotalUSD, 48.75)
        cost.precisionUsageUSD = 25; XCTAssertEqual(cost.normalTotalUSD, 54.75)
        XCTAssertEqual(cost.normalTotalUSD.map { String(format: "%.2f", $0) }, "54.75")
        cost.aiCLISubscriptionUSD = nil; XCTAssertNil(cost.normalTotalUSD)
        for invalid in [-1, Double.infinity, .nan] {
            var bad = cost; bad.aiCLISubscriptionUSD = invalid
            XCTAssertThrowsError(try bad.validate())
        }
    }

    func testOldCostJSONDecodesAndEvaluationCostGainsOnlyOneKey() throws {
        var cost = MonthlyOperatingCost()
        cost.month = "2026-11"; cost.sonioxUsageUSD = 9.75; cost.otherCostUSD = 0
        let oldBytes = try JSONEncoder().encode(cost)
        let oldKeys = Set((try JSONSerialization.jsonObject(with: oldBytes) as! [String: Any]).keys)
        XCTAssertFalse(oldKeys.contains("aiCLISubscriptionUSD"))
        XCTAssertNil(try JSONDecoder().decode(MonthlyOperatingCost.self, from: oldBytes).aiCLISubscriptionUSD)
        cost.aiCLISubscriptionUSD = 20
        let newKeys = Set((try JSONSerialization.jsonObject(with: JSONEncoder().encode(cost)) as! [String: Any]).keys)
        XCTAssertEqual(newKeys.subtracting(oldKeys), ["aiCLISubscriptionUSD"])
        XCTAssertTrue(oldKeys.isSubset(of: newKeys))
    }
}
private extension Data {
    func scriptEnvelope() throws -> Data {
        let object = try JSONSerialization.jsonObject(with: self) as! [String: Any]
        return try JSONSerialization.data(withJSONObject: object["script"]!)
    }
}

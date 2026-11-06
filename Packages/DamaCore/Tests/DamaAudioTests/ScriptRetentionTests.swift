import DamaCore
import Foundation
import XCTest
@testable import DamaAudio

/// usage-bundle2 AC-04 · AC-08: 결과 보관 규칙(순수 계산). 스펙 §02-2 사례표.
final class ScriptRetentionTests: XCTestCase {
    private struct Item: RetentionListing {
        let id: String
        let createdAt: Date
        let sessionId: String
        let engine: EngineKind
        let hasHumanEdits: Bool
    }
    private typealias Link = ScriptRetention.RunLink
    private let session = "S"

    /// C = 결합(자식 아님), S = Soniox 자식, R = 실행 기록 없음. 숫자가 클수록 최근(createdAt = 숫자 × 100).
    private func item(_ id: String, _ time: Double, human: Bool = false, session: String? = nil) -> Item {
        Item(id: id, createdAt: Date(timeIntervalSince1970: time * 100), sessionId: session ?? self.session,
             engine: id.hasPrefix("S") ? .managedSoniox : .hybridSonioxNemotron, hasHumanEdits: human)
    }
    private func combined(_ id: String, soniox: String?) -> (String, Link) { (id, Link(parentRunID: nil, sonioxRunID: soniox)) }
    private func child(_ id: String, parent: String) -> (String, Link) { (id, Link(parentRunID: parent, sonioxRunID: nil)) }
    private func plan(_ items: [Item], _ links: [(String, Link)], skipIDs: Set<String> = [], skippedSessions: Set<String> = [],
                      pending: ScriptRetention.PendingGeneration? = nil) -> ScriptRetention.Plan {
        ScriptRetention.plan(items, links: Dictionary(uniqueKeysWithValues: links), skipIDs: skipIDs,
                             skippedSessions: skippedSessions, pending: pending)[session] ?? .init()
    }

    // 사례 ① 재사용: C3(S1) · C2(S1) · C1(S1)
    private var reuse: ([Item], [(String, Link)]) {
        ([item("C3", 3), item("C2", 2), item("C1", 1), item("S1", 0.5)],
         [combined("C3", soniox: "S1"), combined("C2", soniox: "S1"), combined("C1", soniox: "S1"), child("S1", parent: "C1")])
    }
    // 사례 ② 새 Soniox: C3(S3) · C2(S2) · C1(S1)
    private var fresh: ([Item], [(String, Link)]) {
        ([item("C3", 3), item("S3", 2.9), item("C2", 2), item("S2", 1.9), item("C1", 1), item("S1", 0.9)],
         [combined("C3", soniox: "S3"), child("S3", parent: "C3"), combined("C2", soniox: "S2"), child("S2", parent: "C2"),
          combined("C1", soniox: "S1"), child("S1", parent: "C1")])
    }
    // 사례 ⑤ 사람 수정: C3 · C2 · C1(C1만 사람 수정)
    private var human: [Item] { [item("C3", 3), item("C2", 2), item("C1", 1, human: true)] }

    func testCase1ReusedSonioxBelongsToEveryGeneration() {
        let (items, links) = reuse
        XCTAssertEqual(plan(items, links), .init(keep: ["C3", "C2", "S1"], remove: ["C1"]))
    }
    func testCase2NewSonioxPerGeneration() {
        let (items, links) = fresh
        XCTAssertEqual(plan(items, links), .init(keep: ["C3", "S3", "C2", "S2"], remove: ["C1", "S1"]))
    }
    func testCase3ChildWithoutParentResultIsItsOwnGeneration() {
        let items = [item("S3", 3), item("C2", 2), item("S2", 1.9), item("C1", 1), item("S1", 0.9)]
        let links = [child("S3", parent: "P3"), combined("C2", soniox: "S2"), child("S2", parent: "C2"),
                     combined("C1", soniox: "S1"), child("S1", parent: "C1")]
        XCTAssertEqual(plan(items, links), .init(keep: ["S3", "C2", "S2"], remove: ["C1", "S1"]))
    }
    func testCase4ResultWithoutRunRecordIsItsOwnGeneration() {
        let items = [item("R", 2), item("C1", 1), item("S1", 0.9)]
        XCTAssertEqual(plan(items, [combined("C1", soniox: "S1"), child("S1", parent: "C1")]),
                       .init(keep: ["R", "C1", "S1"], remove: []))
    }
    func testCase5HumanEditedResultIsKept() {
        XCTAssertEqual(plan(human, [combined("C3", soniox: nil), combined("C2", soniox: nil), combined("C1", soniox: nil)]),
                       .init(keep: ["C3", "C2", "C1"], remove: []))
    }
    func testCase6SkippedRecordingIsUntouched() {
        let (items, links) = fresh
        XCTAssertEqual(plan(items, links, skippedSessions: [session]).remove, [])
        XCTAssertEqual(plan(items, links, skippedSessions: ["다른 녹음"]).remove, ["C1", "S1"])
    }
    func testCase7EqualGenerationTimeOrdersByRepresentativeID() {
        let items = [item("A", 1), item("B", 1), item("C", 1)]
        let links = [combined("A", soniox: nil), combined("B", soniox: nil), combined("C", soniox: nil)]
        XCTAssertEqual(plan(items, links).remove, ["C"])
    }
    func testCase8SkippedResultIsNeverRemoved() {
        let (items, links) = fresh
        XCTAssertEqual(plan(items, links, skipIDs: ["C1"]), .init(keep: ["C3", "S3", "C2", "S2", "C1"], remove: ["S1"]))
    }
    func testRecordingsArePlannedSeparately() {
        let (items, links) = fresh
        let other = [item("X3", 3, session: "T"), item("X2", 2, session: "T"), item("X1", 1, session: "T")]
        let plans = ScriptRetention.plan(items + other, links: Dictionary(uniqueKeysWithValues: links))
        XCTAssertEqual(plans["T"]?.remove, ["X1"])
        XCTAssertEqual(ScriptRetention.removals(plans), ["C1", "S1", "X1"])
    }

    /// AC-08: 재전사 확인창 N = 이 실행(+ 재사용 Soniox)을 새 세대로 놓은 정리 수.
    func testPendingGenerationCountsForConfirmation() {
        func pending(_ members: Set<String>) -> ScriptRetention.PendingGeneration {
            .init(sessionId: session, representativeID: "NEW", createdAt: Date(timeIntervalSince1970: 1_000), memberIDs: members)
        }
        let (reuseItems, reuseLinks) = reuse
        XCTAssertEqual(plan(reuseItems, reuseLinks, pending: pending(["NEW", "S1"])).remove, ["C2", "C1"])
        let (freshItems, freshLinks) = fresh
        XCTAssertEqual(plan(freshItems, freshLinks, pending: pending(["NEW"])).remove, ["C2", "S2", "C1", "S1"])
        XCTAssertEqual(plan(human, [], pending: pending(["NEW"])).remove, ["C2"])
        XCTAssertEqual(plan([item("C1", 1), item("S1", 0.9)], [combined("C1", soniox: "S1"), child("S1", parent: "C1")],
                            pending: pending(["NEW"])).remove, [])
        // 결과가 하나도 없는 녹음의 첫 실행.
        XCTAssertEqual(ScriptRetention.plan([Item](), links: [:], pending: pending(["NEW"]))[session], .init())
    }
}

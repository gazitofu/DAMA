import DamaCore
import Foundation

/// 결과 보관 판정에 필요한 목록 필드 (usage-bundle2).
public protocol RetentionListing: ScriptListing {
    var hasHumanEdits: Bool { get }
}
extension LibraryScriptSummary: RetentionListing {}
extension LibraryScriptFile: RetentionListing {
    public var hasHumanEdits: Bool { script.hasHumanEdits }
}

/// usage-bundle2 결과 보관 (library-script.md «결과 보관»). 파일을 읽거나 쓰지 않는 순수 계산이다.
/// 재전사 확인창의 정리 수와 실제 정리가 이 함수 하나를 쓴다.
public enum ScriptRetention {
    /// 녹음마다 남기는 세대 수. 사용자 결정값(T2a-1 «최신 성공본 + 직전 성공본»).
    public static let keptGenerations = 2

    /// 스크립트 id(= Run id)의 실행 기록 연결. 실행 기록이 없는 결과는 목록에 없다.
    public struct RunLink: Sendable, Equatable {
        public let parentRunID: String?
        public let sonioxRunID: String?
        public init(parentRunID: String?, sonioxRunID: String?) {
            self.parentRunID = parentRunID; self.sonioxRunID = sonioxRunID
        }
    }

    /// 확인창용 가상 세대: 아직 결과가 없는 이 실행. 구성 = 이 실행 + 재사용할 Soniox 결과.
    public struct PendingGeneration: Sendable, Equatable {
        public let sessionId: String
        public let representativeID: String
        public let createdAt: Date
        public let memberIDs: Set<String>
        public init(sessionId: String, representativeID: String, createdAt: Date, memberIDs: Set<String>) {
            self.sessionId = sessionId; self.representativeID = representativeID
            self.createdAt = createdAt; self.memberIDs = memberIDs
        }
    }

    public struct Plan: Sendable, Equatable {
        public var keep: Set<String>
        public var remove: Set<String>
        public init(keep: Set<String> = [], remove: Set<String> = []) { self.keep = keep; self.remove = remove }
    }

    private struct Generation {
        let time: Date
        let representative: String
        let members: Set<String>
    }

    /// 녹음(sessionId)별 남김·정리 집합. `skipIDs` 결과와 `skippedSessions` 녹음은 정리하지 않는다.
    public static func plan<T: RetentionListing>(_ files: [T], links: [String: RunLink],
                                                skipIDs: Set<String> = [], skippedSessions: Set<String> = [],
                                                pending: PendingGeneration? = nil,
                                                kept: Int = keptGenerations) -> [String: Plan] {
        var plans: [String: Plan] = [:]
        let sessions = Set(files.map(\.sessionId)).union(pending.map { [$0.sessionId] } ?? [])
        for session in sessions {
            let group = files.filter { $0.sessionId == session }
            let present = Set(group.map(\.id))
            if skippedSessions.contains(session) { plans[session] = Plan(keep: present); continue }
            func isChild(_ id: String) -> Bool { links[id]?.parentRunID != nil }
            var generations: [Generation] = [], referenced: Set<String> = []
            for file in group where !isChild(file.id) {
                var members: Set<String> = [file.id]
                if let soniox = links[file.id]?.sonioxRunID, present.contains(soniox) {
                    members.insert(soniox); referenced.insert(soniox)
                }
                generations.append(Generation(time: file.createdAt, representative: file.id, members: members))
            }
            if let pending, pending.sessionId == session {
                referenced.formUnion(pending.memberIDs.intersection(present))
                generations.append(Generation(time: pending.createdAt, representative: pending.representativeID,
                                              members: pending.memberIDs))
            }
            // 부모 결과가 없는 자식 결과는 혼자 한 세대다.
            for file in group where isChild(file.id) && !referenced.contains(file.id) {
                generations.append(Generation(time: file.createdAt, representative: file.id, members: [file.id]))
            }
            generations.sort { $0.time != $1.time ? $0.time > $1.time : $0.representative < $1.representative }
            var keep = generations.prefix(max(0, kept)).reduce(into: Set<String>()) { $0.formUnion($1.members) }
            keep.formUnion(group.filter(\.hasHumanEdits).map(\.id))
            keep.formUnion(skipIDs)
            keep.formIntersection(present)
            plans[session] = Plan(keep: keep, remove: present.subtracting(keep))
        }
        return plans
    }

    /// 모든 녹음의 정리 대상 id.
    public static func removals(_ plans: [String: Plan]) -> Set<String> {
        plans.values.reduce(into: Set<String>()) { $0.formUnion($1.remove) }
    }
}

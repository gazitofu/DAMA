import CryptoKit
import Foundation

/// usage-bundle1 교정 실패 기록 1건. 원문·stderr 내용·프롬프트는 담지 않는다.
public struct CorrectionFailureRecord: Codable, Sendable, Equatable {
    /// 청크 번호(저장 0부터, 표시 1부터)와 전체 청크 수.
    public let chunkIndex: Int
    public let totalChunks: Int
    public let kind: CorrectionFailureKind
    /// 없으면 null (시간 초과·실행 불가·취소).
    public let exitCode: Int32?
    /// 청크 시작부터 실패 판정까지 경과 ms.
    public let elapsedMs: Int64
    public let stderrBytes: Int
    public let recordedAt: Date
    public init(chunkIndex: Int, totalChunks: Int, kind: CorrectionFailureKind, exitCode: Int32?,
                elapsedMs: Int64, stderrBytes: Int, recordedAt: Date = Date()) {
        self.chunkIndex = chunkIndex; self.totalChunks = totalChunks; self.kind = kind; self.exitCode = exitCode
        self.elapsedMs = elapsedMs; self.stderrBytes = stderrBytes; self.recordedAt = recordedAt
    }
}

/// 끝난 청크 하나의 검증된 결과(수정·이름·이름 근거).
public struct CorrectionChunkResult: Codable, Sendable, Equatable {
    public let chunkIndex: Int
    public let edits: [CorrectionEdit]
    public let names: [String: String]
    public let evidence: [String: String]
    public init(chunkIndex: Int, edits: [CorrectionEdit], names: [String: String], evidence: [String: String]) {
        self.chunkIndex = chunkIndex; self.edits = edits; self.names = names; self.evidence = evidence
    }
}

/// usage-bundle1 교정 시도 기록 (`<내부 root>/CorrectionAttempts/<scriptID>.json`, 스크립트당 1개).
/// 진행 중이거나 끝나지 않은 교정의 진행분을 스크립트 파일 대신 여기에 둔다(스크립트 사본을 청크마다 만들지 않는다).
public struct CorrectionAttempt: Codable, Sendable, Equatable {
    public static let currentFormatVersion = 1
    /// 실패 기록 보관 상한(신규 후보값).
    public static let failureLimit = 20
    public var formatVersion = Self.currentFormatVersion
    public let scriptID: String
    public let attemptID: String
    public let engine: String
    /// 교정 입력 스냅숏(확인창에서 확인한 참고 발췌 포함). 이어서 교정은 이 입력을 다시 만들지 않고 쓴다.
    public let input: ConversionNotes
    public let planSHA256: String
    public let chunkSHA256s: [String]
    public private(set) var results: [CorrectionChunkResult]
    public private(set) var failures: [CorrectionFailureRecord]
    public let startedAt: Date

    public init(scriptID: String, engine: String, input: ConversionNotes, planSHA256: String, chunkSHA256s: [String],
                attemptID: String = UUID().uuidString, startedAt: Date = Date()) {
        self.scriptID = scriptID; self.attemptID = attemptID; self.engine = engine; self.input = input
        self.planSHA256 = planSHA256; self.chunkSHA256s = chunkSHA256s; results = []; failures = []; self.startedAt = startedAt
    }

    public var totalChunks: Int { chunkSHA256s.count }
    public var completedChunks: Int { results.count }
    /// 아직 끝나지 않은 청크 번호(오름차순).
    public var remainingChunks: [Int] {
        let done = Set(results.map(\.chunkIndex))
        return (0..<totalChunks).filter { !done.contains($0) }
    }
    public var lastFailure: CorrectionFailureRecord? { failures.last }

    public mutating func record(_ result: CorrectionChunkResult) {
        guard (0..<totalChunks).contains(result.chunkIndex), !results.contains(where: { $0.chunkIndex == result.chunkIndex }) else { return }
        results.append(result); results.sort { $0.chunkIndex < $1.chunkIndex }
    }
    public mutating func record(_ failure: CorrectionFailureRecord) {
        failures.append(failure)
        if failures.count > Self.failureLimit { failures.removeFirst(failures.count - Self.failureLimit) }
    }

    /// 기록된 모든 청크 결과를 청크 순서로 합친다. 청크 사이 이름 충돌은 그 화자의 자동 이름을 뺀다(현행 규칙).
    public func merged() -> (edits: [CorrectionEdit], names: [String: String], evidence: [String: String]) {
        var edits: [CorrectionEdit] = [], names: [String: String] = [:], evidence: [String: String] = [:], conflicts = Set<String>()
        for result in results.sorted(by: { $0.chunkIndex < $1.chunkIndex }) {
            edits += result.edits
            for (id, name) in result.names {
                if let previous = names[id], previous != name { conflicts.insert(id) }
                names[id] = name
                evidence[id] = result.evidence[id]
            }
        }
        for id in conflicts { names.removeValue(forKey: id); evidence.removeValue(forKey: id) }
        return (edits, names, evidence)
    }
}

/// 교정 청크 계획. AI 교정 겹(correction·showsOriginal)을 뺀 현재 스크립트로 만든다. 사람 수정·삭제가 바뀌면 해시가 달라진다.
public enum CorrectionPlan {
    public static func chunks(for script: LibraryScript) throws -> [CorrectionChunk] {
        var source = script; source.correction = nil; source.showsOriginal = nil
        return try ContextCorrection.chunks(source)
    }
    /// `JSONEncoder` `.sortedKeys`로 인코드한 청크 목록 전체의 SHA256 (소문자 16진).
    public static func sha256(_ chunks: [CorrectionChunk]) throws -> String { hex(try encoder.encode(chunks)) }
    public static func chunkSHA256s(_ chunks: [CorrectionChunk]) throws -> [String] { try chunks.map { hex(try encoder.encode($0)) } }
    private static var encoder: JSONEncoder { let value = JSONEncoder(); value.outputFormatting = [.sortedKeys]; return value }
    private static func hex(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}

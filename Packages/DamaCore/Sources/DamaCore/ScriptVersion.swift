import Foundation

public struct ScriptVersion: Codable, Sendable, Equatable, Identifiable {
    public var id: String { revisionID }
    public let revisionID: String
    public let sha256: String
    /// 0 = before the first indexed correction; 1... = completed AI results.
    public let number: Int
    public let correctionID: String
    public let createdAt: Date
    public var title: String { number == 0 ? "AI 보정 전" : "AI 보정 \(number)" }
    public init(revisionID: String, sha256: String, number: Int, correctionID: String, createdAt: Date) {
        self.revisionID = revisionID; self.sha256 = sha256; self.number = number
        self.correctionID = correctionID; self.createdAt = createdAt
    }
    public func validate() throws {
        guard UUID(uuidString: revisionID) != nil, UUID(uuidString: correctionID) != nil,
              sha256.count == 64, sha256.allSatisfy(\.isHexDigit), number >= 0 else { throw LibraryFailure.invalidScript }
    }
}

import Foundation

/// Local display diagnostics. Never includes source bytes, decoder details or credentials.
public struct FileScanIssue: Sendable, Identifiable {
    public enum Reason: Sendable {
        case unreadable, duplicateIdentity, unsafePath, changedFile
        public var message: String {
            switch self {
            case .unreadable: "파일 형식·내용·접근 권한을 확인해 주세요."
            case .duplicateIdentity: "같은 ID의 파일이 여러 개라 모두 목록에서 제외했습니다."
            case .unsafePath: "심볼릭 링크 또는 저장 위치를 확인해 주세요."
            case .changedFile: "원본 파일이 변경되어 확인이 필요합니다."
            }
        }
    }
    public var id: String { url.standardizedFileURL.path }
    public let url: URL
    public let reason: Reason
    public let sessionID: String?
    public let itemID: String?
    public init(url: URL, reason: Reason = .unreadable, sessionID: String? = nil, itemID: String? = nil) {
        self.url = url; self.reason = reason; self.sessionID = sessionID; self.itemID = itemID
    }
}

public struct FileScanResult<Item: Sendable>: Sendable {
    public var items: [Item]
    public var issues: [FileScanIssue]
    public init(items: [Item] = [], issues: [FileScanIssue] = []) {
        self.items = items; self.issues = issues
    }
}

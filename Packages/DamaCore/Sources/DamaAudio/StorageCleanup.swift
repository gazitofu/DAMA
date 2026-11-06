import CryptoKit
import DamaCore
import Foundation

/// usage-bundle2 저장 공간 정리 (설정 · 기존분 1회, library-script.md «결과 보관»).
/// 이력 파일을 다루는 코드는 모두 `FolderLibraryStore` actor 안에 둔다. 사용자 파일(Scripts·Speeches)은 여기서 쓰지 않는다.
public struct RevisionCleanupItem: Sendable, Equatable {
    public enum Layout: String, Sendable { case legacy, current }
    public let url: URL
    public let scriptID: String
    public let revisionID: String
    public let bytes: Int64
    public let layout: Layout
}

public struct RevisionCleanupPlan: Sendable, Equatable {
    /// 현재 Scripts에 없는 스크립트의 이력(구·새 배치).
    public var deletions: [RevisionCleanupItem] = []
    /// 나머지 구 배치 이력(새 배치로 압축 이전).
    public var migrations: [RevisionCleanupItem] = []
    /// 현재 Scripts에 없는 스크립트의 교정 시도 기록(스크립트 ID).
    public var attempts: [String] = []
    /// Scripts 조회에 파일별 문제가 있어 지울 이력·시도 기록을 0으로 두었다(문구 15).
    public var skippedOrphans = false
    /// 해독하지 못해 소속을 모르는 구 배치 파일. 지우지도 옮기지도 않는다(모르면 지우지 않는다).
    public var unreadable: [URL] = []
    public var deletionBytes: Int64 { deletions.reduce(0) { $0 + $1.bytes } }
    public var migrationBytes: Int64 { migrations.reduce(0) { $0 + $1.bytes } }
}

public struct RevisionCleanupResult: Sendable, Equatable {
    public var deleted = 0
    public var migrated = 0
    public var attemptsDeleted = 0
    public var failed = 0
}

extension FolderLibraryStore {
    static let cleanupLogName = "storage-cleanup-log.jsonl"

    /// 설정을 열 때의 «내부 수정 이력 {크기}»: `LibraryRevisions` 아래 일반 파일 크기 합(바이트, 해독 없음).
    public func revisionStorageBytes() -> Int64 {
        guard let walker = FileManager.default.enumerator(at: revisionFolder, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        while let url = walker.nextObject() as? URL {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]), values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    /// 저장 공간 정리 확인 단계(쓰기 없음): Scripts를 다시 읽고(요약 캐시도 쓰지 않음) 그 결과로 이력 정리를 계획한다.
    /// Scripts 조회에 파일별 문제가 있으면 지울 이력·시도 기록은 0이다.
    public func planStorageCleanup(scriptsFolder: URL) async throws -> (scan: FileScanResult<LibraryScriptSummary>, plan: RevisionCleanupPlan) {
        let scan = try scanScriptSummaries(in: scriptsFolder, writeCache: false)
        let plan = try await planRevisionCleanup(presentScriptIDs: Set(scan.items.map(\.id)), scanHasIssues: !scan.issues.isEmpty)
        return (scan, plan)
    }

    /// 확인 단계(쓰기 없음). `presentScriptIDs` = 현재 Scripts 조회의 스크립트 ID, `scanHasIssues` = 파일별 조회 문제.
    public func planRevisionCleanup(presentScriptIDs: Set<String>, scanHasIssues: Bool) async throws -> RevisionCleanupPlan {
        var plan = RevisionCleanupPlan(skippedOrphans: scanHasIssues)
        let manager = FileManager.default
        if manager.fileExists(atPath: revisionFolder.path) {
            try safe(revisionFolder)
            let entries = try manager.contentsOfDirectory(at: revisionFolder, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                                                          options: [.skipsHiddenFiles])
            for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                await Task.yield()
                let values = try entry.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                if values.isDirectory == true {
                    // 새 배치 폴더: 이름 = 스크립트 ID. 현재 Scripts에 없으면 그 안의 이력이 «지울 이력».
                    let scriptID = entry.lastPathComponent
                    guard !presentScriptIDs.contains(scriptID), !scanHasIssues, InternalStoragePaths.isSafeScriptID(scriptID) else { continue }
                    for file in try manager.contentsOfDirectory(at: entry, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])
                        where file.lastPathComponent.hasSuffix(RevisionCodec.compressedSuffix) {
                        let revisionID = String(file.lastPathComponent.dropLast(RevisionCodec.compressedSuffix.count))
                        plan.deletions.append(RevisionCleanupItem(url: file, scriptID: scriptID, revisionID: revisionID,
                            bytes: Int64(try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0), layout: .current))
                    }
                    continue
                }
                let name = entry.lastPathComponent
                guard name.hasSuffix(RevisionCodec.legacySuffix) else { continue }
                let revisionID = String(name.dropLast(RevisionCodec.legacySuffix.count))
                guard UUID(uuidString: revisionID) != nil else { continue }
                // 구 배치: 해독해 소속 스크립트 ID를 얻는다.
                let scriptID: String
                do {
                    let script = try JSONDecoder().decode(LibraryScript.self, from: Data(contentsOf: entry))
                    guard script.revisionID == revisionID, InternalStoragePaths.isSafeScriptID(script.id) else { throw LibraryFailure.invalidScript }
                    scriptID = script.id
                } catch { plan.unreadable.append(entry); continue }
                let item = RevisionCleanupItem(url: entry, scriptID: scriptID, revisionID: revisionID,
                                               bytes: Int64(values.fileSize ?? 0), layout: .legacy)
                if presentScriptIDs.contains(scriptID) { plan.migrations.append(item) }
                else if !scanHasIssues { plan.deletions.append(item) }
            }
        }
        if !scanHasIssues {
            let folder = root.appendingPathComponent(InternalStoragePaths.correctionAttemptsFolder, isDirectory: true)
            if manager.fileExists(atPath: folder.path) {
                for file in try manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                    where file.pathExtension == "json" {
                    let scriptID = file.deletingPathExtension().lastPathComponent
                    if InternalStoragePaths.isSafeScriptID(scriptID), !presentScriptIDs.contains(scriptID) { plan.attempts.append(scriptID) }
                }
                plan.attempts.sort()
            }
        }
        return plan
    }

    /// 실행 2–4단계: 지울 이력 → 압축 이전 → 지울 시도 기록. `removedScriptIDs` = 1단계(보관 정리)에서 휴지통으로 옮긴 스크립트.
    /// 그 스크립트의 구 배치 이력은 압축하지 않고 지운다. 항목마다 기록 파일에 처리 즉시 한 줄을 덧붙인다.
    public func runRevisionCleanup(_ plan: RevisionCleanupPlan, removedScriptIDs: Set<String>,
                                   progress: @Sendable (Int) -> Void) async -> RevisionCleanupResult {
        var result = RevisionCleanupResult(), done = 0
        func step() { done += 1; progress(done) }
        let deletions = plan.deletions + plan.migrations.filter { removedScriptIDs.contains($0.scriptID) }
        for item in deletions {
            await Task.yield()
            do {
                try safe(item.url)
                if FileManager.default.fileExists(atPath: item.url.path) { try FileManager.default.removeItem(at: item.url) }
                result.deleted += 1; appendCleanupLog("deleteRevision", item, "ok")
            } catch { result.failed += 1; appendCleanupLog("deleteRevision", item, "failed") }
            step()
        }
        // 비워진 새 배치 폴더는 지운다.
        for scriptID in Set(plan.deletions.filter { $0.layout == .current }.map(\.scriptID)) {
            let folder = revisionFolder.appendingPathComponent(scriptID, isDirectory: true)
            if let left = try? FileManager.default.contentsOfDirectory(atPath: folder.path), left.isEmpty { try? FileManager.default.removeItem(at: folder) }
        }
        for item in plan.migrations where !removedScriptIDs.contains(item.scriptID) {
            await Task.yield()
            if migrate(item) { result.migrated += 1; appendCleanupLog("migrateRevision", item, "ok") }
            else { result.failed += 1; appendCleanupLog("migrateRevision", item, "failed") }
            step()
        }
        for scriptID in plan.attempts {
            await Task.yield()
            let item = RevisionCleanupItem(url: root, scriptID: scriptID, revisionID: "", bytes: 0, layout: .legacy)
            do {
                let url = try InternalStoragePaths.correctionAttemptURL(root: root, scriptID: scriptID)
                try safe(url)
                if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
                result.attemptsDeleted += 1; appendCleanupLog("deleteAttempt", item, "ok")
            } catch { result.failed += 1; appendCleanupLog("deleteAttempt", item, "failed") }
            step()
        }
        result.failed += plan.unreadable.count
        return result
    }

    /// 구 배치 1파일 이전: 읽기 → 압축 → 새 배치 쓰기 → 다시 읽어 풀기 → 원본 바이트와 같을 때만 원본 삭제.
    /// 새 파일이 이미 있으면(이전 정리 중단) 풀어서 대조해 같으면 원본만 지우고, 다르면 새 파일을 지우고 다시 압축한다.
    private func migrate(_ item: RevisionCleanupItem) -> Bool {
        do {
            try safe(item.url)
            let original = try Data(contentsOf: item.url)
            let target = try revisionURL(scriptID: item.scriptID, revisionID: item.revisionID)
            if FileManager.default.fileExists(atPath: target.path) {
                if (try? RevisionCodec.inflate(Data(contentsOf: target))) == original {
                    try cleanupHook?(item.url)
                    try FileManager.default.removeItem(at: item.url); return true
                }
                try FileManager.default.removeItem(at: target)
            }
            try writeNewRevision(try cleanupCompressor(original), to: target)
            guard (try? RevisionCodec.inflate(Data(contentsOf: target))) == original else {
                try? FileManager.default.removeItem(at: target); return false
            }
            try cleanupHook?(item.url)
            try FileManager.default.removeItem(at: item.url)
            return true
        } catch { return false }
    }

    func appendCleanupLog(_ kind: String, _ item: RevisionCleanupItem, _ outcome: String) {
        let formatter = ISO8601DateFormatter()
        let line: [String: Any] = ["at": formatter.string(from: Date()), "kind": kind, "scriptID": item.scriptID,
                                   "revisionID": item.revisionID, "bytes": item.bytes, "result": outcome]
        guard var data = try? JSONSerialization.data(withJSONObject: line, options: [.sortedKeys]) else { return }
        data.append(0x0A)
        let url = root.appendingPathComponent(Self.cleanupLogName)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd(); try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url, options: .withoutOverwriting)
        }
    }
}

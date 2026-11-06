import DamaCore
import Foundation
import XCTest
@testable import DamaAudio

/// usage-bundle2 AC-11 · AC-13: 실데이터 읽기 전용 모의. 환경변수가 있을 때만 돈다(메인 실행).
/// DAMA_REAL_ROOT = 내부 저장소, DAMA_REAL_SCRIPTS = Scripts 폴더, DAMA_REAL_OUT = 집계 JSON 경로(개수·크기·ID 앞 8자만).
/// 실데이터에 쓰지 않는다: 요약 캐시는 임시 root에 쓰고, 실제 root에는 쓰기 없는 함수만 부른다. 전후 매니페스트(경로·크기·mtime)를 대조한다.
final class RealDataProbeTests: XCTestCase {
    private struct Entry: Equatable { let size: Int64; let modified: Date }
    private func manifest(_ folder: URL) -> [String: Entry] {
        var result: [String: Entry] = [:]
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys)
        while let url = walker?.nextObject() as? URL {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            result[url.path] = Entry(size: Int64(values.fileSize ?? 0), modified: values.contentModificationDate ?? .distantPast)
        }
        return result
    }

    func testRealDataRetentionAndCleanupPlanAreReadOnly() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let rootPath = env["DAMA_REAL_ROOT"], let scriptsPath = env["DAMA_REAL_SCRIPTS"], let outPath = env["DAMA_REAL_OUT"] else {
            throw XCTSkip("실데이터 모의는 DAMA_REAL_ROOT · DAMA_REAL_SCRIPTS · DAMA_REAL_OUT이 있을 때만 메인이 돌린다.")
        }
        let root = URL(fileURLWithPath: rootPath), scripts = URL(fileURLWithPath: scriptsPath)
        let beforeRoot = manifest(root), beforeScripts = manifest(scripts)
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }

        // 1. 요약(요약 캐시는 임시 root에만 쓴다).
        let scan = try await FolderLibraryStore(root: temporary).scanScriptSummaries(in: scripts)
        let summaries = scan.items
        // 2. 실행 연결(state.json 직독).
        var links: [String: ScriptRetention.RunLink] = [:]
        let sessions = root.appendingPathComponent("Sessions")
        for session in (try? FileManager.default.contentsOfDirectory(at: sessions, includingPropertiesForKeys: nil)) ?? [] {
            for run in (try? FileManager.default.contentsOfDirectory(at: session.appendingPathComponent("runs"), includingPropertiesForKeys: nil)) ?? [] {
                guard let data = try? Data(contentsOf: run.appendingPathComponent("state.json")),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let id = object["id"] as? String else { continue }
                links[id] = .init(parentRunID: object["parentRunID"] as? String, sonioxRunID: object["sonioxRunID"] as? String)
            }
        }
        // 3. 대표 결과: 구 규칙(엔진 등급 → createdAt → id) vs 새 규칙.
        func oldPrimary(_ files: [LibraryScriptSummary]) -> LibraryScriptSummary? {
            files.max { l, r in
                let pl = [EngineKind.hybridSonioxPyannote, .hybridSonioxNemotron].contains(l.engine) ? 1 : 0
                let pr = [EngineKind.hybridSonioxPyannote, .hybridSonioxNemotron].contains(r.engine) ? 1 : 0
                if pl != pr { return pl < pr }
                if l.createdAt != r.createdAt { return l.createdAt < r.createdAt }
                return l.id > r.id
            }
        }
        let bySession = Dictionary(grouping: summaries, by: \.sessionId)
        let changed = bySession.values.filter { oldPrimary($0)?.id != ScriptResultPresentation.primaryFile(in: $0)?.id }
        // 4. 보관 규칙(2세대 · 대조 1세대).
        func sizeOf(_ ids: Set<String>) -> Int64 {
            summaries.filter { ids.contains($0.id) }.reduce(0) { $0 + Int64((try? $1.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        }
        let keep2 = ScriptRetention.removals(ScriptRetention.plan(summaries, links: links))
        let keep1 = ScriptRetention.removals(ScriptRetention.plan(summaries, links: links, kept: 1))
        // 5. 저장 공간 정리 확인 단계(실제 root, 쓰기 없음).
        let real = FolderLibraryStore(root: root)
        let plan = try await real.planRevisionCleanup(presentScriptIDs: Set(summaries.map(\.id)), scanHasIssues: !scan.issues.isEmpty)
        let storageBytes = await real.revisionStorageBytes()
        // 6. AI 버전 readVersion (AC-13; 실제 root에서 쓰기 없음).
        var versionsOK = 0, versionsFailed = 0
        for file in try await real.scripts(in: scripts) {
            for version in file.script.versions ?? [] {
                do { _ = try await real.readVersion(version, for: file); versionsOK += 1 } catch { versionsFailed += 1 }
            }
        }
        let afterRoot = manifest(root), afterScripts = manifest(scripts)
        let out: [String: Any] = [
            "measuredAt": ISO8601DateFormatter().string(from: Date()),
            "scripts": summaries.count, "scanIssues": scan.issues.count, "sessions": bySession.count, "runLinks": links.count,
            "primaryChanged": changed.count, "primaryChangedSessions": changed.compactMap { $0.first.map { String($0.sessionId.prefix(8)) } }.sorted(),
            "humanEdited": summaries.filter(\.hasHumanEdits).count,
            "retainRemove2": keep2.count, "retainRemove2Bytes": sizeOf(keep2),
            "retainRemove1": keep1.count, "retainRemove1Bytes": sizeOf(keep1), "retainRemove1IDs": keep1.map { String($0.prefix(8)) }.sorted(),
            "deletions": plan.deletions.count, "deletionBytes": plan.deletionBytes,
            "deletionScripts": Set(plan.deletions.map(\.scriptID)).count,
            "migrations": plan.migrations.count, "migrationBytes": plan.migrationBytes,
            "attempts": plan.attempts.count, "unreadable": plan.unreadable.count, "skippedOrphans": plan.skippedOrphans,
            "revisionStorageBytes": storageBytes,
            "versionsOK": versionsOK, "versionsFailed": versionsFailed,
            "rootFilesBefore": beforeRoot.count, "rootManifestUnchanged": beforeRoot == afterRoot,
            "scriptFilesBefore": beforeScripts.count, "scriptsManifestUnchanged": beforeScripts == afterScripts,
        ]
        try JSONSerialization.data(withJSONObject: out, options: [.sortedKeys, .prettyPrinted]).write(to: URL(fileURLWithPath: outPath))
        XCTAssertEqual(beforeRoot, afterRoot)
        XCTAssertEqual(beforeScripts, afterScripts)
    }
}

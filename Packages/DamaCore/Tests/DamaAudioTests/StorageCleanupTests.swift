import CryptoKit
import DamaCore
import Foundation
import os
import XCTest
@testable import DamaAudio

/// usage-bundle2 AC-09: 저장 공간 정리 엔진(합성).
final class StorageCleanupTests: XCTestCase {
    private struct Fixture {
        let base: URL, folder: URL, root: URL
        let store: FolderLibraryStore
        let a: LibraryScriptFile, b: LibraryScriptFile
        let cID: String, dID: String
        let sessions: URL
    }
    private func sha(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private func manifest(_ folder: URL) -> [String: String] {
        var result: [String: String] = [:]
        let base = folder.standardizedFileURL.resolvingSymlinksInPath().path
        let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey])
        while let url = walker?.nextObject() as? URL {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true, let data = try? Data(contentsOf: url) else { continue }
            result[String(url.standardizedFileURL.resolvingSymlinksInPath().path.dropFirst(base.count))] = sha(data)
        }
        return result
    }
    private func legacy(_ root: URL) -> [URL] {
        let folder = root.appendingPathComponent("LibraryRevisions")
        return ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasSuffix(".dama.json") }
    }
    /// 새 배치 이력을 구 배치로 되돌린다(이 유닛 전 저장분과 같은 모양).
    /// `only`가 있으면 그 revisionID만 옮기고 나머지는 새 배치에 남긴다.
    private func toLegacy(_ root: URL, scriptID: String, only: Set<String>? = nil) throws {
        let folder = root.appendingPathComponent("LibraryRevisions/\(scriptID)")
        for file in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
            let revisionID = String(file.lastPathComponent.dropLast(".dama.json.deflate".count))
            guard only?.contains(revisionID) ?? true else { continue }
            try RevisionCodec.inflate(Data(contentsOf: file)).write(to: root.appendingPathComponent("LibraryRevisions/\(revisionID).dama.json"))
            try FileManager.default.removeItem(at: file)
        }
        if (try FileManager.default.contentsOfDirectory(atPath: folder.path)).isEmpty { try FileManager.default.removeItem(at: folder) }
    }

    /// 현재 스크립트 A(구 배치 3 = 만들기 · AI 보정 전 snapshot · 보정 저장, 새 배치 1 = AI 보정 1 snapshot) · B(구 배치 2), 서로 다른 녹음 각 1세대.
    /// 없는 스크립트 C(구 배치 2) · D(새 배치 1). 시도 기록 A · C.
    private func fixture() async throws -> Fixture {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = base.appendingPathComponent("Scripts"), root = base.appendingPathComponent("internal")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: base) }
        var repo = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { repo.deleteLastPathComponent() }
        let model = try JSONDecoder().decode(TranscriptDocument.self,
            from: Data(contentsOf: repo.appendingPathComponent("fixtures/normalized-transcript.json")))
        let store = FolderLibraryStore(root: root)
        func make(_ name: String, session: String) async throws -> LibraryScriptFile {
            var transcript = model
            transcript.runId = UUID().uuidString; transcript.revision.sourceRunId = transcript.runId; transcript.sessionId = session
            let script = try LibraryScript(transcript: transcript, title: "기밀제목 \(name)", recordedAt: nil, dateSource: "합성", input: ConversionNotes())
            return try await store.saveScript(script, to: folder.appendingPathComponent(name + ".dama.json"), expectedHash: nil)
        }
        let a = try await make("a", session: "S-A")                           // 이력 1 (만들기)
        var correction = ScriptCorrection(input: a.script.input, engine: "synthetic", state: .completed); correction.completedAt = Date()
        let aFinal = try await store.saveCorrection(correction, for: a)          // + snapshot 2 + 보정 저장 1
        let versions = try XCTUnwrap(aFinal.script.versions)
        XCTAssertEqual(versions.count, 2)
        try toLegacy(root, scriptID: aFinal.id, only: [a.script.revisionID, versions[0].revisionID, aFinal.script.revisionID])
        var b = try await make("b", session: "S-B")
        b = try await store.saveTitle("기밀제목 b2", for: b)
        try toLegacy(root, scriptID: b.id)
        let c = try await make("c", session: "S-C")
        _ = try await store.saveTitle("기밀제목 c2", for: c)
        try toLegacy(root, scriptID: c.id)
        try FileManager.default.removeItem(at: c.url)                          // Finder에서 지운 스크립트
        let d = try await make("d", session: "S-D")
        try FileManager.default.removeItem(at: d.url)
        for id in [aFinal.id, c.id] {
            let url = try InternalStoragePaths.correctionAttemptURL(root: root, scriptID: id)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(#"{"synthetic":true}"#.utf8).write(to: url)
        }
        let sessions = root.appendingPathComponent("Sessions/S-A/runs/r")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try Data("원응답".utf8).write(to: sessions.appendingPathComponent("state.json"))
        return Fixture(base: base, folder: folder, root: root, store: store, a: aFinal, b: b, cID: c.id, dID: d.id,
                       sessions: root.appendingPathComponent("Sessions"))
    }

    func testPlanIsReadOnlyAndClassifiesHistory() async throws {
        let f = try await fixture()
        XCTAssertEqual(f.a.script.versions?.count, 2)
        let before = manifest(f.root)
        let plan = try await f.store.planRevisionCleanup(presentScriptIDs: [f.a.id, f.b.id], scanHasIssues: false)
        XCTAssertEqual(manifest(f.root), before)
        XCTAssertEqual(plan.deletions.count, 3)                     // C 2 (구) + D 1 (새)
        XCTAssertEqual(Set(plan.deletions.map(\.scriptID)), [f.cID, f.dID])
        XCTAssertEqual(plan.migrations.count, 5)                     // A 3 + B 2
        XCTAssertEqual(Dictionary(grouping: plan.migrations, by: \.scriptID).mapValues(\.count), [f.a.id: 3, f.b.id: 2])
        XCTAssertEqual(plan.attempts, [f.cID])
        XCTAssertFalse(plan.skippedOrphans)
        XCTAssertEqual(plan.unreadable, [])
    }

    /// Scripts에 손상 파일 1개 → 확인 단계가 조회 문제를 보고 지울 이력·시도 기록을 0으로 둔다. C·D 이력 SHA256 불변.
    func testScanIssuesKeepOrphansUntouched() async throws {
        let f = try await fixture()
        // 조회 문제가 없을 때의 고아 파일 경로(C 구 배치 2 + D 새 배치 1 + C 시도 기록)를 먼저 잰다.
        let unblocked = try await f.store.planStorageCleanup(scriptsFolder: f.folder).plan
        let orphanPaths = unblocked.deletions.map(\.url.path) + [try InternalStoragePaths.correctionAttemptURL(root: f.root, scriptID: f.cID).path]
        XCTAssertEqual(unblocked.deletions.count, 3)
        func hashes() throws -> [String: String] {
            Dictionary(uniqueKeysWithValues: try orphanPaths.map { ($0, sha(try Data(contentsOf: URL(fileURLWithPath: $0)))) })
        }
        let before = try hashes()
        try Data("손상된 스크립트".utf8).write(to: f.folder.appendingPathComponent("broken.dama.json"))
        let checked = try await f.store.planStorageCleanup(scriptsFolder: f.folder)
        XCTAssertEqual(checked.scan.issues.count, 1)
        XCTAssertTrue(checked.plan.skippedOrphans)
        XCTAssertEqual(checked.plan.deletions, [])
        XCTAssertEqual(checked.plan.attempts, [])
        XCTAssertEqual(checked.plan.migrations.count, 5)
        _ = await f.store.runRevisionCleanup(checked.plan, removedScriptIDs: []) { _ in }
        XCTAssertEqual(try hashes(), before)
    }

    /// 확인 단계는 내부 저장소에 아무것도 쓰지 않는다(요약 캐시가 없거나 낡아도).
    func testCheckStepWritesNothingEvenWithStaleSummaryCache() async throws {
        let f = try await fixture()
        let cache = f.root.appendingPathComponent("library-script-summaries.json")
        try? FileManager.default.removeItem(at: cache)
        let before = manifest(f.root), scriptsBefore = manifest(f.folder)
        let checked = try await FolderLibraryStore(root: f.root).planStorageCleanup(scriptsFolder: f.folder)
        XCTAssertEqual(checked.scan.items.count, 2)
        XCTAssertEqual(manifest(f.root), before)
        XCTAssertEqual(manifest(f.folder), scriptsBefore)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path))
    }

    func testRunMigratesDeletesLogsAndKeepsEverythingElse() async throws {
        let f = try await fixture()
        let legacyBefore = Dictionary(uniqueKeysWithValues: try legacy(f.root).map { ($0.lastPathComponent, sha(try Data(contentsOf: $0))) })
        let sessionsBefore = manifest(f.sessions), scriptsBefore = manifest(f.folder)
        let plan = try await f.store.planRevisionCleanup(presentScriptIDs: [f.a.id, f.b.id], scanHasIssues: false)
        let total = plan.deletions.count + plan.migrations.count + plan.attempts.count
        let seen = OSAllocatedUnfairLock(initialState: [Int]())
        let result = await f.store.runRevisionCleanup(plan, removedScriptIDs: []) { value in seen.withLock { $0.append(value) } }
        XCTAssertEqual(result, RevisionCleanupResult(deleted: 3, migrated: 5, attemptsDeleted: 1, failed: 0))
        XCTAssertEqual(seen.withLock { $0 }, Array(1...total))
        XCTAssertEqual(legacy(f.root), [])
        // 이전한 파일마다 풀어서 원본 SHA256과 같다.
        for item in plan.migrations {
            let target = try await f.store.revisionURL(scriptID: item.scriptID, revisionID: item.revisionID)
            XCTAssertEqual(sha(try RevisionCodec.inflate(Data(contentsOf: target))), legacyBefore[item.url.lastPathComponent])
        }
        let current = manifest(f.root.appendingPathComponent("LibraryRevisions"))
        XCTAssertEqual(current.count, 6)                             // A 3 이전 + A 새 배치 1 + B 2
        XCTAssertFalse(current.keys.contains { $0.contains(f.cID) || $0.contains(f.dID) })
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.root.appendingPathComponent("LibraryRevisions/\(f.dID)").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: try InternalStoragePaths.correctionAttemptURL(root: f.root, scriptID: f.cID).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try InternalStoragePaths.correctionAttemptURL(root: f.root, scriptID: f.a.id).path))
        XCTAssertEqual(manifest(f.sessions), sessionsBefore)
        XCTAssertEqual(manifest(f.folder), scriptsBefore)
        // AI 버전(snapshot)은 새 배치에서 열린다.
        for version in try XCTUnwrap(f.a.script.versions) {
            let opened = try await f.store.readVersion(version, for: f.a)
            XCTAssertTrue(opened.url.lastPathComponent.hasSuffix(".dama.json.deflate"))
        }
        // 건별 기록: 줄 수 = 처리 항목 수, 키 6개, 제목 문자열 없음.
        let log = try String(contentsOf: f.root.appendingPathComponent("storage-cleanup-log.jsonl"), encoding: .utf8)
        let lines = log.split(separator: "\n")
        XCTAssertEqual(lines.count, total)
        for line in lines {
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
            XCTAssertEqual(Set(object.keys), ["at", "kind", "scriptID", "revisionID", "bytes", "result"])
        }
        XCTAssertFalse(log.contains("기밀제목"))
        // 다시 확인하면 정리할 것이 없다.
        let again = try await f.store.planRevisionCleanup(presentScriptIDs: [f.a.id, f.b.id], scanHasIssues: false)
        XCTAssertEqual(again.deletions.count + again.migrations.count + again.attempts.count, 0)
    }

    func testRetainedRemovalsLegacyHistoryIsDeletedNotMigrated() async throws {
        let f = try await fixture()
        let plan = try await f.store.planRevisionCleanup(presentScriptIDs: [f.a.id, f.b.id], scanHasIssues: false)
        let result = await f.store.runRevisionCleanup(plan, removedScriptIDs: [f.b.id]) { _ in }
        XCTAssertEqual(result, RevisionCleanupResult(deleted: 5, migrated: 3, attemptsDeleted: 1, failed: 0))
        XCTAssertFalse(manifest(f.root.appendingPathComponent("LibraryRevisions")).keys.contains { $0.contains(f.b.id) })
    }

    func testRoundTripMismatchKeepsOriginalAndCountsFailure() async throws {
        let f = try await fixture()
        await f.store.setCleanupTestHooks(beforeRemovingOriginal: nil, compressor: { _ in try RevisionCodec.deflate(Data("다른 바이트".utf8)) })
        let plan = try await f.store.planRevisionCleanup(presentScriptIDs: [f.a.id, f.b.id], scanHasIssues: false)
        let result = await f.store.runRevisionCleanup(plan, removedScriptIDs: []) { _ in }
        XCTAssertEqual(result.migrated, 0)
        XCTAssertEqual(result.failed, 5)
        XCTAssertEqual(legacy(f.root).count, 5)
        let current = manifest(f.root.appendingPathComponent("LibraryRevisions")).keys.filter { $0.hasSuffix(".deflate") }
        XCTAssertEqual(current.count, 1)                             // A의 기존 새 배치 1만 남음
    }

    /// 중단 안전: 원본 삭제 직전 중단 → 다음 정리 → 중단 없는 정리와 같은 최종 상태.
    /// 최종 상태 = 구 배치 0 · 이전 대상마다 새 배치가 원본 바이트로 풀림 · 스크립트별 파일 수 · 임시 파일 0.
    private func finalState(_ f: Fixture, _ plan: RevisionCleanupPlan, originals: [String: String]) async throws -> [String: Int] {
        XCTAssertEqual(legacy(f.root), [])
        for item in plan.migrations {
            let target = try await f.store.revisionURL(scriptID: item.scriptID, revisionID: item.revisionID)
            XCTAssertEqual(sha(try RevisionCodec.inflate(Data(contentsOf: target))), originals[item.revisionID])
        }
        let files = manifest(f.root.appendingPathComponent("LibraryRevisions")).keys
        XCTAssertFalse(files.contains { $0.contains("/.tmp-") })
        return Dictionary(grouping: files) { path in path.contains(f.a.id) ? "A" : path.contains(f.b.id) ? "B" : "other" }.mapValues(\.count)
    }
    private func originals(_ f: Fixture) throws -> [String: String] {
        Dictionary(uniqueKeysWithValues: try legacy(f.root).map {
            (String($0.lastPathComponent.dropLast(".dama.json".count)), sha(try Data(contentsOf: $0)))
        })
    }

    func testInterruptedMigrationResumesToSameFinalState() async throws {
        let reference = try await fixture()
        let referenceOriginals = try originals(reference)
        let referencePlan = try await reference.store.planRevisionCleanup(presentScriptIDs: [reference.a.id, reference.b.id], scanHasIssues: false)
        _ = await reference.store.runRevisionCleanup(referencePlan, removedScriptIDs: []) { _ in }
        let expected = try await finalState(reference, referencePlan, originals: referenceOriginals)
        XCTAssertEqual(expected, ["A": 4, "B": 2])

        let f = try await fixture()
        let fOriginals = try originals(f)
        let ticks = OSAllocatedUnfairLock(initialState: 0)
        await f.store.setCleanupTestHooks(beforeRemovingOriginal: { _ in
            if ticks.withLock({ $0 += 1; return $0 }) > 2 { throw CocoaError(.userCancelled) }
        }, compressor: nil)
        let plan = try await f.store.planRevisionCleanup(presentScriptIDs: [f.a.id, f.b.id], scanHasIssues: false)
        let interrupted = await f.store.runRevisionCleanup(plan, removedScriptIDs: []) { _ in }
        XCTAssertEqual(interrupted.migrated, 2)
        XCTAssertEqual(interrupted.failed, 3)                        // 3번째부터 원본 삭제 직전 중단: 새 파일과 원본이 함께 남음
        XCTAssertEqual(legacy(f.root).count, 3)
        // 남은 새 파일 하나는 잘린 채로 둔다(풀 수 없음 → 지우고 다시 압축).
        let leftover = try XCTUnwrap(legacy(f.root).first)
        let leftoverRevision = String(leftover.lastPathComponent.dropLast(".dama.json".count))
        let leftoverScript = try XCTUnwrap(plan.migrations.first { $0.revisionID == leftoverRevision }).scriptID
        let truncated = try await f.store.revisionURL(scriptID: leftoverScript, revisionID: leftoverRevision)
        let bytes = try Data(contentsOf: truncated); try bytes.prefix(bytes.count / 2).write(to: truncated)
        await f.store.setCleanupTestHooks(beforeRemovingOriginal: nil, compressor: nil)
        let resumed = try await f.store.planRevisionCleanup(presentScriptIDs: [f.a.id, f.b.id], scanHasIssues: false)
        XCTAssertEqual(resumed.migrations.count, 3)
        let second = await f.store.runRevisionCleanup(resumed, removedScriptIDs: []) { _ in }
        XCTAssertEqual(second.migrated, 3)
        XCTAssertEqual(second.failed, 0)
        let state = try await finalState(f, plan, originals: fOriginals)
        XCTAssertEqual(state, expected)
    }

    /// 단위 고정: 크기 = 파일 크기 바이트 합(구·새 배치), 표기 = ByteCountFormatter .file(1000진).
    func testStorageBytesSumsBothLayoutsInDecimalFileUnits() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: base) }
        let revisions = base.appendingPathComponent("LibraryRevisions/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: revisions, withIntermediateDirectories: true)
        try Data(count: 1_000).write(to: base.appendingPathComponent("LibraryRevisions/\(UUID().uuidString).dama.json"))
        try Data(count: 2_500).write(to: revisions.appendingPathComponent("\(UUID().uuidString).dama.json.deflate"))
        try Data(count: 500).write(to: revisions.appendingPathComponent("\(UUID().uuidString).dama.json.deflate"))
        let total = await FolderLibraryStore(root: base).revisionStorageBytes()
        XCTAssertEqual(total, 4_000)
        XCTAssertEqual(StorageCleanupNotice.size(1_000_000), ByteCountFormatter.string(fromByteCount: 1_000_000, countStyle: .file))
        XCTAssertNotEqual(StorageCleanupNotice.size(1_000_000), ByteCountFormatter.string(fromByteCount: 1_000_000, countStyle: .memory))
        let empty = await FolderLibraryStore(root: base.appendingPathComponent("없음")).revisionStorageBytes()
        XCTAssertEqual(empty, 0)
    }
}

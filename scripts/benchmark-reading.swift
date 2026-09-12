// Compile with DamaCore sources (-O), or with package modules and -D STORE_BENCHMARK.
// Arguments: Scripts folder, internal root, new report JSON, Run ID.
// Reads existing files only. Reports timings/hashes/counts, never transcript text.
import Foundation
import CryptoKit
#if STORE_BENCHMARK
import DamaCore
import DamaAudio
#endif

@main struct ReadingBenchmark {
    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func milliseconds(since start: ContinuousClock.Instant) -> Double {
        let elapsed = start.duration(to: .now).components
        return Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15
    }
    static func stats(_ samples: [Double]) -> [String: Any] {
        // Order statistic at count/2: the upper middle value when the count is even.
        ["samples": samples.count, "medianMs": samples.sorted()[samples.count / 2], "minMs": samples.min()!, "maxMs": samples.max()!]
    }
    // Vary the consumed row so the optimizer cannot hoist a constant count out of the loop.
    @inline(never) static func consume(_ snapshot: ScriptReadingSnapshot, index: Int) -> Int {
        let block = snapshot.blocks[index % snapshot.blocks.count]
        return block.text.utf8.count + block.turns.count
    }
    static func signature(_ blocks: [ScriptBlock]) throws -> Data {
        struct Block: Encodable {
            let turns: [TranscriptTurn], issues: [ReviewIssue]
            let text: String, name: String, colorIndex: Int?, edited: Bool
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(blocks.map { Block(turns: $0.turns, issues: $0.issues, text: $0.text, name: $0.name, colorIndex: $0.colorIndex, edited: $0.edited) })
    }
    static func main() async throws {
        guard CommandLine.arguments.count == 5 else { fatalError("expected folder, internal root, new report, run ID") }
        let folder = URL(fileURLWithPath: CommandLine.arguments[1]), root = URL(fileURLWithPath: CommandLine.arguments[2])
        let report = URL(fileURLWithPath: CommandLine.arguments[3]), run = CommandLine.arguments[4]
        guard !FileManager.default.fileExists(atPath: report.path) else { fatalError("report already exists") }
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasSuffix(".dama.json") }
        var hashes: [String: String] = [:], selected: LibraryScript?
        for url in files {
            let bytes = try Data(contentsOf: url); hashes[url.path] = hash(bytes)
            let script = try JSONDecoder().decode(LibraryScript.self, from: bytes); try script.validate()
            if script.id == run { selected = script }
        }
        guard let script = selected else { fatalError("selected run not found") }
        let snapshot = ScriptReadingSnapshot(script: script)
        let projectionEqual = try signature(snapshot.blocks) == signature(script.blocks())
        precondition(projectionEqual)
        var uncached: [Double] = [], lookup: [Double] = [], checksum = 0
        for _ in 0..<20 {
            let start = ContinuousClock.now
            let blocks = script.blocks()
            checksum += blocks.count
            uncached.append(milliseconds(since: start))
            let cachedStart = ContinuousClock.now
            for index in 0..<1_000 { checksum += consume(snapshot, index: index) }
            lookup.append(milliseconds(since: cachedStart))
        }
        var result: [String: Any] = ["readingPolicy": ScriptReadingPolicy.algorithmVersion,
            "measuredAt": ISO8601DateFormatter().string(from: Date()), "runID": run,
            "scriptFiles": files.count, "blocks": snapshot.blocks.count, "events": snapshot.reviewEvents.count,
            "uncachedOneBlocksCall": stats(uncached), "cached1000Lookups": stats(lookup), "checksum": checksum,
            "projectionSHA256": hash(try signature(snapshot.blocks)), "markdownSHA256": hash(try script.markdown()),
            "inputSHA256": hashes, "projectionEqual": true]
        #if STORE_BENCHMARK
        var cold: [Double] = [], warm: [Double] = []
        for _ in 0..<5 {
            let store = FolderLibraryStore(root: root), start = ContinuousClock.now
            let first = try await store.scripts(in: folder)
            cold.append(milliseconds(since: start))
            let nextStart = ContinuousClock.now
            let next = try await store.scripts(in: folder)
            warm.append(milliseconds(since: nextStart))
            precondition(first.count == next.count)
            for (a, b) in zip(first, next) { precondition(a.reading === b.reading && a.hash == b.hash) }
        }
        result["moduleBuild"] = "SwiftPM Debug; caller -O"
        result["coldFolderScan"] = stats(cold); result["warmFolderScan"] = stats(warm)
        #else
        result["moduleBuild"] = "DamaCore sources -O Swift 6"
        _ = root
        #endif
        for (path, expected) in hashes {
            let current = try hash(Data(contentsOf: URL(fileURLWithPath: path)))
            precondition(current == expected)
        }
        try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys, .prettyPrinted]).write(to: report, options: .withoutOverwriting)
        print("reading benchmark verified: \(files.count) source files unchanged, \(snapshot.blocks.count) blocks, \(snapshot.reviewEvents.count) events")
    }
}

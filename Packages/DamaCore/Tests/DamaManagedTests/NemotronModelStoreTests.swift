import Foundation
import XCTest
@testable import DamaManaged

final class NemotronModelStoreTests: XCTestCase {
    private func temp() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
    private static let contents = ["a.bin": Data("first".utf8), "nested/b.bin": Data("second file".utf8)]
    private func pinned(_ root: URL) throws -> [NemotronModel.File] {
        let scratch = root.appendingPathComponent("pin")
        return try Self.contents.keys.sorted().map { path in
            let url = scratch.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Self.contents[path]!.write(to: url)
            return NemotronModel.File(path: path, sha256: try NemotronModelStore.sha256(url), bytes: Int64(Self.contents[path]!.count))
        }
    }
    private static func fill(_ folder: URL, changing changed: String? = nil, skipping skipped: String? = nil) throws {
        for (path, data) in contents where path != skipped {
            let url = folder.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            var bytes = data
            if path == changed { bytes[0] ^= 0x01 }
            try bytes.write(to: url)
        }
    }

    func testStateIsReadyOnlyWhenEveryPinnedFileMatches() throws {
        let root = try temp(), store = NemotronModelStore(modelsRoot: root.appendingPathComponent("Models"), files: try pinned(root))
        XCTAssertEqual(store.state(), .missing)
        try Self.fill(store.directory)
        XCTAssertEqual(store.state(), .ready)
        try Self.fill(store.directory, changing: "nested/b.bin")
        XCTAssertEqual(store.state(), .mismatch)
        XCTAssertEqual(try store.removeIfMismatched(), .mismatch)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.directory.path))
        XCTAssertEqual(store.state(), .missing)
        try Self.fill(store.directory, skipping: "a.bin")
        XCTAssertEqual(store.state(), .mismatch)
    }

    func testInstallVerifiesStagingBeforeReplacing() async throws {
        let root = try temp(), store = NemotronModelStore(modelsRoot: root.appendingPathComponent("Models"), files: try pinned(root))
        try await store.install { cache in try Self.fill(cache.appendingPathComponent(NemotronModel.folderName)) }
        XCTAssertEqual(store.state(), .ready)
        do {
            try await store.install { cache in try Self.fill(cache.appendingPathComponent(NemotronModel.folderName), changing: "a.bin") }
            XCTFail("installed a mismatching model")
        } catch { XCTAssertEqual(error as? NemotronModelError, .mismatch) }
        XCTAssertEqual(store.state(), .ready, "the verified copy stays in place")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: store.modelsRoot.path).filter { $0.hasPrefix(".staging") }
        XCTAssertTrue(leftovers.isEmpty)
    }

    func testPinnedListMatchesTheMeasuredDownload() {
        XCTAssertEqual(NemotronModel.files.count, 6)
        XCTAssertEqual(NemotronModel.files.reduce(0) { $0 + $1.bytes }, 199_162_417)
        XCTAssertEqual(NemotronModel.manifestSHA256, NemotronModel.digest(NemotronModel.files))
        XCTAssertEqual(NemotronModel.files.map(\.path).filter { $0.hasPrefix(NemotronModel.bundlePath) }.count, 4)
    }
}

import DamaCore
import Foundation

/// usage-bundle2 수정 이력 압축 (library-script.md «AI 결과 버전·필드 저장»·«결과 보관»).
/// 형식 = raw DEFLATE(RFC 1951): Apple `COMPRESSION_ZLIB`(`NSData.compressed(using: .zlib)`), level 5 고정
/// (SDK compression.h «We implement the zlib level 5 encoder only … raw DEFLATE»). Scripts 활성 파일은 압축하지 않는다.
enum RevisionCodec {
    static let compressedSuffix = ".dama.json.deflate"
    static let legacySuffix = ".dama.json"

    static func deflate(_ bytes: Data) throws -> Data {
        try (bytes as NSData).compressed(using: .zlib) as Data
    }
    /// 풀 수 없는 바이트는 손상이다.
    static func inflate(_ stored: Data) throws -> Data {
        do { return try (stored as NSData).decompressed(using: .zlib) as Data }
        catch { throw LibraryFailure.invalidScript }
    }
    /// 같은 폴더 임시 이름에 쓴 뒤 덮어쓰기 없는 이동으로만 만든다(대상이 있으면 실패). 부분 기록 파일은 보이지 않는다.
    static func writeNew(_ stored: Data, to url: URL) throws {
        let folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let temporary = folder.appendingPathComponent(".tmp-\(UUID().uuidString)")
        try stored.write(to: temporary, options: .withoutOverwriting)
        do { try FileManager.default.moveItem(at: temporary, to: url) }
        catch {
            try? FileManager.default.removeItem(at: temporary)
            if FileManager.default.fileExists(atPath: url.path) { throw LibraryFailure.changedFile }
            throw error
        }
    }
}

import Foundation
import CryptoKit
import DamaCore

/// Reads only selected local Markdown/plain text. No documents are executed or sent here.
public actor ReferenceFolder {
    public init() {}
    public func excerpts(in directory: URL, query: String) throws -> [ReferenceExcerpt] {
        let root = directory.standardizedFileURL.resolvingSymlinksInPath()
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .isDirectoryKey]
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { throw LibraryFailure.missingFile }
        let terms = Set(query.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).filter { $0.count >= 2 }.map(String.init))
        var candidates: [(score: Int, excerpt: ReferenceExcerpt)] = [], inspected = 0
        for case let url as URL in walker {
            inspected += 1
            if inspected > 300 { break }
            let values = try url.resourceValues(forKeys: Set(keys))
            if values.isSymbolicLink == true { walker.skipDescendants(); continue }
            if values.isDirectory == true && walker.level >= 3 { walker.skipDescendants(); continue }
            guard values.isRegularFile == true, ["md", "txt"].contains(url.pathExtension.lowercased()),
                  (values.fileSize ?? Int.max) <= 200_000, url.resolvingSymlinksInPath().path.hasPrefix(root.path + "/") else { continue }
            let handle = try FileHandle(forReadingFrom: url)
            let data = try handle.read(upToCount: 200_001) ?? Data()
            try handle.close()
            guard data.count <= 200_000, let content = String(data: data, encoding: .utf8) else { continue }
            let paragraphs = content.components(separatedBy: "\n\n").enumerated().map { index, text in
                (index: index, text: String(text.prefix(2000)), score: terms.filter { text.lowercased().contains($0) }.count)
            }
            let selected = paragraphs.sorted { $0.score == $1.score ? $0.index < $1.index : $0.score > $1.score }.prefix(3).sorted { $0.index < $1.index }
            let text = String(selected.map(\.text).joined(separator: "\n\n[…]\n\n").prefix(4000))
            if !text.isEmpty {
                let name = String(url.resolvingSymlinksInPath().path.dropFirst(root.path.count + 1))
                let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                candidates.append((selected.map(\.score).reduce(0, +), ReferenceExcerpt(name: name, sha256: hash, text: text)))
            }
        }
        var remaining = 12_000, result: [ReferenceExcerpt] = []
        for item in candidates.sorted(by: { $0.score == $1.score ? $0.excerpt.name < $1.excerpt.name : $0.score > $1.score }).prefix(8) {
            if remaining <= 0 { break }
            let text = String(item.excerpt.text.prefix(remaining)); remaining -= text.count
            result.append(ReferenceExcerpt(name: item.excerpt.name, sha256: item.excerpt.sha256, text: text))
        }
        return result
    }
}

import CryptoKit
import Foundation

/// One human-authored reading paragraph, never redistributed over provider Turns.
public struct ScriptParagraphEdit: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let turnIDs: [String]
    public let sourceSHA256: String
    public let baseRevisionID: String
    public let baseTextSHA256: String
    public let text: String
}

extension LibraryScript {
    public static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    public func sourceFingerprint() throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return Self.digest(try encoder.encode(transcript))
    }
    public var humanOwnedTurnIDs: Set<String> {
        var ids = Set(turnTexts.keys).union((paragraphEdits ?? []).flatMap(\.turnIDs))
        let words = Set(transcript.words.filter { $0.editedText != nil }.map(\.id))
        for turn in transcript.turns where transcript.revision.humanEdited || !words.isDisjoint(with: turn.wordIds) {
            ids.insert(turn.id)
        }
        return ids
    }
    func validateParagraphEdits() throws {
        guard let edits = paragraphEdits, !edits.isEmpty else { return }
        let fingerprint = try sourceFingerprint()
        let joinable = ScriptReadingStructure(self).joinableBefore
        let positions = Dictionary(uniqueKeysWithValues: transcript.turns.enumerated().map { ($0.element.id, $0.offset) })
        var seen = Set<String>(), editIDs = Set<String>()
        for edit in edits {
            guard UUID(uuidString: edit.id) != nil, editIDs.insert(edit.id).inserted,
                  UUID(uuidString: edit.baseRevisionID) != nil,
                  edit.sourceSHA256 == fingerprint,
                  edit.baseTextSHA256.count == 64, edit.baseTextSHA256.allSatisfy(\.isHexDigit),
                  !edit.turnIDs.isEmpty else { throw LibraryFailure.invalidScript }
            var previous: Int?
            for id in edit.turnIDs {
                guard let i = positions[id], seen.insert(id).inserted, transcript.turns[i].kind == .speech else {
                    throw LibraryFailure.invalidScript
                }
                if let previous {
                    guard i > previous,
                          transcript.turns[(previous + 1)..<i].allSatisfy({ $0.kind == .missingSpeech }),
                          joinable.contains(id) else { throw LibraryFailure.invalidScript }
                }
                previous = i
            }
        }
    }
    public mutating func editParagraph(_ block: ScriptBlock, text: String) throws {
        try validate()
        guard block.isSpeech, let current = blocks().first(where: { $0.turnIDs == block.turnIDs }),
              current.text == block.text else { throw LibraryFailure.changedFile }
        guard text != current.text else { return }
        let ids = Set(block.turnIDs)
        let prior = paragraphEdits ?? []
        guard prior.allSatisfy({ ids.isDisjoint(with: $0.turnIDs) || $0.turnIDs == block.turnIDs }) else {
            throw LibraryFailure.invalidInput
        }
        let edit = ScriptParagraphEdit(id: UUID().uuidString, turnIDs: block.turnIDs,
            sourceSHA256: try sourceFingerprint(), baseRevisionID: revisionID,
            baseTextSHA256: Self.digest(Data(block.text.utf8)), text: text)
        paragraphEdits = prior.filter { $0.turnIDs != block.turnIDs } + [edit]
        revisionID = UUID().uuidString
        try validateParagraphEdits()
    }
}

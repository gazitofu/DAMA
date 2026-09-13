import Foundation

public struct ScriptSpeaker: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let colorIndex: Int
}

public struct ScriptDeletedParagraph: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let turnIDs: [String]
}

extension LibraryScript {
    public func registeredSpeaker(for turnID: String) -> ScriptSpeaker? {
        guard let id = turnSpeakerIDs?[turnID] else { return nil }
        return registeredSpeakers?.first { $0.id == id }
    }
    func manualName(for turn: TranscriptTurn) -> String? {
        registeredSpeaker(for: turn.id)?.name ?? turnNames[turn.id]
    }
    /// Legacy manually entered names also remain selectable without rewriting the file on read.
    public var availableSpeakers: [ScriptSpeaker] {
        var result = registeredSpeakers ?? [], seen = Set(result.map(\.name))
        for turn in transcript.turns {
            guard let name = turnNames[turn.id]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty, seen.insert(name).inserted else { continue }
            result.append(ScriptSpeaker(id: "legacy:" + turn.id, name: name,
                colorIndex: colorIndex(for: turn.speakerId) ?? result.count % 10))
        }
        return result
    }
    func speakerTargets(_ turnID: String, scope: SpeakerNameScope) -> [String] {
        guard let index = transcript.turns.firstIndex(where: { $0.id == turnID }) else { return [] }
        let turn = transcript.turns[index], registered = turnSpeakerIDs?[turnID]
        let deleted = deletedTurnIDs
        if scope == .one || (registered == nil && turn.speakerId == nil) { return deleted.contains(turnID) ? [] : [turnID] }
        return transcript.turns.enumerated().filter { i, candidate in
            let matches = registered.map { turnSpeakerIDs?[candidate.id] == $0 } ?? (candidate.speakerId == turn.speakerId)
            return matches && !deleted.contains(candidate.id) && (scope == .all || i >= index)
        }.map { $0.element.id }
    }
    mutating func registerName(_ value: String, for ids: [String], anchor: String) throws {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !ids.isEmpty, snapshotTitle == nil else { throw LibraryFailure.invalidInput }
        let speaker: ScriptSpeaker
        if let existing = registeredSpeakers?.first(where: { $0.name == name }) { speaker = existing }
        else {
            let color = availableSpeakers.first(where: { $0.name == name })?.colorIndex
                ?? registeredSpeaker(for: anchor)?.colorIndex
                ?? transcript.turns.first(where: { $0.id == anchor }).flatMap { colorIndex(for: $0.speakerId) }
                ?? (registeredSpeakers?.count ?? 0) % 10
            speaker = ScriptSpeaker(id: UUID().uuidString, name: name, colorIndex: color)
            registeredSpeakers = (registeredSpeakers ?? []) + [speaker]
        }
        if turnSpeakerIDs == nil { turnSpeakerIDs = [:] }
        // Explicit reuse of an existing name registers its legacy occurrences as the same person.
        for (id, legacyName) in turnNames where turnSpeakerIDs?[id] == nil && legacyName.trimmingCharacters(in: .whitespacesAndNewlines) == name {
            turnSpeakerIDs?[id] = speaker.id
        }
        for id in ids { turnSpeakerIDs?[id] = speaker.id; turnNames[id] = name }
        revisionID = UUID().uuidString
    }
    public var deletedTurnIDs: Set<String> { Set((deletedParagraphs ?? []).flatMap(\.turnIDs)) }
    public mutating func deleteParagraph(_ block: ScriptBlock) throws {
        try validate()
        guard snapshotTitle == nil, let current = blocks().first(where: { $0.turnIDs == block.turnIDs }),
              current.text == block.text, current.name == block.name else { throw LibraryFailure.changedFile }
        deletedParagraphs = (deletedParagraphs ?? []) + [ScriptDeletedParagraph(id: UUID().uuidString, turnIDs: block.turnIDs)]
        revisionID = UUID().uuidString
        try validatePeopleAndDeletion()
    }
    public mutating func undoParagraphDeletion() throws {
        guard snapshotTitle == nil, deletedParagraphs?.isEmpty == false else { throw LibraryFailure.invalidInput }
        deletedParagraphs?.removeLast()
        revisionID = UUID().uuidString
    }
    func validatePeopleAndDeletion() throws {
        let people = registeredSpeakers ?? [], personIDs = Set(people.map(\.id))
        let turns = Dictionary(uniqueKeysWithValues: transcript.turns.enumerated().map { ($0.element.id, $0.offset) })
        guard personIDs.count == people.count, Set(people.map(\.name)).count == people.count,
              people.allSatisfy({ UUID(uuidString: $0.id) != nil && !$0.name.isEmpty && $0.name == $0.name.trimmingCharacters(in: .whitespacesAndNewlines) && (0..<10).contains($0.colorIndex) }),
              Set((turnSpeakerIDs ?? [:]).keys).isSubset(of: Set(turns.keys)),
              Set((turnSpeakerIDs ?? [:]).values).isSubset(of: personIDs) else { throw LibraryFailure.invalidScript }
        var seen = Set<String>(), deletionIDs = Set<String>()
        for deletion in deletedParagraphs ?? [] {
            guard UUID(uuidString: deletion.id) != nil, deletionIDs.insert(deletion.id).inserted,
                  !deletion.turnIDs.isEmpty else { throw LibraryFailure.invalidScript }
            var previous: Int?
            for id in deletion.turnIDs {
                guard let index = turns[id], seen.insert(id).inserted, transcript.turns[index].kind == .speech else { throw LibraryFailure.invalidScript }
                if let previous {
                    guard index > previous, transcript.turns[(previous + 1)..<index].allSatisfy({ $0.kind == .missingSpeech }) else { throw LibraryFailure.invalidScript }
                }
                previous = index
            }
        }
    }
}

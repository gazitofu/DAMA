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

/// One saved speaker-name change, with the exact state it replaced.
/// A turn listed in `turnIDs` but missing from a map had no value before the change.
public struct ScriptNameChange: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let turnIDs: [String]
    public let previousNames: [String: String]
    public let previousSpeakerIDs: [String: String]
    public let addedSpeakerID: String?

    public init(id: String, name: String, turnIDs: [String], previousNames: [String: String],
                previousSpeakerIDs: [String: String], addedSpeakerID: String?) {
        self.id = id; self.name = name; self.turnIDs = turnIDs
        self.previousNames = previousNames; self.previousSpeakerIDs = previousSpeakerIDs
        self.addedSpeakerID = addedSpeakerID
    }
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
    /// ‘이 부분부터/전체’는 항상 원 화자 ID(Speaker A/B/C)가 같은 Turn 집합이다 (2026-09-21 사용자 규칙).
    /// 등록 인물·이름은 대상 선정에 쓰지 않으므로, 같은 이름으로 지정된 다른 원 화자는 함께 바뀌지 않는다.
    func speakerTargets(_ turnID: String, scope: SpeakerNameScope) -> [String] {
        guard let index = transcript.turns.firstIndex(where: { $0.id == turnID }) else { return [] }
        let deleted = deletedTurnIDs
        guard scope != .one, let speaker = transcript.turns[index].speakerId else { return deleted.contains(turnID) ? [] : [turnID] }
        return transcript.turns.enumerated().filter { i, candidate in
            candidate.speakerId == speaker && !deleted.contains(candidate.id) && (scope == .all || i >= index)
        }.map { $0.element.id }
    }
    /// Initial design value (2026-09-21). Bounded so one sweep over a long recording cannot grow the file without limit.
    public static let nameHistoryLimit = 20

    mutating func registerName(_ value: String, for ids: [String], anchor: String) throws {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !ids.isEmpty, snapshotTitle == nil else { throw LibraryFailure.invalidInput }
        var addedSpeakerID: String?
        let speaker: ScriptSpeaker
        if let existing = registeredSpeakers?.first(where: { $0.name == name }) { speaker = existing }
        else {
            let color = availableSpeakers.first(where: { $0.name == name })?.colorIndex
                ?? registeredSpeaker(for: anchor)?.colorIndex
                ?? transcript.turns.first(where: { $0.id == anchor }).flatMap { colorIndex(for: $0.speakerId) }
                ?? (registeredSpeakers?.count ?? 0) % 10
            speaker = ScriptSpeaker(id: UUID().uuidString, name: name, colorIndex: color)
            registeredSpeakers = (registeredSpeakers ?? []) + [speaker]
            addedSpeakerID = speaker.id
        }
        if turnSpeakerIDs == nil { turnSpeakerIDs = [:] }
        // Explicit reuse of an existing name registers its legacy occurrences as the same person.
        var touched = ids
        for (id, legacyName) in turnNames where turnSpeakerIDs?[id] == nil && legacyName.trimmingCharacters(in: .whitespacesAndNewlines) == name {
            turnSpeakerIDs?[id] = speaker.id
            if !touched.contains(id) { touched.append(id) }
        }
        // The replaced state is captured before the write so one undo restores it exactly.
        var previousNames: [String: String] = [:], previousSpeakerIDs: [String: String] = [:]
        for id in touched {
            if let name = turnNames[id] { previousNames[id] = name }
            if let person = registeredSpeaker(for: id)?.id { previousSpeakerIDs[id] = person }
        }
        for id in ids { turnSpeakerIDs?[id] = speaker.id; turnNames[id] = name }
        var history = nameHistory ?? []
        history.append(ScriptNameChange(id: UUID().uuidString, name: name, turnIDs: touched,
            previousNames: previousNames, previousSpeakerIDs: previousSpeakerIDs, addedSpeakerID: addedSpeakerID))
        if history.count > Self.nameHistoryLimit { history.removeFirst(history.count - Self.nameHistoryLimit) }
        nameHistory = history
        revisionID = UUID().uuidString
    }
    /// Restores the state the last saved name change replaced. Original words, times and speaker IDs never move.
    public mutating func undoNameChange() throws {
        guard snapshotTitle == nil, var history = nameHistory, let last = history.last else { throw LibraryFailure.invalidInput }
        for id in last.turnIDs {
            if let name = last.previousNames[id] { turnNames[id] = name } else { turnNames.removeValue(forKey: id) }
            if let person = last.previousSpeakerIDs[id] { turnSpeakerIDs?[id] = person } else { turnSpeakerIDs?.removeValue(forKey: id) }
        }
        history.removeLast()
        // A person this change created is dropped only when nothing left, history included, still names it.
        if let added = last.addedSpeakerID,
           !(turnSpeakerIDs ?? [:]).values.contains(added),
           !history.contains(where: { $0.previousSpeakerIDs.values.contains(added) }) {
            registeredSpeakers?.removeAll { $0.id == added }
            if registeredSpeakers?.isEmpty == true { registeredSpeakers = nil }
        }
        if turnSpeakerIDs?.isEmpty == true { turnSpeakerIDs = nil }
        nameHistory = history.isEmpty ? nil : history
        revisionID = UUID().uuidString
        try validate()
    }
    func validateNameHistory() throws {
        let history = nameHistory ?? []
        guard history.count <= Self.nameHistoryLimit else { throw LibraryFailure.invalidScript }
        let turnIDs = Set(transcript.turns.map(\.id)), personIDs = Set((registeredSpeakers ?? []).map(\.id))
        var seen = Set<String>()
        for change in history {
            let touched = Set(change.turnIDs)
            guard UUID(uuidString: change.id) != nil, seen.insert(change.id).inserted,
                  !change.turnIDs.isEmpty, touched.count == change.turnIDs.count, touched.isSubset(of: turnIDs),
                  !change.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  Set(change.previousNames.keys).isSubset(of: touched),
                  Set(change.previousSpeakerIDs.keys).isSubset(of: touched),
                  Set(change.previousSpeakerIDs.values).isSubset(of: personIDs),
                  change.previousNames.values.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
                  change.addedSpeakerID.map({ UUID(uuidString: $0) != nil }) ?? true
            else { throw LibraryFailure.invalidScript }
        }
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

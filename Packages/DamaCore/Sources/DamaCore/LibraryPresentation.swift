import Foundation

/// Reading-only initial parameters, separately versioned from model normalization.
public enum ScriptReadingPolicy {
    public static let algorithmVersion = "reading-v3"
    public static let maximumGapUs: Int64 = 1_500_000
    public static let maximumParagraphUs: Int64 = 30_000_000
}

/// Related warnings share a listening range; their original IDs and kinds remain available.
public struct ScriptReviewEvent: Identifiable, Sendable {
    public var id: String { issues[0].id }
    public let issues: [ReviewIssue]
    public var startUs: Int64? { issues.compactMap(\.startUs).min() }
    public var endUs: Int64? { issues.compactMap(\.endUs).max() }
    public var kinds: [IssueKind] {
        Array(Set(issues.map(\.kind))).sorted { $0.rawValue < $1.rawValue }
    }
    public static func grouped(_ issues: [ReviewIssue]) -> [Self] {
        let sorted = issues.sorted { ($0.startUs ?? Int64.max, $0.id) < ($1.startUs ?? Int64.max, $1.id) }
        var groups: [Self] = []
        for issue in sorted {
            if let start = issue.startUs, let end = issue.endUs, start <= end,
               let last = groups.last, let lastEnd = last.endUs, start <= lastEnd {
                groups[groups.count - 1] = Self(issues: last.issues + [issue])
            } else { groups.append(Self(issues: [issue])) }
        }
        return groups
    }
}

/// A reversible reading layout. It never changes normalized turns or word timing.
public struct ScriptBlock: Identifiable, Sendable {
    public var id: String { turns[0].id }
    public let turns: [TranscriptTurn]
    public let name: String
    public let text: String
    public let colorIndex: Int?
    public let issues: [ReviewIssue]
    public let edited: Bool
    public var startUs: Int64? { turns.first?.startUs }
    public var endUs: Int64? { turns.last?.endUs }
    public var turnIDs: [String] { turns.map(\.id) }
    public var isSpeech: Bool { turns.allSatisfy { $0.kind == .speech } }
    public var openIssues: [ReviewIssue] { issues.filter { $0.status == .open } }
    public var reviewEvents: [ScriptReviewEvent] { ScriptReviewEvent.grouped(openIssues) }
}

extension LibraryScript {
    public func colorIndex(for speakerID: String?) -> Int? {
        guard let speakerID else { return nil }
        var seen = Set<String>(), order: [String] = []
        for turn in transcript.turns {
            if let id = turn.speakerId, seen.insert(id).inserted { order.append(id) }
        }
        return order.firstIndex(of: speakerID).map { $0 % 10 }
    }

    public func blocks() -> [ScriptBlock] {
        let words = Dictionary(uniqueKeysWithValues: transcript.words.map { ($0.id, $0) })
        var base = self; base.turnNames = [:]
        var names: [String: String] = [:], colors: [String: Int] = [:]
        for turn in transcript.turns {
            if let id = turn.speakerId, names[id] == nil {
                names[id] = base.name(for: turn); colors[id] = colors.count % 10
            }
        }
        func displayName(_ turn: TranscriptTurn) -> String {
            turnNames[turn.id] ?? turn.speakerId.flatMap { names[$0] } ?? "화자 미확정"
        }
        func currentText(_ turn: TranscriptTurn) -> String {
            if let edit = turnTexts[turn.id] { return edit }
            if showsOriginal != true, let edit = correction?.edits.first(where: { $0.turnID == turn.id && $0.applied }) { return edit.text }
            if turn.kind == .missingSpeech { return turn.markerText ?? "[음성 감지 / 전사 누락 의심]" }
            return turn.wordIds.compactMap { words[$0] }.sorted { $0.ordinal < $1.ordinal }
                .map { $0.prefix + ($0.editedText ?? $0.text) }.joined()
        }
        let evidence = transcript.diarization + transcript.exclusiveDiarization
        func mayJoin(_ previous: TranscriptTurn, _ next: TranscriptTurn, groupStart: Int64?) -> Bool {
            guard !transcript.revision.humanEdited,
                  previous.kind == .speech, next.kind == .speech,
                  let speaker = previous.speakerId, speaker == next.speakerId,
                  displayName(previous) == displayName(next),
                  let start = previous.startUs, let end = previous.endUs,
                  let nextStart = next.startUs, let nextEnd = next.endUs,
                  let groupStart,
                  start <= end, end <= nextStart, nextStart <= nextEnd,
                  nextStart - end <= ScriptReadingPolicy.maximumGapUs,
                  nextEnd - groupStart <= ScriptReadingPolicy.maximumParagraphUs else { return false }
            // A new/ending B remains a boundary, even without B text. Within one
            // continuous overlap, A's adjacent words can share a paragraph and warning.
            return !evidence.contains {
                $0.speakerId != speaker && $0.startUs < nextEnd && $0.endUs > start &&
                !($0.startUs <= start && $0.endUs >= nextEnd)
            }
        }
        var groups: [[TranscriptTurn]] = []
        for turn in transcript.turns {
            if let previous = groups.last?.last, mayJoin(previous, turn, groupStart: groups.last?.first?.startUs) {
                groups[groups.count - 1].append(turn)
            } else { groups.append([turn]) }
        }
        var result: [ScriptBlock] = []
        var attached = Set<String>()
        for group in groups {
            let ids = Set(group.flatMap(\.reviewIssueIds) + group.flatMap(\.wordIds).flatMap { words[$0]?.reviewIssueIds ?? [] })
            let issues = transcript.reviewIssues.filter { ids.contains($0.id) }
            attached.formUnion(issues.map(\.id))
            let text = group.map(currentText).reduce("") { current, next in
                let needsSpace = !current.isEmpty && !next.isEmpty && current.last?.isWhitespace == false && next.first?.isWhitespace == false
                return current + (needsSpace ? " " : "") + next
            }
            // Trim only the reading paragraph. Keep source tokens and user-authored spacing intact.
            let hasHumanText = transcript.revision.humanEdited || group.contains {
                turnTexts[$0.id] != nil || $0.wordIds.contains { words[$0]?.editedText != nil }
            }
            let displayText = hasHumanText ? text : text.trimmingCharacters(in: .whitespacesAndNewlines)
            result.append(ScriptBlock(turns: group, name: displayName(group[0]), text: displayText,
                colorIndex: group[0].speakerId.flatMap { colors[$0] }, issues: issues,
                edited: group.contains { turnTexts[$0.id] != nil }))
        }
        // Session/interval-level events without turn references must remain reachable.
        for issue in transcript.reviewIssues where !attached.contains(issue.id) && !result.isEmpty {
            let index = result.firstIndex { block in
                guard let start = issue.startUs, let end = issue.endUs,
                      let blockStart = block.startUs, let blockEnd = block.endUs else { return false }
                return start < blockEnd && end > blockStart
            } ?? issue.startUs.flatMap { start in
                result.firstIndex { ($0.endUs ?? -1) >= start } ?? result.indices.last
            } ?? 0
            let block = result[index]
            result[index] = ScriptBlock(turns: block.turns, name: block.name, text: block.text,
                colorIndex: block.colorIndex, issues: block.issues + [issue], edited: block.edited)
        }
        return result
    }

    public func affectedTurns(in block: ScriptBlock, scope: SpeakerNameScope) -> [String] {
        if scope == .one { return block.turnIDs }
        return affectedTurns(block.id, scope: scope)
    }
    public mutating func rename(_ block: ScriptBlock, name: String, scope: SpeakerNameScope) throws {
        guard blocks().contains(where: { $0.turnIDs == block.turnIDs }),
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LibraryFailure.invalidInput }
        for id in affectedTurns(in: block, scope: scope) { turnNames[id] = name }
        revisionID = UUID().uuidString
    }
}

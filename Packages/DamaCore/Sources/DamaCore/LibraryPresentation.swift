import Foundation

/// In-memory derived values for one immutable, validated Script file.
/// The storage layer binds this to the exact file bytes, including all display overrides.
public final class ScriptReadingSnapshot: Sendable {
    public let blocks: [ScriptBlock]
    public let reviewEvents: [ScriptReviewEvent]
    public let speakerCountSummary: String
    public let speakerCountMismatch: Bool

    public init(script: LibraryScript) {
        blocks = script.blocks()
        reviewEvents = ScriptReviewEvent.forListening(script.transcript.reviewIssues.filter { $0.status == .open })
        speakerCountSummary = script.speakerCountSummary
        speakerCountMismatch = script.speakerCountMismatch
    }
}

/// Reading layout, separately versioned from model normalization.
public enum ScriptReadingPolicy {
    public static let algorithmVersion = "reading-v7"

    /// Legacy Soniox source-Turn segmentation. Reading-v7 no longer uses this guard.
    static func endsSentence(_ text: String) -> Bool {
        let closers = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'”’)]}」』"))
        let ending = text.trimmingCharacters(in: closers)
        guard let last = ending.last else { return false }
        if "?!。？！".contains(last) { return true }
        guard last == ".", !ending.hasSuffix("..") else { return false }
        return ending.dropLast().contains(where: \.isLetter)
    }
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
    public static let listeningPolicy = "review-events-v2"
    /// Initial listening-layout limits, not measured accuracy thresholds. Raw issue IDs remain intact.
    public static func forListening(_ issues: [ReviewIssue]) -> [Self] {
        grouped(issues, maximumGapUs: 1_000_000, maximumSpanUs: 30_000_000)
    }
    public static func grouped(_ issues: [ReviewIssue], maximumGapUs: Int64 = 0, maximumSpanUs: Int64 = .max) -> [Self] {
        let sorted = issues.sorted { ($0.startUs ?? Int64.max, $0.id) < ($1.startUs ?? Int64.max, $1.id) }
        var groups: [Self] = []
        for issue in sorted {
            if let start = issue.startUs, let end = issue.endUs, start <= end,
               let last = groups.last, let lastEnd = last.endUs, let first = last.startUs,
               start <= lastEnd || (start - lastEnd <= maximumGapUs && end - first <= maximumSpanUs) {
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
    public var startUs: Int64? { turns.compactMap(\.startUs).min() }
    public var endUs: Int64? { turns.compactMap(\.endUs).max() }
    public var turnIDs: [String] { turns.map(\.id) }
    public var isSpeech: Bool { turns.allSatisfy { $0.kind == .speech } }
    public var openIssues: [ReviewIssue] { issues.filter { $0.status == .open } }
    public var reviewEvents: [ScriptReviewEvent] { ScriptReviewEvent.grouped(openIssues) }
}

extension LibraryScript {
    public var detectedSpeakerCount: Int { Set(transcript.words.compactMap(\.speakerId)).count }
    public var speakerCountMismatch: Bool { input.speakerCount.map { $0 != detectedSpeakerCount } ?? false }
    public var speakerCountSummary: String {
        let expected = input.speakerCount.map { "예상 \($0)명 · " } ?? "예상 미입력 · "
        return expected + "감지 \(detectedSpeakerCount)명" + (speakerCountMismatch ? " · 화자 구분 검수 필요" : " · 인원 일치만으로 정확도를 보장하지 않습니다")
    }
    public var speakerCountApplication: String {
        if transcript.provenance.engine == .managedSoniox {
            if input.sonioxContext == true, let count = input.sonioxSpeakerCountHint { return "Soniox에 \(count)명 힌트 전송 · 강제 지정 아님" }
            return "Soniox 자동 판단 · 화자 수 힌트 미전송"
        }
        return input.speakerCount.map { "pyannote에 \($0)명 제약 전달" } ?? "자동 판단"
    }

    /// Hard boundary guard shared by automatic and manual reading layout.
    public func canJoinParagraph(before turnID: String) -> Bool {
        guard !transcript.revision.humanEdited,
              let i = transcript.turns.firstIndex(where: { $0.id == turnID }), i > 0 else { return false }
        guard let previous = transcript.turns[..<i].last(where: { $0.kind == .speech }) else { return false }
        let next = transcript.turns[i]
        return canJoin(previous, next, previousName: name(for: previous), nextName: name(for: next))
    }
    private func canJoin(_ previous: TranscriptTurn, _ next: TranscriptTurn, previousName: String, nextName: String) -> Bool {
        guard !transcript.revision.humanEdited else { return false }
        guard previous.kind == .speech, next.kind == .speech,
              let speaker = previous.speakerId, speaker == next.speakerId,
              previousName == nextName,
              let start = previous.startUs, let end = previous.endUs,
              let nextStart = next.startUs, let nextEnd = next.endUs,
              start <= end, nextStart <= nextEnd, start <= nextStart else { return false }
        // Reading follows transcribed speaker changes. Evidence-only detections and
        // nested punctuation times remain in the source without splitting the body.
        return true
    }

    public mutating func setParagraphBreak(before turnID: String, split: Bool?) throws {
        guard !(paragraphEdits ?? []).contains(where: { $0.turnIDs.contains(turnID) }) else { throw LibraryFailure.invalidInput }
        guard let turn = transcript.turns.first(where: { $0.id == turnID }), turn.kind == .speech,
              split != false || canJoinParagraph(before: turnID) else { throw LibraryFailure.invalidInput }
        if paragraphBreaks == nil { paragraphBreaks = [:] }
        paragraphBreaks?[turnID] = split
        revisionID = UUID().uuidString
    }

    public func colorIndex(for speakerID: String?) -> Int? {
        guard let speakerID else { return nil }
        var seen = Set<String>(), order: [String] = []
        for turn in transcript.turns {
            if let id = turn.speakerId, seen.insert(id).inserted { order.append(id) }
        }
        return order.firstIndex(of: speakerID).map { $0 % 10 }
    }

    public func blocks() -> [ScriptBlock] {
        // Freeze the exact source membership of human paragraphs, independent of punctuation/AI.
        let owners = Dictionary((paragraphEdits ?? []).flatMap { edit in edit.turnIDs.map { ($0, edit.id) } }, uniquingKeysWith: { a, _ in a })
        let edits = Dictionary((paragraphEdits ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
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
            if showsOriginal != true, let text = correction?.edits.first(where: { $0.turnID == turn.id })?.effectiveText { return text }
            return turn.wordIds.compactMap { words[$0] }.sorted { $0.ordinal < $1.ordinal }
                .map { $0.prefix + ($0.editedText ?? $0.text) }.joined()
        }
        let texts = Dictionary(uniqueKeysWithValues: transcript.turns.map { ($0.id, currentText($0)) })
        let preservesSourceSpacing = transcript.provenance.engine == .hybridSonioxPyannote || transcript.provenance.engine == .managedSoniox || transcript.provenance.engine == .hybridPyannoteQwen
        func appended(_ current: String, _ next: String) -> String {
            let needsSpace = !preservesSourceSpacing && !current.isEmpty && !next.isEmpty && current.last?.isWhitespace == false && next.first?.isWhitespace == false
            return current + (needsSpace ? " " : "") + next
        }
        func mayJoin(_ previous: TranscriptTurn, _ next: TranscriptTurn) -> Bool {
            guard canJoin(previous, next, previousName: displayName(previous), nextName: displayName(next)) else { return false }
            if owners[previous.id] != nil || owners[next.id] != nil { return owners[previous.id] == owners[next.id] }
            if let split = paragraphBreaks?[next.id] { return !split }
            return true
        }
        var groups: [[TranscriptTurn]] = []
        var groupTexts: [String] = []
        for turn in transcript.turns where turn.kind == .speech {
            let text = texts[turn.id] ?? ""
            if let previous = groups.last?.last, let accumulated = groupTexts.last, mayJoin(previous, turn) {
                groups[groups.count - 1].append(turn)
                groupTexts[groupTexts.count - 1] = appended(accumulated, text)
            } else { groups.append([turn]); groupTexts.append(text) }
        }
        var result: [ScriptBlock] = []
        var attached = Set<String>()
        let issueIndex = Dictionary(uniqueKeysWithValues: transcript.reviewIssues.enumerated().map { ($0.element.id, ($0.offset, $0.element)) })
        for (groupIndex, group) in groups.enumerated() {
            let ids = Set(group.flatMap(\.reviewIssueIds) + group.flatMap(\.wordIds).flatMap { words[$0]?.reviewIssueIds ?? [] })
            let issues = ids.compactMap { issueIndex[$0] }.sorted { $0.0 < $1.0 }.map(\.1)
            attached.formUnion(issues.map(\.id))
            let paragraph = owners[group[0].id].flatMap { edits[$0] }
            let text = paragraph?.text ?? groupTexts[groupIndex]
            // Trim only the reading paragraph. Keep source tokens and user-authored spacing intact.
            let hasHumanText = paragraph != nil || transcript.revision.humanEdited || group.contains {
                turnTexts[$0.id] != nil || $0.wordIds.contains { words[$0]?.editedText != nil }
            }
            let displayText = hasHumanText ? text : text.trimmingCharacters(in: .whitespacesAndNewlines)
            result.append(ScriptBlock(turns: group, name: displayName(group[0]), text: displayText,
                colorIndex: group[0].speakerId.flatMap { colors[$0] }, issues: issues,
                edited: paragraph != nil || group.contains { turnTexts[$0.id] != nil }))
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

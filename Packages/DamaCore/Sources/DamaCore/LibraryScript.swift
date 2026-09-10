import Foundation

public struct ConversionNotes: Codable, Sendable, Equatable {
    public var speakerCount: Int?
    public var context: String
    public var reference: String
    public init(speakerCount: Int? = nil, context: String = "", reference: String = "") {
        self.speakerCount = speakerCount; self.context = context; self.reference = reference
    }
    public func validate() throws {
        if let speakerCount, speakerCount < 1 { throw LibraryFailure.invalidInput }
    }
}

public enum LibraryFailure: Error, Sendable {
    case invalidInput, invalidScript, changedFile, unsafePath, missingFile
}
public enum SpeakerNameScope: String, CaseIterable, Sendable { case one, from, all }

/// An editable library file wrapping the unchanged normalized v1 contract.
/// Overrides never modify provider words, timestamps, confidence maps or speaker attribution.
public struct LibraryScript: Codable, Sendable, Identifiable {
    public let format: String
    public let id: String
    public var revisionID: String
    public var title: String
    public let createdAt: Date
    public let recordedAt: Date?
    public let dateSource: String
    public let timeZoneID: String
    public let input: ConversionNotes
    public let transcript: TranscriptDocument
    public var turnNames: [String: String]
    public var turnTexts: [String: String]

    public init(transcript: TranscriptDocument, title: String, recordedAt: Date?, dateSource: String,
                timeZoneID: String = TimeZone.current.identifier, input: ConversionNotes,
                createdAt: Date = Date()) throws {
        self.format = "dama-library-script-1"
        self.id = transcript.runId
        self.revisionID = UUID().uuidString
        self.title = title
        self.createdAt = createdAt; self.recordedAt = recordedAt; self.dateSource = dateSource
        self.timeZoneID = timeZoneID; self.input = input; self.transcript = transcript
        self.turnNames = [:]; self.turnTexts = [:]
        try validate()
    }
    public func validate() throws {
        try input.validate()
        try TranscriptValidator().validate(transcript)
        let ids = Set(transcript.turns.map(\.id))
        guard format == "dama-library-script-1", id == transcript.runId,
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              UUID(uuidString: revisionID) != nil,
              Set(turnNames.keys).isSubset(of: ids), Set(turnTexts.keys).isSubset(of: ids),
              turnNames.values.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        else { throw LibraryFailure.invalidScript }
    }
    public func name(for turn: TranscriptTurn) -> String {
        if let name = turnNames[turn.id] { return name }
        guard let id = turn.speakerId else { return "화자 미확정" }
        // Preserve names already manually edited in a legacy current revision.
        if transcript.revision.humanEdited,
           let speaker = transcript.speakers.first(where: { $0.id == id }),
           speaker.displayName != speaker.providerId, !speaker.displayName.hasPrefix("화자 ") {
            return speaker.displayName
        }
        var speakers: [String] = []
        for t in transcript.turns {
            if let s = t.speakerId, !speakers.contains(s) { speakers.append(s) }
        }
        guard let i = speakers.firstIndex(of: id) else { return "화자 미확정" }
        return "Speaker \(Self.letters(i))"
    }
    private static func letters(_ index: Int) -> String {
        var n = index + 1, result = ""
        while n > 0 { n -= 1; result = String(UnicodeScalar(65 + n % 26)!) + result; n /= 26 }
        return result
    }
    public func text(for turn: TranscriptTurn) -> String {
        if let text = turnTexts[turn.id] { return text }
        return originalText(for: turn)
    }
    public func originalText(for turn: TranscriptTurn) -> String {
        if turn.kind == .missingSpeech { return turn.markerText ?? "[음성 감지 / 전사 누락 의심]" }
        let ids = Set(turn.wordIds)
        return transcript.words.filter { ids.contains($0.id) }.sorted { $0.ordinal < $1.ordinal }
            .map { $0.prefix + ($0.editedText ?? $0.text) }.joined()
    }
    public func modelText(for turn: TranscriptTurn) -> String {
        if turn.kind == .missingSpeech { return turn.markerText ?? "[음성 감지 / 전사 누락 의심]" }
        let ids = Set(turn.wordIds)
        return transcript.words.filter { ids.contains($0.id) }.sorted { $0.ordinal < $1.ordinal }
            .map { $0.prefix + $0.text }.joined()
    }
    public func affectedTurns(_ turnID: String, scope: SpeakerNameScope) -> [String] {
        guard let index = transcript.turns.firstIndex(where: { $0.id == turnID }) else { return [] }
        let speaker = transcript.turns[index].speakerId
        if scope == .one || speaker == nil { return [turnID] }
        return transcript.turns.enumerated().filter {
            $0.element.speakerId == speaker && (scope == .all || $0.offset >= index)
        }.map { $0.element.id }
    }
    public mutating func rename(_ turnID: String, name: String, scope: SpeakerNameScope) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LibraryFailure.invalidInput }
        let ids = affectedTurns(turnID, scope: scope)
        guard !ids.isEmpty else { throw LibraryFailure.invalidInput }
        for id in ids { turnNames[id] = name }
        revisionID = UUID().uuidString
    }
    public mutating func editText(_ turnID: String, text: String) throws {
        guard transcript.turns.contains(where: { $0.id == turnID && $0.kind == .speech }) else { throw LibraryFailure.invalidInput }
        turnTexts[turnID] = text; revisionID = UUID().uuidString
    }
    public mutating func renameTitle(_ title: String) throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LibraryFailure.invalidInput }
        self.title = title; revisionID = UUID().uuidString
    }
    public static func timestamp(_ us: Int64?) -> String {
        guard let us, us >= 0 else { return "시간 미확인" }
        let ms = us / 1_000
        return String(format: "%02lld:%02lld:%02lld.%03lld", ms / 3_600_000, (ms / 60_000) % 60, (ms / 1_000) % 60, ms % 1_000)
    }
    public func markdown() throws -> Data {
        try validate()
        let date = DateFormatter()
        date.locale = Locale(identifier: "en_US_POSIX")
        date.timeZone = TimeZone(identifier: timeZoneID) ?? TimeZone(secondsFromGMT: 0)
        date.dateFormat = "yyyy-MM-dd HH:mm:ss XXX"
        var lines = ["# \(Self.escape(title))", "", "## 녹음 정보", "",
                     "- 녹음 날짜·시간: \(recordedAt.map { date.string(from: $0) } ?? "미확인")",
                     "- 시간대: \(Self.escape(timeZoneID))", "- 날짜 근거: \(Self.escape(dateSource))",
                     "- 녹음 길이: \(Self.timestamp(transcript.durationUs))",
                     "- 스크립트 생성: \(date.string(from: createdAt))", "",
                     "## 변환 전 입력 정보", "", "- 참여 화자 수: \(input.speakerCount.map(String.init) ?? "자동 (미입력)")",
                     "", "### 맥락", "", Self.escape(input.context.isEmpty ? "미입력" : input.context),
                     "", "### 참고 정보", "", Self.escape(input.reference.isEmpty ? "미입력" : input.reference),
                     "", "맥락·참고 정보는 사용자가 입력한 로컬 참고 메모입니다.", "", "## 스크립트", ""]
        for turn in transcript.turns {
            lines += ["### [\(Self.timestamp(turn.startUs)) – \(Self.timestamp(turn.endUs))] \(Self.escape(name(for: turn)))", "",
                      Self.escape(text(for: turn)), ""]
            if turnTexts[turn.id] != nil { lines += ["*사용자 수정 발화 · 시간은 원 모델 구간이며 재정렬하지 않았습니다.*", ""] }
            for issue in transcript.reviewIssues where turn.reviewIssueIds.contains(issue.id) {
                lines += ["> 검수: \(Self.escape(issue.kind.rawValue))", ""]
            }
        }
        return Data(lines.joined(separator: "\n").utf8)
    }
    private static func escape(_ text: String) -> String {
        let special = Set("\\`*_{}[]<>()#+-.!|&")
        return text.map { special.contains($0) ? "\\\($0)" : String($0) }.joined()
    }
}

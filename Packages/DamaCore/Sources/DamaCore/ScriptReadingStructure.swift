import Foundation

/// Source-based joins. Punctuation is typography, not an acoustic speaker boundary.
/// Human paragraph membership and explicit breaks are applied separately by blocks().
struct ScriptReadingStructure {
    let words: [String: TranscriptWord]
    let decorations: Set<String>
    let opening: Set<String>
    let joinableBefore: Set<String>

    init(_ script: LibraryScript) {
        let words = Dictionary(uniqueKeysWithValues: script.transcript.words.map { ($0.id, $0) })
        self.words = words
        let turns = script.transcript.turns.filter { $0.kind == .speech }
        var base = script; base.turnNames = [:]
        var names: [String: String] = [:]
        for turn in script.transcript.turns {
            if let id = turn.speakerId, names[id] == nil { names[id] = base.name(for: turn) }
        }
        func name(_ turn: TranscriptTurn) -> String {
            script.turnNames[turn.id] ?? turn.speakerId.flatMap { names[$0] } ?? "화자 미확정"
        }
        var decorations = Set<String>(), opening = Set<String>()
        let openCharacters = CharacterSet(charactersIn: "([{「『‘“").union(.whitespacesAndNewlines)
        for turn in turns {
            let tokens = turn.wordIds.compactMap { words[$0] }
            guard !tokens.isEmpty, tokens.allSatisfy({ $0.tokenKind == .punctuation && $0.editedText == nil }),
                  script.turnTexts[turn.id] == nil else { continue }
            decorations.insert(turn.id)
            let text = tokens.map { $0.prefix + $0.text }.joined()
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               text.unicodeScalars.allSatisfy(openCharacters.contains) { opening.insert(turn.id) }
        }
        self.decorations = decorations
        self.opening = opening
        let sourceSpacing = script.transcript.provenance.engine == .hybridSonioxPyannote || script.transcript.provenance.engine == .managedSoniox || script.transcript.provenance.engine == .hybridPyannoteQwen
        var joins = Set<String>(), anchor: TranscriptTurn?
        for (i, next) in turns.enumerated() {
            defer { if !decorations.contains(next.id) { anchor = next } }
            guard i > 0, !script.transcript.revision.humanEdited else { continue }
            let previous = turns[i - 1]
            // A manually named decoration must retain that name and boundary.
            if (decorations.contains(next.id) || decorations.contains(previous.id)),
               (script.turnNames[next.id] != nil || script.turnNames[previous.id] != nil),
               name(next) != name(previous) { continue }
            if decorations.contains(next.id) {
                if !opening.contains(next.id) || opening.contains(previous.id) { joins.insert(next.id) }
                continue
            }
            if decorations.contains(previous.id), opening.contains(previous.id) || anchor == nil {
                joins.insert(next.id); continue
            }
            guard let left = anchor,
                  let a = left.startUs, let b = left.endUs, let c = next.startUs, let d = next.endUs,
                  a <= b, c <= d, a <= c, name(left) == name(next) else { continue }
            if let speaker = left.speakerId, speaker == next.speakerId { joins.insert(next.id); continue }
            // Unknown is still unknown. Join only adjacent subword pieces of one orthographic word.
            guard sourceSpacing, left.speakerId == nil, next.speakerId == nil,
                  let last = left.wordIds.last.flatMap({ words[$0] }),
                  let first = next.wordIds.first.flatMap({ words[$0] }),
                  last.tokenKind == .lexical, first.tokenKind == .lexical,
                  first.ordinal == last.ordinal + 1,
                  (last.prefix + last.text).last?.isWhitespace == false,
                  (first.prefix + first.text).first?.isWhitespace == false,
                  last.asrSpeakerLabel == first.asrSpeakerLabel else { continue }
            joins.insert(next.id)
        }
        self.joinableBefore = joins
    }

    func anchor(in turns: [TranscriptTurn]) -> TranscriptTurn? {
        turns.first { !decorations.contains($0.id) }
    }
}

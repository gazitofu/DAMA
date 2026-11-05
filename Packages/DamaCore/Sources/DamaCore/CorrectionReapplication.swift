import Foundation

extension ContextCorrection {
    /// Reuse saved model proposals only on explicit application. Loading history never changes it.
    public static func reapplyingPending(in script: LibraryScript) throws -> ScriptCorrection? {
        try script.validate()
        guard script.snapshotTitle == nil, let previous = script.correction, previous.state == .completed else { return nil }
        let owned = script.humanOwnedTurnIDs.union(script.deletedTurnIDs)
        let turns = Dictionary(uniqueKeysWithValues: script.transcript.turns.map { ($0.id, $0) })
        var changed = false
        let edits = try previous.edits.map { edit -> CorrectionEdit in
            guard !owned.contains(edit.turnID), let decisions = edit.changes, let unresolved = edit.unresolved,
                  decisions.contains(where: { !$0.applied && $0.change.certain }) else { return edit }
            guard let turn = turns[edit.turnID], script.modelText(for: turn) == edit.original else { throw LibraryFailure.invalidScript }
            let source = CorrectionTurn(id: turn.id, speakerID: turn.speakerId, startUs: turn.startUs, endUs: turn.endUs, text: edit.original)
            // Turn-wide uncertainty was already expanded into saved unresolved spans by the validator.
            let reply = CorrectionReply.Turn(id: turn.id, text: edit.text, certain: true, reason: "",
                changes: decisions.map(\.change), unresolved: unresolved)
            guard let updated = try CorrectionSpans.validated(reply, source: source, input: previous.input),
                  updated.effectiveText != edit.effectiveText else { return edit }
            changed = true
            return updated
        }
        guard changed else { return nil }
        var result = ScriptCorrection(input: previous.input,
            engine: previous.engine + " · 저장 후보 반영 " + version, state: .completed)
        result.edits = edits; result.speakerNames = previous.speakerNames; result.nameEvidence = previous.nameEvidence
        result.completedChunks = previous.completedChunks; result.totalChunks = previous.totalChunks
        result.completedAt = Date()
        return result
    }
}

# T-04 result — implementation and reviews complete

Updated: 2026-09-09

## Status

- T-04 implementation: complete within the delegated paths.
- Initial focused Core verification: PASS, 47 tests with 0 failures.
- Required `bash scripts/check.sh`: PASS with no SKIP.
- No app/UI, exporter, scripts, fixtures, SSOT, plan, git, audio, API, Keychain, signing, notarization, or native UI launch work.
- Existing T02/T03 source and tests, including immutable `DomainContracts.swift`, were preserved.
- Main review focused verification: PASS, 51 tests with 0 failures.
- Main review `bash scripts/check.sh`: PASS with no SKIP.
- Final integration review implementation: complete.
- Final integration focused Core verification: PASS, 54 tests with 0 failures.
- Final integration `bash scripts/check.sh`: PASS with no SKIP.

## Changed files

- `Packages/DamaCore/Sources/DamaCore/TranscriptEditing.swift`
- `Packages/DamaCore/Tests/DamaCoreTests/TranscriptEditingTests.swift`
- `notes/m0-fixture-review/codex/t04-result.md`

## Actual public interfaces

- `TranscriptEditOperation`: `assignWords`, `renameSpeaker`, `replaceWordText`, `revertWordText`, `splitTurn`, `acknowledgeIssue`, `reopenIssue`.
- `TranscriptEditor.applying(_:to:model:) throws -> TranscriptDocument`: value-based editing that validates the complete result before returning it.
- `TranscriptEditingError(code:context:)`: typed invalid-operation, busy/history, storage, and state-conflict errors without transcript content.
- `TranscriptIssueOrdering.openIssues(in:)` and `nextOpenIssue(after:in:)`.
- `EditingRevisionIdentity` and `EditingRevisionFactory`; the default produces a safe UUID revision ID and ISO-8601 save time.
- `TranscriptEditingSession.open(repository:sessionId:revisionFactory:)` loads the active revision and its explicit immutable Run model through the existing `FileSessionRepository` interfaces.
- `TranscriptEditingSession.state()`, `apply(_:)`, `undo()`, `redo()`, `retry()`, and `cancelFailedSave()`.
- `TranscriptEditingState`: committed document, current draft, `isDirty`, `isSaving`, typed failure, `canUndo`, `canRedo`, and `canExport`.

## Editing behavior

- Word assignment requires a nonempty duplicate-free set of known word IDs and either a known speaker or explicit null. It changes only current `speakerId`/`assignmentSource`, plus the Turn subdivision required for uniform current-speaker membership.
- Each preexisting Turn is processed independently. A mixed Turn is subdivided into contiguous speaker groups; existing boundaries and markers are retained, and adjacent same-speaker Turns are never merged.
- Renaming changes exactly one speaker `displayName`. Provider labels and all other speakers remain unchanged; the operation has no cross-Run mapping behavior.
- Text replacement changes only one `editedText` and sets `timingOrigin = inheritedUnaligned`. Original `text` and `prefix` remain. Explicit reversion clears `editedText` and restores the immutable model Word's recorded timing origin, including a tested non-`.model` origin.
- Explicit split requires an existing speech Turn and an internal word boundary. Splitting at the first word, splitting a marker, unknown IDs, empty selections, duplicate selections, empty names, and no-op changes throw before any save.
- Editor inputs and immutable models are validated before any dictionary construction. Duplicate Word IDs therefore produce typed `stateConflict` rather than trapping, while the caller's value remains unchanged.
- A newly split/subdivided segment derives its range only from its own timed Words, using the minimum start and maximum end across all timed members. A segment with no timed Words stores both endpoints as null; an unchanged single-group Turn retains its original range without gratuitous recomputation.
- Acknowledledge/reopen changes only the selected issue status. It does not assign an unknown word, alter a marker, change another issue, or set `Turn.reviewed`.

## Session state and revision transitions

- Every successful apply, Undo, and Redo stamps and commits a new immutable revision with the current committed revision as `baseRevisionId`, the current `runId` as `sourceRunId`, `humanEdited = true`, and an ISO-8601 `savedAt`.
- Successful apply appends an Undo entry and clears Redo. Successful Undo moves the same before/after history entry to Redo; successful Redo moves it back to Undo. The new persisted revision contains the restored content rather than reactivating or overwriting an old file.
- Actor reentrancy is guarded with `isSaving`: overlapping apply/Undo/Redo/retry/cancel commands throw `busy`. `canExport` is false while saving or while a failed dirty draft is pending.
- Save failure keeps the intended draft and its revision identity, retains the prior committed document, records an explicit failure, and does not update history stacks.
- Retry first resolves actual active storage. It accepts the exact intended revision if the pointer succeeded uncertainly, retries the same intended bytes when the old committed revision remains active, and rejects an unrelated active revision.
- Cancel first reloads actual active storage. If the old committed revision is still active, it restores the prior in-memory content. If the intended revision actually became active before an ambiguous error, cancel writes the prior content as a new immutable revision based on that intended revision and becomes clean/exportable only after the restoration commit succeeds. Unrelated active state or restoration failure retains an explicit recoverable failure. No files are deleted.
- A failed restoration retains that exact restoration snapshot and revision identity. A later retry or cancel reconciles an already-installed identical restoration or commits the same pending restoration when the edited revision is still active; neither path mutates Undo/Redo history or claims exportability early.
- Undo/Redo history is intentionally process-local. Reopening loads the persisted active content and explicit old snapshots, but correctly exposes no reconstructed Undo/Redo stack.
- `TranscriptEditingSession.open` uses `loadWithRecovery`; recovery notices remain available through the same `FileSessionRepository.recoveryNotices()` actor queue. T06 can consume that public route after opening rather than inventing another notice channel.

## Issue ordering

- Only open issues are included.
- Timed issues sort by increasing `startUs`; ties sort by ID. Untimed issues follow all timed issues and sort by ID.
- `nextOpenIssue(after:nil)` returns the first or nil when none exist. After the last it returns nil. An ID absent from the current ordered-open set throws `unknownIssue`.
- Fixed evidence includes `i1` at 850000µs before 2100000µs candidates, ID tie order, and null time last.

## Verification

Final command:

```sh
bash scripts/check.sh
```

Result: exit 0, `backpressure OK`, no SKIP.

- Contract/regression: 29 tests PASS.
- DamaCore contract copy: byte-exact PASS.
- Swift 6 contract compile and fixture roundtrip: PASS.
- Core: 54 tests, 0 failures. This comprises 38 prior tests and 16 T-04 editing/session tests.
- Unsigned Dama Debug build: PASS. This is compile evidence only, not signing/distribution or native UI proof.

T-04 tests use the existing synthetic normalized fixture in memory and unique temporary repository roots. They cover:

- w5 assignment to C while preserving `text = 네`, model B, overlap, and source evidence; explicit null restoration;
- necessary t1 subdivision without remerging and marker preservation;
- Run-local speaker rename and unchanged provider labels/other Run value;
- single text replacement, explicit reversion from immutable timing metadata, Undo/Redo, original text/prefix, and reopened persistence;
- t1 split to five Turns, Undo to four, Redo to five, subsequent assignment Undo/Redo, and explicit old snapshot reload after reopening;
- i1-only acknowledgement/reopen, i2 open, w5 null, marker and `Turn.reviewed` unchanged;
- deterministic timed/tie/null issue ordering and first/next/last/none/unknown behavior;
- invalid and empty operations leaving the active revision unchanged;
- real temp-root repository fault injection after final revision installation and during partial temp write, exact-revision retry, cancel, dirty/failure/export flags, and persisted active state;
- an intentionally suspended save against the real repository rejecting an overlapping command as busy.
- null-timed w1 (`timingOrigin = none`) split and assignment: its segment remains null/null while timed w2 remains 400000–700000µs; repository commit, restart, original Word evidence, and model-based text reversion remain valid;
- duplicate-Word input returning a typed failure without mutation or process trap;
- a real repository wrapper that persists the intended revision then throws once, followed by cancel reconciliation and a persisted restoring revision;
- a handshake/permit save gate proving the save reached suspension before the overlap assertion;
- two separately persisted Runs with identical provider labels, where a session rename and reopen leave the other Run's names and evidence unchanged;
- fresh editor open after pointer recovery leaving the notice visible through `repository.recoveryNotices()`.
- cancellation recovery when the edit commit and then the first restoration commit each persist before throwing, plus recovery when the first restoration attempt throws before commit;
- non-monotonic Word end times proving subdivided Turn bounds use the minimum timed start and maximum timed end without changing Word timing.

## Failure classification

- First focused compile found a Swift restriction on `Self` in a default argument and Swift 6 ambiguity selecting the `sorted` overload. Both were implementation compile defects and were fixed directly.
- The final-integration focused run initially found one invalid test-fixture Turn bound; correcting that fixture setup produced 54/0. This was test construction, not a product failure.
- Initial focused/full runs passed 47/0; main-review focused/full runs passed 51/0; final-integration focused Core passed 54/0.
- Final `bash scripts/check.sh` passed all four axes on its first run for this code revision. No filesystem/environment denial or known Xcode sandbox failure occurred; no retry or bypass was attempted.

## Remaining limitations

- No exporter is implemented in T-04. `canExport` only exposes whether later export code may consume the committed state.
- Undo/Redo history is not reconstructed after process restart; only the resulting immutable documents and active revision persist, as explicitly allowed for M0.
- The session serializes one actor instance. T03's documented cross-process and power-loss durability limits remain unchanged.
- No app/UI command wiring, visual/VoiceOver verification, real audio/API access, signing, notarization, distribution, or real-device accuracy claim is included.

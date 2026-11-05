# T-05 result — implementation and main review complete

Updated: 2026-09-09

## Status

- Contract and implementation review: complete.
- Exporter implementation: complete within delegated paths.
- Focused Core verification: PASS, 61 tests with 0 failures.
- Required `bash scripts/check.sh`: PASS with no SKIP.
- Main review implementation: complete.
- Main review focused Core verification: PASS, 63 tests with 0 failures.
- Main review `bash scripts/check.sh`: PASS with no SKIP.
- Work is limited to the T-05 delegated paths; no app/UI, SSOT, fixture, plan, script, project, or git changes are included.

## Implementation milestone

- Added explicit automatic/current export selections carrying session, Run, and revision identity.
- JSON uses the existing normalized codec; TXT preserves Turn order, prefixes, edited-or-original text, markers, unknown speaker/time, issue status, overlap warnings, and provider-confidence availability without presenting scores as probability percentages.
- Export is coordinated inside `TranscriptEditingSession`: saving, dirty/failed state, and an in-flight export prevent a competing export/edit transition. The state reports export separately from saving.
- Repository-aware destination validation rejects direct and symlink aliases into internal storage. The exporter validates/encodes before writing, uses a temporary sibling, and replaces the selected destination only after the temporary bytes are complete.
- Focused verification initially found a symlink-alias assertion failure for a nonexistent final filename. Resolving the existing parent before appending the final component fixed this implementation defect; the repeated focused run passed 61/61.

## Changed files

- `Packages/DamaCore/Sources/DamaCore/TranscriptExporting.swift`
- `Packages/DamaCore/Sources/DamaCore/TranscriptEditing.swift`
- `Packages/DamaCore/Sources/DamaCore/FileSessionRepository.swift`
- `Packages/DamaCore/Tests/DamaCoreTests/FileSessionRepositoryTests.swift`
- `Packages/DamaCore/Tests/DamaCoreTests/TranscriptExportingTests.swift`
- `notes/m0-fixture-review/codex/t05-result.md`

`Packages/DamaCore/Sources/DamaCore/DomainContracts.swift`, app/UI/project files, scripts, fixtures, SSOT, plan, git state, and main-owned task prompts were not modified.

## Actual public interfaces

- `TranscriptExportVersion`: `.automatic`, `.current`.
- `TranscriptExportFormat`: `.json`, `.text`.
- `TranscriptExportSelection(version:sessionId:runId:revisionId:)` explicitly identifies the displayed document; the session rejects any mismatch before writing.
- `TranscriptExportResult(selection:format:)` reports exactly which selection and format completed, without returning an internal or destination path.
- `TranscriptExporter.data(for:selection:format:) throws -> Data` validates the selected document and renders JSON/TXT without changing it.
- `TranscriptExporter.write(_:to:) throws` accepts only an explicit absolute file URL and performs temporary-sibling installation.
- `TranscriptExportFaultStage`: `.beforeTemporaryWrite`, `.beforeDestinationReplacement`; `TranscriptExporter.init(faultInjector:)` supports deterministic pure-test failures.
- `TranscriptExportError(code:context:)` exposes sanitized `invalidSelection`, `invalidDocument`, `unsafeDestination`, and `writeFailure` categories.
- `TranscriptEditingSession.export(selection:format:to:exporter:) async throws -> TranscriptExportResult` coordinates selection, destination validation, rendering, and writing under the editing actor.
- `TranscriptEditingState.isExporting` distinguishes export activity from `isSaving`; `canExport`, Undo, and Redo are false while export is active.
- `FileSessionRepository.validateExportDestination(_:) throws` rejects lexical or resolved destinations at/below its injected or Application Support root, including a symlinked parent.

## Export behavior

- Automatic export uses the exact immutable model already loaded for the session's Run. Current export uses the exact committed revision. The request must match document session, Run, and revision IDs; a stale displayed identity is rejected without creating the destination.
- A dirty, failed, or saving session cannot export. While export is suspended, edits are rejected as busy; while a save is suspended, export is rejected before writing. Successful export does not create a revision or touch repository state.
- JSON is produced only by `NormalizedTranscriptCodec.encode`. It therefore contains the complete normalized schema, explicit nullable keys, original/model/current evidence, provenance, marker, issue status, and revision metadata, with no export-only schema keys.
- TXT begins with separate provenance/version metadata, including synthetic status, selected version, identity, engine, and the exact warning `공급자 화자 점수와 시간 정렬 점수는 정답 확률이 아닙니다.`; no percentage symbol is used.
- Each Turn remains a blank-separated block headed by `[start–end] displayName`. A partial or wholly unavailable range becomes `[시간 미확인]`; null speaker is exactly `화자 미확정`.
- Speech content concatenates each selected Word's `prefix + (editedText ?? text)` in stored Turn order. It does not deduplicate repetitions or correct/redact arbitrary transcript words.
- A `missingSpeech` Turn emits its `markerText` verbatim as its own block and never synthesizes a Word. Issue kind/status, overlap limitations, unknown assignment, confidence maps, and missing confidence remain visible. Referenced regular or exclusive evidence is emitted as one labeled line per interval with interval ID/time/source and that interval's independently sorted map or explicit `미제공`; maps are never flattened or normalized. Marker issue source intervals are resolved through the same ID contract. Acknowledgement changes the displayed issue status but does not remove overlap/unknown warnings or claim accuracy.
- A block containing `editedText` with `timingOrigin = inheritedUnaligned` carries a separate `시간 재정렬 안 됨` annotation. The automatic original has no such annotation, and replacement content still uses the exact stored prefix without trimming/correction.
- Destination bytes are fully rendered first. The exporter writes a unique temporary sibling, reads it back, then uses same-directory atomic rename. A failed temporary write or replacement removes only the temporary file and preserves an existing destination.
- Output contains no destination URL or repository root. Tests ground this in actual storage/destination paths containing a sentinel while preserving suspicious-looking user transcript text verbatim. M0's export/session interfaces accept no credentials or signed URLs, so no credential-handling path is claimed as exercised. Errors contain symbolic context only, not transcript text or absolute paths.

## Numeric mini-audit linkage to T-02

- Source timestamps remain `Int64` microseconds. TXT calls the existing integer-only `TranscriptTimePresentation.timestamp(_:)`; it does not rewrite model values.
- Fixed export assertions retain T-02's `850000µs → 00:00:00.850` and `990000µs → 00:00:00.990`, yielding the marker header `[00:00:00.850–00:00:00.990]` and preserving the 140ms interval.
- The fixture's unknown overlapping Word remains `[00:00:02.100–00:00:02.300] 화자 미확정`.
- A valid nil-timed variant emits `[시간 미확인]` and retains nil Word times. Repeated `네 네` is emitted twice with its prefixes intact.
- The marker's d2 evidence is independently labeled. The d4 confidence map remains `SPEAKER_01=65` and `SPEAKER_02=60` (sum 125, not normalized), while d5 is a separate labeled interval with `미제공`. Repeated provider labels therefore retain interval identity; JSON preserves the exact map/null representation.

## Verification

Focused commands used the repository-local SwiftPM scratch/cache/module-cache paths and disabled external dependency/keychain access. Initial result was 61 tests; after main-review additions the final focused result was 63 tests, 0 failures: 19 repository, 16 editing, 8 exporting, 17 loading/validation, and 3 time-presentation tests.

Final command:

```sh
bash scripts/check.sh
```

Result: exit 0, `backpressure OK`, no SKIP.

- Contract/regression: 29 tests PASS.
- DamaCore contract copy: byte-exact PASS.
- Swift 6 contract compile and fixture roundtrip: PASS.
- Core: PASS; final focused measurement was 63 tests, 0 failures.
- Unsigned Dama Debug build: PASS. This is compile evidence only, not signing/distribution or native UI proof.

The eight T-05 tests cover the four automatic/current × JSON/TXT combinations; normalized JSON reload; edited versus immutable content and inherited-time warning; marker and A-marker-A ordering; interval-specific d2/d4/d5 confidence evidence; unknown speaker, overlap, issue acknowledgement, exact timestamps, nil times, and repeated words; explicit selection mismatch; successful new and existing user-selected destinations; direct, parent-symlink, and final-file-symlink internal-path rejection; injected and real write failures preserving prior data; actual path isolation without transcript-word redaction; a real failed dirty save blocking both export versions until retry; and both directions of in-flight save/export contention. The repository suite additionally covers a new nonexistent session below an escaping `Sessions` symlink and proves no outside directory is created.

## Failure classification

- The first focused run compiled successfully and ran 61 tests. Two assertions in one test failed because `URL.resolvingSymlinksInPath()` did not resolve the alias when the final destination did not yet exist. This was an implementation safety defect, not an environment denial.
- Destination validation was corrected to resolve the existing parent and then append the final filename. The next focused run passed 61/61.
- Main review generalized containment resolution to follow the nearest existing ancestor, including a final selected-file symlink, and added the review evidence above. The review-focused run passed 63/63 without a compiler or assertion failure.
- The initial and main-review `bash scripts/check.sh` runs each passed all four axes on their first run for their respective final code revision. No known Xcode sandbox failure, filesystem denial, unresolved assertion, retry, or sandbox bypass occurred.

## Remaining limitations

- T-05 implements no NSSavePanel or other interactive UI. The later app task must obtain the user-selected URL and normal overwrite confirmation, then call this Core API; the exporter invents no default destination.
- Atomic rename is same-volume because the temporary file is a sibling, but directory metadata is not `fsync`ed. This does not claim power-loss durability.
- Repository destination validation follows existing ancestors and final symlinks before writing, but an external process could still change filesystem symlinks between validation and write. There is no cross-process filesystem lock; T03's documented limits remain.
- TXT is a faithful human-readable projection, not the normalized contract. JSON remains the lossless machine-readable export for every field and nullable value.
- No app launch, native visual/VoiceOver flow, real audio/API/Keychain access, external transfer, signing, notarization, distribution, or Korean accuracy validation was performed or claimed.

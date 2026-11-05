# T-03 result — final integration review complete

Updated: 2026-09-09

## Status

- Initial T-03 implementation/backpressure: complete and recorded below.
- Main review follow-up implementation: complete.
- Focused Core verification after review fixes: PASS, 35 tests, 0 failures.
- Follow-up `bash scripts/check.sh`: PASS with no SKIP.
- Final integration review fixes: complete.
- Focused Core verification after final integration fixes: PASS, 38 tests, 0 failures.
- Final integration `bash scripts/check.sh`: PASS with no SKIP.
- No app/UI, git, SSOT, fixture, audio, API, Keychain, signing, or notarization changes/actions.
- `DomainContracts.swift` remains unchanged (`git diff --quiet` exit 0).

## Changed files

- `Packages/DamaCore/Sources/DamaCore/FileSessionRepository.swift`
- `Packages/DamaCore/Tests/DamaCoreTests/FileSessionRepositoryTests.swift`
- `notes/m0-fixture-review/codex/t03-result.md`

Main-owned untracked prompt/review files were observed and not modified.

## Actual public interfaces

- `public actor FileSessionRepository: TranscriptRepository`
  - `init(rootURL:faultInjector:)` injects an isolated root for tests.
  - `static applicationSupport(faultInjector:) throws` resolves `FileManager`'s user Application Support directory plus `com.gazitofu.Dama`; tests never call it or initialize real app storage.
  - Existing protocol signatures remain `load(sessionId:revisionId:)` and `commitRevision(_:)`.
  - `importSyntheticTranscript(_:)` imports only bytes accepted by `SyntheticTranscriptFixtureLoader`.
  - `loadModel(sessionId:runId:)` reads the explicit immutable automatic model for export consumers.
  - `loadWithRecovery(sessionId:revisionId:)` returns `SessionLoadResult` with an optional `SessionRecoveryNotice` without changing the protocol load signature.
  - `listSessions()` returns valid existing `SessionListing` values; filesystem enumeration/read failures are thrown rather than converted to empty history.
  - `recoveryNotices()` exposes notices retained by the actor for later UI consumption.
- `SessionRepositoryFaultStage`: `.afterPartialTemporaryRevisionWrite`, `.afterFinalRevisionInstallation`.
- `SessionRepositoryError` has typed, sanitized codes and symbolic context only; it does not include transcript contents or absolute storage paths.
- Result/value types: `SyntheticTranscriptImportResult`, `SessionLoadResult`, `SessionListing`, `SessionRecoveryNotice`, `SessionRecoveryReason`.

## Implemented storage behavior

- Layout is `Sessions/<session>/runs/<run>/raw/synthetic-normalized-input.json`, `normalized/model.json`, session-level `revisions/<revision>.json`, and `session.json` active pointer.
- Synthetic source bytes are preserved byte-for-byte. The raw name explicitly identifies synthetic normalized input and is never called a provider response. Canonically encoded model and revision bytes are immutable.
- Imports preserve `isSynthetic`, engine, and provenance. Reimport is idempotent only when source/model/revision bytes and identity match, and it leaves an edited active pointer unchanged. Conflicts are preflighted before any missing immutable file is installed.
- Session/run/revision IDs accept bounded ASCII alphanumeric, non-leading dot, underscore, and hyphen only. Leading-dot IDs are rejected so accepted storage cannot be hidden from restart scans. Resolved paths must remain below the injected root before access; a symlink escape is rejected.
- Commit order is validator/identity/base/model comparison, same-directory temporary revision write, close/read/codec revalidation, exclusive hard-link installation, then atomic pointer rename. A different existing immutable file is never overwritten.
- Only the current active revision of the same Run can be a base. An identical orphan final revision can be retried; different bytes under the same revision ID are rejected.
- A valid old pointer remains authoritative over a newer orphan. A missing/corrupt/dangling pointer scans only valid final `.json` revisions, checks filename/document/session/run/model evidence/validator/base chain, ignores malformed or temp candidates, and deterministically selects greatest `savedAt`, then revision ID.
- Immutable comparison preserves document identity, duration/language, provenance, speaker IDs/provider IDs, diarization, original word/issue evidence, every model missing-speech marker, and every model speech-Turn membership boundary. It permits speaker display names, current word assignment/source/edited text/timing origin, subdivision/Undo within one original model speech Turn, issue status, and revision metadata.

## Main review follow-up

- New-session import now writes its expected first pointer directly and records zero recovery notices. Missing/corrupt pointers on already stored sessions still recover and emit notices.
- Missing-speech marker identity, kind, times, speaker, empty word IDs, marker text, reviewed flag, and issue references must exactly match the model. Added, removed, or rewritten marker evidence is rejected.
- Each current speech Turn may contain words from only one original model speech Turn. User subdivision and restoration are allowed; cross-model merging is rejected even when the typed validator alone accepts it.
- Leading-dot identifiers are rejected before writes. Storage existence uses filesystem attributes and distinguishes actual missing items from other filesystem errors; list failures are not returned as empty history.
- The immutable installer captures `errno` immediately after exclusive linking and before cleanup.
- Recovery ordering is verified with differing UTC offsets using parsed `Date` instants. Imported models are explicitly rejected when `humanEdited == true` or `baseRevisionId != nil`.

## Final integration review

- First initialization is now determined from the session directory before import creates any directories. Importing a different Run into an existing session with a lost pointer recovers the existing latest valid edited Run and emits a missing-pointer notice; a genuinely new session still emits none.
- Turn evidence now preserves the exact flattened model Word order and nondecreasing original model Turn positions, including marker positions. Subdivisions may share one original position and an Undo restoration to the original Turn layout is accepted.
- Moving the unchanged marker before `t1` and swapping `t1`/`t2` both pass the typed validator in the regression setup but are rejected by the repository without changing the active revision.
- `loadModel` now rejects stored `model.json` whose revision is human-edited or has a base revision, including direct corruption under an injected test root.

## Verification

Final command:

```sh
bash scripts/check.sh
```

Result: exit 0, `backpressure OK`, no SKIP.

- Contract/regression: 29 tests PASS.
- DamaCore contract copy: byte-exact PASS.
- Swift 6 contract compile and fixture roundtrip: PASS.
- Core: 38 tests, 0 failures. This comprises 20 prior loader/validator/time tests and 18 repository tests.
- Unsigned Dama Debug `xcodebuild`: PASS inside the current sandbox with existing repository-local caches. This is compile evidence, not signing/distribution proof.

Repository tests use a unique temporary root and cleanup per test. They cover:

- exact synthetic raw bytes, immutable model access, active load, and session listing;
- partial temp write and final-installed-before-pointer faults;
- SHA-256 comparison of raw/model/prior revision before and after each required fault/recovery flow;
- new repository instance reload, valid-old-pointer authority, identical orphan retry, corrupt and missing pointer notices, and malformed candidate rejection;
- stale base, conflicting existing revision bytes, unsafe IDs, and symlink escape;
- repeat fixture import preserving active edits and conflicting source rejection;
- two Runs with identical provider labels remaining independent;
- permitted reassignment preserving original text/model speaker and forbidden original evidence mutation;
- explicit missing revision never falling back, and sanitized no-valid-revision errors.
- exact marker preservation and rejection with active/model/raw/pointer SHA-256 hashes unchanged;
- cross-model speech-Turn merge rejection while same-model subdivision remains allowed;
- first initialization producing no recovery notice, leading-dot ID rejection, non-directory/unreadable storage error propagation, differing-offset recovery order, and edited/based model import rejection.
- existing edited Run recovery when a different older Run is imported after pointer loss;
- marker/speech Turn reordering rejection plus positive subdivision and Undo restoration;
- direct stored-model corruption rejection for both human-edited and based revision metadata.

## Failure classification

- During implementation, the first focused compile found one implementation type-inference error around POSIX `rename` (`Int` versus `Int32`); fixed.
- The first test compile found async calls inside XCTest autoclosures; test values are now awaited before assertions.
- Initial implementation focused/final runs passed 30/0. Main-review follow-up focused and final backpressure runs passed 35/0.
- Final integration focused and final backpressure runs passed 38/0; no new compiler, assertion, environment, or app-build failures occurred.
- No runtime assertion failures, filesystem permission denials, known Xcode sandbox error, or unresolved code failures remain in this task.

## Remaining limitations

- Actor isolation serializes one repository instance only. Immutable hard-link installation protects against replacement across processes, but there is no cross-process writer lock and a process can race between symlink validation and access.
- Files are closed/read back and pointer rename is atomic on the same volume, but directory metadata is not `fsync`ed. These tests simulate interruption points; they do not prove power-loss durability or hardware/filesystem crash consistency.
- The real Application Support location is resolved but intentionally not written or exercised by tests.
- Repository failure prevents `commitRevision` from returning success. UI “saved” state and export suppression cannot be tested until their later tasks exist.
- T-04 editing/Undo, export, app/UI, real audio/API, visual/VoiceOver, signing, and distribution are not implemented or claimed here.

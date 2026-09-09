# T-02 result — main reviewed

2026-09-09. CLI gpt-5.6-sol (medium) produced Core implementation and tests, with full backpressure PASS in its log. It did not create the required result file before prolonged silence after the last small source change (last file event17:40:56; still no result17:48). Main stopped that invocation, reviewed the delivered files, preserved the original exact fixture assertions and added the edited-text timing regression. This report is main-authored evidence, not a fabricated delegate final response.

## Actual interfaces

- TranscriptLoading.swift: `NormalizedTranscriptCodec.decode(_ data: Data) throws -> TranscriptDocument`, `encode(_ document: TranscriptDocument) throws -> Data`; strict normalized object keys before typed decode, explicit nulls on encoding.
- `PyannoteJobDecoder.decode(_:) throws -> PyannoteJobDTO`: separate DTO; unknown status string preserved.
- `SyntheticTranscriptFixtureLoader.load(data:)` / `load(from:)`: refuse non-synthetic provenance rather than relabel it.
- `TranscriptContractError(code:path:)`: structured code and schema position; excludes unknown-field contents and input values.
- TranscriptValidator.swift: `TranscriptValidator().validate(_:)`: identifiers, schema/provenance/revision, finite scores, references, paired-null/ranged times, exactly-one speech membership, marker barriers, exclusive timeline, edited-text timing. User reassignment does not erase or equate model evidence.
- TranscriptTimePresentation.swift: `milliseconds(fromMicroseconds:)`, `timestamp(_:)`, `durationMilliseconds(startUs:endUs:)`, `duration(startUs:endUs:)`.

## Numeric mini-audit

- Input and persisted model unit are Int64 microseconds. No model timestamp is changed for display.
- Presentation divides by1000 and rounds half-up using quotient/remainder; no floating-point conversion or value+500 overflow.
-850000µs→00:00:00.850;990000µs→00:00:00.990; difference140000µs→140ms. 849499→.849 and849500→.850.
- Fixed tests also exercise Int64.max, missing/negative/reversed presentation values; invalid typed document times still fail validation.

## Verification

Main `bash scripts/check.sh` after final integration: exit0, no SKIP. Python29 PASS, contract copy byte-exact PASS, Swift6 smoke PASS, Core20 tests/0failures, unsigned Dama Debug compile PASS. Execution was inside the Codex sandbox with existing Xcode package/build caches; this does not prove a fresh-cache sandbox build works (T01 first-build denial remains documented).

Main read all3 new source files and the new test file, then their staged diff. The previous DomainContractDecodeTests.swift was folded into TranscriptLoadingTests.swift; all6 original exact assertions remain, including schemaVersion and confidence65/60 individually (sum125 additionally checked). `git diff --cached --check` passed. SSOT originals and existing fixtures were not modified.

Tests cover full fixture semantic roundtrip, all schema required keys recursively, absent nullable/unknown keys, wrong JSON type, non-synthetic refusal, unknown vendor state, map/null, duplicate/dangling IDs, negative/partial/reversed time, missing/double membership, invalid marker/mixed speakers, exclusive overlap, positive multiword user reassignment, marker swallowing refusal, score/date/run errors and text timing provenance.

## Limits

This task implements no repository, editing session, export or interactive UI. No audio/API/Keychain use, signing/notarization or xcodebuild test. No native visual/VoiceOver proof. The codec checks the supported normalized schema structure plus typed/semantic rules; it is not a general-purpose JSON Schema engine.

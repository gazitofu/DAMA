# M0 implementation delegation contract

The user authorized /build m0-fixture-review on 2026-09-09. You are a limited implementation delegate. Main owns decomposition, review, integration, git commits and plan status. Do not delegate again or stop because this is Codex. Read this contract, the specific task, repo CLAUDE.md, versions/m0-fixture-review/plan.md, relevant existing implementation and cited SSOT before editing.

## Scope and preservation

- Work only in /Users/gazitofu/Developer/Dama on work/m0-fixture-review. Follow each task's allowed paths. Do not change plan/status, git state, fixtures, ssot/contracts originals, design, tone, or the adopted spec. Do not perform commits.
- M0 is a synthetic fixture review app, not recording/STT. No network/audio/API/Keychain access, signing, notarization, xcodebuild test, package downloads, permission prompts or external uploads. No fake functional controls. Swift 6, arm64, macOS 26.6.2. No third-party dependencies.
- Mechanical code and meaningful tests belong to the task. Keep changes cohesive and maintainable. Never weaken tests or skip new failures to claim success; never use unchecked Sendable to silence errors.
- DomainContracts.swift source is immutable. The Core copy must be byte-identical with drift validation. Preserve required JSON nulls, confidence maps, unknown speaker, raw/model text, provenance and missing-speech barriers. No API signature invention.
- Prior task files/commits are inputs. Main-owned task prompts and plan changes can be present; preserve them. Only modify the named task result document in this directory.

## Verification and report

- Run `bash scripts/check.sh`; retain `-module-cache-path` and keep all build caches under repository `.build/`. Core SwiftPM pure tests and unsigned Debug compile are allowed. Never run xcodebuild test, code signing or notarization. No signing identity changes.
- If a command fails inspect path-denial evidence first (~/.cache, ~/Library, Keychain). Report environment denial versus compiler/assertion failure explicitly; do not label environment failure a code defect. Main can rerun with normal permissions.
- Result MUST be written to the task's `tNN-result.md` path: changed files, actual interfaces, commands/results/test counts, failures classified, unverified items, limitations. A final chat reply is not the deliverable.
- Main monitors log/mtime/CPU progress. Use bounded commands and emit milestones. First runtime is measured, subsequent no-progress timeout is 5 times measured normal task runtime (initial conservative ceiling 20 minutes without any log/file/CPU progress). Do not leave detached processes.

## Measured inputs (main read before ordering)

- ssot/contracts/DomainContracts.swift: public Codable Sendable document types, explicit nullable encoding, TranscriptRepository.load(sessionId:revisionId:)/commitRevision(_:); implicit memberwise initializers internal to Core.
- fixtures/normalized-transcript.json: five words/four turns/two issues, marker 850000–990000 microseconds with no word IDs; w5 unknown with model speaker B; confidence d4 map sums to125 and d5 null. Provenance hybridPyannoteWhisperKit/isSynthetic true.
- scripts/check.sh: 29 Python regression checks, Swift6 smoke currently pass; Core/project absent before T01. scripts/validate_contracts.py and SmokeCheck.swift read, preserve regressions.
- Native UI and VoiceOver cannot be verified by this agent's currently enabled tools. Compile/test success is never visual/real-device/acoustic accuracy proof. Report those gaps honestly.

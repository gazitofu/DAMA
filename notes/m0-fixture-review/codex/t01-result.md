# T-01 result — main reviewed

2026-09-09. CLI gpt-5.6-sol implemented the scaffold. Main interrupted its repeated Xcode sandbox workaround attempts, removed the unsupported `-IDEPackageSupportDisableManifestSandbox` option and the generated `.build/xcode-home/Library/Preferences/com.apple.dt.Xcode.plist`, then completed verification. This file is main-authored from actual files/logs; no successful delegate final report is claimed.

## Changes and interfaces

- Dama.xcodeproj/project.pbxproj and shared Dama.xcscheme: native Dama target, local DamaCore product, Swift6, arm64, Debug/Release deployment26.6.2, bundle com.gazitofu.Dama. Scheme has no app test target yet.
- App/DamaApp.swift + UI/ReviewShell.swift: empty SwiftUI window1180×760, minimum900×600, truthful unsupported recording/transcription message. No fixture autoload or network/audio code.
- Resources/Info.plist: generated product metadata, no microphone usage/permission request.
- Packages/DamaCore/Package.swift: Foundation library and XCTest target, no external dependencies. Core baseline macOS26; application minimum remains26.6.2.
- Core DomainContracts.swift is byte-exact SSOT derivative, SHA256 `7be81c3301184397b14b284019946c66394750bb5cdbce2c1234504642791535`. Existing public interfaces unchanged.
- scripts/check_contract_copy.py: fail-on-drift check, also called by Xcode build phase. Check only; no silent synchronization/overwrite.
- scripts/check.sh: all module/scratch/package/DerivedData/log paths under `.build/`; preserves explicit swiftc module cache. SwiftPM pure tests disable nested SwiftPM sandbox and credential lookup. App build explicitly CODE_SIGNING_ALLOWED=NO.

## Actual verification

| Command/axis | Result and classification |
|---|---|
| CLI sandbox `bash scripts/check.sh` | Python29 PASS, Swift smoke PASS, Core XCTest1 PASS. App failed initially from unsupported CLI flag, then local package manifest `sandbox-exec: sandbox_apply: Operation not permitted`. Also ~/Library/Logs/CoreSimulator write denial. Environment failure after command correction, not source defect |
| Main outside sandbox `bash scripts/check.sh` | exit0, all4 axes PASS, no SKIP: Python29, byte-exact copy, Swift6 smoke, Core1, unsigned Debug compile |
| `file` built executable | Mach-O64-bit executable arm64 |
| `plutil -p` built app Info.plist | LSMinimumSystemVersion26.6.2; bundle com.gazitofu.Dama; Xcode26.6, actual SDK macosx26.5 |
| Xcode log | BUILD SUCCEEDED; no CodeSign build command |
| Deliberately altered `.build/drift-probe.swift` | check_contract_copy.py exit1 with different hashes, confirming mismatch rejection; originals unchanged |
| `git diff --check` | exit0 |

CLI runtime was approximately15 minutes before main handoff, including initial document/SDK reads and environment experiments. This is a first-run observation, not a recurring build-time estimate. Incremental checks are materially shorter; exact timing is not claimed here.

Main read every new source/project/check file and scripts/check.sh diff. Tests use #filePath to locate the original synthetic fixture independent of cwd. No original fixture or contract changes. T02 prompt created by main is intentional and excluded from T01 implementation commit.

## Unmeasured

Actual UI appearance, app launch, keyboard/VoiceOver, recording, API, signing/notarization, xcodebuild test. Core's single decode test establishes module wiring only; editing/storage/export remain T02–T07 work. No AC completion beyond this limited scaffold is claimed.

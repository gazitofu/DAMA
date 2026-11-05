# 백엔드 검수 모집단

2026-09-11 · 기준 HEAD `fb08330` · `work/m0-fixture-review`.

이 파일은 [검수 결과](audit.md)의 파일별 증거 인덱스다. 상태 정본은 `versions/backend-audit/plan.md`다.

구현 검수와 테스트 실행을 구분한다. 테스트 파일 전체의 모든 assertion을 다시 심사했다는 의미는 아니다. UI는 백엔드 연결만 대상이며 아이콘 비트맵·문서 전체·Git 이력은 코드 모집단에서 제외했다.

## App: 상태·동의·수명주기 호출 경로 검수

| 파일 | 줄 수 | SHA-256 | 진입점/테스트 수 |
|---|---:|---|---|
| [App/AppLifecycle.swift](../../App/AppLifecycle.swift) | 111 | `56c0e0508cf51e1c2cea88ad60035e965d100c3130c06b982c0425ef2229e49f` | L5: DamaAppDelegate, applicationDidFinishLaunching, applicationShouldTerminate, applicationShouldTerminateAfterLastWindowClosed |
| [App/CorrectionWorkspace.swift](../../App/CorrectionWorkspace.swift) | 149 | `8a7614a68033664633de1ff17a1a22c0c5668085ec6f36684e51dfa4c261a1c5` | L7: CorrectionWorkspace, chooseReferences, chooseExecutable, choose |
| [App/DamaApp.swift](../../App/DamaApp.swift) | 21 | `1d8080f71fdf9a7de7ea9e3a74ee6bd165b8f7e125ff70c7fba65dba4cd369ab` | L3: DamaApp |
| [App/LibraryWorkspace.swift](../../App/LibraryWorkspace.swift) | 418 | `fba3bb676007056e8fd9631af5df8b324cb66fa281b5125c23cd82018c91894c` | L8: LibraryFolder, LibraryWorkspace, start, setUpDefaultFolders |
| [App/ProcessingWorkspace.swift](../../App/ProcessingWorkspace.swift) | 291 | `12351c7ae4395d1efc333ff969b67f2625724a3069c221f65b2396873c5f3881` | L8: ProcessingWorkspace, chooseQwenRuntime, start, run |
| [App/RecordingWorkspace.swift](../../App/RecordingWorkspace.swift) | 105 | `2e533bf6fa6d5864ba1deb6c927bb9656776d8a18feffff8e3be79bf2af4c7a1` | L7: RecordingWorkspace, start, toggleRecord, importFile |
| [App/ReviewWorkspace.swift](../../App/ReviewWorkspace.swift) | 257 | `09d65f90936efa2c94d5ed45cba1746d9a879dcbce28e1537a692f9469951093` | L8: ReviewWorkspace, start, refresh, open |
| [App/StatusBarController.swift](../../App/StatusBarController.swift) | 85 | `31fb4d15b582069fae268be957f6b5009f9856bec2a097afcbe2ba60c6cb0d1f` | L6: StatusBarController, icon, menuWillOpen, update |

## UI: 처리·저장·편집·표시 소비 경로 검수 (시각 디자인 제외)

| 파일 | 줄 수 | SHA-256 | 진입점/테스트 수 |
|---|---:|---|---|
| [UI/EditDialog.swift](../../UI/EditDialog.swift) | 92 | `fa235b8eec8d3e81240d52f7336d5d14b95c7f938e8ad7c13f979be49b9dea58` | L4: EditDialog, Kind, EditDialogView, ExactTextEditor |
| [UI/EvidencePanel.swift](../../UI/EvidencePanel.swift) | 87 | `97d9fd9424363eabd1c1b858d6705282b3f0782085605673a896ac3469c29b2a` | L4: EvidencePanel, section |
| [UI/LibraryShell.swift](../../UI/LibraryShell.swift) | 831 | `0f611860947f8f27ca5c98f30f3879a7accf3dedb779650b2ebdb7a20ac32be8` | L7: ProcessingProgressCard, ScriptBlockRow, issueLabel, LibraryShell |
| [UI/RecordingPanel.swift](../../UI/RecordingPanel.swift) | 110 | `666d033e023b8bac964e95344b493ffe319f5a89067f11d3fc90c7102a92bb46` | L5: RecordingPanel, recordLabel |
| [UI/ReviewShell.swift](../../UI/ReviewShell.swift) | 358 | `6336c5fb81dff6426dd85ff7aa7ac7779c468da9f3d92475cea56bd6fd570c4f` | L5: ReviewShell, header, turnRow, words |

## DamaCore: 정규화·보존·수정·읽기·export 구현 검수

| 파일 | 줄 수 | SHA-256 | 진입점/테스트 수 |
|---|---:|---|---|
| [Packages/DamaCore/Sources/DamaCore/CorrectionSpans.swift](../../Packages/DamaCore/Sources/DamaCore/CorrectionSpans.swift) | 137 | `b4d4c0c6622d09bd8b91332fa8018d8b4489d5eef6553d55a0fbbb18beb58c5b` | L5: CorrectionChange, CorrectionUnresolved, CorrectionChangeDecision, CorrectionSpans |
| [Packages/DamaCore/Sources/DamaCore/CorrectionTerms.swift](../../Packages/DamaCore/Sources/DamaCore/CorrectionTerms.swift) | 58 | `b46a153bfbba4a79bc5956d055ac8bfe1f98d039001c3b1576214e8b765c872b` | L6: CorrectionTerm, CorrectionTerms, entries, spellingOnly |
| [Packages/DamaCore/Sources/DamaCore/DomainContracts.swift](../../Packages/DamaCore/Sources/DamaCore/DomainContracts.swift) | 280 | `e5c0dfbe0fef9c103e0993151a292e710eb6db22e88ff75e9e3ed6bef6e88fb5` | L8: encodeRequiredNullable, Speaker, DiarizationInterval, CodingKeys |
| [Packages/DamaCore/Sources/DamaCore/FileSessionRepository.swift](../../Packages/DamaCore/Sources/DamaCore/FileSessionRepository.swift) | 1006 | `214a5daa451c58c96ff441da81cc8efc1d27f6861581aee71ec2fa81dd821c9b` | L4: SessionRepositoryFaultStage, SessionRepositoryError, Code, SessionRecoveryReason |
| [Packages/DamaCore/Sources/DamaCore/LibraryPresentation.swift](../../Packages/DamaCore/Sources/DamaCore/LibraryPresentation.swift) | 209 | `c2a82dcd0463a43b6e9d91f3c258d039d934bb89e2b0ca54cc687fd22468158f` | L4: ScriptReadingPolicy, endsSentence, completesReadingSentence, ScriptReviewEvent |
| [Packages/DamaCore/Sources/DamaCore/LibraryScript.swift](../../Packages/DamaCore/Sources/DamaCore/LibraryScript.swift) | 237 | `fcc867e94588b9514e953d78ec2e4e1ca17efe72b299ad67e3cc6d0a492cce96` | L3: ConversionNotes, validate, LibraryFailure, SpeakerNameScope |
| [Packages/DamaCore/Sources/DamaCore/ManagedNormalizer.swift](../../Packages/DamaCore/Sources/DamaCore/ManagedNormalizer.swift) | 124 | `b9b3db4d5dfb44b66ee56fb3a6158d8b2b942424d6d061e145734091f56666bc` | L3: ManagedNormalizationError, ManagedNormalizer, normalize, time |
| [Packages/DamaCore/Sources/DamaCore/QwenNormalizer.swift](../../Packages/DamaCore/Sources/DamaCore/QwenNormalizer.swift) | 133 | `37f3dd81889816e354e6267cc8c2ba0e9ab4da639835d69aa03b79bf8306fdce` | L3: QwenResult, Word, Chunk, QwenNormalizer |
| [Packages/DamaCore/Sources/DamaCore/ScriptCorrection.swift](../../Packages/DamaCore/Sources/DamaCore/ScriptCorrection.swift) | 212 | `ff723e928dafe80b9bf91c97adcd148ea3ee17bc229a363eb782c1ec65cd27ec` | L3: ReferenceExcerpt, CorrectionEdit, ScriptCorrection, State |
| [Packages/DamaCore/Sources/DamaCore/ScriptEvaluation.swift](../../Packages/DamaCore/Sources/DamaCore/ScriptEvaluation.swift) | 127 | `6fbe705b552a32133172cd3fa4c50cd45818d7539f20dbe26fad0e4ee2f03855` | L3: ReviewError, ReviewSample, ReviewedTurn, ScriptReviewRecord |
| [Packages/DamaCore/Sources/DamaCore/SonioxNormalizer.swift](../../Packages/DamaCore/Sources/DamaCore/SonioxNormalizer.swift) | 107 | `53f52d691702f9834533b9667205859b744517eef254a260ee2bbe4ee1f6036b` | L3: SonioxTranscriptDTO, Token, SonioxNormalizer, normalize |
| [Packages/DamaCore/Sources/DamaCore/SonioxPrecisionNormalizer.swift](../../Packages/DamaCore/Sources/DamaCore/SonioxPrecisionNormalizer.swift) | 126 | `8be0285647c32178bfef06e20487ca75f6f00c15cd49c8df77bab3c97c8c958b` | L4: SonioxPrecisionNormalizer, normalize, intervals, flag |
| [Packages/DamaCore/Sources/DamaCore/TranscriptEditing.swift](../../Packages/DamaCore/Sources/DamaCore/TranscriptEditing.swift) | 665 | `56ab01426edb25072d429846cd849ef236a7285f6a0dcdbfdcd3566d90b8cf9d` | L3: TranscriptEditOperation, TranscriptEditingError, Code, TranscriptEditor |
| [Packages/DamaCore/Sources/DamaCore/TranscriptExporting.swift](../../Packages/DamaCore/Sources/DamaCore/TranscriptExporting.swift) | 241 | `fe2d0e103b64c67a4ad04bd72bb58b75fd957918d1a2f86c576d795d797fd4cc` | L4: TranscriptExportVersion, TranscriptExportFormat, TranscriptExportSelection, TranscriptExportResult |
| [Packages/DamaCore/Sources/DamaCore/TranscriptLoading.swift](../../Packages/DamaCore/Sources/DamaCore/TranscriptLoading.swift) | 209 | `003d6b9d22e8dd05d1db1f76d2384dfbdd0dd3ade5f402bcfe9fc47e8820ea4c` | L3: TranscriptContractError, Code, NormalizedTranscriptCodec, decode |
| [Packages/DamaCore/Sources/DamaCore/TranscriptTimePresentation.swift](../../Packages/DamaCore/Sources/DamaCore/TranscriptTimePresentation.swift) | 34 | `f2f5a5f2f4574c8b009cadfe2be5a57bda1b060fbd0a30c30d11216bf805e155` | L3: TranscriptTimePresentation, milliseconds, timestamp, durationMilliseconds |
| [Packages/DamaCore/Sources/DamaCore/TranscriptValidator.swift](../../Packages/DamaCore/Sources/DamaCore/TranscriptValidator.swift) | 335 | `1c76533959d0c23e6b279fca91dc994ba9ef484934f294b5f9ae36a1b05428c3` | L3: TranscriptValidator, validate, validateProvenance, validateRevision |
| [Packages/DamaCore/Sources/DamaCore/TranscriptionProvider.swift](../../Packages/DamaCore/Sources/DamaCore/TranscriptionProvider.swift) | 79 | `6c4570279357dcb909b65dee16f397426129f2858073cc68497c3c5ba83bdc87` | L3: TranscriptionProvider, SonioxRequest, context, prepare |

## DamaAudio: callback·저장·변환·폴더·재생 구현 검수

| 파일 | 줄 수 | SHA-256 | 진입점/테스트 수 |
|---|---:|---|---|
| [Packages/DamaCore/Sources/DamaAudio/AnalysisConverter.swift](../../Packages/DamaCore/Sources/DamaAudio/AnalysisConverter.swift) | 115 | `34a958afc961a500f75eed38ff4df0a0fde9c515b2a08a9948660b6b766d9095` | L4: AnalysisConverter, Input, next, convert |
| [Packages/DamaCore/Sources/DamaAudio/AudioStorage.swift](../../Packages/DamaCore/Sources/DamaAudio/AudioStorage.swift) | 211 | `882c348771b9c1abcd1abe1a72c4b0f22a67860f4e4707a262e41585c5c4c0cd` | L5: AudioFailure, CapturePhase, beginning, stopping |
| [Packages/DamaCore/Sources/DamaAudio/CaptureBufferPool.swift](../../Packages/DamaCore/Sources/DamaAudio/CaptureBufferPool.swift) | 78 | `f450d13f90683f91d61a8d6663bfef6d5ab28752723aa5e5c7a7d1f209b2c2e4` | L7: CaptureBufferPool, close, offer, consume |
| [Packages/DamaCore/Sources/DamaAudio/CaptureWriter.swift](../../Packages/DamaCore/Sources/DamaAudio/CaptureWriter.swift) | 101 | `35ffe6c0b4cb97b2fb549aa7705c6d334549b08b04cf73a751482510fa29f15d` | L4: CaptureWriter, snapshot, drain, append |
| [Packages/DamaCore/Sources/DamaAudio/FolderLibraryStore.swift](../../Packages/DamaCore/Sources/DamaAudio/FolderLibraryStore.swift) | 209 | `df7d9644658d26c23d9c3a362d09f0d610f0ad84643e310cadda5a4f7cf9bb20` | L4: LibrarySpeech, LibraryScriptFile, FolderLibraryStore, prepareDefaultFolder |
| [Packages/DamaCore/Sources/DamaAudio/MicrophoneCapture.swift](../../Packages/DamaCore/Sources/DamaAudio/MicrophoneCapture.swift) | 162 | `ade4d8865020d0c8518500f674d2ca1a7681530dd3cfbc4b7d48a2628fca937f` | L7: MicrophoneCapture, toggle, start, audioTap |
| [Packages/DamaCore/Sources/DamaAudio/ReferenceFolder.swift](../../Packages/DamaCore/Sources/DamaAudio/ReferenceFolder.swift) | 46 | `a2a417a0df90f1cb17550587fa05295fc4da4f051f7bdae13b3d7f73caf802fe` | L6: ReferenceFolder, excerpts |
| [Packages/DamaCore/Sources/DamaAudio/SegmentPlayback.swift](../../Packages/DamaCore/Sources/DamaAudio/SegmentPlayback.swift) | 53 | `e7c49dbaab0d4156a940627d942d3a8c8670b48edf50679adb8d9d3ee4f9ef56` | L6: SegmentPlayback, range, listeningRange, play |

## DamaManaged: 제출·재개·키·worker 구현 검수

| 파일 | 줄 수 | SHA-256 | 진입점/테스트 수 |
|---|---:|---|---|
| [Packages/DamaCore/Sources/DamaManaged/CodexCorrectionClient.swift](../../Packages/DamaCore/Sources/DamaManaged/CodexCorrectionClient.swift) | 70 | `84fb93c9dc3b27899a484286c64f9315ade4c1a3afb4a2f3c585e41beb011400` | L5: CodexCorrectionFailure, CodexCorrectionClient, arguments, correct |
| [Packages/DamaCore/Sources/DamaManaged/KeychainStore.swift](../../Packages/DamaCore/Sources/DamaManaged/KeychainStore.swift) | 38 | `504f02772a21d08736a4bb5b5bb6fc9ac7daabd0cb6548c5b3ec932ef934e47c` | L5: KeychainStore, query, read, save |
| [Packages/DamaCore/Sources/DamaManaged/ManagedProcessor.swift](../../Packages/DamaCore/Sources/DamaManaged/ManagedProcessor.swift) | 497 | `00cd9cc4a513e8cd455596e28f17c5e712b198d6a02c3ab29dce2c32390dffc8` | L6: ManagedRun, ManagedProcessor, directory, persist |
| [Packages/DamaCore/Sources/DamaManaged/ProcessingPresentation.swift](../../Packages/DamaCore/Sources/DamaManaged/ProcessingPresentation.swift) | 64 | `217a831e1708bc9c55e3748d54a11ce44e9f436e566c5c770f0f5cb88074fc0e` | L4: ProcessingPresentation, elapsed |
| [Packages/DamaCore/Sources/DamaManaged/PyannoteTransport.swift](../../Packages/DamaCore/Sources/DamaManaged/PyannoteTransport.swift) | 94 | `6dcb288c41b41217d43850d6272469d2af78ccf4948b74e2ca85977a4d0ef438` | L3: HTTPReply, api, upload, ManagedFailure |
| [Packages/DamaCore/Sources/DamaManaged/QwenRunner.swift](../../Packages/DamaCore/Sources/DamaManaged/QwenRunner.swift) | 98 | `e3fae6ad5524d97b446b1c1f58133e2991a6e5f4eca3cbf499f01061888e6303` | L6: QwenFailure, validateReady, transcribe, QwenRunner |
| [Packages/DamaCore/Sources/DamaManaged/SonioxTransport.swift](../../Packages/DamaCore/Sources/DamaManaged/SonioxTransport.swift) | 67 | `71ad5255b36d0dbd1b5f25232f7409cc0eaa4cb958b853311d431686f955aae5` | L4: api, upload, SonioxTransport, request |

## 테스트: 사례 목록·주요 경계 assertion 확인 + 전체 145건 실행

| 파일 | 줄 수 | SHA-256 | 진입점/테스트 수 |
|---|---:|---|---|
| [Packages/DamaCore/Tests/DamaAudioTests/AudioJourneyTests.swift](../../Packages/DamaCore/Tests/DamaAudioTests/AudioJourneyTests.swift) | 187 | `78366f580f6ce71c0eb42f69e978c587ae33e0714774c7ac287cecef833b490d` | L6: XCTest 7건 |
| [Packages/DamaCore/Tests/DamaAudioTests/ContextAudioTests.swift](../../Packages/DamaCore/Tests/DamaAudioTests/ContextAudioTests.swift) | 106 | `61a52f5f10aee80e8db0969508a9d8162d746e8f61c9a280dd067f96194e2d1f` | L6: XCTest 5건 |
| [Packages/DamaCore/Tests/DamaAudioTests/LibraryJourneyTests.swift](../../Packages/DamaCore/Tests/DamaAudioTests/LibraryJourneyTests.swift) | 131 | `00754cbbb7573eb6e8afd5805d21a1ff8489bd0cd2bdaaa27f33216301ea9e2c` | L6: XCTest 5건 |
| [Packages/DamaCore/Tests/DamaCoreTests/ContextCorrectionTests.swift](../../Packages/DamaCore/Tests/DamaCoreTests/ContextCorrectionTests.swift) | 235 | `e9f2f578cf84306551cb77089bbd1effd759f043fed6e55a77f06d41d262b1fb` | L5: XCTest 9건 |
| [Packages/DamaCore/Tests/DamaCoreTests/FileSessionRepositoryTests.swift](../../Packages/DamaCore/Tests/DamaCoreTests/FileSessionRepositoryTests.swift) | 782 | `95ebd12ce7b5906e33e451773bae4975dbe39cee906cd03aa79118606564eedb` | L6: XCTest 20건 |
| [Packages/DamaCore/Tests/DamaCoreTests/LibraryPresentationTests.swift](../../Packages/DamaCore/Tests/DamaCoreTests/LibraryPresentationTests.swift) | 231 | `e1097fcf418a3e27268c5de91e012591d6140a06164ead8586c0a37f20f4c0f1` | L5: XCTest 11건 |
| [Packages/DamaCore/Tests/DamaCoreTests/QwenNormalizerTests.swift](../../Packages/DamaCore/Tests/DamaCoreTests/QwenNormalizerTests.swift) | 58 | `e5999129c80f9177b598f135b5a9682be6b3403b9f78a97a1fc2f91644095755` | L4: XCTest 5건 |
| [Packages/DamaCore/Tests/DamaCoreTests/ScriptEvaluationTests.swift](../../Packages/DamaCore/Tests/DamaCoreTests/ScriptEvaluationTests.swift) | 52 | `dd32795f3104c42997f69086bccb26f8029047847f87b815e52b7f690d694205` | L5: XCTest 2건 |
| [Packages/DamaCore/Tests/DamaCoreTests/SonioxNormalizerTests.swift](../../Packages/DamaCore/Tests/DamaCoreTests/SonioxNormalizerTests.swift) | 110 | `1dd7620c3b22d4c89a82f781271547f3cd5a33a700cff936500c31eb13b12b22` | L5: XCTest 6건 |
| [Packages/DamaCore/Tests/DamaCoreTests/SonioxPrecisionTests.swift](../../Packages/DamaCore/Tests/DamaCoreTests/SonioxPrecisionTests.swift) | 57 | `e3ac4c4735157e59e514334408322427187b0223de6bacbd665aad3a3e4dfe0c` | L5: XCTest 4건 |
| [Packages/DamaCore/Tests/DamaCoreTests/TranscriptEditingTests.swift](../../Packages/DamaCore/Tests/DamaCoreTests/TranscriptEditingTests.swift) | 848 | `10caf87445ec2d1343aa692671f57a717188b8518d05faa1b687eabd341e5308` | L5: XCTest 16건 |
| [Packages/DamaCore/Tests/DamaCoreTests/TranscriptExportingTests.swift](../../Packages/DamaCore/Tests/DamaCoreTests/TranscriptExportingTests.swift) | 478 | `c8890bca64eaf12b1d0ea65578cd646cee25430a39c1049de55313ea3a4f5598` | L5: XCTest 8건 |
| [Packages/DamaCore/Tests/DamaCoreTests/TranscriptLoadingTests.swift](../../Packages/DamaCore/Tests/DamaCoreTests/TranscriptLoadingTests.swift) | 303 | `4bc51e5c1975149f7a6ac55e89ad0dbef5a92f98958a0c302f251945e0fa2423` | L5: XCTest 20건 |
| [Packages/DamaCore/Tests/DamaManagedTests/CodexCorrectionTests.swift](../../Packages/DamaCore/Tests/DamaManagedTests/CodexCorrectionTests.swift) | 73 | `c9ff4090f84faf39898a037b46c8f99709afaf417c7c6a4462ddaea92670b698` | L6: XCTest 4건 |
| [Packages/DamaCore/Tests/DamaManagedTests/ManagedJourneyTests.swift](../../Packages/DamaCore/Tests/DamaManagedTests/ManagedJourneyTests.swift) | 411 | `3b935bc2188c578bd5a3630678712e18ce4fb60bb3a0aa6704d135f2e75a8874` | L9: XCTest 12건 |
| [Packages/DamaCore/Tests/DamaManagedTests/ProcessingPresentationTests.swift](../../Packages/DamaCore/Tests/DamaManagedTests/ProcessingPresentationTests.swift) | 39 | `1de2482acf0264a3dbba47dedf88326342f38819bd046a627d8a008c309557c5` | L5: XCTest 2건 |
| [Packages/DamaCore/Tests/DamaManagedTests/QwenJourneyTests.swift](../../Packages/DamaCore/Tests/DamaManagedTests/QwenJourneyTests.swift) | 98 | `cfae70e3c4ddf501a90228663340bbb2f7e98b6927527bab4bfc12e086006c61` | L8: XCTest 3건 |
| [Packages/DamaCore/Tests/DamaManagedTests/SonioxJourneyTests.swift](../../Packages/DamaCore/Tests/DamaManagedTests/SonioxJourneyTests.swift) | 224 | `7cb9d85036f4c4b3df7f9e02d1c10e5bd0090b42ee7477a21864bace1eedd606` | L8: XCTest 6건 |

## 실행·검증 scripts: 코드/호출 연결 검수 (아이콘은 출력 연결만)

| 파일 | 줄 수 | SHA-256 | 진입점/테스트 수 |
|---|---:|---|---|
| [scripts/SmokeCheck.swift](../../scripts/SmokeCheck.swift) | 38 | `78f085eedafd8298f711136ac9dcf70e67c0bc83c028e068074bd26aa9fba08d` | L5: ContractSmokeCheck, main |
| [scripts/check.sh](../../scripts/check.sh) | 108 | `d10293964f1f0afa682bf6aa24c40127a2a42a10e410808001369cff5a3059af` | L1: 설정/필드/호출 연결 |
| [scripts/check_contract_copy.py](../../scripts/check_contract_copy.py) | 50 | `381d5a16c1a65a1218dc76ad87a6515522ff2ca84e1b89316cb016b1ffc6e34f` | L1: 설정/필드/호출 연결 |
| [scripts/generate-dama-icons.py](../../scripts/generate-dama-icons.py) | 161 | `27d31dcfd8d46f87ad7eef7c0078fcdd329b6d5d2e02518ae7111cf14e331d91` | L1: 설정/필드/호출 연결 |
| [scripts/qwen-requirements.lock](../../scripts/qwen-requirements.lock) | 31 | `1d6efd54a5856fdf3fd4f2a7ab9275489b01d90ad3918b6b4609ed3796f00e28` | L1: 설정/필드/호출 연결 |
| [scripts/qwen_download.py](../../scripts/qwen_download.py) | 22 | `0337d0554c62886b1de9c7643c6bd88fe3e386cbaa4cbdb9ae9ec43cdae00446` | L1: 설정/필드/호출 연결 |
| [scripts/qwen_worker.py](../../scripts/qwen_worker.py) | 203 | `1450235abf090335defaf9ae1e505213f14dfa621d67d345638b55321f41d288` | L1: 설정/필드/호출 연결 |
| [scripts/test_qwen_worker.py](../../scripts/test_qwen_worker.py) | 33 | `887869b4c079e1c5e103565b27d512926495eaede003795ab2aae0b133832446` | L5: MappingTests |
| [scripts/validate_contracts.py](../../scripts/validate_contracts.py) | 314 | `e1fe12d50a7c9b282178aa76deec8160f3b18f3ca22a0430043fc71ce8c32a88` | L192: ContractTests |

## 계약·프로젝트 설정: 채택 계약/필드·타입·빌드 경계 대조

| 파일 | 줄 수 | SHA-256 | 진입점/테스트 수 |
|---|---:|---|---|
| [Packages/DamaCore/Package.swift](../../Packages/DamaCore/Package.swift) | 26 | `0e9259c629b4e0e55154596821c4070b19a70ca12f4619f80f8a079d4144e53c` | L1: 설정/필드/호출 연결 |
| [Dama.xcodeproj/project.pbxproj](../../Dama.xcodeproj/project.pbxproj) | 371 | `234bbe20c53c079674976fcec03e6bddf8593d78d8815f7f80ccae87437361e5` | L1: 설정/필드/호출 연결 |
| [Dama.xcodeproj/xcshareddata/xcschemes/Dama.xcscheme](../../Dama.xcodeproj/xcshareddata/xcschemes/Dama.xcscheme) | 74 | `3e1b06a25ec5e0f8e711b6a0d8cece0da106c12388b1b1bf8992ee6dae7fe2df` | L1: 설정/필드/호출 연결 |
| [Resources/Info.plist](../../Resources/Info.plist) | 36 | `2365359c2faebc371ff5cff7e194fe3d1f3a11db66c9d390892b83fe582d50c6` | L1: 설정/필드/호출 연결 |
| [Resources/Dama.entitlements](../../Resources/Dama.entitlements) | 8 | `205669665088f73cb25ee4a79295df64889a6d9cee3eecb03a7782e0047589d6` | L1: 설정/필드/호출 연결 |
| [ssot/contracts/DomainContracts.swift](../../ssot/contracts/DomainContracts.swift) | 280 | `e5c0dfbe0fef9c103e0993151a292e710eb6db22e88ff75e9e3ed6bef6e88fb5` | L8: encodeRequiredNullable, Speaker, DiarizationInterval, CodingKeys |
| [ssot/contracts/transcript.v1.schema.json](../../ssot/contracts/transcript.v1.schema.json) | 520 | `20b1968a2bc0bfb349ee11898347116f3a8ecc1ecb83e5a353c3192f73e284b7` | L1: 설정/필드/호출 연결 |
| [ssot/contracts/library-script.md](../../ssot/contracts/library-script.md) | 118 | `88f74624949af819e25e009515e90ab47740035c8c449518a5e4b437484b06b9` | L1: 설정/필드/호출 연결 |
| [ssot/contracts/operating-baseline.md](../../ssot/contracts/operating-baseline.md) | 65 | `499c664d815246e6718263eee9017745b8a412019879521ccc39bcb3028f6926` | L1: 설정/필드/호출 연결 |

총 82파일. 이번에 추가한 진단 도구 2개는 검수 대상 제품 코드와 별도로 `audit.md`의 재현 절에 기록한다.

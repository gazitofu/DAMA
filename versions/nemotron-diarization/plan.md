---
unit: nemotron-diarization
branch: work/m0-fixture-review
status: building
decisions_resolved: true
resume: "게이트 ② 대기. 0.5.13(31) 설치, AC-14·15 확인. 남음: AC-09 실화면 문구, AC-10 실기기 녹음 우선 여정."
spec: notes/nemotron-diarization/nemotron-diarization.src.html
---

## 근거

- 컨펌: 스펙 `#s-verdict` `data-state="closed"` (게이트 ① 2026-10-30, 사용자 «권고안대로 확정»: D-01~05 전부 ⓐ, 판정 축 ①②③ 확정). 확정 문구 `ssot/tone/nemotron-diarization.md`. 커밋 `632d4e6`.
- 규율 14종 2026-10-30 재독(스펙 «참조 근거»와 동일 목록). 프로젝트 메모리 `pyannote-dropped`.
- `ssot/dev.md` §1·2·4·5, `ssot/design/00_README.md`(02·03·04 컨펌 계약), `ssot/design/04` INV-01~10, `ssot/api/pyannote-verified.md`(새 호출 없음, 참조만), `ssot/contracts/operating-baseline.md`, `ssot/contracts/library-script.md` §45·§195.
- 계약 실측: `transcript.v1.schema.json` provenance.engine enum = `managedPyannoteWhisper, managedSoniox, hybridPyannoteWhisperKit, hybridPyannoteQwen, hybridSonioxPyannote`. interval = `{id, startUs≥0, endUs≥0, speakerId, confidence: object|null (0–100)}` 전부 required. `DomainContracts.swift:50` `EngineKind` 같은 5값. 패키지 사본 `Packages/DamaCore/Sources/DamaCore/DomainContracts.swift`는 check.sh 2단계가 byte-exact 대조.
- 사전 확인 (2026-10-30):
  - branch `work/m0-fixture-review`, `origin/..HEAD` 63커밋, main은 이 유닛 기반 파일(`TranscriptionProvider.swift`, `SonioxPrecisionReconciler.swift` 등) 없음. 스킬 절차 `checkout main && -b work/$1`은 미적용, 이전 유닛 선례대로 현 브랜치 유지(공유 트리 브랜치 전환 금지). worktree는 이 checkout + prunable scratch 1개.
  - `git status`: 타 소유 수정 14파일(세션 시작 시점부터 존재, `App/LibraryWorkspace.swift`·`UI/SpeechDetailView.swift`·`Packages/DamaCore/Sources/DamaCore/P2TimeEvidence.swift`·`DamaManaged/ProcessingPresentation.swift`·`Dama.xcodeproj/project.pbxproj` 포함) + untracked `notes/diarization-research/`·`scripts/nemotron-probe/`·`ssot/api/nari-verified.md`. 커밋은 pathspec + `git diff --cached` 헝크 확인, 타 소유 헝크 제외.
  - check.sh 기준선 PASS: 계약 30 · 계약 파생물 byte-exact · Swift 6 SmokeCheck · swift test 224(Core 151 / Managed 36 / Audio 37) · xcodebuild Debug, SKIP 없음. `.build/check-logs/run-20261030T062500Z-Oeeuzh`, 요약 `.build/check-logs/nemotron-baseline.log`. 타 소유 미커밋분 포함 상태의 결과.
- 로컬 실측(읽기 전용, 2026-10-30): Run 상태 provider별 `sonioxPrecision` ready 13·partialResult 3·waitingForBilling 1(B460D5A5, P2 자식 `http402`), `soniox` ready 23, `precision` ready 13·waitingForBilling 1, `qwen` ready 1, `pyannote` ready 6. 1a 확률 28개 `.build/diagnostics/nemotron/<session>/{probs.f32,meta.json}` 22.82시간. 모델 `.build/nemotron-models/nemotron-3-diarization/monolithic/v2/Nemotron3Diarizer_offline.mlmodelc` 190MB. FluidAudio 0.18.0 revision `e15287985625dbf544a343df679436789ffb03fb` (`scripts/nemotron-probe/Package.resolved`).

## 의도

새 변환의 운영 기본 경로를 «Soniox 전사 + 이 Mac Nemotron 3 화자 분리»로 바꾸고, pyannote에 새 요청을 보내는 경로를 모두 닫는다. 결합은 Nemotron 확률에서 파생한 구간에 승인된 B2(v4) 배정 규칙을 그대로 적용한다.

## 영향 범위 (현행 실측)

| 경로 | 현행 |
|---|---|
| `Packages/DamaCore/Sources/DamaCore/TranscriptionProvider.swift` | cases `pyannote, soniox, qwen, sonioxPrecision, precision`; `selectable = [.sonioxPrecision, .soniox, .qwen, .pyannote]`; `EngineKind.title` 5값 |
| `Packages/DamaCore/Sources/DamaCore/SonioxPrecisionNormalizer.swift` | `PyannoteJobDTO` 디코드 → 화자 `\(runID)-p2-\(i)`·구간·이슈 생성, engine `.hybridSonioxPyannote`, `diarizationModel "precision-2"`, version `soniox-p2-v2` |
| `Packages/DamaCore/Sources/DamaCore/SonioxPrecisionReconciler.swift` | `normalize(soniox:diarization:...)` = v2 → `applying(policy: .wordRepair)`; `applying`이 화자 ID를 `\(runID)-p2-\(offset)`로 재매핑 |
| `Packages/DamaCore/Sources/DamaManaged/ManagedProcessor.swift` | `executeCombined`: Soniox 자식 → P2 자식(`.precision`) → raw 복사 → 정규화. 필드 `sonioxRunID`, `precisionRunID` |
| `Packages/DamaCore/Sources/DamaCore/LibraryScript.swift` | `ConversionNotes.sonioxSourceRunID`, `precisionSourceRunID` |
| engine 분기 | `LibraryPresentation.swift:143`·`ScriptReadingStructure.swift:36` 원문 공백 보존, `FileSessionRepository.swift:389·394` 가져오기 허용·raw 파일명, `FolderLibraryStore.swift:83` 대표 결과 우선순위, `LibraryPresentation.swift:88` `speakerCountApplication` |
| `App/ProcessingWorkspace.swift` | 선택 저장 키 `transcription.operatingProvider`, 확인창, `admitsProcessing`(Qwen만 녹음 판정), `localInferenceActive = busy && activeProvider == .qwen`, `canResume` 상태 목록에 `waitingForBilling` 포함 |
| `App/RecordingWorkspace.swift:49` · `App/AppLifecycle.swift:48` | 녹음 시작 시 `pauseLocalInferenceForRecording`, 종료 시 `pauseAndWait` |
| `UI/SpeechDetailView.swift` | 엔진 제목 분기 `.sonioxPrecision`, 화자 수 안내, 새 전사 설정(Picker·Qwen 엔진) |
| `Packages/DamaCore/Sources/DamaManaged/ProcessingPresentation.swift` | 단계 4종 문구, 상태별 제목·설명 |

## 수용 기준

- [x] AC-01 계약: schema·`ssot/contracts/DomainContracts.swift`·패키지 사본에 `hybridSonioxNemotron` 추가, check.sh 1·2단계 PASS(사본 byte-exact). `validate_contracts.py`에 새 enum 왕복 1건 이상 추가. 기존 5값 fixture 전부 통과 유지. `operating-baseline.md`·`library-script.md` §195·`CLAUDE.md` 최상위 경계 6 개정(운영 = Soniox + Nemotron 3, pyannote 새 요청 없음, 과거 P2 결과 보존).
- [x] AC-02 구간 변환 단위(INV-02, numeric): 입력 = Float32 확률 `[frame × 8]`·`frameCount`·`durationUs`(Int64 µs). 내부 = Int64 µs 반열린 `[start, end)`, 프레임 i = `[i·10_000, (i+1)·10_000)`. 고정 테스트: ① 0번 프레임 `[0, 10_000)` ② 마지막 프레임 end = `durationUs`로 자름(예: durationUs 25_000, frameCount 3 → 마지막 `[20_000, 25_000)`) ③ start ≥ durationUs 프레임 버림 ④ 정확히 0.5 = 비활성, 0.50001 = 활성 ⑤ 활성 1프레임 = 구간 1개 길이 10_000 ⑥ 최소 길이·패딩·틈 메우기 없음(같은 채널 활성-비활성 1프레임-활성 = 구간 2개). 역뮤테이션 2종(`>`→`>=`, 끝 자르기 제거)에서 FAIL.
- [x] AC-03 경계 2·INV-06·INV-07·INV-08(RC-01·03·04·09·12): 합성 확률 A 1초 → B 30 ms → A 1초 → 일반 구간 3개, 결합 스크립트 speech Turn이 A·B·A로 분리(RC-01). B 구간에 단어가 없으면 `missing_speech` marker, A 앞뒤 병합 없음(RC-03). 음성 대조(B 확률 0.5) → B 구간 0개·B 화자 없음. 두 채널 동시 활성 → 일반 구간 2개, 그 프레임은 단독 구간에서 제외, 해당 단어 `overlapping_speech`(RC-04). A 마지막 프레임 i, B 첫 프레임 i+1 → 겹침 이슈 0(RC-09). 활성 채널 0개 → 화자 목록에서 제외. 모든 구간 `confidence = null`, `low_confidence` 이슈 0.
- [x] AC-04 B2 회귀: 공통화 전후 기존 `soniox-p2-v2`·`soniox-p2-word-v4`(및 v3·v5 비교 정책) 테스트 전부 PASS, 기존 결합 테스트 입력의 출력 JSON 바이트 동일(공통화 직전 코드로 만든 기대 파일 대조). 역뮤테이션 1종(공통 경로의 화자 ID 접두를 바꿈)에서 FAIL.
- [x] AC-05 결합 버전: 새 Run provenance = engine `hybridSonioxNemotron`, `diarizationModel "nemotron-3-diarization-coreml-offline"`, `algorithmVersion "soniox-nemotron-word-v1"`, 화자 ID `\(runID)-nm-\(channel)`, providerId `channel-\(channel)`, displayName «화자 k»(채널 오름차순 k=1…), 구간 ID 일반 `d\(i)`·단독 `e\(i)`(start µs, channel 오름차순). 같은 녹음 두 Run의 화자 ID는 Run별로 달라 이전 이름 매핑을 자동 재사용하지 않음(INV-09, RC-13). Soniox 토큰 문자열·공백·순서·원시간·ASR confidence·언어·`asrSpeakerLabel` 불변(원 Soniox 정규화 대비 필드 대조). 계약 검증 통과.
- [x] AC-06 Run·재사용·네트워크 0: `sonioxNemotron` parent → Soniox 자식(기존) → `nemotron` 자식 → parent `raw/`에 `soniox-response.json`·`nemotron-probabilities.f32`·`nemotron-meta.json` 불변 복사 → 정규화. Nemotron 재사용 키 = session·분석 WAV SHA256·모델 파일 SHA256 목록·FluidAudio `0.18.0`·프리셋 `offline` 전부 일치. mock 테스트: Nemotron 실행 중 Soniox·pyannote transport 호출 0; 둘 다 재사용 시 transport 호출 0·diarizer 호출 0; 키 하나라도 다르면 재사용 안 함(키별 1건). 자식 ID는 실행 전 persist.
- [x] AC-07 상태 전이: 자식 `queued → localDiarizing → readyForReview`; 실행 오류 → 자식 `failed`(`localDiarizationFailed`), parent `failed` + 재개 가능(재개 시 Soniox 요청 0, diarizer 1회); 모델 해시 불일치 → `failed`(`modelUnavailable`); 녹음 판정 거부 → 자식 `queued`·parent `queued`·diarizer 호출 0; 취소 → 자식 `queued`, 확률 파일 미기록. `submissionUncertain` 생성 0.
- [x] AC-08 멈춘 P2 Run: P2 자식이 `readyForReview`가 아닌 `sonioxPrecision` Run과 `qwenDiarizationRunID == nil`인 미완료 `qwen` Run은 `canResume == false`, 재개 경로 pyannote transport 호출 0(mock). B460D5A5와 같은 형태의 사본 fixture로 «다시 전사» → 새 `sonioxNemotron` Run, 조건 일치 시 Soniox 새 요청 0. P2 완료된 기존 Run의 로컬 `reconcile`·열람 동작 불변.
- [ ] AC-09 선택·화면·문구: `selectable == [.sonioxNemotron, .soniox]`. 저장 값이 목록 밖(`sonioxPrecision`·`qwen`·`pyannote`·`precision`·없음)이면 `.sonioxNemotron`, 목록 안이면 유지(단위 테스트). `EngineKind.title`·`speakerCountApplication`·Speech 엔진 제목·화자 수 안내·모델 상태 4종·모델 버튼·모델 안내·모델 없이 변환·녹음 차단·진행 3종·확인창 줄이 `ssot/tone/nemotron-diarization.md`와 글자 단위 일치(문자열 상수 테스트 + 실화면 1회). 엔진 분기 6곳(`LibraryPresentation:143`·`ScriptReadingStructure:36`·`FileSessionRepository:389·394`·`FolderLibraryStore:83`·`speakerCountApplication`)이 새 engine을 Soniox 결합본으로 다룸(대표 결과 우선순위 = `hybridSonioxPyannote`와 같은 등급, 동급 시 최신).
- [ ] AC-10 녹음 우선: `admitsProcessing`가 `sonioxNemotron` 실행·재개에 `allowsLocalInference` 적용, 거부 시 문구 «녹음 원본을 저장한 뒤 화자 분리를 시작하거나 재개해 주세요.» `localInferenceActive`가 parent 단계 `localDiarizing`이면 true. 실기기: 화자 분리 중 녹음 시작 → 녹음 즉시 진행, 원본 저장, 자식 `queued`, 이후 변환 재개로 완료(여정 1회). 앱 종료 시 Nemotron 취소. INV-01 영향 없음.
- [x] AC-11 모델: 저장 위치 = 앱 내부 저장소 `Models/nemotron-3-diarization/`. SHA256 목록 = `.build/nemotron-models/nemotron-3-diarization/` 실제 파일에서 생성해 소스에 상수로 박음(파일 경로·SHA256·바이트 수). 테스트: 목록 일치 → 준비됨, 파일 1개 바이트 변조 → 불일치·삭제·`다시 받기`(역뮤테이션: 대조 생략 시 FAIL), 파일 누락 → 필요. «모델 받기» 누를 때만 네트워크(변환 경로 다운로드 호출 0, mock). 실기기 다운로드 1회 후 목록 일치(사용자 승인 후).
- [x] AC-12 실데이터 결합 측정(네트워크 0, 사용자 저장소 쓰기 0): Soniox 원응답 + 1a 확률이 있는 녹음 전부로 결합 문서 생성 → 전건 계약 검증 통과, `speakers` 배열 수 = 1a `summary.json` `nemotronChannels`(전건, 둘 다 «0.5 초과 프레임이 1개 이상인 채널» 정의 · `scripts/nemotron-probe/analyze.py:125`). 스크립트 «감지 N명»(`detectedSpeakerCount` = 단어 배정 화자 수)과는 다른 자이며 그 값은 기록만. 녹음별 미배정 lexical 비율·시간당 `missing_speech` 수 기록, P2 결합본이 있는 녹음은 나란히. 문턱 없음(정확도 아님). 결과 `.build/check-logs/nemotron-diarization/ac12-*.txt`.
- [x] AC-13 앱 실행 재현·메모리: 설치 앱에서 1개 녹음 실행 → 저장된 확률과 1a `probs.f32`의 프레임 수 일치·채널 수 일치·최대 절대 차이 기록. 최장 녹음(126FB238, 2.82시간) 실행 최대 RSS 기록. 문턱 없음.
- [x] AC-14 전달: check.sh PASS(계약 31+, Swift 224+신규, Debug), SKIP 0. `MARKETING_VERSION`·`CURRENT_PROJECT_VERSION` 상향, 실행 중 Bundle 버전 확인. pathspec 커밋, 타 소유 헝크 바이트 보존.
- [x] AC-15 v2 단독 구간(스펙 r2, 사용자 2026-10-30 «v2로 변경»): 합성 확률에서 두 채널 동시 활성 프레임의 단독 구간 = 확률이 높은 채널, 최고 확률 동률 프레임은 단독 구간 제외, 무활성 프레임 제외. v1 규칙 출력은 기존 테스트 그대로(재현). 새 Run `combinationAlgorithmVersion`·provenance = `soniox-nemotron-word-v2`, v1으로 저장된 미완료 Run 재개는 v1, 그 밖 버전은 실패(자동 치환 없음). 역뮤테이션(v2에서 겹침 프레임 제외로 되돌림) FAIL. 실데이터: Soniox 원응답과 1a 확률이 있는 녹음 전부에서 v1·v2 미배정 lexical 비율, P2 결합본이 있는 녹음은 P2 함께(문턱 없음, 정확도 아님). 설치 앱에서 BED2C097 다시 전사 1회(Soniox·Nemotron 재사용, 새 요청 0).

## 실행 기록 (2026-10-30)

- 커밋: `d3a1bf3` T-01 계약 · `c9574c2` T-02 구간 변환 · `13b13f3` 공통화 전 골든 · `338dd94` T-03 결합 공통화 · `f41932c` 모델 고정 목록 · `9ad1227` 처리기 · `f76659a` FluidAudio 실행기·앱 연결 · `1f18083`·`e27a15b` 측정 도구. 타 소유 헝크(`App/LibraryWorkspace.swift` convert 재전사 분기, `UI/SpeechDetailView.swift` 버튼 문구, `ProcessingPresentation.swift` partialResult 문구, `project.pbxproj` 버전 줄)는 HEAD+자기 변경 blob만 인덱스에 올려 제외, 작업 트리에 그대로.
- 사고 1건: T-06 편집 스크립트가 쓰기 열기를 읽기보다 먼저 해 `UI/SpeechDetailView.swift`가 0바이트가 됨. 세션 앞에서 기록한 타 소유 diff로 HEAD+그 헝크를 재구성해 복원, 복원 후 `git diff` blob `6793b4d`가 원래 값과 동일. 이후 스크립트는 읽기 완료 뒤 쓰기.
- check.sh 최종 `.build/check-logs/run-20261030T065539Z-kCbi5x` exit 0, SKIP 없음: 계약 31 · 파생물 byte-exact · SmokeCheck · swift test 254(Core 171 / Audio 37 / Managed 46, 기준 224) · xcodebuild Debug(FluidAudio 0.18.0 `e1528798` 링크).
- AC-01: 새 enum 왕복·미지 enum 거부 테스트, 운영 계약·`library-script.md`·`CLAUDE.md` 경계 6 개정.
- AC-02: `NemotronIntervalsTests` 9건. 역뮤테이션 `>`→`>=` 1 FAIL, 끝 자르기 제거 2 FAIL, 복원 SHA256 일치.
- AC-03·05: `SonioxNemotronReconcilerTests` 10건(A→B 30ms→A 3 Turn, 누락 marker, 0.5 대조, 겹침, 접점, provenance·ID·confidence null, Soniox 토큰 불변, Run별 ID, 선택 이전).
- AC-04: `PolicyGoldenTests` 공통화 전 v3·v4·v5·v4-new 35개 지문 고정 후 공통화 뒤 동일. 역뮤테이션(p2 접두 변경) 35 FAIL, 복원 SHA256 일치. 기존 `NormalizationGoldenTests` 21개 유지.
- AC-06·07·08: `NemotronJourneyTests` 6건(mock diarizer·transport: pyannote 호출 0, 재사용 시 diarizer·Soniox 추가 0, 재사용 키 6필드 각각 거부, 실패 후 재개 시 Soniox 요청 1회 유지, 모델 불일치·부재 시 실행 0, 녹음 판정 거부·취소 시 queued·확률 파일 없음, 멈춘 P2 Run 재개 거부·상태 파일 불변·다시 전사 성공).
- AC-11 일부: `NemotronModelStoreTests` 3건(일치·바이트 변조·누락·설치 검증·staging 정리). 역뮤테이션(해시 대조 생략) 6 FAIL, 복원 일치. 고정 목록 6파일 199,162,417 bytes는 1a 다운로드 실측.
- AC-12: `.build/check-logs/nemotron-diarization/ac12-summary.txt`. 1a 확률 28개 중 Soniox 원응답이 있는 18개 결합: 계약 검증 18/18, `speakers` = 1a 채널 수 18/18. 미배정 lexical 2.13–12.47%(중앙 7.04), `missing_speech` 56–431/h. P2 결합본이 있는 11개는 P2 미배정 0.03–8.00%(10개가 1.14% 이하). 결합 불가 10개(8개 미변환, 2개 pyannote+Whisper만).
- AC-13 일부(설치 앱 아님): 앱과 같은 `FluidNemotronDiarizer`를 감싼 `scripts/nemotron-combine` `NemotronAppRun`. 542D0E56(9분) · 126FB238(2.82시간) 둘 다 1a `probs.f32`와 바이트 동일, 채널 수 동일, 처리 2.34 s · 5.71 s, 최대 RSS 0.68 GB · 2.37 GB, 원본 WAV SHA256 전후 동일. `.build/check-logs/nemotron-diarization/ac13-app-executor.txt`.
- 버전: `project.pbxproj` 0.5.11(29)→0.5.12(30). 타 소유 미커밋 상향과 같은 줄이라 선례대로 작업 트리에만 둠. 빌드 산출물 `.build/xcode/Build/Products/Debug/DAMA.app` 0.5.12(30), 미설치.
- 설치(사용자 승인 2026-10-30 «설치 진행»): 실행 중 0.5.11(29) 일반 종료, 백업 `.build/backups/DAMA-0.5.11-29-before-nemotron.app`(실행 파일 SHA256 일치), 기존 번들 휴지통, 0.5.12(30) Debug 설치. 설치 번들은 빌드 산출물과 `diff -rq` 동일, 코드 `DAMA.debug.dylib`는 이전과 다르고 빌드와 동일. 실행 중 PID가 `/Applications/DAMA.app/Contents/MacOS/DAMA.debug.dylib`를 로드, Bundle 0.5.12(30). 내부 저장소에 `Models/` 없음(모델 미다운로드 상태).
- 설치 앱 실사용(2026-10-30 16:48 KST, 사용자 실행): 앱에서 모델 받기 → 내부 저장소 `Models/nemotron-3-diarization` 6파일 SHA256·크기 고정 목록과 일치(AC-11). BED2C097 «Soniox + Nemotron 3» Run `E33ADFD9` readyForReview, 자식 `F196F231` 확률이 1a `probs.f32`와 바이트 동일(SHA256 `6342b3fb…`), 1.34시간 처리 10.93 s(AC-13; 설치 앱 RSS는 미측정, 하네스 실측 2.37 GB/2.82시간으로 대체 기록).
- 미배정 진단(사용자 지적 «화자 미배정 많음», `.build/check-logs/nemotron-diarization/unassigned-diagnosis.txt`, 스크립트 `notes/nemotron-diarization/{unassigned,overlap,p2excl}.py`): E33ADFD9 lexical 22,635 중 미배정 1,387(6.13%). 그중 1,275(92%)는 토큰 구간 전체가 두 채널 이상 > 0.5인 프레임(파생 단독 구간에서 빠짐), 71 Nemotron 무음, 39 시간 무효/0길이, 2 동률. 저장된 P2 13개 원응답은 일반 구간 겹침 프레임 236,162개를 단독 구간이 100% 한 화자로 덮음. 즉 P2 미배정이 낮았던 원인은 공급자 단독 출력이며 기존 v3·v4·v5 규칙은 단독 후보가 있어야 동작해 이 92%를 줄이지 못한다.
- 스펙 r2(v2, 사용자 «v2로 변경»): `4efd7ba` 스펙·운영 계약·AC-15 · `884eb5b` 구현. `NemotronIntervals.Rule`(v1 `singleActive` 재현 유지, v2 `mostProbable`), `SonioxNemotronReconciler.Version`(새 Run v2, 저장된 v1은 v1, 미지원 버전은 `failed`). 테스트: 겹침 프레임 최고 확률 채널·동률 제외·v1 비교·v1/v2 결합·저장 버전 유지·미지원 버전 실패. 역뮤테이션(v2를 v1 동작으로) Intervals 1·Reconciler 2 FAIL, 복원 SHA256 일치. check.sh `.build/check-logs/run-20261030T082802Z-CTHPl9` exit 0, SKIP 없음, swift test 257(Core 173 / Audio 37 / Managed 47). 0.5.13(31) Debug 빌드, dylib에 `soniox-nemotron-word-v2` 포함, 미설치.
- 재현성 발견: 같은 입력으로 B2 결합을 Release(-O)로 빌드하면 설치 앱(Debug) 결과와 BED2C097에서 15단어(꼬리 공유 구절 나누기)가 다르다. Debug 빌드 재생은 설치 앱 출력과 바이트 동일. 같은 구절 나누기 코드를 단독 프로그램으로 -O/-Onone 컴파일하면 동일해 원인 미확정. 전달 앱은 Debug라 현재 결과 영향 없음. 측정 도구는 Debug로 돌린다.
- AC-15 실데이터(`.build/check-logs/nemotron-diarization/ac15-summary.txt`, Debug 빌드 도구): Soniox 원응답과 1a 확률이 있는 19개, v2 계약 검증 19/19, 화자 수 = 1a 채널 19/19. 미배정 lexical v1 2.02–12.47%(중앙 6.76) → v2 0.57–7.03%(중앙 1.26). P2 결합본 11개 P2 0.03–8.00%(10개 1.14% 이하). BED2C097 v1 6.13%는 설치 앱 Run E33ADFD9와 일치. 정확도 지표 아님. 남은 미배정이 큰 녹음: 6F4FA04E 7.03%, 73B651D8 5.45%, 542D0E56 4.58%.
- 0.5.13(31) 설치(사용자 «설치 진행», 2026-10-30): 0.5.12(30)를 `.build/backups/DAMA-0.5.12-30-before-v2.app`에 백업, 기존 번들은 Finder 휴지통. 실행 PID가 `/Applications/DAMA.app/Contents/MacOS/DAMA.debug.dylib`를 적재, 빌드 산출물과 `cmp` 동일, Info.plist 0.5.13(31), 문자열 `soniox-nemotron-word-v1/v2`·`nemotron-intervals-v1/v2` 포함(AC-14).
- 설치 앱 다시 전사(사용자 실행, 2026-10-30 19:56 KST): BED2C097 새 parent `108E3A3C` readyForReview, `combinationAlgorithmVersion`·provenance `soniox-nemotron-word-v2`, 자식 Soniox `CCDF109D`·Nemotron `F196F231` 재사용(이전 v1 parent `E33ADFD9`와 같은 자식, 자식 state.json 수정 시각 16:50·16:51 그대로, raw Soniox 응답·확률 파일 `cmp` 동일 → 새 Soniox·Nemotron 요청 0). lexical 22,635 중 미배정 v1 1,387(6.13%) → v2 130(0.57%), Debug 측정 도구 값과 일치. 화자 3명 동일. 검수 표시 `ambiguous_speaker` 1,387→130, `provider_disagreement` 222→525(겹침 단어가 배정되며 Soniox 화자와 다른 경우 증가), `overlapping_speech` 1,883 유지, `unrepresented_speaker` 528→436 (AC-15).
- 미검증: AC-09 실화면, AC-10 실기기 녹음 우선 여정. QA 판정 주체(GPT-6.1-sol) 부재로 QA 판정 미수행.

## 작업 분해

- T-01 계약(AC-01): schema enum·`ssot/contracts/DomainContracts.swift`·패키지 사본·`validate_contracts.py` 테스트·fixture 1건, `operating-baseline.md`·`library-script.md`·`CLAUDE.md` 개정. 코드 사용처는 컴파일 오류가 나는 exhaustive switch만 최소 수정.
- T-02 구간 변환(AC-02·03 일부): DamaCore 새 파일 `NemotronIntervals.swift` — `static func derive(probabilities: [Float], frameCount: Int, channels: Int, durationUs: Int64, runID: String) throws -> (speakers: [Speaker], regular: [DiarizationInterval], exclusive: [DiarizationInterval])`, `static func decode(f32: Data, frameCount: Int, channels: Int) throws -> [Float]`(little-endian, 크기 = frameCount·channels·4 아니면 오류). 상수 `threshold: Float = 0.5`(외부 공급자 기본값, 한국어 실측 전), `frameUs: Int64 = 10_000`, `version = "nemotron-intervals-v1"`. `P2TimeEvidence.swift`는 타 소유 헝크가 있어 수정하지 않는다.
- T-03 결합 공통화(AC-03·04·05·09 일부): 새 `SonioxDiarizationNormalizer`(Soniox bytes + 화자·일반·단독 구간·engine·diarizationModel·version·partial 플래그 → v2 형태 기본 문서). `SonioxPrecisionNormalizer`는 P2 디코드 후 이를 호출(출력 바이트 동일). `SonioxPrecisionReconciler.applying`의 화자 ID 접두를 매개변수화(`p2` 기본). 새 `SonioxNemotronReconciler.normalize(soniox:probabilities:meta:...)` = 구간 파생 → 공통 기본 문서 → `applying(policy: .wordRepair, speakerPrefix: "nm")` → version `soniox-nemotron-word-v1`. 공통화 전 기대 출력 파일을 먼저 커밋. 엔진 분기 6곳·`EngineKind.title`·`speakerCountApplication`.
- T-04 모델·실행기(AC-11·07 일부): 패키지에 FluidAudio `exact: "0.18.0"` 의존성과 새 target `DamaNemotron`(DamaManaged 의존). DamaManaged에 `protocol LocalDiarizing: Sendable { func diarize(analysisWAV: URL) async throws -> (probabilities: Data, meta: NemotronMeta) }`과 `NemotronMeta: Codable`(스펙 §02 필드). `DamaNemotron`: `NemotronModelStore`(목록 대조·상태 4종·다운로드 = `Nemotron3Models.loadFromHuggingFace(config: .offline, cacheDirectory:)`를 앱 Models 폴더로) + `NemotronDiarizer` actor(`Nemotron3Diarizer` 1개 보유, `processComplete` 1회, 결과 뒤 `Task.isCancelled`면 폐기). 오디오 콜백 경로와 무관.
- T-05 처리기(AC-06·07·08): `TranscriptionProvider`에 `sonioxNemotron`(title «Soniox + Nemotron 3 (운영)», destination Soniox, model `stt-async-v5`), `nemotron`(자식 전용). `ManagedRun.nemotronRunID`, `ConversionNotes.nemotronSourceRunID`(optional, 구 파일 nil). `ManagedProcessor.init`에 `diarizer: (any LocalDiarizing)?`, `admitsLocalInference: @Sendable () async -> Bool`. `executeCombined`를 화자 분리 출처 매개변수로 일반화, `reusableNemotron(sessionID:audioHash:modelManifest:)`, 단계 `localDiarizing`, failure `localDiarizationFailed`·`modelUnavailable`. 멈춘 P2·Qwen Run 재개 차단. mock diarizer·transport 테스트.
- T-06 앱 연결(AC-09·10·11): `ProcessingWorkspace`(선택 이전·확인창 줄·`admitsProcessing`·`resume`/`canResume`·`localInferenceActive`·`pauseAndWait`·`label`), `ProcessingPresentation`(`localDiarizing` 제목·설명·단계 2, 실패·멈춘 P2 문구), `SpeechDetailView`(엔진 제목·화자 수 안내·모델 상태 줄·«모델 받기»/«다시 받기»·Soniox 단독 시 숨김·모델 없을 때 변환 안내), 앱 타깃에 `DamaNemotron` 링크. 타 소유 헝크가 있는 `SpeechDetailView.swift`·`ProcessingPresentation.swift`는 HEAD+자기 변경만 인덱스에 올린다.
- T-07 실데이터 측정(AC-12): `scripts/nemotron-probe`에 오프라인 실행 타깃 또는 DamaCore 테스트 밖 실행 도구로 28개 결합 문서를 scratch에 생성·검증·집계. 사용자 Sessions 읽기 전용.
- T-08 검증·전달(AC-13·14·10 실기기): check.sh, 버전 상향, 설치(승인), 모델 다운로드(승인), 1개 녹음 실행·재현 대조, 녹음 우선 여정, 최장 녹음 RSS, plan 갱신.

## 결정 항목

없음. D-01~05는 게이트 ①에서 ⓐ로 확정. 대표 결과 우선순위(`hybridSonioxNemotron` = `hybridSonioxPyannote`와 같은 등급, 동급 시 최신)는 «결합본 우선» 기존 규칙(`FolderLibraryStore.swift:83`)을 새 결합 engine에 그대로 적용한 것이라 새 정책이 아니다. Qwen Run 재개 차단은 스펙 «pyannote에 새 요청을 보내는 경로는 없앤다»(R4)의 적용이다.

## 막힘

- QA 판정 주체 GPT-6.1-sol(`gpt-6.1-sol`)이 이 세션 에이전트 목록에 없음. 테스트·실측은 메인이 수행하고 QA 판정은 미수행으로 표시, 게이트 ②에서 사용자 확인.
- 네트워크(사용자 승인 건별): FluidAudio 0.18.0 패키지 해석(로컬 SwiftPM 캐시 `FluidAudio-08d244c7` 존재, Xcode 패키지 해석은 샌드박스 exit 74 선례로 외부 실행), 앱의 모델 다운로드 1회(Hugging Face).
- 실기기: 앱 설치·녹음 시작 여정은 사용자 앱 실행 상태에 의존.
- OpenMDW-1.1(모델)·Apache-2.0(FluidAudio) 표기 의무 원문 미확인. 개인 사용 앱이며 배포 전 확인.

## Follow-ups

- Release(-O) 빌드에서 B2 꼬리 공유의 구절 나누기가 Debug와 다르게 동작(BED2C097 15단어, `.build/replay-build` 재생 도구로 재현). P2 결합 경로에도 같은 코드가 쓰이므로 Release 전달 전에 원인 확인 필요.

- 결합 미배정 비율이 P2보다 높다(AC-12, 같은 11개에서 중앙 7%대 vs 1% 미만). 정확도 지표는 아니지만 검수 부담 신호다. 원인 후보(Nemotron 무음 프레임·단독 구간 교집합 없음) 1축 진단과 규칙 조정은 별도 결정(`algorithmVersion` 변경 대상).
- 녹음 시작 시 Nemotron 취소는 앱이 0.5초 주기로 갱신하는 Run 단계로 판정한다. 화자 분리 시작 직후 0.5초 안의 녹음 시작은 취소되지 않고 수 초 안에 끝난다(녹음은 막히지 않음). Qwen 중단 안내 문구에 대응하는 Nemotron 안내 문구는 확정 문구에 없어 표시하지 않는다.

- 음성 유사도 기반 채널 분할 안내(스펙 D-05, 후속 유닛).
- 3시간 초과 녹음 메모리(Soniox 상한 300분까지) 미측정.
- FluidAudio의 Hugging Face revision 고정 여부 미확인(해시 대조로 방어).
- pyannote API 키 설정 화면·`PyannoteTransport` 코드 정리는 범위 밖.
- `notes/diarization-research/`·`scripts/nemotron-probe/`는 스펙 근거인데 미커밋(이번 유닛 시작 전부터 untracked). 커밋 여부 사용자 확인.

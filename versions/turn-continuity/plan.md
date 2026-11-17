---
unit: turn-continuity
branch: work/m0-fixture-review
status: building
decisions_resolved: true
resume: "building (2026-11-17). T-01 e63926b · T-02 9ecf78b · T-03 a078132 · T-04 완료. 다음 = T-05 교정 짝짓기·저장. 기준선 HEAD 200f7d8 · check run-20261117T064312Z-7nDMlN (362 실행 = 360 통과 + skipped 2)."
spec: notes/turn-continuity/turn-continuity.src.html
---
## 근거

- 컨펌: `notes/turn-continuity/turn-continuity.src.html` `#s-verdict` `data-state="closed"` (게이트 ① 11.17, D-01–D-05 전부 ⓐ, 판정 축 ①–③ 확정, r2). 확정 문구 `ssot/tone/turn-continuity.md` (`200f7d8`, 문구 6–11). 문구 1–5 · 2a = `ssot/tone/correction-turn-isolation.md`.
- 규율 메모리 15종 (`~/.claude/projects/-Users-gazitofu/memory/`): rule-purpose-first · rule-ambiguous-instructions · rule-scope-stop · rule-gate-hygiene · rule-measurement · rule-negative-claims · rule-carryover-remeasure · rule-verify-at-consumption · rule-delegation-artifacts · rule-destructive-writes · rule-shared-tree-commits · rule-numeric-test-integrity · rule-external-media-verify · rule-longrun-watchdog · rule-branch-base-is-main. 프로젝트 메모리 pyannote-dropped · advisors-fable-astra.
- `ssot/dev.md` §2 (check 1–3 태스크마다, 4는 QA 경계) · §4 검증 층위 · §5 외부 전제 · §6 실녹음 저장소 반입 금지. `ssot/api/pyannote-verified.md` 머리 (이 유닛 pyannote 요청 0). `ssot/design/00_README.md` 하이브리드 채택 (04 정본, 개정 = D-03). `04` :44 INV-05 · :46 INV-06 · :117 §7 · INV-03 · INV-04 · INV-08 · INV-09 · INV-10. `06` §2 RC-01 · RC-03 · RC-05 · RC-10.
- 계약 실측 (schema · DomainContracts 변경 없음): SHA256 `DomainContracts.swift` f34fb40b… · `transcript.v1.schema.json` 87a059bb… (직전 유닛과 같음). `git grep -n -i 'inputLevel\|context-correction\|reading-v\|soniox-nemotron' -- ssot/contracts/DomainContracts.swift ssot/contracts/transcript.v1.schema.json` = 0줄 (종료 1). 쓰는 필드 = `TranscriptWord.ordinal` (:56) · `modelSpeakerId` (:62) · `alignmentScore` (:65, 필수 nullable) · `sourceIntervalIds` (:68) · `asrSpeakerLabel` (:72, 선택) · `TokenKind` = lexical · punctuation 둘뿐 (:49).
- 개정 앵커 (스펙 §05 인용과 글자 일치 확인): `04` :46 · :117. `library-script.md` :83 · :134 · :182 · :195 · :197 · :206 · :207 · :216. `operating-baseline.md` :20 (재사용 키 문장) · :22 («새 Run 버전은 `soniox-nemotron-word-v3`»).
- 사전 확인 (2026-11-17 15:40–16:30 KST):
  - HEAD `200f7d8`, `git status` clean. branch `work/m0-fixture-review` 유지: 선례 19/19 plan (`versions/correction-turn-isolation/plan.md:3` 외), 이 유닛 스펙 커밋 3개 (`d3f9a16` · `04ddc8e` · `200f7d8`)가 이 브랜치에만 있고 origin보다 3커밋 앞(미push)이라 전환 금지 (rule-shared-tree-commits). `git merge-base HEAD main` = `git rev-parse main` = `83327d5`, `main..HEAD` = 이 유닛 스펙 3커밋뿐. worktree = 이 트리 + prunable scratch 1.
  - check.sh `run-20261117T064312Z-7nDMlN` (HEAD `200f7d8`): 계약 31 PASS · byte-exact PASS · SmokeCheck PASS · swift test 362 실행 = 360 통과 + skipped 2 (`CorrectionFormatProbeTests.testCorrectionChunkReplyAgainstValidationRules` · `RealDataProbeTests.testRealDataRetentionAndCleanupPlanAreReadOnly`, 둘 다 환경변수 게이트) · 실패 0 (Managed 66 · Core 212 · Audio 84) · xcodebuild Debug PASS · SKIP 축 없음.
  - pbxproj `MARKETING_VERSION` 0.5.20 · `CURRENT_PROJECT_VERSION` 38 (:311 · :320 · :333 · :342). `/Applications/DAMA.app` 0.5.20 (38) 실행 중.
  - 실데이터 (읽기 전용, 숫자·ID 앞 8자만): Nemotron v3 parent 6개 전부 readyForReview · `soniox-nemotron-word-v3`. 발화 Turn / 미상 발화 Turn = `9F73A02B` 439/63 · `AB66A52D` 751/45 · `0FAACD0C` 1,283/88 · `E2B926E5` 751/330 · `7A430186` 2,643/162 · `44F4E8DD` 3,828/1,826 (스펙 §01 표 1 «현행» 6/6 일치). 자식 meta 6/6 `inputLevel` 키 없음, 저장 처리 1.2 · 1.7 · 5.2 · 9.2 · 10.9 · 17.0초.
  - 분석 WAV 0.1초 RMS P90 (numpy 선형 보간, 실험 `prep.py`와 같은 산법): `9F73A02B` −19.20 → 이득 0.00 · `E2B926E5` −42.97 → 22.97 · `0FAACD0C` −37.06 → 17.06 · `44F4E8DD` −33.83 → 13.83 dB. 4개 모두 16bit PCM 16kHz. 스크립트 `/private/tmp/claude-501/-Users-gazitofu-Developer-Dama/960b1030-8136-4dcd-85d8-4e651025fda5/scratchpad/probe/p90.py`.
  - `CorrectionAttempts/` 2건: `44F4E8DD` `context-correction-6` 0/44 실패 1 · `AB66A52D` `context-correction-7` 5/8 실패 4 (스펙 §02-5 ⑤와 같다).

## 의도

Nemotron에 넣는 음성만 메모리에서 음량을 맞추고(v1), 결합 v4가 어절 안 미상 조각을 그 어절의 단일 화자로 맞추며 어절 안 Turn을 잇고, 읽기 v9가 이웃 미상 어절을 한 문단으로 묶는다. AI 교정 v8은 부분열 응답을 받고 실패 청크를 재시도·원문 유지로 넘겨 «이어서 교정» 없이 끝난다. 모르는 화자는 null, 어절 사이 A → B → A 장벽, 원문·사람 수정 보존은 그대로다.

## 영향 범위 (경로 · 현행 실측 2026-11-17)

- `Packages/DamaNemotron/Sources/DamaNemotron/FluidNemotron.swift` (46줄): :12 `readMono16k` 결과를 :20 `processComplete`에 그대로 넣음 · :24 `LocalDiarization` 반환. DamaNemotron은 테스트 대상 없음 (check.sh 밖, `Package.swift` 주석).
- `…/DamaManaged/NemotronModel.swift`: :104–114 `LocalDiarization` · :122–136 `NemotronMeta` (합성 Codable, 13필드).
- `…/DamaManaged/ManagedProcessor.swift`: :215–229 `reusableNemotron` (6조건 + 확률 크기) · :270 새 parent 버전 = `SonioxNemotronReconciler.version` · :304–305 저장 버전 유지·미지원 실패 · :507 기존 자식 재개(버전 확인 없음, 불변) · :543 `Version(rawValue:) ?? currentVersion` · :597–635 `diarize` (:622–627 meta 작성).
- `…/DamaCore/SonioxNemotronReconciler.swift`: :6–12 `Version` v1–v3 · :11 `unifiesSplitWords` · :14 `currentVersion = .v3` · :35–36 `applying` 호출.
- `…/DamaCore/SonioxPrecisionReconciler.swift`: :49–51 `applying` 매개변수 · :64–86 단계 (:79 갈린 어절 맞춤 · :86 닫는 부호) · :95–108 이슈 (:105 `ambiguous_speaker`) · :143–149 Turn 생성 · :174–188 `orthographicGroups` · :333–358 `speakerTurns` (:343 화자 nil 비병합 · :347 시작 순행 · :348 marker·중단 장벽 · :349–351 다른 화자 구간 장벽).
- (/build 실측 추가) `…/DamaCore/TranscriptValidator.swift` `validateBarrier`가 INV-06을 모든 문서에 적용해 v4 Turn을 `invalidBarrier`로 거부 → D-03 INV-06 단서를 같은 규칙으로 반영 (Nemotron v4 · 같은 어절일 때 다른 화자 구간 검사만 생략, marker · 중단 · 모델 화자 일치는 유지, 어절 = `SonioxPrecisionReconciler.orthographicGroups` 공유). 테스트 쪽 `ReferenceTranscriptValidator.swift`도 독립 구현으로 같은 단서, `TranscriptValidatorEquivalenceTests` 1 추가 (v4 받음 · v3 재표기 · 어절 사이 → 둘 다 invalidBarrier).
- `…/DamaCore/ScriptReadingStructure.swift`: :36 원문 공백 보존 엔진 4종 · :40 `humanEdited` 제외 · :53–55 시간·이름 조건 · :56 같은 화자 잇기 · :57–66 미상 어절 안 조각 잇기 (ordinal +1 · 공백 없음 · `asrSpeakerLabel ==`).
- `…/DamaCore/LibraryPresentation.swift:21` `ScriptReadingPolicy.algorithmVersion = "reading-v8"` → Markdown :230 «- 문단 표시» · `ScriptEvaluation.swift:100`.
- `…/DamaCore/ScriptCorrection.swift`: :30–32 `CorrectionRejectionRule` 6종 · :56 `rejectedTurns` · :62–65 `rejectedCount(in:)` (전 규칙) · :66–78 `validate` · :122 `version = "context-correction-7"` · :176 프롬프트 «모든 id … 정확히 한 번» (불변) · :200–225 `validated` (:201–202 id 완전 일치 · 배열 하나만 nil → throw).
- `…/DamaCore/CorrectionAttempt.swift`: :5–31 `CorrectionFailureRecord` (:16 CodingKeys · :18–25 사용자 encode, exitCode 명시 null) · :34–47 `CorrectionChunkResult` · :54 `failureLimit = 20` · :93–107 `merged()`.
- `…/DamaCore/CorrectionReapplication.swift:28–33` 새 결과로 옮기는 값 (rejectedTurns 포함, failures 없음).
- `…/DamaCore/CorrectionRejectionText.swift` (23줄, 문구 1–5 · 2a).
- `…/DamaCore/LibraryScript.swift`: :241 문구 4 조건 = `rejectedTurns?.count ≥ 1` (전 규칙) · :275–278 문단 문구 5 + 2.
- `…/DamaManaged/CorrectionRunner.swift`: :57 init · :95–124 `run` (:99–104 실패 = 기록·저장·멈춤 · :109–112 검증 throw = 형식 · :116 progress = `completedChunks`).
- `…/DamaManaged/CodexCorrectionClient.swift`: :7–19 `CodexCorrectionError` · :227 출력 파일 없음 · :229 읽기 nil · 2,000,000 B 초과 · :230 해독 · :231 배열 누락 → 전부 `.format`.
- `App/CorrectionWorkspace.swift`: :10–11 진행 상태 · :141 `run` 호출 · :143–152 완료 (:146 rejectedTurns · :152 완료 문장) · :153–160 실패.
- `UI/ScriptReadingView.swift`: :106 «AI 보정 중… {k}/{n}» · :265–271 검증 실패 구간 정보 · :272 «모델 원문».
- 측정 도구: `scripts/nemotron-combine/Sources/NemotronAppRun/main.swift` (앱 `FluidNemotronDiarizer` 1회 실행·저장 확률 대조) · `…/NemotronCombine/main.swift` (저장 Soniox + 확률 → 결합).
- 계약 문서 (T-01): `ssot/design/04` 2곳 · `ssot/contracts/operating-baseline.md` 2곳 · `ssot/contracts/library-script.md` 8곳.
- 시간·단위: 결합·읽기 내부 시간 Int64 µs, 구간 `[startUs, endUs)`. 읽기 v9 간격 300ms = 300_000 µs (부호: 다음 시작 − 앞 끝, 음수 = 겹침, ≤ 300_000이면 만족). 음량은 아래 AC-02 mini-audit.

## 수용 기준

QA 판정 = GPT-6.1-sol (`codex exec -m gpt-6.1-sol --sandbox read-only --ignore-user-config -c model_reasoning_effort="high"`, correction-turn-isolation 선례; 모델 ID 실행 가능 여부는 QA 직전 1회 확인). 키체인·설치 앱·사용자 데이터 측정·실화면은 메인이 실행하고 판정만 넘긴다. 차수: A = AC-01–11 · B = AC-12–14 · 전달 = AC-15–17. 공통: 태스크마다 check.sh 1–3 PASS. «가드 이동» = 형태·건수 유지, 기대값만 옮김 + 역뮤테이션 1회 (원본 바이트 보관·복원·SHA256 대조, 붉음 건수 기록).

### 차수 A · 계약·코드 (합성)

- [ ] AC-01 계약 (D-01–D-05): 스펙 §05 «계약 개정 문안» 전부 글자 그대로. `04` :46 INV-06 끝 단서 · :117 단서 / `operating-baseline.md` :20 재사용 키 끝 «·입력 음량 처리 버전(`nemotron-input-level-v1`)» + 음량 문장 · :22 v4 문장 (v3 설명 문장 유지) / `library-script.md` :83 v9 · :134 뒤 v9 줄 (v8 문장 유지) · :182 뒤 v8 줄 · :195 · :197 · :206 (2구절) · :207 (3구절) · :216 (+ 규칙 코드 목록 «missing·chunk(응답 없음)»). 줄 번호는 앵커 문자열로 찾는다. 고치지 않는 것 diff 0: `CLAUDE.md` 최상위 경계 2–4 · `06` RC-01 · RC-03 · RC-05 · schema · `DomainContracts.swift`. `validate_contracts.py` 31 OK. 자 = 문안 대조 (QA).
- [ ] AC-02 입력 음량 함수 (D-05 · §02-1, 축 1): DamaManaged `public enum NemotronInputLevel` (DamaNemotron에는 테스트 대상이 없어 측정 도구·앱이 같이 쓰는 DamaManaged에 둔다). 상수 `version = "nemotron-input-level-v1"` · `targetDbfs = −20` · `maximumGainDb = 24` · `knee: Float = 0.7` · `windowSamples = 1_600` · `percentile = 0.9`. `public struct Record: Codable, Sendable, Equatable { version: String; gainDb: Double; p90Dbfs: Double }`. `measure(_ samples: [Float]) -> Record` · `apply(_ samples: inout [Float]) -> Record`.
  - mini-audit: 입력 Float32 선형 진폭 (−1…1) → 창 RMS (Double 누적) → dBFS = 20·log10(√mean(x²) + 1e−9) → 창 값들 오름차순 정렬, P90 = 선형 보간 (h = 0.9·(n−1), v[⌊h⌋] + (h − ⌊h⌋)·(v[⌊h⌋+1] − v[⌊h⌋]), numpy 기본과 같음) → g = min(24, max(0, −20 − P90)) → 소수 2자리 반올림 (`(g·100).rounded()/100`) 값을 기록하고 **같은 값을 적용** → 배율 = 10^(g/20) → 출력 Float32. 끝 표본(< 1,600)은 측정에서만 빼고 처리에는 포함. 부호: 이득은 0 이상만 (감쇠 없음). 창 0개(표본 < 1,600)면 g = 0 · p90Dbfs = −180.00 (빈 측정 = 무음 창 값).
  - 고정 테스트 (합성, 창마다 일정 진폭 a = 10^(d/20)): ① d = −70, −65, …, −25 (10창) → P90 −29.50 · gain 9.50 ② 전부 −60 → P90 −60.00 · gain 24.00 (상한) ③ d = −60, −55, …, −20 (9창) + 진폭 0.9 창 1개 → P90 −18.09 · gain 0.00 · `apply` 뒤 표본 바이트 = 입력 바이트 (0.7 위 표본 포함) ④ ①에 진폭 1.0 끝 표본 1,599개 추가 → P90 같음 ⑤ 리미터 |v| = 0.7 → 0.7 · 0.8 → 0.7 + 0.3·tanh(1/3) · 1.0 → 0.928478 (Float 허용 1e−6) · −0.8 → 부호 대칭 · |v| = 10 → ≤ 1.0 ⑥ g = 20 → 배율 10.0 · 6.02 → 2.0 (허용 1e−3).
  - 역뮤테이션 2종 붉음: 상한 24 제거 (②) · g = 0 처리 건너뛰기 제거 후 리미터 항상 적용 (③, 0.9 표본이 0.8748로 바뀜).
- [ ] AC-03 meta·재사용 키 (§02-1 ⑥⑦, 축 2): `LocalDiarization.inputLevel: NemotronInputLevel.Record` (init 필수 인자, 기본값 없음) · `NemotronMeta.inputLevel: NemotronInputLevel.Record?` (없으면 키 생략, 기존 meta 해독). `FluidNemotron.diarize` = 읽기 → `apply` → `processComplete` → 반환에 Record. `ManagedProcessor.diarize`가 meta에 기록. `reusableNemotron`에 `meta.inputLevel?.version == NemotronInputLevel.version` 추가. `NemotronJourneyTests` (FakeDiarizer는 Record를 돌려주도록 보조물 수정): ⓐ 새 Run meta에 `inputLevel` 키 · version v1 ⓑ `inputLevel` 없는 meta → `reusableNemotron` nil ⓒ v1 → 재사용, diarizer 호출 0 (현행 :73–80 단정 유지) ⓓ version «nemotron-input-level-v0» → nil (`testReuseKeyRejectsEachChangedField` 변경 목록에 2항 추가, 기존 6항 유지) ⓔ 기존 형태 meta JSON 리터럴 (키 13개) 해독 → 재인코딩 바이트 동일 (`.sortedKeys`). :507 기존 자식 재개 경로 diff 0.
- [ ] AC-04 어절 안 미상 조각 (D-01 · §02-2, 축 4 · INV-03 · INV-08): `SonioxPrecisionReconciler.applying(… fillsWordFragments: Bool = false, continuesWithinWords: Bool = false)`, :79 다음 · :86 앞에 단계 1개. 어절(`orthographicGroups`)마다 lexical 중 배정 화자 집합이 정확히 {S}이고 미배정 lexical ≥ 1이면 그 토큰을 S로: `sourceIntervalIds` = 자기 ∪ 같은 어절 배정 lexical 근거 (중복 제거·정렬) · `alignmentScore` nil · overlap·boundary는 자기 `direct` 값. 합성 (`SonioxNemotronReconcilerTests`, v4): ① 현행 ⑧ 토큰 («같·이·요?») → [a, a, a], «이» 근거 = 자기 ∪ «같»·«요», `alignmentScore` nil, «이»의 `ambiguous_speaker` 0 ② 배정 {a, b} 갈린 어절 + 미상 → 미상 null 유지 ③ 어절 전체 미상 → 전부 null · `ambiguous_speaker` 유지 ④ 0길이 미상 조각 (start = end, 단독 구간 없음) → 맞춤 ⑤ v3로 같은 입력 → 현행 값 (맞춤 없음). P2 경로 (`fillsWordFragments` 기본 false) 출력 불변 = AC-06 P2 골든.
- [ ] AC-05 Turn 구성 (D-03 · §02-3, 축 5 · INV-05 · INV-06 · RC-01 · RC-03 · RC-10): `speakerTurns`에서 `continuesWithinWords`일 때만 ⓐ T1: 같은 화자 · 두 토큰이 같은 어절 → :349–351 다른 화자 구간 장벽을 보지 않음 ⓑ N1: 둘 다 화자 nil · 같은 어절 · `right.ordinal == left.ordinal + 1` · `asrSpeakerLabel` `==` (읽기 v8 :62–65와 같은 술어) → 합침. 두 경우 모두 :347 시작 순행 · :348 marker·중단 장벽 · `modelSpeakerId ==` · 양쪽 시간 존재는 그대로. 합성 (v4 vs v3): ① 어절 안 A 토큰 2개 사이 틈에 B 일반 구간 (B 구간이 lexical과 겹쳐 marker 없음) → v4 1 Turn · v3 2 Turn ② 어절 사이 A → B «네» → A → 3 Turn (현행 `testShortInterjectionStaysSeparateTurnBetweenSameSpeaker`, 기본 버전 v4로 유지 PASS · RC-01) ③ 어절 사이 누락 marker (현행 `testMissingShortSpeakerTextLeavesMarkerAndBarrier` PASS · RC-03) ④ 어절 안 누락 marker → 끊김 ⑤ 어절 안 `capture_interrupted` 구간 → 끊김 ⑥ 같은 어절 미상 조각 2개 (같은 라벨) → 1 Turn ⑦ 같은 어절 미상 · 라벨 다름 → 2 Turn ⑧ 다른 어절 미상 → 2 Turn. 전부 `TranscriptValidator` 통과 (INV-04 · INV-05).
- [ ] AC-06 결합 버전·골든·가드 이동 (§02-6, 축 7 합성): `Version.v4 = "soniox-nemotron-word-v4"` · `unifiesSplitWords` = v3 · v4 · `continuesWords` = v4만 (두 매개변수에 넘김) · `currentVersion = .v4`. 저장 v1–v3 parent 재개 = 저장 버전 (:304–305 · :543 diff 0). 골든: `DAMA_CAPTURE_NEMOTRON_GOLDENS=1` 1회 → `fixtures/nemotron-goldens.synthetic.json` 키 15 → 20 (5 사례 × v4), HEAD 판 15키 값 = 새 판 같은 키 값 (해독 대조, 줄 diff 아님). P2 `fixtures/policy-goldens.synthetic.json` 35지문 · `normalization-goldens` 21 diff 0.
  - 가드 이동: G-07 `SonioxNemotronReconcilerTests.swift:88` v3 → v4 · G-08 :195 `[a, nil, a]` → `[a, a, a]` (기본 버전 = v4, AC-04 ①) + v3 고정 단정 `[a, nil, a]` 1개 추가 (저장 v3 재현 축) · G-09 `NemotronJourneyTests.swift:48` · :51 · :180 v3 → v4.
  - 역뮤테이션: `currentVersion = .v3` → 붉음 ≥ 5 (G-07 · G-08 · G-09 ×3, 건수 기록) · v4에서 `fillsWordFragments` false → AC-04 붉음 · `continuesWithinWords` false → AC-05 ① · ⑥ 붉음.
- [ ] AC-07 읽기 v9 (D-02 · §02-4, 축 6 · INV-05 · INV-10): `ScriptReadingPolicy.algorithmVersion = "reading-v9"`, 상수 `unknownWordGapUs: Int64 = 300_000` («외부 설계 초기값» 04 §7). :57–66 조건 실패 시 v9 조건을 OR로 본다: 원문 공백 보존 엔진 (:36) · 앞 문단 anchor의 마지막 lexical (ordinal 최대)과 다음 Turn 첫 lexical의 `asrSpeakerLabel` 둘 다 있음 · 같음 · 두 ordinal 사이 모든 단어가 punctuation · 둘 다 시간 있음 · 다음 start − 앞 end ≤ 300_000. 화자 null 유지, Turn·이슈 불변. 사람 문단 편집·수동 나눔 우선 (`blocks()` :153–159 불변) · :40 `humanEdited` 제외 · :55 이름 비교 유지. 합성 (managedSoniox): 전부 만족 → 1문단 «화자 미확정» · 간격 300_000 → 이음 · 300_001 → 안 이음 · −1 (겹침) → 이음 · 조건 하나씩 어김 → 안 이음 (엔진 hybridPyannoteWhisperKit · 라벨 다름 · 라벨 한쪽 nil · 사이 lexical 1개 (Turn 순서 ≠ ordinal 순서로 구성) · 시간 nil · 수동 나눔 `split: true` · 이름 붙인 미상 Turn 이름 다름). 기존 읽기 단정 붉음 0 예상 (정적 검토: `ScriptPeopleAndDeletionTests` 미배정 2문단 = 라벨 없음 + 간격 500ms · `ReadingDecorationTests` · `ReadingTokenBoundaryTests:63` = 다음 Turn 화자 있음), T-04 check로 확인.
  - (/build 실측 정정) 위 «기존 읽기 단정 붉음 0 예상»은 틀렸다: Markdown 머리 :230 «- 문단 표시»가 읽기 버전을 찍어 골든 3종 76키 (정규화 21 · P2 정책 35 · Nemotron 20) 의 Markdown 지문이 바뀌고, 정규화 골든 `overlap-boundary-and-unrepresented/combined` 1키는 읽기 지문도 바뀐다 (P2 결합본 미상 «겹말» · «경계», 같은 라벨 «one», 간격 300 ms → v9 이음, 스펙 §03-1 «기존 결과에도 적용»). 골든은 대상 이동 (각 파일 기존 인코더로 재캡처, 줄 diff 77 = Markdown 76 + 읽기 1). normalized 지문 76/76 불변. 증명 = 버전 문자열만 v8로 되돌리고 HEAD 골든을 넣으면 실패 1키 (그 사례) 뿐.
  - 가드 이동 G-05: `CorrectionTurnIsolationTests.swift:280` `baselineSHA` (Markdown :230이 v9를 찍음) → 같은 합성 스크립트를 T-04 뒤 코드로 만든 SHA (크기 1,564 B 유지 확인) · 단정 :283 · :301 2개. 역뮤테이션: 버전 v8 → 2 붉음 · v9 조건 제거 → 위 합성 «이음» 사례 붉음.
- [ ] AC-08 응답 짝짓기·규칙·엔진 (D-04 · §02-5 ① ⑤, 축 9): `CorrectionRejectionRule` += `missing` · `chunk` (allCases 8, 순서 quote · overlap · text · limit · reason · other · missing · chunk), `isNoResponse` = missing · chunk. `public enum CorrectionFormatDetail: String, Codable, Sendable, CaseIterable { noOutput, tooLarge, decode, missingArrays, idDuplicate, idUnknown, idOrder, idTooFew }`. `ContextCorrection.replyMismatch(_:chunk:) -> CorrectionFormatDetail?` 검사 순서 = idDuplicate → idUnknown → idOrder (R이 I의 부분열 아님) → idTooFew (|R| < ⌈|I|/2⌉) → missingArrays (받은 Turn 중 changes · unresolved 하나만 nil). `validated`는 이것이 nil 아니면 현행처럼 `LibraryFailure.invalidScript` throw (오류 형식 불변), 아니면 받은 Turn을 v7대로 판정하고 빠진 Turn을 `missing`으로 `rejected`에 넣음 (입력 순서, 검증 실패와 섞어 정렬). `version = "context-correction-8"`. 합성 (I = [a, b, c], ⌈3/2⌉ = 2): [a, b] → c · missing · [a, c] → b · missing · [a(quote 위반), c] → [a · quote, b · missing] · [a] → idTooFew · [] → idTooFew · [a, a, c] → idDuplicate · [a, b, x] → idUnknown · [b, a, c] → idOrder · [a, b, c(unresolved nil)] → missingArrays. 경계: |I| = 4 → 2 받음 · 1 idTooFew / |I| = 5 → 3 받음 · 2 idTooFew. 이름 검증은 원문 Turn 기준 그대로.
  - 가드 이동: G-01 `MeaningGuardTests.swift:67` · G-02 :106 · G-03 `CorrectionTurnIsolationTests.swift:205` v7 → v8 · G-04 :75 allCases 6 → 8 · G-05' :172 `[a, b]` 사례 → throw 대신 `rejected == [c · missing]` (나머지 3사례 throw 유지). 역뮤테이션: 짝짓기를 완전 일치로 되돌림 → 위 받음 사례 + G-05' 붉음 · 버전 v7 → 3 붉음.
- [ ] AC-09 저장 (§02-5 ④, 축 11 · INV-09): `CorrectionFailureRecord` 선택 키 `retry: Int?` (0 · 1 · 2) · `detail: CorrectionFormatDetail?` · `expectedTurns: Int?` · `returnedTurns: Int?` (CodingKeys 추가, `encodeIfPresent`, exitCode 명시 null 유지, init 기본 nil). `ScriptCorrection.failures: [CorrectionFailureRecord]?` (nil이면 키 생략). `rejectedCount(in:)` = 검증 실패 6종만 · 신규 `noResponseCount(in:)` = missing · chunk. `reapplyingPending`이 `failures`도 옮김. 합성: ⓐ 현행 형태 리터럴 3종 (실패 기록 1건 든 시도 기록 · `failures` 없는 교정 스크립트 · `rejectedTurns` 6종만) 해독 → 재인코딩 바이트 동일 ⓑ 새 키 왕복 (retry 2 · detail idTooFew · 100/12) ⓒ 규칙 «bogus» · detail «bogus» → 해독 실패 → 목록 제외 `.unreadable` (현행 분류) ⓓ `missing` · `chunk` Turn도 현행 저장 검증 (발화 안 · 중복 없음 · edits와 겹침 없음) ⓔ 교정 저장 전후 `transcript` 인코딩 바이트 동일.
- [ ] AC-10 재시도·완주 (D-04 · §02-5 ② ③, 축 10, 가짜 CLI): `CorrectionRunner` 상수 `retryDelay = .seconds(5)` · `maximumRetries = 2` · `consecutiveSkipLimit = 2`, init `wait: @Sendable (Duration) async throws -> Void` (기본 `Task.sleep`), `run(…, progress:, retrying: @Sendable (Int?) async -> Void = { _ in })`. 실패마다 기록 1건 (`retry` = 그 청크 몇 번째 재시도) · 저장. auth · config · unavailable · cancelled → 즉시 `.failed`. format → 즉시 재시도 · timeout · network · unclassified → `wait(5초)` 뒤 재시도 (wait 중 취소 → cancelled). 재시도 소진 → 건너뜀 (메모리), 연속 2개 → `.failed` (건너뛴 청크는 remaining에 남음). 성공이 나오면 연속 수 0. 끝까지 가면 `attempt.results` (건너뜀 추가 전) 0개 → `.failed(마지막 오류)`, 아니면 건너뛴 청크마다 결과 (편집 0 · 그 청크 Turn 전부 `chunk`)를 반환 attempt에만 추가 (저장소에는 쓰지 않음) → `.completed`. progress k = 성공 + 건너뜀. 어댑터 `CodexCorrectionError.detail` (+ `expectedTurns` · `returnedTurns`) : :227 · :229 nil/0 B = noOutput · > 2,000,000 B = tooLarge · :230 decode · :231 missingArrays. 가짜 CLI: `fail-at` = 범위 «a-b» · `fail-kind` (auth = «ERROR: 401 Unauthorized» exit 1 · config = «error: unexpected argument» exit 2). 기준선 = 12청크 한 번에 호출 12 (`CorrectionRunnerTests.swift:99`). 사례 (wait 기록 주입):
  - fail-at 5 → `.completed` · 호출 13 · edits 1,200 · wait [5s] · 실패 기록 1 (unclassified · retry 0) · retrying [1, nil]
  - fail-at 5-7 → `.completed` · 호출 14 · 결과 12 · chunk 4의 100 Turn 전부 `chunk` · edits 1,100 · names 1 · wait [5s, 5s]
  - fail-at 5-10 → `.failed` (unclassified) · 호출 10 · 완료 4 · remaining 4..<12 · 실패 기록 6 (retry [0,1,2,0,1,2]) → 이어서 교정 → 호출 18 · `merged()` = 한 번에 끝낸 기준선
  - 형식 (garbage) · 1청크 스크립트 → `.failed` · 호출 3 · wait [] · detail decode ×3 (성공 0 → failed)
  - auth · config → 호출 1 · `.failed` · 실패 기록 1 (retry 0) · 실행 파일 없음 → unavailable · 호출 0 · wait 취소 → cancelled · 호출 1
  - 완료 조립: DamaCore `ScriptCorrection.complete(with: CorrectionAttempt, at: Date)` (edits · names · evidence · rejectedTurns · failures (빈 목록 → nil) · completedChunks = total · state completed). 5-7 사례 → `failures` 3건 · retry [0,1,2].
  - 가드 이동 G-11 (`CorrectionRunnerTests.swift`, wait 기록 주입): `testFailAtFifth…` :106 «5» → «5-10» · :114 chunkIndex 4 → 5 · :124 13 → 18 (:110–113 · :115 · resumeState · merged 유지) / `testPlanOrEngine…` :150 «1» → «1-6» (단정 유지) / `testResumeKeepsRejected…` :227 → «5-10» · :236 13 → 18 / `testUnpairableReplies…` :253 1 → 6 (garbage · swap · missing) · drop 사례 → `.completed` · 호출 12 · `merged().rejected` = 청크마다 끝 Turn `missing` 12 · edits 1,188 + detail 단정 (garbage decode · swap idOrder · missing missingArrays). 역뮤테이션: `maximumRetries = 0` → 재시도 사례 붉음 · 연속 한도 무시 → 5-10 사례 붉음.
- [ ] AC-11 문구·화면 (§03 · 문구 6–11, 축 12): `CorrectionRejectionText` 신규 = `noResponseTitle` «원문 유지 · AI 응답 없음» · `noResponseNote(count:)` «AI 응답을 받지 못해 이 문단은 원문을 유지했습니다.» (+ k ≥ 2 « ({k}개 원구간)») · `noResponseSuffix(count:)` M ≥ 1 « AI 응답을 받지 못한 {M}개 원구간은 원문을 유지했습니다.» · `completionMessage(rejectedCount:noResponseCount: = 0)` = 현행 + 문구 3 + 문구 8 순 · `markdownNoResponseSummary(count:)` «- 응답 없음으로 원문 유지: {M}개 원구간» · `markdownNoResponsePrefix` «> AI 응답 없음: » · `retrySuffix(_:)` « · 응답 다시 받는 중 ({r}/2)». 단위: k = 1 · 2 · 3, N · M ∈ {0, 1, 12} 조합, r = 1 · 2 글자 그대로 (tone 표 대조). N = M = 0 → 완료 문장 = 현행 리터럴 바이트, Markdown = 같은 코드의 `rejectedTurns` nil 출력 바이트. 기존 `testRejectionTextMatchesToneTable` 단정 불변.
  - Markdown: :241 조건 = 검증 실패 수 N ≥ 1 (missing만 있으면 문구 4 없음) · 그 다음 줄 M ≥ 1이면 문구 9 · :275–278 다음에 문단 k ≥ 1이면 문구 10 + 문구 7 한 줄과 빈 줄. 합성 = 검증 실패 1 + missing 2 (같은 문단) + chunk 1 (다른 문단).
  - 화면: `CorrectionWorkspace` 완료 = `complete(with:)` + `completionMessage(rejectedCount: N, noResponseCount: M)` · `@Published private(set) var retry: Int?` (retrying 콜백, 시작·끝 nil) · `ScriptReadingView` :106 뒤 `retrySuffix` · :271 다음 · :272 앞 응답 없음 블록 (`VStack(alignment: .leading, spacing: 6)` { 문구 6 `.fontWeight(.semibold)` · 문구 7 } `.font(.caption)`, 조건 `noResponseCount(in: block.turnIDs) ≥ 1`). 자 = 단위 + 코드 대조 (QA). 실화면은 게이트 ② 사용자 관측 (합성 QA 앱은 AI 실행 차단 `CorrectionWorkspace.swift:95` · :104, 선례 F-03).

### 차수 B · 실데이터 (이 Mac, 읽기 전용, 네트워크 0)

출력 = 숫자 · ID 앞 8자 · `.build/qa/turn-continuity/` (미커밋). 사용자 데이터 쓰기 0. Nemotron 실행은 건별 300초 무진행 워치독 (저장 처리 1.2–17.0초의 5배 + 모델 적재 여유, PID 판정).

- [ ] AC-12 앱 경로 음량 (축 3): `NemotronAppRun` 확장 (앱 `FluidNemotronDiarizer` · 확률·Record 저장). 4개 meta gainDb = 0.00 · 22.97 · 17.06 · 13.83 (±0.01, 위 P90 실측) · `9F73A02B` 확률 = 저장 `3362D8E6` 확률 바이트 동일. 85 · 47 · 141분의 무음 판정 단어 비율 (Soniox lexical 구간에 0.5 초과 채널 프레임이 하나도 없는 단어 ÷ lexical) 과 단독 배정 유지율 (원본 · 맞춤 둘 다 단독 배정인 단어의 채널 대응 일치율)을 스펙 표 3 (16bit 사본 3.13→0.71 · 0.94→0.63 · 6.04→5.19 %, 유지 99.6 · 98.1 · 99.2 %) 옆에 기록. 문턱 없음 (정확도 아님).
- [ ] AC-13 저장 Run 재현 (축 7 실데이터): `7A430186` (v3)을 저장 Soniox 원응답 + 저장 확률 + 저장 Run ID · 생성 시각 · v3로 재결합 → `NormalizedTranscriptCodec.encode` 바이트 = 저장 `normalized/model.json` 바이트.
- [ ] AC-14 실데이터 결합 (축 8): 6개 녹음 = 저장 Soniox 원응답 + AC-12 실행기 확률 (나머지 2개 `AB66A52D` · `7A430186`도 같은 실행기) → v4 결합 → `TranscriptValidator` 6/6 · `LibraryScript.blocks()`. 기록: 미배정 lexical % · 발화 Turn · 미상 발화 Turn · 어절 중간 Turn 경계 · 문단 · 화자 미확정 문단 · 어절 중간 문단 경계, 현행 (위 사전 확인 · 스펙 표 1 · 2) 옆. 스펙 모의값은 참고 (문턱 아님, 모의 N1은 ordinal · 라벨 조건 없음).

### 전달

- [ ] AC-15 회귀 (축 13): check.sh 1–4 PASS · swift test 실행 ≥ 362 + 신규 · skipped 2 유지 · 실패 0 · 테스트 이름 삭제 0 · 완화 0 (이동 = G-01–G-11뿐, 각 역뮤테이션 기록) · `git diff 200f7d8 -- Packages/DamaCore/Tests/DamaManagedTests/CorrectionFormatProbeTests.swift` 빈 출력.
- [ ] AC-16 버전·설치: `MARKETING_VERSION` 0.5.21 · `CURRENT_PROJECT_VERSION` 39 (Debug/Release). 설치 (막힘 1) 뒤 실행 중 Bundle 0.5.21 (39) (`lsappinfo` · Info.plist), 메뉴바 툴팁 = 사용자 관측.
- [ ] AC-17 실데이터 게이트 ② (축 14, 막힘 2): 사용자가 설치 앱에서 30분 안팎 Nemotron 결합본 1개를 «다시 전사» (Soniox 재사용 · Nemotron 로컬) → «AI 검수/보정» 1회. 메인이 메타데이터로 잰다: 새 parent 버전 v4 · 자식 meta `inputLevel` · 이어서 교정 없이 끝났는지 · 상태 · 완료/전체 청크 · 재시도 수 · 건너뛴 청크 · 규칙별 원구간 수 · `failures` 세부 · 화자 미확정 문단 수 (현행 Run 옆). 문턱 없음 (모델 응답에 달림). 완료 띠 · 진행 줄 글자는 사용자 관측.

## 작업 분해

- T-01 계약 개정 (AC-01): 문안 §05 전부. 문서만.
- T-02 입력 음량 (AC-02 · AC-03): `NemotronInputLevel` · `LocalDiarization` · `NemotronMeta` · `FluidNemotron` · `ManagedProcessor` · FakeDiarizer · 역뮤테이션 2.
- T-03 결합 v4 (AC-04 · AC-05 · AC-06): reconciler 매개변수 2 · `Version.v4` · `currentVersion` · 골든 캡처 · G-07–G-09 · 역뮤테이션.
- T-04 읽기 v9 (AC-07): `ScriptReadingStructure` · `ScriptReadingPolicy` · G-05.
- T-05 교정 짝짓기·저장 (AC-08 · AC-09): 규칙 8 · `CorrectionFormatDetail` · `replyMismatch` · `validated` missing · 실패 기록 키 · `ScriptCorrection.failures` · 개수 함수 · 재반영 · v8 · G-01–G-04 · G-05'.
- T-06 실행기 (AC-10): 재시도 · 건너뜀 · 멈춤 · 어댑터 detail · `complete(with:)` · 가짜 CLI · G-11.
- T-07 문구·화면 (AC-11): `CorrectionRejectionText` · Markdown · `CorrectionWorkspace` · `ScriptReadingView`. **차수 A 경계**: check.sh 1–4 + QA A (AC-01–11).
- T-08 실데이터 측정 (AC-12–14): `NemotronAppRun` · `NemotronCombine` 확장, 6개 녹음 실행, 기록. QA B.
- T-09 전달 (AC-15–17): 버전 0.5.21 (39) · 설치 (막힘 1) · 게이트 ② 측정 (막힘 2). QA 전달.

구현 = 메인 직접 (프로젝트 CLAUDE.md «메인이 Opus면 직접 구현», correction-turn-isolation 선례). 태스크마다 check.sh 1–3, 앱 빌드는 차수 경계 1회. 커밋 = 태스크마다 pathspec.

## 결정 항목

없음. 스펙이 열어 둔 자리는 아래로 닫았다 (새 정책 아님, AC에 값으로 박음):
- 음량 함수 위치 = DamaManaged (AC-02). 스펙 «DamaManaged 또는 DamaNemotron», DamaNemotron은 check.sh 밖이라 축 1을 잴 수 없다.
- P90 산법 = numpy 선형 보간 (AC-02). 표 3 실험 `prep.py`와 같고, 실측 이득 4점이 스펙 표 3 값과 0.04 dB 안에서 맞았다. 적용 이득 = 기록값 (소수 2자리) 으로 meta와 처리를 일치시킴. 창 0개 = 처리 없음 (현행 동작 유지 방향).
- N1의 라벨 비교 = 읽기 v8 :65와 같은 `==` (AC-05). Turn 데이터가 읽기 화면이 이미 잇는 범위와 같아진다 (스펙 표 2 «N1+T1만 적용하면 문단 현행과 같다»).
- 짝짓기 오류 형식 = 현행 `LibraryFailure.invalidScript` 유지, 세부는 `replyMismatch`로 따로 (AC-08). `CorrectionFormatProbeTests` · 기존 오류 형식 단정 보존. 세부 검사 순서 = 스펙 ④ 나열 순서.
- 건너뛴 청크 결과는 반환 attempt에만 (AC-10). 스펙 ③ «메모리에만 두고 시도 기록의 끝난 청크로 쓰지 않는다» · 완료 저장 전 앱이 죽으면 이어서 교정이 다시 보낸다.
- 재시도 대기 주입 = 테스트 시간 (wait 기록) 과 «형식 즉시 · 그 밖 5초» 판정을 같은 자로 잰다 (AC-10).
- 기대 호출 수 = 기준선 12청크 실측 (`CorrectionRunnerTests.swift:99`) 에서 산출 (스펙 축 10 «/plan이 기준선 실측으로 확정»).

## 막힘 (사용자 실행·승인 항목)

1. 설치 앱 교체 1회 (T-09, 0.5.21 (39)): 실행 중 앱 0.5.20 (38) 종료 포함. 승인 후 메인 실행, 백업 `.build/backups/DAMA-0.5.20-38-before-turn-continuity.app` 파일 수 · SHA256 대조 뒤 교체.
2. 실데이터 게이트 ② (AC-17): 사용자 실행. «다시 전사» = Soniox 재사용 확인창 + Nemotron 로컬 (meta 6/6 `inputLevel` 없음 → 재사용 안 함). «AI 검수/보정» = OpenAI 전송 · Codex 사용량. 대상은 사용자가 고른다.
3. 실데이터 로컬 측정 (AC-12–14): 게이트 ① 축 3 · 7 · 8로 확정된 측정. 읽기 전용 · 네트워크 0 · 위 출력 규칙. 추가 승인 없음.
4. 안 잼 (스펙 §04): 화자 배정 정확도 (E1 · E2, 원음 청취 없음) · 141분 녹음 청취 밖 무음 81–87% 원인 · 교정 품질과 «형식» 하위 원인 분포 · 새 문장 키보드 · VoiceOver (묶음 5).

## Follow-ups

- F-01 (기록) v8 뒤 `CorrectionFormatProbeTests` (환경변수 게이트) 의 `r["validated"]`는 일부 Turn이 빠진 응답에서도 true가 된다. 코드 불변 (AC-15). 진단을 다시 돌리면 `replyMismatch`로 읽는다.
- F-02 (기록) 프롬프트 :176 «모든 id를 입력 순서 그대로 정확히 한 번씩» 은 그대로다 (스펙이 바꾸지 않음). 부분열 수용은 받는 쪽 규칙이다.
- F-04 (기록) `scripts/validate_contracts.py`의 Python 장벽 검사는 INV-06 v4 단서를 넣지 않았다. 합성 fixture 전용이고 v4 입력이 없다 (check 1단계 31 OK). v4 export를 그 스크립트로 검사할 일이 생기면 같은 단서를 넣는다.
- F-03 (실데이터) v7 이하 미완료 시도 2건 (`AB66A52D` 5/8 · `44F4E8DD` 0/44) 은 v8 설치 뒤 «이어서 교정» 대신 이어하기 불가 문구 (`usage-bundle1.md:60`). 새로 시작할지는 사용자.

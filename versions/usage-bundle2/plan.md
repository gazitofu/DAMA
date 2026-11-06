---
unit: usage-bundle2
branch: work/m0-fixture-review
status: building
decisions_resolved: true
resume: "building. T-01–T-09 구현·QA A/A3/B 반영, T-10 버전 커밋(1727e31) 뒤. 남은 것 = 게이트 ② 상신(설치·실데이터 정리·실화면·문언 정정 F-04/05/06). check.sh는 `bash /Users/gazitofu/Developer/Dama/scripts/check.sh` (대문자 절대경로)로만 돌린다."
spec: notes/usage-bundle2/usage-bundle2.src.html
---
## 근거

- 컨펌: `notes/usage-bundle2/usage-bundle2.src.html` `#s-verdict` `data-state="closed"` (게이트 ① 11.06, D-01–D-04 ⓐ, 판정 축 ①–③). 확정 문구 `ssot/tone/usage-bundle2.md` (`ca0f13d`, 문구 1–23, 19 결번). 입력 결정 `notes/usage-review/decisions.md` T2a 1–4.
- 규율 메모리 14종 (`~/.claude/projects/-Users-gazitofu/memory/`): rule-purpose-first · rule-ambiguous-instructions · rule-scope-stop · rule-gate-hygiene · rule-measurement · rule-negative-claims · rule-carryover-remeasure · rule-verify-at-consumption · rule-delegation-artifacts · rule-destructive-writes · rule-shared-tree-commits · rule-numeric-test-integrity · rule-external-media-verify · rule-longrun-watchdog. 추가 rule-branch-base-is-main. 프로젝트 메모리 pyannote-dropped · advisors-fable-astra.
- `ssot/dev.md` §1–7 · `ssot/api/pyannote-verified.md` (이 유닛 외부 API 호출 0, 참조만) · `ssot/design/00_README.md` 하이브리드 채택 · `02` §9 (:156–160 재처리 새 Run · 삭제 구분 확인) · `04` §3 INV-09 (:52) · `06` §2 RC-13.
- 계약 실측 인용 (이 유닛은 schema·DomainContracts를 바꾸지 않는다):
  - `transcript.v1.schema.json` `$defs/revision` `humanEdited` (:504, required :516) · `$defs/word` `editedText` (:165, required :260).
  - `DomainContracts.swift:188–205` `RevisionMetadata.humanEdited: Bool` · `:58` `TranscriptWord.editedText: String?` · `:104–129` `TranscriptTurn`에 humanEdited 필드 없음.
  - 개정 대상 줄 = 스펙 §05와 일치 실측: `library-script.md` :43 · :44 · :66 · :72 · :91 · :92 · :182 · :193. `operating-baseline.md` :11 · :36 (불변) · :73 (개정). `CLAUDE.md:20` 경계 6.
- 사전 확인 (2026-11-06 22:10–22:20 KST):
  - HEAD `ca0f13d`, `git status` clean. branch `work/m0-fixture-review` 유지: 17유닛 선례(`versions/usage-bundle1/plan.md:21`), 로컬이 origin보다 4커밋 앞(미push)이라 전환 금지(rule-shared-tree-commits). `git merge-base HEAD main` = main `3031fd4`. `main..HEAD` 4 = 문서 커밋(nemotron plan 2 · 이 유닛 스펙 2). worktree = 이 트리 + prunable scratch 1.
  - check.sh: 소문자 경로 실행 `run-20261106T131025Z-nfR5EE` = 2·4단계 FAIL (`_DarwinFoundation1 is defined in both`, 모듈 캐시 경로 대소문자 충돌, 환경). 대문자 절대경로 `run-20261106T131144Z-GBBT8v` = 계약 31 PASS · byte-exact PASS · SmokeCheck PASS · swift test 303 (Managed 60 / Core 199 / Audio 44) PASS · xcodebuild Debug PASS · SKIP 없음.
  - 도구 Swift 6.4.2 · Xcode 27.2 (27B52) · target arm64-apple-macosx27.2.0 (dev.md §1 기록 6.3.3·26.6과 다름, 이 유닛 판정 대상 아님). 설치 앱 0.5.18 (36) = pbxproj Debug/Release.
- 실데이터 재측정 (읽기 전용, 제목·본문 미출력):
  - `python3 -I notes/usage-bundle2/measure-t2a.py` 22:19 → `/private/tmp/claude-501/-Users-gazitofu-Developer-Dama/7f8fdbcb-d002-42b6-9dc4-e0d137190b48/scratchpad/t2a-plan.json`: 스크립트 38 · 324.0 MB · 사람 수정 22 · 실행 기록 없음 3 · 이력 574 · 10,002.0 MB · 고아 62 · 243.1 MB (스크립트 18) · 남는 512 · 9,758.9 MB → raw DEFLATE 5 651.8 MB (×14.97) · AI 버전 참조 7/7 · baseRevisionID 73 · python 해독 59.6초 · 압축 31.8초. 스펙 11.06 21:22 값과 전부 같다.
  - `retention-sim.py` 보관 2 → 지울 스크립트 0 · 보관 1 → 4 · 24.8 MB. 대표 변경 0/20 (스펙 모의).
  - legacy 표지 (scratchpad `legacy-count.py`): `transcript.revision.humanEdited` 0 · word `editedText` 0 · Turn `humanEdited` 0 · 9필드 22 · 합 22/38.
  - ID: 스크립트 38 · Run 72 전부 대문자 UUID. 실행 기록 없는 스크립트 3개는 모두 실행 기록 있는 녹음 소속.
  - Run stage: readyForReview 67 · partialResult 3 (sonioxPrecision) · waitingForBilling 2 (sonioxPrecision 1 · precision 자식 1). `CorrectionAttempts/` 0 · `storage-cleanup-log.jsonl` 없음.

## 의도

녹음별 스크립트 보관 규칙(최근 2세대 + 사람 수정 보호)과 대표 결과(가장 늦은 createdAt)를 넣는다. 스크립트를 지우면 그 내부 수정 이력과 교정 시도 기록을 함께 지운다. 수정 이력은 새 배치에 raw DEFLATE로 쓰고, 기존분은 설정 «저장 공간 정리…»로 1회 이전한다.

## 영향 범위 (경로 · 현행 실측 2026-11-06)

- `Packages/DamaCore/Sources/DamaAudio/FolderLibraryStore.swift`: :32–51 `LibraryScriptSummary` 8필드 · :54–58 `ScriptListing` · :68–93 `ScriptResultPresentation` (:77 · :84–86 `priority` 엔진 등급) · :268 `summaryVersion = 1` · :349–359 `createScript` (같은 id가 있으면 그것을 반환) · :361–377 `saveScript` → `writeRevision` · :381–386 `revisionFolder`·`revisionURL` (평면 `<revisionID>.dama.json`, UUID 검사) · :387–400 `writeRevision` (`.withoutOverwriting`, 같은 ID면 해독·재인코딩 비교) · :464–472 `snapshot` (sha256 = writeRevision 반환 바이트) · :473–485 `readVersion` (파일 바이트 SHA256 = version.sha256) · :509–528 `validateDeletion`·`trashScript` (해시 검사 → trash, 이력 남김).
- `…/DamaCore/LibraryScript.swift:62–88` 사람 수정 9필드 · `correction` · `showsOriginal` · `versions` · `snapshotTitle`. `…/DamaCore/ScriptVersion.swift:3–20`.
- `…/DamaManaged/CorrectionRunner.swift:4–36` `CorrectionAttemptStore` (`CorrectionAttempts/<scriptID>.json`, ID 문자 검사 :11–16). 의존 방향 DamaManaged → DamaAudio → DamaCore (`Package.swift:16–18`): DamaAudio는 이 store를 부를 수 없다.
- `…/DamaManaged/ManagedProcessor.swift:6–29` `ManagedRun` (id · sessionID · createdAt · stage · parentRunID · sonioxRunID) · :262–264 `begin`은 Run이 있으면 재전사가 아닐 때 `existingRun` · :485–496 자식 생성·재사용 모두 `run.sonioxRunID = asr.id`.
- `App/LibraryWorkspace.swift`: :53 `canLeave` · :67 `primaryScripts` · :76 `foldersLocked` · :167–200 `refresh` (`scriptsLoading` · `scanIssues[.scripts]`) · :285–287 `completedScript` → `primaryFile` · :342–356 `deleteScript` (:345 설명 · :353 완료 문장) · :357–363 `confirmDeletion` · :365–386 `convert` (readyForReview인데 스크립트 없음 → `processingFinished(run)`, :386 스크립트가 있으면 선택만) · :402–430 `processingFinished` (:403 P2·Nemotron 자식 제외 · :415 `createScript` · :418–421 select=false면 `library.savedSourceRuns` · :424 완료 문장).
- `App/ProcessingWorkspace.swift`: :11 `runs` · :129–140 `refreshRuns` · :142–144 `historyAllowsProcessing` · :160–265 `reviewTransmission` (:205–210 재전사 문단, :206 «기존 스크립트와 사용자 수정은 유지하고 …» · :217–226 sonioxPrecision · :227–236 sonioxNemotron, :232 «완료된 결과는 보존하고, …» · :237–240 접수 불명) · :279–285 `saveCompletedSources` (:283 `processingFinished(run, select: false)`) · :287–327 `launch` (:317 readyForReview → `processingFinished(result)`).
- `App/CorrectionWorkspace.swift:22–25` `queue` · `activeID` · `busy`.
- `UI/LibraryShell.swift:238–285` `LibrarySettings` (:267 «내부에 보존된 녹음을 Speeches에 저장» · :271–272 `Divider`·`APIKeySettings` · :280 width 470).
- `…/DamaCore/TranscriptionProvider.swift:6` `selectable = [.sonioxNemotron, .soniox]`.
- `AudioStorage.swift:47–61` 합성 QA 앱(`com.gazitofu.Dama.ReadingQA` · `--reading-fixture-root /private/tmp/dama-reading-qa-*`)은 내부 저장소가 `<fixture>/internal`로 격리된다.
- 테스트 가드: `LibraryJourneyTests.swift:26–34` (단정 4) · `ManagedJourneyTests.swift:148` · `ScriptVersionTests.swift:111–113` · `LibraryTitleTests.swift:89 · 94 · 95`.
- 문서 (/build 개정, D-04): `CLAUDE.md:20` · `ssot/contracts/library-script.md` · `ssot/contracts/operating-baseline.md:73`.

## 수용 기준

«문구 N» = `ssot/tone/usage-bundle2.md` 번호. QA 판정 = GPT-6.1-sol (`codex exec -m gpt-6.1-sol --sandbox read-only --ignore-user-config`, usage-bundle1 F-02 형식). 키체인·설치 앱·사용자 데이터 집계·실화면 수집은 메인이 실행하고 판정만 넘긴다. 차수: A = AC-01–06 · B = AC-07–11 · 전달 = AC-12–13. 공통: 각 태스크 뒤 check.sh 1–3단계 PASS, swift test 수 ≥ 303 + 신규, 기존 테스트 삭제·완화 0(이동은 아래 명시분만, 역뮤테이션 붉음 건수 기록).

### 차수 A · 계약·저장소 (합성)

- [ ] AC-01 계약·문구 (D-04): 스펙 §05 10곳 문안이 그대로 들어갔다. 대상 = `CLAUDE.md:20` · `library-script.md` :43–44 · :66 · :72 · :91 · :92 · :182 · :193 · 새 절 «결과 보관 (usage-bundle2)» · `operating-baseline.md:73`. 새 절의 사람 수정 판정은 legacy 표지를 계약 필드로 쓴다: `transcript.revision.humanEdited == true` 또는 word `editedText != nil` (F-02). 고치지 않는 것 diff 0: `04_DATA_AND_RECONCILIATION.md:52` INV-09 · `CLAUDE.md` 함정 3 · `02` §9 · `operating-baseline.md:11 · :36`. 자 = 문안 대조(QA), 모집단 = 10곳. `validate_contracts.py` 31 OK.
- [ ] AC-02 대표 결과 (T2a-2): `primaryFile` = createdAt 최대, 같으면 id 사전순 앞(현행 동률 규칙). 엔진 등급 코드 0: `git grep -n 'priority' -- Packages/DamaCore/Sources/DamaAudio/FolderLibraryStore.swift` = 0줄.
  - 가드 이동 `LibraryJourneyTests.swift:26–34`, 단정 4 유지: `primaryFiles([soniox 300, olderCombined 100, newerCombined 200, otherSpeech 400])` = [otherSpeech, soniox] · `primaryFile([soniox, olderCombined, newerCombined])` = soniox · `([laterSoniox 600, newerCombined, nemotron 500])` = laterSoniox · `([nemotron, newestP2 700])` = newestP2.
  - 역뮤테이션 (엔진 등급 되살리기): 붉음 3 (단정 1·2·3), 단정 4는 두 등급 같아 녹색. 복원은 보관한 원본 바이트로, 해시 대조.
  - 고정 동률 사례 1: createdAt 같은 두 결과 id `0…` · `F…` → `0…`.
- [ ] AC-03 사람 수정 판정·요약 캐시: `LibraryScript.hasHumanEdits` = 9필드(turnTexts · turnNames · turnSpeakerIDs · registeredSpeakers · nameHistory · deletedParagraphs · paragraphBreaks · paragraphEdits · reviewRecords) 중 하나라도 nil 아님·비어 있지 않음, 또는 `transcript.revision.humanEdited`, 또는 word `editedText != nil`. 제목·`showsOriginal`·`correction`만 바뀐 결과 = false.
  - 합성 14사례: 9필드 단독 9 true · revision.humanEdited 1 true · editedText 1 true · 아무것도 없음 · 제목만 · AI 교정만 각 false.
  - `LibraryScriptSummary.hasHumanEdits` 추가, `summaryVersion` 1 → 2. 구 버전 캐시가 있는 폴더 첫 조회 = 파일 수만큼 해독(`scriptDecodeCount`), 둘째 조회 = 0.
- [ ] AC-04 보관 규칙 (T2a-1, INV-09 · RC-13): 순수 계산 `ScriptRetention` (DamaAudio). 입력 = 요약 목록 + 실행 연결 `id → (parentRunID?, sonioxRunID?)` + 건너뛸 결과 ID + 건너뛸 녹음 ID + 선택 가상 세대(확인창용: 시각·대표 id·구성 id). 출력 = 녹음별 남김·정리 집합. 보관 세대 수 2 = 사용자 결정값(T2a-1), 상수 1곳.
  - 세대 = 자식 아닌 결과 + 그 Run의 sonioxRunID가 가리키는 자식 결과(재사용 자식은 가리키는 세대 모두에 소속). 부모 결과 없는 자식·실행 기록 없는 결과 = 혼자 한 세대. 세대 시각 = 대표 createdAt, 내림차순, 같으면 대표 id 사전순 앞.
  - 합성 사례 (C 결합 · S Soniox 자식 · R 실행 기록 없음, 번호 클수록 최근): ① C3(S1)·C2(S1)·C1(S1) → 남김 {C3, C2, S1} 정리 {C1} ② C3(S3)·C2(S2)·C1(S1) → 남김 {C3, S3, C2, S2} 정리 {C1, S1} ③ S3 혼자·C2(S2)·C1(S1) → 남김 {S3, C2, S2} 정리 {C1, S1} (시점 규칙은 AC-07) ④ R·C1(S1) → 정리 ∅ ⑤ C3·C2·C1(C1만 사람 수정) → 정리 ∅ ⑥ 건너뛸 녹음 → 정리 ∅ ⑦ 세대 시각 동률 → 대표 id 사전순 앞이 앞 세대 ⑧ 건너뛸 결과 ID는 정리 집합에 들지 않는다.
  - 역뮤테이션 2종: 사람 수정 보호 끄기 → ⑤ 붉음 · 재사용 소속을 가리키는 세대 중 가장 오래된 하나로 제한 → ① 붉음.
  - 남은 결과의 9필드·transcript 바이트 불변, 다른 Run 결과로의 이름·문장 이식 0 (INV-09 · RC-13).
- [ ] AC-05 수정 이력 배치·압축 (T2a-4 · D-03):
  - ⓐ 새 저장 1회 → `LibraryRevisions/<스크립트 ID>/<revisionID>.dama.json.deflate` 1개 생성, 평면 배치 생성 0. 두 ID 모두 UUID 아니면 `unsafePath`.
  - ⓑ 형식 = raw DEFLATE(RFC 1951), Apple `COMPRESSION_ZLIB` (`NSData.compressed(using: .zlib)`), level 5 고정(SDK `compression.h`). 고정 테스트: 합성 정렬 JSON 바이트 → 압축 → 해제 = 원본 바이트, 첫 바이트 ≠ 0x78 (zlib 머리 없음).
  - ⓒ 새 파일은 같은 폴더 임시 이름에 쓴 뒤 덮어쓰기 없는 이동으로만 생긴다(대상이 있으면 실패). 같은 revisionID가 새·구 배치 어디에 있든 풀어서 해독·재인코딩 비교, 다르면 `changedFile`.
  - ⓓ `readVersion`: 새 배치 → 없으면 구 배치 `<revisionID>.dama.json` → 둘 다 없으면 오류. sha256 = 압축을 푼 바이트 SHA256. 구 배치로 만든 버전이 이전 뒤에도 같은 sha256로 열린다(Scripts 파일 바이트 불변).
  - ⓔ 가드 이동 `ScriptVersionTests.swift:111–113`: (1) 압축 파일 1바이트 변조 → `LibraryFailure` (2) 풀어서 1바이트 변조 후 다시 압축 → `LibraryFailure`. 역뮤테이션 (해시 검사 제거) → (2) 붉음.
  - ⓕ Scripts 활성 파일 바이트 = 정렬 JSON(비압축). `LibraryTitleTests.swift:89 · 94 · 95` 수정 없이 PASS.
- [ ] AC-06 삭제 동반 정리 (T2a-3, 합성): 결과 하나 지우는 순서 = 휴지통 이동 → (자식이면) `library.savedSourceRuns` 등록 → `LibraryRevisions/<id>/` 삭제 → `CorrectionAttempts/<id>.json` 삭제. 이력 파일을 다루는 코드는 `FolderLibraryStore` actor 안에만.
  - 휴지통 이동 성공 → 그 id의 이력 폴더·시도 기록 0, 다른 스크립트 이력 SHA256 목록 불변, `Sessions/` SHA256 목록 불변.
  - 휴지통 이동 실패(해시 불일치) → 이력·시도 기록·savedSourceRuns 불변.
  - 시도 기록 경로 규칙은 한 곳(DamaCore)에서 `CorrectionAttemptStore`와 `FolderLibraryStore`가 함께 쓴다: `git grep -n '"CorrectionAttempts"' -- Packages/DamaCore/Sources App` = 1줄 (기준선 `CorrectionRunner.swift:9` 1줄).
  - 가드 이동 `ManagedJourneyTests.swift:148`: «이력 파일 있음» → «지운 스크립트 이력 폴더 없음 + 남은 스크립트(second) 이력 있음».
  - Script 삭제 확인창 설명 = 문구 6, 이력 삭제 실패 시 완료 문장 = «Script를 휴지통으로 이동했습니다.» + 문구 7 (현행 «원음과 다른 스크립트는 유지됩니다.» 뺌). 성공 시 현행 완료 문장 그대로.

### 차수 B · 앱 흐름·정리

- [ ] AC-07 자동 정리 시점·건너뜀·완료 메시지 (자 = 코드 대조 QA + 합성 단위):
  - 시점: `ProcessingWorkspace.launch`의 readyForReview 결과(:317)로 부른 `processingFinished`에서, `parentRunID == nil`이고 `createScript`가 새 파일을 만든 직후, 그 녹음 하나만. 설정 정리(AC-09)에서 모든 녹음 1회.
  - 정리 안 함: 자식 저장(select=false) · `createScript`가 기존 파일 반환 · `convert`의 재저장 경로(:372) · 앱 시작 · 실패·부분 완료.
  - 녹음 전체 건너뜀: `runHistoryAvailable == false` 또는 그 녹음 `scanIssues` 있음(:142–144 조건). 모든 녹음 건너뜀: `scriptsLoading` 또는 `scanIssues[.scripts]` 비어 있지 않음.
  - 결과 건너뜀 ID = `openedScript` · `historicalFile`의 스크립트 · `savingRunIDs` · `CorrectionWorkspace` activeID·queue.
  - 메시지: 현행 «스크립트를 저장했습니다. 화자와 내용을 확인해 주세요.» 뒤에 옮긴 수 ≥ 1 → 문구 4, 실패 수 ≥ 1 → 문구 5. 실패 = 휴지통 이동 실패(해시 불일치 포함). 건너뛴 결과는 정리 집합에 들지 않아 어느 수에도 들지 않는다. 0이면 붙이지 않는다.
  - 업데이트 전에 시작한 미완료 Run의 재개 완료도 같은 시점 규칙을 따른다. 실데이터 재개 가능 비퇴역 Run 0 (미완료 5 전부 sonioxPrecision/precision).
- [ ] AC-08 재전사 확인창 N·문구 1–3:
  - N = `ScriptRetention`에 가상 세대(대표 = 이 실행, 시각 = 확인창 시점, 구성 = 이 실행 + `sonioxSourceRunID`)를 넣은 정리 수. 확인창과 실제 정리는 같은 함수.
  - 합성: 사례 ① 기존 + 새 결합(S1 재사용) → N = 2 (C2, C1) · 사례 ② 기존 + 새 Soniox 단독 → N = 4 (C2, S2, C1, S1) · 사례 ⑤ 기존 + 새 결합(재사용 없음) → N = 1 (C2) · C1(S1)만 있는 녹음 + 새 결합 → N = 0.
  - 문구 조립은 순수 함수: N = 0 → 현행 문자열과 바이트 동일(:206 · :232 · :235 기준). N ≥ 1 → Soniox + Nemotron 3: :232 문단을 문구 3으로, «기존 수정본은 보존됩니다. …» 문단 뒤·접수 불명 경고 앞에 문구 1. Soniox 단독 재전사: :206 문장을 문구 2로, 그 문단 뒤·접수 불명 경고 앞에 문구 1.
  - Soniox 단독 첫 전사(재전사 문단 없음)에서 N ≥ 1이면 문구 1을 «AI 문맥 교정 OFF …» 줄 앞에 둔다. 도달 조건 = 실행 기록 없는 결과가 2세대 이상이고 Run이 없는 녹음. 실데이터 0 (`begin` :262–264, 실행 기록 없는 3개 모두 Run 있는 녹음).
- [ ] AC-09 저장 공간 정리 (FolderLibraryStore, 합성):
  - ⓐ 확인(쓰기 0): 합성 = 현재 스크립트 A(구 배치 3, 그중 AI 버전 snapshot 1 · 새 배치 1) · B(구 배치 2), A·B는 서로 다른 녹음 각 1세대 + 없는 스크립트 C(구 배치 2) · D(새 배치 폴더 1파일) + 시도 기록 A·C. 기대 = 정리할 스크립트 0 · 지울 이력 3 (C 2 + D 1) · 압축할 이력 5 (A 3 + B 2) · 지울 시도 기록 1 (C). 확인 전후 내부 저장소 매니페스트 차이 0.
  - ⓑ Scripts 조회 문제(손상 파일 1) → 지울 이력 0 · 지울 시도 기록 0 · 문구 15 표지 · C·D 이력 SHA256 불변.
  - ⓒ 실행 순서 = 보관 정리(AC-06 순서) → 지울 이력 → 압축 이전 → 지울 시도 기록. 끝나면 구 배치 0, 새 배치 6, 각 파일 풀어서 원본 SHA256 일치, A의 snapshot `readVersion` 성공.
  - ⓓ 압축 이전 = 읽기 → 압축 → 새 배치 쓰기 → 다시 읽어 풀기 → 원본 바이트 같으면 원본 삭제. 다른 바이트 주입 → 새 파일 삭제 · 원본 유지 · 실패 1.
  - ⓔ 건별 기록 `<내부 root>/storage-cleanup-log.jsonl`: 처리 즉시 1줄 덧붙임, 줄 수 = 처리 항목 수, 키 = at · kind · scriptID · revisionID · bytes · result. 합성 제목·본문 표지 문자열 grep 0.
  - ⓕ 중단 안전: k번째 원본 삭제 직전 throw 주입 → 다음 정리 → 최종 상태(파일 집합 · 풀린 바이트 SHA256) = 중단 없는 정리의 최종 상태. 새 파일이 잘린 채 원본과 함께 있으면 새 파일 삭제 후 다시 압축.
  - ⓖ 남는 것 불변: 정리 전후 `Sessions/` 전체 · 남는 Scripts 파일 SHA256 목록 차이 0.
  - ⓗ 크기 (단위 고정 테스트): 입력 = `LibraryRevisions` 아래 파일 디스크 크기 바이트(Int64, 구·새 배치 모두, 압축 파일은 압축 크기, 해독 없음). 출력 = `ByteCountFormatter` `.file`(1000진). 합성 1,000 · 2,500 · 500 B → 4,000 B. 1,000,000 B의 `.file` 표기 ≠ `.memory` 표기.
  - ⓘ 확인 결과 전부 0 → 확인창 없이 문구 22. 확인 단계 throw → 문구 23, 쓰기 0.
- [ ] AC-10 설정 «저장 공간» 절 (앱 빌드 + 합성 QA 앱 실화면, `QASnapshot`):
  - 위치 = :267 버튼(·녹음 저장 다시 시도) 뒤 `Divider` 다음, `APIKeySettings` 앞. 문구 8 · 9 · 10 («내부 수정 이력 {크기}»는 설정을 열 때 계산).
  - 꺼짐 = 변환(`ProcessingWorkspace.busy`) · AI 교정(`CorrectionWorkspace.busy`) · 녹음 마무리(`capture.needsFinalization`·저장 중) · `!canLeave` · `scriptsLoading` → 문구 11. 녹음 중 자체는 끄지 않는다.
  - 확인 중 문구 12 앞쪽 · 확인창 NSAlert 제목 문구 12 뒤쪽 · 줄 순서 13 → 14 또는 15 → 16 → 17 → 18, 0인 줄 뺌 · 버튼 «취소»(기본)·«정리».
  - 진행 중 문구 20 «({n}/{N})», N = 확인창 항목 수 합. 진행 중 스크립트 편집·저장·변환·AI 교정 시작 막힘, 녹음은 막지 않음.
  - 완료 문구 21 (스크립트 ≥ 1·실패 ≥ 1일 때만 둘째·셋째 문장). 빈 이력 → «내부 수정 이력 0 바이트»(포매터 표기) + 버튼 켜짐 → 문구 22.
  - 실화면: 합성 fixture(구 배치 이력 · 고아 이력 · Scripts 2)로 기본 → 확인창 → 정리 중 → 완료 → 재진입 «정리할 항목이 없습니다.» 캡처. 수집기 = AC 문언과 조작 경로 대조표를 실행 전에 만든다(rule-verify-at-consumption).
- [ ] AC-11 실데이터 읽기 전용 모의 (메인 실행, 환경변수 지정 시에만 도는 테스트, 내부 root = 임시 폴더, Run은 state.json 직독):
  - 대표 결과 변경 0/20 (구 규칙 vs 새 규칙). 보관 2 → 정리 0 · 보관 1 → 4 (retention-sim.py 같은 값). `hasHumanEdits` 22/38.
  - 저장 공간 정리 확인 단계 = 지울 이력 62 · 243.1 MB · 압축할 이력 512 · 9,758.9 MB · 정리할 스크립트 0 · 시도 기록 0 (기준 22:19 실측, 집행 직전 재측정값과 대조).
  - 쓰기 0: 모의 전후 `~/DAMA/Scripts` · `~/Library/Application Support/com.gazitofu.Dama` 매니페스트(경로·크기·mtime) 차이 0. 출력은 개수·크기·ID 앞 8자만.

### 전달

- [ ] AC-12 버전·설치: `MARKETING_VERSION` 0.5.19 · `CURRENT_PROJECT_VERSION` 37 (Debug/Release). check.sh 4단계 PASS. 설치 앱 교체(막힘 1) 뒤 실행 중 Bundle 값 0.5.19 (37).
- [ ] AC-13 실데이터 1회 정리 (막힘 2, 사용자 실행):
  - 실행 전: 메인이 AC-11 확인 단계 재측정 → 확인창 수·크기와 대조, 다르면 중단·보고. 전 매니페스트 = `LibraryRevisions` 574 파일 SHA256 · `Sessions/` SHA256 · Scripts 38 SHA256.
  - 실행 후: 구 배치 0 · 이전된 파일 수 = 확인창 압축 수(기준 512) · 각 파일 풀어서 SHA256 = 전 매니페스트 해당 파일 · 고아(기준 62) 부재 · `Sessions/`·Scripts SHA256 차이 0 · `storage-cleanup-log.jsonl` 줄 수 = 처리 수 · 크기 줄 «{전} → {후}» = 디스크 실측 · AI 버전 7개 `readVersion` 성공(AC-11 방식 읽기 전용 모의, root = 실제 내부 저장소, `scripts(in:)`로 열기, 전후 매니페스트 차이 0).

## 작업 분해

- T-01 계약·문구 개정 (AC-01): §05 10곳. 새 절에 §02-1 · §02-2 · §02-5 요약, legacy 표지는 F-02 필드.
- T-02 Core 판정 (AC-02 · 03): `primaryFile` 엔진 등급 제거 + 가드 이동 · `LibraryScript.hasHumanEdits` · 요약 필드·`summaryVersion` 2.
- T-03 `ScriptRetention` (AC-04 · 08 계산부): 새 파일 DamaAudio, 사례 ①–⑧ · 가상 세대 · 역뮤테이션 2.
- T-04 이력 배치·압축 (AC-05): `revisionURL(scriptID:revisionID:)` · 구 배치 URL · `writeRevision` 압축·임시 이동 · `readVersion` 순서 · `snapshot` sha256 · 가드 이동.
- T-05 삭제 동반 정리 (AC-06): 시도 기록 경로 규칙 DamaCore로 · `FolderLibraryStore` 이력 폴더·시도 기록 삭제 · `deleteScript` 순서·문구 6·7 · 가드 이동. **차수 A 경계**: check.sh 1–3 + QA A.
- T-06 자동 정리 연결 (AC-07): `processingFinished` 정리 인자(launch 경로만) · `createScript` 생성 여부 반환 · 건너뜀 ID 수집 · 문구 4·5.
- T-07 확인창 N (AC-08): `reviewTransmission` N 계산 · 문구 조립 순수 함수 · 문구 1–3.
- T-08 저장 공간 정리 엔진 (AC-09): 확인·실행·건별 기록·중단 재개·크기 합, `FolderLibraryStore` 안.
- T-09 설정 절·실데이터 모의 (AC-10 · 11): `LibrarySettings` 절·상태·NSAlert·진행 중 차단 · 합성 QA 앱 실화면 · 실데이터 읽기 전용 모의. **차수 B 경계**: check.sh 4단계 + QA B.
- T-10 전달 (AC-12 · 13): 버전 0.5.19 (37) · 설치(막힘 1) · 게이트 ② 실데이터 정리(막힘 2) 전후 매니페스트.

구현 = 메인 직접 (프로젝트 CLAUDE.md «메인이 Opus면 직접 구현», usage-bundle1 선례). 태스크마다 check.sh 1–3단계, 앱 빌드·실화면은 차수 경계에서 1회. 사용자 데이터 쓰기는 T-10의 사용자 실행 1회뿐이다.

## 결정 항목

없음. 스펙이 정하지 않은 자리는 실측으로 닫고 위 AC에 값으로 박았다(새 정책 아님):
- 자동 정리 시점 = launch 경로의 새 파일 생성 직후, `convert` 재저장 제외 (스펙 «readyForReview가 되어 … 새로 만든 직후»의 코드 자리, AC-07).
- 실패 수 M = 휴지통 이동 실패만, 건너뜀 제외 (AC-07).
- legacy 사람 수정 표지 = `transcript.revision.humanEdited` (F-02, 실데이터 결과 불변 22/38).
- Soniox 단독 첫 전사 문구 1 자리 (AC-08, 실데이터 도달 0).
- 시도 기록 경로 규칙 DamaCore 이동 (패키지 의존 방향 때문, AC-06).

## 막힘 (사용자 실행·승인 항목)

1. 설치 앱 교체 1회 (T-10, 0.5.19 (37)). 승인 후 메인 실행.
2. 실데이터 1회 정리: 사용자가 설치 앱 설정 «저장 공간 정리…» → 확인창 값 확인 → «정리». 비가역 = 고아 이력 62 · 243.1 MB 삭제(기준 22:19). 메인은 AC-13 전후 매니페스트만 잰다.
3. 안 잼 (스펙 §04): 앱 안 정리 소요 시간 · LZFSE/LZMA 비율 · Finder 휴지통 비움 시점 · 새 설정 절 키보드·VoiceOver(묶음 5) · 재전사 확인창 실화면(Soniox 재사용이면 유료 호출 없이 볼 수 있으나 «닫기»로만 확인, 사용자 요청 시) · 실제 재전사 완료로 일어나는 자동 정리(실데이터 쓰기).

## Follow-ups

- F-01 check.sh 소문자 경로 실행 = 모듈 캐시 대소문자 충돌 2회 (usage-bundle1 11.05 `run-20261105T093251Z-ibPcMG` · 이 plan 11.06 `run-20261106T131025Z-nfR5EE`). 제안: `scripts/check.sh` `ROOT="$(pwd -P)"`. 이 유닛 범위 밖, 승인 시 별도 커밋.
- F-02 스펙 §02-2 «legacy humanEdited Turn»: 계약에 Turn 필드는 없고 legacy 표지는 `RevisionMetadata.humanEdited`(DomainContracts.swift:192)다. measure-t2a.py·retention-sim.py는 Turn 키를 봐 이 축을 0으로 셌다. 실측 revision.humanEdited 0/38이라 판정·예상값은 같다. 계약 새 절과 구현은 계약 필드로 쓴다.
- F-03 재사용 Soniox 자식이 앞선 정리로 휴지통에 간 뒤 새 결합이 그 자식을 다시 재사용하면, savedSourceRuns 등록 때문에 Soniox 단독 스크립트가 다시 만들어지지 않는다(재사용 판단은 Run 기준이라 결합은 정상). 실데이터 해당 0. 문구 3 «Soniox 단독과 결합본을 따로 엽니다.»와 어긋날 수 있는 경로로 기록만.
- F-04 (AC-05ⓐ, 문언 · /build 발견) 스크립트 ID = `transcript.runId`이고 계약은 UUID를 요구하지 않는다(`fixtures/normalized-transcript.json` runId `run-fixture-001`). UUID로 막자 기존 테스트 21개가 저장 불가(`unsafePath`). 구현 = revisionID는 UUID, 스크립트 ID는 시도 기록과 같은 경로 안전 규칙(ASCII 영숫자·`-`·`_`, 1–128자, `InternalStoragePaths.isSafeScriptID`). 실데이터 스크립트 38 · Run 72 전부 UUID라 동작 차이 0. 권고: AC 문언을 구현대로 정정. QA A D-2 «부분».
- F-05 (AC-01 ③, 문언) 스펙 §05 3번 문안을 글자 그대로 치환하면 «… 기록 후. 구 배치는 읽기와 정리 이전에만 쓴다 외부 활성 파일을 atomic 쓰기한다.»로 문장이 끊긴다. 구현 = «… 기록 후 외부 활성 파일을 atomic 쓰기한다. 구 배치는 읽기와 정리 이전에만 쓴다.»(낱말 같음, 순서만). QA A D-1 «부분».
- F-06 (AC-09ⓐⓒ, 문언 · /build 발견) 합성 fixture «A 구 배치 3(그중 snapshot 1) · 새 배치 1»은 API(만들기·제목·AI 보정)로 만들 수 없는 모양이다(AI 보정 1회 = snapshot 2 + 저장 1). 실제 fixture는 A 구 배치 5 · 새 배치 1 → 기대 압축 7 · 실행 뒤 새 배치 8(AC 문언 5 · 6). 지울 이력 3 · 시도 기록 1과 규칙은 같다. 권고: 수량 문언을 실제 fixture대로 정정. QA B D-2 «규칙 차이 아닌 fixture 차이, 설명 타당».

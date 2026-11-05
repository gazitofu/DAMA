---
unit: usage-bundle1
branch: work/m0-fixture-review
status: building
decisions_resolved: true
resume: "게이트 ② 2차 상신 대기 (2026-11-05). ①② 완료: 합성 QA 앱 접근성 실화면(화면 기록 권한 없음, 픽셀 0) + 결함 1건 수정 b3bce1b + 설치 0.5.16(34) 실행 확인, QA 판정 .build/qa/usage-bundle1/D-verdict.md. 남은 것 = 사용자 회신: 설치 앱 창을 열어 실제 결합본 «주의» 0·설정 머리 재확인(사용자가 키보드를 쓰지 않는 시간에만, 열기 전 확인), 막힘 2–5 승인, 결정 F-04–F-07·F-10·F-11. 회신 전 실행 금지. check.sh는 대문자 절대경로"
spec: notes/usage-bundle1/usage-bundle1.src.html
---
## 근거

- 컨펌: `notes/usage-bundle1/usage-bundle1.src.html` `#s-verdict` `data-state="closed"` (게이트 ① 11.05, D-01–D-04 ⓐ, 판정 축 ①–⑥). 확정 문구 `ssot/tone/usage-bundle1.md` (`eb61415`). 입력 결정 `notes/usage-review/decisions.md` (status decided).
- 규율 메모리 14종 (`~/.claude/projects/-Users-gazitofu/memory/`): rule-purpose-first · rule-ambiguous-instructions · rule-scope-stop · rule-gate-hygiene · rule-measurement · rule-negative-claims · rule-carryover-remeasure · rule-verify-at-consumption · rule-delegation-artifacts · rule-destructive-writes · rule-shared-tree-commits · rule-numeric-test-integrity · rule-external-media-verify · rule-longrun-watchdog. 프로젝트 메모리 pyannote-dropped · advisors-fable-astra.
- `ssot/dev.md` §1–7 (§2 층위, §4 검증 층위, §5 외부 전제) · `ssot/api/pyannote-verified.md` (퇴역 경로 기록, 이 유닛 새 요청 0) · `ssot/design/00_README.md` 하이브리드 채택 · `01` §6 «제목을 채워야 녹음할 수 있는 흐름 금지»·§8 · `04` §3 INV-01–10 · `06` §2 RC-01–16.
- 계약 실측 인용 (이 유닛은 두 파일을 바꾸지 않는다):
  - `ssot/contracts/transcript.v1.schema.json` `$defs/issue/properties/kind` enum 10 = ambiguous_speaker · overlapping_speech · missing_speech · boundary_conflict · unrepresented_speaker · provider_disagreement · invalid_timestamp · low_confidence · capture_interrupted · partial_result. `status` enum = open · resolved · acknowledged.
  - `ssot/contracts/DomainContracts.swift:131–137` `IssueKind` (같은 10) · `IssueStatus`. DamaCore 사본은 byte-exact 검사 대상이라 확장은 별도 파일 `extension`으로만 한다.
  - `ssot/contracts/library-script.md` «Markdown 내보내기» 79–90 (4항 «검수 이슈») · «화자 기준 연속 발화» 109–115 (missingSpeech 숨김 선례) · «AI 문맥 교정» 147–175 (`context-correction-5`, 진단 stdout/stderr 폐기, 300초·512kB·2MB 초기 자원 한도, 모든 청크 성공 후 적용, 자동 재호출 없음, CLI 0.154.0 인자).
  - `ssot/contracts/operating-baseline.md:97` 월 비용 공식, 예 28.75.
- 사전 확인 (2026-11-05):
  - HEAD `eb61415`. branch `work/m0-fixture-review` 유지: main `15d09d2`는 129커밋 뒤, 기존 16유닛 모두 이 브랜치. 커맨드 절차 `checkout main && -b work/$1`은 적용하지 않는다(선례, 공유 트리 브랜치 전환 금지).
  - `git status`: 타 소유 수정 14파일 + untracked 3 (`notes/diarization-research/` · `scripts/nemotron-probe/` · `ssot/api/nari-verified.md`). nemotron-diarization r3 기록과 같다. 이 유닛과 겹치는 타 소유 헝크: `App/LibraryWorkspace.swift` (+5 재전사 분기) · `UI/SpeechDetailView.swift` (버튼 문구) · `Packages/DamaCore/Sources/DamaManaged/ProcessingPresentation.swift` · `Dama.xcodeproj/project.pbxproj` (작업 트리 0.5.15(33), HEAD 0.5.9(27)). 커밋은 pathspec + HEAD+자기 변경 blob만 인덱스에 올린다.
  - check.sh: **`bash /Users/gazitofu/Developer/Dama/scripts/check.sh` (대문자 절대경로)로 실행한다.** 소문자 경로 실행 `run-20261105T093251Z-ibPcMG`는 모듈 캐시 충돌(`_DarwinFoundation1 is defined in both`)로 2·4단계 FAIL(환경). 재실행 `run-20261105T093439Z-sgWg1n`: 계약 31 중 1 FAIL · byte-exact PASS · SmokeCheck PASS · swift test 264 (Core 179 / Managed 48 / Audio 37) PASS · xcodebuild Debug PASS · SKIP 없음.
  - 계약 FAIL 원인 = `notes/usage-review/advisor-astra.md` 링크 19개의 `경로:줄` 형식. 사용자 승인(11.05)으로 이 plan 커밋에서 `#L줄`로만 바꿈(앵커를 되돌리면 원본과 동일). `python3 scripts/validate_contracts.py` 31 OK.
- Codex CLI 0.166.0 실측 (사용자 승인 11.05, 앱과 같은 인자 + 합성 프롬프트, 사용자 데이터 0). 스크립트 `/private/tmp/claude-501/-Users-gazitofu-Developer-Dama/682fd8c3-c2a7-4734-8171-0961b4fcd2b5/scratchpad/codex-probe.sh`:

  | # | 조건 | exit | 걸린 시간 | 끝 줄 |
  |---|---|---|---|---|
  | 1 | CODEX_HOME 빈 폴더 (로그인 없음) | 1 | 16초 | `ERROR: unexpected status 401 Unauthorized: Missing bearer …` |
  | 2 | 모르는 `-c features.*` 키 | 1 | 15초 | 경고 `Codex is ignoring 1 unrecognized configuration setting` 뒤 진행 → 401 |
  | 3 | `model_reasoning_effort="dama-probe"` | 1 | 15초 | 거부 없이 진행 → 401 |
  | 4 | 모르는 플래그 | 2 | 0초 | `error: unexpected argument '…' found` |
  | 5 | 프록시 127.0.0.1:9 (실로그인) | 60초 감시에서 강제 종료 | 60초+ | `ERROR: Reconnecting... waiting for network` 반복 |
  | 6 | 프록시 `.invalid` (실로그인) | 강제 종료 | 60초+ | 같음, `failed to lookup address information` |
  | 7 | 없는 모델 (실로그인) | 1 | 3초 | `ERROR: The '…' model is not supported when using Codex with a ChatGPT account.` |
  | 8 | `gpt-6.1-sol` «Reply OK» | 0 | 8초 | 출력 `OK` (사용자 전역 설정 적재로 18,727 tokens) |

  - 모든 실행에서 stderr 맨 앞에 `user` 줄과 **stdin 프롬프트 전문**이 찍힌다. 앱의 프롬프트는 지시문 여러 줄 + 한 줄 JSON(`JSONEncoder` 기본, `ScriptCorrection.swift:145`)이라 전사 본문이 stderr에 들어간다.
  - 1번 실행에서 앱의 `-c` 21개에 대한 무시 경고 0 = 0.166.0이 모두 인식한다.
- 붉음 전수 (scratch 사본, repo 무수정): `/private/tmp/claude-501/-Users-gazitofu-Developer-Dama/682fd8c3-c2a7-4734-8171-0961b4fcd2b5/scratchpad/redrun/repo`에 문단 `> 검수:` 제거 · 월 비용 새 공식 · `context-correction-6`을 얹은 `swift test`. 붉은 테스트 7개, 단정 63건:
  - 스펙 목록 2곳: `LibraryPresentationTests.swift:81` · `ScriptEvaluationTests.swift:40–42`.
  - 스펙 밖 2곳: `ContextCorrectionTests.swift:219` `invalid\_timestamp` · `LibraryPresentationTests.swift:318` (open이 아닌 `capture_interrupted`도 Markdown에 남는다는 현행 단정).
  - 골든 57건: `NemotronGoldenTests:62` ×12 · `NormalizationGoldenTests:18` ×15 · `PolicyGoldenTests:51` ×30. 57건 전부 `normalized`·`reading` 해시는 같고 `markdown`만 다르다.
  - 버전 문자열 단정 0 (테스트는 `ContextCorrection.version`을 참조).
- 사용자 데이터 집계 (읽기 전용, 본문·제목 미출력, 2026-11-05):
  - `~/DAMA/Scripts` 38개: 자동 경고 8종 합 54,221 · capture_interrupted 3 (Script 3개, 각 1) · partial_result 0 · 상태 전부 open 54,224 · reviewRecords 0 · correction none 32 / failed 3 / completed 3.
  - 인덱스 `~/Library/Application Support/com.gazitofu.Dama/library-index.json` 33항목 · 중복 id 0 · 키 8개.
  - 의미 보호 자기 검증 `python3 -I notes/usage-bundle1/measure-b1.py --selftest` = 11/11.
  - `~/.codex/models_cache.json`에 `gpt-6.1-sol` · `gpt-5.6-luna` 있음.

## 의도

사용 복기 묶음 1(T1 · T3 · T5 · T4-1 · T4-2 + T2a-5)을 구현한다. 자동 경고는 화면 문단과 Markdown 문단에서 걷고 데이터는 보존한다. 녹음 표시 제목은 인덱스 한 곳에 두어 녹음과 연결 스크립트가 공유한다. 퇴역 pyannote 설정을 접는다. AI 교정 실패는 원인 분류와 진행분을 남겨 이어서 보낼 수 있게 하고, 숫자·단위·부정·조건을 바꾸는 수정은 자동 반영하지 않는다.

## 영향 범위 (경로 · 현행 실측 2026-11-05)

- `Packages/DamaCore/Sources/DamaCore/LibraryScript.swift`: `:214` `# \(title)` · `:226` `- 검수: \(reviewSummary)` · `:253–255` 문단 `> 검수: \(issue.kind.rawValue)` (block.issues 전부, 상태 무관).
- `…/DamaCore/ScriptEvaluation.swift`: `:75–80` `reviewSummary` = «검수 기록 N건 · 원음 확인 N건 · …» · `:106–126` `MonthlyOperatingCost` Double? 7필드 · `normalTotalUSD` (P2 3항목 필수) · `validate` (유한·0 이상).
- `…/DamaCore/LibraryPresentation.swift`: `:77` `openIssues` · `:206` 미부착 이슈의 문단 연결. `blocks()`는 바꾸지 않는다.
- `…/DamaCore/ScriptCorrection.swift`: `:64` `CorrectionChunk: Codable` · `:98` `version = "context-correction-5"` · `:145` 프롬프트 한 줄 JSON.
- `…/DamaCore/CorrectionSpans.swift:64–105` `validated`: 불확실 → 보류, 그 밖 반영(형식 동등이면 근거만 다름).
- `…/DamaAudio/FolderLibraryStore.swift`: `:5–14` `LibrarySpeech` 8필드 · `:30` `LibraryScriptSummary` · `:110–118` 인덱스 읽기·원자 쓰기 · `:193–198` `saveNotes` · `:199` `storedSpeech` · `:337` `createScript` `title: speech.title` · `:342–351` `saveScript` → `writeRevision` · `:397` `saveTitle`.
- `…/DamaManaged/CodexCorrectionClient.swift`: `:5` 실패 4종 · `:12–27` 인자 · `:47` stdout·stderr `nullDevice` · `:64` 비정상 종료 → `.failed`.
- `…/DamaManaged/KeychainStore.swift`: `:11` `read` · `:22` `save` · `:34` `delete`, provider 기본 `.pyannote`.
- `App/ScriptEditingSession.swift`: `:30–38` 0.5초 대기 저장 · `:54` «자동 저장됨».
- `App/CorrectionWorkspace.swift:96–158`: 청크 루프 · 실패 시 `edits = []` · 고정 실패 문구.
- `App/LibraryWorkspace.swift`: `:33` `titlePending` · `:43` `canLeave` · `:244` `sessionId == speech.id` · `:289` / `:303` 삭제 확인 · `:395` `saveTitle` · `:462` 내보내기 파일 이름 · `:475–478` 월 비용 UserDefaults `evaluation.monthlyCost` · `:500–508` `recordingSaved`.
- `App/ProcessingWorkspace.swift`: `:194` · `:211` · `:217` · `:227` `record.title` · `:371–403` `APIKeySettings` Picker(기본 pyannote).
- `App/RecordingWorkspace.swift:25–28` `onSaved` → `recordingSaved`. `App/AppLifecycle.swift:88` NSPanel은 Dock 계산 제외.
- `UI/ScriptReadingView.swift`: `:33–39` 제목칸 · `:196` 구간 정보 이슈 목록 · `:250` «주의» 버튼.
- `UI/ReviewShell.swift:318` `issueLabel` (공유: `UI/EvidencePanel.swift:40`, `UI/ReviewShell.swift:231`).
- `UI/LibraryShell.swift`: `:139` · `:163` 목록 제목 · `:272–275` API 키·교정 설정 · `:297–334` 월 비용 시트. `UI/SpeechDetailView.swift:21` `Text(speech.title)`. `UI/ScriptModalSheets.swift:94`.
- 계약 문서 (/build가 개정): `ssot/contracts/library-script.md` · `ssot/contracts/operating-baseline.md` · `ssot/tone/uiux-reading.md`.

## 수용 기준

«문구 N» = 스펙 §04 «문구» 표의 번호, 문안 정본 = `ssot/tone/usage-bundle1.md`. QA 판정 = GPT-6.1-sol (`codex exec -m gpt-6.1-sol`, 실측 8번 형식). 키체인·마이크·설치 앱·사용자 데이터 집계는 메인이 실행하고 판정만 넘긴다. 차수: A = AC-01–04 · B = AC-05–09 · C = AC-10–14 · 전달 AC-15–16.

### 차수 A · 검수 표시

- [x] AC-01 계약·문구: 스펙 §05 문안 5항이 그대로 반영됐다. 대상은 `library-script.md`의 새 절 «검수 이슈 표시 (2026-11-05 사용자 확정 · usage-bundle1)» · 새 절 «녹음 표시 제목 (2026-11-05 · usage-bundle1)» · AI 교정 절 3곳, `operating-baseline.md:97`, `tone/uiux-reading.md` 3곳. 자 = 문안 대조(QA), 모집단 = §05 5항. `validate_contracts.py` 31 OK.
- [x] AC-02 경고 분류 (Core, 합성): `IssueKind.isAutoWarning` (8종 true, capture_interrupted·partial_result false). `ScriptBlock.autoWarningSummary: [(kind: IssueKind, count: Int)]`는 open 자동 경고만 세고, 건수 내림차순, 같으면 `rawValue` 오름차순, 0건 종류는 뺀다. `ScriptBlock.persistentWarnings: [ReviewIssue]` = open capture_interrupted·partial_result.
  - 합성 Script 1개: 8종 · 중단 · 일부 결과 · 미배정 · acknowledged 1 · resolved 1.
  - 고정 사례: 같은 건수 2종 → `boundary_conflict`가 `overlapping_speech`보다 앞.
  - 종류별 합 = 그 문단 open 자동 경고 수. 경고 0 문단은 빈 배열.
- [ ] AC-03 Markdown (INV-06·INV-10, RC-01·RC-03):
  - ⓐ `> 검수:` 0줄.
  - ⓑ 머리말 검수 줄은 tone 문구 7의 3형식이다(원음 확인 0건 / 자동 경고 0건 / 원음 확인 1건 이상). 종류 이름은 문구 8, 순서는 AC-02와 같다. 천 단위 쉼표는 로캘과 무관하게 고정(1402 → `1,402`). 총수는 `transcript.reviewIssues` 중 8종 전부이고 상태·삭제 문단을 따지지 않는다.
  - ⓒ 녹음 중단·일부 결과: 머리말에 종류당 1줄(있을 때만), 붙은 문단 아래 `> 녹음 중단: …` / `> 일부 결과: …`(문구 9). **상태와 무관하게 쓴다**(현행 `LibraryPresentationTests:318` 단정 유지). 삭제된 문단의 것은 머리말에만.
  - ⓓ 현 Scripts 38개 모의(메인, 읽기 전용, 출력은 `/private/tmp` 아래 임시 폴더 · 집계 후 삭제): 문단 `> 검수:` 0 (기준선 = 문단 이슈 수만큼) · 머리말 총수 합 54,221 (기준선 2026-11-05 집계 54,221) · 중단 Script 3개에 머리말 1·문단 1, 나머지 0 · 모의 전후 Scripts 38개 SHA256 차이 0 · `### [` 줄 수 = 변경 전 같은 모의의 값(T-02 착수 전 기록).
  - ⓔ `blocks()` · `TranscriptExporting.swift` diff 0줄. 평가 JSON의 `script.transcript.reviewIssues` 수 = 원본 수(합성).
  - ⓕ 가드 이동, 단정 형태·건수 유지:
    - `LibraryPresentationTests:81` → 머리말 «겹침 n» 단정 + `!md.contains("> 검수:")`.
    - `:318` → `> 녹음 중단:` 포함.
    - `ContextCorrectionTests:219` → 머리말 «시간 불명 n».
    - 골든 3종 → 새 경로에 다시 포착한 뒤, 엔트리 키 집합과 `normalized`·`reading` 값이 전후 같음을 확인하고 `markdown` 값만 교체한다(엔트리 15·21·35 = 71개 전부 markdown 바뀜 예상, 이유 = 머리말 형식 변경).
    - 역뮤테이션: 옛 문단 줄을 원본 바이트 보관 방식으로 복원했을 때 붉어지는 단정 수를 기록한다.
- [ ] AC-04 읽기 화면 (UI):
  - ⓐ 문단 행 «주의» 0 (합성 UI fixture Debug 빌드 + 설치 앱 실제 결합본 1개, 읽기만). 기준선 = open 이슈가 있는 문단마다 1.
  - ⓑ 중단·일부 결과는 문단 본문 아래 ⚠ 기호 + 문구 1 줄, 이슈 1건당 1, open만.
  - ⓒ 구간 정보는 맨 위 경고 줄 → «자동 경고 N건» 접힘(기본 닫힘) 순서다. 펼치면 문구 5 + «{문구} · {N}건»이 나오고, 0건이면 줄 없음. 하단 «정보»로 연다.
  - ⓓ `issueLabel` 4종은 문구 2(확정본)로, 4종은 문구 3(유지)로.
  - ⓔ `git grep -n '"주의"' -- UI App` = 0.

### 차수 B · 녹음 제목

- [ ] AC-05 제목 데이터 (Audio, 합성 저장소):
  - `LibrarySpeech.displayTitle: String?`. 구 인덱스(키 8)는 nil로 읽고, nil이면 인코드 시 키가 없다(구 바이트 왕복 동일).
  - `FolderLibraryStore.saveDisplayTitle(_ title: String, speechID: String) throws -> LibrarySpeech`: id가 같은 항목 전부를 원자 쓰기로 갱신한다. 빈값·공백뿐이면 `invalidInput`, 없는 id면 `missingFile`. 입력값은 다듬지 않는다(앞뒤 공백 보존).
  - `displayTitles() throws -> [String: String]`: 찾지 못한 파일 항목 포함 전체.
  - 쓰기 범위: 저장 1회 전후 내부 저장소·Scripts 파일 목록과 해시를 비교하면 `library-index.json`만 바뀌고 Scripts·`LibraryRevisions` 변화는 0이다. 기준선 = 현행 스크립트 제목 1회 = 스크립트 파일 1 + 사본 1.
- [x] AC-06 제목 해석 (pure): `LibraryTitles.speech(_:) = displayTitle ?? title` · `LibraryTitles.script(fileTitle:sessionID:displayTitles:) = displayTitles[sessionID] ?? fileTitle`.
  - 합성 5사례: 연결 + displayTitle · 연결 + 없음 · 미연결 · Speech 휴지통(인덱스만 있음) · AI 버전 보기(스냅숏 파일 제목 그대로).
  - `createScript`의 새 파일 `title` = 해석 녹음 제목.
- [x] AC-07 쓰는 자리 전수: 해석 제목을 쓰는 자리는 Speech 목록·상세 · Script 목록·읽기 제목칸 · AI 검수/보정 창 머리 · 삭제 확인 2곳 · 변환·재전사 확인창 4곳 · Markdown `# 제목`(`markdown(title: String? = nil)`, nil = 파일 제목) · 내보내기 파일 이름. 평가 JSON `script.title`은 파일 값 그대로. 자 = `git grep -nE '(speech|record|file)\.title|script\.title' -- App UI` 남은 줄 전수를 «해석 함수 입력 / 평가 JSON / AI 버전 보기»로 분류해 결과 파일에 기록.
- [ ] AC-08 저장 시점·양방향:
  - pure `TitleDraft` (DamaCore). 사건 = 편집(조합 여부) · Enter · 이탈 · Esc. 동작 = 없음 · 저장(값) · 되돌림(마지막 저장값) · 거부(«제목을 입력해 주세요.», 입력 유지). 조합 중 Enter·이탈 = 없음. 합성 단정 8개 이상.
  - `git grep -n 'milliseconds(500)' -- App/ScriptEditingSession.swift` = 0.
  - 상태 문구 11 (입력 중 «Enter를 누르면 저장합니다.» · «제목 저장 중…» · «제목 저장됨» · 빈값 · 실패).
  - 연결 스크립트 제목칸 저장 = 인덱스만 쓰고 스크립트 파일 쓰기 0. 미연결 = 현행 `saveTitle`.
  - 캡션 «녹음 제목과 같이 바뀝니다.»는 연결 있을 때만.
  - Speech 제목칸 = `InlineScriptText` 제목 모드, 접근성 «녹음 제목».
  - `titlePending` 중 다른 Speech·Script로 이동 차단(현행 `canLeave`).
- [ ] AC-09 녹음 직후 입력창:
  - ⓐ pure `TitlePromptQueue` (DamaCore): 끝난 순서로 줄 서고 한 번에 하나만 보인다. 인덱스에서 확인된 id만 표시하고, 닫으면 다음으로 넘어가며, 종료 시 전부 버린다. 합성 단정.
  - ⓑ 계기·표시:
    - 계기 = `publishRecording` 성공 → `refresh` 스캔에서 그 id 확인.
    - 건너뜀 4조건: Speeches 미선택 · 저장 실패 · 파일 가져오기 · «보존된 녹음 저장».
    - `NSPanel`(Dock 계산 제외), 화면 가운데 위쪽, 문구 10.
    - Enter = 저장(조합 중 아님), Esc = 나중에.
    - 저장 중 입력·버튼 비활성, 실패 시 문구 11 실패 + 입력 유지.
  - ⓒ 실기기 1회(메인, 막힘 2): 10초 녹음 → 원본 저장 시각 < 입력창 표시 → 저장 → Speech 목록·상세 제목 일치 → 입력창이 열린 상태에서 메뉴바 녹음 토글 동작.
  - ⓓ Script 목록·Markdown 제목 일치: 새 녹음의 Script 생성은 Soniox 전송이라 막힘 3. 승인이 없으면 합성 UI fixture로 대체하고 «실녹음 Script 연결 미검증»으로 표시.

### 차수 C · 설정·교정

- [ ] AC-10 API 키:
  - Picker 없음. Soniox 키 입력·저장·삭제는 현행 문구 그대로.
  - `KeychainStore.exists(provider:) -> Bool`은 값을 반환하지 않는다(`kSecReturnData` 없음).
  - 설정을 열 때와 삭제 뒤에 확인한다. 키가 있으면 문구 21 안내 줄 + «pyannote 키 삭제». 확인창 기본 버튼은 «취소», 삭제 뒤 «pyannote 키 삭제됨»이 뜨고 줄이 사라진다.
  - 실기기(메인): 있음·없음 표시. 삭제 단계는 막힘 4.
- [x] AC-11 월 비용 (USD Double, 내부 그대로, 출력 `%.2f`):
  - `aiCLISubscriptionUSD: Double?` 추가, 검증에 포함(−1 · `.infinity` → throw).
  - 4사례: 29.75 · 48.75 · 54.75 · 미측정(퇴역 1칸만 입력).
  - 구 기록 19/19/13.2/9.75/0 + AI CLI nil → nil (현행 28.75, 기준선 `ScriptEvaluationTests:40`).
  - 구 JSON(키 없음) 디코드 → nil. 평가 JSON `cost`는 값이 있을 때 키 1개가 늘고 기존 키는 그대로.
  - 시트: 주 항목 5 · Nemotron 줄 · «퇴역 서비스 (기록용) · pyannote» 기본 닫힘 · 문구 22.
  - 가드 이동 `ScriptEvaluationTests:37–43` → 새 4사례 + 구 기록 사례, 역뮤테이션 1회.
- [ ] AC-12 의미 보호 `context-correction-6`:
  - 엔진 문자열 `Codex CLI · GPT-5.6 Luna · context-correction-6`.
  - 판정 순서: ① 불확실·미해결 겹침 → 원문 유지 ② 단일 적용 형식 동등 → 반영 ③ `MeaningGuard.changedClasses(quote:replacement:) -> [MeaningClass]`(숫자·단위·부정·조건 순)가 비어 있지 않으면 원문 유지 ④ 반영.
  - 표식은 `notes/usage-bundle1/measure-b1.py`의 `num_sig`·`unit_sig`·`neg_sig`·`cond_sig`와 같다. 11쌍 11/11 (보류 7 · 통과 4).
  - 보류 근거는 문구 20, 분류명을 «·»로 잇는다.
  - `CorrectionReapplication`도 같은 규칙. 열기·과거 버전 조회는 판정 불변.
  - 보고: 완료 교정 3건 변경 140건을 Swift 구현으로 다시 판정한 보류 수(문턱 없음, Python 모의 0/140).
- [ ] AC-13 실패 분류 (Managed, 가짜 CLI):
  - `CorrectionFailureKind` 8종 = cancelled · unavailable · timeout · auth · network · config · format · unclassified.
  - 오류 `CodexCorrectionError { kind, exitCode: Int32?, signaled: Bool, elapsedMs: Int64, stderrBytes: Int }`.
  - stdout은 `nullDevice`. stderr는 파이프로 끝까지 읽어 바이트 수를 전부 센다. 대조는 D-02 ⓐ: 줄 시작이 `ERROR: `·`error: `인 줄만, 줄 버퍼 64 KiB에서 자르고 대조 직후 버린다. 내용은 파일·로그·화면 어디에도 쓰지 않는다.
  - 분류 순서는 스펙 §02-3 표 그대로이고 예외 1줄(D-01 ⓐ): 시간 초과로 끝났는데 stderr에 network 표식이 있었으면 «네트워크». 대기 300초는 그대로.
  - 오염 방지 고정 테스트: 가짜 CLI가 stdin 프롬프트처럼 `{"…Unauthorized…waiting for network…"}` 한 줄을 stderr에 먼저 쓰고 표식 없이 exit 1 → «미분류».
  - 표식 (실측 1·4·5·7):
    - auth = `ERROR: ` 줄 + `401 Unauthorized`
    - config = exit 2 + `error: unexpected argument` 줄, 또는 `ERROR: ` 줄 + `model is not supported`
    - network = `ERROR: Reconnecting... waiting for network` (D-01)
  - 8/8: 가짜 CLI로 8분류를 하나씩 일으켜 기록된 분류를 본다. 시간 초과는 주입한 짧은 timeout으로.
  - 막힘 방지: 가짜 CLI가 stderr 1 MiB를 쓰고 exit 0 → 시간 초과 없이 정상, `stderrBytes` = 1,048,576.
  - 단위 고정 테스트: Duration → Int64 ms 절삭, 0 이상. `.milliseconds(1500)` → 1500, `.microseconds(1999)` → 1.
  - 원문 미기록: 가짜 CLI가 stderr에 쓴 고유 표식 문자열이 임시 내부 저장소·임시 Scripts 전수 검색에서 0 (양성 대조 `stderrBytes` > 0). `git grep -nE 'os_log|Logger\(|NSLog|print\(' -- App/CorrectionWorkspace.swift Packages/DamaCore/Sources/DamaManaged` = 0.
- [ ] AC-14 시도 기록·이어서 교정:
  - `CorrectionAttempt` Codable (`formatVersion` 1 · scriptID · attemptID · engine · 입력 스냅숏 · `planSHA256` · `chunkSHA256s` · 끝난 청크 결과 · 실패 최근 20).
  - 저장 위치 `<내부 root>/CorrectionAttempts/<scriptID>.json`, 원자 쓰기. `planSHA256` = `JSONEncoder` `.sortedKeys`로 인코드한 `[CorrectionChunk]`(AI 겹 제외)의 SHA256.
  - 실행: `CorrectionRunner` (DamaManaged, 가짜 CLI 테스트 가능), 앱은 이것을 부른다.
  - 12청크 중 5번째 실패 → 이어서 → 가짜 CLI 호출 5 + 8 = 13, edits·names·evidence가 한 번에 끝낸 경우와 같다(ID·시각 제외).
  - 문단 1개 수정 → 버튼 없음 + 문구 16. 엔진이 다르면 같음. 0개 완료 → «같은 입력으로 다시 시도».
  - 새 교정 시작 → 기록 버림 + 문구 19. 성공 저장 직후 기록 삭제. 휴지통 이동 시 남음. 앱 재시작 뒤 남음.
  - 확인창 기본 «취소», 문구 17. 하단 문구 13·14, 버튼 15, 안내 띠 문구 18 (기존 실패 문구 대체).
  - 실기기: 막힘 5.

### 전달

- [x] AC-15 check.sh PASS · SKIP 0 (대문자 절대경로). `MARKETING_VERSION`·`CURRENT_PROJECT_VERSION` Debug/Release 0.5.15(33) → 0.5.16(34)(작업 트리만, 타 소유 상향과 같은 줄). 설치(막힘 1) 뒤 실행 중 Bundle 0.5.16(34) 확인. pathspec 커밋, 타 소유 헝크 바이트 보존, 마감 `git status` = 타 소유 14 + untracked 3.
- [x] AC-16 QA: 차수마다 GPT-6.1-sol 판정 파일 `.build/qa/usage-bundle1/{A,B,C}-verdict.md`. QA 전후 `git status --short`·`git diff --stat` 동일. 브리프에 사용자 데이터 경로 열람 금지를 명시한다. 판정 «부분·실패»는 해당 결함과 영향 범위만 재검증한다.

## /build 결과 (2026-11-05 · 게이트 ② 상신)

커밋 `6eeaea2`…`a047826` (T-01–T-10 12커밋 + QA 결함 수정 6커밋). QA = GPT-6.1-sol `codex exec -m gpt-6.1-sol --sandbox read-only --ignore-user-config`, 판정 `.build/qa/usage-bundle1/{A,B,B2,C,C2,C3,C4}-verdict.md` · 증거 `{A,B,C}-evidence.md` (gitignored). 7회 모두 QA 전후 `git status --short`·`git diff --stat` 동일. 최종 check.sh `run-20261105T113128Z-lKI66x` (HEAD `a047826`): 계약 31 · byte-exact · SmokeCheck · swift test Core 199 / Audio 44 / Managed 60 · xcodebuild Debug 전부 PASS, SKIP 0.

| AC | 판정 | 남은 것 |
|---|---|---|
| 01 | 통과 | |
| 02 | 통과 | |
| 03 | 부분 | F-04 명세 밖 머리말 조합(현 데이터 0건). ⓓ 모의 38개: `> 검수:` 57,037→0 · 머리말 합 54,221 · 중단 3/3 · SHA256 차이 0 |
| 04 | 부분 | 실화면 미검증 (F-08) |
| 05 | 부분 | F-05 «구 바이트 왕복 동일» 문언 (기본 JSONEncoder 200회 3종·왕복 198/200 불일치) |
| 06 | 통과 | |
| 07 | 통과 | 남은 grep 2줄 = 해석 함수 입력 |
| 08 | 부분 | 코드 통과, 실화면 미검증 |
| 09 | 부분 | ⓐⓑ 코드 통과(QA B D-1–D-3·N-1 수정 후 재판정 해소), ⓒ 막힘 2 · ⓓ 막힘 3 미실행 |
| 10 | 부분 | 코드 통과, 키체인 pyannote 항목 있음(종료 코드만), 화면·삭제(막힘 4) 미검증 |
| 11 | 통과 | 역뮤테이션 7 |
| 12 | 통과(코드)·보고 | QA C D-1 해소. 완료 교정 140 변경 재판정 보류 0 (Python 0/140) |
| 13 | 부분 | D-2 잔여 = F-06 문언(자식이 제한 시각 넘어 stderr 보유 시 «끝까지» 불가). 8/8 · 1 MiB · 오염 방지 · 표식 0 통과 |
| 14 | 부분 | QA C D-3·D-4 해소. 막힘 5 미실행, F-07 |
| 15 | 부분 | 작업 트리 0.5.16(34), check.sh PASS·SKIP 0. 설치(막힘 1)·실행 Bundle 확인 미실행 |
| 16 | 통과 | 부분·실패는 해당 결함만 재판정 |

### 게이트 ② 회신 뒤 (2026-11-05 · 화면 확인·설치 승인분)

증거 `.build/qa/usage-bundle1/D-evidence.md` · 덤프 `D-ax/` · 판정 `D-verdict.md` (GPT-6.1-sol, QA 전후 `git status --short`·`git diff --stat` 동일).

- 권한: 접근성 있음, 화면 기록 없음(`screencapture` exit 1). 실화면 = 합성 QA 앱(0.5.16(34), ReadingQA, fixture `/private/tmp/dama-reading-qa-ub1-b` + 가짜 CLI로 만든 auth 실패 시도 기록 2건)의 접근성 트리. 시각 속성(⚠ 글리프·배치·잘림)은 안 잼.
- 결함 1건 수정 `b3bce1b`: 설정 API 키 머리가 «Soniox 단독 (비교) API 키»(`provider.title` 보간). 문구 21 «Soniox API 키»로 고침. C차 증거가 이를 «Soniox API 키»로 잘못 적어 QA C가 놓쳤다. 저장·삭제 문구는 AC-10 «현행 그대로»라 남김(F-10). 수정 뒤 화면 재확인은 안 함(QA 앱은 수정 전 빌드, 설치 앱 창은 안 열었다). 전달 바이너리에 «Soniox API 키» 1건.
- check.sh `run-20261105T125104Z-LT4x0k` (HEAD `b3bce1b`): 계약 31 · byte-exact · SmokeCheck · swift test Core 199 / Audio 44 / Managed 60 · xcodebuild Debug PASS, SKIP 0.
- 설치: 0.5.15(33)은 21:34:57 이미 정상 종료 상태(통합 로그 QUITTING, 충돌 없음, 원인 미확정·메인 종료 명령 아님, 내부 저장소 21:00 이후 쓰기 0) → 백업 `.build/backups/DAMA-0.5.15-33-before-usage-bundle1.app` 11파일 일치 → `/Applications/DAMA.app` 교체, launcher·dylib 포함 11파일 SHA256 일치 → 실행 pid의 Bundle `com.gazitofu.Dama` 0.5.16(34), 적재 경로 `/Applications`, 메뉴바 툴팁 «DAMA 0.5.16 · 빌드 34».
- 사건: QA 앱 확인창(문구 17)이 열린 사이 «다시 시도»로 닫혔다(도구 입력 아님, 사용 중이던 사용자 입력으로 추정·미확정). QA 앱 차단 가드가 막아 시도 기록 변화 0, 외부 전송 0. 이후 확인창 여는 여정 중단, 키체인 삭제 경로는 열지 않음.

| AC | 판정 (D) | 남은 것 |
|---|---|---|
| 04 | 부분 | ⓐⓑ 합성 화면 «주의» 0·경고 줄 2 확인, 설치 앱 실제 결합본 미검증, ⚠ 시각 미검증. ⓒ 기본 닫힘·안내·종류 행·동률 순서·0건 줄 없음 확인, 접힘 라벨 글자·경고 줄과 접힘 공존 문단 순서 미검증, «하단 «정보»» 문언 불일치(F-11). ⓓ 통과 |
| 08 | 부분 | 이탈·Enter 저장, 인덱스만 쓰기(Scripts·LibraryRevisions 0), 공백 거부·입력 유지, 이동 차단, Esc 되돌림, 녹음↔스크립트 양방향 확인. 저장 중·실패·IME·미연결 미검증 |
| 10 | 부분 | Picker 없음, pyannote 줄·버튼 확인. 머리 결함 `b3bce1b` 코드 통과·화면 미검증. 키 없음 상태·삭제 확인창·삭제 뒤(막힘 4) 미검증 |
| 11 | 통과 | 시트 구성·4사례(29.75 · 미측정+문구 22 · 48.75 · 54.75). 3사례는 메인 관측 기록 |
| 14 | 부분 | 하단 줄 13·14, 버튼 «같은 입력으로 다시 시도», 확인창 문구 17(완료 0), 문단 수정 뒤 문구 16·버튼 없음, AI 창 문구 19 확인. AXDefaultButton 미조회, 완료 ≥1·엔진 불일치 화면·실패 띠(문구 18)·실기기(막힘 5) 미검증 |
| 15 | 통과 | |


## 작업 분해

- T-01 계약·문구 개정 (AC-01): §05 문안 5항. AI 교정 절 stderr 항은 «stdout은 버리고 stderr는 줄 시작이 `ERROR: `·`error: `인 줄만 메모리에서 분류 표식과 대조한 뒤 버린다(줄당 64 KiB). 바이트 수만 기록한다. 시간 초과 중 네트워크 표식이 있었으면 네트워크로 분류한다»로 쓴다 (D-01 ⓐ · D-02 ⓐ).
- T-02 Core 경고 표시·Markdown (AC-02·03): 새 파일 `ReviewIssueDisplay.swift`(extension · 요약 · 짧은 이름) · `LibraryScript.markdown(title:)` · 가드 이동 4곳 + 골든 3종 다시 포착. 착수 전 38개 모의로 `### [` 기준선을 기록한다.
- T-03 UI 읽기 화면 (AC-04): `ScriptReadingView` «주의» 제거 · 경고 줄 · 구간 정보 접힘 · `issueLabel` 4문구. **차수 A 경계**: Debug 빌드 + 합성 fixture 화면 + QA A.
- T-04 Core·Audio 제목 데이터 (AC-05·06, AC-08·09 pure): `displayTitle` · `saveDisplayTitle` · `displayTitles` · `LibraryTitles` · `TitleDraft` · `TitlePromptQueue` · `createScript` 제목.
- T-05 App 제목 저장·쓰는 자리 (AC-07·08): `ScriptEditingSession` 대기 저장 제거·저장 대상 분기 · `SpeechDetailView` 제목칸 · `LibraryWorkspace` `displayTitles` 공급·`saveDisplayTitle` · 목록·확인창·Markdown·파일 이름. 타 소유 헝크가 있는 두 파일은 HEAD+자기 변경만 커밋한다.
- T-06 녹음 직후 입력 패널 (AC-09): `NSPanel` + SwiftUI · `recordingSaved` 뒤 줄 서기 · 종료 시 버림. **차수 B 경계**.
- T-07 설정 (AC-10·11): `KeychainStore.exists` · `APIKeySettings` · `MonthlyOperatingCost.aiCLISubscriptionUSD`·공식·검증 · 월 비용 시트 · 가드 이동.
- T-08 의미 보호 (AC-12): `MeaningGuard` (measure-b1.py 이식) · `CorrectionSpans` 3단계 · `version` -6.
- T-09 실패 분류 (AC-13): `CodexCorrectionClient` stderr 파이프 · 병행 읽기 · 표식 대조 · `CodexCorrectionError`. `CodexCorrectionTests` 기존 단정은 새 오류형으로 대상 이동한다.
- T-10 시도 기록·이어서 교정 (AC-14): `CorrectionAttempt` · 저장소 · `CorrectionRunner` · `CorrectionWorkspace` 연결 · 하단 줄·확인창·안내 띠·S8 문구. **차수 C 경계** → AC-15·16.

구현 = 메인 직접 (프로젝트 CLAUDE.md «메인이 Opus면 직접 구현», 이전 유닛 선례). 태스크마다 `check.sh` 1–3단계, 앱 빌드·실기기는 차수 경계에서 1회.

## 결정 항목

**해소 (사용자 확정 2026-11-05): D-01 ⓐ · D-02 ⓐ.** 반영 위치 = AC-13, T-01 AI 교정 절 stderr 항. 아래는 상신 당시 기록.

판정 축 = 실패 분류가 실제 원인을 짚는가(사용자가 다음 행동을 고를 수 있는가) · 원문이 메모리 밖으로 새지 않는가. 공통 전제: 300초 제한·자동 재시도 없음·stderr 내용 미기록은 그대로 둔다.

- **D-01 네트워크 실패의 분류.** 실측 5·6: Codex는 네트워크가 끊기면 끝나지 않고 `ERROR: Reconnecting... waiting for network`를 반복한다(60초 넘게). 스펙 표의 «네트워크 = 종료 코드 0 아님 + 표식»은 실측상 생기지 않아, 지금 규칙대로면 300초 뒤 «시간 초과»가 된다.
  - ⓐ (권고) 시간 초과일 때 stderr에 그 표식이 있었으면 «네트워크»로 남긴다. 대기 300초는 그대로이고, 분류 순서에만 이 예외 1줄을 둔다.
  - ⓑ 표식을 보는 즉시 중단하고 «네트워크»로 남긴다. 결과가 수 초 안에 나오지만 «중단 조건» 하나가 새로 생긴다. 순간 끊김에서 Codex가 회복할 기회를 앱이 끊는다.
  - ⓒ 스펙 그대로. 네트워크 분류는 실제로 쓰이지 않고 «시간 초과» 문구가 뜬다.
- **D-02 stderr 표식 대조 범위.** 실측: stderr 맨 앞에 프롬프트 전문(지시문 + 한 줄 JSON 전사)이 찍히고 오류 줄은 끝에 온다. 스펙 값 «앞 64 KiB»(신규 후보)는 청크 입력이 64 KiB를 넘으면 오류 줄을 놓쳐 «미분류»로 떨어진다(청크 상한 16k자 ≈ 48 KB + 참고 발췌 최대 12k자).
  - ⓐ (권고) 줄 단위로 끝까지 읽되, 줄 시작이 `ERROR: `·`error: `인 줄만 대조한다. 줄 버퍼는 64 KiB에서 자르고 내용은 대조 직후 버린다. 프롬프트 줄(`{`로 시작하는 JSON · 고정 지시문)은 대조 대상이 아니라서 전사 안의 낱말이 분류를 오염시키지 않는다.
  - ⓑ 끝 64 KiB를 남겨 대조. 구현은 단순하지만 프롬프트 꼬리(전사 일부)가 메모리에 남고, 전사 낱말(«Unauthorized» 등)이 표식으로 잡힐 수 있다.
  - ⓒ 스펙 그대로(앞 64 KiB).

## 막힘 (사용자 실행·승인 항목)

1. 설치 앱 교체 1회 (차수 C 뒤 0.5.16(34)). 차수 A·B의 실제 데이터 화면 축은 이때 한꺼번에 잰다. **교체 완료 2026-11-05 21:54.** 실제 데이터 화면 축은 미실행(창을 열면 앱이 앞으로 나와 사용 중인 사용자 입력이 실제 스크립트에 들어갈 수 있음).
2. 마이크 10초 녹음 1회 (AC-09ⓒ, 메인 실행). 녹음은 Speeches에 남고 정리는 사용자가 한다.
3. 새 녹음 Script 생성 = Soniox 전송 10초 (AC-09ⓓ, 건별 승인). 미승인 시 합성 fixture로 대체하고 미검증으로 표시.
4. pyannote 키 삭제 (AC-10). 키가 있으면 사용자가 직접 누르거나 승인한다.
5. 실기기 교정 실패 화면 (AC-14): 완료 교정이 있는 실제 Script 1개에 가짜 실행 파일을 지정해 실패 경로만 본다(스크립트 파일 쓰기 0, `CorrectionAttempts/` 1파일 생김, 성공·이어하기 경로는 합성 테스트로만). 승인이 없으면 합성 단위만 보고 «실화면 미검증».
6. 실제 Codex 교정 호출 0. 만료 토큰의 인증 문구는 재지 않았다(안 잼).

## Follow-ups

- F-01 Codex는 모르는 `-c` 키를 경고만 남기고 무시한다(실측 2). 앞으로 CLI가 `features.shell_tool` 같은 격리 키를 없애면 격리 설정이 조용히 빠질 수 있다. 0.166.0에서는 21개 모두 인식한다. 무시 경고 줄을 실패로 다룰지는 별도 결정(묶음 3 T4-5와 함께).
- F-02 QA 호출이 사용자 Codex 전역 설정(hook·MCP·plugin)을 적재한다(실측 8, «OK» 1회에 18,727 tokens). 프로젝트 문서만 넣는 실행 형태는 /build에서 비용을 보고 정한다.
- F-03 `CorrectionAttempts/` 정리 정책은 묶음 2(T2a).
- F-04 (AC-03, 결정) 원음 확인 ≥1 & 자동 경고 0일 때 머리말: tone 3형식 밖. 현재 «{현행 요약}. 자동 경고 0건 (경고 없음이 정확도를 보장하지 않음)». 현 데이터 해당 0 (reviewRecords 0, 만드는 화면 없음).
- F-05 (AC-05, 문언) «구 바이트 왕복 동일» → «키 정렬 왕복 동일 + nil 키 생략». 기본 인코더는 이 유닛 전부터 바이트 정본이 아님(프로브).
- F-06 (AC-13, 문언) 정상 종료는 EOF까지 전수, 자식이 stderr를 제한 시각 넘어 붙잡으면 판정 시점(제한 시각 또는 강제 종료 + 2초 + 정리 최대 1.2초)까지 도착분. QA C4 «부분».
- F-07 (AC-14, 결정) 실패 기록 없이 끊긴 시도(앱 종료 등)의 하단 줄: 짧은 원인을 생략함. 정본 문구 없음.
- F-08 (갱신 11.05 게이트 ② 회신 뒤) 접근성은 열림, 화면 기록은 여전히 없음. 접근성 트리로 잰 축과 미검증 축은 «게이트 ② 회신 뒤» 표.
- F-10 (AC-10, 결정) 저장·삭제 문구의 서비스 이름이 «Soniox 단독 (비교)»로 남는다(«Soniox 단독 (비교) 키 저장됨 · 연결 유효성 미검증», «이 Mac의 Soniox 단독 (비교) API 키를 삭제할까요?», «Soniox 단독 (비교) 키 삭제됨»). 머리 «Soniox API 키»와 이름이 갈린다. 권고: 세 문구도 «Soniox»로 통일(운영 기본값의 키라 «비교»가 틀린 설명). QA D는 현행 유지가 AC-10 문자 해석으로 타당, 통일은 사용자 결정이라고 판정.
- F-11 (AC-04ⓒ, 문언) 스펙 417행 «구간 정보는 하단 도구막대의 «정보»로 연다». 실제 «정보» 버튼은 `74b774e`(2026-09-12)부터 상단 결과 줄이고 이 유닛은 옮기지 않았다. 스펙이 기존 위치를 잘못 적은 것으로 본다. 권고: 문언을 «결과 줄의 «정보»»로 정정, 버튼 이동 없음.
- F-12 (절차) 사용자가 쓰는 중인 Mac에서 접근성으로 QA 앱을 조작하면 확인창이 사용자 입력을 받는다(이번 사건). QA 앱의 설정은 실제 로그인 키체인 항목의 존재를 조회하고, 삭제 버튼은 실제 항목을 지운다(Bundle ID 분리로 격리되지 않음). 다음 실화면 검증은 사용자 부재 시간을 합의하고, 키 삭제 여정은 격리 키체인이 생기기 전까지 보류한다.
- F-09 `FileHandle.read(upToCount:)`는 파이프에서 개수를 채우거나 EOF까지 블록한다(역뮤테이션에서 관측). 다른 파이프 읽기 코드(Qwen·Nemotron 실행기)에 같은 가정이 있는지 별도 점검.

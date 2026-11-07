---
unit: correction-turn-isolation
branch: work/m0-fixture-review
status: building
decisions_resolved: true
resume: "설치 0.5.20(38) 완료(AC-11 툴팁 관측만 남음). AC-09 실화면 = 이 세션 System Events 무응답으로 조작 불가, 처리 방식 사용자 확인 대기. AC-12 = 사용자 실데이터 교정 1회 대기."
spec: notes/correction-turn-isolation/correction-turn-isolation.src.html
---
## 근거

- 컨펌: `notes/correction-turn-isolation/correction-turn-isolation.src.html` `#s-verdict` `data-state="closed"` (게이트 ① 11.07, D-01 ⓐ 엔진 v7 + §05 문안 5곳 · D-02 ⓐ `rejectedTurns`, 판정 축 ①–③). 확정 문구 `ssot/tone/correction-turn-isolation.md` (`e4b9153`, 문구 1–5 · 2a). 입력 `notes/usage-review/correction-measure.md` (진단 3회) · `decisions.md` (next 줄 `7b59b85`).
- 규율 메모리 15종 (`~/.claude/projects/-Users-gazitofu/memory/`): rule-purpose-first · rule-ambiguous-instructions · rule-scope-stop · rule-gate-hygiene · rule-measurement · rule-negative-claims · rule-carryover-remeasure · rule-verify-at-consumption · rule-delegation-artifacts · rule-destructive-writes · rule-shared-tree-commits · rule-numeric-test-integrity · rule-external-media-verify · rule-longrun-watchdog · rule-branch-base-is-main. 프로젝트 메모리 pyannote-dropped · advisors-fable-astra.
- `ssot/dev.md` §1–7 (부칙 11-07 도구 Swift 6.4.2 · Xcode 27.2) · `ssot/api/pyannote-verified.md` 머리 (이 유닛 외부 API 호출 0, pyannote 요청 0) · `ssot/design/00_README.md` 하이브리드 채택 (이 유닛은 02·03·04를 바꾸지 않는다) · `04` §3 INV-06 · INV-09 · INV-10 · `06` §2 RC-01 · RC-13.
- 계약 실측 (schema·DomainContracts 변경 없음): `git grep -n -i correction -- ssot/contracts/DomainContracts.swift ssot/contracts/transcript.v1.schema.json` = 0줄. SHA256 `DomainContracts.swift` f34fb40b… · `transcript.v1.schema.json` 87a059bb…. AI 교정 계약 = `ssot/contracts/library-script.md`: 개정 대상 :181 · :188 · :194 · :206 · :215가 스펙 §05 인용과 글자 일치, 불변 대상 :196 · :200 · :205.
- 사전 확인 (2026-11-07 15:40–15:50 KST):
  - HEAD `7b59b85`, `git status` clean. branch `work/m0-fixture-review` 유지: 선례 (`versions/usage-bundle2/plan.md:3` · usage-bundle1 동일), 로컬이 origin보다 7커밋 앞(미push)이라 전환 금지 (rule-shared-tree-commits). `git merge-base HEAD main` = `git rev-parse main` = `bd8eebe`. `main..HEAD` 7 = usage-review 문서 4 (`c64df9a` · `c366a6c` · `8e89793` · `7b59b85`) · 진단 테스트 1 (`2a20b08`, `CorrectionFormatProbeTests.swift` +187) · 이 유닛 스펙 2 (`574cae7` · `e4b9153`). worktree = 이 트리 + prunable scratch 1.
  - check.sh `run-20261107T064050Z-YUtp42` (HEAD `7b59b85`): 계약 31 PASS · byte-exact PASS · SmokeCheck PASS · swift test 345 실행 = 343 통과 + skipped 2 (`CorrectionFormatProbeTests.testCorrectionChunkReplyAgainstValidationRules` · `RealDataProbeTests`, 둘 다 환경변수 게이트) · 실패 0 (Managed 62 · Core 201 · Audio 82) · xcodebuild Debug PASS · SKIP 축 없음.
  - pbxproj `MARKETING_VERSION` 0.5.19 · `CURRENT_PROJECT_VERSION` 37 (:311 · :320 · :333 · :342). `/Applications/DAMA.app` 0.5.19 (37) 실행 중.
  - 실데이터 시도 기록 (읽기 전용, ID 앞 8자): `CorrectionAttempts/` 1건 `44F4E8DD` · formatVersion 1 · 엔진 끝 `context-correction-6` · 결과 0/44 · 실패 1 (format). 스펙 값과 같다.
  - 신규 문구 리터럴 기준선: 문구 1 · 2 · 3 뒤쪽 · 4 · 5와 `rejectedTurns`가 `-- App UI Packages/DamaCore/Sources scripts`에서 각 0줄 (양성 대조 «AI 보정 결과를 저장했습니다.» 1줄).

## 의도

AI 응답에서 검증을 통과하지 못한 Turn은 그 Turn만 원문을 유지하고 `rejectedTurns`(Turn ID · 규칙 코드)에 남기며, 같은 청크의 다른 Turn은 v6 판정대로 반영한다. 응답을 입력과 짝지을 수 없는 실패만 청크 실패(형식)로 남긴다. 엔진은 `context-correction-7`.

## 영향 범위 (경로 · 현행 실측 2026-11-07)

- `Packages/DamaCore/Sources/DamaCore/ScriptCorrection.swift`: :29–55 `ScriptCorrection` (합성 Codable, :46–54 `validate`: edits turnID 중복·발화 밖 금지 + `validateStored`) · :98 `version = "context-correction-6"` · :173–217 `validated` (:174 id 목록 일치 throw · :177 Turn text·reason 상한 throw · :178–181 span 경로 · :182–201 legacy 경로 · :203–215 이름 검증, 원문 Turn 기준).
- `…/DamaCore/CorrectionSpans.swift`: :27–38 `range` (빈 인용·음수·초과·못 찾음 → throw) · :40–53 `ranges` (:41 개수 100 · :43 change reason 600·replacement 상한 · :49–50 겹침) · :64–109 `validated` (:65 배열 누락·unresolved 100 · :70 재구성 · :73 빈 원문 · :78 미해결 이유 · :81 미해결 인용) · :113–125 `validateStored`. 전부 `LibraryFailure.invalidScript`.
- `…/DamaCore/CorrectionAttempt.swift`: :34–42 `CorrectionChunkResult` · :47 `currentFormatVersion = 1` · :87–99 `merged()`.
- `…/DamaCore/CorrectionReapplication.swift:5–31` `reapplyingPending` (:25–28 새 결과로 옮기는 값 = edits·이름·근거·청크 수).
- `…/DamaCore/LibraryScript.swift`: :237–241 «## AI 교정 정보» 머리 (:239 «- 원문·시간·화자 경계 보존. …») · :259–272 문단별 AI 교정 줄.
- `…/DamaManaged/CorrectionRunner.swift`: :38 `engine` · :75–82 `resumeState` (엔진 일치) · :109–113 검증 실패 = `.format`, 성공 = `CorrectionChunkResult` 기록.
- `…/DamaManaged/CodexCorrectionClient.swift:227–231` 어댑터 형식 검사 (출력 없음 · 2 MB 초과 · 해독 실패 · Turn 배열 누락). 변경 없음.
- `App/CorrectionWorkspace.swift`: :144–151 완료 (:151 완료 문장) · :153 · :161 실패 시 비움.
- `UI/ScriptReadingView.swift`: :252–263 구간 정보 AI 교정 항목 · :264 «모델 원문» 접힘.
- `scripts/ReadingUIFixture.swift:60–62` 합성 QA 앱의 AI 결과 (completed, edits 없음).
- 테스트 가드 (이 유닛 정책에 붉어지는 단정 8): `MeaningGuardTests.swift:67` · `:106` (버전) · `ContextCorrectionTests.swift:70–73` (5사례, `XCTAssertThrowsError`) · `:74` (1사례).
- 수정 없이 PASS해야 하는 가드: `ContextCorrectionTests.swift:77` (validateStored) · `:112` (unresolved 누락 → throw) · `:236` (빈 응답 → throw) · `CorrectionRunnerTests.swift:146` (엔진 «다른 모델 · v6» → planChanged) · `:90–118` · `CorrectionFormatProbeTests.swift` 전체 (스펙 §05 «바꾸지 않는다»; 쓰는 API = `CorrectionSpans.range/ranges/compose/validated`, `ContextCorrection.validated(…).edits` · `outputSchema` · `prompt`, `CodexCorrectionClient.arguments`, `CorrectionAttemptStore.load`, `CorrectionPlan.chunks/sha256`).
- 문서 (/build 개정, D-01): `ssot/contracts/library-script.md` 5곳.
- 시간·단위: 변경 없음. 상한은 Swift `String.count` 글자 수 그대로 (계약상 초기 자원 한도, 확정값 아님).

## 수용 기준

«문구 N» = `ssot/tone/correction-turn-isolation.md` 번호. 규칙 코드 = `quote` · `overlap` · `text` · `limit` · `reason` · `other`. QA 판정 = GPT-6.1-sol (`codex exec -m gpt-6.1-sol --sandbox read-only --ignore-user-config -c model_reasoning_effort="high"`, usage-bundle2 선례; 모델 ID 실행 가능 여부는 QA 직전 1회 확인). 키체인·설치 앱·사용자 데이터 집계·실화면 수집은 메인이 실행하고 판정만 넘긴다. 차수: A = AC-01–08 · B = AC-09 · 전달 = AC-10–12. 공통: 각 태스크 뒤 check.sh 1–3단계 PASS.

### 차수 A · 계약·Core·문구 (합성)

- [x] AC-01 계약 (D-01): 스펙 §05 문안 5곳이 글자 그대로 들어갔다. ① :215 첫 문장 교체 (나머지 문장 유지) ② :194 «완료/전체 청크 수를 보존한다.» 구절 교체 ③ :206 «끝난 청크의 검증된 결과» → «끝난 청크의 검증된 결과(검증 실패 Turn 포함)» ④ :188 끝에 «검증 실패 Turn 기록은 그대로 옮긴다.» ⑤ :181 줄 다음에 `context-correction-7` 줄 신설. 줄 번호가 밀리므로 문안의 앵커 문자열로 편집한다. 고치지 않는 것 diff 0: :196 · :200 · :205 문장 · `CLAUDE.md` 최상위 경계 4. 자 = 문안 대조 (QA), 모집단 5곳. `validate_contracts.py` 31 OK.
- [x] AC-02 Turn 격리 (§02-1 · §02-2, 축 1): `ContextCorrection.validated` 합성 청크 3 Turn [A = 확실한 change 1개 · B = changes `[]` · unresolved `[]` · text 원문 · C = 사례별]. C 원문 «가나다 라마바»(7자) 기준:

  | 사례 | C 응답 | 기대 `rejected` |
  |---|---|---|
  | limit | text «가»×257 (상한 max(256, 21) = 256) | `[C · limit]` |
  | quote | change «없는말»→«라마사» | `[C · quote]` |
  | overlap | changes «가나다 라»→X · «라마바»→Y | `[C · overlap]` |
  | text | change «라마바»→«라마사», text 원문 그대로 | `[C · text]` |
  | reason | unresolved «라마바» · reason «  »(공백만) | `[C · reason]` |
  | other | C 원문 «» · certain=false · changes `[]` · unresolved `[]` | `[C · other]` |
  | 위반 없음 | C = B 형태 | `[]` |

  - 7사례 모두 throw 없음. A의 편집 = `CorrectionSpans.validated(A 단독)` 결과와 같다 (`CorrectionEdit` Equatable, applied·basis 포함). B 편집 없음. C 편집 없음. `names`·`evidence` = 위반 없음 사례와 같다 (원문 Turn 기준 이름 검증, §02-2 ④).
  - 처음 걸린 규칙 2사례: C text 257자 + change 인용 없음 → `limit` · unresolved 하나가 이유 공백 + 인용 없음 → `reason`.
  - 전부 실패: A · B · C 모두 quote 위반 → throw 없음, edits `[]`, `rejected` 3개 입력 순서.
  - 검사 순서 = 현행 throw 순서 (첫 위반 1개만 기록): ① `ScriptCorrection.swift:177` Turn text·reason 상한 → limit ② `CorrectionSpans.swift:65` unresolved > 100 → limit ③ :41 changes > 100 → limit ④ change마다 순서대로 :43 reason·replacement 상한 → limit, 이어서 :28–37 인용 → quote ⑤ :49–50 → overlap ⑥ :70 → text ⑦ :73 → other ⑧ unresolved마다 :78 이유 공백 → reason · 600 초과 → limit, 이어서 :81 인용 → quote. legacy 경로(changes · unresolved 둘 다 nil) Turn은 ①만.
- [x] AC-03 청크 실패 유지 (§02-1, 축 2): 4사례 → 청크 실패(형식), 결과 기록 없음.
  - `ContextCorrection.validated` 단위: id 순서 뒤바뀜 · id 1개 빠짐 · Turn 하나 `unresolved` nil(`changes` 있음) → `LibraryFailure.invalidScript` throw. 배열 누락은 응답 전체를 먼저 훑어 판정한다: index 0 Turn quote 위반 + index 2 Turn `unresolved` nil → throw (Turn 격리로 넘어가지 않음).
  - `CorrectionRunner.run` (가짜 CLI 모드 파일): 해독 실패(출력 «{») · id 순서 뒤바뀜 · id 1개 빠짐 · Turn 하나 `unresolved` 키 없음 → 4사례 모두 `.failed`, `lastFailure.kind == .format`, `exitCode == 0`, `results` 0개.
  - 어댑터 불변: `git diff 7b59b85 -- Packages/DamaCore/Sources/DamaManaged/CodexCorrectionClient.swift` 빈 출력.
- [x] AC-04 엔진·가드 이동 (D-01 · §02-4, 축 7 · 8):
  - `ContextCorrection.version == "context-correction-7"`, `CorrectionRunner.engine` 끝 « · context-correction-7».
  - 가드 이동 8단정 (형태·건수 유지, 사례당 단정 1): `MeaningGuardTests.swift:67` 기대값 v7 · `:106` `hasSuffix("저장 후보 반영 context-correction-7")` · `ContextCorrectionTests.swift:70–73` 5사례 `XCTAssertThrowsError` → `rejected == [t · 규칙]` (인용 «없음» quote · 위치 −1 quote · 위치 2 quote · 같은 change 2개 overlap · «30억원 30억원» + change() overlap) · `:74` → `[t · text]`. 스펙 축 8의 «버전 단정 2곳»은 실측 8단정으로 정정 (§02-1이 :70–74 6사례를 Turn 실패로 정한다).
  - 역뮤테이션 (원본 바이트 보관·복원·해시 대조): ⓐ Turn 실패를 다시 throw → 붉음 = AC-02 10사례 중 위반 9 + 이동 6 + AC-06 runner 사례 (건수 기록) ⓑ version을 v6로 → 붉음 2 (:67 · :106).
  - 수정 없이 PASS: `ContextCorrectionTests.swift:77` · `:112` · `:236` · `CorrectionRunnerTests.swift:146`.
- [x] AC-05 저장 (D-02 · §02-3, 축 3):
  - ⓐ 타입: `public enum CorrectionRejectionRule: String, Codable, Sendable, CaseIterable { case quote, overlap, text, limit, reason, other }` · `public struct CorrectionRejectedTurn: Codable, Sendable, Equatable { public let turnID: String; public let rule: CorrectionRejectionRule }` · `ScriptCorrection.rejectedTurns: [CorrectionRejectedTurn]? = nil` (합성 Codable, nil이면 키 없음) · `ScriptCorrection.rejectedCount(in turnIDs: [String]) -> Int`.
  - ⓑ 기존 파일 바이트: 현행 형태로 고정한 `ScriptCorrection` JSON 리터럴 1개 (키 정렬, `rejectedTurns` 없음, edits 1 · speakerNames 1) 해독 → `.sortedKeys` 재인코딩 = 리터럴 바이트. `fixtures/normalized-transcript.json` 기반 `LibraryScript`(교정 completed, `rejectedTurns` nil) 인코딩 → 해독 → 재인코딩 바이트 동일, `rejectedTurns` 문자열 0.
  - ⓒ 저장 검증 위반 4종 → 손상: (1) turnID `t-marker` (fixture의 missingSpeech Turn = 발화 밖) (2) 같은 turnID 2개 (3) edits에 있는 turnID (4) rule «bogus». (1)–(3) `ScriptCorrection.validate` → `LibraryFailure.invalidScript`. (4) `JSONDecoder().decode(LibraryScript.self)` 실패. 폴더 조회에서 4종 모두 목록 제외 · issue `.unreadable` (현행 손상 분류 `FolderLibraryStore.swift:346–353`).
  - ⓓ 왕복: `rejectedTurns [t3 · quote]` 결과 `saveCorrection` → 다시 열기 → 같은 값, 저장 바이트에 키 1개.
  - ⓔ 경계 4 · INV-09 · INV-06/RC-01: 교정 저장 전후 `transcript` 인코딩 바이트 동일 (Turn ID·시간·화자·Turn 수 불변, 다른 Run 매핑 0).
- [x] AC-06 시도 기록·실행기 (§02-2 ⑦ · §02-3, 축 4):
  - `CorrectionChunkResult.rejected: [CorrectionRejectedTurn]?` (init 기본값 nil, 빈 목록 → nil). `CorrectionAttempt.currentFormatVersion` 1 유지. `merged()` 반환에 `rejected` (청크 순서 → 청크 안 입력 순서). `CorrectionRunner.run`이 검증 결과의 rejected를 청크 결과에 기록.
  - 가짜 CLI «reject» 모드 (청크마다 첫 Turn change quote를 «없는말»로): `CorrectionRunnerTests.script()` 12청크 → `.completed`, 청크 결과마다 rejected 1개 (quote), `merged().rejected` 12개, `merged().edits` 1,188 (현행 기준선 1,200 = `CorrectionRunnerTests.swift:91` − 12).
  - 이어서: reject 모드 + fail-at 5 → 실패, 시도 기록 파일의 완료 4청크 결과에 rejected 각 1 → 이어서 교정 → 호출 13 (5 + 8, 현행 :112와 같음) → `merged().rejected` = 한 번에 끝낸 reject 기준선과 같은 12개·같은 순서.
  - 기존 시도 기록: 현행 형태 JSON 리터럴 (formatVersion 1, 결과 1개 `rejected` 키 없음) → `CorrectionAttemptStore.load` 성공 · `save` 재인코딩 바이트 = 리터럴.
- [x] AC-07 재반영·오류 형식 (§02-3, 축 5):
  - `MeaningGuardTests.testReapplication…` 구성 (fixture t1 · t2 보류 후보 2) + `rejectedTurns [t3 · quote]` → `reapplyingPending` 결과 `rejectedTurns == [t3 · quote]`, edits 단정은 현행 :94–105 그대로. 바뀔 후보 없으면 nil (현행).
  - 밖으로 나가는 오류 형식은 현행 `LibraryFailure.invalidScript`만: `validateStored` 변조 (`ContextCorrectionTests.swift:76` 같은 `appliedText` 변조 1 + change quote 변조 1) → 오류가 `LibraryFailure.invalidScript`. `reapplyingPending`도 같은 형식 (Turn 격리는 새 응답 검증에만).
- [x] AC-08 문구·Markdown·구간 정보·완료 띠 (§03 · §04 문구표, 축 6):
  - DamaCore `CorrectionRejectionText`: `inspectorTitle` = 문구 1 · `paragraphNote(count:)` = 문구 2, count ≥ 2면 « ({count}개 원구간)» · `completionSuffix(count:)` = count ≥ 1이면 « » + 문구 3, 0이면 «» · `markdownSummary(count:)` = 문구 4 · `markdownPrefix` = 문구 5. 단위: k = 1 · 2 · 3, N = 0 · 1 · 12 글자 그대로 (tone 표와 대조).
  - 리터럴 1곳: 문구 1 · 2 · 4 · 5와 «원구간은 원문을 유지했습니다.» 각각 `git grep -n -F '<문구>' -- App UI Packages/DamaCore/Sources scripts` = 1줄 (`CorrectionRejectionText`, 기준선 0).
  - 완료 띠: `CorrectionWorkspace` 완료 문장 = 현행 :151 리터럴 + `completionSuffix(count: merged.rejected.count)`, 완료 시 빈 목록 → `rejectedTurns` nil. 실패 두 자리 (:153 · :161) `rejectedTurns = nil`. N = 0 → 현행 리터럴과 바이트 동일 (단위). 자 = 단위 + 코드 대조 (QA).
  - Markdown: :239 줄 다음에 N ≥ 1이면 문구 4 한 줄. 문단의 AI 교정 줄 반복 (:259–272) 다음에 k ≥ 1이면 `markdownPrefix + paragraphNote(count: k)` 한 줄과 빈 줄. 합성 = fixture + `rejectedTurns [t3]` → 머리 줄 1 · t3 문단 줄 1 · 다른 문단 0. 원구간 2개 문단 사례 → « (2개 원구간)». N = 0 (nil): Markdown SHA256 = T-06 착수 전 현행 코드로 만든 같은 합성 스크립트 Markdown SHA256 (실측 뒤 기록).
  - 구간 정보: `ScriptReadingView.swift` :263 `ForEach(edits)` 다음 · :264 «모델 원문» 앞, 조건 `rejectedCount(in: block.turnIDs) ≥ 1`, `VStack(alignment: .leading, spacing: 6)` { 문구 1 `.fontWeight(.semibold)` · `paragraphNote(count: k)` } `.font(.caption)`. 원문 보기 전환과 무관 (`shown.script.correction`, :252와 같은 출처). 자 = 코드 대조 (QA) + AC-09.

### 차수 B · 실화면

- [ ] AC-09 구간 정보 실화면 (막힘 2): `ReadingUIFixture.swift`의 합성 AI 결과에 문단 P1 = AI 교정 항목 1 (legacy 보류 edit) + 버린 원구간 1 · P2 = 버린 원구간 ≥ 2 · P3 = 없음 (fixture 실측 후 문단 선택). 합성 QA 앱 `com.gazitofu.Dama.ReadingQA` + fixture `/private/tmp/dama-reading-qa-cti-*` QASnapshot: P1 = AI 교정 항목 → 문구 1 → 문구 2 → «모델 원문» 순, 2a 없음 · P2 = 문구 2 끝 « ({k}개 원구간)» · P3 = 문구 1 · 2 없음 · P1을 원문 보기 전환 켠 상태로 1장 더 (문구 1 · 2 그대로). 수집기 = 실행 전 AC 문언·조작 경로·관측 수단 대조표.

### 전달

- [ ] AC-10 회귀 (축 8): check.sh 1–4 PASS · swift test 통과 ≥ 343 + 신규 · skipped 2 유지 · 기존 테스트 삭제 0 · 완화 0 (이동 = AC-04 8단정뿐) · `git diff 7b59b85 -- Packages/DamaCore/Tests/DamaManagedTests/CorrectionFormatProbeTests.swift` 빈 출력, 그 안의 상시 테스트 `testProbeClassifierNamesTheFirstFailingRule` PASS.
- [ ] AC-11 버전·설치: `MARKETING_VERSION` 0.5.20 · `CURRENT_PROJECT_VERSION` 38 (Debug/Release). check.sh 4단계 PASS. 설치 앱 교체 (막힘 1) 뒤 실행 중 Bundle 0.5.20 (38), 메뉴바 툴팁.
- [ ] AC-12 실데이터 (축 9, 게이트 ②, 막힘 3): 사용자가 설치 앱 0.5.20에서 30–40분 Soniox + Nemotron 결합본 1개를 «AI 검수/보정» 1회. 메인이 메타데이터로 잰다 (출력 = 개수·규칙 이름·ID 앞 8자): 상태 · 완료/전체 청크 · `rejectedTurns` 수 · 규칙별 수 · 발화 Turn 수 · edits 수 · 실패면 분류·종료 코드·경과. 문턱 없음 (모델 응답에 달림). 완료 띠 글자는 사용자 관측. 이어서 묶음 3 ① 원음 대조 (`correction-measure.md` 프로토콜, 이 유닛 밖).

## /build 결과 (2026-11-07 · 1차, 막힘 대기)

커밋 `d557f8c`(T-01) · `0f3c797`(T-02) · `a6bb767`(T-03) · `f65f6dc`(T-04) · `6267108`(T-05) · `fc73e21`(T-06) · `61fa996`(QA A D-1) · `5be318c`(T-07 fixture) · `0e4c51a`(T-08 버전 0.5.20 (38)). 구현 = 메인 직접. QA = GPT-6.1-sol `codex exec -m gpt-6.1-sol --sandbox read-only --ignore-user-config -c model_reasoning_effort="high"` (codex-cli 0.166.0), 증거·판정 `.build/qa/correction-turn-isolation/` (A · A2).

- check.sh `run-20261107T082026Z-HJGlkU` (HEAD `0e4c51a`): 계약 31 · byte-exact · SmokeCheck · swift test 362 실행 = 360 통과 + skipped 2 (Managed 66 / Core 212 / Audio 84), 실패 0 · xcodebuild Debug PASS, 산출물 Bundle 0.5.20 (38). 기준선 343 + 2 → 360 + 2 (신규 17, 사라진 테스트 이름 0, 이동 = AC-04 8단정).
- 역뮤테이션 (러너 = 원본 바이트 보관·복원·SHA256 대조, 전부 복원 해시 같음): ⓐ Turn 실패 → 청크 throw = 붉음 23 (AC-02 위반 9 · 이동 6 · 분리 신규 6 · 실행기 2) · ⓑ 버전 v6 = 2 · ⓒ 재반영 운반 삭제 = 1 · ⓓ 저장 검증 오류 변환 삭제 = 2.
- Markdown N = 0 기준선 SHA256 `5dc04eb6…` · 1,564 B (T-06 착수 전 HEAD `6267108` 실측) = 변경 뒤 nil · `[]` 같은 값.
- QA 앱: `.build/xcode-qa/Build/Products/Debug/DAMA.app` `com.gazitofu.Dama.ReadingQA` 0.5.20 (38), 로그 `.build/check-logs/cti-qa-app-build.log` BUILD SUCCEEDED (첫 시도는 소문자 cwd 모듈 캐시 충돌, `cd "$(/bin/pwd -P)"` 뒤 성공 · dev.md 부칙 11-07과 같은 원인). 합성 fixture `/private/tmp/dama-reading-qa-cti-a` (임시 패키지 = job tmp, `scripts/ReadingUIFixture.swift`와 같은 소스): 스크립트 `8DEED307` 편집 t0 · 버림 t1(quote) · t4 · t5(text), 문단 [t0 t1 t2] · [t3] · [t4 t5] …
- 실제로 쓴 것: 이 Mac의 사용자 데이터 읽기 1회 (plan 근거 `CorrectionAttempts/` 메타데이터, 개수·ID 앞 8자). 앱 실행·마이크·API·네트워크(QA용 codex 호출 제외)·음성 전송·키체인·설치 0. 사용자 데이터 쓰기 0.

| AC | 판정 (QA) | 남은 것 |
|---|---|---|
| 01–03 · 05–08 | 통과 (A) | AC-08 구간 정보·완료 띠는 코드 대조까지. 실화면 = AC-09 · 게이트 ② |
| 04 | 통과 (A2, D-1 해소) | |
| 09 | 막힘 | 합성 QA 앱 0.5.20 (38) · fixture a 실행, QASnapshot 창 캡처 1장 성공(`ui/` 기본 화면). System Events 질의가 10초 안에 끝나지 않아(SIGALRM, 이 백그라운드 세션의 자동화·접근성 권한 없음으로 봄) «정보»·결과 전환·문단 선택 조작 불가. «원문 보기 전환» 컨트롤은 UI에 없음(`toggleOriginal` 호출처 0) → fixture b `showsOriginal = true` 사본 준비. 처리 방식 사용자 확인 |
| 10 | 메인 실측 충족 (check.sh 1–4 PASS · 360 통과 · 삭제·완화 0 · 진단 테스트·어댑터 diff 0) | 최종 판정은 전달 차수 QA |
| 11 | 설치 2026-11-07 20:2x (사용자 승인): 설치 앱 0.5.19 (37) 종료 → 백업 `.build/backups/DAMA-0.5.19-37-before-correction-turn-isolation.app` 11파일 SHA256 = 설치본 → `/Applications/DAMA.app` 교체 11파일 SHA256 = `.build/xcode/Build/Products/Debug/DAMA.app`, adhoc·linker-signed. 실행 pid 적재 경로 `/Applications/DAMA.app`, `lsappinfo` bundleID `com.gazitofu.Dama` · Version 38, Info.plist 0.5.20 | 메뉴바 툴팁 = 사용자 관측 (접근성 불가) |
| 12 | 대기 | 막힘 3 (사용자 실행) |

## 작업 분해

- T-01 계약 개정 (AC-01): `library-script.md` §05 5곳.
- T-02 저장 타입·검증 (AC-05): `CorrectionRejectionRule` · `CorrectionRejectedTurn` · `ScriptCorrection.rejectedTurns` · `validate` 3조건 · `rejectedCount(in:)`.
- T-03 응답 검증 Turn 격리·엔진 v7 (AC-02 · AC-03 단위 · AC-04): 내부 오류 `CorrectionTurnRejection(rule)` (DamaCore internal)을 `CorrectionSpans.range/ranges/validated`가 낸다 (시그니처 불변). `ContextCorrection.validated` 반환 `(edits:, names:, evidence:, rejected:)`, throw는 id 불일치 · 배열 하나만 nil뿐. `version` v7. 가드 이동 8 · 역뮤테이션 2.
- T-04 시도 기록·실행기 (AC-06 · AC-03 실행기): `CorrectionChunkResult.rejected` · `merged()` · `CorrectionRunner.run` · 가짜 CLI 모드 (reject · 해독 실패 · id 순서 · id 빠짐 · 배열 누락).
- T-05 재반영·오류 형식 (AC-07): `reapplyingPending`이 `rejectedTurns`를 옮김 · `validateStored`·재반영이 내부 오류를 `LibraryFailure.invalidScript`로 바꿔 낸다.
- T-06 문구·Markdown·구간 정보·완료 띠 (AC-08): `CorrectionRejectionText` · `LibraryScript` Markdown · `ScriptReadingView` · `CorrectionWorkspace`. Markdown N = 0 SHA256 기준선은 착수 전에 잰다. **차수 A 경계**: check.sh 1–4 + QA A (AC-01–08).
- T-07 실화면 (AC-09): `ReadingUIFixture.swift` 합성 rejectedTurns · QA 앱 캡처 (막힘 2). QA B.
- T-08 전달 (AC-10 · 11 · 12): 버전 0.5.20 (38) · 설치 (막힘 1) · 게이트 ② 실데이터 측정 (막힘 3).

구현 = 메인 직접 (프로젝트 CLAUDE.md «메인이 Opus면 직접 구현», usage-bundle1 · 2 선례). 태스크마다 check.sh 1–3단계, 앱 빌드·실화면은 차수 경계에서 1회. 사용자 데이터 쓰기 0 (AC-12는 사용자 실행).

## 결정 항목

없음. 스펙이 정하지 않은 자리는 실측으로 닫고 위 AC에 값으로 박았다 (새 정책 아님):
- 가드 이동 수 = 8단정 (스펙 축 8 «2곳» 정정, AC-04). §02-1이 `ContextCorrectionTests.swift:70–74` 6사례를 Turn 실패로 정하므로 대상 이동만 성립한다 (rule-numeric-test-integrity: 형태·건수 유지 + 역뮤테이션).
- 배열 누락 = 응답 전체를 먼저 훑어 청크 실패 (AC-03). 현행도 청크 실패라 결과 같다. 둘 다 nil인 Turn은 legacy 로컬 경로 유지 (실응답은 어댑터 :231이 막음, 불변).
- `CorrectionChunkResult.rejected` 빈 목록 → nil, 순서 = 청크 → 입력 Turn (AC-06). `ScriptCorrection`과 같은 규칙.
- 밖으로 나가는 오류 형식 = 현행 `LibraryFailure.invalidScript` (AC-07). 스펙 §02-3 «버린 Turn은 다시 판정하지 않는다».
- 모르는 규칙 = 해독 실패, 조회 분류는 `invalidScript`와 같은 `.unreadable` (AC-05ⓒ).
- 문구 조립 = DamaCore 1곳 (AC-08). UI · Markdown · 완료 띠가 같은 문자열을 쓰고 단위로 잰다.
- 실화면 축 = 스펙 §03-1 배치·굵기 요구의 소비 경로 확인 (AC-09). 합성 QA 앱 선례 (usage-bundle1 · 2).

## 막힘 (사용자 실행·승인 항목)

1. 설치 앱 교체 1회 (T-08, 0.5.20 (38)): 실행 중 앱 종료 포함. 승인 후 메인 실행, 백업 `.build/backups/DAMA-0.5.19-37-before-correction-turn-isolation.app` 파일 수·SHA256 대조 뒤 교체.
2. 합성 QA 앱 실화면 (AC-09): 앱 창이 앞으로 오고 접근성 조작이 사용자 입력과 겹친다 (usage-bundle1 F-12 · F-15). 사용자 부재 시간 합의 뒤에만.
3. 실데이터 교정 1회 (AC-12): 사용자 실행 (OpenAI 전송, Codex 사용량 소모). 대상 30–40분 결합본은 사용자가 고른다. `44F4E8DD`(140.6분, v6 미완료 0/44)는 대상 조건 밖이며 열면 «이어서 교정» 대신 기존 문구 16이 뜬다 (엔진 불일치, `CorrectionRunnerTests.swift:146` 축).
4. 안 잼 (스펙 §04): 교정 품질 (묶음 3 ①) · 인용 불일치 원인과 Turn 실패율 변화 · 새 문장 키보드·VoiceOver (묶음 5) · 다른 공급자 (T4-5). 완료 띠 실화면은 합성 QA 앱이 AI 실행을 막아 (`CorrectionWorkspace.swift:95` · `:104`) 게이트 ② 사용자 관측만.

## Follow-ups

- F-01 (기록) 이 유닛 뒤 `CorrectionFormatProbeTests`의 `r["validated"]`는 Turn 실패만 있는 응답에서도 true가 된다 (코드 불변, 스펙 §05). 묶음 3 진단을 다시 돌리면 판정은 `turnRule` 집계로 읽는다.
- F-02 (관측, 이 유닛 범위 밖) `CorrectionFailureTests.testNetworkMarkerDuringTimeoutIsNetworkAndOtherConfigMarker`가 check.sh `run-20261107T081450Z-MtBELu`에서 1회 실패(«timeout» ≠ «network»). 400ms 시간 초과 안에 셸 루프가 stderr 표식을 내야 하는 시간 경쟁. 이 테스트가 든 check 실행 40회 중 1회, 직전 PASS 이후 바뀐 것은 Core 테스트 2파일뿐(`CodexCorrectionClient` 무변경), 같은 트리 재실행 `run-20261107T081612Z-tmygxn` PASS. 시간 여유를 넓힐지는 별도 결정.

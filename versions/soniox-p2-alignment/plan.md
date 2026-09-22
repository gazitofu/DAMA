---
unit: soniox-p2-alignment
branch: work/m0-fixture-review
status: building
decisions_resolved: true
resume: "T-07 착수: 09-22 진단 결과로 사용자가 어절 원자성 개선을 승인(2026-09-22). 비교 정책 soniox-p2-word-v5 추가 → 비교 Script 생성 → 사용자 판정. 운영 기본값 word-v4는 D-02대로 유지. T-01~06 AC 및 타 트랙 보류 유지."
spec: "사용자 2026-09-13 규칙 완화/결과 비교 승인 + 2026-09-22 어절 원자성 개선 승인, ssot/design/00·02·04 및 notes/uiux-reading/speaker-context-diagnosis.md"
---

## 근거

- 사용자: 규칙 완화 허용. Soniox 연속 원문을 P2로 분할하는 아이디어 판단, 권고안도 결과 확인 후 결정. 목적은 화자 구분 + Soniox 텍스트 품질이며 AI 문맥 후보정은 추후.
- 하이브리드 계약 유닛. UI는 게이트② 확인 완료이며 새 화면/재승인 없음. 비교본 생성과 검증까지 자율 승인, 운영 기본값 승격은 결과 확인 뒤 결정.
- 홈/Vault appdev/repo CLAUDE와 주입 AGENTS, README/Vault 인덱스, spec·plan·build 절차; 규율22종 설명 재탐색, 이전 로드 공통10/appdev2/미디어/워치독/정렬/Apple/인라인/리뷰종료 본문 재사용, 수치·공유트리 본문 재확인. 독립 Codex 직접 구현, 하위 위임 없음.
- design00·02·04·06, dev/API verified, DomainContracts/schema/operating-baseline/library-script 실측. 현재 App은 Script의 sessionId로 보존 analysis.wav를 재생하며 새 runId의 Script도 기존 UI에서 읽을 수 있음.
- HEAD3a9d529, 기존 dirty7(.claude/commands/build.md, README.md, notes/qwen-local/evaluation.md, ssot/dev.md, versions/m0·m1·m2 plan) 보존. 공유 트리이므로 브랜치 전환/타 소유 커밋 없음.
- 사전검사 PASS: `.build/check-logs/soniox-p2-alignment-baseline/run-20260912T160116Z-OI0Nzz`, 계약30/Swift170/Debug/SKIP0. 새 독립 scratch 동명.

## 의도

### T-07 · 2026-09-22 어절 원자성 비교 정책

- 입력: 사용자 "지금 9/22 녹취록의 퀄리티를 개선할 방법이 없는지 봐봐" → 진단 보고 → "가장 큰 개선 진행하자". 새 화면·재승인 없음. 이 유닛만 built→building→built로 갱신하고 이전 AC는 유지한다.
- 실측 HEAD `4ae706b`, branch 일치, 설치 0.5.9(27). 사전검사 `.build/check-logs/word-v5-baseline/run-20260922T073822Z-nKVt5O` 계약30 / Swift205 / Debug PASS, SKIP 0. 타 소유 dirty 8 + untracked `ssot/api/nari-verified.md` 보존.
- 진단 근거: 현행 `soniox-p2-word-v4`가 09-22에서 한 어절을 두 화자로 42건 갈라 놓았다. 전부 `해야지` `거예요` `차액이` `1600억` 같은 단일 어절이고 두 단어가 붙은 사례는 0건이다. 한 어절을 두 사람이 나눠 말할 수 없으므로 42건 모두 최소 한쪽이 확정적으로 틀렸고 동시에 헛된 발화 구분 42개를 만든다.
- 변경: 비교 정책 `soniox-p2-word-v5`를 추가한다. v4의 문장부호·꼬리 보완을 그대로 켜고, `sharePhraseTailEvidence` 뒤 `attachClosingPunctuation` 앞에 어절 원자성 패스를 넣는다. **v4가 어절 안에서 화자를 갈라 둔 어절에만** 적용하고, 어절 전체 구간의 exclusive coverage 최대 화자로 통일한다. 동률·후보 없음은 그대로 둔다. 공백 경계를 넘지 않으므로 짧은 B 발화 어절은 보존된다(INV-06).
- 운영 기본값은 바꾸지 않는다. `normalize`는 `.wordRepair`, `ManagedRun.combinationAlgorithmVersion`은 `soniox-p2-word-v4` 유지. 승격은 사용자 판정 후 별도 태스크다(D-02).
- 시간·수치: 새 변환·오프셋·임계값을 만들지 않는다. `P2TimeEvidence.token`의 기존 반열린 구간·동률 규칙을 그대로 쓴다. 500,000µs 꼬리 한도 변경 없음.
- 위임: 발주문 `notes/soniox-p2-alignment/codex/t07-word-atomicity.md`, 수탁 Codex CLI. 분할·diff 리뷰·테스트 실행·통합·판정은 메인.
- [x] AC-17 `soniox-p2-word-v5`가 v4의 문장부호/꼬리/`acoustic` 판정을 동일하게 켠다. 이미 단일 화자이거나 전부 null인 어절은 v4와 바이트 동일. 동률 어절은 v4와 동일하며 전체 null로 만들지 않는다. 공백 경계를 넘지 않는다.
- [x] AC-18 Soniox 원문·prefix·ordinal·token kind·원시간·ASR confidence·언어·`asrSpeakerLabel` 보존. `overlap`/`boundary` 파생 이슈는 `direct()` 계산값 유지. 기존 v2/v3/v4 결과·기본값·golden 불변. INV-01·02·06·08·09.
- [x] AC-19 실제 저장 응답으로 09-22·09-21 비교본을 생성하고 v4 대비 문단·미배정·단어중간절단을 실측한다. 새 음성/API/AI 호출 0. 미배정·문단 수는 정확도 실측이 아니다.
- [ ] AC-20 계약·Swift 전수·Debug PASS, 역뮤테이션으로 새 검사의 실패 확인. 사용자 Scripts 기존 파일 해시 불변, 새 비교 파일만 추가.
- QA 경계: 정책 계산 → 비교본 생성 → 앱에서 v4/v5 대조 한 묶음. 운영 승격·AI 구조 변경·Qwen 학습·타 트랙은 보류.

#### T-07 검증·전달 결과

- 구현은 발주문대로 Codex CLI 수탁(`task-mucd8c4p-h16dym`). `SonioxPrecisionReconciler`에 `.wordAtomic = "soniox-p2-word-v5"`와 `repairsWords` 계산 속성, `resolveWordAtomicity` 추가. v4의 세 분기(문장부호 Choice, 꼬리 공유, `acoustic`)를 `repairsWords`로 v5에도 연결. `normalize`의 `.wordRepair`, ManagedProcessor, `combinationAlgorithmVersion`, reconcile 가드, `policy != .timeline` 두 분기는 불변.
- 수탁 테스트는 샌드박스에서 실행 불가(`swift test` manifest 컴파일 단계 쓰기 차단)로 미실행 기록. 메인이 밖에서 전수 실행했고 `XCTAssertEqual(try a, b)`의 `try` 누락 5건 컴파일 오류를 메인이 수정했다. 실패 로그 `.build/check-logs/word-v5-impl/run-20260922T074613Z-Gfzlmk`.
- 사전검사 `.build/check-logs/word-v5-baseline/run-20260922T073822Z-nKVt5O` 계약30/Swift205/Debug/SKIP0. 최종 `.build/check-logs/word-v5-impl2/run-20260922T074701Z-XoPiYn` **계약30/Swift212/Debug/SKIP0 PASS**, 실패 0. 신규 7건 전부 통과.
- 역뮤테이션 2종: 분할 어절 한정 가드(`Set(...).count > 1`) 제거 시 `testWordAtomicLeavesUnanimousWordAlone` 등 3단정 FAIL, 원자성 패스 비활성 시 8단정 FAIL. 각각 복원 후 대상 19건 PASS, 원본 파일 SHA256 `89a1a477…` 바이트 복원 확인.
- `scripts/CompareSonioxPrecision.swift` 갱신(메인): 원본 Script가 이미 정책 결과(word-v4)면 같은 raw로 v2 기반본을 다시 만들고 기록된 정책을 재적용해 현재 파일과 `NormalizedTranscriptCodec` 바이트 동일한지 확인한 뒤 그 기반본을 비교 입력으로 쓴다. `.wordAtomic` 라벨 "비교 C · 어절 원자성" 추가. 이 동일성 확인이 통과했다는 것은 현재 09-22·09-21 결과가 저장 응답만으로 재현된다는 뜻이다.
- 실제 저장 응답으로 생성(새 음성/API/AI 호출 0, transport 미사용). 09-22 `.build/diagnostics/word-v5/0922-v5/227D4B49-AC4D-4924-BF89-64FE0FC2682F.dama.json`(base Run `6F7A3B89`), 09-21 `.build/diagnostics/word-v5/0921-v5/6E757EE7-26D3-4CD1-BCB9-3396C3A42B6E.dama.json`(base Run `3E66BE55`). 각 manifest에 입력 8개 해시·원본 snapshot·normalized·Markdown 보존.

| | 문단 | 미배정 문단 | 미배정 토큰 | 단어중간절단 | 어절 안 화자 분할 | 어절/문단 |
|---|---|---|---|---|---|---|
| 09-22 v4 | 193 | 12 | 66 | 61 | 42 | 26.0 |
| 09-22 v5 | 172 | 9 | 61 | 19 | **0** | 29.2 |
| 09-21 v4 | 323 | 39 | 130 | 73 | 31 | 20.2 |
| 09-21 v5 | 312 | 35 | 123 | 43 | **0** | 20.9 |

- 토큰 5,851/7,605 보존. `id·ordinal·text·prefix·startUs·endUs·tokenKind·asrConfidence·language·asrSpeakerLabel·editedText·timingOrigin` 불일치 0, `diarization`/`exclusiveDiarization` 개수 동일. 바뀐 필드는 `speakerId·modelSpeakerId·assignmentSource·alignmentScore·sourceIntervalIds·reviewIssueIds`뿐이고 `overlap`은 보존됐다. providerId 기준 화자가 바뀐 어절은 09-22 54개(null→화자 3, 화자→null 0, A→B 51), 09-21 38개(null→화자 4, 화자→null 0, A→B 34).
- 예시(09-22): `아, 당연히 해야` / `지. 인수는—` → `아, 당연히 해야지.` / `인수는— 인수는 벌써 했잖아.` · `회사 입` / `장에서.` → `회사` / `입장에서.` · `그러니` / `까 이건 우리 아이디` / `어` / `지.` → `그러니까` / `이건 우리 아이디어지. …` · `환하면` → `상환하면`.
- 문단·미배정 수는 정확도 실측이 아니다. E1/E2와 실제 화자 정답은 사용자의 원음 대조로만 판정한다. 운영 기본값은 v4 그대로이며 앱 바이너리·버전 변경 없음(0.5.9(27) 유지). 앱은 `algorithmVersion`을 Markdown 표시 외에 분기에 쓰지 않아 설치본이 v5 Script를 그대로 읽는다.
- 사용자 `~/DAMA/Scripts` 17개 파일 무변경(16:40 이후 수정 0건). **비교본 배치는 외부 폴더 쓰기이므로 사용자 승인 대기 중이다.**

### T-06 · 2026-09-13 승인된 B2의 새 전사 기본 연결

- 입력: operating-baseline plan:84 재개 요청 및 B2 확정. B2 재승인·새 화면 설계 없음. 이 유닛만 planning→ready-to-build→building→built로 갱신하고 이전 AC는 유지한다.
- 실측 HEAD `bb44c84`, branch 일치, 설치0.5.4(22). 다른 소유 dirty7는 기존 목록과 일치하며 `.build/diagnostics/word-v4/preservation-before.json`에 파일 해시와 현재 Script7개 해시를 보존했다. B2에는 후속 AI/사람 수정이 있으므로 현재 파일 바이트를 기준으로 보존한다.
- 홈/appdev/repo 지침, README/Vault 인덱스, spec·plan·build, 현행 규율22개 설명 및 필수 공통10/appdev2/미디어/워치독·Apple/인라인/리뷰종료 본문, design00·02·03·04·06·07, dev/API verified, DomainContracts/schema/library-script/operating-baseline, T-05·Core/Managed/저장/앱 소비 경로를 읽었다. 독립 Codex 직접 구현.
- 변경: Reconciler의 raw 정규화 진입점에서 동일 word-v4 계산을 재사용한다. `ManagedRun.combinationAlgorithmVersion: String?`를 새 parent 생성 시 `soniox-p2-word-v4`로 저장한다. 기존 누락 필드는 v2로 읽고 재개 때 고정, 지원하지 않는 정책은 소스 실행 전에 실패한다. 비교용 `reconcile`의 새 Run·사람 수정 거부는 유지한다.
- 새 전사·저장 소스 재사용·중단 재개는 Run에 고정한 정책과 같은 원응답을 사용한다. completed model/revision은 immutable, 다른 Run의 이름·본문·등록 화자·삭제·AI 이력은 이식하지 않는다. source 캐시 동일성·접수 불명·키/동의 경계는 기존 계약을 유지한다.
- 시간: Soniox ms/P2 s→기존 Int64 µs, 반열린 구간. 변환·500,000µs 꼬리 한도·정책값 변경 없음. INV-01~09/RC-01~09·13 및 기존 T-05 고정 회귀 재사용.
- [x] AC-13 새 mock 처리와 양쪽 저장 소스 재사용 결과가 word-v4, source request/raw/ID·원 토큰/시간 보존, 새 Run/화자 ID 분리. 승인된 비교 계산과 normalized 전 필드 동일.
- [x] AC-14 재시작/중단과 model 저장 후 상태 저장 전 복구에서 같은 Run/정책/결과 유지, 추가 POST 없음. 구 정책 누락/v2는 v2 유지, 미지원 버전은 외부 호출 전에 거부, 불명 접수 재제출 없음.
- [x] AC-15 실제 저장 소스 사본의 Managed 경로→Script 저장·재열기·Markdown 검증, B2와 정규화 의미 동일, 현재 Script7개/입력/사람 수정 불변. 새 음성/API/AI 전송 없음. E1/E2/청취 정답은 미측정.
- [x] AC-16 계약·Swift 회귀·Debug PASS, Debug/Release0.5.5(23), 백업 후 로컬 앱 전달·실행 버전 확인. main/push/release 없음.
- QA 경계: 신규 처리/재사용→중단/재개→Script 저장/재열기/내보내기 한 묶음. 위 네 축 확인 후 종료하며 다른 트랙·AI 구조 변경·Qwen 학습은 보류한다.
- 사전검사 원본 `word-v4-baseline/run-20260913T042120Z-dcE75t`: 계약30 PASS, Swift/앱 FAIL. `_DarwinFoundation1`의 `Developer/Dama`와 `developer/dama` 공용 PCM 중복 정의와 signal11 관측. 공용 캐시 삭제 없이 check.sh 사본의 루트·MODULE_CACHE만 고정해 동일4단계 재검사한다.
- 사전 재검사 `word-v4-baseline-isolated/run-20260913T042740Z-56SdI1`: 계약30/Swift195/Debug/SKIP0 PASS. 정책 결정 해소, ready-to-build 확인 후 building 진입.

#### T-06 검증·전달 결과

- 최종 제품 변경: 새 parent에 word-v4 저장, 필드 없는 과거 Run에 v2 고정, 정책 미지원 조기 거부, raw→B2 정규화 진입점과 비교 경로의 동일 계산. 기존 비교 `reconcile`의 새 Run/사람 수정 거부는 유지. Core v2 정규화·B2 수치·읽기·AI·소스 캐시 선택 규칙 변경 없음.
- `SonioxJourneyTests`의 새3건+확장1건: 새 요청/무키 재사용, 프로세서 재생성·취소, 모델 저장 후 normalizing 복구, 필드 누락/명시 v2, 미지원 정책 및 불명 접수. 영향25건 PASS(`word-v4-targeted-final.log`). 기본값을 v2로 역뮤테이션하면 대상1건의5단정 FAIL(`word-v4-reverse-mutation.log`), 원 변경을 바이트 복원 후 최종 전수검사.
- 최종 `.build/check-logs/word-v4-final/run-20260913T095110Z-LrFLrU`: 계약30/Swift198/Debug/SKIP0 PASS, 계약 사본 byte-exact. 사전 공용 PCM 충돌·첫 targeted 홈 캐시 접근 실패 및 테스트의 누락 try 컴파일 실패 로그도 보존. 최종은 전용 캐시와 동일4단계로 검사했고 생략 없음. 기존 SDK target/AppIntents 경고·adhoc/linker-signed 유지.
- 실제 검증 CLI `.build/diagnostics/word-v4/VerifyManaged.swift`를 최종 Core/Audio/Managed object에 링크했다. `.build/diagnostics/word-v4/internal-selected`에는 B2의 정확한 두 source, `internal`에는 현재 전체 저장 이력 사본을 준비. 실제 보존 음성21분53.280초·6,016토큰 사용, 실패하는 transport를 주입하고 키는 빈 문자열. 모델/API 재호출·AI 전송 없이 `begin`→`loadModel`→`FolderLibraryStore.createScript`→새 actor 재열기→Markdown→normalizing 복구를 완주했다.
- 정확한 B2 입력 결과 Run `3AF57B39-5B35-4A88-8A80-D6F2E3B9AB34`, 전체 이력의 최신 재사용 결과 Run `4A4E7361-C180-46EE-BB03-FEE52E26FFC8`. 양쪽6016토큰/276읽기문단/미배정 lexical9, 각 같은 raw의 승인 비교 계산과 normalized 전 필드 동일. 원 B2의 normalized도 승인 계산과 동일. 결과 `result-exact.json`/`result-latest.json`, Markdown2개 및 명령 로그는 같은 ignored 진단/검사 폴더. 미배정·문단 수는 정확도 측정이 아니다.
- 현재 캐시는 더 최근 P2 `336E25CC-02C0-4A3A-B67B-26487CC9FACD`를 선택하며 B2 당시 P2는 `0F20720E-C464-4744-91B5-9BDC23EE0513`다. 첫 진단은 같은 source ID라는 가정 단정에서 실패했고, 두 입력 모집단을 분리해 검증했다. raw/요청 사본/source ID 보존 및 각 Run의 재개 결과 byte-equal, transport 호출0. 새 결과에는 사람 이름·본문·등록/삭제·AI/버전 이식 없음.
- 설치 전후 원본 Script7개와 기존 session 전체 파일+library-index173개, 다른 소유 문서7개 SHA256 불변. 사용자 폴더에 QA 결과를 추가하지 않았고 기존 v2/A/B/B2와 사람/AI 수정본을 유지했다. `preservation-before.json`/`source-before.json`/`delivery.json`에 모집단과 해시 보존.
- 이전 앱 백업 `.build/backups/DAMA-0.5.4-22-before-word-v4.app`, `.build/xcode/Build/Products/Debug/DAMA.app`를 `/Applications/DAMA.app`에 설치. binary/debug dylib/Info.plist byte-equal, CUA About **DAMA Version0.5.5(23)** 확인 및 기존 B2/등록 화자/사람 본문/AI 보정1 재열기 확인. 첫 종료는 저장 보호 안내로 취소됐고 정상 종료 재시도 후 교체, 강제 종료 없음. 실마이크/새 서버 응답/청취 정답/E1·E2/정상요금은 이번 검증 축 아님.
- 최종 branch `work/m0-fixture-review`; 이번 파일만 pathspec 로컬 커밋, 기존 타 소유 dirty7 보존. 운영 연결 완료, AI 구조 변경·Qwen 학습·다른 트랙 보류 유지.

### T-05 · 2026-09-13 부호·어절 진단 뒤 사용자 수정 승인

- 사용자 ‘수정하자’에 따라 직전 권고1·2 실행. 읽기에서 부호/공백은 독립 발화를 만들지 않고, 원문상 동일 미배정 어절 조각을 합친다. 앞뒤 화자가 다른00:27의 재귀속/AI 구조 변경은 수행하지 않는다.
- 신규 비교 `soniox-p2-word-v4`(B2)는 기존 B에 제한된 미배정 어절 꼬리의 단일 P2 근거 공유 추가. 쉼표/종결/줄바꿈/ASR label 전환/다른 P2 화자 근거를 넘지 않는다. null suffix 한 어절만 허용하고 정렬 score를 만들어내지 않음. 새 Run으로 원본 B/소스 보존, 운영 v2 승격 아님.
- 초기 설계 한도: anchor 종료→꼬리 시작0~500,000µs, 꼬리 첫 시작→마지막 끝0~500,000µs(각 경계 포함). 시간 원값 불변; 500ms/501ms 고정 경계 및 역뮤테이션으로 검증한다. 이 값은 정확도 실측 최적값이 아니다.
- [x] AC-10 기존 Scripts의 부호 독립 문단 제거·unknown 동일 어절 묶음, 사람 문단/이름/수동 경계 보호, 읽기/Markdown/저장 왕복 일관성.
- [x] AC-11 B2의19:21 꼬리 연결,00:27 unknown 어절 유지, 실제 화자 전환/무근거/동률/쉼표/ASR 전환/시간 한도 회귀. 전체 원토큰/시간/기존6개 파일 보존.
- [x] AC-12 계약/전체 회귀/Debug 및0.5.3(21) 설치·실행·두 예시 화면 확인. AI/외부 음성 호출 없음.
- HEAD2cb6576/branch/dirty7 재실측 일치. 같은 세션의 지침·커맨드·적용 규율 본문 재사용, 규율22개 설명 재탐색/수치 규율 본문 확인. 독립 Codex 직접 구현. 영향은 Core 읽기·문단 검증·비교 정책·합성 테스트·CLI·계약/진단/상태·앱 버전이다.

#### T-05 검증·전달 결과

- `ScriptReadingStructure`를 읽기와 문단 저장 검증에 공통 사용. 부호의 원 speaker/time이 lexical 경계·이름 수정 범위·재생 범위를 결정하지 않는다. 미배정 동일 어절은 null을 보존하며 묶는다. 사람 소유 원 ID 집합/원문/명시적 경계와 실제 lexical A→B→A를 보존. 화자 이름 조회는 speaker별 캐시로 인접 Turn마다 전체를 재탐색하지 않음.
- 새 비교 정책 `soniox-p2-word-v4`는 기존 v3를 보존하고 제한된 꼬리만 보완한다. B2 준비본은 `.build/diagnostics/soniox-p2-alignment/preview-r2/`, Run/파일 `F96D664D-1F1E-4D03-8B8B-E26C09B507A7`, 제목 ‘비교 B2 · 문단 보완’. 최종 코드로 재조정한 normalized가 준비본과 완전 일치. 입력8개/analysis.wav 해시는 manifest 참조. AI OFF, 새 네트워크/유료 호출 없음.
- 현행7개 전수: B 읽기294(v7)→279(v8), B2 276, A308, 최신v2 615, 이전v2 604, Soniox273, Pyannote324. 부호만 문단은7개 파일 모두0. B unknown lexical13→B2 9(전체 unknown23→17), 원 Soniox6,016토큰/원시간은 동일. 문단 수·미배정 수는 E1/E2 정확도 실측이 아니다.
- B2 예시: 00:27.030–00:27.150의 원3Turn을 한 미배정 어절로 읽고 다음00:27.510은 분리. 19:21.150 질문의 꼬리2lexical을 앞 P2 근거로 연결하고 물음표까지 한 문단으로 표시. lexical 종료19:21.930으로 읽기 범위를 정하며 부호의19:22.950까지 늘리지 않는다. 부호가 다음 P2 시작과5ms 겹친 것을 화자 근거로 사용하지 않음.
- 실제 데이터 검증 `.build/diagnostics/soniox-p2-alignment/VerifyReadingV8.swift`/`reading-v8-verification.json`: Script7개 validate, 표시 토큰 전체 순서/ID 보존, 최대 문단 각3개 총21개 메모리 편집·왕복/source fingerprint 불변, Markdown placeholder0. 추가 B2 Draft2020-12 schema PASS. 실제 원문은 ignored 산출물에만 저장.
- 합성 추가8개 및 기존 회귀: 문장부호/여는 괄호, 미배정 한 어절/공백, 이름 수정·AI 사람 보호 맥락, 실제 화자 전환, 시간 역행,500ms 포함/501ms 제외, 쉼표/줄바꿈/ASR 전환/다른 화자 끼어들기/무근거·동률 보존. 대상35개 PASS. 500,000→499,000µs 및 unknown 어절 연결 비활성의 역뮤테이션에서2개 검사/4단정 FAIL 후 원 코드 복원. 로그 `reading-v8-reverse-mutation.log`.
- golden은 normalized21개 모두 불변. 읽기2개(`invalid-zero-reversed-and-uncovered/combined`, `short-b-missing-punctuation/combined`)와 Markdown21개(버전/lexical 시간 범위/부호 표시)를 의도대로 갱신. 첫 통합 검사에서 구 golden 불일치와 공유 scratch의 signal10 종료가 있었고, 별도 scratch `reading-v8`에서 전체를 다시 실행해 **계약30/Swift189/Debug/SKIP0 PASS**. 최종 로그 `.build/check-logs/reading-v8-final/run-20260913T011119Z-n8xEzW`, 실패 로그 `reading-v8-integration` 보존. 테스트 생략 없음.
- `.build/check-logs/reading-v8-delivery-build.log` PASS, Debug/Release0.5.3(21), `CODE_SIGNING_ALLOWED=NO`/entitlements 없음 유지. 이전 앱 백업 `.build/backups/DAMA-0.5.2-20-before-reading-v8.app`. 설치 binary와 빌드 SHA256 일치, CUA About **DAMA Version 0.5.3 (21)** 확인. 전달 증거 `reading-v8-app-delivery.json`.
- `.build/diagnostics/soniox-p2-alignment/deliver-r2.py`: 준비본 schema/해시 및 기존6개/입력8개 확인 후 사용자 승인된 외부 폴더 쓰기로 B2 한 개 exclusive create. 현재 Scripts7개, 새 파일 준비본 일치/기존6개/입력8개 불변을 설치 및 최종 UI 확인 후 재검증. `delivery-r2-before.json`/`delivery-r2-result.json` 보존.
- CUA에서 기존 앱 정상 종료 후 교체·시작, B2 자동 선택, 스크롤바 AX 값0.018/0.871로 두 예시의 연결과 실제 앞뒤 화자 분리 스크린샷 확인. B2 19:21을 열어둠. 실제 원음 청취 정답/재생 음질 검증은 하지 않음. 운영 기본값 v2·AI 구조 기능·타 트랙 보류 유지. 이번 소유 파일만 로컬 커밋하며 기존 타 소유 dirty7는 보존, 원격 push 없음.

같은 Soniox 원문과 P2 응답을 사용한 비교본2개를 현재 앱에 제공한다. 미배정·분절 감소와 실제 화자 정확도를 구분해 사용자 청취 판정이 가능한 상태로 끝낸다.

### 2026-09-13 후속 승인: 읽기 문단

- 사용자가 `[음성 감지 / 전사 누락 의심]` 전부 제거 및 01:42.630–01:47.430, 02:39.030–02:39.870의 같은 화자 연결을 요청. 문장별 세분화 대신 Soniox 수준의 문단 수가 목표.
- `reading-v7`로 기존 파일의 화면/Markdown을 함께 변경한다. 누락 marker와 전사 없는 diarization은 읽기 경계를 만들지 않는다. 실제 텍스트 화자 전환·미배정·사람 문단/수동 경계는 유지. 원 normalized INV-06 장벽과 모델 원문·시간·이슈는 불변이다. 이 절이 이전 Follow-ups의 읽기 장벽 보류를 대체한다.
- T-04 영향: LibraryPresentation·ScriptParagraphEdit·회귀 테스트·읽기 계약·앱 버전0.5.2(20)·기존 상태 문서. HEAD5f26b08/branch 실측 일치, 타 소유 dirty7 보존. API/AI 호출 없이 로컬 원본6개로 전후 측정.
- [x] AC-07 누락 의심은 본문/Markdown 문단0개. 동일 화자의 완결 문장도 연결하며 실제 A→B→A 텍스트는 보존.
- [x] AC-08 사용자 두 시간대 연결 및 전체 전후 문단 수 실측. 토큰/시간/원본6개 해시 불변. 사람 문단 저장·왕복·이름/경계/unknown 보호 검증.
- [x] AC-09 backpressure PASS 및 앱0.5.2(20) 전달, 실제 실행 버전·화면 확인. 인식/화자 정확도 개선과 구분.

#### T-04 검증·전달 결과

- `reading-v7`: 누락 marker를 읽기 그룹에서 제외, 문장 종결과 전사 없는 화자 감지 장벽 제거. 종료 시각이 안쪽에 있는 부호도 합치고 재생 범위 min/max 사용. `ScriptParagraphEdit`는 숨긴 marker만 건너뛴 ID 집합을 저장 가능. 다른 speech를 건너뛰는 편집은 계속 거부.
- `.build/diagnostics/soniox-p2-alignment/ReadingContinuity.swift`를 변경 전/후 실제 Core에 링크해 `reading-before.json`/`reading-after.json` 측정. Script6개 validate, 동일 단어 ID 순서, 전체 원본 해시·source fingerprint6개 불변, 각 최대 문단3개(총18개)의 메모리 편집·왕복 PASS. 마지막 설치/화면 확인 후에도 원본6개 불변.
- **전체 표시 항목**: A727→349, B490→294, 최신 기존v2 1,279→1,062, Soniox439→273, Pyannote456→324, 이전v2 1,274→1,063. marker는 A/B/기존v2의72개, Pyannote20개 모두 본문0개. 실제 화자 미배정은 이번에 바꾸지 않아 구v2는 여전히 많음. B는 기존 Soniox439문단보다 적고, 같은 새 정책의 Soniox273문단과 가까움. 수를 맞추기 위한 화자 추정 없음.
- B 지적 구간: 01:42.630 시작4문단 → 01:42.630–01:47.550 단일 문단(원23토큰); 02:39.030 시작3문단 → 02:39.030–02:40.710 단일 문단(원12토큰). 사용자가 적은 마지막 시작 시점 이후의 원 토큰 종료까지 표시 범위에 포함.
- 기존 문장/누락 표시 검사 기대값을 최신 승인으로 갱신. normalized golden21개 해시는 모두 불변, reading golden 변경5개는 숨긴 marker/장벽 영향, Markdown21개는 reading 버전 메타데이터 및 같은 표시 변경. 실제 transcribed A→B→A/raw missing-B 보존 단정은 유지. 합성 source 문장 분할용 `endsSentence`는 변경 없이 보존.
- 최초 targeted는 남은 Soniox source helper 참조 누락으로 compile 실패 후 복구,27개 PASS. 전수의 구 읽기 기대값28단정 및 테스트 접근 지정 오류를 수정. 이후181개 중 AAC 실코덱1건만 sandbox 실패, 승인된 밖 실행 최종 **계약30/Swift181/Debug/SKIP0 PASS**. `.build/check-logs/reading-v7-final-approved/run-20260913T002322Z-QYjc98` 및 앞 실패 로그 보존. 검증된 제품 코드 이후에는 테스트/문서만 변경.
- 전달 빌드 `.build/check-logs/reading-v7-delivery-build-approved.log` PASS. 초기 전달 빌드의 홈 캐시 쓰기 sandbox 차단 후 정상 권한으로 재실행. `CODE_SIGNING_ALLOWED=NO`, entitlements 없음 유지. 기존 앱 백업 `.build/backups/DAMA-0.5.1-19-before-reading-v7.app`, 새 binary와 `/Applications/DAMA.app` SHA256 일치. Debug/Release 버전0.5.2(20) 함께 증가.
- CUA: 기존 앱 정상 종료→교체→Scripts A/B 표시→스크롤바 AX 값으로 두 예시 이동→화면/스크린샷 확인. B 02:39.030 단일 본문을 열어둠. About에 **DAMA Version 0.5.2 (20)** 실측. 스크롤 제스처 noWindowsAvailable는 AX 값 대체로 해소. 새 음성/유료 API/AI 호출 없음, 화자 정답·실제 원음 재생 품질은 이 표시 수정의 검증 축 아님.
- 최종 공유 트리에서 본 태스크 파일만 pathspec 커밋. 기존 타 소유 dirty7는 그대로 유지, main/원격 push 없음.

## 영향 범위

- 신규 Core `SonioxPrecisionReconciler`: v2 normalized 원본으로부터 명시적 새 Run과 정책별 알고리즘 생성. 기존 `SonioxPrecisionNormalizer`/ManagedProcessor 기본값 v2 유지.
- 신규 로컬 `scripts/CompareSonioxPrecision.swift`: 저장 Script와 입력 소스 검증 → 새 Run ID → 새 Script/정규화/원본 출처 manifest를 gitignored 출력 폴더에 생성. 외부 SDK/Keychain/API 호출 없음.
- 신규 Core 회귀 테스트, 운영 계약에 비교 정책 명시, 이 plan과 기존 진단/resume 갱신. 현재 앱0.5.1(19)에 데이터만 추가하므로 앱 바이너리/버전 변경 없음.
- 사용자 Scripts에는 새 UUID 파일2개만 추가. 원본/사람 수정/AI 이력/기존 Run 보존. 배치 전 준비 파일 검증·해시 확정, `.withoutOverwriting` 배치 및 기존 파일 비변경 검증.

## 수용 기준

- [x] AC-01 Soniox text/prefix/ordinal/token kind/원시간/ASR confidence/언어/asrSpeakerLabel byte-value 보존. 기존 v2 결과/기본값 불변. INV-01·02·08·09.
- [x] AC-02 A `soniox-p2-timeline-v3`: 양수 시간 최대 교집합, 정확한 동률/후보 없음 null. 0길이는 반열린 exclusive 구간의 유일한 포함 시점 후보. 겹말·경계 경고는 유지하되 일괄 null 금지. 닫는 문장부호는 앞 원문 발화에 붙임. 외부 설계 coverage0.60 제거는 비교 전용 사용자 승인.
- [x] AC-03 B `soniox-p2-word-v3`: A에 같은 어절 조각의 단일 P2 근거 공유를 추가. 여러 exclusive 화자/다른 화자 끼어들기/역행·누락 시간은 공동 배정 불가. 화자별 연속 원 Turn으로 구성해 P2 화자 전환을 중심으로 본문 분할. 원 토큰을 자르거나 새 텍스트/시간을 발명하지 않음.
- [x] AC-04 A→짧은 B→A 및 B 전사 누락 장벽, 동률·무근거·겹말·부호·0길이·한국어 부분 토큰·구간 경계·시간 역행 회귀. RC-01~06/INV-06. confidence map·정렬 score·사람 확인 분리. 오류/누락 의심 근거 재계산.
- [x] AC-05 실제 최신 저장 결합과 소스 해시 재검사, 두 비교본의 전체6,016토큰 보존/새 Run ID/전체 Script 및 export validate/원본 보존. 미배정/문단은 정답률로 표현하지 않음. AI 보정 OFF.
- [x] AC-06 검증된 비교본2개를 현재 Scripts에 추가, 실제 앱에서 A/B 선택·원문 표시·연결된 원음 재생 경로 확인. 현재 원본 파일 해시 비변경. 청취 정답/E1/E2/수정시간은 사용자 비교 단계로 표시. **경로와 WAV 일치 확인이며 실제 재생 성공은 미측정**(아래 QA 한계).

## 시간·수치 계약

- Soniox 원시간 ms→기존 normalized Int64 µs, P2 초→기존 µs 변환 재사용. 새 변환/오프셋/타임스탬프 수정 없음. 모든 구간 `[start,end)`.
- 최대 겹침 B800µs > A200µs이면 B, A500=B500이면 null. 1,000,000µs 경계는 앞 구간 제외/뒤 구간 포함. 면적이 없는0길이에는 coverage를 만들지 않음.
- 어절 공동 근거의 score를 개별 토큰 직접 coverage로 표시하지 않음. 참조 sourceIntervalIds는 직접 및 같은 어절/문장부호의 배정 근거를 포함.

## 작업 분해

| 작업 | 산출물 | 검증 |
|---|---|---|
| T-01 | Core 비교 정책2개·계약·합성 회귀 | 계약/Swift compile/pure tests, 기존 v2 단정 유지 |
| T-02 | 로컬 비교 생성기·실제 응답 비교본 | 같은 원문/시간·새 ID·schema/Script/내보내기, 원본 해시 |
| T-03 | Scripts 추가·현재 앱 소비 확인 | 목록/본문/A↔B/원음 연결, 원본 비변경 |

## 결정 항목

- 2026-09-13 T-05 후속 사용자 ‘오케이 이정도로 확정’으로 B2 결과 판정 승인. 이어 요청한 등록 화자/발화 삭제는 uiux-reading T-08에 구현·전달했다. 다음 새 전사 기본값 연결에서 B2 결과 선택을 재확인하지 않는다. 이 UI 작업이 ManagedProcessor 기본값을 변경한 것은 아니다.

- D-01 사용자 승인: 규칙 완화·두 후보 비교. 최대 교집합과 어절/부호 보완을 구현 판단으로 구체화. 근거 없는 최근접 화자/문맥 인물 추정 없음.
- D-02 사용자 결과 판정 전에는 운영 기본값 v2를 바꾸지 않는다. 이번 완료는 비교 가능한 결과 제공이며 정확도 승격이 아니다.

## Follow-ups

- T-01: 관련16개(신규9+기존v2/읽기7) PASS, `.build/check-logs/soniox-p2-alignment-core-retry.log`. 최초 manifest가 홈 캐시를 써서 sandbox 차단된 기록은 core.log에 보존; 환경 변수로 repo 캐시 지정 및 승인된 외부 실행으로 검사. 경계 시점 start포함을 의도적으로 제외하는 역뮤테이션에서 고정 검사1개 FAIL(단정1), 복원 후 PASS. 기존 v2 테스트 기대값 변경/삭제 없음.
- T-02/T-03 완료: `scripts/CompareSonioxPrecision.swift`를 DamaCore에 링크하여 실제 v2를 양쪽 raw에서 재구성해 완전 일치 검증 후 생성. `.build/diagnostics/soniox-p2-alignment/preview-r1/manifest.json`에 원본8개 해시·입력 Run·새 Run·산출물 해시. `.dama.json`2개, source 하위 raw/request/원본 snapshot/normalized/Markdown 보존. 최종 제목만 현재 앱에서 짧게 저장해 화면 겹침을 피했고 title/revisionID 외 변경 없음 검증. 생성기도 같은 짧은 제목으로 갱신/재컴파일.
- 측정(동일6,016토큰): 현재 미배정657/lexical412/발화문단1,207 → A71/44/655 → B23/13/418. 누락 의심 marker72는 두 후보 모두 유지. 문장부호만 있는 문단은 현재267/A74/B57로 아직 남음. `LibraryScript.validate`/codec/Markdown 및 Draft2020-12 JSON Schema2개 PASS. 정확도 청취 결과가 아님.
- 최종 backpressure 계약30/Swift179/Debug PASS, SKIP0. `.build/check-logs/soniox-p2-alignment-final/run-20260912T161755Z-QbezLo`; scratch `run-20260912T160116Z-OI0Nzz` 재사용. CLI 마지막 제목 변경은 해당 실행 파일 재컴파일과 앱 실제 제목 저장/동등성으로 검증했으며 전체 검사는 반복하지 않음.
- 현재 `/Users/gazitofu/DAMA/Scripts`에 A `84420BCA-5F8F-477C-B3B4-A438783056D5.dama.json`, B `870BD136-53B9-4D0E-828F-F092DF9AF306.dama.json`만 추가. 사전 원본Script4개 unchanged4, 입력8개 unchanged8, 후보2개 준비본=설치본. 배치 스크립트는 `.withoutOverwriting`에 해당하는 exclusive create와 사전/사후 해시를 사용했으며 작업 폴더 밖 추가 쓰기 권한 승인 후 실행.
- 실제 앱0.5.1(19)에서 목록 새로고침→A 본문→B 본문→제목 자동 저장→A/B 재선택 확인, 최종 B를 열어 전달. `sessionId`가 기존 분석 WAV를 가리키고 해시가 같음을 검증. **원음 듣기 AX 클릭은 AXError.failure, 좌표 대체는 noWindowsAvailable로 실제 재생 성공 미측정**. 앱 재생 결함으로 단정하지 않으며 청취 검증으로 산입하지 않음. 원문/음성/AI 외부 호출 및 키 접근 없음.
- 같은 엔진·같은 분 생성본은 현재 ‘다른 결과 보기’ 메뉴에 같은 표시가 나온다. 이번 비교는 서로 다른 제목이 보이는 Scripts 목록에서 A/B를 선택한다. 신규 UI 수정은 하지 않음.
- 사용자 원음 판정 후 채택 정책을 새 변환 기본값으로 연결. 필요하면 남은 lexical 시간 불일치에 별도 음성 정렬기를 비교.
- 부호만 남는 문단은 원시간 역행/다른 화자·누락 장벽/부호 종류별로 원인을 추가 확인할 보완 대상. 원음을 대조하지 않은 상태에서 장벽을 일괄 제거하거나 원시간을 고치지 않음.
- AI 문맥 후보정은 다음 단계. 원문/화자/시간/사람 수정 보존 및 녹음별 전송 확인 계약 유지.

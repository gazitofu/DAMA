---
unit: library-loading
branch: work/m0-fixture-review
status: built
decisions_resolved: true
resume: "게이트 ② 통과(사용자 2026-10-30 AC-05·AC-06 실화면 '둘 다 통과'). 다음은 /ship. QA 판정(GPT-6.1-sol) 미수행."
spec: "계약 유닛. 컨펌 출처 = ssot/design/00_README.md 하이브리드 채택(2026-09-09) + 사용자 2026-10-30 AskUserQuestion '근본 수정 먼저(Script 요약 디스크 저장·본문 지연 로딩·Speech가 Script를 기다리지 않음, 화면 변화 없음)'. 진단 notes/library-workspace/startup-loading-diagnosis.md"
---

## 근거

- 규율: rule-purpose-first · rule-ambiguous-instructions · rule-scope-stop · rule-gate-hygiene · rule-measurement · rule-negative-claims · rule-carryover-remeasure · rule-verify-at-consumption · rule-delegation-artifacts · rule-destructive-writes · rule-shared-tree-commits · rule-numeric-test-integrity · rule-external-media-verify · rule-longrun-watchdog (2026-10-30 본문 재독).
- `ssot/design/00_README.md` 하이브리드 채택, `ssot/dev.md`, `ssot/api/pyannote-verified.md`(이 유닛 무관, pyannote는 2026-10-30 사용자 결정으로 운영 제외), `ssot/contracts/library-script.md` §53–54(LibraryScriptFile 메모리 파생물, 새로고침 시 실제 bytes 해시 비교 후에만 재사용), `ssot/contracts/transcript.v1.schema.json`·`DomainContracts.swift`(LibraryScript는 계약 Swift 밖, 스키마 변경 없음).
- 사전 확인: branch `work/m0-fixture-review`, `main..HEAD` 84커밋·`HEAD..main` 0. 스킬 절차 `checkout main && -b work/library-loading`은 84커밋을 잃으므로 미적용, 이전 유닛 선례대로 현 브랜치 유지(공유 트리 브랜치 전환 금지). `git status`: 타 소유 수정 14파일(세션 시작 시점부터 존재) + untracked `ssot/api/nari-verified.md`, 이번 세션 untracked `notes/diarization-research/`, `notes/library-workspace/startup-loading-diagnosis.md`, `scripts/nemotron-probe/`(빌드 산출물은 `.build/nemotron-probe-build/`로 이동해 계약 링크 검사 오염 해소).
- check.sh 기준선: 계약 30 · 계약 파생물 byte-exact · Swift 6 SmokeCheck · swift test 213(Managed 36 / Core 148 / Audio 29) · xcodebuild Debug PASS, SKIP 0. `.build/check-logs/run-20261030T044440Z-lfODi2`.

## 의도

앱 첫 실행에서 Speech가 Script 전량 디코딩·검증(실측 6.70s)을 기다리지 않게 하고, Script 목록은 해시가 같은 파일에 한해 디스크 요약으로 즉시 표시한 뒤 본문은 열 때 읽는다. 검증기의 이차 비용(실측 4.13s)은 결과를 바꾸지 않고 선형화한다.

## 영향 범위 (현행 실측, 2026-10-30, 릴리스 빌드, 32 Script 227.3MB, 디스크 캐시 웜)

| 경로 | 현행 | 실측 |
|---|---|---|
| `Packages/DamaCore/Sources/DamaCore/TranscriptValidator.swift` `validateBarrier` | 인접 단어쌍마다 markers·interruptions compactMap + 전체 diarization 선형 탐색 | 전 32파일 TV 4.13s, 최악 파일(단어 52,437·턴 6,500·marker 1,356·regular 5,094) 2.67s |
| 같은 파일 `validateExclusive` | exclusive 전 쌍 O(E²) + 쌍마다 path 문자열 생성 | 최악 파일 exclusive 4,250 |
| `Packages/DamaCore/Sources/DamaAudio/FolderLibraryStore.swift` `scanScripts` | 매 실행 전 파일 read+SHA256+decode+validate+ScriptReadingSnapshot, 캐시는 메모리 | read 0.08 · hash 0.08 · decode 2.11 · validate 4.77 · reading 0.62 s, scanScripts 6.70 s, 재호출 0.09 s |
| 같은 파일 `scanSpeeches` | m4a/wav 전체 해시, 번들은 manifest 해시, 색인 일치 시 재사용 | 24개 전부 색인 일치, 0.24 s |
| `App/LibraryWorkspace.swift` `refresh()` | scanSpeeches → scanScripts 순차, 둘 다 끝날 때까지 `busy=true`, `canLeave`가 `!busy` 포함 | Speech 선택 포함 라이브러리 조작이 ~6.7 s 막힘 |
| 같은 파일 `convert()` | `scripts`가 완전하다는 전제. run readyForReview인데 Script 미발견 → `processingFinished` 재생성, run·Script 모두 미발견 → 새 전사 | 로딩 중 실행되면 중복 Script 또는 유료 재제출 위험 |
| `UI/LibraryShell.swift`·`UI/ScriptReadingView.swift`·`UI/SpeechDetailView.swift`·`App/ProcessingWorkspace.swift:215`·`App/DamaApp.swift:36` | 목록·메뉴가 `LibraryScriptFile.script` 전문 사용 | 목록 단계 사용 필드: id, url, hash, title, createdAt, transcript.sessionId, provenance.engine, provenance.sourceAudioSHA256 |

## 수용 기준

- [x] AC-01 검증기 동치: 새 `TranscriptValidator`와 현행 구현 사본(테스트 타깃 `ReferenceTranscriptValidator`, 이번 변경 직전 코드 그대로)의 결과(통과 또는 첫 오류 `code`+`path`)가 같다. 모집단: 기존 DamaCore 테스트 fixture 전부 + 결정적 시드 생성 문서 ≥200개(위반 포함) + 고정 변이 7종: ①gap 안 missingSpeech marker ②gap 안 capture_interrupted ③gap과 겹치는 다른 화자 regular 구간 ④같은 화자 구간(허용) ⑤접하는 구간 `[currentStart, x)`·`[y, previousEnd)`(위반 아님) ⑥exclusive 다른 화자 `[a,b)`·`[b,c)`(위반 아님) ⑦exclusive 1µs 겹침(위반, 같은 path). 단위: 내부 Int64 µs, 반열린 구간, `overlaps = max(start) < min(end)` 불변. 역뮤테이션 2종(새 barrier 질의 비활성, 새 exclusive 질의 비활성)에서 동치 테스트 FAIL 확인. INV-02·04·06.
- [x] AC-02 검증기 성능: 같은 Mac·릴리스·같은 32파일에서 TV 합계 ≤ 1.2 s(기준 4.13 s), 최악 파일 ≤ 0.3 s(기준 2.67 s). 측정 명령·출력을 `.build/check-logs/library-loading/`에 남긴다. 실제 32파일 모두 검증 통과 유지.
- [x] AC-03 요약 캐시: 내부 저장소 `library-script-summaries.json`(원자 쓰기, `summaryVersion` 포함)에 파일별 {standardized path, bytes SHA256, id, title, createdAt, sessionId, engine, sourceAudioSHA256}만 저장. 새로고침마다 모든 `.dama.json` bytes를 읽어 SHA256 비교(계약 §54 유지). path+hash+summaryVersion 일치 → 디코딩·검증 생략, 불일치·신규 → 현행대로 decode+validate 후 요약 갱신. 캐시 손상·누락·버전 불일치 → 빈 캐시로 간주, 전량 재구성. 중복 ID·손상 파일·symlink 이슈 처리 현행 동일(FileScanTests·LibraryJourneyTests 통과 유지). Scripts 폴더 파일 bytes 불변(스캔 전후 32파일 SHA256 동일). 실측: 캐시 적중 시 scanScripts ≤ 0.5 s(같은 32파일).
- [x] AC-04 본문 지연 로딩: Script 선택·열기·재전사·다른 결과 이동·내보내기·삭제 직전에 `loadScript(summary)`가 bytes 재해시 → 요약 hash와 다르면 `changedFile`(현행 stale 규칙)로 새로고침 유도, 같으면 decode+validate+ScriptReadingSnapshot. 저장 시 `expectedHash` 충돌 방어 현행 동일. 최대 파일(31.1MB) 열기 시간을 기록(기준 없음, 측정만).
- [x] AC-05 Speech 먼저·위험 차단: `refresh()`가 Speech 결과를 먼저 반영하고 Speech 목록·상세 선택을 Script 스캔과 독립으로 허용. Script 스캔 중(`scriptsLoading`)에는 변환·재전사·Script 삭제·'스크립트 열기/저장 다시 시도'·폴더 변경 비활성, `convert()` 진입 차단(새 전사 제출 0·Script 생성 0, 순수 판정 함수 단위 테스트). 상태 문구 신설 없음: Speech 상세의 변환 상태 두 줄 자리에 기존 문구 "불러오거나 저장하는 중"을 표시. INV-01(녹음 안전) 영향 없음.
- [x] AC-06 보존·전달: `ssot/contracts/library-script.md` §53–54 개정(영속 요약·지연 디코딩, 해시 비교 유지). 타 소유 hunk 바이트 보존, pathspec 커밋, `git diff --cached` 헝크 확인. check.sh PASS(계약 30, Swift 213+신규, Debug), SKIP 0. `MARKETING_VERSION`·`CURRENT_PROJECT_VERSION` 상향, 실행 중 Bundle 버전 확인. 실기기 여정: 콜드 실행 → Speech 선택 가능 시점·Script 목록 표시 시점 측정 → 최대 Script 열기 → 다른 결과 보기 → 앱 재시작 후 캐시 적중 확인.

## 작업 분해

- T-01 검증기 선형화 (`TranscriptValidator.swift`): markers·interruptions 시간 구간을 문서당 1회 정렬, regular diarization을 화자별 시작 정렬 + 접두 최대 끝 배열로 색인, 단어쌍 질의는 이진 탐색. exclusive는 시작 정렬 스윕으로 위반 존재만 판정하고, 위반이 있을 때만 현행 이중 루프로 첫 오류 path 산출. path 문자열은 실패 시에만 생성. 테스트: AC-01 동치·변이·역뮤테이션. AC-01·02.
- T-02 계약 개정 (`ssot/contracts/library-script.md` §53–54): 요약 필드·저장 위치·무효화 키·지연 디코딩·`changedFile` 처리. AC-06.
- T-03 요약 저장소 (`FolderLibraryStore`): `LibraryScriptSummary`(Codable, Sendable), `scanScripts` 요약 반환·캐시 적중/갱신, `loadScript(_:)`, `ScriptResultPresentation`을 요약 기반으로. 기존 메모리 `scriptCache`는 열린 전문용으로 유지. 테스트: 적중·불일치·손상 캐시·중복 ID·symlink·bytes 불변. AC-03·04.
- T-04 앱 연결 (`LibraryWorkspace`·`LibraryShell`·`ScriptReadingView`·`SpeechDetailView`·`ProcessingWorkspace`·`DamaApp`): `scripts`를 요약 목록으로, 선택 Script 전문 지연 로딩, Speech 먼저 반영, `scriptsLoading` 차단 판정. AC-04·05.
- T-05 검증·전달: check.sh, AC-02/03 실측, 버전 상향, 실기기 여정 1회, plan 갱신. AC-02·03·06.

## 실행 기록 (2026-10-30)

- 커밋: `017357e` plan · `0641b4d` T-01 검증기 · `a02dae6` T-02 계약 · `66ee6b3` T-03 요약 저장소 · `7b631ac` T-04 앱 연결. 타 소유 hunk(`App/LibraryWorkspace.swift` convert() 재전사 분기, `UI/SpeechDetailView.swift` 버튼 문구)는 HEAD+자기 변경만 인덱스에 올려 제외, 작업 트리에 그대로.
- AC-01: 동치 테스트 3건(고정 변이 7종·생성 문서 400개: 통과 70·barrier 285·exclusive 45) PASS. 역뮤테이션 barrier 무력화 109 FAIL, exclusive 무력화 48 FAIL, 복원 SHA256 일치.
- AC-02: `.build/check-logs/library-loading/ac02-validator-after.txt` 3회 TV 합계 0.47–0.48 s(기준 4.13), 최악 파일 0.08–0.09 s(기준 2.67). 32파일 전부 검증 통과.
- AC-03: `ac03-summary-timing.txt` 2회, scratch root(사용자 저장소 쓰기 없음). 캐시 적중 0.08–0.09 s, 빈 캐시 2.86–2.89 s, 기존 전체 스캔 3.24–3.28 s(검증기 개선 반영, 원 기준 6.70 s). Scripts bytes 전후 동일. 요약 캐시 테스트 8건 PASS, 역뮤테이션 3종(캐시 미사용 7 FAIL·해시 무시 3 FAIL·로드 해시 생략 1 FAIL) 검출, 복원 SHA256 일치.
- AC-04: 최대 파일(31.1MB, 단어 52,437) `loadScript` 0.46–0.47 s. 저장 병합이 열지 않은 Script를 디코딩하지 않음(테스트). 실기기 확인 대기.
- AC-05: 코드 경로 구현(`scriptsLoading` 차단: convert·재전사·Script 삭제·폴더 변경·변환 버튼, 상태 영역·Script 화면은 기존 문구, Speech 배지 숨김). 검증 방법 변경: 차단 조건이 `!scriptsLoading` 한 줄이라 판정 함수 단위 테스트는 실패 불가 검사가 되므로, 요약 캐시를 지워 로딩 구간을 늘린 실기기 확인으로 대체한다.
- 버전: `project.pbxproj` 0.5.10(28)→0.5.11(29). 0.5.10(28)은 타 소유 미커밋 상향이며 설치본도 0.5.10(28)이었다. 버전 상향은 0.5.10 선례대로 작업 트리에 두고 커밋하지 않는다(타 소유 hunk와 같은 줄).
- 설치(사용자 승인 2026-10-30): 실행 중 0.5.10(28)을 일반 종료, 백업 `.build/backups/DAMA-0.5.10-28-before-library-loading.app`, 기존 번들은 휴지통, 새 Debug 번들 설치. 실행 파일·Info.plist 빌드 산출물과 SHA256 동일, 실행 중 Bundle 0.5.11(29).
- 실앱 시작 측정(`ac06-launch-cpu-settle.txt`, 자 = `open`부터 프로세스 CPU 누적이 3 s 동안 멈춘 시점, 앱 기동·UI 포함 근사치, Debug 빌드): 0.5.10(28) 46.38 / 45.24 s, 0.5.11(29) 빈 캐시 5.24 s, 캐시 적중 1.64 / 1.78 s. 첫 실행 캐시 기록까지 5.51 s(`open` 기준). 측정 전후 Script 32개·`library-index.json` SHA256 동일.
- check.sh(마지막 코드 커밋 `7b631ac` 이후, 이후 변경은 plan.md뿐): `.build/check-logs/run-20261030T051011Z-SEEwfx` exit 0, SKIP 없음, 계약 30, swift test 224(Managed 36 / Core 151 / Audio 37, 기준 213), xcodebuild Debug PASS.
- 게이트 ② 실화면(사용자 승인 2026-10-30): DAMA 일반 종료 → 요약 캐시를 `.build/backups/library-script-summaries-20261030T052757Z.json`으로 이동(삭제 아님) → 0.5.11(29) 재실행. 캐시는 실행 후 6 s 안에 32건으로 재생성, 이전 캐시와 파싱 결과 동일(bytes SHA256은 다름, JSON 키 순서 비결정 추정). 사용자 확인: AC-05(로딩 중 Speech 선택 가능·기존 문구·변환/폴더 변경 비활성)와 AC-06 여정(최대 Script 열기·다른 결과 보기·재시작 후 목록 즉시 표시) 둘 다 통과.
- QA 판정 주체(GPT-6.1-sol) 부재로 QA 판정 미수행.

## 결정 항목

없음. 범위(요약 디스크 저장·지연 로딩·Speech 우선)는 사용자 2026-10-30 선택, 해시 비교 유지는 계약 §54, 상태 문구는 기존 문구 재사용으로 신설 없음. 검증기 선형화는 결과 동치 조건의 성능 수정이라 정책 변경이 아니다.

## 막힘

- QA 판정 주체: 전역 규칙상 GPT-6.1-sol(`gpt-6.1-sol`)이나 이 세션의 실행 가능 에이전트 목록에 없음. 테스트 실행·실측은 메인이 수행하고 QA 판정은 미수행으로 표시해 게이트 ②에서 사용자 확인. 구현은 repo CLAUDE.md 위임 절(메인이 Opus면 직접 구현).
- 실기기 콜드 실행 측정은 사용자 앱 실행 상태에 의존(디스크 캐시 콜드 재현 불가 시 웜으로 표시).

## Follow-ups

- `LibraryScript.validate()`의 검증기 외 부분이 32파일에 0.42–0.46 s(25.4MB Soniox 파일 0.33 s). 이번 범위 밖.
- 요약 캐시 JSON이 같은 내용이어도 bytes가 달라진다(키 순서 추정). 동작 영향 없음, 결정적 출력(`.sortedKeys`) 여부는 별도 판단.
- 전달 앱이 Debug 빌드다(이전 선례). 릴리스 빌드 전달 여부는 별도 판단.
- `project.pbxproj` 버전(0.5.10→0.5.11)은 타 소유 미커밋 상향과 같은 줄이라 작업 트리에만 있다.

- 녹음 분류(신규/기존/변환, 사용자 정의는 진단 문서) 화면은 별도 `/spec`.
- Nemotron-3 정식 도입은 별도 유닛(`/spec` 착수 예정).
- `scripts/validate_contracts.py`의 문서 탐색이 하위 `.build`를 제외하지 않는다(최상위만 제외). 이번엔 산출물 이동으로 회피, 수정은 별도 판단.

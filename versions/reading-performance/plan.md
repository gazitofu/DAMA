---
unit: reading-performance
branch: work/m0-fixture-review
status: built
decisions_resolved: true
resume: ""
spec: "사용자 2026-09-12 이어서 진행 승인; notes/backend-audit/audit.md F-03; ssot/design/02·04 및 ssot/contracts/library-script.md"
---

## 근거·의도

- 긴 Script를 재생·열기·수정할 때 반복되는 읽기 계산과 평가 export의 MainActor I/O를 제거한다. reading-v6/저장 schema/화자·문단·교정 정책은 유지한다. 하이브리드로 컨펌된 데이터·저장 계약의 최적화이며 화면 재설계는 없다.
- 홈/appdev/repo 지침, README, spec/plan/build 절차 및 공통10종·공유 트리·수치·외부 미디어·워치독·Apple 툴체인·리뷰 종료·인라인 스크립트 규율 본문 확인. 이전에 읽은 design02·03·04·api·dev·schema/Swift 계약은 재사용하고 이번 변경 관련 코드·library-script 계약을 재측정. Codex 직접 구현.
- 착수 HEAD9161d3f, branch 일치, 이전 유닛 built. 기존 dirty7(build 커맨드/README/Qwen evaluation/ssot dev/m0·m1·m2 plan)은 보존·커밋 제외. 승인된 브랜치 유지 예외를 이어받는다. 기존 계약30/전체152/Debug 통과 로그 확인; 기존 실패 scratch 재사용 없음.
- 실측: LibraryShell이 SegmentPlayback 전체를 관찰하고 body에서 blocks()/검수 사건을 계산. positionUs는 약30ms마다 publish하지만 현행 UI는 위치를 사용하지 않는다. exportEvaluation의 hash/evaluationData/write는 MainActor Task에서 실행된다.

## 범위·수용 기준

- [x] AC-01 FolderLibraryStore에서 검증한 파일 bytes와 SHA256을 묶고 불변 ScriptReadingSnapshot을 생성한다. 같은 URL/hash는 재사용, bytes가 바뀌면 revisionID가 같아도 재생성. 현재 목록 밖 cache는 정리하며 다른 Run/파일을 혼용하지 않는다.
- [x] AC-02 UI가 snapshot blocks/검수 사건을 소비하고 재생은 playingID/message 변경만 관찰한다. 위치 tick이 전체 LibraryShell 갱신을 유발하지 않는다. 문단 내용·시간·화자·이슈·순서는 기존 blocks()/Markdown과 동일 (INV-01·06·08·09).
- [x] AC-03 사람 대사/이름·수동 문단·AI 교정 병합·원문 보기·외부 변경/새로고침·재열기에서 최신 내용 반영. stale hash 저장·export 거부 유지. 캐시 재사용/무효화 검사는 깨뜨린 조건에서 실패 확인.
- [x] AC-04 평가 JSON의 검증·hash·encoding·write를 저장 actor로 이동. 월 비용은 클릭 시 snapshot, security scope는 await 종료까지 유지. 내부 경로·Script·Speech 덮어쓰기 차단, 실패 시 원본/기존 출력 보존을 합성 임시 파일로 검증.
- [x] AC-05 같은 실제 저장 Script를 사용해 최적화 빌드의 계산/재사용 비용을 동일 조건에서 기록하고 원본 hash·표시/Markdown 동일성 확인. 전체 테스트·계약·Debug 통과, 앱0.4.5(15) 로컬 전달 및 실제 긴 Script 열기/재생·편집창/내보내기 확인. 실마이크·AI 실행/정확도는 미측정으로 구분.

## 작업

- T-01 완료 `90cfb5c`: 저장 actor의 불변 읽기 결과/bytes cache, 최신 수정 반영 회귀 검사.
- T-02 완료 `a366e47`: UI 소비/재생 관찰 범위와 평가 export 연결, 영향 검사.
- T-03 완료: 동일 원본 비교·전체 검사·앱 QA·0.4.5(15) 전달·상태 기록.

## 검증 자·종료 조건

- 입력/내부 시간 Int64 µs, 표시 ms 절삭·재생 초 변환·30ms tick은 변경하지 않는다. 문단 계산 횟수/반복 조회 ms는 실행 조건과 반복 수를 함께 기록하고 실제 프레임 지연과 구분한다.
- 저장/재열기 검증은 합성 임시 파일에서 수정한다. 실제 사용자 Script8본/원응답/분석 음원은 읽기·재생·새 export에만 사용하며 사전/사후 hash manifest로 보존 검산한다.
- 위 AC 축 1회 검토 후 결함 영향 범위만 재검증하고 종료. 캐시가 검증·외부 변경 확인을 생략하지 않는지 확인한다. 파일별 손상 격리 F-04, 공통 normalizer F-06, 검사 스크립트 F-07, Qwen 학습/UI 시안은 별도 후속.
- 실제 앱 기존 버전 백업 후 동일 signing 방식으로 교체. 원격 push/새 API/음성 전송 없음.

## 검증 기록

- T-01 ReadingSnapshot2/LibraryJourney5/ContextAudio5, **12건 PASS** (`.build/check-logs/reading-performance-storage-approved.log`). 최초 검사는 manifest 홈 캐시 sandbox 거부로 실패, 승인된 외부 실행 사용. 같은 경로의 URL 표현 차이로 저장 직후 cache miss가 발생해 표준화 path 키로 수정; AI 이름 합성은 사람 이름 override가 없는 화자로 고쳐 우선순위와 분리했다.
- 해시 확인을 잠시 제거한 역뮤테이션은2건 중1건의5개 assertion에서 실패/예외0 (`reading-performance-cache-mutation.log`). 실제 코드 복원 후12건 재통과. 계약30 및 canonical Swift 사본12,200bytes 동일 확인. 실제 모델/API·마이크 실행 없음.
- T-02: UI는 불변 blocks/검수 사건/인원 집계와 playingID/message 구독을 사용. 평가 내보내기를 FolderLibraryStore로 이동하고 클릭 시 비용/보호 경로를 고정했다. 저장·교정·평가 영향 **13건 PASS** (`reading-performance-storage-approved.log`). 정상 export bytes/비용 동일, stale source/잘못된 비용/내부 경로/Script/Speech/symlink 차단과 기존 출력 보존 확인. 중간 실패는 테스트 JSON 키 순서의 비결정성으로, sortedKeys로 같은 전체 Turn 필드 검사를 유지했다 (`reading-performance-projection-order-failure.log`). 앱 컴파일·실물은 T-03에서 확인한다.

### T-03 최종 검증·전달 (2026-09-12)

- 전체 Core/Audio/Managed **155건 PASS, 실패0**, 독립 `.build/reading-performance-final` (12:18 KST, `.build/check-logs/reading-performance-final-tests.log`). 첫 `.build/reading-performance` 전체 실행은 signal11로 실패 (`reading-performance-all-tests.log`). crash의 실제 위치는 `URL.isFileURL → FolderLibraryStore.safe → trashScript → ManagedJourneyTests`였다. 새 scratch 성공만으로 원인을 캐시 손상이라고 확정하지 않는다. 실패 로그는 보존하며 F-07에 남긴다. `check.sh` 원본의 전체 통과로 표기하지 않는다.
- 계약 Python30/Swift 사본 동일 PASS, 최종 Debug 앱 **BUILD SUCCEEDED** (`reading-performance-contracts.log`, `reading-performance-app-build.log`). 승인된 sandbox 밖 Swift/Xcode 실행, 기존 deployment target/AppIntents 경고 유지. Release 버전만 함께 올렸으며 Release 컴파일·공증은 미측정.
- 계측 도구 `scripts/benchmark-reading.swift`: 동일 Soniox+P2 Run의 **1,274개 block/259개 사건**, cached/uncached 전체 표시 필드(원 Turn·시간·화자·이슈·텍스트·색·수정 표시) signature 동일. Core 전체 `-O`/Swift6에서 blocks 단회20회 중앙값 **77.45ms**, 행을 바꿔 조회하는 cached1,000회20표본 중앙값 **0.0071ms**. 전체 계산과 개별 조회의 서로 다른 작업량이며 UI 프레임 속도 개선율로 환산하지 않는다.
- 같은 Debug package/최적화 호출부에서 저장 Script8본의 새 actor 최초 조회·같은 actor 재조회5쌍 측정: 최초 중앙값 **1,844.98ms**, 재조회 **9.46ms**. 재조회는 실제 bytes hash를 매번 읽고8개 reading 객체 identity를 재사용한다. 최초 조회는 새 cache 기준이며 OS 디스크 cache를 비운 측정이 아니다. 이전 버전 cold scan과의 비교도 아니다. 파생물 보관만큼 메모리를 사용한다.
- 증거 `.build/diagnostics/reading-performance/{core-optimized-v2,store-debug-v2}.json`. 처음 count만 반복 읽은 지표는 최적화로 반복이 생략될 수 있어 채택하지 않았다. 실제 행 index를 바꾼 v2만 위 수치로 사용한다. 입력8본 해시와 두 컴파일 조건의 표시/Markdown signature 일치.
- 지표의 `medianMs`는 정렬한 samples[count/2]다. 20표본은 가운데 두 값 중 큰 값(11번째), 5표본은3번째를 사용한다. 최소·최대와 표본 수도 JSON에 함께 기록했다.
- 기존0.4.4(14) 정상 종료·백업 `.build/backups/DAMA-0.4.4-14-before-reading-performance.app` 후 **`/Applications/DAMA.app` 0.4.5(15)** 설치. 실제 About UI `DAMA Version 0.4.5 (15)` 확인. 설치/빌드 실행 파일·debug dylib byte-equal, adhoc/linker-signed 유지. 기존 dirty7 보존, 브랜치 유지·원격 push 없음.
- 실제21:53.280 Script 재열기·검수 기록1건/원음 확인0건·검수 사건259개 복원. 문단 원음 재생 시 정지 아이콘을 실화면에서 확인했고, 다중 Turn 편집창 열기/취소 확인. 실제 데이터에는 수정 저장하지 않았다. Markdown141,208bytes는 **0.4.4 출력과 byte-equal**. 새 평가 JSON7,800,498bytes의 embedded Script는 저장본과 전 필드 의미 동일, reading-v6 유지.
- 저장 후 CUA UI 조회가 시간 초과했다. Markdown은 Escape 후 완료 안내·화면 복귀까지 확인. 평가 JSON은 파일 저장/검산을 확인했으나 저장 완료 안내는 미확인. 12:28 KST PID86753 sample은0.4.5(15), 메인 스레드274/274표본이 이벤트 대기였다. 도구 시간 초과를 앱 정지로 단정하지 않았고 강제 종료하지 않았다. 재생 주변 sample은 활성 tick과 시간 정렬을 보장하지 않아 body 실행 횟수/FPS 근거로 사용하지 않는다.
- 최종 원본·수정본·원응답·분석 음원 **14파일 SHA256 불변**, 저장 Script8본 불변. ignored `verify-delivery.py`/`delivery-verification.json`에 설치/원본/실제 Markdown·평가 JSON 검산. 실제 마이크·새 모델 추론/API·청취 정답·한국어 정확도·FPS·능동 수정시간은 미측정.

## 다음 후속

- F-04/F-07은 2026-09-12 [storage-isolation](../storage-isolation/plan.md)에서 완료,0.4.6(16) 전달. 정상 파일 접근/영향 session 차단, 실행별 로그·독립 scratch를 검증했다. 실패 바이너리 단독 signal11 재현과 동일 코드 새 빌드 PASS로 범위를 좁혔으며 근본 원인은 미확정이다.
- F-06 공통 근거 계산, F-05 runtime 고정/학습, 화면 시안은 기존 순차 계획대로 별도 유닛.

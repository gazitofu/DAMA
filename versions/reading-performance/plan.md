---
unit: reading-performance
branch: work/m0-fixture-review
status: building
decisions_resolved: true
resume: "T-01/T-02 구현 및 저장·평가 영향13건 PASS. T-03 실제 저장본 계측·전체 테스트·앱 빌드/QA/0.4.5(15) 전달."
spec: "사용자 2026-09-12 이어서 진행 승인; notes/backend-audit/audit.md F-03; ssot/design/02·04 및 ssot/contracts/library-script.md"
---

## 근거·의도

- 긴 Script를 재생·열기·수정할 때 반복되는 읽기 계산과 평가 export의 MainActor I/O를 제거한다. reading-v6/저장 schema/화자·문단·교정 정책은 유지한다. 하이브리드로 컨펌된 데이터·저장 계약의 최적화이며 화면 재설계는 없다.
- 홈/appdev/repo 지침, README, spec/plan/build 절차 및 공통10종·공유 트리·수치·외부 미디어·워치독·Apple 툴체인·리뷰 종료·인라인 스크립트 규율 본문 확인. 이전에 읽은 design02·03·04·api·dev·schema/Swift 계약은 재사용하고 이번 변경 관련 코드·library-script 계약을 재측정. Codex 직접 구현.
- 착수 HEAD9161d3f, branch 일치, 이전 유닛 built. 기존 dirty7(build 커맨드/README/Qwen evaluation/ssot dev/m0·m1·m2 plan)은 보존·커밋 제외. 승인된 브랜치 유지 예외를 이어받는다. 기존 계약30/전체152/Debug 통과 로그 확인; 기존 실패 scratch 재사용 없음.
- 실측: LibraryShell이 SegmentPlayback 전체를 관찰하고 body에서 blocks()/검수 사건을 계산. positionUs는 약30ms마다 publish하지만 현행 UI는 위치를 사용하지 않는다. exportEvaluation의 hash/evaluationData/write는 MainActor Task에서 실행된다.

## 범위·수용 기준

- [x] AC-01 FolderLibraryStore에서 검증한 파일 bytes와 SHA256을 묶고 불변 ScriptReadingSnapshot을 생성한다. 같은 URL/hash는 재사용, bytes가 바뀌면 revisionID가 같아도 재생성. 현재 목록 밖 cache는 정리하며 다른 Run/파일을 혼용하지 않는다.
- [ ] AC-02 UI가 snapshot blocks/검수 사건을 소비하고 재생은 playingID/message 변경만 관찰한다. 위치 tick이 전체 LibraryShell 갱신을 유발하지 않는다. 문단 내용·시간·화자·이슈·순서는 기존 blocks()/Markdown과 동일 (INV-01·06·08·09).
- [x] AC-03 사람 대사/이름·수동 문단·AI 교정 병합·원문 보기·외부 변경/새로고침·재열기에서 최신 내용 반영. stale hash 저장·export 거부 유지. 캐시 재사용/무효화 검사는 깨뜨린 조건에서 실패 확인.
- [x] AC-04 평가 JSON의 검증·hash·encoding·write를 저장 actor로 이동. 월 비용은 클릭 시 snapshot, security scope는 await 종료까지 유지. 내부 경로·Script·Speech 덮어쓰기 차단, 실패 시 원본/기존 출력 보존을 합성 임시 파일로 검증.
- [ ] AC-05 같은 실제 저장 Script를 사용해 최적화 빌드의 계산/재사용 비용을 동일 조건에서 기록하고 원본 hash·표시/Markdown 동일성 확인. 전체 테스트·계약·Debug 통과, 앱0.4.5(15) 로컬 전달 및 실제 긴 Script 열기/재생·편집창/내보내기 확인. 실마이크·AI 실행/정확도는 미측정으로 구분.

## 작업

- T-01 저장 actor의 불변 읽기 결과/bytes cache, 최신 수정 반영 회귀 검사.
- T-02 UI 소비/재생 관찰 범위와 평가 export 연결, 영향 검사.
- T-03 동일 원본 비교·전체 검사·앱 QA·버전 전달·상태 기록.

## 검증 자·종료 조건

- 입력/내부 시간 Int64 µs, 표시 ms 절삭·재생 초 변환·30ms tick은 변경하지 않는다. 문단 계산 횟수/반복 조회 ms는 실행 조건과 반복 수를 함께 기록하고 실제 프레임 지연과 구분한다.
- 저장/재열기 검증은 합성 임시 파일에서 수정한다. 실제 사용자 Script8본/원응답/분석 음원은 읽기·재생·새 export에만 사용하며 사전/사후 hash manifest로 보존 검산한다.
- 위 AC 축 1회 검토 후 결함 영향 범위만 재검증하고 종료. 캐시가 검증·외부 변경 확인을 생략하지 않는지 확인한다. 파일별 손상 격리 F-04, 공통 normalizer F-06, 검사 스크립트 F-07, Qwen 학습/UI 시안은 별도 후속.
- 실제 앱 기존 버전 백업 후 동일 signing 방식으로 교체. 원격 push/새 API/음성 전송 없음.

## 검증 기록

- T-01 ReadingSnapshot2/LibraryJourney5/ContextAudio5, **12건 PASS** (`.build/check-logs/reading-performance-storage-approved.log`). 최초 검사는 manifest 홈 캐시 sandbox 거부로 실패, 승인된 외부 실행 사용. 같은 경로의 URL 표현 차이로 저장 직후 cache miss가 발생해 표준화 path 키로 수정; AI 이름 합성은 사람 이름 override가 없는 화자로 고쳐 우선순위와 분리했다.
- 해시 확인을 잠시 제거한 역뮤테이션은2건 중1건의5개 assertion에서 실패/예외0 (`reading-performance-cache-mutation.log`). 실제 코드 복원 후12건 재통과. 계약30 및 canonical Swift 사본12,200bytes 동일 확인. 실제 모델/API·마이크 실행 없음.
- T-02: UI는 불변 blocks/검수 사건/인원 집계와 playingID/message 구독을 사용. 평가 내보내기를 FolderLibraryStore로 이동하고 클릭 시 비용/보호 경로를 고정했다. 저장·교정·평가 영향 **13건 PASS** (`reading-performance-storage-approved.log`). 정상 export bytes/비용 동일, stale source/잘못된 비용/내부 경로/Script/Speech/symlink 차단과 기존 출력 보존 확인. 중간 실패는 테스트 JSON 키 순서의 비결정성으로, sortedKeys로 같은 전체 Turn 필드 검사를 유지했다 (`reading-performance-projection-order-failure.log`). 앱 컴파일·실물은 T-03에서 확인한다.

---
unit: backend-hardening
branch: work/m0-fixture-review
status: building
decisions_resolved: true
resume: "T-01 영향7건/T-02 영향29건 및 원응답 전후 비교 PASS. T-03 전체 새 scratch 테스트·앱 빌드/실물 QA/0.4.4(14) 전달 진행."
spec: "사용자 2026-09-11 이어서 진행 승인; notes/backend-audit/audit.md F-01/F-02; ssot/design/02·03·04 및 ssot/contracts/library-script.md"
---

## 근거·의도

- 백엔드 검수 후속 F-01/F-02 수정. 녹음 원본 저장을 우선하고 토큰 분리와 무관하게 공통 문장 종결을 판정한다. 컨펌된 계약의 결함 수정이며 화면 재설계는 포함하지 않는다.
- 홈·appdev·repo 지침, spec/plan/build 절차, 공통10종/공유 트리/수치/외부 미디어/워치독 규율과 Apple 툴체인·리뷰 종료·인라인 스크립트 규율 재사용. 규율 목록·설명을 새로 확인했다. Codex 직접 구현.
- 착수 HEAD21bf45f, branch 일치. 기존 dirty7은 이전 작업과 동일하며 보존·커밋 제외. README/ssot/dev/기존 세 트랙 plan/Qwen evaluation/build 커맨드 소유를 변경하지 않는다. 브랜치 유지 승인을 이어받는다.
- 이월 검증: 계약30/새 scratch 전체145/앱 Debug 통과, 기존 scratch signal11. 실패 scratch를 재사용하지 않고 이번 유닛 독립 scratch로 검증한다.

## 범위·정책

- T-01: AppLifecycle/RecordingWorkspace/ProcessingWorkspace, DamaAudio의 종료 순서·진입 가드, QwenRunner 취소 대기. 녹음 시작을 모델 정지 대기로 지연하지 않는다. 시작 직전 Qwen 취소 요청, 새 Qwen 시작/재개는 capture busy·미확정 저장·앱 종료 중 차단. 자동 재개·새 API 제출 없음. 종료는 녹음 저장 실패 여부와 관계없이 로컬 추론 정지를 기다리고, 저장 실패면 종료 거부.
- T-02: LibraryPresentation reading-v6, 관련 테스트/진단 도구/계약. 직전 Turn 대신 누적 표시 문장으로 종결 판정. 닫는 따옴표·연속 종결기호는 같은 안전 구간에서 붙이고 소수점·말줄임표와 구분. null/다른 화자/누락/시간 역행/표시 이름/사람 수동 경계 가드는 유지.
- 시간 입력/정규화 단위·숫자 임계값은 변경하지 않는다. 내부 Int64 µs, 반열린 구간. 기존 동일21:53.280 원음의3개 저장 Run을 읽기 비교에만 사용하고 원응답·모델·사람 수정본을 변경하지 않는다.
- T-03: 영향 여정 QA, Debug/Release0.4.4(14), 로컬 앱 전달·실행 버전 확인. 기존 앱 백업, 키/서명 identity 유지. 실제 API·새 회의 추론·학습·원격 push 없음.

## 수용 기준

- [x] AC-01 녹음 중/저장 미확정/종료 중 Qwen 시작·재개 차단과 녹음 시작의 기존 Qwen 취소 요청. 실행 provider를 선택 메뉴/과거 Run에서 추정하지 않음.
- [x] AC-02 저장 성공·실패 양쪽에서 로컬 종료를 기다림. 실제 합성 자식 프로세스의 SIGINT 무응답→강제종료 후 잔류 없음/체크포인트 보존, 시작 전 취소 검증. 마이크/실모델 사용 여부는 구분.
- [x] AC-03 분리 구두점 완성 문장·질문/닫는 기호, 소수점/말줄임표·한국어 미완성, A→B→A/누락/null/수동 분절 회귀. 원문/시간/화자/Turn 불변과 Markdown 동일 경계. 구버전에서 새 종결 회귀 실패 확인.
- [x] AC-04 같은3개 raw 재구성·읽기 전후 집계/변경 경계·입력 hash 불변. 과병합 수정과 미확정 과분절을 구분.
- [ ] AC-05 계약·영향 테스트·전체 새 scratch·앱 빌드 통과, 로컬 앱 실행/재열기·표시/내보내기 영향 여정 및 버전 확인. 미측정 축과 dirty7 보존 기록.

## 작업

- T-01 녹음 우선과 종료 안전성 구현/검증/커밋.
- T-02 누적 문장 종결 구현/동일 원음 비교/검증/커밋.
- T-03 여정 QA·버전 전달·상태 기록.

## Follow-ups

- F-03 읽기 snapshot/메인 I/O, F-04 손상 파일 격리, F-05 runtime bytes 고정, F-06 근거 계산 중복, F-07 검사 scratch 옵션은 별도 작은 단위다.
- null 화자를 합치는 표시 변경, Qwen 정렬 재실행·학습, UI/UX 시안은 이번 범위가 아니다.

## 검증 기록

- T-01: RecordingLifecycle2/QwenRunnerCancellation2/QwenJourney3, 합계7건 PASS (`.build/check-logs/backend-hardening-lifecycle.log`). SIGINT 무응답 합성 Python 자식의 실제 종료/체크포인트 bytes 보존 및 시작 전 취소 확인. 마이크·실모델·API는 사용하지 않음. 최초 sandbox는 manifest의 홈 모듈 캐시 쓰기가 차단돼 실패, 같은 명령을 승인된 외부 실행으로 검증했다.
- T-02: 새 ReadingTokenBoundaryTests3건을 구 reading-v5에서 실행해22개 assertion 실패/예외0 확인 (`backend-hardening-reading-red-valid.log`). 첫 합성 입력의 Double×0.2 부동소수 경계 초과는 µs 정수→초 변환으로 고쳐 정책 회귀와 분리했다. reading-v6에서 LibraryPresentation/Soniox/Qwen 관련29건 PASS (`backend-hardening-reading.log`). 계약30/사본/Swift roundtrip도 PASS.
- 전후 비교: 기준21bf45f와 현재 코드를 각각 최적화 컴파일해 같은 원음/원응답3본을 재구성. 양쪽 normalized가 저장 모델과 동일, 입력 hash manifest 동일, Turn/word/issue/수정 필드 보존. Soniox speech434→434·1초미만146→146, 결합1,123→1,202·886→937, Qwen1,013→1,013·415→415. 결합 자동 종결 경계79개 추가/기존 경계 삭제0, 다른2본 경계 변경0. 합성 구두점 분리 문장2문단, 실제 null 차단961/814 유지. 구두점만인 결합 문단272→273도 숨기지 않는다. 문장 종결 수정이지 분절 감소나 정답 판정이 아니다.
- 재현 증거: `.build/diagnostics/backend-hardening/{before-boundaries,after-boundaries,reading-comparison}.json` 및 `compare-reading.py`. sourcehash/변경 boundary ID는 ignored, 원문을 Git에 포함하지 않음. 진단 도구는 reading-v6 판정/구두점·소수점 예외와 실제 blocks를 대조하도록 갱신.

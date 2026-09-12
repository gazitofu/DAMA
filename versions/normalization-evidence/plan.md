---
unit: normalization-evidence
branch: work/m0-fixture-review
status: building
decisions_resolved: true
resume: "T-01 baseline 고정/영향17건 PASS. T-02 순수 P2 시간 근거 추출부터."
spec: "사용자 2026-09-12 이어서 요청; backend-audit F-06; design00 하이브리드 채택, design02·03·04 및 normalized/operating-baseline 계약"
---

## 근거·의도

- Qwen+P2와 Soniox+P2의 동일 시간 근거 계산을 내부 순수 함수로 추출한다. 경로별 토큰 해석·원문·화자 ID·경고 생성/순서·누락 marker·Turn 구성은 보존한다. Soniox 단독과 ManagedNormalizer는 대조군이며 자체 정책은 변경하지 않는다.
- 동일 세션에서 읽은 홈/appdev/repo, spec/plan/build, 공통10종·공유 트리·수치·미디어·워치독·Apple 툴체인·리뷰 종료·인라인 규율 본문 재사용. 착수 지침 mtime/규율 전체 목록·설명 재확인. measurement/정렬 규율, 관련 normalizer·테스트·진단 도구/채택 design00 재독. 직접 구현하며 하위 CLI 발주 없음.
- 착수 HEAD04cf64a, branch 일치. 이전 storage-isolation built/전체160·계약30·Debug PASS/설치0.4.6(16) 근거 확인. 타 소유 dirty7(build 커맨드/README/Qwen evaluation/dev/m0·m1·m2 plan) 보존·제외. 기존 branch 유지 예외 적용.

## 결정·범위

- 추출: P2 interval 변환, 반열린 시간 교집합, 서로 다른 화자의 동시 겹침, exclusive 화자별 합집합 점유율, 화자 경계 여부, lexical 단어가 나타내는 interval 근거.
- 초 Double ×1,000,000 반올림 → Int64 µs, 기존 검증식 유지. [0,100)과 [100,200)은 겹치지 않는다. 점수 B0.8이 A0.2보다 먼저, 동점 A0.5/B0.5면 speaker ID A가 B보다 먼저. 이 구체 쌍을 양쪽 경로가 읽는 합성 fixture에 고정한다.
- 0.60 coverage는 기존 초기 표시/배정 값이며 정확도 확률이 아니다. 버전 qwen-p2-v1/soniox-p2-v2/soniox-v1/managed-v1/reading-v6 유지. 임계값·schema·전송·학습·UI 재설계 변경 없음.
- nil/0길이 처리, Qwen 어절과 Soniox 구두점 eligibility, 원 ASR 후보와 provider_disagreement, warning/capture 이슈 순서는 각 호출부 소유. 단순 계산 추출로 정책을 통합하지 않는다.

## 수용 기준

- [ ] AC-01 수정 전 합성 공통 fixture의 세 경로 normalized 전체 필드/배열 순서 canonical SHA256 및 읽기/Markdown을 고정. overlap/boundary/점유율 union·동점/0.60·nil/0길이/역행·짧은 B·marker·confidence map·warning/중단을 포함한다(INV-01·06·08·09, RC-01~09·11~14). exclusive 자체 겹침처럼 전체 계약이 거부하는 입력은 순수 근거 함수의 별도 단위 검사로 검증한다.
- [ ] AC-02 추출 후 golden 동일, 틀린 시간/화자/이슈 및 marker 변형은 검사 실패, JSON 키 순서만 다른 대조는 통과. 기존 정규화·읽기 및 전체 회귀 유지. 새 측정 자의 자기 검증 포함.
- [ ] AC-03 같은 실제 Soniox 단독/결합/Qwen 저장 원응답3경로를 전후 재구성해 저장 모델과 canonical bytes 동일. 입력14파일 hash, 읽기 문단·순서·Markdown 내용 동일. 실행 시간은 정확도/속도 개선 수치로 환산하지 않는다.
- [ ] AC-04 전체/계약/Swift 왕복/Debug 빌드 통과. 0.4.7(17) 버전 동시 증가·기존 앱 백업·로컬 전달/실제 실행과 원래8Script 확인. 실마이크·추론/API·청취 정답·학습 미측정 구분.

## 작업

- T-01 완료: 합성 fixture/golden·실제 baseline·검사 자기 검증, 소스 변경 전 고정.
- T-02 공통 시간 근거 추출·경로 연결·동일성/회귀 검증.
- T-03 전체 검사·0.4.7(17) 전달·AC/상태 기록.

## 종료·후속

- AC 축 한 번 검토 후 결함 영향 범위만 재검증. 실제 저장 결과 덮어쓰기·새 전사/음성 전송·push 없음.
- 이후 UI/UX 시안은 operating-baseline 순서4의 화면 컨펌 절차, F-05 runtime 고정은 Mac-only 학습 선행. 과거 signal11은 storage-isolation의 미확정 근본 원인 기록 유지.

## 검증 기록

- T-01: 기존 normalizer 코드로 공통 합성7사례 × Soniox 단독/결합/Qwen = **21개 결과**의 normalized canonical bytes/전체 읽기 필드/Markdown SHA256을 `fixtures/normalization-goldens.synthetic.json`에 고정. 생성 도구는 새 출력만 허용하고 테스트는 기대값을 갱신하지 않는다. 안정된 session/run/시각/Script revision·timezone 사용.
- 영향 **17건 PASS** (15:10 KST, `.build/check-logs/normalization-evidence-baseline-tests.log`), 계약30 PASS. 같은 JSON의 키 순서만 바꾼 대조는 같은 지문, 시간1µs/모델 후보/이슈 severity/누락 marker 제거는 다른 지문임을 확인했다. Swift6 최적화 capture 컴파일은 repo cache 사용, SwiftPM은 승인된 sandbox 밖 실행. 초기 생성기 인자 순서 컴파일 오류는 수정/별도 로그 보존.
- 실제 baseline `.build/diagnostics/normalization-evidence/reading-before.json`: 저장 원응답3경로를 재구성해 기존 embedded normalized와 canonical bytes 일치, 동일P2·원음 및 입력14파일 SHA256 검증. diagnostic에 normalized/전체 읽기 필드/Markdown 지문을 추가했다. 원문은 Git이나 도구 stdout으로 내보내지 않는다.

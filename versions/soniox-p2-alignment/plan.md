---
unit: soniox-p2-alignment
branch: work/m0-fixture-review
status: ready-to-build
decisions_resolved: true
resume: "T-01: 기존 v2 기본값을 보존하고 명시적 비교용 timeline/word 정책을 구현한다. T-02 합성·실제 저장 응답 검증 후 T-03 현재 Scripts에 새 비교본2개만 추가해 기존 앱에서 확인한다."
spec: "사용자 2026-09-13 규칙 완화/결과 비교 승인, ssot/design/00·02·04 및 notes/uiux-reading/speaker-context-diagnosis.md"
---

## 근거

- 사용자: 규칙 완화 허용. Soniox 연속 원문을 P2로 분할하는 아이디어 판단, 권고안도 결과 확인 후 결정. 목적은 화자 구분 + Soniox 텍스트 품질이며 AI 문맥 후보정은 추후.
- 하이브리드 계약 유닛. UI는 게이트② 확인 완료이며 새 화면/재승인 없음. 비교본 생성과 검증까지 자율 승인, 운영 기본값 승격은 결과 확인 뒤 결정.
- 홈/Vault appdev/repo CLAUDE와 주입 AGENTS, README/Vault 인덱스, spec·plan·build 절차; 규율22종 설명 재탐색, 이전 로드 공통10/appdev2/미디어/워치독/정렬/Apple/인라인/리뷰종료 본문 재사용, 수치·공유트리 본문 재확인. 독립 Codex 직접 구현, 하위 위임 없음.
- design00·02·04·06, dev/API verified, DomainContracts/schema/operating-baseline/library-script 실측. 현재 App은 Script의 sessionId로 보존 analysis.wav를 재생하며 새 runId의 Script도 기존 UI에서 읽을 수 있음.
- HEAD3a9d529, 기존 dirty7(.claude/commands/build.md, README.md, notes/qwen-local/evaluation.md, ssot/dev.md, versions/m0·m1·m2 plan) 보존. 공유 트리이므로 브랜치 전환/타 소유 커밋 없음.
- 사전검사 PASS: `.build/check-logs/soniox-p2-alignment-baseline/run-20260912T160116Z-OI0Nzz`, 계약30/Swift170/Debug/SKIP0. 새 독립 scratch 동명.

## 의도

같은 Soniox 원문과 P2 응답을 사용한 비교본2개를 현재 앱에 제공한다. 미배정·분절 감소와 실제 화자 정확도를 구분해 사용자 청취 판정이 가능한 상태로 끝낸다.

## 영향 범위

- 신규 Core `SonioxPrecisionReconciler`: v2 normalized 원본으로부터 명시적 새 Run과 정책별 알고리즘 생성. 기존 `SonioxPrecisionNormalizer`/ManagedProcessor 기본값 v2 유지.
- 신규 로컬 `scripts/CompareSonioxPrecision.swift`: 저장 Script와 입력 소스 검증 → 새 Run ID → 새 Script/정규화/원본 출처 manifest를 gitignored 출력 폴더에 생성. 외부 SDK/Keychain/API 호출 없음.
- 신규 Core 회귀 테스트, 운영 계약에 비교 정책 명시, 이 plan과 기존 진단/resume 갱신. 현재 앱0.5.1(19)에 데이터만 추가하므로 앱 바이너리/버전 변경 없음.
- 사용자 Scripts에는 새 UUID 파일2개만 추가. 원본/사람 수정/AI 이력/기존 Run 보존. 배치 전 준비 파일 검증·해시 확정, `.withoutOverwriting` 배치 및 기존 파일 비변경 검증.

## 수용 기준

- [ ] AC-01 Soniox text/prefix/ordinal/token kind/원시간/ASR confidence/언어/asrSpeakerLabel byte-value 보존. 기존 v2 결과/기본값 불변. INV-01·02·08·09.
- [ ] AC-02 A `soniox-p2-timeline-v3`: 양수 시간 최대 교집합, 정확한 동률/후보 없음 null. 0길이는 반열린 exclusive 구간의 유일한 포함 시점 후보. 겹말·경계 경고는 유지하되 일괄 null 금지. 닫는 문장부호는 앞 원문 발화에 붙임. 외부 설계 coverage0.60 제거는 비교 전용 사용자 승인.
- [ ] AC-03 B `soniox-p2-word-v3`: A에 같은 어절 조각의 단일 P2 근거 공유를 추가. 여러 exclusive 화자/다른 화자 끼어들기/역행·누락 시간은 공동 배정 불가. 화자별 연속 원 Turn으로 구성해 P2 화자 전환을 중심으로 본문 분할. 원 토큰을 자르거나 새 텍스트/시간을 발명하지 않음.
- [ ] AC-04 A→짧은 B→A 및 B 전사 누락 장벽, 동률·무근거·겹말·부호·0길이·한국어 부분 토큰·구간 경계·시간 역행 회귀. RC-01~06/INV-06. confidence map·정렬 score·사람 확인 분리. 오류/누락 의심 근거 재계산.
- [ ] AC-05 실제 최신 저장 결합과 소스 해시 재검사, 두 비교본의 전체6,016토큰 보존/새 Run ID/전체 Script 및 export validate/원본 보존. 미배정/문단은 정답률로 표현하지 않음. AI 보정 OFF.
- [ ] AC-06 검증된 비교본2개를 현재 Scripts에 추가, 실제 앱에서 A/B 선택·원문 표시·연결된 원음 재생 경로 확인. 현재 원본 파일 해시 비변경. 청취 정답/E1/E2/수정시간은 사용자 비교 단계로 표시.

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

- D-01 사용자 승인: 규칙 완화·두 후보 비교. 최대 교집합과 어절/부호 보완을 구현 판단으로 구체화. 근거 없는 최근접 화자/문맥 인물 추정 없음.
- D-02 사용자 결과 판정 전에는 운영 기본값 v2를 바꾸지 않는다. 이번 완료는 비교 가능한 결과 제공이며 정확도 승격이 아니다.

## Follow-ups

- 사용자 원음 판정 후 채택 정책을 새 변환 기본값으로 연결. 필요하면 남은 lexical 시간 불일치에 별도 음성 정렬기를 비교.
- AI 문맥 후보정은 다음 단계. 원문/화자/시간/사람 수정 보존 및 녹음별 전송 확인 계약 유지.

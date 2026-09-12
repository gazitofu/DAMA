---
unit: soniox-p2-alignment
branch: work/m0-fixture-review
status: built
decisions_resolved: true
resume: ""
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

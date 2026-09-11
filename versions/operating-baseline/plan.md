---
unit: operating-baseline
branch: work/m0-fixture-review
status: built
decisions_resolved: true
resume: ""
spec: "사용자 최종 운영/실험 분리 및 평가 체계 반영 승인, ssot/design/02·03·04"
---

## 근거와 범위
- 사용자 최종안: 운영 Soniox+Precision-2, Soniox 자체 결과 보존, Qwen 선별 비교, 모델 중립 품질/능동 수정시간/정상요금 평가. 현재 0.3.0(9), Qwen built 및 0e90919 확인. 기존 Soniox 힌트/reading-v5/수동 경계는 완료 기능으로 재사용.
- ~/CLAUDE.md, ~/Vault/appdev/CLAUDE.md, repo CLAUDE.md·README, spec/plan/build 절차, ssot/design/00·02·03·04, ssot/dev·api·contracts 및 세션 공통/구현/측정/보존 규율 적용. 독립 Codex 직접 구현. 사용자 최종안의 기존 선택/검수 UI 확장과 운영 기본값을 승인 범위로 해석, 별도 전면 화면 설계 없음.
- 현재 브랜치 유지. 착수 시 혼합7문서(.claude/commands/build.md, README.md, ssot/dev.md, versions/m0·m1·m2 plan, notes/qwen-local/evaluation.md)는 보존·커밋 제외. 기존 다른 트랙 owner/status 변경 없음.
- 신규 외부 음성 전송 없이 저장된 동일 음성의 Soniox/P2로 실제 결합 검증. 외부 기준 TIRO/클로바 실제 실행, 새 회의 수집, 계정 혜택/청구서 수집, Qwen 학습은 이 단계에서 수행하지 않는다. 운영·승격 정책 및 측정 수단은 구현한다.

## 수용 기준
- [x] AC-01 운영 기본 선택 Soniox+Precision-2. 요청별 두 공급자·재사용·AI OFF 표시. Qwen/통합 STT는 선택 비교로 유지.
- [x] AC-02 Soniox 독립 Run과 P2 전사 OFF Run을 한 번씩 요청/재사용하고 별도 결합 Run 생성. 원응답/입력/모델/해시/참조 Run/결합 버전 보존. 중단/불명 접수는 자동 재제출 없음, 완료 소스 보존 및 열기.
- [x] AC-03 토큰 시간으로 P2 배정, 원 Soniox 후보 보존, 안정 구간/경계/겹말/누락/미정렬 구분. 후보 화자 ID 전체 치환 금지. null 유지 및 A→B→A 장벽, 단어 원문/시간 불변 테스트.
- [x] AC-04 관련 검수 사건 묶음/원음 재생과 동일 음성 결과 비교 연결. 사용자 수정 전후/범위/원음 확인 여부/오류 분류/능동 시간/표본 유형을 저장, 원음 확인 안 된 것을 정답/학습 데이터로 승격하지 않음.
- [x] AC-05 운영/실험/승격 정책·정상요금/실청구 분리·고정비/크레딧 산식·미측정 상태 기록 및 평가 내보내기. 무료기간·수정시간20%·8~12회의 가정/후속 실행을 완료로 표시하지 않음.
- [x] AC-06 영향 테스트/계약/앱 빌드, 실제 저장 소스의 결합과 원문 해시 보존, 앱 설치/선택/비교/검수 저장/재열기. 품질 정답 미측정 분리. 전달 버전0.4.3(13).

## 작업
- T-01 공통 결합기/Managed 복합 작업/소스 재사용/실패 복구
- T-02 운영 기본 UI/두 결과 보존 및 비교/검수 이력·측정
- T-03 가격·모델중립 평가 정책/내보내기/실제 로컬 결합/앱 전달

## 시간·증거 계약
- 입력 Soniox ms, P2 s; 내부 Int64 µs, 반열린 구간. 기존 Qwen/P2 0.60 coverage는 초기값으로 유지하되 다른 화자 경계는 보류. 확률/정답으로 표현하지 않음.
- 0길이 토큰은 원시간 보존+미확정. 읽기 묶음이 원시간/화자를 생성하지 않음. 공급자 간 라벨 일치는 인물 동일성이 아니며 시간 중첩 대응은 검수 후보 생성에만 사용.
- 비용 USD/월과 사용량 USD를 분리. 포함 크레딧은 구독료를 없애지 않음. 미입력 청구액·능동 시간은 0이 아닌 미측정. 관측 정확도는 원음 검수 표본에만 적용.

## 검증 결과 (2026-09-11)

- T-01 Core/managed/계약 `68f32a6`, T-02 앱 기본값/검수·비용 UI `fc8b1be`. 후속 source evidence 보존 검증은 아래 마무리 커밋에 포함.
- 계약 Python30건 PASS (`.build/check-logs/operating-contracts.log`), Swift canonical/사본 byte-exact PASS, check.sh 계약 compile/roundtrip PASS.
- 전체 Core·Audio·Managed143건 PASS: 샌드박스 밖 새 `.build/operating-clean`, 로그 `.build/check-logs/operating-clean-tests.log`. 첫 sandbox 시도는 macOS AAC 제한, 기존 `.build/swiftpm` 재사용은 signal11로 중단. 실패 로그를 PASS로 취급하지 않으며 새 scratch 전체 실행으로 해소했다.
- 이후 경고 지역화·듣기 묶음·읽기 조회 최적화: Soniox/ScriptEvaluation/LibraryPresentation 영향29건 PASS (`operating-events-tests.log`, 최종 `operating-reading-tests.log`). 새로운 전환 경고 테스트1건 포함, 같은 tests를 별도 정확도 표본으로 세지 않는다.
- 앱 Debug 최종 컴파일 PASS (`.build/check-logs/operating-final-build.log`), 서명 identity는 기존 adhoc/linker-signed 그대로. 기존 SDK deployment target/AppIntents 경고는 유지한다. 녹음/실시간 모델 성능·공증·다른 Mac 호환성 검증 아님.

### 실제 저장 음성의 로컬 재구성

- 21분53.280초 동일 분석 WAV의 Soniox 기본 문맥+3명 힌트(폴더 미포함)와 기존 Precision-2 numSpeakers3 결과 사용. 앱 확인창에서 양쪽 source 재사용 ID를 확인하고 키 읽기/신규 업로드/과금 POST 없이 결합했다. 외부 호출 테스트는 합성 mock이며 이 단계 실제 API 호출0건.
- 최종 `soniox-p2-v2` Run `DF6F46D1-D574-4493-8CA9-C7289F94EB92`, 실제 Script `~/DAMA/Scripts/8DBB4AE2-B250-43BD-86CE-8FAB4ACB2233.dama.json`. 이전 v1 개발 결합본·기존 Soniox/Qwen/pyannote 결과도 보존했다.
- 6,008개 원 Soniox 토큰의 문자열·prefix·순서·시간·ASR confidence·언어·timingOrigin·tokenKind가 source와 전부 동일. 양쪽 raw 파일 byte-equal, 새 결합 Run에 신규 API request/upload 파일 없음. source Run ID와 요청 사본이 정상 기록됨.
- Soniox 단독 감지2명, 결합 감지3명. 결합 미확정 token662, 누락 의심 marker72, local 전환 불일치37건. 검수 raw issue1,580개를 듣기 사건259개로 표시. 경고 지역화는 원 후보를 지우거나 정확도가 좋아졌다는 의미가 아니다.

| 같은 원음 결과 | speech 읽기 문단 | 1초 미만 speech 문단 |
|---|---:|---:|
| Soniox 자체 | 434 | 146 |
| Soniox + P2 | 1,123 | 886 |

**결합본의 짧은 문단은 증가했다.** 시간 경계·미확정 토큰을 안전하게 남긴 결과이며 ‘분절 감소’ 또는 ‘화자 정확도 향상’으로 보고하지 않는다. 불확실한 화자를 추정해서 합치지 않았다. 이 운영 구성의 품질 승격 여부는 원음 기반 E1/E2·짧은 응답·의미·수정시간 검수가 필요하다.

- 실제 읽기 조회 최적화: 결합본 blocks() 13.792초 → 0.444초 (이 Mac Debug 단회 측정). Soniox4본+결합1본의 모든 문단 Turn ID/표시 이름/텍스트/이슈 ID 배열을 수정 전후 byte-exact 비교 PASS. 알고리즘/문단 정책 변경 없이 조회만 최적화했다. 97분·다른 Mac 성능으로 외삽하지 않는다. 증거 `.build/diagnostics/operating-baseline/{reading-before,reading-after}.txt`, before/after JSON.

### 앱 여정

- 기본 선택 Soniox+Precision-2, AI OFF, 기본 문맥 ON/폴더 OFF; 기존 공통 입력·키 설정 보존.
- 실제 Soniox 단독↔결합본 메뉴 전환 및 재열기 PASS. 검수 사건 펼치기/원음 재생 명령에서 오류 없음. 사람의 원음 청취·정답 판정은 수행하지 않았다.
- 검수 타이머 시작/정지/취소 확인; 취소한 시간은 저장 안 됨. 최종 결합본에 `[동작 확인]` 메모1건만 저장/재열기/평가 JSON 확인. 원음 확인false·시간nil·오류미분류이며 원 텍스트·이름 override0건. 이 메모는 정확도/수정시간 데이터가 아니다.
- 비용 UI에 가정19/19/13.2/9.75/0 입력 시28.75 표시 PASS; 취소해 실제 금액/계정 조건은 nil 유지. 해당 가정을 계정 요금으로 저장하지 않았다.
- 실제 `평가 내보내기` 성공: `.build/diagnostics/operating-baseline/DAMA-evaluation-DF6F46D1-D574-4493-8CA9-C7289F94EB92.json`. source IDs, 불명 비용/시간, 원문/검수 기록을 파일로 재검증 PASS. 개인 원문이 있는 산출물은 ignored, Git에 포함 안 함.
- 0.4.1의 느린 UI가 종료 응답을 주지 않아 검증 세션 소유 PID13357을 SIGTERM 후 성능 수정본 설치. 녹음/편집 없음, source·완료 결과는 보존됨. 0.4.2에서 Scripts 열기·검수창 동작·재열기·내보내기 및 About 버전 확인 PASS. 최종 source evidence 저장 거부 검증을 0.4.3(13)에 추가.

## 후속 평가 (이번 완료 범위와 구분)

- 새 회의8~12개와 TIRO/클로바 동일 원음 기준 비교, 원음 검수표본/시간 축적, 실제 계정 정상 요금/무료 종료일·포함량 입력은 아직 미수행.
- Qwen은 기존 전사/비교 완료 상태를 이어받고 새 학습/추가 전사를 실행하지 않았다. 먼저 정렬·누락 병목을 분리하고 새 회의에서 문맥 효과를 재현한다. 자동 모델 승격 없음.
- 자동 월 청구 수집·원음1시간당 완성 수정시간 자동 집계·다중 오류 정답 판정·학습 데이터 자동 추출/학습·자동 후보 채택은 제공하지 않는다. 기록/JSON으로 같은 검수 구간과 측정 범위를 맞춰 평가한다.
- 결합 요청의 진행 카드 세부 단계는 parent 중심이며 자식의 상세 진행률은 Run별 state에 보존한다. 완료 source 복구/비교는 제공한다.
- 로컬 built 단계다. main merge/release/push는 이번에 실행하지 않는다. 기존 혼합7문서는 계속 보존한다.

### 최종 전달·상태

- source 후보/ASR confidence/언어를 revision으로 변조하는 저장 거부 검사 추가. FileSessionRepository20건 PASS (`.build/check-logs/operating-source-preservation.log`). 기존 전체143건과 이후 추가2건/해당 영향 범위 검사를 구분해 기록한다.
- `/Applications/DAMA.app` **0.4.3(13)** 최종 설치. 실제 About UI에 `DAMA Version 0.4.3 (13)` 확인, 최신 결합본 재열기·검수 메모1건·감지3명·사건259개 복원 확인. 설치/빌드 실행 파일 및 debug dylib byte-equal. 0.3.0(9) 백업은 `.build/backups/` 보존.
- 마지막 코드 변경 이후 추가 전사/모델 실행/원음 수정 없음. 품질·비용 목표 달성이 아니라 운영/비교/기록 기능 built다.
- 마지막 status 실측: `work/m0-fixture-review`, 사용자/다른 트랙 혼합7문서만 기존 변경으로 남긴다. 앱 코드·신규 계약·본 plan은 이 작업 커밋에 포함. 원격 push 없음.

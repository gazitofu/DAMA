---
unit: backend-audit
branch: work/m0-fixture-review
status: built
decisions_resolved: true
resume: "검수·분절 진단 및 F-01/F-02/F-03/F-04/F-06/F-07 완료. versions/normalization-evidence/plan.md 및 이전 후속 유닛 참조. 최신 전달0.4.7(17). 다음은 operating-baseline 순서4의 UI/UX 실물 여정·시안 /spec. F-05는 Mac-only 학습 선행, UI 재설계/학습 미착수."
spec: "사용자 2026-09-11 재개 요청; versions/operating-baseline/plan.md 다음 세션 착수 1·2; ssot/design/02·03·04 및 ssot/contracts"
---

## 근거와 의도

- 읽은 기준: ~/CLAUDE.md, ~/Vault/appdev/CLAUDE.md, repo CLAUDE.md·README, Vault Dama _index, spec/plan/build 절차, operating-baseline plan·계약, 사용자 Qwen 학습 지침 전체. 계약 하이브리드 채택과 이번 진단 요청을 입력으로 한다.
- 규율: spec 필수 공통10종·공유 트리·수치·외부 미디어·워치독, 전수 목록에서 추가한 리뷰 종료·Apple 툴체인·인라인 스크립트·정렬 방향. 독립 Codex 직접 수행.
- 착수 실측 HEAD fb08330, branch work/m0-fixture-review. 기존 dirty7(.claude/commands/build.md, README.md, ssot/dev.md, versions/m0-fixture-review/plan.md, versions/m1-recording-safety/plan.md, versions/m2-managed-processing/plan.md, notes/qwen-local/evaluation.md)는 이월 기록과 동일하며 수정·스테이징하지 않는다. 기존 operating-baseline built 유지.
- 용도: 다음 소규모 수정의 순서·책임 경계를 결정하는 코드 검수와 분절 원인 계측. 앱 재설계·모델 학습·새 전사·배포는 포함하지 않는다.

## 검수 축과 종료 조건

- 모집단: App/·UI/ 처리/저장 연결, Packages/DamaCore의 세 모듈·테스트·Package.swift, scripts/ 실행/검증/배포 연결, ssot/contracts와 채택 설계02·03·04. 순수 시각 자산 생성 스크립트는 배포 연결만 확인한다.
- 축: 데이터 흐름·책임/상태 소유, 중복, 메인 스레드, 파일 I/O/캐시, 취소·재개·실패, 키·로그·개인정보, 원문·시간·화자·수정 이력 보존, 안내 문서 드리프트.
- 종료: 모집단별 검수 근거와 결함 영향·우선순위·회귀 위험을 기록하고 세 경로의 분절 이유를 같은 정의로 측정하면 닫는다. 새 추측 축은 Follow-ups로 분리한다. 무결·화자 정확도 검증으로 승격하지 않는다.
- 시간: Soniox ms·P2/Qwen s → Int64 µs, 반열린 구간. 1초 미만 문단은 speech block의 endUs-startUs < 1,000,000. 원응답·원음·사람 수정본에 쓰지 않고 ignored 로컬 파생물로 재구성한다.

## 수용 기준

- [x] AC-01 파일별 모집단·검수 근거·데이터 흐름·유지/변경 책임 경계·우선순위 기록.
- [x] AC-02 같은 저장 원응답의 Soniox 단독·결합·Qwen+P2 재구성. ASR→정렬→배정→Turn→문단→화면/내보내기 단계별 분절 원인 및 원본 해시 확인.
- [x] AC-03 known-speaker 미완성 연속 발화 병합과 A→짧은 B→A/누락·null·수동 경계 보존을 현행 코드로 회귀 검증. 새 진단 계측은 양성·음성 대조와 실제 blocks() 출력으로 검산.
- [x] AC-04 검수 결과·한계·다음 수정 순서 기록, 기존 dirty7 보존 확인. 앱/운영 알고리즘 변경·새 외부 호출 없음.

## 작업

- T-01 완료: 모집단·호출 경로 고정 및 백엔드 검수.
- T-02 완료: 공통 문단 분절 진단 도구·저장 응답 재구성·영향 회귀 검사.
- T-03 완료: 결과 통합 및 후속 수정 순서 확정.

## 결과 (2026-09-11)

- [검수 결과](../../notes/backend-audit/audit.md), [파일별 모집단82개](../../notes/backend-audit/inventory.md). 정적 발견·합성 재현·실제 저장 응답 계측·미검증을 구분한다.
- 동일21:53.280 원음의 Soniox/결합/Qwen을 원응답으로 재구성해 저장 모델과 동일함을 확인. speech 문단434/1,123/1,013, 1초 미만146/886/415. 결합662/Qwen566의 null 화자가 주요 차단 원인. Qwen null시간336개는 저장 정렬의0길이에서 발생.
- 분리된 종결 구두점의 과병합을 합성으로 재현. 같은 화자 미완성 병합·ABA/누락/수동 경계 보존도 검증. 실제 결합84개 누적 종결 후보는 사람 판정 전이다.
- 기존 scratch의 check.sh는 signal11로 FAIL. 계약30/사본/roundtrip/앱 Debug는 PASS, 새 scratch 전체145건 PASS, Python worker4건 PASS. 재현 명령·실패 로그·한계는 결과 문서 참조.
- built는 검수·진단 산출물 완료를 뜻한다. 앱 결함 수정/설치·품질 승격·UI 시안·Qwen 학습 완료가 아니다. 운영 유닛/타 트랙 상태와 dirty7을 보존했다.

## Follow-ups

- 2026-09-12: F-06은 [normalization-evidence](../normalization-evidence/plan.md)에서 완료,0.4.7(17) 전달. P2 순수 시간 근거만 공통화하고 경로별 정책·알고리즘 버전 유지. 수정 전 합성21개/실제3경로 normalized·읽기·Markdown 동일, 입력14파일 불변, 전체165/계약30/Debug PASS. 다음은 operating-baseline 순서4의 UI/UX 실물 여정 및 /spec 화면 확인이며 F-05 runtime 고정은 Mac-only 학습 선행으로 유지한다.
- 2026-09-12: F-04/F-07은 [storage-isolation](../storage-isolation/plan.md)에서 완료,0.4.6(16) 전달. 파일별 오류/정상 목록과 영향 session 제출 차단, 전체160/계약30/Debug PASS, 실제 합성 폴더 오류 표시·원래8Script 복원/14파일 보존 확인. 실패 바이너리의 단일 테스트 signal11 재현과 같은 코드 독립 빌드 PASS를 구분하며 근본 원인 미확정 유지.
- 2026-09-12: F-03은 [reading-performance](../reading-performance/plan.md)에서 완료,0.4.5(15) 로컬 전달. 동일 표시/실제 Markdown bytes 보존, 전체155건 PASS. 첫 전체 실행 signal11과 저장 뒤 CUA 시간 초과의 한계도 해당 plan에 기록했다.
- 2026-09-12: F-01 녹음/추론 종료 안전성 및 F-02 공통 누적 문장 종결은 [backend-hardening](../backend-hardening/plan.md)에서 완료, DAMA0.4.4(14) 로컬 전달. 전체152건 PASS, 같은 원응답 보존 및 실제 Markdown 내보내기 검증. 본 문서의 2026-09-11 수치는 수정 전 진단 기록으로 유지한다.
- 진단에서 확인한 결함 수정은 아래 결과를 입력으로 별도 작은 구현 단위로 진행한다.
- UI/UX 시안은 /spec 화면 확인 후. Qwen 학습은 Mac-only 독립 유닛이며 이번 착수 대상이 아니다.

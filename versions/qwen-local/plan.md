---
unit: qwen-local
branch: work/m0-fixture-review
status: built
decisions_resolved: true
created: 2026-09-11
resume: ""
spec: "사용자 2026-09-11 Qwen 비교 구현 승인 + ssot/design/02·03·04"
---

## 근거·범위
- 사용자 제공 구성 승인: Qwen3-ASR-1.7B + Qwen3-ForcedAligner-0.6B 로컬, Precision-2 전체 음성/기존 결과 재사용. 기본 엔진 유지, AI 교정 OFF, 기존 선택 UI 확장. 최초 Python/MLX 프로세스 경로.
- ~/CLAUDE.md, ~/Vault/appdev/CLAUDE.md, repo CLAUDE.md, .claude/commands/spec·plan·build, ssot/design/00·04, ssot/contracts, ssot/dev, pyannote API 실검증 문서와 현재 코드 확인. 세션 필수 규율 본문 재사용 및 구현·장기 실행·수치·공유 트리 규율 적용.
- 기존 브랜치 유지: 혼합 미커밋 .claude/commands/build.md, README.md, ssot/dev.md, versions/m0-fixture-review/plan.md, versions/m1-recording-safety/plan.md, versions/m2-managed-processing/plan.md를 보존·커밋 제외. 자동 정리·브랜치 전환 없음.
- 실측 M5 Pro/48GB, Python 시스템3.9.6. 격리 Python3.12 환경 및 모델을 ignored .build 아래 설치. 모델 다운로드는 승인된 개발에 필요한 공개 아티팩트 다운로드, 실제 음성의 신규 클라우드 전송은 기존 녹음별 확인 경로 유지.
- upstream moona3k/mlx-qwen3-asr 커밋 1e28932dac8e2c68b34c29f32e2be338ffc1c852 (0.4.0). 실제 모델 revision도 다운로드 시 고정. raw Qwen·정렬 결과·종료 사유·문맥 hash·청크 위치 보존.

## 수용 기준
- [x] AC-01 격리 런타임 준비, 한국어 context가 실제 호출에 전달, 비양자화 ASR1.7B/aligner0.6B 사용, 로컬 diarize OFF. 모델/의존성 버전 고정·재현 설치 절차.
- [x] AC-02 최대120초/최소60초 안쪽 저에너지 지점 청크(초기 실험값), 무음 삭제 없음. 청크마다 출력 예산·종료 이유·truncated 기록, EOS 아닌 결과는 완료 채택 금지. 완료 청크 재사용·취소/재개·타임아웃.
- [x] AC-03 정렬용 표기와 원 ASR 문자열 분리. 원 문자열 공백/기호/숫자 전수 보존, 정렬 항목을 문자 위치로 연결. 매핑 불확실·0길이/역행/범위초과는 null+검수 이슈, 텍스트 삭제 없음.
- [x] AC-04 화자 결합: 같은 오디오 hash/전체 길이·count/precision-2 설정으로만 기존 결과 재사용. 새 화자분리는 transcription=false. 일반/exclusive 모두 보존, 경계 두 화자/겹말은 null, 무음최근화자 추정 없음. A→B→A 누락 장벽·반복 단어·단위 고정 테스트.
- [x] AC-05 앱의 비교용 엔진 선택→입력/동의→처리→별도 Script→원문 내보내기. 기존 결과·사람 수정 불변, 새 Run ID/원천 Run provenance, 기본값 유지. 준비 안 된 런타임은 구체 오류 표시.
- [x] AC-06 같은21:53 전체 녹음을 실제 로컬 실행, 기존 Precision-2 재사용, 시간·메모리·정렬/불확실/문단 수 집계. Soniox 원문 비교, 정확도/원음 정답 미측정은 구분. 실제 데이터 Git 미포함.
- [x] AC-07 합성 Core/worker/managed 영향 검사·계약 검사·앱 build·실제 UI 여정. 전달 빌드 버전 증가, 기존 앱/Script 보존.

## 작업 분해
- T-01 런타임·모델 고정 설치와 worker 입출력/청크 재개, 짧은 파일럿으로 속도·메모리 및 워치독 초기값 검산.
- T-02 Qwen 정렬 원문 매핑·Core normalization·Precision-2 결합, 단위/경계/누락 테스트.
- T-03 ManagedProcess 로컬 프로세스·캐시/클라우드 재사용·기존 선택 UI/상태/저장 연결.
- T-04 전체 녹음 비교·합성/여정 검사·앱 전달·상태 기록.

## 시간 계약
- worker 청크 위치는 WAV frame 정수/16kHz. 정렬 초→round(seconds×1e6)+청크 offsetUs. 내부/출력 Int64µs, 반열린 구간. 원음 시작점 유지.
- 80ms는 모델 시간 표현 해상도이며 오차 보증으로 표현하지 않음. NULL 시 start/end 함께 NULL. 청크 토큰·시간을 다른 ASR 결과와 순서만으로 대응 금지.
- 경계 2화자 이상은 보류(기존 P1 초기0.60 coverage/0.20 margin보다 보수적). score는 confidence와 분리. algorithmVersion=qwen-p2-v1.

## Follow-ups
- 기본 엔진 승격·정답 CER/E1/E2·능동 수정시간은 원음 검수 후 결정. 자동 이름 매핑 없음.
- 97분 확장, 8bit/언어자동 비교, Swift-native 이식, 자동 구간별 용어 선정은 21:53 검증 뒤 별도. 첫 입력은 사용자 제공 맥락/용어 전체 snapshot, 자동 주제 추정 없음.

## 완료 근거 — 2026-09-11
- [런타임·재현 설치](../../notes/qwen-local/runtime.md), [실측 평가](../../notes/qwen-local/evaluation.md). 앱 0.3.0 (9), /Applications/DAMA.app 설치, 이전0.2.1 ignored 백업 보존.
- 실제 앱 Run 5E0B2593-549B-48BC-9AED-A5C94B809B8C, 새 Script 746492F0-D671-42D7-898C-BB2DD9E9F2AC. 전체21:53 처리100.30초, 기존P2 raw동일/신규POST없음, 기존5Script hash동일. AI교정없음.
- Qwen 정렬2,587항목 중336미정렬; 화자미확정566; 발화문단1,013+누락의심81. 분절/정렬 문제가 남아 비교용으로만 유지. 3명 결과는 화자정확도 증거가 아님.
- Swift 고유82+계약30, Python4 PASS; DomainContracts 양쪽동일, schema enum추가; 최종Xcode build PASS. 실제앱 재실행/새Script 표시/한국어 공백보존 확인.
- AC-02의 취소·재개는 합성journey 검사와 코드로 검증; 실제GPU의 취소·재개/추론중 앱종료 child정리는 미측정. 실제GPU는 정상완료·반복종료복구를 검증했다. AC-05/07 내보내기창 확인 및 실제저장Script의 Core Markdown 출력 검증, GUI Save까지는 수행하지 않았다.
- SSOT 상태 built는 비교 구현의 완료이며 품질 채택·출시승인이 아님. 기본엔진 교체·97분실행·정답평가는 후속범위다.
- 최종 변경 소유: Qwen 관련 앱/Core/Managed/worker·tests·notes/qwen-local·versions/qwen-local 및 버전/계약 enum만 커밋. 착수 시 혼합 변경 6개 문서는 보존.

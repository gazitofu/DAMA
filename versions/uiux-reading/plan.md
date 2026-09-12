---
unit: uiux-reading
branch: work/m0-fixture-review
status: built
decisions_resolved: true
resume: "앱 반영 완료, 0.5.0(18) 설치/실행 확인. 게이트② 완성본 확인 대상. 후속은 notes/uiux-reading/speaker-context-diagnosis.md의 P2 시간 정렬 실험과 영구 개인 용어 프로필. native-qa.md에 합성 전송 사건·도구 제한·미측정 기록. main merge/push/학습/유료 실험 미승인 유지."
spec: notes/uiux-reading/uiux-reading.src.html
---

## 근거

- 2026-09-12 사용자: 제목 직접 입력/자동 저장, Scripts 나머지 전체 승인; Speeches r5 ‘오케이 확정. 이제 앱 반영을 위해서 작업 들어가자.’
- 홈 CLAUDE, Vault/appdev/CLAUDE, repo CLAUDE/AGENTS, README/프로젝트 인덱스; `/spec`·`/plan`·`/build` 파일 절차.
- 규율22종 설명 탐색. 목적·모호성·범위·게이트·측정·부정주장·재실측·소비처·위임산출물·파괴쓰기·공유트리·수치·외부미디어·워치독·정렬·Apple 툴체인·인라인스크립트·리뷰종료 본문.
- design00·01·02·03·04·06, API verified, dev, transcript.v1.schema.json/DomainContracts.swift 실측; library-script/operating-baseline 계약; tone/uiux-reading.
- HEAD f1334e1, 기존 승인 앱/스펙 스택과 타 소유 dirty7을 보존하여 현 브랜치 유지. 독립 Codex 직접 구현, 하위 CLI 위임 없음.
- 타 소유 제외: .claude/commands/build.md, README.md, notes/qwen-local/evaluation.md, ssot/dev.md, versions/{m0-fixture-review,m1-recording-safety,m2-managed-processing}/plan.md.
- 사전검사 `bash scripts/check.sh --log-root .build/check-logs/uiux-reading-baseline`: 계약30, Swift165, Debug build PASS, SKIP0. 로그 run-20260912T091200Z-QxzFao. 실제 음성/API/마이크 미사용.

## 의도

사용자가 읽던 제목·본문에서 바로 수정하고, 화자 이름과 AI 참고만 모달로 다룬다. Speeches는 선택 엔진이 사용하는 입력과 실제 전송 내용을 보여 준다. 미배정 원인·개인 용어/참조 개선 방향은 별도 진단이며 화자 정책·학습을 임의 전환하지 않는다.

## 영향 범위

- DamaCore LibraryScript/LibraryPresentation/ScriptCorrection: 기존 optional map과 원문 유지, 순서가 있는 Turn ID 집합에 문단 수정본 추가.
- FolderLibraryStore: 해시 검사·직렬 필드 병합, AI 성공 시 불변 snapshot 목록, 동일 Run 과거 조회. 과거 성공 이력은 추정 생성하지 않음.
- App LibraryWorkspace/CorrectionWorkspace 및 UI LibraryShell: 네이티브 읽기·입력·전환·모달·재생. 메뉴바 녹음 경로 유지.
- Soniox 컨텍스트 7,500바이트 앱 제한, Qwen 로컬 컨텍스트 제한 유지. md/txt 발췌 선택은 원문/후보/포함·제외를 구분. API 키/음성 전송 신규 실호출 없음.
- ssot/contracts/library-script.md, tone/uiux-reading, notes/uiux-reading/audit.md, versions/uiux-reading/plan.md와 기존 두 유닛의 resume; 전달 때 pbxproj Debug/Release 버전 동시 증가.

## 수용 기준

- [x] AC-01 기존 JSON 무이관 읽기, 모델 원문·시간·화자·marker 보존. 여러 Turn/빈 문자열/ABA·미배정·누락 경계/외부 변경 회귀. INV-01·06·09 및 설계 RC-01~03의 경계 유지.
- [x] AC-02 문단 전체 수정본이 화면·Markdown·버전에 동일. 원 Turn에 재분배하지 않고 AI 대상에서 제외, 읽기 전용 참고로 전달. 기존 사람이 수정한 Turn도 보호.
- [x] AC-03 AI 첫 성공 전/각 성공 snapshot 불변·해시 검증. 실패/취소는 완료 버전 없음; 중복 완료 중복 생성 없음. 현재 편집과 AI 완료 병합, 다른 Run/원문 교체 차단.
- [x] AC-04 같은 본문/같은 폭·글꼴로 수정→내용 변경 때 저장, 취소/Escape·빈 내용·멀티라인·IME 조합 안전. draft 중 탐색/다른 결과/화자/AI/내보내기 차단.
- [x] AC-05 제목 직접 입력, 조합 종료 후500ms 자동 저장/blur·Enter 즉시. 빈값/오류 draft 유지, 연속 입력 순서 보존. 과거 snapshot 읽기 전용.
- [x] AC-06 로고·화자 모달 3범위·주의 정보·다른 결과·본문과 재생 위치 연결. 검수 기록 입력/집계 UI 제거, 기존 기록 보존. 시간 Int64 µs·반열린 구간 유지; 고정 재생 경계 테스트.
- [x] AC-07 AI 추가 참고 모달: 열기/취소 외부 요청0·저장0, 최종 보정하기 입력 snapshot. 기존 성공본 유지, 버전 메뉴로 조회/내보내기.
- [x] AC-08 Speeches r5 목록/입력/접기/변환 확인/진행·재개/결과 열기. 선택 엔진 소비 항목만 노출, 저장/실패/동의/불명확 접수 재제출 차단 유지. 합성 폴더→Soniox payload/Qwen 로컬 입력 소비 검증.
- [x] AC-09 전체 check PASS, 실제 Mac 합성 여정 QA, 실제 사용자 원본 비변경 확인. 앱 버전 올림/설치·실행 Bundle 확인. 실제 ASR 정확도·학습·요금 비교는 미측정 표시.

## 작업 분해

| 작업 | 의도·산출물 | 검증 |
|---|---|---|
| T-01 | 문단 수정본 계약·읽기·AI 사람 수정 보호 | Core 문단/AI 경계 회귀 |
| T-02 | 직렬 필드 저장·AI 버전 snapshot/조회/내보내기 | 저장 충돌·손상·중복·실패 회귀 |
| T-03 | 제목/본문 동일 자리 native 편집과 탐색 차단 | Core + Debug compile, 합성 IME/키보드 여정 |
| T-04 | 화자·정보·재생·결과 메뉴/AI 참고 모달 | 동일 Run/다른 Run·읽기 전용·취소 여정 |
| T-05 | Speeches 재배치·엔진별 실제 소비 입력·참조 진단 | 합성 파일→payload/로컬 요청, 상태·복구 여정 |
| T-06 | 통합 QA·버전 전달·완료 상태, 별도 개선 진단 | 전체 check 및 설치된 실제 앱 |

## 결정 항목

- D-01 승인: 현재만 편집, 첫 성공 전/각 성공 immutable snapshot, 과거 복원/분기 없음. 구 버전 파일에서 유실된 과거 AI 이력을 발명하지 않는다.
- D-02 승인: 문단 전체 사람 수정본 + 순서 있는 원 Turn 집합. 불변 원문 fingerprint 및 저장 시 기준 revision/text 검증, AI/표시보다 우선.
- 저장 구현: snapshot 자체와 현재 파일의 버전 목록을 분리하여 self-hash 순환 방지. snapshot 선저장 → 현재 목록 원자 저장; 중단 잔여 snapshot은 목록에 드러내지 않음.
- 폴더 선택만으로 전송하지 않는다. Soniox 기본 문맥 ON/폴더 OFF; Qwen 로컬 폴더 별도 선택. pyannote 통합 STT에서 소비하지 않는 맥락/참석자/용어/참고 입력 UI 숨김, 저장된 내용 삭제 없음.

## 완료 근거 (2026-09-13)

- T-01~06 완료. [네이티브 QA](../../notes/uiux-reading/native-qa.md), [별도 화자·개인 지식 진단](../../notes/uiux-reading/speaker-context-diagnosis.md). 저장·이력·충돌·내보내기는 Core 검증, 입력/배치/화자/AI 모달·Speeches·재생은 실제 Mac 합성 검증으로 구분한다. 네이티브 저장 패널 완료와 물리 IME/작은 창/라이트·VoiceOver·장시간 성능은 미측정이다.
- 최종 독립 scratch 전체검사 계약30/Swift170/Debug PASS, SKIP0: .build/check-logs/uiux-reading-final-clean/run-20260912T145840Z-iMQdTm. 최초 회귀와 재사용 scratch SIGBUS는 QA 기록에 보존.
- 앱0.5.0(18) About 창 실측, 기존 운영 입력·완료 Run·Scripts 열림 확인. 실제 원본14파일 unchanged14/changed0/missing0. 기존 linker-signed 전달 방식 유지, main merge/push 없음.
- 검증 중 닫기 의도와 달리 합성 무음30초가 외부 처리된 사건을 사용자에게 알림. QA 전용 모델 실행 차단 및 네트워크 권한 제거 후 AI 차단 확인. 비용 미확인; 성능 성과로 산입하지 않음.

## Follow-ups

- T-05: 합성 md 발췌→Soniox 실제 payload builder/컨텍스트 OFF·폴더 OFF, QwenRunner 실제 프로세스 request→가짜 worker 소비 검증 및 전사/복구18 PASS(.build/check-logs/uiux-reading-t05.log). 발췌 구분자 […]를 기대값에 명시해 원문 전체와 구별. 실제 Qwen 모델/외부 ASR 품질 검증 아님. Speeches Debug build PASS.

- T-03/T-04: 동일 NSTextView 읽기/편집, IME 상태를 본 debounce500ms, 문단 draft/버전 탐색 차단, 화자 모달/AI 참고 최종 확인 연결. 저장/읽기/AI 회귀29 PASS(.build/check-logs/uiux-reading-t04.log), Debug build PASS. 새 모달 catch 변수 shadowing 컴파일 오류 수정 후 통과. 실제 입력·배치 QA는 T-06에서 시행.

- T-02 검증: ScriptVersionTests/ContextAudioTests/LibraryJourneyTests/ReadingSnapshotTests 15/15 PASS, .build/check-logs/uiux-reading-t02.log. 제목·문단·AI 병합, 원문 교체/외부 바이트/stale 제목 차단, immutable snapshot/중복 완료/실패/손상/과거 Markdown. 외부 API 없음.

- T-01 검증: LibraryPresentationTests/ContextCorrectionTests 22/22 PASS, .build/check-logs/uiux-reading-t01.log. 원문 fingerprint·그룹 고정·빈 문자열·AI 보호·legacy/손상 입력. 테스트 Markdown 기대값의 점 escaping을 기존 exporter 계약과 일치시킨 뒤 통과. 실제 UI 미측정.

- 별도 진단: 실제 미배정 원인과 P2/exclusive·시간 정렬 후보, 수동 수정시간/E1/E2/정상 요금 평가; 자동 추정·새 유료 호출 없음.
- 개인 용어·별칭·인물/조직 배경 지식과 참조 발췌의 현재 소비/한계, Qwen 컨텍스트와 실제 학습의 구분. 개인 프로필 UI/모델 fine-tuning은 이번 화면 승인과 분리.
- 게이트②: 완성본 확인. main merge/remote push/출시 승인과 별개인 로컬 앱 전달.

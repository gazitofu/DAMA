---
unit: uiux-reading
branch: work/m0-fixture-review
status: built
decisions_resolved: true
resume: "T-12 built: 화자 이름 변경 되돌리기(nameHistory + ‘이름 변경 취소 (N)’). 계약30/Swift205/Debug, 설치0.5.9(27). 단추 실화면 확인은 화면 기록 권한 부재로 미측정."
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

### T-10 · 2026-09-15 Speech당 단일 대표 결과와 교정 모델 고정

- 사용자 요청에 따라 Scripts 좌측 목록은 같은 Speech의 전사 Run을 한 행으로 묶는다. 대표는 최신 Soniox+Precision-2 운영본이며, 운영본이 없을 때만 최신 비교본을 쓴다. 보존된 Soniox 단독·재전사·AI 버전은 삭제하거나 병합하지 않고 기존 ‘다른 결과 보기’에서 연다. 비교본을 보고 있을 때도 같은 Speech의 대표 행을 선택 상태로 표시한다.
- 앱의 Codex CLI 호출은 `--ignore-user-config`로 전역 `model=gpt-5.6-sol`을 읽지 않았고 `--model`도 없어 과거 실제 모델 ID를 확정할 수 없었다. 새 교정은 로컬 모델 카탈로그의 비용 민감형 `gpt-5.6-luna`, reasoning medium으로 명시 고정하고 설정·새 correction engine에 표시한다. 하위 모델에서도 구조화 출력·원문 위치·Turn 소유·미해결 검증과 실패 폐쇄는 동일하게 유지한다.
- [x] AC-17 같은 Speech의 Soniox 단독+결합본+재전사 결과가 Scripts 한 행으로 표시되고 최신 결합본이 기본이며, 모든 원 파일은 ‘다른 결과 보기’에서 선택 가능하다. 다른 Speech는 별도 행이다.
- [x] AC-18 새 Codex 호출 인자·설정·저장 engine은 GPT-5.6 Luna를 일치 표시하고 사용자 전역 설정과 과거 이력을 바꾸지 않는다. 합성/가짜 CLI와 실제 모델 품질을 구분한다.
- [x] AC-19 대상 Core/가짜 CLI, 전체 backpressure, Debug0.5.7(25) 빌드 및 설치·실행 버전/실화면을 확인한다. 실제 AI·음성 전송은 하지 않는다.

#### T-10 완료 근거

- `ScriptResultPresentation`은 sessionID로 원 결과를 묶고 최신 Soniox+Precision-2 운영본을 대표로 선택한다. 대상 Core/가짜 CLI 5건 PASS. 모델 인자 `--model gpt-5.6-luna`, reasoning medium과 Speech별 대표 선택/다른 Speech 분리를 검사했다.
- 원 `scripts/check.sh`의 첫 전수 시도들은 공유 Swift 6.3.3 module cache signal11, 샌드박스 CoreAudio M4A, 샌드박스 Xcode 서비스 제한에 걸렸다. 원 스크립트와 cwd 대소문자·독립 module cache만 다른 기존 진단 wrapper로 재실행하여 계약30/Swift201/Debug/SKIP0 PASS. 로그 `.build/check-logs/script-results-model-full-r3/run-20260915T050448Z-J33QA0`.
- 합성 fixture는 Speech2건 중 1건에 Soniox+Precision-2와 Soniox 원 결과2건을 만들고 외부 요청0건을 확인했다. 실설치 UI에서는 기존 3개 Speech의 Scripts 7행이 3행으로 축약되고, 선택 Speech의 ‘다른 결과 보기’에 두 원 결과와 현재 선택 표시가 유지됐다. 설정의 `문맥 교정 · Codex CLI · GPT-5.6 Luna`, About의 `DAMA Version 0.5.7 (25)` 확인.
- 검사 빌드와 `/Applications/DAMA.app` 실행 파일 SHA-256 `483d259fe332369512a8c60b1eaf7742d766efb3d261f85d17a4e92c57bbfd16` 일치. 이전 앱 백업 `.build/backups/DAMA-0.5.6-24-before-script-results-model.app` 보존.
- 실제 AI·음성 전송·유료 호출은 실행하지 않았다. 과거 `기본 모델`의 실제 모델 ID와 GPT-5.6 Luna의 사용자 한국어 전사 품질은 사후 확정·측정하지 않았으며, 선택 판단은 제한된 구조화 교정 계약과 로컬 모델 카탈로그 역할을 근거로 한다.

### T-09 · 2026-09-13 AI 교정 기본 반영

- 사용자 ‘반영이 안되는 특별한 이유가 없으면 반영을 하자’로 기존 용어 사전 필수 조건을 해제한다. 확실한 수정은 본문에 반영하고 수정별 불확실성/미해결 범위 중첩, 원문 인용·위치·재구성 오류는 유지한다. 모델 원문/시간/화자/사람 수정은 보존한다. 화자 재배정·구조 변경 승인이 아니다.
- `context-correction-5`: 새 구조화 응답은 용어 사전/형식 allowlist를 필수 조건으로 삼지 않는다. 검증된 용어 대응은 근거로만 남긴다. 원문 위치가 없는 legacy 응답은 기존 제한 정책 유지. 기존 저장 판정은 로드만으로 변경하지 않는다.
- 저장된 구조화 후보는 현재 결과의 ‘저장된 AI 교정 반영’으로 외부 호출 없이 재검증·새 AI 버전 저장. 사람이 소유/삭제한 Turn은 재반영에서 제외, 원문 불일치 차단. 과거 버전은 당시 상태 그대로 읽기 전용. 구간 정보에 반영 상태와 수정별 사유를 표시한다.
- 착수 HEAD6c9800e/branch work/m0-fixture-review/status built/타소유 dirty7 실측. 기존 공유트리 유지 승인 범위, 타소유 파일/타트랙 상태는 수정·커밋 제외. 직전 계약30/Swift198/Debug PASS 재사용. 공통 진입점·build/spec 필수 규율·dev/API·library-script 계약을 적용하고 직접 구현한다.
- QA 종료축: 신규 회사명/어휘 교정 및 독립 불확실성, 사람 수정/삭제·원문 보존, 저장 후보→새 버전→재열기/Markdown·이전 버전 불변/충돌, 실제 요청 Script의 본문 표시와 앱 버전. 새 AI/음성 전송·정확도 평가·타 트랙은 실행하지 않는다.
- [x] AC-14 확실한 구조화 문맥 교정 반영, 불확실/잘못된 위치 보류·실패 및 용어 근거와 적용 판정 분리 회귀.
- [x] AC-15 저장 후보 재반영의 새 버전/중복 방지/사람 수정·원문·이전 버전 보존, 재열기/Markdown/충돌 검증.
- [x] AC-16 계약·Swift·Debug 및 실제 저장 후보 반영/본문/재실행,0.5.6(24) 설치·실행 버전 확인.

#### T-09 완료 근거

- `CorrectionSpans` v5는 불확실/미해결 중첩만 보류, 형식·사용자 용어 대응은 추가 근거로 유지. 새 `CorrectionReapplication`과 저장 actor는 현재 후보의 원문 위치를 재검증하고 새 완료 ID/버전으로 저장한다. UI는 저장 후보 반영 버튼과 구간별 반영·보류 사유를 제공한다.
- 영향 Core/버전14건 PASS(`.build/check-logs/ai-application-targeted-r3.log`). 초기 테스트 컴파일의 누락 try, 같은 읽기 문단에 속한 두 원구간을 독립 문단으로 가정한 테스트 구성을 고쳐 실제 서로 다른 문단으로 검사했다. 이전 용어 제한으로 역뮤테이션 시 신규 문맥/CLI 소비 테스트2개가 실패(단언4개)해 회귀 변별력을 확인하고 복원했다(`ai-application-inverse-mutation.log`).
- `bash .build/diagnostics/word-v4/check.sh --scratch-path .build/ai-application-tests --log-root .build/check-logs/ai-application-final`: 계약30/Swift200/Debug PASS·SKIP0, 로그 `run-20260913T102328Z-5xw8cm`. 원 check.sh와 차이는 대소문자 통일 cwd 및 독립 module cache뿐이다. 첫 전수 실행(`run-20260913T101856Z-hdNTWs`)은 구두점 미반영을 기대한 기존 테스트1건 및 재사용 xctest signal10으로 실패했다. 사용자 승인 정책에 맞춰 기대값을 이동하고 별도 scratch에서 전수 통과; signal10 근본 원인은 미확정.
- 실제 요청 Script의 저장 후보44개/적용0개에서44개 적용으로 변경. 동일 코드·저장 actor로 workspace 사본의 저장→새 버전→재열기→Markdown→재적용 no-op PASS(`.build/diagnostics/ai-application/Verify.swift`, `verify-r2.log`). 보존된 이전 버전의 byte/hash, 원 normalized/사람 수정/삭제를 대조했다. 사본 초기 실행은 대상 폴더 미생성으로 실패했고 폴더 생성 후 통과했다.
- DAMA0.5.6(24)를 설치하고 CUA로 실제 ‘저장된 AI 교정 반영’ 실행. 새 ‘AI 보정2’ 본문에서 문제 회사명 교정, 구간 정보의 자동 반영/수정별 사유를 화면 확인했다. 정상 종료→재실행→Scripts에서 같은 교정 본문 확인; About의 실행 버전0.5.6(24) 확인. 기존 AI 보정1은 당시 판정 그대로 보존한다.
- 전달 전후 실제 대상의 변경 필드는 correction/revisionID/versions뿐. 타Script6, 기존 snapshot2, 소스173, 타소유 dirty7 바이트 불변, 설치 앱=검사 빌드 바이트 일치(`.build/diagnostics/ai-application/delivery.json`). 원 앱 백업 `.build/backups/DAMA-0.5.5-23-before-ai-application.app`, 대상 원본 `.build/diagnostics/ai-application/before.dama.json` 보존.
- 실제 AI/음성 전송·유료 호출·마이크·원음 정답 평가는 실행하지 않았다. Markdown은 저장 actor의 실제 파일 생성으로 검증; native 저장 패널은 재검사하지 않았다. main 머지/push/release 없음, 타소유7은 커밋 제외.

### T-08 · 2026-09-13 등록 화자와 발화 삭제

- 사용자 ‘이정도로 확정’으로 B2 결과 확인 완료. 추가 지시1·2는 기존 화자 모달에 등록 화자 선택 추가, 본문 조작에 삭제 추가로 직접 반영한다. 기존 화면을 재설계하거나 재승인을 요구하지 않는다.
- 스크립트 envelope에 optional registeredSpeakers(UUID/name/colorIndex), turnSpeakerIDs(Turn→등록ID), deletedParagraphs(UUID/원Turn ID 집합)를 추가. 원 normalized·음성·기존 사람 수정/AI 이력은 불변, 다른 Script/Run 전파 없음. 이름 입력 저장 시 등록, 같은 이름 재입력/목록 선택 시 동일 등록ID와 색 사용. legacy turnNames는 읽기·목록에서 존중한다. 실제 원 화자 경계를 이름만으로 자동 병합하지 않는다.
- 기존 범위 ‘이 부분만/이 부분부터/전체’ 유지. 등록 화자는 등록ID 기준, 미등록은 원 speakerID 기준. 미배정 최초 지정은 선택 문단만. 삭제 문단은 화면/Markdown/신규 AI 입력에서 제외하고 마지막 삭제부터 취소 가능. 삭제 전후 원구간은 자동 합치지 않는다. 현재 버전만 변경, 과거 snapshot 읽기 전용, 외부 파일 충돌 차단.
- QA 축: 화자C 이름 입력→미배정 문단에서 선택→이름/색/등록ID 일치→저장/재실행/Markdown, 본문 수동 통합→원 문단 삭제→저장/재실행/내보내기→삭제 취소. 원문 fingerprint·순서·사람 수정·AI 완료 병합/과거 버전·실패/외부 변경도 검사. 실제 사용자7개는 읽기 검증/해시 보존, 쓰기 QA는 별도 합성 앱에서 시행.
- HEAD2a6b311/branch/기존 dirty7 실측 일치. 같은 세션 기준/규율 재사용, 설명22개 탐색 및 파괴쓰기 본문 보충. 사전 PASS는 직전 최종 계약30/Swift189/Debug(제품 코드 변경 전) 재사용. 독립 Codex 직접 구현, 위임 없음. 버전0.5.4(22) 전달 예정.
- [x] AC-11 등록 화자 재사용/동일 이름·색/범위/legacy 보존 및 스크립트 간 분리.
- [x] AC-12 삭제·취소/빈 스크립트/사람 수정·AI·원문/시간 보존, 저장·재실행·Markdown/버전/충돌 회귀.
- [x] AC-13 전체 backpressure와 합성 네이티브 두 여정,0.5.4(22) 설치·실행 버전/기존7개 해시 불변 확인. native 저장 패널 완료는 아래 한계로 구분.

#### T-08 완료 근거

- Core optional envelope 등록 화자/Turn 연결/삭제 목록 및 UI 모달 Picker·발화 삭제·삭제 취소 완료. 미배정 최초 지정은 문단만, 동일 등록ID의 이후/전체 범위 지원. 원 화자 ID나 시간은 변경하지 않는다. legacy 입력 이름은 읽기만으로 원 파일을 바꾸지 않고 목록에 표시하며, 명시적 재사용 시 등록한다. 같은 이름만으로 다른 원 화자 경계를 자동 합치지 않음.
- 새 Core5/저장1 검사와 기존 회귀 **계약30/Swift195/Debug/SKIP0 PASS**: `.build/check-logs/reading-people-final/run-20260913T013705Z-GTZV77`, 독립 scratch `reading-people`. 기존189 검사·golden 기대값 변경/삭제 없음. 역뮤테이션(등록 재사용 해제/삭제 표시 해제)2검사5실패 후 복원하여 전수 PASS, `reading-people-mutation.log`.
- 첫 재사용 scratch에서는 ScriptVersionTests2단정 실패(versions nil), 새 scratch에서 동일 원 검사3개와 전체 PASS. 원인을 제품 수정 없이 확정하지 않음. 새 합성 소스의 필수 text 누락은 수정 후5개 PASS. CLI fixture 최초 provider null speaker 거부는 유효 provider payload 후 합성 normalized unknown을 명시하는 방식으로 수정. 실패 로그/부분 준비 폴더 보존, 테스트 완화 없음.
- `.build/diagnostics/reading-people/Verify.swift`/`verification.json`: 실제 현재Script7개 validate, 메모리 이름·문단 수정→삭제→codec 왕복→취소, 원 fingerprint/원 파일 해시 보존. 설치 전후 전체7개 해시 불변. 기존 B2에는 사용자 이름/부분 수정이 이미 있으므로 이전 T-05 전달 직후 해시를 재사용하지 않고 이번 착수 baseline을 사용했다.
- `ReadingUIFixture.swift`는 합성30초 무음/3화자/미배정1개/과거 snapshot2개를 준비한다. `/private/tmp/dama-reading-qa-20260913-people-b`, 별도 `com.gazitofu.Dama.ReadingQA` ad-hoc 앱에서 실제 CUA: Speaker C→이석훈 상무 전체 저장→미배정 목록 선택→원4Turn의 같은 등록ID/색, 화면3문단 확인. 첫 문단에 다음 문단 텍스트를 통합·저장→다음 문단 삭제→7→6문단→앱 재실행 후 유지→삭제 취소로 원7문단 복구, 통합 본문과 등록은 유지. QA 원자료/검증 산출물은 ignored 경로에만 보관.
- native NSSavePanel 저장 클릭 후 timeoutReached가 발생해 Markdown 파일 완료는 확인하지 못함. sample은 메인 이벤트 루프 대기, 앱 교착으로 단정하지 않음. 화자/본문/삭제 저장을 디스크에서 확인한 뒤 QA PID90489만 승인된 TERM/재실행으로 복구, 이후 삭제 취소/정상 종료 확인. AXError.failure가 반환된 일부 클릭도 실제 상태 변화는 재조회로 확인하고 중복 제출하지 않음. 동일 저장 actor `exportMarkdown`으로 QA 삭제 checkpoint의 `.md`를 생성하여 통합 문장1회/삭제 문단 제외를 검증했다. 실제 음성·마이크·AI·유료 모델 호출은 없음.
- `.build/check-logs/reading-people-delivery-build.log` PASS, 독립 derivedData `reading-people-delivery`, Debug/Release0.5.4(22), CODE_SIGNING_ALLOWED=NO/entitlements 없음 유지. 기존 앱 백업 `.build/backups/DAMA-0.5.3-21-before-reading-people.app`. 빌드→설치 번들 파일 해시 전수 일치, 실제 About **DAMA Version 0.5.4 (22)**. 기존 B2의 화자 모달에 이미 입력한3개 이름 표시 확인 후 저장 없이 취소, B2 열어 전달. `.build/diagnostics/reading-people/delivery.json`.
- 이번 소유 파일만 로컬 커밋, 기존 타 소유 dirty7 보존. 소규모 사용자 후속 승인을 기존 스펙에 덧붙여 재빌드하고 tone/계약 갱신. B2 결과 판정 승인과 새 전사의 운영 정책 연결은 구분해 후속에 기록. 원격/main merge/외부 반출 없음.

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
- [x] AC-10 설정 맨 위 화면 모드: 시스템 설정(기본)/라이트/다크. 앱의 창·본문·모달에 즉시 적용하며 선택을 재실행 후 복원. macOS 전체 화면 모드는 변경하지 않음. 사용자 누락 지적에 따른 소규모 수정으로 직접 반영하고 해당 여정만 검증.

## 작업 분해

| 작업 | 의도·산출물 | 검증 |
|---|---|---|
| T-01 | 문단 수정본 계약·읽기·AI 사람 수정 보호 | Core 문단/AI 경계 회귀 |
| T-02 | 직렬 필드 저장·AI 버전 snapshot/조회/내보내기 | 저장 충돌·손상·중복·실패 회귀 |
| T-03 | 제목/본문 동일 자리 native 편집과 탐색 차단 | Core + Debug compile, 합성 IME/키보드 여정 |
| T-04 | 화자·정보·재생·결과 메뉴/AI 참고 모달 | 동일 Run/다른 Run·읽기 전용·취소 여정 |
| T-05 | Speeches 재배치·엔진별 실제 소비 입력·참조 진단 | 합성 파일→payload/로컬 요청, 상태·복구 여정 |
| T-06 | 통합 QA·버전 전달·완료 상태, 별도 개선 진단 | 전체 check 및 설치된 실제 앱 |
| T-07 | 설정의 화면 모드 선택·앱 공통 적용·선택 저장 | 앱 빌드, 실제 라이트/다크 전환·재실행 확인 |

## 결정 항목

- D-01 승인: 현재만 편집, 첫 성공 전/각 성공 immutable snapshot, 과거 복원/분기 없음. 구 버전 파일에서 유실된 과거 AI 이력을 발명하지 않는다.
- D-02 승인: 문단 전체 사람 수정본 + 순서 있는 원 Turn 집합. 불변 원문 fingerprint 및 저장 시 기준 revision/text 검증, AI/표시보다 우선.
- 저장 구현: snapshot 자체와 현재 파일의 버전 목록을 분리하여 self-hash 순환 방지. snapshot 선저장 → 현재 목록 원자 저장; 중단 잔여 snapshot은 목록에 드러내지 않음.
- 폴더 선택만으로 전송하지 않는다. Soniox 기본 문맥 ON/폴더 OFF; Qwen 로컬 폴더 별도 선택. pyannote 통합 STT에서 소비하지 않는 맥락/참석자/용어/참고 입력 UI 숨김, 저장된 내용 삭제 없음.

## 완료 근거 (2026-09-13)

- 사용자 ‘일단 UI는 모두 확인’으로 로컬 앱 완성본 게이트② 확인 완료. 후속 요청은 AI 보정 전 Soniox+P2의 미배정·과분절 해결 방안 진단이며, UI 재설계/main merge/push/출시 승인과 구분한다.
- T-07: 사용자 설정 누락 지적을 직접 반영. UserDefaults 선택값 + NSApplication 공통 appearance, 시작 시 복원. `.build/check-logs/uiux-reading-appearance-build.log` Debug PASS. CUA로 라이트/다크 즉시 전환·라이트 본문·재실행 후 라이트 선택/화면 유지·시스템 모드 복귀 확인. About `0.5.1(19)` 실측, 설정 화면을 열어 전달. 데이터 경로 변경이 없어 Core 전수 검사는 반복하지 않음. 기존 dirty7만 남기고 커밋.
- T-01~06 완료. [네이티브 QA](../../notes/uiux-reading/native-qa.md), [별도 화자·개인 지식 진단](../../notes/uiux-reading/speaker-context-diagnosis.md). 저장·이력·충돌·내보내기는 Core 검증, 입력/배치/화자/AI 모달·Speeches·재생은 실제 Mac 합성 검증으로 구분한다. 네이티브 저장 패널 완료와 물리 IME/작은 창/라이트·VoiceOver·장시간 성능은 미측정이다.
- 최종 독립 scratch 전체검사 계약30/Swift170/Debug PASS, SKIP0: .build/check-logs/uiux-reading-final-clean/run-20260912T145840Z-iMQdTm. 최초 회귀와 재사용 scratch SIGBUS는 QA 기록에 보존.
- 앱0.5.0(18) About 창 실측, 기존 운영 입력·완료 Run·Scripts 열림 확인. 실제 원본14파일 unchanged14/changed0/missing0. 기존 linker-signed 전달 방식 유지, main merge/push 없음.
- 검증 중 닫기 의도와 달리 합성 무음30초가 외부 처리된 사건을 사용자에게 알림. QA 전용 모델 실행 차단 및 네트워크 권한 제거 후 AI 차단 확인. 비용 미확인; 성능 성과로 산입하지 않음.

## T-11 화자 이름 범위 · 화자 지정 롤백 (2026-09-21 사용자 요청)

- 사용자 요청 ①: `20260918_에너벤터식사`의 화자 지정을 롤백. ②: Speaker A·B를 같은 이름으로 지정한 뒤 Speaker B만 다른 이름으로 바꾸면 Speaker B 문단만 바뀌도록 규칙 변경.
- 결함: `speakerTargets(_:scope:)`가 앵커 Turn에 `turnSpeakerIDs`가 있으면 **같은 등록 인물** 전체를 대상으로 잡았다. 이름이 같아진 다른 원 화자까지 함께 바뀌었다. 계약 §화자 범위를 원 speakerId 기준으로 개정하고 구현을 맞췄다.
- 구현: `speakerTargets`는 `.from`/`.all`에서 항상 원 `speakerId`가 같은 Turn만 대상으로 한다. `LibraryScript.originalSpeakerLabel(for:)` 추가 (원 라벨 계산을 `providerLabel(for:)`로 공유). 화자 모달에 `원 화자 Speaker B · 현재 이름 N` 캡션과 새 안내 문구. 등록 인물 재사용(같은 이름 → 같은 등록ID·색)은 유지.
- 롤백: 앱 정상 종료 후 활성 파일 `7F31839A-…dama.json`을 생성 직후 불변 리비전 `23082BB9-…`(11:19:34)의 바이트로 복원. 사전 대조에서 `transcript`·`input`·제목·`createdAt` 동일, 차이는 `turnNames`/`turnSpeakerIDs`/`registeredSpeakers`뿐임을 확인했다. 복원 후 turnNames 0·turnSpeakerIDs nil·registeredSpeakers nil, turns 2,074·words 53,368·원 화자 4명 그대로. 직전 상태는 리비전 `A3EACE1C-…`와 `.build/backups/script-7F31839A-speakers-0.5.7-before-rollback.dama.json`(해시 일치)에 보존.
- 검증: `scripts/check.sh` 계약30/Swift계약/swift test 202/xcodebuild Debug 전부 PASS, SKIP 0 (`.build/check-logs/run-20260921T025440Z-38SOPD`, `uiux-reading-t11-check2.log`). 신규 `testRenamingOneOriginalSpeakerLeavesOtherOriginalSpeakerWithSameName`, 개정 `testScopeFollowsOriginalSpeakerNotRegisteredPerson`.
- 실데이터 검증(`uiux-reading-t11-realdata.log`, 읽기 전용): 롤백 파일 1,160문단이 Speaker A~D로만 표시. Speaker A 전체 지정 14문단 → Speaker B도 같은 이름 지정 583문단(등록 인물 1명) → Speaker B만 다른 이름으로 전체 변경 시 정연서 대표 14·윤현섭 이사 569. 원 speakerId 배열과 원문 fingerprint 불변. 파일 미수정(해시 그대로).
- 부수 수정: Xcode 27 / Swift 6.4 업그레이드로 `FileSessionRepository.validRevisionCandidates`의 지역 재귀 클로저가 region isolation 오류가 됐다. HEAD worktree에서도 동일 실패를 확인해 기존 결함으로 판정하고, 체인 검사를 명시적 상태를 받는 메서드로 분리했다. 동작 변경 없음.
- 전달: Debug 0.5.8(26)을 `/Applications/DAMA.app`에 ditto 설치. 설치본·빌드본 실행 파일 SHA256 일치, adhoc/linker-signed 유지. 이전 0.5.7(25)은 `.build/backups/DAMA-0.5.7-25-before-speaker-scope.app`. 실행 확인(PID 99189).
- 미측정: 실제 앱 화면 캡처·모달 문구 실화면 확인은 화면 기록 권한이 없어 못 했다. 사용자 조작 여정(모달 열기→범위 선택→저장)도 실기기 미측정. Codex 위임은 사용량 한도로 실패해 메인이 직접 구현했다.
- main merge·원격 push·출시 승인 없음. 로컬 전달만 수행했다.

## T-12 화자 이름 변경 되돌리기 (2026-09-21 사용자 요청)

- 사용자: `20260918_에너벤터식사`에서 '전체' 범위 오조작이 두 번 발생했다. 13:32:13 저장은 Speaker B 913개 중 883개를, 13:46:08 저장은 832개를 한 이름으로 덮었다. 두 건 모두 직전 불변 리비전(`9F6BBB45`, `445DEDB7`)의 바이트로 복원했고, 직전 상태는 `.build/backups/script-7F31839A-{A5F634CF,E5CBBB0D}-before-undo-all*.dama.json`에 보존했다. 복원 전 대조에서 `transcript`·`turnTexts`·`registeredSpeakers`·삭제·문단편집·AI 이력이 동일함을 확인했다.
- 원인은 새 범위 규칙이 아니다. 두 사고 모두 원 화자 하나(Speaker B) 안에서만 번졌다. 한 원 화자의 문단을 사람마다 따로 고쳐 둔 상태에서 '전체'를 누르면 그 수정이 전부 덮인다는 구조적 위험이고, 앱에 이름 변경 취소가 없어 매번 파일을 직접 되돌려야 했다.
- 구현: `ScriptNameChange`(UUID `id`, 적용 `name`, 영향 `turnIDs`, 직전 `previousNames`/`previousSpeakerIDs`, `addedSpeakerID?`)와 `nameHistory: [ScriptNameChange]?`를 추가했다. `registerName`이 쓰기 직전 상태를 기록하고, legacy 이름 재사용으로 함께 연결되는 Turn도 대상에 포함한다. `undoNameChange()`는 마지막 항목만 되돌리며, 그 변경이 만든 등록 인물은 남은 이름·남은 이력이 더 이상 참조하지 않을 때만 지운다. 상한 `nameHistoryLimit = 20`은 초기 설계값이며 근거 출처가 있는 수치가 아니다.
- UI: 읽기 하단 도구막대의 '삭제 취소 (N)' 왼쪽에 '이름 변경 취소 (N)'. 도움말에 마지막 이름과 원구간 수를 표시한다. 과거 결과·읽기 전용에서는 나타나지 않는다.
- 검증: `scripts/check.sh` 계약30/Swift계약/swift test 205/xcodebuild Debug PASS, SKIP 0 (`uiux-reading-t12-check.log`). 신규 테스트 3건: 덮인 이름 복원과 생성 인물 제거, 전량 되돌리기 및 snapshot 거부, 상한 유지와 손상 항목 거부.
- 실데이터 검증(`uiux-reading-t12-realdata.log`, 읽기 전용): 실제 파일에서 Speaker B '전체' 사고를 재현해 912개 원구간이 덮이는 것을 확인하고, 취소 1회로 `turnNames`·`turnSpeakerIDs`·`registeredSpeakers`·이름 분포가 사고 전과 완전히 일치함을 확인했다. 원문 fingerprint와 원 speakerId 배열 불변.
- 전달: Debug 0.5.9(27) `/Applications/DAMA.app` 설치. launcher·`DAMA.debug.dylib` 모두 빌드본과 SHA256 일치, adhoc/linker-signed 유지. 이전 0.5.8(26)은 `.build/backups/DAMA-0.5.8-26-before-name-undo.app`.
- 설치 사고: 첫 종료 요청이 `User canceled (-128)`로 거부된 상태에서 ditto가 실행돼 **실행 중 번들을 교체**했다. 이후 재요청으로 정상 종료하고 13:53:11에 새 프로세스로 재실행했다. 앱은 교체 중에도 응답했고 사용자 편집(13:52:22~13:53:06의 이름 변경 5건)은 모두 리비전에 보존됐다. 다음부터는 종료 성공을 확인한 뒤 설치한다.
- 미측정: 단추의 실제 화면 표시·클릭 여정은 화면 기록 권한이 없어 못 했다. 기존 파일에는 `nameHistory`가 없으므로 단추는 새 빌드에서 이름을 한 번 바꾼 뒤부터 나타난다. Codex 위임은 사용량 한도로 불가해 메인이 직접 구현했다.
- main merge·원격 push·출시 승인 없음.

## Follow-ups

- T-05: 합성 md 발췌→Soniox 실제 payload builder/컨텍스트 OFF·폴더 OFF, QwenRunner 실제 프로세스 request→가짜 worker 소비 검증 및 전사/복구18 PASS(.build/check-logs/uiux-reading-t05.log). 발췌 구분자 […]를 기대값에 명시해 원문 전체와 구별. 실제 Qwen 모델/외부 ASR 품질 검증 아님. Speeches Debug build PASS.

- T-03/T-04: 동일 NSTextView 읽기/편집, IME 상태를 본 debounce500ms, 문단 draft/버전 탐색 차단, 화자 모달/AI 참고 최종 확인 연결. 저장/읽기/AI 회귀29 PASS(.build/check-logs/uiux-reading-t04.log), Debug build PASS. 새 모달 catch 변수 shadowing 컴파일 오류 수정 후 통과. 실제 입력·배치 QA는 T-06에서 시행.

- T-02 검증: ScriptVersionTests/ContextAudioTests/LibraryJourneyTests/ReadingSnapshotTests 15/15 PASS, .build/check-logs/uiux-reading-t02.log. 제목·문단·AI 병합, 원문 교체/외부 바이트/stale 제목 차단, immutable snapshot/중복 완료/실패/손상/과거 Markdown. 외부 API 없음.

- T-01 검증: LibraryPresentationTests/ContextCorrectionTests 22/22 PASS, .build/check-logs/uiux-reading-t01.log. 원문 fingerprint·그룹 고정·빈 문자열·AI 보호·legacy/손상 입력. 테스트 Markdown 기대값의 점 escaping을 기존 exporter 계약과 일치시킨 뒤 통과. 실제 UI 미측정.

- 별도 진단(2026-09-13): [현행 파일 재측정/오프라인 결합 비교](../../notes/uiux-reading/speaker-context-diagnosis.md). 최신 결합657토큰 미배정, 발화문단1,207. 원 Soniox 텍스트/시간 동일, 최신 통합과 P2 exclusive502구간 동일. 최대 교집합 후보 B는273/892로 감소하나 귀속 정확도 미검증. 토큰 단위 보완과 E1/E2 청취 비교가 다음 단계이며 앱 정책은 유지. 현재 원본55파일 비변경, 새 유료 호출/AI 보정 없음.
- 개인 용어·별칭·인물/조직 배경 지식과 참조 발췌의 현재 소비/한계, Qwen 컨텍스트와 실제 학습의 구분. 개인 프로필 UI/모델 fine-tuning은 이번 화면 승인과 분리.
- 게이트②: 2026-09-13 사용자 완성본 확인 완료. main merge/remote push/출시 승인과 별개인 로컬 앱 전달.

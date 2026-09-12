---
unit: storage-isolation
branch: work/m0-fixture-review
status: built
decisions_resolved: true
resume: ""
spec: "사용자 2026-09-12 이어서 진행 요청; notes/backend-audit/audit.md F-04/F-07; design00 하이브리드 채택 및 design02·03·04, library-script/operating-baseline 계약"
---

## 근거·의도

- 손상 파일과 정상 파일을 함께 스캔할 때 정상 항목을 계속 열고 실패 파일을 별도로 표시한다. 불명확한 접수 이력은 초기화하지 않는다. 검사 실행별 증거와 scratch 선택을 보존한다.
- 홈/appdev/repo 지침, spec/plan/build, 공통10종·공유 트리·수치·외부 미디어·워치독·Apple 툴체인·리뷰 종료·인라인 스크립트 규율 본문은 같은 세션의 확인본 재사용. 착수 규율 목록·설명과 지침 mtime 재확인. design/api/dev/schema/Swift 계약 재사용, 이번 저장·처리 코드와 관련 계약 실측. Codex 직접 구현.
- HEAD72fa62e, 승인된 branch 유지. 타 소유 dirty7(build 커맨드/README/Qwen evaluation/dev/m0·m1·m2 plan)은 보존·제외한다. 선행 독립 scratch 전체155/계약30/Debug PASS. 기존 check.sh signal11 실패는 F-07 대상이며 성공으로 바꾸지 않는다.

## 결정·영향 범위

- 조회 결과는 정상 항목+파일별 실패. 동일 ID가 둘 이상이면 모두 제외하고 명시한다. 손상/unsafe/삭제된 cache 항목을 정상으로 재사용하지 않는다. 폴더 자체의 접근 실패는 전체 조회 오류로 유지하며 Speeches 실패가 Scripts를 막지 않게 한다.
- Run 조회는 표시용 부분 성공과 실행용 세션별 완전성 검사를 분리한다. 손상/missing/symlink/중복 Run이 있는 session은 begin/resume/reuse 금지. 정상 타 session은 계속 사용. submitting/uploadSubmitting 접수 불명 복구와 명시적 재전사 동의 정책 유지.
- 읽기 정책 reading-v6, normalized/Script 저장 schema, 시간 Int64 µs, 화자/원문/수정/전송 동의는 변경하지 않는다(INV-01·06·08·09).
- check.sh는 실행별 로그를 새 폴더에 남기고 scratch를 명시 선택할 수 있게 한다. 실패 후 자동 재시도/캐시 삭제 없음. signal11 과거 crash와 이번 실행 증거를 대조하고 원인 미확정이면 그 한계를 기록한다.

## 수용 기준

- [x] AC-01 합성 임시 폴더의 정상+손상 Speech/Script, 중복 ID, symlink, 외부 bytes 변경을 파일별 격리. 정상 생성/교정/재열기, stale hash 거부와 원본 보존 검증.
- [x] AC-02 Run 상태의 손상/missing/symlink/중복을 표시하면서 정상 타 session 조회·재개 가능. 영향 session 제출·재개·재사용 차단, submissionUncertain 복구 후 자동 POST0 검증.
- [x] AC-03 앱에서 파일별 실패를 확인할 수 있고 정상 항목을 계속 열 수 있다. 폴더 자체 오류는 기존 목록 유지, 입력 저장 실패는 사람 입력 유지. 실제 정상 Script8본 및 hash14본 보존.
- [x] AC-04 check.sh의 독립 scratch 선택·실행별 성공/실패 로그 보존 검증. 계약/전체 테스트/Debug 빌드 실행과 signal11 진단 범위 기록. skip/실패를 성공으로 간주하지 않는다.
- [x] AC-05 0.4.6(16) Debug/Release 버전 동시 증가, 이전 앱 정상 종료·백업·설치 후 실제 실행 버전과 Script 열기 확인. 마이크/새 모델/API/정확도 미측정 구분.

## 작업

- T-01 완료 `1b295dd`: 조회 결과·저장/처리 실패 격리, 합성 회귀, 앱 연결. 실물 QA는 T-03.
- T-02 완료 `4c1f16f`: 검사 실행 경로·실패 로그 보존, crash 비교·전체 검사.
- T-03 완료: 앱 QA·0.4.6(16) 전달, AC/상태 정리.

## 종료·후속

- AC 축 한 번 검토 후 결함 영향 범위만 재검증한다. 실제 사용자 파일 손상·음성 전송·추론·학습·원격 push 없음.
- F-06 공통 normalizer, F-05 runtime 고정/학습, 화면 시안은 기존 순차 후속. signal11 원인 확정에 OS/컴파일러 변경이 필요하면 별도 범위로 남긴다.

## 검증 기록

- T-01 영향 검사 FileScan2/ReadingSnapshot3/LibraryJourney5/ManagedJourney15 = **25건 PASS** (14:03 KST, `.build/check-logs/storage-isolation-targeted-approved.log`). 합성 손상·중복·symlink·외부 변경/교정·재열기, 타 session 정상 재개, 영향 session 제출/재개/reuse 금지, 두 submitting 단계 접수 불명 복구 후 자동 API0 검증. 반복 손상 wav 스캔도 실패 import session을 누적하지 않는다.
- 계약 Python30 PASS, canonical Swift12200bytes 동일. 첫 실행은 홈 SwiftShims 캐시 sandbox 거부, 승인된 밖 실행. 테스트 작성 중 init/try 컴파일 오류와 URL 표현/fixture sourceRunId 오류는 수정했고 실패 로그를 별도 보존했다. 이 기록은 실제 음성/API 품질 검사가 아니다.

### T-02 검사 경로·crash 분리

- `bash scripts/check.sh --scratch-path .build/storage-isolation-final --log-root .build/check-logs/storage-isolation`: **backpressure OK, exit0, SKIP0**. 실제 계약30·Swift 계약 사본/왕복·전체160 테스트(실패0,14:06 KST)·Debug BUILD SUCCEEDED. 로그 `.build/check-logs/storage-isolation/run-20260912T050643Z-McUdy5/`, 환경/시작·종료/exit/모든 단계 로그 보존.
- 기본 scratch는 실행별 신규 `.build/check-scratch/run-*`. `--scratch-path` 지정 시에만 해당 경로 재사용. 로그는 `--log-root` 아래 매번 별도 `run-*`; 실패/정상/인터럽트 결과와 smoke compile/run 증거를 남기며 자동 삭제·재시도 없음. 강제 SIGKILL은 EXIT trap을 실행할 수 없으므로 result.txt 없이 부분 로그만 남을 수 있다.
- `python3 scripts/test_check_runner.py` **2건 PASS**, `bash -n` PASS. 합성 명령 어댑터로 exit11 실패를 주입한 뒤 다음 정상 실행에도 기존 모든 로그 bytes 불변, 공백 경로·명시 scratch·기본 scratch 독립·잘못된 인자 exit2 확인. 어댑터 검사는 Swift/앱 실제 성공 근거가 아니다. macOS Bash3 empty-array nounset 오류는 발견 후 `${SKIP[*]-}`로 수정했다.
- 보존된 과거 crash5개 비교: ConversionNotes 복사, ScriptCorrection? retain/validate, CodexCorrectionTests, URL.isFileURL에서 각각 발생. 같은 현상이라고 통합하거나 메모리 안전 원인을 확정하지 않았다.
- **재빌드 없이 동일 단일 테스트 비교**: `xcrun xctest -XCTest DamaManagedTests.ManagedJourneyTests/testRetranscriptionCreatesIndependentScriptAndTrashPreservesConnectedData <bundle>` 실행. 기존 `.build/reading-performance` 바이너리 SHA256 `51eedd66…55acf`는 exit139/SIGSEGV 재현. 원래·재현 crash 모두 `URL.isFileURL → FolderLibraryStore.safe → trashScript`, invalid address0x1e. 새 crash `xctest-2026-09-12-141731.ips`; ignored `storage-isolation-old-binary-replay.log` 보존.
- 같은0.4.5 package 코드의 기존 독립 `.build/reading-performance-final` 바이너리 SHA256 `5ddb264c…d4cf`는 동일 단일 테스트1건 PASS(0.081초), `storage-isolation-clean-binary-replay.log`. 이는 전체 테스트 순서 없이 실패 산출물에서 충돌한다는 증거이며, 빌드 산출물 차이와 연관된 범위로 좁혔다. 구체적인 incremental compiler/ABI/cache 결함은 미확정. 새 경로 PASS로 이전 FAIL을 지우거나 자동 재시도해서 성공으로 표기하지 않는다.

### T-03 실물·전달 (2026-09-12)

- 실제 Mac, Xcode26.6(17F113)/Apple Swift6.3.3. Debug/Release 버전0.4.6(16) 동시 증가. 전체 검사 후 앱의 canResume도 session 이력 차단을 반영했음을 확인했고, 미사용 processor binding 경고를 정리한 앱 부분만 재빌드 PASS (`.build/check-logs/storage-isolation-final-app.log`). 기존 deployment target/AppIntents 경고 유지. Release 빌드·공증은 미측정.
- 기존0.4.5(15) 정상 종료/프로세스 종료 확인, `.build/backups/DAMA-0.4.5-15-before-storage-isolation.app`에 실행 파일·debug dylib byte-equal 백업 후 `/Applications/DAMA.app` 설치. 최종 실행 About **DAMA Version0.4.6(16)** 확인, 기존 adhoc/linker-signed 유지. final 앱 binaries는 빌드와 byte-equal.
- CUA 실물 QA: ignored 임시 폴더의 합성 정상1개+중복2개+손상1개. 정상 대사3개를 열고 중복/손상은 **‘읽지 못한 파일·폴더3개’**에 각각 경로와 이유 표시 확인. 실제 사용자 파일을 손상시키지 않았다. 외부 API·모델 실행 없이 화면·AX와 합성 데이터 회귀를 검증했다.
- 원래 `/Users/gazitofu/DAMA/Scripts`로 복원 후 재실행: **Script8개, 파일 조회 오류0, 검수 기록1건/원음 확인0건, 사건259개**. 실제 원본/사람 수정/원응답/분석 음원 **14파일 SHA256 불변**, 기존 Script 집합8개 동일. `.build/diagnostics/storage-isolation/verify-delivery.py`/`delivery-verification.json` 검산.
- 폴더 전체 접근 실패/입력 저장 실패 때 이전 값 유지와 다른 폴더 계속 조회는 앱 연결 코드 검토, 손상 index에서도 정상 Script 조회는 합성 테스트로 확인. 실제 계정의 폴더 권한을 훼손하는 실기기 실험은 하지 않았다.
- 마이크·새 전사/AI 교정·원음 청취 정답·한국어 정확도·학습·Release 실행은 미측정. 이 유닛은 저장 실패 격리와 검사 증거 개선 완료이며 signal11 근본 원인 해결·품질 승격 선언이 아니다. 원격 push 없음, 최종 타 소유 dirty7만 유지.

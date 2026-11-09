# ssot/dev.md — 환경·명령·backpressure 정본

## 1. 실측 환경 (2026-09-09)

| 축 | 값 |
|---|---|
| 기기 | Apple Silicon (`uname -m` = arm64) |
| OS | macOS 26.6.2 (build 25G83) |
| Xcode | 26.6 (17F113) |
| SDK / 앱 타깃 | macOS SDK 26.5 / 최소 macOS 26.6.2, arm64 (M0 plan 확정) |
| Swift | 6.3.3 (swiftlang-6.3.3.1.3), target `arm64-apple-macosx26.0` |
| python3 | 3.9.6 (시스템). homebrew python 없음 |
| jsonschema | 4.25.1 (설치됨 → schema 검사 skip 아님) |
| 여유 공간 | 644 GB |

설계 문서(01)의 macOS 15 가정은 M0 plan D-01로 대체됐다. 사용자 지정 최소 버전은 macOS 26.6.2이며 주 기기는 M5 MacBook Pro다. CPU 모델은 샌드박스 `sysctl` 거부로 미실측이다. Xcode 버전과 SDK 버전은 별개다.

`Packages/DamaCore`와 `Dama.xcodeproj`가 구현되어 두 축 모두 실제 실행된다. 아래 결과는 합성 데이터와 서명 없는 Debug 컴파일 층위다. SKIP은 "통과"가 아니라 "안 쟀음"이다.

## 2. backpressure

```sh
bash scripts/check.sh
```

4단계. 1·2단계(계약·Swift 컴파일)와 3단계 pure test는 샌드박스 안에서 끝나므로 태스크마다 실행하고 통과 전 다음 태스크로 가지 않는다. 4단계 앱 빌드와 `xcodebuild test`·실기기 확인은 plan이 정한 QA 여정 경계에서 메인이 1회 실행한다. 수탁자가 결과 파일에 명령·출력을 남긴 층은 주체가 바뀌었다는 이유로 재실행하지 않는다. 음성 업로드·유료 API 호출·마이크 접근은 없다.

| 단계 | 내용 | 현재 |
|---|---|---|
| 1 | 합성 계약·회귀 29건 (`scripts/validate_contracts.py`) | 통과 |
| 2 | Swift 6 데이터 계약 컴파일 + normalized 왕복 + 명시적 null 보존 | 통과 |
| 3 | `swift test` (check.sh의 repo-local 캐시·키체인 비활성 인자 사용) | 63건 통과 |
| 4 | Dama scheme Debug, `CODE_SIGNING_ALLOWED=NO` | 통과; 실제 앱 실행 미측정 |

개별 실행:

```sh
python3 scripts/validate_contracts.py          # 29 tests
mkdir -p .build/modulecache
DAMA_SMOKE_DIR="$(mktemp -d "$PWD/.build/smoke.XXXXXX")"
swiftc -swift-version 6 -module-cache-path "$PWD/.build/modulecache" ssot/contracts/DomainContracts.swift scripts/SmokeCheck.swift -o "$DAMA_SMOKE_DIR/contract-check"
"$DAMA_SMOKE_DIR/contract-check" fixtures/normalized-transcript.json fixtures/pyannote-job-succeeded.synthetic.json "$DAMA_SMOKE_DIR/roundtrip.json"
```

### Codex 위임 시 (실측 이월)

규율 [[rule-apple-toolchain-sandbox]] (2026-09-09 승격, GAIA·Dama 2회 관측). Apple 툴체인은 cwd 밖 홈 자원에 쓴다. 두 부류를 구분한다.

- **경로 이전으로 해결됨**: `swiftc`의 clang 모듈 캐시. 기본값 `~/.cache/clang/ModuleCache`(실측 91 MB)에 쓰지 못해 Codex 샌드박스에서 exit 1. `scripts/check.sh`가 `-module-cache-path .build/modulecache`로 고정해 해소했다(2026-09-09 실측 · repo 안 30 MB 생성 · `.build/`는 gitignore). **이 플래그를 빼지 마라.**
- **해결 안 됨**: `xcodebuild test`는 키체인·testmanagerd에 접근한다. `-derivedDataPath`로도 돌지 않는다(GAIA gaia-launcher 2026-09-08). 코드 서명·공증도 같은 부류다. 발주 계약에 «테스트 실행은 메인»을 고정하고 메인이 밖에서 재실행한다.
- Codex 쪽 빌드·테스트 실패는 코드 결함으로 단정하기 전에 샌드박스 경로 거부를 먼저 배제한다(`~/.cache`·`~/Library`·키체인 접근 여부).
- Codex는 이 저장소의 `CLAUDE.md`를 project doc으로 자동 주입받는다 (`~/.codex/config.toml`의 `project_doc_fallback_filenames = ["CLAUDE.md"]`). `AGENTS.md`는 두지 않는다. 절차는 `.claude/commands/`를 파일로 읽는다 (`~/.codex/AGENTS.md` 규약).
- 재개 후 Codex는 이 세션에서 직접 구현한다. Claude가 실제 위임할 때만 공통 규칙의 여정 단위 발주·결과 기록을 적용한다. 기존 T별 발주문은 이력이며 하위 CLI 실행 지시가 아니다.

### M0 앱 여정 자동 검사 기록 (2026-09-09)

- T-05의 Core 63건 및 4단계 PASS 기록을 이월했다. T-06·07 통합 후 `bash scripts/check.sh`는 exit 0, 계약 29건·Core 63건·Debug 모두 PASS, SKIP 없음.
- 검색 변경 시 선택 해제·저장 상태 문구 보완 후에는 check.sh 4단계와 동일한 `xcodebuild ... build`만 실행했다. 샌드박스 안 첫 시도는 exit 74: `~/Library/Logs/CoreSimulator/...` 쓰기 거부 및 package 해석의 `sandbox_apply: Operation not permitted`. 소스 컴파일 전에 중단된 **환경 제한**이다.
- 승인 후 동일 명령을 샌드박스 밖에서 재실행해 PASS했다. 창 delegate의 메인 액터 지정 보완도 앱 컴파일만 다시 실행해 exit 0, `BUILD SUCCEEDED` 확인; 해당 소스 경고는 사라졌다. 캐시·DerivedData는 `.build/` 아래, `CODE_SIGNING_ALLOWED=NO` 유지. `xcodebuild test`·앱 실행·키체인·서명·공증은 수행하지 않았다.
- 남은 도구 경고: SDK 26.5의 deployment target 지원 범위는 26.5.99까지여서 사용자 지정 26.6.2를 경고한다. compile/link는 성공했으며 타깃은 유지했다. AppIntents 의존성이 없어 metadata 추출을 생략한다는 경고도 있다. 실제 실행·배포 호환성은 미측정이다.
- 로그: `.build/check-logs/{contracts,contract-copy,swift-test,xcodebuild}.log`; 경로 거부 원본 `xcodebuild-sandbox-denied.log`. 앱 산출물 `.build/xcode/Build/Products/Debug/DAMA.app`.
- 원본 fixture와 실제 앱 번들 리소스 SHA256 모두 `37e41f2055156d2b591cd10ba25165b5d24c1cbb23b2edd41710594d047bfdf8`. Swift 계약과 Core 사본 모두 `7be81c3301184397b14b284019946c66394750bb5cdbce2c1234504642791535`.
- 실제 Mac의 창 조작·재시작·VoiceOver·밝은/어두운 모드는 미측정이다. [README](../README.md)의 단일 확인 여정과 상태 정본 `versions/m0-fixture-review/plan.md`에 이어서 기록한다.

## 3. 스펙 문서 빌드

```sh
python3 ssot/doc-template/_build.py notes/<유닛>/<유닛>.src.html
```

요구: python3 + fonttools + brotli. `ssot/doc-template/fonts/`에 실제 폰트 파일이 없어(manifest만 이식) 폰트 임베드는 현재 동작하지 않을 수 있다. GAIA에서 이식한 미해결 항목이며 첫 `/spec`에서 실측한다.

## 4. 검증 층위 (섞지 않는다)

06 문서의 표를 이 저장소 기준으로 옮긴 것이다. 보고할 때 어느 층까지 했는지 반드시 구분한다.

| 층 | 무엇을 | 어디서 | 지금 |
|---|---|---|---|
| 계약 | JSON schema, 참조·시간·순서 불변식 | `scripts/check.sh` 1·2 | 통과 |
| pure logic | 계약 로더·시간·수정·Turn 장벽·내보내기 | DamaCore 테스트 | 63건 중 해당 suite 통과; 모델 알고리즘 구현·품질 검증 아님 |
| HTTP mock | upload/submit/poll, auth 분리, 재시도 | URLProtocol mock | 미착수 |
| 저장 fault injection | 중간 저장, active pointer, 종료 복구 | 임시 디렉터리 | 19 repository + 16 editing 테스트에 포함; 전원 손실 검증 아님 |
| 앱 컴파일 | 메뉴바·검수·설정·native 저장 창 연결 | 서명 없는 Debug | 통과; 실제 조작·접근성은 미측정 |
| 실기기 | 마이크·권한·메뉴바·원음 seek·동시 부하 | 이 Mac | 미착수 |
| 실제 모델 품질 | 한국어 E1/E2/누락/unknown/검수시간 | 동의받은 실제 회의 | 미착수 |

## 5. 외부 전제 (사용자 실행 항목)

| 항목 | 상태 | 필요 시점 |
|---|---|---|
| pyannote.ai 계정·API 키 | 사용자 가입·키 보유 확인. 키 값 미수신, 앱 등록·유효성·실호출 미검증 | 설계 T-008 실연동 |
| 마이크 권한 (TCC) | 미요청 | 설계 T-005 |
| 코드 서명 identity | 미확인 | 배포 시 |
| 평가용 녹음 파일 | 사용자 제공 M4A, AAC mono 16kHz, 실제 96분53.5초. 전체 로컬 반입·변환·원본 해시 불변 확인. 첫5분 샘플 준비; 언어·화자 수·외부 전송 동의 미확인 | M1 파일 반입·M2 실연동·게이트 G-07 |

키가 없어도 fixture·mock으로 P0 대부분을 만들 수 있다. **키 부재를 이유로 구현을 멈추지 않는다.** 실호출·음성 전송은 건별 사용자 승인 항목이다.

## 6. 테스트 데이터 취급

`fixtures/`는 전부 합성 데이터이며 실제 회의·음성·API 응답이 아니다. 화자 정확도의 근거로 쓰지 않는다. **실제 녹음 파일은 저장소에 넣지 않는다.** `.gitignore`가 `*.wav`·`*.m4a`·`*.caf`·`*.mp3`·`*.flac`·`Sessions/`·`local-test-audio/`를 막고 있다.

## 7. M1·M2 추가 실측 (2026-09-09)

- 이전 절 M0 기록은 그 시점의 결과다. 현행 코드·잔여 AC는 `versions/m1-recording-safety/plan.md`, `versions/m2-managed-processing/plan.md`가 정본.
- Core 63 + managed 8 = 71건, `--filter 'ManagedJourneyTests|DamaCoreTests'` PASS (`.build/check-logs/m2-core-managed-final.log`). HTTP는 actor transport mock 및 URLProtocol 모의만. 키체인·실제 원격 접속 없음.
- 오디오 6건은 합성 PCM→실제 CAF/WAV/M4A 저장·read·복구·변환. 샌드박스에서 5건 PASS, M4A 생성은 Apple AAC encoder `fmt?` (1718449215) 오류. 같은 `--skip-build --filter AudioJourneyTests.testM4AImportAndUnsupportedInput` 외부 실행 PASS. 코덱 서비스 접근 제한으로 구분, skip 없음. 이 코덱 검사는 pure Core 검사와 다른 층이다.
- M1·M2 Debug build는 안쪽 package 해석 `sandbox_apply: Operation not permitted` exit 74가 확인돼 외부에서 `CODE_SIGNING_ALLOWED=NO`로 수행. M2 최종 `BUILD SUCCEEDED`, SDK target/AppIntents 기존 경고 유지. `.build/check-logs/m2-xcodebuild.log`.
- 계약 29건 PASS, Swift 6 SmokeCheck·명시적 null·confidence map 왕복 PASS. Core 계약 사본 SHA256 `7be81c3301184397b14b284019946c66394750bb5cdbce2c1234504642791535` 불변.
- 앱 키 입력·전송 동의·마이크·10분/2시간·실제 한국어 정확도·서명된 entitlement 동작은 미측정. 앱 실행·키 접근 없음. 사용자 실파일은 후속 로컬 반입·변환을 완료했으며 아래 및 M1·M2 plan에 별도 기록한다. 이 build 결과로 배포 호환성을 선언하지 않는다.
- 패키지 위치는 유지하며 제품을 DamaCore(Foundation), DamaAudio(Apple 오디오), DamaManaged(HTTP·Keychain)로 나눴다. `check.sh` 전체는 사용자 터미널에서 77개 package tests를 실행한다. Codex 내부에서는 이미 통과한 층을 이유 없이 반복하지 않고, 코덱·Xcode 제한 층만 외부 실행한다.
- 로컬 커밋: M1 저장 `d989895`, 녹음 UI `7ca0075`, M2 처리 `e131b12`, 동의·키·검수 연결 `af77a5a`. 최종 branch `work/m0-fixture-review`. 혼합 문서 `.claude/commands/build.md`, 이 파일, M0 plan은 사용자 지시에 따라 미커밋 보존; staged 없음. 원격 push 없음.
- 사용자 실파일: 현행 AudioLibrary를 호출해 93,016,000frames 전체 디코딩·복사 해시·원본 불변·동일 길이 분석 WAV 확인. 샌드박스 AAC decoder 1718449215 오류 후 승인된 외부 동일 검사 PASS. 첫5분 WAV 준비, 음성은 `/private/tmp/dama-audio-pilot.nkeaOi/`에만 보존. API·키 접근 없음, 외부 전송 승인은 별도 대기. 세부 수치는 M1·M2 plan 정본에 기록.

---

부칙: 2026-09-09 최초 작성 (환경 실측 · check.sh 신설).
부칙: 2026-11-06 (usage-bundle1 /ship) 실화면 QA 환경 실측: 이 세션 터미널은 접근성 있음·화면 기록 없음(`screencapture` 실패) → 픽셀은 합성 QA 앱 전용 `QASnapshot`(분산 알림 `com.gazitofu.Dama.ReadingQA.snapshot`, `<fixture>/qa-snapshots/`). 이 셸의 `defaults com.gazitofu.Dama`는 앱과 다른 설정 저장소를 보므로 앱 설정은 `defaults … ~/Library/Preferences/com.gazitofu.Dama.plist` 경로 도메인으로만 바꾼다. 접근성은 현재 Space의 창만 보인다.
부칙: 2026-11-07 (usage-bundle2 /ship) check.sh 경로 표기 실측: 대소문자 무시 볼륨에서 소문자 cwd(`/Users/gazitofu/developer/dama`)로 돌리면 같은 `.pcm`이 두 표기로 잡혀 `module '_DarwinFoundation1' is defined in both`로 Swift 계약·xcodebuild가 실패했다. `/bin/bash` 3.2 builtin `pwd -P`는 표기를 바꾸지 않고 `/bin/pwd -P`(getcwd)만 디스크 표기를 준다 → check.sh가 시작 때 `cd "$(/bin/pwd -P)"`로 맞춘다(F-01, 소문자 cwd·대문자 절대경로 모두 PASS). 도구 실측 Swift 6.4.2 · Xcode 27.2(27B52) · arm64-apple-macosx27.2.0(2026-11-06, §1 기록과 다름).
부칙: 2026-11-09 (correction-turn-isolation /ship) 실기기 실측: ① 백그라운드 세션의 `osascript` System Events는 자동화는 통과해도 손쉬운 사용 권한이 없으면 «osascript is not allowed assistive access (-25211)»로 조작이 막힌다(11-07, 11-06 부칙의 «접근성 있음»은 세션마다 다르다). 권한이 통과한 뒤에도 메뉴바 상태 항목은 AX 트리에 없어(`AXExtrasMenuBar` 없음 · Control Center 0건) 버전 툴팁은 사용자 관측으로만 확인된다(11-09). ② 실제 Codex CLI 교정 `context-correction-7`이 실데이터 28.0분 결합본에서 형식 실패 2회(종료 코드 0, 하위 원인 기록 없음 · F-05) 뒤 이어서 교정으로 completed 8/8(11-09, 사용자 실행). 교정 품질은 안 쟀다.

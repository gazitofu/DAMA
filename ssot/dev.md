# ssot/dev.md — 환경·명령·backpressure 정본

## 1. 실측 환경 (2026-09-09)

| 축 | 값 |
|---|---|
| 기기 | Apple Silicon (`uname -m` = arm64) |
| OS | macOS 26.6.2 (build 25G83) |
| Xcode | 26.6 (17F113) |
| Swift | 6.3.3 (swiftlang-6.3.3.1.3), target `arm64-apple-macosx26.0` |
| python3 | 3.9.6 (시스템). homebrew python 없음 |
| jsonschema | 4.25.1 (설치됨 → schema 검사 skip 아님) |
| 여유 공간 | 644 GB |

설계 문서(01)는 "macOS 15 이상 1차 지원"을 가정했다. 실제 개발기는 macOS 26이므로 **deployment target 결정은 `/plan`의 D-NN**이다. 최신 SDK로 빌드하되 최소 지원 버전을 낮게 잡으면 availability 분기가 늘어난다. 배포 대상이 본인 Mac 1대라면 target을 개발기에 맞추는 편이 단순하다.

`swift test`·`xcodebuild`는 저장소에 프로젝트가 생긴 뒤(설계 T-001) 유효하다. 그 전에는 `scripts/check.sh`가 **SKIP으로 표시**하고 통과시킨다. SKIP은 "통과"가 아니라 "안 쟀음"이다.

## 2. backpressure

```sh
bash scripts/check.sh
```

4단계. 태스크마다 실행하고 통과 전 다음 태스크로 가지 않는다. 음성 업로드·유료 API 호출·마이크 접근은 없다.

| 단계 | 내용 | 현재 |
|---|---|---|
| 1 | 합성 계약·회귀 29건 (`scripts/validate_contracts.py`) | 통과 |
| 2 | Swift 6 데이터 계약 컴파일 + normalized 왕복 + 명시적 null 보존 | 통과 |
| 3 | `swift test --package-path Packages/DamaCore` | SKIP (미생성) |
| 4 | `xcodebuild -project Dama.xcodeproj -scheme Dama` | SKIP (미생성) |

개별 실행:

```sh
python3 scripts/validate_contracts.py          # 29 tests
TMP="$(mktemp -d)"
swiftc -swift-version 6 ssot/contracts/DomainContracts.swift scripts/SmokeCheck.swift -o "$TMP/contract-check"
"$TMP/contract-check" fixtures/normalized-transcript.json fixtures/pyannote-job-succeeded.synthetic.json "$TMP/roundtrip.json"
```

### Codex 위임 시 (실측 이월)

규율 [[rule-apple-toolchain-sandbox]] (2026-09-09 승격, GAIA·Dama 2회 관측). Apple 툴체인은 cwd 밖 홈 자원에 쓴다. 두 부류를 구분한다.

- **경로 이전으로 해결됨**: `swiftc`의 clang 모듈 캐시. 기본값 `~/.cache/clang/ModuleCache`(실측 91 MB)에 쓰지 못해 Codex 샌드박스에서 exit 1. `scripts/check.sh`가 `-module-cache-path .build/modulecache`로 고정해 해소했다(2026-09-09 실측 · repo 안 30 MB 생성 · `.build/`는 gitignore). **이 플래그를 빼지 마라.**
- **해결 안 됨**: `xcodebuild test`는 키체인·testmanagerd에 접근한다. `-derivedDataPath`로도 돌지 않는다(GAIA gaia-launcher 2026-09-08). 코드 서명·공증도 같은 부류다. 발주 계약에 «테스트 실행은 메인»을 고정하고 메인이 밖에서 재실행한다.
- Codex 쪽 빌드·테스트 실패는 코드 결함으로 단정하기 전에 샌드박스 경로 거부를 먼저 배제한다(`~/.cache`·`~/Library`·키체인 접근 여부).
- Codex는 이 저장소의 `CLAUDE.md`를 project doc으로 자동 주입받는다 (`~/.codex/config.toml`의 `project_doc_fallback_filenames = ["CLAUDE.md"]`). `AGENTS.md`는 두지 않는다. 절차는 `.claude/commands/`를 파일로 읽는다 (`~/.codex/AGENTS.md` 규약).
- 병행 발주는 메인이 인터페이스(타입·함수 스텁)를 선커밋해 파일 소유를 가른다. 발주문은 `notes/{유닛}/codex/tNN.md`로 남기고 인라인 반환은 인정하지 않는다.

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
| pure logic | 후보 점수, overlap, marker, Turn 병합 | DamaCore 테스트 | 미착수 |
| HTTP mock | upload/submit/poll, auth 분리, 재시도 | URLProtocol mock | 미착수 |
| 저장 fault injection | 중간 저장, active pointer, 종료 복구 | 임시 디렉터리 | 미착수 |
| 실기기 | 마이크·권한·메뉴바·원음 seek·동시 부하 | 이 Mac | 미착수 |
| 실제 모델 품질 | 한국어 E1/E2/누락/unknown/검수시간 | 동의받은 실제 회의 | 미착수 |

## 5. 외부 전제 (사용자 실행 항목)

| 항목 | 상태 | 필요 시점 |
|---|---|---|
| pyannote.ai 계정·API 키 | **없음** (2026-09-09) | 설계 T-008 실연동 |
| 마이크 권한 (TCC) | 미요청 | 설계 T-005 |
| 코드 서명 identity | 미확인 | 배포 시 |
| 한국어 평가용 실제 회의 파일 (동의 확보) | 미준비 | 게이트 G-07 |

키가 없어도 fixture·mock으로 P0 대부분을 만들 수 있다. **키 부재를 이유로 구현을 멈추지 않는다.** 실호출·음성 전송은 건별 사용자 승인 항목이다.

## 6. 테스트 데이터 취급

`fixtures/`는 전부 합성 데이터이며 실제 회의·음성·API 응답이 아니다. 화자 정확도의 근거로 쓰지 않는다. **실제 녹음 파일은 저장소에 넣지 않는다.** `.gitignore`가 `*.wav`·`*.m4a`·`*.caf`·`*.mp3`·`*.flac`·`Sessions/`·`local-test-audio/`를 막고 있다.

---

부칙: 2026-09-09 최초 작성 (환경 실측 · check.sh 신설).

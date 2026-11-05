---
unit: m0-fixture-review
branch: work/m0-fixture-review
status: building
decisions_resolved: true
resume: "기본 수정→저장→재실행→내보내기는 사용자 확인 완료, 재검사 없음. M0 미측정 AC는 유지. 사용자 후속 구현 지시로 M1·M2 코드와 합성/mock 검증 진행; 각각의 plan 참조. 남은 실제 UI·접근성만 한 묶음으로 확인."
spec: notes/review-workspace/review-workspace.src.html
spec_sections: "02 검수·수정·내보내기; 03 검수 창; 04 검수 관련 규격·문구; 05; 06"
deployment_target: "26.6.2"
architecture: arm64
primary_device: "M5 MacBook Pro (사용자 지정)"
created: 2026-09-09
updated: 2026-09-09
---

## 근거

- 사용자 2026-09-09: `/plan 진행하자`; 최소 OS `macOS 26.6.2`, 주 기기 M5 MacBook Pro 명시. 후속 ‘구현 들어가자’로 이 계획의 /build 승인.
- `notes/review-workspace/review-workspace.src.html` §02–06: 계획 입력 채택, `#s-verdict[data-state=closed]`. 사용자 직접 시각 검수 완료 진술은 없음. 에이전트 브라우저 시각 검수는 file URL 정책으로 미완료.
- `/Users/gazitofu/.codex/AGENTS.md`, `/Users/gazitofu/CLAUDE.md`, `/Users/gazitofu/Vault/appdev/CLAUDE.md`, `CLAUDE.md`, `README.md`, `/Users/gazitofu/Vault/appdev/Dama/_index.md`: 세션에서 본문 열람. 인덱스 다음 단계는 화면 spec 후 M0 plan.
- `.claude/commands/spec.md`, `.claude/commands/plan.md`, `.claude/commands/build.md`: 본문 열람. 계획은 300줄·10태스크 이내, 구현·fixture·계약 변경 금지.
- `ssot/design/00_README.md`: 하이브리드 채택. 02·03·04와 contracts는 기존 컨펌된 정본.
- `ssot/design/01_PRODUCT_AND_UX.md` FR-06–09·§7–9, `02_ARCHITECTURE_AND_STORAGE.md` §3·7·9, `03_ENGINE_AND_API_CONTRACT.md` §3·4, `04_DATA_AND_RECONCILIATION.md` §2·3·8: 세션 본문 열람.
- `ssot/design/05_IMPLEMENTATION_PLAN.md` M0·설계 T-001–003, `06_TEST_AND_RELEASE.md` RC-01·03·07·11–16 및 G-03·04·06, `07_SECURITY_AND_DECISIONS.md` §1·2·6: 세션 본문 열람. 설계 티켓 번호와 아래 T-NN은 별도 체계.
- `ssot/api/pyannote-verified.md`, `ssot/dev.md`, `ssot/tone/review-workspace.md`: 본문 열람. 공급자 문서 주장은 이번 턴에 웹 재검증하지 않음; M0는 외부 호출 없음.
- `ssot/contracts/DomainContracts.swift`와 `ssot/contracts/transcript.v1.schema.json`: 이번 /plan에서 재열람. 타입·함수 인용은 아래 실측 계약 절 참조.
- `fixtures/README.md`, `fixtures/normalized-transcript.json`, `fixtures/pyannote-job-succeeded.synthetic.json`: 직독. normalized는 P1 합성, vendor는 별도 DTO 목적; 동일 실제 Run의 변환 전후로 취급하지 않음.
- `scripts/check.sh`, `.gitignore`, `ssot/doc-template/_build.py`: 세션 본문 열람. 폰트 manifest는 `sets: {}`; HTML은 시스템 서체 사용.
- 규율 경로 `/Users/gazitofu/.claude/projects/-Users-gazitofu/memory/`: 이번 턴 rule-*.md 21개의 파일명·name·description 재탐색. 아래 17개 본문은 이 세션에서 읽었으며 중복 열람은 생략.
- 필수 14종: `rule-purpose-first.md`, `rule-ambiguous-instructions.md`, `rule-scope-stop.md`, `rule-gate-hygiene.md`, `rule-measurement.md`, `rule-negative-claims.md`, `rule-carryover-remeasure.md`, `rule-verify-at-consumption.md`, `rule-delegation-artifacts.md`, `rule-destructive-writes.md`, `rule-shared-tree-commits.md`, `rule-numeric-test-integrity.md`, `rule-external-media-verify.md`, `rule-longrun-watchdog.md`.
- 보충: `rule-apple-toolchain-sandbox.md`(검증 주체), `rule-inline-script-file-exec.md`(문서 스크립트), `rule-sort-direction-concrete-pair.md`(이슈 이동 순서).

## 의도

M0는 합성 normalized 데이터로 검수 창 → 화자·텍스트·이슈 수정 → 영속 저장 → 재실행 → JSON/TXT 내보내기의 수직 경로를 만든다.
실제 녹음·실음성 재생·pyannote 처리 없이도 데이터 보존과 수정 범위를 검증한다. M0 완료는 녹음 앱·한국어 정확도·P0 전체 완료가 아니다.

## 영향 범위

| 경로 | /plan 착수 실측 | /build 허용 변경 |
|---|---|---|
| `Dama.xcodeproj/`, `App/`, `UI/`, `Resources/` | 없음 | macOS 앱·공유 Dama scheme·검수 UI·fixture 전용 진입점 |
| `Packages/DamaCore/` | 없음 | Foundation 중심 Core, Swift 단위 테스트, 저장·편집·내보내기 |
| `ssot/contracts/` | Swift·schema 존재 | 원본 수정 금지. 제품용 파생 사본은 원본과 바이트 일치 검사 |
| `fixtures/` | 합성 JSON 3종·README | 기존 파일 수정 금지; tests에서 메모리 복사·변형 |
| `scripts/check.sh` | 계약·Swift smoke 실행, Core·app 경로 존재 시 실행 | 캐시 플래그 유지, 파생물 drift 검사, 서명 없는 Debug 컴파일 층위 명시 |
| `scripts/` | 기존 검사·문서 빌더 존재 | 필요할 때 계약 파생물 동기화·검사만 추가 |
| `README.md`, `ssot/dev.md` | 앱 없음·2축 SKIP 설명 | 구현 후 실제 실행 명령·측정 결과만 갱신 |
| `notes/m0-fixture-review/codex/` | 없음 | /build에서 발주 계약·T별 발주·결과 파일 생성 |
| `versions/m0-fixture-review/plan.md` | 이번 요청에서 신규 | 상태·AC·resume의 유일한 정본 |

- 선행 스펙 미커밋분은 이 세션 소유 2파일만 존재했음. 문구 편입 후 `15d09d2` 로컬 커밋, clean 확인 후 작업 브랜치 생성. 타 세션 변경분·원격 없음.
- `notes/review-workspace/`는 공유 화면 스펙이다. M0 유닛은 frontmatter `spec`으로 참조하며 동일 역할의 스펙 사본을 만들지 않는다.
- `ssot/design/` 원본 채택 계약과 전사 임계값·API 요청은 이 유닛에서 변경하지 않는다.

## 환경·사전 검사

| 축 | 2026-09-09 이번 턴 결과 |
|---|---|
| `sw_vers` / `uname -m` | macOS 26.6.2 (25G83) / arm64 |
| 주 기기 | M5 MacBook Pro: 사용자 지정. `sysctl -n machdep.cpu.brand_string`은 Operation not permitted로 실측 못 함 |
| `xcodebuild -version` / `swift --version` | Xcode 26.6 (17F113) / Swift 6.3.3 |
| `swiftc -print-target-info -target arm64-apple-macos26.6.2` | exit 0; triple 인식. 실제 앱 link·실행 검증은 아님 |
| `df -h .` | 여유 644Gi |
| `bash scripts/check.sh` | 샌드박스 안 exit 0: 합성 29건 PASS, Swift 6 계약·왕복 PASS |
| SKIP | Core 유닛 테스트: Packages/DamaCore 없음; 앱 build: Dama.xcodeproj 없음. 두 축 모두 안 쟀음 |
| 브랜치 | work/m0-fixture-review. 원격 없음; pull·push 없음 |

## 실측 계약과 구현 선택

### 원본 계약: 이미 존재하는 선언

```swift
// ssot/contracts/DomainContracts.swift:14,270–272
public typealias Microseconds = Int64
public protocol TranscriptRepository: Sendable {
    func load(sessionId: String, revisionId: String?) async throws -> TranscriptDocument
    func commitRevision(_ document: TranscriptDocument) async throws
}
```

- `TranscriptDocument`(200행)는 schemaVersion/sessionId/runId/durationUs/language/provenance/speakers/diarization/exclusiveDiarization/words/turns/reviewIssues/revision을 가진다.
- `TranscriptWord`(54행): text와 editedText, modelSpeakerId와 speakerId, alignmentScore, timingOrigin 분리. nullable 필드는 JSON null로 직렬화하며 생략하지 않는다.
- `DiarizationInterval.confidence: [String: Double]?`(28행), `IssueStatus = open/resolved/acknowledged`(130행). `IssueKind`에 result_expired는 없다(124행).
- `PyannoteJobDTO.status: String`(239행): unknown 문자열 보존. 같은 값의 UI 상태를 알려진 성공으로 추정하지 않는다.
- `TranscriptEngine`(263행)의 실제 process 함수는 M0에서 구현하거나 호출하지 않는다. 합성 문서를 fixture loader로 읽고 provider 성공 상태로 가장하지 않는다.
- 구조체에 명시적 public memberwise initializer가 없음: 같은 Core 모듈 내부에서 생성하고, 앱에 필요한 생성 경로만 별도 factory/extension으로 제공. 원본 Swift 계약 파일 편집 금지.

### M0에서 확정하는 구현 경로

- 앱 `Dama`, scheme `Dama`, Core library `DamaCore`, bundle ID `com.gazitofu.Dama`, Swift 6 모드, arm64, 최소 macOS 26.6.2. 외부 package·Python 런타임·STT 제품 의존성 없음.
- SwiftPM 컴파일 사본 `Packages/DamaCore/Sources/DamaCore/DomainContracts.swift`는 ssot 원본의 결정적 파생물. 동기화 전 수동 변경 여부를 검사하고 drift가 있으면 실패. 원본·파생물을 각각 손 편집하지 않는다.
- 앱은 로컬 DamaCore package에 의존. 프로젝트 파일은 저장소에 직접 보존하고 미설치 생성기를 새 필수 전제로 삼지 않는다.
- Debug에서 명시적으로 선택한 ‘합성 테스트 데이터 열기’만 fixture를 복사한다. Release/default 경로는 fixture 자동 로드·가짜 녹음·가짜 서버 상태 없음. 처음에는 빈 상태와 미지원 안내.
- 모든 합성 실행은 `isSynthetic=true`와 기존 provenance를 보존. M0는 normalized P1 예시를 P0 결과로 재라벨링하지 않는다.
- FileSessionRepository는 actor. FileManager가 반환한 Application Support 아래 앱 namespace를 사용하고 tests는 임시 root를 주입. ID를 검증 없이 파일 경로에 연결하지 않음.
- 저장: 새 revision 임시 파일 → decode/불변식 검증 → close/rename → 마지막 active pointer 갱신. 기존 revision·raw·model 파일을 덮어쓰지 않음. pointer 전 실패 시 이전 active 유지.
- load(nil)는 유효 active revision. pointer가 손상됐으면 마지막 검증된 revision 복구와 복구 안내를 반환하는 앱 내부 결과 경로를 둔다. 원본 프로토콜 signature는 유지.
- 편집은 현재 revision 값의 복사본에 적용. 선택 Word의 speakerId/assignmentSource만 변경하고 modelSpeakerId는 보존. 기존 Turn 경계·marker는 병합하지 않고 필요할 때 해당 Turn 내부를 화자별로 분할.
- 이름은 현재 Run의 Speaker.displayName만 변경. 단일 Word 텍스트 변경은 editedText와 timingOrigin=inheritedUnaligned. 원문 text·prefix 유지. 다중 Word 텍스트 일괄 대체는 비활성.
- Turn 수동 분리는 Word 경계만 허용하고 새 revision의 Turn 배열에 보존. 이후 편집도 기존 Turn 경계를 유지하므로 재실행 뒤 합쳐지지 않음.
- 이슈 ‘확인함’은 status=acknowledged만 변경. speakerId·marker·다른 이슈는 보존. 이슈 확인만으로 Turn.reviewed를 자동 확정하지 않음.
- 저장 중 편집·Undo·export를 직렬화/비활성화. Undo/Redo는 변경 전후 snapshot을 새 revision으로 저장하고 이전 revision은 보존. 저장 실패 시 dirty 변경·오류를 유지하고 재시도/변경 취소 제공.
- 내보내기 대상은 현재 표시 판. 자동본 선택 시 immutable model을 읽음. JSON은 계약 전체, TXT는 시간·화자·marker·불확실성 유지. 각 파일은 사용자가 선택한 경로에 저장.
- 신규 helper 이름·세부 signature는 T-01에서 실제 Swift 모듈 경계를 확인해 발주 계약에 고정. 여기서 미실측 SDK signature를 만들어내지 않는다.

## 수용 기준

- [x] AC-01 프로젝트: DamaCore의 pure tests와 Dama Debug 컴파일 성공. module cache `.build/modulecache` 고정. 파일 경로 존재에 따른 SKIP 2개가 M0 완료 시 남지 않음. 서명 없는 compile을 배포 검증으로 표시하지 않음.
- [x] AC-02 계약: 원본 schema와 Swift 파생물 일치; normalized 재인코딩의 모든 required nullable 키 존재. unknown provider status 문자열 보존. d4 confidence 합 125(65+60), d5 confidence=null 그대로. 모집단: 기존 normalized·vendor 2파일과 메모리 변형. INV-01·02·08, RC-07·12.
- [x] AC-03 데이터 보존: normalized fixture Words 5, Turns 4, 이슈 2. t1 → t-marker → t2 분리; t-marker 850000–990000µs, wordIds=[]; w5 speakerId=null/modelSpeakerId=speaker-b. 로드·수정·저장·재실행·두 포맷 출력 모두 대조. INV-03–07·10, RC-01·03·11.
- [x] AC-04 수정 범위: w5를 speaker-c로 변경해도 text='네', modelSpeakerId=speaker-b, overlap=true 유지. speaker-a 이름 변경은 B/C와 다른 Run 불변. 한 Word editedText 변경은 원문·prefix 보존; Undo/Redo·재실행 후 동일. INV-05·08·09, RC-13·15.
- [x] AC-05 장벽: t1 내부 w1/w2 경계 수동 분리 → 5 Turns; 후속 화자 변경·Undo/Redo·재실행에서도 marker와 수동 경계 보존. Word 한 개가 정확히 한 speech Turn에 속하는지 전수 확인. INV-04–06.
- [ ] AC-06 이슈: i1만 확인하면 acknowledged, i2는 open, w5는 null, marker 유지. 다음 이슈는 850000µs의 i1이 2100000µs의 i2보다 먼저. 동일 시간은 ID 순, null 시간은 유효 시간 뒤. 확인 이슈 없음/검색 없음/선택 없음 상태에서 조작이 잘못 활성화되지 않음. INV-08·10.
- [ ] AC-07 저장 실패: (a) 임시 작성 중 (b) revision 확정 후 pointer 직전 (c) pointer 손상 세 지점 fault injection. 기존 model/raw/유효 revision 해시 보존, 이전 또는 복구된 유효 active 로드. 실패 중 ‘저장됨’·내보내기 금지. 전원 손실 내구성을 이 검사로 주장하지 않음.
- [x] AC-08 시간·TXT: 내부 Int64 µs→화면/TXT 밀리초 표시만 변환. 850000→00:00:00.850, 990000→00:00:00.990; 140000µs=140ms. null은 ‘시간 미확인’; 음수·역전 범위는 검증 실패. 정수 표시 반올림은 모델 시간을 수정하지 않음. INV-02, RC-07. 고정 테스트 필수.
- [x] AC-09 export: 자동본/현재 수정본×JSON/TXT 4조합; null 화자는 ‘화자 미확정’, marker 보존, 정답 확률(%) 미표시. output에 API 키·서명 URL·내부 저장소 절대경로 없음. 합성 provenance 유지. INV-08–10, G-04 중 export 층위.
- [ ] AC-10 UI: 기본 1180×760, 최소 900×600에서 원문·명령이 겹치지 않음. 목록 220pt, Inspector 260pt, 최소 폭 접기·근거 보기 overlay 실제 열기/닫기. 합성 fixture 배지, marker·unknown·confidence 미제공 표시를 육안 확인. HTML mock PASS로 대체하지 않음.
- [ ] AC-11 사용자 여정: Debug 합성 데이터 열기 → 단어/범위 선택 → 화자 변경 → 이름 변경 → Undo/Redo → 저장 → 종료·재실행 → JSON/TXT 저장. 저장 파일 재로딩으로 같은 데이터 확인. 녹음·원음 재생·키 입력·전사 버튼은 미지원 안내/비활성, 권한 요청·API 호출 없음.
- [ ] AC-12 접근성: 검수 창의 선택·화자 변경·이슈 이동·내보내기를 키보드로 1회 완주; VoiceOver의 화자·시간·이슈·선택 이름 확인. 밝은/어두운 모드에서 label·focus 가독성 육안 기록. 실행 불가 시 미측정으로 남기고 built 처리 금지.

## 작업 분해

| ID | 한 태스크의 의도·출력 | 선행 | 완료 근거 |
|---|---|---|---|
| T-01 | 앱·Core 타깃과 검증 명령 생성: Dama.xcodeproj, Package.swift, shared scheme, 진입점, cache·파생물 drift 검사. Debug compile은 서명 단계 실행 없이 분리 | 없음 | AC-01; 설계 T-001 |
| T-02 | 계약 로드·검증 경로: DTO/normalized 분리, nullable 왕복, ID·시간·참조·Turn membership validator, fixture loader | T-01 | AC-02·03·08; 설계 T-002 |
| T-03 | FileSessionRepository와 immutable revision/active pointer 복구. raw/model 초기 반입은 fixture 복사본에서만 수행 | T-02 | AC-07; 설계 T-002 |
| T-04 | Revision 편집·Undo/Redo: 귀속·이름·단일 텍스트·Turn 분리·이슈 확인, 기존 경계 보존 | T-03 | AC-04–06; 설계 T-003 |
| T-05 | JSON/TXT exporter: 자동본/수정본, nullable·marker·시간 표시, atomic 파일 저장 | T-04 | AC-08·09; 설계 T-003 |
| T-06 | 검수 창·Inspector·검색·이슈 이동·선택·수정·저장/오류 UI, 최소 폭 overlay | T-04·05 | AC-10·12; 스펙 §02–04 |
| T-07 | 메뉴바·설정·Debug fixture 진입 및 앱 재실행 여정 통합; 실제 미지원 기능 노출 차단 | T-06 | AC-11; 설계 T-001·003 |
| T-08 | M0 전체 검산과 게이트 ②: 회귀/저장 fault/실행 여정, README·dev 실제 결과 갱신 | T-07 | AC 전 항목과 미측정 층위 보고 |

- QA 지점은 여정 2개다. **① 데이터 여정** (T-02~T-05, 헤드리스): 합성 데이터 열기 → 수정 → 저장 → 재실행 → JSON/TXT 내보내기. AC-02·03·04·05·06·07·08·09. **② 앱 여정** (T-01·T-06~T-08): 앱 실행 → 검수 창 조작 → 저장 → 종료·재실행 → 파일 저장. AC-01·10·11·12. 파일·계층·태스크·커밋은 QA 경계가 아니다.
- 태스크마다 도는 것은 샌드박스 안 층(`check.sh` 1·2, DamaCore pure test)이다. 앱 빌드·`xcodebuild test`·실기기·접근성은 여정 경계에서 메인이 1회. 수탁자가 결과 파일에 명령·출력을 남긴 층은 재실행하지 않는다. 새 검사 실패를 삭제·완화해 통과시키지 않음. 한 의도 단위 pathspec 커밋.
- 코딩은 Codex CLI GPT 5.6 sol에 위임. 메인은 분할·diff 리뷰·통합·검증 판단. 이 plan 작성에서는 코딩 위임/구현을 실행하지 않음.
- /build 발주 파일: `notes/m0-fixture-review/codex/contract.md` + 차수 발주문. 기착지 `t01`~`t05`와 미착수 초안 `t06`~`t08`은 이력으로 보존하고, 남은 발주는 여정 단위로 묶는다(T-05 마감 1건, T-06~T-08 앱 여정 1건). 태스크마다 발주문·결과 보고서·리뷰 파일을 새로 만들지 않는다. 입력·수정 허용 경로·보존 파일·명령·출력 경로를 명시.
- 순차 발주. 후속 병행이 필요하면 메인이 실제 타입·함수와 파일 소유를 먼저 고정. 장기 실행은 진행 신호·정상 소요 대비 워치독을 발주에 포함.

## 검증 실행 주체

| 실행 주체 | 명령/행위 | 제한 |
|---|---|---|
| Codex 수탁 | `bash scripts/check.sh` | `swiftc -module-cache-path "$ROOT/.build/modulecache"` 유지. 오류 발생 시 ~/.cache·~/Library·키체인 경로 거부를 먼저 배제하고 결과 파일에 분류 |
| Codex 수탁 | Core pure tests 및 Debug compile을 check.sh에서 수행 | T-01에서 Debug compile에 CODE_SIGNING_ALLOWED=NO를 명시하여 서명 실행을 분리. 이 결과는 컴파일 층위만. 앱 실행·배포·서명 검증으로 승격 금지 |
| 외부 메인/사용자 | `xcodebuild test` 계열·코드 서명·공증 | 현재 Codex 세션은 실행하지 않음. 키체인·testmanagerd 의존. 실제 실행 명령은 생성된 scheme 확인 후 결과 파일에 기록 |
| 외부 메인/사용자 | 실제 macOS 앱 열기·클릭·VoiceOver·재실행 여정 | 가능한 권한·도구로 앱 실물 확인. 브라우저 file URL 차단 우회로 대체하지 않음 |

- Debug compile의 서명 생략은 사용자 요청한 ‘Codex는 코드 서명 미실행’ 경계를 지키기 위한 검증 분리. 기존 서명 identity를 변경하지 않음. 서명이 필요한 앱 실행은 외부 메인에게 이관.
- check.sh가 환경 거부로 실패하면 결과는 환경 제한, 소스 컴파일 오류면 코드 실패, pure test assertion이면 회귀 실패로 분류. 환경 제한을 이유로 AC를 체크하지 않음.

## 결정 항목

| ID | 판정 축 | 확정값·근거 |
|---|---|---|
| D-01 | 최소 지원 OS | macOS 26.6.2. 사용자 2026-09-09 “macOS 26.6.2 잡자 나는 M5 맥북 프로를 주로 쓰고 있음”. 이전 OS 지원 제외. Swift target-info 인식 확인 |

- 열린 D-NN 없음. 화면 계약·managed 기본 경로·원문 보존을 다시 묻지 않음.
- /build 착수 시 ready-to-build·decisions_resolved·브랜치·clean을 실측하고 building으로 전환. 모든 AC는 검증 근거가 생기기 전까지 미체크.

## 막힘

| 항목 | 상태·사용자 실행 | M0에 미치는 영향 |
|---|---|---|
| API 키·유료 호출·음성 전송 | 사용자 pyannote.ai 가입·키 보유 확인. 키 값 미수신·유효성 미검증, 실전송·유료 호출 승인 없음 | M0 필요 없음. M2에서 앱 키 입력과 건별 실행 확인 |
| 마이크 권한·평가용 녹음 | 마이크 미요청. 사용자 1시간 30분 녹음 보유 진술; 파일 실측·외부 전송 동의 미확인 | M1 반입·M2 한국어 평가에서 확인 |
| 서명·키체인·testmanagerd | 현재 수탁 세션 실행 제외 | 앱 실물·xcodebuild test 확인이 남으면 해당 AC 미체크 유지; 외부 메인 결과 수신 필요 |
| HTML 시각 검수 | file URL 정책 차단, 우회 없음 | 스펙 입력은 사용자 /plan 지시로 채택. M0의 실제 앱 시각·접근성 검수로 확인 |

## 앱 여정 구현·검증 근거 (2026-09-09 재개)

- 사용자 “별도 세션에서 고쳤음. DAMA 프로젝트 다시 이어하자”에 따라 갱신된 공통·도메인·build 규칙을 확인했다. T-06~08은 이 Codex 세션이 직접 구현했고 하위 CLI·태스크별 결과 보고서는 새로 만들지 않았다. T-06~08 기존 발주 초안은 실행 근거가 아닌 과거 이력으로 보존한다.
- T-05 `e05d0b0`: 자동본/현재 수정본 JSON·TXT, 저장 실패·동시 export 방지, 내부 저장소 및 symlink 목적지 보호. 기존 63건 PASS 기록을 이월했으며 담당자가 바뀌었다는 이유로 재검사하지 않았다.
- T-06·07: `App/ReviewWorkspace.swift`의 앱 공용 editor, `UI/ReviewShell.swift` 검수 창, 단어·Shift 범위 선택/화자·이름·텍스트·분리/Undo·Redo/이슈 확인/검색, `EvidencePanel` 구간별 원점수, `EditDialog` 자동 교정 없는 텍스트 입력을 구현했다. 자동본은 읽기 전용이며 실패한 수정은 재시도·변경 취소 전까지 export·종료를 막는다.
- 메뉴바/단일 검수 창/설정, 명시적 Debug 합성 반입, 저장 세션 재로딩, NSSavePanel의 표시 버전×포맷 선택을 연결했다. Release 반입 버튼은 `#if DEBUG`로 제외한다. 실제 녹음·원음·키 입력·전사 기능을 제공한 것으로 표시하지 않는다.
- 통합 `bash scripts/check.sh`: exit 0, 합성 계약 29건·Core 63건·Swift 계약·서명 없는 Debug PASS, SKIP 없음. Core 구성은 loader 17 + time 3 + repository 19 + editor 16 + exporter 8이다. 앱 로직은 이 Core 테스트 수에 포함하지 않는다.
- 이후 검색 변경 시 이전 선택 해제 및 저장 상태 문구·창 delegate 메인 액터 지정을 보완했다. 변경된 앱 컴파일만 재검증했다. 안쪽 첫 실행의 exit 74는 `~/Library/Logs/CoreSimulator` 거부와 `sandbox_apply` 실패로 소스 검사 전 중단된 환경 제한이었다. 승인된 동일 명령의 외부 실행은 통과했다. 소스 assertion 실패로 분류하지 않았다.
- 로그는 `.build/check-logs/`; 환경 거부 원본은 `xcodebuild-sandbox-denied.log`, 최종 앱 출력은 `xcodebuild.log`다. module cache는 `.build/modulecache`, 서명은 `CODE_SIGNING_ALLOWED=NO`. `xcodebuild test`·서명·공증·실제 앱 실행·마이크·음성·유료 API 호출은 하지 않았다.
- fixture와 앱 번들 `Contents/Resources/normalized-transcript.json` SHA256 모두 `37e41f2055156d2b591cd10ba25165b5d24c1cbb23b2edd41710594d047bfdf8`. 계약 Swift 원본·Core 사본 모두 `7be81c3301184397b14b284019946c66394750bb5cdbce2c1234504642791535`. 원본 수정 없음.
- SDK 26.5가 사용자 지정 deployment target 26.6.2를 지원 범위 밖으로 경고하지만 Debug compile/link는 성공했다. 타깃을 임의로 낮추지 않았다. 실제 실행·배포 호환성은 미측정이다.

| AC | 현재 판정·근거 |
|---|---|
| 01 | PASS: 위 계약·Core·Debug 실제 실행, SKIP 없음. 네이티브 실행 증거 아님 |
| 02·03·04·05 | PASS: 기존 loader/repository/editor/exporter 고정 테스트; 원본/null/map/장벽/수정 범위·불변 revision 재로드 확인 |
| 06 | Core 이슈 순서·ack 범위 PASS. 화면의 선택 없음·검색 없음·이슈 없음 조작은 구현했으나 실제 Mac 확인 미측정으로 체크 보류 |
| 07 | Core 저장 fault·해시 보존·dirty export 차단 PASS. native 실패 안내·종료 방지 실제 확인은 미측정으로 체크 보류 |
| 08·09 | PASS: 고정 µs→ms/140ms/null·역전 테스트, 4개 export 조합 및 실제 임시 저장 경로로 데이터 보존 검사. 앱에 API 키·서명 URL 입력 경로 없음 |
| 11 | 사용자 확인: DAMA.app에서 합성 데이터 수정→저장→재실행→내보내기 “막힌 부분 없었음”. 기본 앱 여정 통과. 범위 선택·이름 변경·Undo/Redo·각 포맷 재로드를 개별 확인했다는 진술까지 확대하지 않아 전체 AC 체크는 보류 |
| 10·12 | 창 크기/팝오버·키보드·VoiceOver·밝은/어두운 모드의 개별 확인 결과는 미수신 |

T-08은 기본 정상 여정을 제외한 위 미측정 축만 한 묶음으로 확인해 보충한다. `building`을 유지하며 게이트 ②·`built`로 승격하지 않는다. 과거 후속 착수 보류는 2026-09-09 사용자의 명시적인 M1 계획·구현 및 M2 연결 요청으로 대체됐다. 후속 구현 완료와 M0 미측정 AC는 별개다.

- 로컬 커밋: T-05 `e05d0b0`, 앱 여정 `24c081d`. 마지막 실측 branch `work/m0-fixture-review`, HEAD `24c081d`. 작업 트리의 `.claude/commands/build.md`는 다른 세션 규칙 변경이며, `ssot/dev.md`·이 plan은 그 세션의 QA 규칙 변경과 이번 실측 갱신이 함께 있어 미커밋으로 보존했다. 코드 변경과 섞어 일괄 커밋하지 않았다.

## Follow-ups

### 다음 세션: 실사용까지의 재개 순서 (사용자 요청 2026-09-09)

- 명칭: **DAMA(다마)**. 앱 화면·저장 기본 파일명은 다마, 앱 번들은 `DAMA.app`, TXT 제품 헤더는 DAMA. repo/Xcode 프로젝트 경로·scheme `Dama`·`DamaCore`·bundle ID는 기존 기술 식별자를 유지하여 저장 데이터 경로를 바꾸지 않는다.
- 명칭 변경 후 최종 검사: `bash scripts/check.sh` 1회, 계약 29건·Core 63건·Swift 계약·Debug PASS, SKIP 없음. 빌드된 `DAMA.app/Contents/Info.plist`에서 `CFBundleName=DAMA`, `CFBundleDisplayName=다마` 실측. 기존 실제 UI 미측정 판정은 유지한다.
- 현재 가능한 범위: 합성 원문 검수·수정·저장·export. 아직 실제 회의를 녹음하거나 실제 전사를 얻는 앱은 아니다. 다음 세션은 새 핸드오프를 만들지 않고 이 plan의 resume·미체크 AC와 실제 git 상태를 먼저 확인한다.
- **① M0 마감:** 사용자에게서 DAMA.app의 합성 데이터 수정→저장→재실행→export “막힌 부분 없었음” 결과를 받았다. 이 정상 여정을 다시 요구하거나 자동 검사를 재실행하지 않는다. 남은 개별 AC(빈 상태/저장 실패 UI, 크기·팝오버, 키보드·VoiceOver 등)는 별도 미측정으로 유지하고 마감 때 한 묶음으로 확인한다. SDK 경고가 기본 앱 실행을 막지는 않았다는 사용자 실행 근거가 생겼으며 배포 호환성 전체 검증으로 확대하지 않는다.
- **② M1 계획·구현:** `ssot/design/05_IMPLEMENTATION_PLAN.md` M1·설계 T-004~006과 녹음 화면 스펙을 읽고 `m1-recording-safety` plan을 만든다. 기본 마이크 권한→메뉴바 시작/종료→원본 저장→중단/재실행 복구, M4A/WAV 반입·분석 시간축을 하나의 녹음 여정으로 구현한다. API 키·네트워크 없이 원본 보존이 먼저다. 시스템 오디오 캡처·입력 장치 선택은 현재 P0 비범위다.
- **③ M2 계획·구현:** 실제 원본을 보존한 뒤 managed API의 Keychain 키 저장·건별 전송 동의·업로드/제출/조회·normalized 변환과 검수 창을 연결한다. 과금 POST의 접수 불명은 자동 재제출하지 않는다. 원음 재생/검수까지 연결한 뒤 실제 짧은 한국어 대화로 E1/E2·누락·미확정 화자를 확인한다. 현재 fixture를 정확도 증거로 쓰지 않는다.
- M1/M2는 이번 턴에 착수·완료한 것으로 기록하지 않는다. M0 확인 후 후속 단계 커맨드가 요구하는 실제 선행 조건을 충족해서 진행한다. 서명·공증·배포는 별도 단계다.

| 사용자가 준비할 것 | 시점·방법 |
|---|---|
| M0 앱 실행 결과 | 수신 완료: `.build/xcode/Build/Products/Debug/DAMA.app`의 합성 데이터 수정→저장→재실행→내보내기에 막힘 없음. 동일 여정 재확인 요청 불필요. |
| 테스트용 마이크 | M1 실기기 확인 때 M5 MacBook Pro의 마이크를 사용하고, 앱이 요청할 때 접근을 허용한다. 지금 M0에는 마이크 권한 요청이 없다. |
| pyannote 계정·API 키 | 준비 완료(사용자 진술): 가입·키 보유. 다음 세션에서 다시 준비 요청하지 않는다. 키 유효성은 미검증이며 구현된 앱 입력 화면에서 Keychain에 저장한다. 지금은 입력 화면이 없다. |
| 평가용 녹음 | 1시간 30분 파일 보유(사용자 진술, 실제 길이 미측정). 실연동 시 경로·포맷·언어·화자 수와 테스트·외부 전송 동의를 확인한다. 최초 연결은 이 파일의 짧은 구간으로 확인한 뒤 전체 90분 처리로 진행한다. 원본 보존, 저장소 반입 금지. |
| 실제 API 실행 승인 | M2가 준비되면 해당 파일의 외부 전송·유료 호출을 건별 확인한다. 키 준비만으로 업로드가 승인되는 것은 아니다. |

사용자에게 요청했던 기본 앱 여정 확인은 완료됐다. API 키와 테스트 음성은 M1 구현을 시작하기 위한 선행 조건이 아니다. 다음 세션 요청 예: “DAMA 이어서. m0-fixture-review plan의 다음 세션 절부터 진행. 기본 수정·저장·재실행·내보내기는 문제없었음. 마이크 녹음·원본 보존을 먼저 구현하자.”

사용자 준비 상태 추가: 1시간 30분 녹음과 pyannote.ai 계정·API 키 보유를 확인했다. 파일·키를 실제로 열거나 API를 호출한 것은 아니며, 준비 완료를 외부 전송 승인으로 해석하지 않는다. 다음 세션은 이 준비 상태를 이월한다.

| 후속 유닛 후보 | 이전 단계 입력 | 남은 전체 스펙 범위·설계 티켓 |
|---|---|---|
| m1-recording-safety | M0 타깃·repository | 실제 메뉴바 시작/종료, callback·청크·중단 복구, M4A/WAV 가져오기, 분석 시간축. 설계 T-004–006; 스펙 녹음 AC-08 |
| m2-managed-processing | M1 원본 보존·분석 파일 | Keychain·전송 동의·upload/submit/poll·P0 normalizer/TurnBuilder. 설계 T-007–009. 접수 불명·만료는 여기서 실응답/mock 검증 |
| m2-review-release | M2 실제 Run + M0 편집 UI | 실제 원음 seek·재생·저장 재실행·전송/삭제/복구 통합, G-01–08 및 한국어 지표. 설계 T-010–011; 스펙 AC-07·09 |

- 후속 plan은 선행 유닛 실물을 읽은 뒤 생성. 지금 미래 상태 문서·빈 폴더를 만들지 않음.
- coverage 0.60·margin 0.20·gap 300ms·marker 150ms·polling 10–60초는 외부 설계 초기값. M0는 알고리즘 재구현·임계값 조정 없음. 140ms marker를 짧다고 삭제하지 않는 데이터 보존만 검산.
- M3 WhisperKit·M4 확장은 P0 검증 이후 별도 결정. normalized P1 합성 fixture 사용은 P1 구현 승인으로 해석하지 않음.

## 계획 검산

- 승인 신호: 실제 source closed, 채택 근거는 사용자 /plan 지시. 시각 검수 미완료 문구 보존.
- 예시 역검산: fixture t-marker 길이 990000−850000=140000µs; i1이 i2보다 먼저; 전체 Turns 4이며 A/marker/A만 세면 3. d4 confidence 합 125, d5 null. 사용자 수동 분리 후 기대 5 Turns는 원래 4에 1 추가.
- 검증 기준 12개, 태스크 8개, 열린 D-NN 0개. 상태·AC·코드의 완료를 혼동하지 않음.
- 문서 작성/검산 후 로컬 커밋. 원격 생성·push·업로드·API 호출·음성 전송·코드 서명·공증 없음.

# 05. 로컬 코딩 AI 구현 계획

## 1. 작업 시작 규칙

기존 repository가 있으면 먼저 읽고 보존한다. 이 패키지 자체를 완성 앱이라고 가정하지 않는다. 실행 가능한 프로젝트와 테스트를 만드는 것이 다음 작업이다. 각 단계는 실제 빌드/테스트 명령과 결과를 남긴 뒤 진행한다. 구현하지 않은 기능을 mock 화면으로 완성했다고 보고하지 않는다.

먼저 `sw_vers`, `uname -m`, `xcodebuild -version`, `swift --version`과 디스크 여유 공간을 확인한다. 개인 식별 정보는 작업 보고에 불필요하게 포함하지 않는다. Xcode/Swift 버전 선택은 문서의 minimum target 및 선택한 package release와 맞춘다. '최신 버전'이라는 문자열만 보고 의존성을 업데이트하지 않는다.

이 계획의 command는 프로젝트 생성 후 사용할 계약이다. 이 전달 패키지에는 아직 `.xcodeproj`나 설치 가능한 `.app`이 없다.

## 2. 단계별 티켓

### M0 — 프로젝트와 가짜 모델 결과로 수직 경로

**T-001: 앱/Core 타깃 생성**

입력: 01, 02, AGENTS. 생성: Dama.xcodeproj, App, Core Swift Package, 테스트 scheme. Core는 UI/SDK에 의존하지 않는다. Debug fixture engine과 Production engine을 compile-time/명시적 설정으로 구분한다.

완료: 빈 메뉴바 앱 실행, 설정 창 열기, `swift test`와 앱 build 성공. 빌드에 필요하지 않은 권한 요청 없음. 기존 파일을 지우는 초기화 스크립트 금지.

**T-002: 도메인/저장/decoder**

입력: schema, contracts, normalized fixture, pyannote fixture. 생성: Codable 모델, Raw DTO, Repository, migrations 기본 골격. raw 응답과 normalized 데이터는 다른 타입.

완료: fixture decode/round-trip, confidence map 보존, null 화자 유지, unknown provider status에 대한 테스트. active pointer 이전 단계에서 강제 실패해도 마지막 정상 revision 복구.

**T-003: fixture 기반 검수/내보내기**

생성: 기본 ReviewWindow, 원문 표시, 화자 선택 수정, JSON/TXT exporter. 실제 음성이 없으므로 sample fixture 화면에는 '합성 테스트 데이터' 표시; 원음 재생 성공을 가장하지 않는다.

완료: A/B/A marker가 한 문장으로 합쳐지지 않음. TXT와 JSON에 미확정/이슈 유지. 수정을 저장하고 앱 재실행 후 동일 결과.

### M1 — 실제 녹음 안전성

**T-004: 메뉴바 state machine**

좌클릭 시작/종료, 우클릭 패널, 중복 클릭 방지, 창과 녹음 수명 분리. 상태 reducer와 명령 호출 횟수 단위 테스트.

**T-005: 마이크 capture와 writer**

권한, 실제 입력 포맷, owned buffer, 지속 PCM 저장, 정상 종료 drain. 첫 단계에서는 단일 CAF로 수직 검증하되 M1 완료 전에 청크/manifest 복구 경로를 완성한다.

완료: 10분 연속 녹음, 입력 파형/실제 재생 일치, 패널 닫아도 지속, 녹음 종료 후 파일 정상. 네트워크/키가 없어도 동일 작동.

**T-006: 중단/가져오기/분석 파일**

M4A/WAV를 앱 저장소로 복사, 원본 hash, 16kHz 공통 시간축 변환. 디스크 부족/장치 변경/앱 강제 종료 시 부분 복구. 알 수 없는 gap을 조용히 이어 붙이지 않음.

완료: 파일 duration/frame 비교, 반대 위상 입력 처리, 마지막 청크 손실 가능 범위 보고. 원본 해시는 전사/검수 후에도 동일.

### M2 — 실제 API와 end-to-end MVP

**T-007: Keychain/전송 정책**

키 추가/교체/삭제, ask/auto/never 정책, 세션별 override. API 키가 없으면 전사만 보류한다. 키/원문이 로그에 나오지 않는 테스트.

**T-008: upload/submit/poll**

03에 따라 URLSession adapter, API와 서명 PUT transport 분리, raw response 저장. 계정 테스트는 사용자가 제공한 키와 전송을 승인한 샘플만 사용.

완료: URLProtocol mock으로 400/401/402/429/5xx, 응답 전 앱 종료, POST 접수 불명, GET 재시도 테스트. 실제 API 호출은 mock 통과 뒤 별도 opt-in 단계.

**T-009: normalization/TurnBuilder/ReviewIssueDetector**

P0 provider word labels 보존, 단어 timestamp 변환, 원본 일반/배타적 diarization 보존. missing marker와 병합 장벽 구현. confidence dictionary decoder를 scalar로 단순화하지 않음.

완료: 이 패키지의 사례를 Swift 회귀 테스트로 옮기고 통과. 문장 단위 화자 투표 없음. null speaker를 가장 가까운 사람으로 채우지 않음.

**T-010: 원음 검수/수정 이력/내보내기**

실제 오디오 seek, 단어 범위 귀속 변경, Undo/Redo, 검수 표시와 화자 수정 구분. JSON/TXT에서 자동본/수정본 선택.

완료: 실제 녹음에서 3구간 수정 → 저장 → 재실행 → 같은 내용; old Run 보존. 1시간 파일 seek 오차 실측 보고.

**T-011: 회복/보안/배포 점검**

네트워크 단절 중 새 녹음, 결과 만료, sleep/wake, 로그 검증, entitlement 최소화, 원본 삭제 확인. 비용 숫자 추측 금지.

완료: 06의 P0 Gate 전부 통과 또는 실패 항목을 명시한 미완료 보고. '실행해보지 않았지만 된다'는 완료 보고 금지.

### M3 — 선택적 Hybrid 개선

**T-012: WhisperKit 통합**

공식 repository의 선택 버전 고정, model download/verification/loader, ko/word timestamps 설정, 단어 offset 계약 테스트. 임의 Python 런타임/ffmpeg 필수 의존성을 추가하지 않는다.

**T-013: 자체 결합과 A/B**

04의 알고리즘을 Swift pure function으로 구현. P0와 P1을 같은 원본/범위/화자 수로 실행해 E1/E2/unknown/검수시간을 함께 비교. 결과가 나쁘면 P0를 기본으로 유지한다.

### M4 — 선택적 확장

시스템 오디오 별도 트랙, 전역 단축키, launch-at-login, 장치 선택, iPhone 전용 앱은 독립 티켓으로 둔다. 첫 앱의 권한과 실패 가능성을 불필요하게 늘리지 않는다.

## 3. 의존관계

`T-001 → T-002 → T-003`; `T-001 → T-004 → T-005 → T-006`; `T-002 + T-006 + T-007 → T-008 → T-009 → T-010 → T-011`; `T-011 통과 후 T-012 → T-013`.

UI/fixture 검증은 오디오 capture와 일부 병렬 가능하지만, 실제 API 연결을 먼저 만들고 녹음 복구를 나중으로 미루지 않는다.

## 4. 생성할 빌드/실행 명령

프로젝트를 만든 AI는 아래 형태의 실제 실행 명령을 저장소 README에 기록한다. scheme/path를 다르게 만들었다면 맞는 명령으로 교체한다.

```sh
swift test --package-path Packages/DamaCore
xcodebuild -project Dama.xcodeproj -scheme Dama \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath .build/xcode build
```

마이크/TCC/Keychain/UI/코드서명 테스트는 순수 Core 테스트와 별개다. 서명 계정이 없어 실패하면 원인과 사용자 설정 단계를 명확히 보고한다. 서명 검증을 꺼서 성공한 명령을 배포 검증으로 보고하지 않는다.

## 5. 각 작업의 보고 형식

```text
구현한 티켓:
변경한 파일:
실행한 빌드/테스트와 결과:
실제 Mac/오디오/API를 사용했는지:
발견한 제한/실패:
다음 미완료 티켓:
```

개발 AI는 계획만 다시 쓰고 끝내지 말고 M0부터 실제 파일을 만든다. 단, API 키/음성 전송/유료 호출/사용자 데이터 삭제/코드서명 등 외부 효과는 지정된 권한과 사용자 승인을 넘지 않는다.

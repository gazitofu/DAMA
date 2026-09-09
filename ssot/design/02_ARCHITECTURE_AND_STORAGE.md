# 02. 아키텍처, 녹음 및 저장

## 1. 고정할 설계 결정

UI와 녹음 수명 분리, 녹음과 전사 상태 분리, 공급자 DTO와 앱 도메인 분리, 모델 원본과 사용자 수정 분리가 핵심이다. 종속성은 UI → Application → Domain 방향으로 둔다. 네트워크/디스크/WhisperKit은 Domain의 프로토콜을 구현한다.

```text
NSStatusItem / SwiftUI windows
             |
       AppCoordinator (@MainActor)
        /                \
CaptureService      ProcessingQueue actor
      |                    |
Audio buffer pool      TranscriptEngine protocol
      |                 /              \
Serial file writer   Managed engine   Hybrid engine (P1)
      |                 |              /          \
Session repository   pyannote API  pyannote API   WhisperKit
      |                 \             /          /
      +------------ raw result store -----------+
                            |
                    Transcript normalizer
                            |
              Review detector / Turn builder
                            |
              Immutable run + revision storage
                            |
                  Review UI / JSON / TXT
```

이 텍스트 구조는 구현 설명이다. 런타임에서 오디오 버퍼가 MainActor를 거쳐 파일로 가도록 만들라는 의미가 아니다.

## 2. 권장 프로젝트 구조

```text
Dama.xcodeproj
App/                       AppDelegate, AppCoordinator, WindowCoordinator
UI/                        StatusBarController, RecordingPanel, ReviewWindow
Capture/                   CaptureController, BufferPool, AudioWriter, Importer
Infrastructure/Pyannote/   Client, DTOs, Poller, UploadTransport
Infrastructure/Whisper/    WhisperKitAdapter, ModelManager (P1)
Infrastructure/Storage/    FileSessionRepository, KeychainStore
Packages/DamaCore/
  Sources/                 Domain, Reconciliation, TurnBuilder, Exporter
  Tests/                   DTO, StateMachine, Reconciliation, Export tests
Resources/                 Info.plist, entitlements, localization
Tests/                     app integration, UI, recovery
```

Core는 Apple UI/네트워크/WhisperKit에 의존하지 않는 Swift Package로 만든다. 테스트에 실제 API 키가 없어도 모델 결과 fixture로 검증할 수 있어야 한다. 공급자 모델 이름은 adapter 설정에만 존재하고 UI에서 문자열 비교로 분기하지 않는다.

## 3. 병행성 경계

| 구성요소 | 소유권/실행 경계 |
|---|---|
| AppCoordinator, UI state | MainActor |
| CaptureController | 하나의 제어용 직렬 경로에서 AVAudioEngine 시작/종료 |
| 오디오 callback | 미리 확보한 버퍼에 복사하고 제한된 큐로 넘김; await/네트워크/로깅/대형 할당 금지 |
| AudioWriter | 독립 직렬 writer; 받은 버퍼 소유권을 다 쓴 뒤 pool에 반환 |
| ProcessingQueue | actor; 영속 상태 변경을 직렬화 |
| Pyannote transport | URLSession 비동기 I/O; UI executor 차단 금지 |
| 로컬 ASR | 전용 adapter가 추론 객체 독점; 동시 실행 1개부터 |
| Repository | actor; revision 생성과 active pointer 변경의 순서 보장 |

오디오 callback의 AVAudioPCMBuffer를 소유권 복사 없이 비동기 closure에 보관하지 않는다. Task를 매 callback마다 만들거나 무제한 AsyncStream으로 전체 오디오를 쌓지 않는다. Sendable 오류를 숨기려고 프로젝트 전체를 `@unchecked Sendable`로 만들지 않는다. 실제로 unsafe 코드가 필요한 buffer pool 경계는 작게 격리하고 별도 테스트한다.

## 4. 녹음 경로

마이크 수집은 AVAudioEngine의 입력 노드 tap을 이용하는 구조다. [AVAudioEngine](https://developer.apple.com/documentation/avfaudio/avaudioengine), [installTap](https://developer.apple.com/documentation/avfaudio/avaudionode/installtap(onbus:buffersize:format:block:))

설계 순서:

1. 저장소 쓰기와 마이크 권한을 확인한다. 새 Session ID 및 manifest를 만든다.
2. 실제 입력 포맷(sample rate, channel count)을 확인한다. 포맷을 48kHz stereo로 강제 가정하지 않는다.
3. buffer pool, writer, engine 순으로 준비한다. engine 시작 직후가 아니라 첫 오디오를 받은 시점을 recorded time의 기준으로 둔다.
4. 실제 입력 샘플을 무손실 PCM CAF 청크로 지속 기록한다. 청크 기본 길이는 30초다. 파일 전환은 하나의 연속 writer에서 수행하며 프레임 누락을 허용하지 않는다.
5. 종료 요청 후 새 입력 수신을 중지하고 남은 큐를 배출한다. 파일을 닫고 manifest를 확정한다.
6. 원본 파일과 프레임 수를 검증한 뒤에만 분석 파일 생성/전사 대기열로 보낸다.

CAF/청크 저장은 앱의 정책이다. 강제 종료 시 이미 확정한 청크를 복구하는 것을 목표로 하되 **최근 청크 또는 OS 미동기화 버퍼가 전혀 손실되지 않는다고 보장하지 않는다.** 마지막 미완료 청크가 읽히지 않으면 격리하고 확정 청크로만 복구한다. 정상 종료는 모든 프레임 보존이 합격 기준이다.

오디오 큐 포화, 디스크 부족, 입력 포맷 변경, 선택 장치 소실 시 조용히 프레임을 버리며 계속 녹음하지 않는다. 가능한 부분을 확정하고 `capture_interrupted`로 종료한다. 1차 버전에서는 자동으로 다른 장치로 바꾸거나 끊긴 회의를 이어 붙이지 않는다.

## 5. 시간축

저장된 원본의 샘플 프레임을 기준으로 한 `recorded audio time`을 사용한다. UI용 벽시계/날짜는 별도 필드다. 녹음 종료 후 두 AI는 같은 `analysis.wav`를 사용한다.

- 표준 분석 파일: mono PCM WAV, 16,000Hz, 16-bit를 초기 정책으로 설정한다. 원본은 별도 보존한다.
- 전체 샘플 수를 유지하며 리샘플링한다. 앞뒤 무음 자르기, 길이 압축, ASR 결과에 맞춘 오디오 잘라내기는 금지한다.
- mono 변환 전 다채널 검사를 한다. 반대 위상 신호로 상쇄되는 테스트 파일이면 자동 평균 대신 오류/확인 상태로 전환한다. 온라인 회의 독립 트랙은 이 경로에 무심코 섞지 않는다.
- 입력 청크 포맷이 달라지면 하나의 연속 녹음인 것처럼 연결하지 않는다.
- normalized 시간은 Int64 마이크로초다. 공급자 초 단위 Double은 유한성/범위 확인 후 한 번만 변환한다. 오디오 플레이어와의 변환은 공통 TimeMapper를 사용한다.
- 범위는 반열린 구간 `[startUs, endUs)`다. 경계가 맞닿는 두 발화는 동시발화가 아니다.
- 공급자 timestamp가 잘못되면 원본 응답을 보존하고 normalized word의 시간을 null로 둔다. 임의로 오디오 끝에 잘라 붙여 정상인 것처럼 만들지 않는다.

저장용 30초 청크를 각각 별도 diarization 작업으로 보내면 안 된다. 화자 ID는 기본적으로 하나의 Run 안에서만 유효하다. 전체 회의를 처리할 수 없는 공급자 제한이 발견되면 우선 명시적 오류를 내고, 장시간 분할과 화자 재연결을 별도 설계한다.

## 6. 상태기계

### CaptureState

`idle → authorizing → starting → recording → finalizing → idle`

권한/시작 실패는 `failed → idle`, 녹음 중 실패는 가능한 파일 확정 후 `interrupted → idle`로 간다. 파일 오류는 해당 Session에 남긴다. Starting/Finalizing에서 새 Start를 받으면 무시한다. 단일 마이크 녹음 세션만 허용한다.

### ProcessingState — 녹음별 Run

```text
awaitingConsent → queued → preparing → uploading → submitting
                                              |
                                              +→ submissionUncertain
submitting → remotePending → fetching → normalizing → readyForReview

P1 Hybrid: remote diarization / local ASR 두 branch 완료 후 normalizing
```

일시 정지는 `waitingForNetwork / waitingForCredentials / waitingForBilling / paused`로 구분한다. 최종 실패는 `failed / resultExpired / locallyCanceled`로 구분한다. `readyForReview`는 자동 처리 완료이지 화자 검수 완료가 아니다. Review 상태는 `unreviewed / inProgress / reviewed`로 별도 관리한다.

상태 변경은 다음 작업을 시작하기 전에 저장한다. 특히 submitting 직전에 attempt ID와 요청 해시를 저장하고, jobId를 받으면 곧바로 저장한다. 앱 재실행 시 queued는 재개, remotePending은 기존 jobId 조회, submitting에 jobId가 없으면 submissionUncertain으로 바꾼다.

## 7. 영속 저장소

MVP는 파일 기반 Repository로 구현한다. SwiftData/SQLite를 도입하지 않아도 되도록 앱 인덱스는 세션 manifest에서 재생성 가능한 캐시로 둔다. 전체 데이터의 진실은 Session 폴더와 immutable Run/Revision이다.

```text
Application Support/<bundle-id>/
  index.json                         재생성 가능한 목록 캐시
  Sessions/<session-id>/
    session.json                     캡처 메타데이터/정책/active revision
    audio/source/                    가져온 원본 또는 확정 CAF 청크
    audio/capture-manifest.json       순서/포맷/프레임 수/중단 정보
    audio/analysis.wav               표준 시간축 파일
    audio/analysis-manifest.json      해시/변환 버전/프레임 수
    runs/<run-id>/
      request.json                   인증 헤더를 제외한 요청 설정
      state.json                     영속 작업 상태/jobId/재시도 정보
      raw/pyannote-response.json      원본 응답, 수정 금지
      raw/whisper-output.json         P1만
      normalized/model.json          사용자 수정 전 결과
    revisions/<revision-id>.json     수정 snapshot + 변경 이유/기반 Run
    cache/waveform.bin               재생성 가능
```

FileManager가 반환하는 앱 저장 경로를 사용한다. 샌드박스 컨테이너 경로를 하드코딩하지 않는다. 오디오를 번들/소스 리포지토리에 저장하지 않는다.

원자적 저장은 같은 볼륨의 임시 파일 작성 → 검증/close → 교체 → 마지막으로 active revision pointer 갱신 순서다. snapshot과 pointer를 한 파일처럼 가정하지 않는다. 중간 종료 시 dangling pointer를 검출하고 마지막 유효 revision으로 복구한다. 파일시스템 crash consistency는 실기기 fault injection으로 검증해야 하며 단순 atomic rename만으로 전원 손실까지 보장하지 않는다.

## 8. API/로컬 추론 병행 정책

원본 녹음은 모든 후처리보다 높은 우선순위를 갖는다. 기본 cloud Run 동시 실행 수는 1이다. 로컬 Whisper 추론 중 새 녹음이 시작되면 추가 ASR 작업은 시작하지 않는다. 진행 중 추론의 안전한 취소/일시중지는 라이브러리 지원을 확인해 구현하고, 지원되지 않으면 낮은 동시성으로 계속할지 사용자가 선택하도록 한다. 이 동작은 녹음 부하 테스트의 필수 항목이다.

녹음 중에는 idle sleep 억제를 검토하되, 덮개 닫힘/강제 sleep에서도 계속 녹음된다고 표시하지 않는다. 실제 중단이 생기면 세션을 끊는다. wake 후 녹음 자동 재개는 P0에서 제외한다. 맥이 꺼져 있는 동안 앱의 로컬 후처리가 계속된다는 설명도 금지한다.

## 9. 삭제와 재처리

재처리는 새 Run을 만들고 기존 수정본을 덮어쓰지 않는다. 새 Run의 SPEAKER_00을 이전 Run의 같은 사람으로 자동 연결하지 않는다. 수정 이식은 이후 명시적인 diff 기능으로 다룬다.

삭제는 로컬 원본/결과/캐시를 구분해서 확인받는다. 원본만 삭제하면 재전사와 원음 검수가 불가능하다는 문구를 표시한다. 로컬 삭제를 서버의 즉시 삭제로 표현하지 않는다. 클라우드 보관 정책은 03의 별도 제약을 따른다.

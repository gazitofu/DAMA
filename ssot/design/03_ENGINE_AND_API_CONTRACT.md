# 03. 처리 엔진 및 외부 API 계약

이 파일은 확인한 공개 문서를 바탕으로 한 구현 계약이다. 공급자 API의 실계정 호출은 이 패키지 작성 과정에서 실행하지 않았다. 문서 확인과 실제 계정/요금제에서의 사용 가능성 검증은 구분한다.

## 1. 엔진 선택

`managedPyannoteWhisper`를 P0 기본으로 구현한다. `hybridPyannoteWhisperKit`은 P1에 같은 TranscriptEngine 인터페이스로 추가한다. 로컬 엔진을 추가하면서 UI나 Repository가 공급자 출력 형식에 종속되지 않게 한다.

통합 전사는 Precision-2와 STT 모델을 함께 실행하고 화자 귀속 결과를 제공한다. 공식 문서에서 기본 STT는 Parakeet으로 설명하므로 Whisper 모델을 **명시적으로 설정**한다. [통합 전사 문서](https://docs.pyannote.ai/tutorials/speech-to-text-diarization)

## 2. API 요청

Base URL: `https://api.pyannote.ai`

### 2.1 임시 업로드 위치

`POST /v1/media/input`, JSON body:

```json
{"url":"media://dama/SESSION_UUID/RUN_UUID.wav"}
```

API 도메인 요청에 `Authorization: Bearer <key>`와 JSON Content-Type을 넣는다. 응답의 `url`은 오디오를 PUT할 서명 URL이다. 오디오는 해당 URL에 바이너리로 PUT하고 Content-Type은 `application/octet-stream`을 사용한다. **업로드 저장소 URL에는 pyannote Bearer 키를 전달하지 않는다.** [업로드 가이드](https://docs.pyannote.ai/tutorials/how-to-upload-files)

설계 보안 정책: 서명 URL의 HTTPS를 검사한다. 별도 URLSession을 사용해 Authorization 전파와 redirect 시 자격증명 유출을 막는다. 서명 URL을 로그/크래시 리포트에 남기지 않는다. 파일은 URLSession의 파일 업로드 경로로 스트리밍하고 Data(contentsOf:)로 전체를 메모리에 읽지 않는다.

### 2.2 통합 작업 요청

`POST /v1/diarize`:

```json
{
  "url": "media://dama/SESSION_UUID/RUN_UUID.wav",
  "model": "precision-2",
  "exclusive": true,
  "turnLevelConfidence": true,
  "transcription": true,
  "transcriptionConfig": {
    "model": "faster-whisper-large-v3-turbo"
  }
}
```

화자 수를 실제로 아는 경우에만 `numSpeakers`를 추가한다. 정확한 수와 범위 설정을 함께 보내지 않는다. `transcriptionConfig.language` 등 공개 스키마에 없는 키를 추측해서 추가하지 않는다. 요청 필드와 모델 식별자는 [Diarize API](https://docs.pyannote.ai/api-reference/diarize), 언어 옵션 노출 여부와 응답 타입은 [OpenAPI](https://docs.pyannote.ai/openapi.json)를 기준으로 한다.

`numSpeakers`와 `minSpeakers/maxSpeakers`는 배타적이며 범위는 min≤max여야 한다. 모르면 모두 생략한다. [화자 수 규칙](https://docs.pyannote.ai/tutorials/speaker-configuration)

P1 Hybrid 요청은 위 body에서 `transcription: false`로 바꾸고 `transcriptionConfig`를 생략한다. 로컬 Whisper는 같은 analysis.wav를 입력받는다.

### 2.3 상태 조회

작업 제출에서 받은 `jobId`로 `GET /v1/jobs/{jobId}`를 호출한다. 알려진 상태는 `pending / created / running / succeeded / failed / canceled`다. 알 수 없는 새 상태 문자열은 decode 실패 대신 `unknown(rawValue)`로 보존하고 사용자에게 표시한다. [작업 조회 API](https://docs.pyannote.ai/api-reference/get-job)

초기 polling 간격은 10초, 반복 대기 시 최대 60초, ±20% jitter를 설계값으로 둔다. `Retry-After`가 있으면 우선한다. 로컬 앱에는 공인 webhook 수신 서버를 두지 않는다. polling은 앱이 실행 중일 때만 재개 가능하다고 설명한다. 공급자도 polling과 webhook을 문서화하며 과도한 조회에 대한 rate limit을 안내한다. [처리 결과 조회](https://docs.pyannote.ai/tutorials/how-to-diarize-audio)

## 3. 응답 DTO

공급자 DTO는 앱의 normalized schema와 분리한다. `start/end`는 공급자 초 단위이며 normalized 형식에서는 마이크로초로 변환한다.

| 위치 | 읽을 필드 |
|---|---|
| 최상위 | jobId, status, createdAt, updatedAt, output |
| output | diarization, exclusiveDiarization, wordLevelTranscription, turnLevelTranscription, warning, error |
| diarization segment | start, end, speaker, confidence(선택) |
| word/turn transcription item | start, end, text, speaker |

**중요:** 발화별 `confidence`는 하나의 숫자가 아니라 `{"SPEAKER_00": 91, "SPEAKER_01": 14}` 같은 화자별 map이다. 합이 100일 필요는 없으며, 누락되면 미제공으로 둔다. `confidence:true`의 sample-level 데이터와 `turnLevelConfidence:true`는 다르다. [신뢰도 문서](https://docs.pyannote.ai/tutorials/confidence-scores)

신뢰도 map을 확률로 정규화하거나 임의의 단어 확률로 복사하지 않는다. 선택 화자 점수는 원본 diarization interval의 값으로 표시하고, 여러 interval을 걸치는 단어에는 해당 interval ID 목록을 연결한다. 앱이 계산한 시간 겹침 점수는 별도 `alignmentScore`다.

P0에서는 provider의 word speaker를 우선 보존한다. 최대 겹침 알고리즘으로 정상 공급자 결과를 무조건 덮어쓰지 않는다. 원본 화자와 시간 근거가 충돌하면 review issue를 추가한다. output 성공이어도 word 필드가 없으면 sentence 단위로 대충 채우지 말고 `partialResult`/검수 상태로 표시한다.

## 4. 오류와 중복 제출

| 상황 | 앱의 정책 |
|---|---|
| 키 오류/401/403 | waitingForCredentials; 반복 제출 금지 |
| 과금/구독 문제/402 | waitingForBilling; 원본 유지 |
| 잘못된 요청/400 | 요청 검증 오류, 자동 재시도 금지 |
| 429 | 서버 지시 우선 backoff |
| 조회 GET의 timeout/5xx | 제한적 재시도 가능, 기존 jobId 유지 |
| PUT 실패 | 파일과 media key 유지, 만료 여부 확인 후 업로드 재시도 |
| POST diarize의 timeout/연결 끊김/결과 불명 5xx | submissionUncertain; 자동 재제출 금지 |
| succeeded인데 output 없음 | 만료/부분 실패 여부 확인; 빈 성공 transcript 생성 금지 |
| 모델/스키마 변경 | raw 보존, adapterFailure; 이미 저장한 녹음 유지 |

`Idempotency-Key` 지원이나 서버 작업 취소/삭제 endpoint를 확인 없이 만들어내지 않는다. 로컬 요청 해시는 동일 앱 안의 중복 동작 예방일 뿐 서버의 exactly-once 실행 보장이 아니다. 응답을 받기 전에 서버가 작업을 만들었을 수 있으므로 접수 불명 요청은 사용자 확인 없이 재제출하지 않는다.

서버 작업에 대한 버튼은 '로컬 추적 중단'으로 표현한다. 서버 처리가 취소되거나 비용이 환불됐다는 메시지를 출력하지 않는다. 수동 재처리는 비용이 다시 발생할 수 있음을 알리고 새 Run으로 만든다.

## 5. 보관/지역 제약

업체 정책상 job output은 완료 후 24시간, Media API 업로드는 48시간 이내 자동 삭제 대상이다. 학습에 고객 데이터를 사용하지 않는다는 정책도 업체가 명시한다. 기본 Any region 처리와 EU 제한 설정이 구분되므로 외부 전송 동의 화면에서 계정의 실제 설정을 확인하도록 한다. 이는 업체 공개 정책이지 이 앱의 독립 감사 결과가 아니다. [보관 및 지역 정책](https://docs.pyannote.ai/data-retention)

앱 정책: 성공 응답 bytes를 곧바로 로컬 raw 파일로 저장한 후 parsing한다. 맥이 장기간 꺼져 있으면 결과 보관 기간을 놓칠 수 있다. '24시간 뒤까지 가져올 수 있다'를 로컬 추정 타이머만으로 단정하지 말고 서버 응답으로 상태를 확인한다. 저장소 TTL과 업로드 URL의 서명 만료시간은 서로 다른 개념이다.

계정별 가격/한도는 하드코딩하지 않는다. 첫 실제 연동 시 5~10분짜리 동의받은 샘플 1개로 연동, 파일 형식, 타임스탬프, 계정 한도를 확인한다. 큰 파일을 자동 분할해 공급자 제한을 우회하는 기능은 P0가 아니다.

## 6. P1: WhisperKit adapter

Swift package는 `https://github.com/argmaxinc/argmax-oss-swift`, product는 `WhisperKit`이다. 선택한 릴리스/commit을 고정하고 Package.resolved를 커밋한다. `main`을 계속 추적하거나 TTS/SpeakerKit umbrella를 불필요하게 앱에 링크하지 않는다. [Package.swift](https://raw.githubusercontent.com/argmaxinc/argmax-oss-swift/main/Package.swift)

로컬 모델 후보는 Core ML용 multilingual Large v3 Turbo다. 공식 README에는 `openai_whisper-large-v3-v20240930_turbo`와 압축 변형이 소개되어 있다. 이 식별자는 pyannote의 `faster-whisper-large-v3-turbo` API 이름과 다르다. 실제 다운로드 revision/hash와 선택 모델을 Run에 기록한다. [WhisperKit README](https://github.com/argmaxinc/argmax-oss-swift)

DecodingOptions의 시작 설정은 `task=.transcribe, language="ko", detectLanguage=false, withoutTimestamps=false, wordTimestamps=true, concurrentWorkerCount=2`다. 이는 benchmark 시작점이다. faster-whisper의 `vad_filter`나 `condition_on_previous_text`를 이름 그대로 Swift API에 넣지 않는다. 현재 공개 옵션은 [Configurations.swift](https://raw.githubusercontent.com/argmaxinc/argmax-oss-swift/main/Sources/WhisperKit/Core/Configurations.swift)를 확인한다.

### 모델 준비와 정규화

다운로드/검증/로드를 녹음 시작과 분리한다. 모델 준비가 안 됐어도 녹음은 된다. 로컬 ASR이 선택된 상태에서는 사용자 동의 없이 다른 클라우드 STT로 fallback하지 않는다. WhisperKit의 내부 청크 시간이 전체 파일 기준인지, segment 상대시간인지 **고정한 버전과 fixture로 확인**한다. 이미 global timestamp인 결과에 offset을 한 번 더 더하지 않는다.

P1 합격 조건은 한국어 샘플의 ASR 텍스트와 word timing을 확인하고 P0보다 E1/E2/누락/검수시간에서 어떤 차이가 나는지 보고하는 것이다. 로컬 실행이나 Large 모델 자체가 더 정확하다고 광고하지 않는다. 별도 SpeakerKit/community 모델이 존재하더라도 Precision-2의 대체품으로 몰래 사용하지 않는다.

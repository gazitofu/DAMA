# Soniox async API · 2026-09-11 공식 문서 대조

사용자 승인: Soniox를 기존 pyannote와 선택해서 비교. 녹음 후 전체 파일 async 처리이며 Python 실시간 예제를 별도 실시간 기능으로 확대하지 않는다. 실제 API 호출·정확도 검증은 아직 하지 않았다.

| 계약 | 공식 근거 |
|---|---|
| `stt-async-v5` 활성 모델 | [Models](https://soniox.com/docs/stt/models) |
| WAV multipart `POST https://api.soniox.com/v1/files`, Bearer key, 반환 UUID `id` | [Upload file](https://soniox.com/docs/api-reference/stt/files/upload_file) |
| `POST /v1/transcriptions`: model, file_id, language_hints ko/en, enable_speaker_diarization, enable_language_identification, client_reference_id | [Create transcription](https://soniox.com/docs/api-reference/stt/transcriptions/create_transcription) |
| `client_reference_id`는 추적값이며 고유성/idempotency 보장 없음. 접수 불명확 시 자동 POST 금지 | 위 Create transcription |
| `GET /v1/transcriptions/{id}`: queued/processing/completed/error, model, audio_duration_ms 및 에러/추적 메타데이터 | [Get transcription](https://soniox.com/docs/api-reference/stt/transcriptions/get_transcription) |
| 완료 후 `GET /v1/transcriptions/{id}/transcript`, id/text/tokens | [Get transcript](https://soniox.com/docs/api-reference/stt/transcriptions/get_transcription_transcript) |
| 토큰은 word/subword, start_ms/end_ms, text 안 원 공백. speaker 문자열, language, ASR confidence | [Timestamps](https://soniox.com/docs/stt/concepts/timestamps), [Speaker diarization](https://soniox.com/docs/stt/concepts/speaker-diarization), [Async example](https://soniox.com/docs/stt/async/async-transcription) |
| context general(key/value), text, terms. 공식 최대 8,000 tokens. 앱은 tokenizer 추정 대신 별도 보수적 7,500 UTF-8 bytes 상한을 쓰며 초과시 사용자에게 줄이도록 안내 | [Context](https://soniox.com/docs/stt/concepts/context) |
| 파일 최대 300분. 파일·전사 30일 자동삭제, 앱에서 조기삭제하지 않음 | [Limits](https://soniox.com/docs/stt/async/limits-and-quotas) |

## DAMA 구현 계약
- 하나의 분석 WAV 전체를 업로드한다. 매 저장 청크마다 별도 STT를 만들지 않는다. 입력 hash/Run/업로드 ID/작업 ID/요청 hash/모델/상태를 저장한다. raw 폴더의 upload/submission/poll 원응답과 `soniox-response.json`, request.json은 내부 저장소에 보존하며 Git에 넣지 않는다. 과금액은 추측하지 않는다. 서버 model이 없으면 Run.reportedModel은 nil, 정규화 모델 표시는 요청 모델이다.
- 기본 제공자는 pyannote. 새 변환/재전사만 선택값 사용, 재개는 영속 Run 입력 사용. 키체인 서비스 `com.gazitofu.Dama.soniox`, 기존 pyannote 서비스 이름 그대로.
- 업로드 또는 과금 POST의 응답 불명확/중단은 submissionUncertain. 재개 버튼으로 다시 제출하지 않는다. 명시적 새 재전사는 중복 가능성을 다시 안내한다. 완료 GET 실패는 같은 작업 ID를 유지한다.
- Soniox ASR 문맥은 OFF 기본. ON이면 맥락·참석자 general, 참고 텍스트 및 선택 폴더 발췌 text, 사용자 입력 terms의 전송값 전체 미리보기를 제공한다. 입력 화자 수는 로컬 메모이며 지원되지 않는 numSpeakers를 보내지 않는다. translation/translation_terms/yo 언어 힌트 없음.
- 독립 VAD/exclusive/화자 confidence map이 없는 응답에 그런 자료를 만들어 넣지 않는다. 따라서 pyannote missingSpeech 검출과 같은 증거를 확보했다고 말하지 않는다. token confidence는 별도 asrConfidence로 보존한다.
- Soniox 토큰 문자열을 정확히 연결한다. 정상 토큰은 원 순서/시간/화자/ASR confidence/language를 보존한다. 시간 오류는 raw 유지+null/검수 이슈. 알 수 없는 화자 nil, 재전사 화자 ID 새 namespace. text와 token 연결이 다르면 부분 실패로 보존한다.
- 같은 화자의 연속 유효 시간 토큰은 문장 단위로 묶고, 화자 전환/null/역행 시간은 넘지 않는다. 표시에서는 reading-v4 사용, Soniox 원문에는 임의 토큰 사이 공백을 추가하지 않는다. 겹말은 토큰 시간으로 확인되는 경우만 검수 표시.
- 비교 옵션 ON 기본으로 새 작업의 자동 AI 교정 OFF. 기존 교정 설정/수정 이력은 바꾸지 않으며 비교 옵션 OFF 후 명시적으로 교정 가능.

## 한계
- 한국어/다중 화자 실품질 미측정, 자동 우승 모델 선정 없음. API 키·실제 계정/오디오 전송은 앱 내 확인 후 사용자 검증 필요.
- 원격 조기삭제 UI, 비용 조회/청구액, realtime, 큰 참고 자료의 요약/분할은 후속 범위.

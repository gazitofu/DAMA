# Nari Labs STT API 계약 · 1차 출처 실검증 기록

검증일 **2026-09-14** · 검증자 = Dama 메인 세션 · 방법 = 공식 문서 원문(markdown) 직접 조회 (계정 없음, 실호출 0건)

출처: `https://docs.narilabs.com/{stt-quickstart, transcribe-audio, transcripts-and-turn-detection, models-and-pricing, rate-limits, usage-and-billing, errors, authentication}.md` 및 `api-reference/speech-to-text/realtime/realtime-transcription.md`. 사용자 요청(2026-09-14)으로 "독립 전사 엔진 후보"로 검토했다. 정확도·속도·실제 청구는 **미측정**이다.

## 1. 계약 요약

| 항목 | 1차 출처 | Dama 관점 |
|---|---|---|
| 엔드포인트 | `WSS wss://api.narilabs.com/v1/realtime?intent=transcription` 단일. HTTP 배치·파일 업로드 전사 endpoint **없음** | 저장된 녹음도 WebSocket으로 스트리밍해야 한다 |
| 인증 | `Authorization: Bearer <key>`. 키는 조직 소속, `https://app.narilabs.com/keys` | Keychain 슬롯 1개 추가 |
| 모델 | `qwen3-asr:free`, `qwen3-asr-fast:free` (무료) · `qwen3-asr` $0.06/h, `qwen3-asr-fast` $0.12/h (Partner, public alpha 중 `founders@narilabs.com` 신청) | 로컬 비교 경로의 Qwen3-ASR과 같은 계열. 크기(1.7B 등)는 문서에 없음 |
| 오디오 | 16 kHz · mono · PCM16 LE · WAV 헤더 없음 · base64 · JSON 메시지 ≤128 KiB. 샘플레이트 변경 불가 | analysis WAV(16 kHz)를 그대로 슬라이스 가능 |
| 언어 | `language` enum 30종, **`ko` 포함**. null이면 자동 인식 | 한국어 고정 권장. 영어 혼용 시 자동 인식 동작은 미검증 |
| 문맥 | `prompt: string|null` "Names or terminology to help recognition", 세션 전체에 적용. 길이 제한 미기재 | `meetingTerms` 전달 위치. Soniox `terms`와 같은 역할 |
| 발화 경계 | 수동 `input_audio_buffer.commit` 또는 `turn_detection: {type: server_vad, threshold 0.5, prefix_padding_ms 300, silence_duration_ms 500}` | 저장 음원 처리에는 수동 commit이 결정적이다 |
| 발화 길이 한도 | **36초**. 초과 시 `commit_reason: max_duration`으로 강제 종료, 연결 유지 | 36초 넘는 발화는 클라이언트가 나눠야 한다 |
| 유휴 한도 | 60초 무음 전송 시 연결 종료 (최종 결과 대기 중은 예외) | |
| 동시성 | 조직당 **2 연결** (모델·키·Playground 공유) | 병렬 청크 처리 불가에 가깝다 |
| 무료 일일 한도 | STT 모델별 **100 accepted connections/일**, 00:00 UTC 초기화. 접수 후 실패·취소는 복원 안 됨 | 연결 1개로 여러 발화 처리 가능 → 녹음 1건 = 연결 1개면 충분 |
| 과금 | Partner: 접수된 입력 오디오 초 단위, 무음 포함, 연결 실패·취소 후에도 차감. Free: 크레딧 미차감 | 자동 재제출 금지 원칙(함정 2) 그대로 적용 |
| 결과 | `transcript.completed { item_id, transcript, language, commit_reason, usage.input_audio_seconds }`. partial은 전체 가설 교체 | |
| 시간 정보 | **단어·세그먼트 타임스탬프 없음.** VAD 모드에서만 `speech_started.audio_start_ms` / `speech_stopped.audio_end_ms` (연결 누적 타임라인, 발화 단위) | Dama 결합 파이프라인의 전제(단어 시간) 부재 |
| 화자분리 | **없음** | 화자는 P2로 별도 확보해야 한다 |
| 오류 | WS: `INVALID_REQUEST, SESSION_SETUP_TIMEOUT(10초 내 configure), MODEL_NOT_FOUND, PARTNER_ACCESS_REQUIRED, FREE_DAILY_LIMIT_EXCEEDED, INSUFFICIENT_CREDITS, SESSION_CONFIGURATION_LOCKED, SESSION_IDLE_TIMEOUT, VAD_*, SERVER_DRAINING, INTERNAL_ERROR`. HTTP 429 `CONCURRENCY_LIMIT_EXCEEDED / UPSTREAM_RATE_LIMITED` | 429·5xx는 backoff, 402/403은 대기 상태 |

## 2. 문서에 없어서 실측이 필요한 항목

- 저장 음원을 **실시간보다 빠르게** 전송해도 되는지(서버가 pacing을 요구하는지). 문서는 100 ms 간격 예시만 있고 금지 문구는 없다. 실시간 pacing이 강제되면 1시간 녹음 = 1시간 전사가 된다.
- `prompt` 길이 상한, 한국어 용어 효과.
- 데이터 보관·학습 사용·처리 지역 정책. 문서에 **retention/privacy 조항이 없다.** 동의 문구에 "보관 정책 미확인"으로 표기해야 한다.
- 한국어 정확도, 36초 강제 분할 지점의 단어 손실 여부, `qwen3-asr` 대 `-fast` 품질 차.
- Partner 승인 가능 여부와 일정. 미승인 상태에서는 무료 모델만 쓸 수 있고 "100 연결/일 · 2 동시"가 상한이다.

## 3. Dama 통합 시 계약상 제약

1. 단어 시간이 없으므로 `SonioxPrecisionReconciler`·`QwenNormalizer`의 토큰 단위 P2 coverage 계산을 그대로 쓸 수 없다. 발화(utterance) 단위 시간만 클라이언트가 안다(보낸 바이트 오프셋 = 시간).
2. 따라서 화자 귀속의 유일한 정직한 경로는 **P2 exclusive 구간을 먼저 확보하고, 구간별로 오디오를 잘라 발화 1개 = P2 화자 1명**으로 보내는 것이다. 발화 안의 단어는 시간 없음(`timingOrigin: none`)으로 두고, Turn 시간은 구간 시간을 쓴다. INV-06(A→짧은 B→A 장벽)은 P2 구간이 이미 나눠 주므로 유지된다.
3. 36초 초과 구간은 클라이언트가 나눈다(초기값: 저에너지 지점 우선, 없으면 36초 경계). 나뉜 조각의 텍스트 결합은 원문 그대로 이어붙이며 문장 재구성 금지.
4. 짧은 구간(수백 ms)을 개별 발화로 보내면 문맥이 없어 오인식 가능성이 높다. 이는 정확도 실험의 주요 실패 경로다.
5. 새 외부 목적지(api.narilabs.com)이므로 녹음별 동의 확인이 필요하고(함정 8), raw 이벤트 로그 전체를 `raw/nari-response.json`으로 보존한다.

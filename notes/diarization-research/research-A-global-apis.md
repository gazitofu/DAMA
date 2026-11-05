# 리서치 A: 글로벌 상용 클라우드 API 화자분리 갱신 조사 (2025-09 ~ 2026-10)

- 조사일: 2026-10-14. 모든 가격·스펙은 이 날짜에 1차 출처(벤더 문서·가격표·changelog)를 열어 확인했다. 1차 출처에서 확인 못한 값은 "미확인" 또는 "2차 출처"로 표시했다.
- 읽기 전용 조사. 가입·로그인·업로드·폼 제출 없음.
- 벤치마크 표기: **V** = 벤더 자체 주장, **C** = 경쟁 벤더가 측정, **I** = 독립·학술 측정. 영어 데이터셋 결과는 한국어 성능의 근거가 아니다.
- 사용자 우선순위(조정 반영): ① 화자 수 붕괴(3명→2명, 1명→2명) ② E1 오귀속 ③ E2 병합. 그래서 화자 수 제어(정확값/최소·최대), 비슷한 목소리 군집, 화자 등록(voiceprint) 식별, 화자 수 추정 정확도 근거를 우선 정리했다.

## 0. 결론 요약

1. **pyannoteAI Precision-3**가 이 기간의 가장 직접적인 개선이다. 현 파이프라인의 `precision-2`를 enum 한 줄로 바꿔 시험할 수 있고 가격은 같다. 벤더 주장 기준 화자 혼동(confusion)이 단일 화자 구간 -17.8%, 겹침 구간 -20.7%다. 단 화자 수 추정 정확도 수치는 P3에 대해 공개되지 않았고 한국어 데이터셋도 없다.
2. **화자 수 붕괴를 구조적으로 막는 수단**은 두 가지뿐이다. (a) 화자 수를 정확값 또는 하한·상한으로 강제(pyannote `numSpeakers/minSpeakers/maxSpeakers`, AssemblyAI `speakers_expected`·hard min/max, AWS `MaxSpeakerLabels`), (b) 참석자 음성 등록 후 식별(pyannote voiceprint+identify, Speechmatics speaker identifiers, ElevenLabs speaker library, OpenAI known speaker 클립). Soniox·Deepgram은 화자 수 파라미터가 없다.
3. **Soniox는 stt-async-v5(2026-06-11) 이후 새 모델이 없다.** 화자 수 제어 파라미터도 없다. 경쟁사(AssemblyAI)가 측정한 영어 cpWER 표에서 Soniox v5 Async는 회의(AMI 58.93, NOTSOFAR 67.29/58.36)에서 비교 대상 7개 중 최하위였다(C, 영어). 사용자가 겪는 화자 품질 문제와 방향이 일치하지만 경쟁사 측정이라 그대로 믿지 않는다.
4. **OpenAI 화자분리 경로는 끝나간다.** `gpt-4o-transcribe-diarize`는 2026-08-26 폐기 공지, 2027-02-26 종료. 후속 `gpt-transcribe`(2026-07-28)는 화자분리 언급이 없다.
5. **한국어 화자분리를 공개 벤치마크로 검증한 상용 API는 하나도 찾지 못했다.** 결국 자체 한국어 녹음으로 비교해야 한다.

## 1. 후보 표

| 이름 / 모델 id | 출시·최종 갱신 (출처) | 한국어 근거 | 화자분리 기능 (화자 수 제어 · 단어 단위 · 겹침 · 신뢰도 · 등록) | 가격/h (2026-10-14 확인) | 데이터 정책 | 벤치마크 (측정 주체) | 판정 |
|---|---|---|---|---|---|---|---|
| **pyannoteAI Precision-3** / `precision-3` | changelog 목록 2026-09-17 "Precision-3 now available on API and On-Premise". 블로그·개별 페이지 메타데이터는 2026-10-12. API 기본값은 아직 `precision-2`, P3는 opt-in이며 추후 기본값 전환 후 P2 폐기 예정(날짜 미공개) | 언어 무관 음향 모델이라는 벤더 주장. 벤치 15개 중 AISHELL·AliMeeting(중국어) 포함, 한국어 데이터셋 없음 | `numSpeakers`(정확값), `minSpeakers`/`maxSpeakers`. 단 짧은 파일에 화자가 많으면 무시될 수 있고 warning 반환. 신규 `vadSensitivity`(-5~5, 높을수록 한 단어 턴 검출), `crosstalkSensitivity`(-5~5), 출력 `speakerProbability`(화자별 프레임 확률), `speechProbability`, `crosstalkProbability`. `turnLevelConfidence` 유지. 프레임 `confidence`는 P3에서 에러(폐기). `exclusive` 파라미터는 P3 제한 표기 없음(실호출 미확인). 단어 단위 출력은 STT orchestration 사용 시에만 | Developer €0.112/h, Starter €0.096/h (P2와 동일가) | 고객 데이터로 학습하지 않음, 결과 24h 후 삭제, 업로드 48h 내 삭제, EU 처리 옵션 | V: 15개 데이터셋 평균 DER 16.02→14.35(-10.4%). 오류 분해: confusion 단일 3.13→2.57, 겹침 1.59→1.26, 겹침 miss 4.09→3.30, **단일 화자 구간 miss 2.81→3.02(악화)**. 화자 수 추정 정확도 P3 수치 미공개. I(ETH, arXiv 2509.26177, 2025-09): P2 기반 pyannoteAI가 5개 시스템 중 최저 DER 11.2% (영·중·독·일·서) | **즉시 시험** (현 P2 자리에 drop-in, 동가, 화자 혼동 감소 주장) |
| **pyannoteAI Voiceprint + Identify** / `POST /v1/voiceprint`, `POST /v1/identify` | identify가 `model: precision-3` 지원 (API 레퍼런스, 2026-10-14 확인) | 등록 음성 언어 무관이라고 문서화 | voiceprint는 단일 화자 최대 30초 음성 1개/인. identify에 voiceprint 1~50개, `matching.exclusive`(기본 true, 한 voiceprint에 여러 화자 매칭 금지), `matching.threshold` 0~100(기본 0이라 모두 매칭되므로 조정 필요), 화자별 후보 confidence. 미매칭은 `match: null`로 diarization 라벨 유지. `numSpeakers/min/max`·`exclusive`·P3 확률 출력 동일 지원. STT orchestration과는 병용 불가 | voiceprint €0.015/개. identify는 가격표상 "Volume-based", 문서상 오디오 길이 과금(최소 20초) | 위와 동일. voiceprint는 pyannote가 저장하지 않고 클라이언트가 보관 | 식별 정확도 공개 수치 없음 | **즉시 시험** (참석자 사전 등록이 가능한 회의에서 화자 수 붕괴 직접 대응. INV-03·09와의 계약 검토 필요) |
| pyannoteAI STT Orchestration | 2025-12-11 출시(Parakeet), 2026-01-15 Whisper large-v3-turbo 추가 | 기본 `parakeet-tdt-0.6b-v3`는 유럽어 중심이라 한국어 근거 없음. `faster-whisper-large-v3-turbo`는 Whisper 계열이라 한국어 포함(정확도 미확인) | `wordLevelTranscription`(word·start·end·speaker), `turnLevelTranscription`. P2·P3 지원. BYO STT는 서버 엔드포인트가 아니라 클라이언트 병합 레시피(세그먼트 단위, WhisperX 방식) | €0.168/h (BYO €0.146/h, 가격표상 Enterprise 성격) | 위와 동일 | 없음 | **관찰** (한국어 ASR이 Soniox보다 약할 가능성. 서버측 단어 정렬 참조 구현으로만 가치) |
| **Soniox** / `stt-async-v5` | 2026-06-11 출시, 이후 신모델 없음(models 페이지 2026-10-14). v4는 2026-06-30에 v5로 alias | 블로그에 Korean-English 코드스위칭 예시. 한국어 화자분리 수치 없음 | `enable_speaker_diarization` 불리언만. 화자 수·최소·최대 파라미터 없음. 최대 15명. "비슷한 목소리면 정확도 저하" 명시. 토큰 단위 speaker 라벨 | $0.10/h (화자분리 포함) | 학습 미사용, Async 저장분 30일 자동 삭제 | V: "speaker separation completely reengineered", 수치 없음. **C(AssemblyAI, 2026-07-07, 영어)**: 평균 cpWER 44.58로 7개 중 최하위, AMI 58.93, NOTSOFAR dev 67.29. 전화(CallHome)는 16.11로 상위권 | **현행 유지, 화자 판단 근거로는 비교본만** |
| **ElevenLabs Scribe v2** / `scribe_v2` | 2026-01-09 출시(공식 블로그). scribe_v1은 2026-07-09 제거 예정 공지. 2026-09-11 `scribe_v2_medical` GA | STT 언어 표에서 Korean "Good (>10% ~ ≤20% WER)" 등급 | `diarize`, `num_speakers`는 **최대값**(≤32, 정확값 아님). `diarization_threshold`(기본 약 0.22, 2025-06-30 changelog상 0.1~0.4): 높이면 병합 쪽, 낮추면 분할 쪽. **num_speakers와 동시 사용 불가**. 단어 단위 `speaker_id`·`logprob`. `use_speaker_library`(워크스페이스 등록 화자와 매칭, 등록 방법·출시일 미확인). `detect_speaker_roles`(agent/customer, +10%) | $0.22/h (keyterm +$0.05/h) | 학습 opt-out 토글 존재(2차 출처), Zero Retention은 Enterprise 전용(1차 문서) | C(AssemblyAI, 영어): 평균 cpWER 35.26(7개 중 2위), CallHome 14.82·16.18로 1위, NOTSOFAR 51.29/44.37. I(Indic DiarBench, 2026-07): DER 35.0, cpWER 58.3, confusion 15.3으로 confusion 높음 | **즉시 시험** (단어 단위 화자, 분할·병합 임계값을 직접 조절 가능. 단 정확값 강제 불가) |
| **AssemblyAI Universal-2** / `universal-2` (+`speaker_labels`) | Universal-3.5 Pro 출시 2026-07-07이지만 한국어는 여전히 Universal-2로만 처리 | Korean "Good (10–25%)" 등급(Universal-2). U3.5 Pro는 18개 언어에 한국어 없음, 미지원 언어는 무경고 U2 fallback 가능 | **`speakers_expected`(정확값)**, `speaker_options.min_speakers_expected`(hard 하한)/`max_speakers_expected`(hard 상한, 초과 화자는 기존 라벨로 병합). 기본 상한은 길이별 10/30. 단어 단위 `speaker` + `include_speaker_confidence`. Speaker Identification(이름 치환)은 `speech_understanding` 기반으로 음성 등록 방식인지 미확인 | U2 $0.15 + 화자분리 $0.02 = $0.17/h | 기본은 약관상 학습 허용, 유료 계정은 대시보드에서 opt-out(소급 불가). EU 서버·BAA는 학습 제외 | V(U3.5 Pro, 영어): 평균 cpWER 30.17. U2 한국어 화자분리 수치 없음. I(Indic DiarBench): U2 DER 40.5, cpWER 88.6(최하위권) | **즉시 시험** (정확값·hard 하한 강제가 화자 수 붕괴 대조군으로 유일. U2 품질은 회의적) |
| AssemblyAI Universal-3.5 Pro / `universal-3-pro` | 2026-07-07 | 한국어 미지원(18개 언어) | 전사·화자 전환 공동 모델링 주장 | $0.21/h | 위와 동일 | V: cpWER 30.17 | **제외** (한국어 미지원) |
| Deepgram Nova-3 + Batch Diarization v2 / `nova-3`, `diarize_model=v2` 또는 `latest` | Diarization v2 2026-05-13 changelog. Nova-3 한국어 개선 모델 2026-08-04, 한국어 띄어쓰기 버그 수정 2026-05-28(self-hosted) | Nova-3·Nova-2 한국어(`ko`,`ko-KR`) 지원. 한국어 화자분리 수치 없음 | 화자 수 파라미터 문서에 없음. 단어 단위 `speaker` + `speaker_confidence`(batch). v2는 batch 전용. `diarize=true`는 v1로 라우팅되니 `diarize_model` 필수 | Nova-3 mono $0.0043/min ≈ $0.26/h, multilingual ≈ $0.31/h (PAYG, 화자분리 포함) | Model Improvement Program, 요청별 `mip_opt_out=true`. opt-out 시 50% 할인 상실이라는 서술은 2차 출처(공식 페이지에 가격 언급 없음, 미확인) | V: v2가 v1 대비 사람 선호 3.3배, contact-center median confusion 약 -80%. C(영어): Nova-3 EN 평균 cpWER 37.92. I(Indic): DER 32.0, cpWER 63.2 | **관찰** (화자 수 제어 없음이 우선순위 1과 정면 충돌) |
| Speechmatics Standard / Enhanced (+ Speaker Identification) | 2026-03-04 changelog에 Enhanced 화자분리 정확도 개선(수치 없음). Melia 1 batch preview 2026-06-17, realtime 2026-10-13 | 한국어 `ko` batch Standard·Enhanced·Melia 1·Oak 1 지원. 한국어 화자분리 명시 없음(미확인) | batch: `speaker_sensitivity`(0~1, 높을수록 화자 증가), `prefer_current_speaker`(짧은 턴 놓칠 수 있음 명시). batch 문서에 max_speakers 없음. 단어 단위 `speaker`(S1.., UU). **화자 등록**: `get_speakers`로 identifiers 추출 후 `speakers`에 label+identifiers 전달, 미매칭은 S1 유지 | Standard $0.45/h, Enhanced $0.75/h (학습 opt-in 시 각 $0.30/$0.50). Melia $0.129/h부터 | 학습 기본 OFF, batch 데이터 7일 내 자동 삭제 | V: 수치 없음. pyannote 벤치 페이지에 비교 대상으로 있으나 수치는 이미지라 미추출 | **관찰** (등록 기반 식별이 필요할 때 pyannote 다음 대안. Enhanced는 기준가에 근접) |
| Google Chirp 3 / `chirp_3` (STT v2) | GA 2025-10-13(전사, 화자분리 포함), 지역 확대 2025-11-13 | 화자분리 언어 14개 목록에 Korean 포함 | min/max speaker count 예시(1~6)와 "not currently used" 서술이 문서 간 충돌. BatchRecognize 약 1시간 한도, **단어 타임스탬프는 약 20분 한도** | 1차 가격표 본문 미추출(미확인) | 미확인 | 없음 | **제외** (2시간 회의 불가, 단어 정렬 20분 한도) |
| Google Gemini 3.5 Transcribe / `gemini-3.5-transcribe` | 모델 페이지 "August 2026" 갱신, 2026-09-01 기준 문서 | ko-KR 지원(85+ 로캘) | `diarization: true`, **최대 8명, 3명 이상은 experimental**, 이름 지정 불가. 단어 단위 `words` + `speakerLabel`. **화자분리·단어 타임스탬프 사용 시 30분 한도**, custom vocabulary와 병용 불가 | $0.003/min ≈ $0.18/h (유료 등급) | 유료 등급 데이터는 제품 개선 미사용 | V(MS 발표의 비교 대상으로만 등장). I(Indic, 범용 Gemini 3 Pro): DER 74.0, 짧은 맞장구 누락·타임스탬프 불안정 | **제외** (30분 청크 분할 시 Run 내 화자 ID 불일치, 3명 이상 실험적) |
| OpenAI gpt-4o-transcribe-diarize | 2025-10 중순 출시(Azure 카탈로그 2025-10-15, 1차 changelog 미확인). **2026-08-26 폐기 공지, 2027-02-26 종료** | gpt-4o-transcribe 계열(한국어 수치 없음) | `diarized_json` 세그먼트(speaker,start,end,text). **단어 타임스탬프 없음**. known speaker 참조 클립 최대 4명, 2~10초. 파일 25MB, 30초 초과 시 `chunking_strategy` 필수 | $0.006/min ≈ $0.36/h | API 데이터 기본 학습 미사용(일반 정책, 이번 세션 1차 확인 안 함) | I(Indic, gpt-4o-transcribe): DER 36.2, cpWER 83.1 | **제외** (단어 단위 없음, 종료 예정, 후속 모델에 화자분리 없음) |
| OpenAI gpt-transcribe | 2026-07-28 | 언어 힌트 다중 지원, 목록 미기재 | 화자분리 언급 없음 | $0.0045/min ≈ $0.27/h | 위와 동일 | 없음 | **제외** (화자분리 없음) |
| Microsoft MAI-Transcribe-2 (Azure Speech enhancedMode) | 2026-09-03 발표, public preview(문서 2026-09-24 갱신). MAI-Transcribe-1은 2026-08-20 폐기 | 언어 표에 `ko` 지원 | `diarization.enabled`, 세그먼트 단위 speaker + `timestamps: "word"`로 단어 타이밍. 화자 수 파라미터 문서에 없음. 화자분리 시 처리 가능 길이가 더 짧다고 명시(수치 미확인). fast transcription 동기 API 한도 2시간·250MB | $0.10/h (2026년 말까지 한정 프로모, 정가 미공개) | 미확인 | V: FLEURS 평균 WER 5.2%, 화자분리 수치 없음 | **관찰** (preview·SLA 없음·정가 미정·길이 한도 미확인) |
| Azure 기존 fast transcription diarization | 문서 2026-08-10 갱신 | ko-KR 전사 지원, 화자분리 언어 지원 미확인 | `maxSpeakers` 힌트 2~35, speaker는 phrase 단위(단어에 speaker 없음) | 미확인 | 미확인 | I(Indic, Azure STT): DER 34.8, miss 24.4로 매우 높음 | **제외** |
| AWS Transcribe | 큰 변경 없음 | ko-KR batch·streaming 지원 | `ShowSpeakerLabels`, `MaxSpeakerLabels`(최대 30), 단어(item) 단위 `speaker_label`. batch 8시간·2GB | 예시 단가 $0.006/min ≈ $0.36/h(US East 예시, 화자분리 포함) | 기본은 서비스 개선에 사용 가능, AWS Organizations AI opt-out 정책으로 거부 | **I(Indic DiarBench, 2026-07, 저자 Sarvam/AI4Bharat)**: 상용 API 중 최상위 DER 23.5, cpWER 43.7, confusion 7.4 | **관찰** (독립 비영어 벤치 상위. 화자 상한 지정 가능. 단 한국어 근거 아님, opt-out 설정 필요) |
| Mistral Voxtral Mini Transcribe V2 / `voxtral-mini-latest` | 2026-02-04 | 13개 언어에 Korean 포함 | `diarize`, `timestamp_granularities` segment/word(단 `language`와 병용 불가), 3시간 한도. speaker 출력 단위·화자 수 파라미터 미확인 | $0.003/min ≈ $0.18/h | 미확인 | V: 영어 5종 + TalkBank 다국어(독·서·영·중·일) 평균 DER, 수치는 차트라 미추출. C(영어): 평균 cpWER 37.52 | **관찰** (저가·한국어·3시간. 출력 형태 1차 확인 필요) |
| xAI Grok STT → Grok Voice Transcribe 2.0 / `grok-voice-transcribe-2.0` | v1 2026-04-17(공식). v2.0 2026-09-18(2차 출처) | 25개 포맷 언어에 한국어 포함(2차 출처), 공식 발표는 언어명 미기재 | 단어 단위 speaker_id(2차 출처), 화자 수 파라미터 미확인 | $0.10/h batch (공식) | 미확인 | C(영어, v1 추정): 평균 cpWER 42.58 | **관찰** (1차 문서 접근 실패, 확인 후 판단) |
| Gladia (Solaria) | 2026-09-19 가격 변경 보도(2차 출처, 진위 미확인) | 100+ 언어 주장 | `number_of_speakers`, `min_speakers`, `max_speakers`는 강제 아닌 힌트. utterance 단위 speaker | Starter $0.61/h, Growth $0.20/h부터 | Growth부터 학습 opt-out 자동, Starter 불명 | C(영어): 평균 cpWER 36.87 | **제외** (힌트만, Starter 학습 정책 불명, 기준가 근접) |
| Rev.ai | 신규 확인 없음 | 한국어 화자분리 근거 없음 | 화자 수 옵션은 영·서·불만이라는 2차 출처 | 미확인 | 미확인 | 없음 | **제외** |
| smallest.ai Pulse STT | 한국어 streaming 추가(날짜 미기재) | "Korean not formally supported on batch" | 미확인 | 미확인 | 미확인 | 없음 | **제외** |

## 1-1. 화자 수 붕괴 관점 정리 (우선순위 1)

| 서비스 | 정확값 강제 | 하한/상한 | 분할·병합 감도 | 음성 등록 식별 | 화자 수 추정 정확도 근거 |
|---|---|---|---|---|---|
| pyannote P3 | `numSpeakers` | `min/maxSpeakers` | 없음(VAD·crosstalk 감도만) | voiceprint 최대 50개, threshold·exclusive 매칭 | P2: 내부 250파일(2~10명)에서 정확 화자 수 70%(P1 50%) V. P3 수치 미공개 |
| AssemblyAI U2 | `speakers_expected` | hard min/max, 초과분은 기존 라벨로 병합 | 없음 | 미확인(이름 치환 기능은 있음) | 없음 |
| ElevenLabs Scribe v2 | 불가(최대값만) | 상한만(`num_speakers`) | `diarization_threshold`(상한과 병용 불가) | `use_speaker_library`(등록 절차 미확인) | 없음 |
| AWS Transcribe | 불가 | 상한 `MaxSpeakerLabels` ≤30 | 없음 | 없음 | 없음 |
| Speechmatics | 불가(batch 문서 기준) | 없음 | `speaker_sensitivity` 0~1 | speaker identifiers | 없음 |
| Azure fast | 불가 | `maxSpeakers` 힌트 2~35 | 없음 | 없음 | 없음 |
| Google Chirp 3 | 문서 충돌 | 1~6(동작 여부 충돌) | 없음 | 없음 | 없음 |
| Gemini 3.5 Transcribe | 불가 | 최대 8명 고정 | 없음 | 없음 | 3명 이상 experimental |
| OpenAI diarize | 불가 | 없음 | 없음 | 참조 클립 최대 4명 | 없음 |
| Soniox v5 | 불가 | 없음(최대 15명) | 없음 | 없음 | 없음 |
| Deepgram v2 | 불가 | 없음 | 없음 | 없음 | 없음 |
| Gladia | 힌트만 | 힌트만 | 없음 | 없음 | 없음 |

해석: 화자 수를 알고 있는 녹음이라면 pyannote `numSpeakers`와 AssemblyAI `speakers_expected`가 직접 대응한다. 다만 정확값 강제는 "3명을 3명으로 맞추는 것"이지 "누가 누구인지"를 보장하지 않는다. 비슷한 목소리 2명을 1명으로 묶던 모델은 강제 시 다른 사람을 쪼개 숫자만 맞출 수 있다(실패 경로). 이 경우를 직접 막는 것은 등록 식별이다.

## 2. 2025-09 이후 새로 나온 것

| 날짜 | 항목 | 출처 등급 |
|---|---|---|
| 2025-09-29 | pyannote Community-1 (OSS, exclusive 지원) | 1차 |
| 2025-10-06 | pyannote 신규 요금제 | 1차 |
| 2025-10-13 | Google Chirp 3 전사 GA, 화자분리 포함 | 1차 |
| 2025-10 중순 | OpenAI gpt-4o-transcribe-diarize (Azure 카탈로그 2025-10-15) | 2차·Azure |
| 2025-10-21 | Soniox stt-async-v3 | 1차 |
| 2025-12-11 | pyannote STT Orchestration (Parakeet) | 1차 |
| 2026-01-09 | ElevenLabs Scribe v2 (batch, 32명) | 1차 블로그 |
| 2026-01-15 | pyannote STT Orchestration에 Whisper large-v3-turbo | 1차 |
| 2026-01-29 | Soniox stt-async-v4 | 1차 |
| 2026-02-04 | Mistral Voxtral Transcribe 2 (Mini Transcribe V2 batch 화자분리, 한국어) | 1차 |
| 2026-03-04 | Speechmatics Enhanced 화자분리 정확도 개선, 채널+화자 모드 | 2차(changelog 검색 요약) |
| 2026-04-17 | xAI Grok STT API (batch $0.10/h, 화자분리) | 1차 |
| 2026-05-04 / 07-07 | pyannote 스트리밍 Live-1 베타 / GA | 1차 |
| 2026-05-13 | Deepgram Batch Diarization v2 (`diarize_model`) | 1차 |
| 2026-06-11 | Soniox stt-async-v5 (화자 분리 재설계 주장) | 1차 |
| 2026-06-17 | Speechmatics Melia 1 batch preview | 1차 |
| 2026-07-07 | AssemblyAI Universal-3.5 Pro (한국어 미지원) | 1차 |
| 2026-07-28 | OpenAI gpt-transcribe / gpt-live-transcribe (화자분리 언급 없음) | 1차 |
| 2026-08-04 | Deepgram Nova-3 한국어 포함 개선 모델 | 1차 |
| 2026-08-26 | OpenAI 전사 모델 4종 폐기 공지(diarize 포함), 2027-02-26 종료 | 1차 |
| 2026-08 | Google Gemini 3.5 Transcribe (화자분리 8명, 30분) | 1차 |
| 2026-09-03 | Microsoft MAI-Transcribe-2 (preview, 한국어, 화자분리, $0.10/h 한정) | 1차 |
| 2026-09-17 | **pyannote Precision-3** (API·온프렘) | 1차 |
| 2026-09-18 | xAI Grok Voice Transcribe 2.0 | 2차 |
| 2026-09 | AssemblyAI Universal-3.6 Pro Realtime (streaming, 한국어) | 1차(llms 참조 문서) |

## 3. 벤치마크 정리

- **한국어 화자분리 공개 벤치마크: 찾지 못함.** 상용 API를 한국어 DER/cpWER로 비교한 1차·학술 자료 없음(2026-10-14 검색 기준).
- **I, ETH Zurich, arXiv 2509.26177 (2025-09-30)**: 상용은 pyannoteAI(P2)만 포함. pyannoteAI DER 11.2%, DiariZen 13.3%. 주 오류원은 missed speech, 다음이 speaker confusion. 화자 수 추정 정확도 미보고. 언어: 영·중·독·일·서.
- **I(이해관계 있음), Indic DiarBench, arXiv 2607.23808 (2026-07-26)**: 저자 소속 Sarvam AI·AI4Bharat이고 1위가 자사 Sarvam(DER 16.0). 상용 API 순위: AWS(DER 23.5/cpWER 43.7) > Deepgram Nova-3(32.0/63.2) > Azure(34.8/60.8) > ElevenLabs Scribe(35.0/58.3) > GPT-4o Transcribe(36.2/83.1) > AssemblyAI U2(40.5/88.6) > Gemini 3 Pro(74.0/58.9). pyannote·Soniox 미포함. 인도 22개 언어라 한국어와 직접 연결 불가. Gemini는 맞장구·짧은 발화 누락 지적(사용자의 "네/아" 누락 문제와 같은 유형).
- **C, AssemblyAI (2026-07-07, 영어 6개 데이터셋, cpWER)**: U3.5 Pro 30.17 / ElevenLabs 35.26 / Gladia 36.87 / Voxtral 37.52 / Deepgram 37.92 / Grok 42.58 / Soniox v5 44.58. 경쟁사 설정 공개 없음.
- **V, pyannote Precision-3 (15개 데이터셋 평균 DER)**: 14.35 vs P2 16.02. 경쟁 대비 "AISHELL 40% 낮음, AliMeeting 3배" 주장이나 경쟁사 미지명. pyannote 공개 벤치 페이지(DIHARD 259개, 2026-10-12 갱신)는 P3·Soniox v5·ElevenLabs·AssemblyAI·Deepgram·Speechmatics를 화자 수 미제공 조건으로 비교하나 수치가 이미지라 이번 조사에서 추출하지 못함(미확인).
- **V, Deepgram v2**: 사람 선호 3.3배, contact-center median confusion 약 -80%. DER 수치 아님.
- 측정 조건 경고: collar·겹침 채점·oracle VAD 여부로 수치가 크게 달라진다(pyannote 블로그도 인정). DER과 cpWER은 서로 순위를 뒤집을 수 있다.

## 4. 반론과 실패 경로

- **P3 개선폭은 작고 벤더 측정이다.** 평균 DER 1.67pt. 단일 화자 구간 missed detection은 오히려 악화(+7.5%)했다. 짧은 맞장구 누락이 핵심 불만이라면 `vadSensitivity`를 올려야 하고, 그러면 false alarm이 늘 수 있다. 한국어 회의에서 실측 전에는 개선을 단정하지 않는다.
- **정확값 강제의 역효과.** 비슷한 목소리를 합치던 모델에 `numSpeakers=3`을 주면 숫자는 맞지만 한 사람을 둘로 쪼개고 다른 둘을 합친 상태가 될 수 있다. 화자 수 일치를 성공 지표로 쓰면 안 된다(CLAUDE.md 운영 원칙과 동일).
- **등록 식별은 데이터 계약을 건드린다.** voiceprint는 생체 정보에 가깝다. 저장 위치(pyannote는 클라이언트 보관), 동의, INV-09(Run 간 자동 매핑 금지)와 충돌 여부를 먼저 정해야 한다. threshold 기본 0은 "모두 매칭"이라 그대로 쓰면 모르는 화자를 등록 화자로 채운다(INV-03 위반 위험).
- **단일 공급자 통합 STT로 갈아타는 것의 위험.** ElevenLabs·AssemblyAI U2의 한국어 WER은 "10~20%/10~25%" 등급이라 Soniox 원문 품질보다 나쁠 가능성이 크다. 이들은 화자 신호원으로만 쓰고 원문은 Soniox를 유지하는 결합 구조가 현실적이다. 그 경우 공급자 간 단어 정렬 비용이 다시 생긴다.
- **경쟁사 벤치의 Soniox 최하위 결과는 영어 회의 기준이다.** 한국어에서도 같다는 근거는 없다.
- **가격 리스크.** MAI-Transcribe-2 $0.10/h는 2026년 말 종료 프로모. Deepgram은 학습 opt-out 시 실가가 오를 수 있다(2차 출처).

## 5. 미확인 목록

- pyannote P3의 화자 수 추정 정확도, `exclusive` 실제 동작, 한국어 성능, P2 폐기 일정.
- ElevenLabs speaker library 등록 절차·출시일, 학습 opt-out 1차 문서.
- AssemblyAI U2의 한국어 화자분리 지원 명시(문서에 언어 목록 없음), Speaker Identification이 음성 등록 방식인지.
- Speechmatics 한국어 화자분리 지원 명시, speaker identification 출시일·언어 제한, batch max_speakers.
- Google Chirp 3 가격·min/max 실제 동작.
- MAI-Transcribe-2 화자분리 시 길이 한도·데이터 정책·정가.
- Voxtral 화자 출력 단위(세그먼트/단어)와 화자 수 파라미터.
- xAI Voice Transcribe 2.0 1차 문서(언어·화자 파라미터·데이터 정책).
- pyannote 공개 벤치 페이지 수치(이미지).
- Deepgram MIP opt-out 시 가격 영향 1차 근거.

## 6. 출처 URL (모두 2026-10-14 열람)

pyannoteAI
- https://www.pyannote.ai/changelog
- https://www.pyannote.ai/changelog/precision-3
- https://www.pyannote.ai/blog/precision-3
- https://www.pyannote.ai/precision-3
- https://www.pyannote.ai/pricing
- https://docs.pyannote.ai/models
- https://docs.pyannote.ai/api-reference/diarize
- https://docs.pyannote.ai/api-reference/identify
- https://docs.pyannote.ai/tutorials/identification-with-voiceprints
- https://docs.pyannote.ai/tutorials/speech-to-text-diarization
- https://docs.pyannote.ai/tutorials/diarization-asr-merge
- https://docs.pyannote.ai/data-retention
- https://www.pyannote.ai/benchmark
- https://www.pyannote.ai/blog/top-7-speaker-diarization-apis-and-models-in-2026

Soniox
- https://soniox.com/docs/stt/models
- https://soniox.com/blog/soniox-v5-async
- https://soniox.com/docs/stt/concepts/speaker-diarization
- https://soniox.com/docs/stt/api-reference/transcriptions/create_transcription
- https://soniox.com/speech-to-text/features/diarization
- https://soniox.com/pricing
- https://soniox.com/docs/security-and-privacy

ElevenLabs
- https://elevenlabs.io/blog/introducing-scribe-v2
- https://elevenlabs.io/docs/api-reference/speech-to-text/convert
- https://elevenlabs.io/docs/overview/models
- https://elevenlabs.io/docs/capabilities/speech-to-text
- https://elevenlabs.io/pricing/api
- https://elevenlabs.io/docs/changelog
- https://elevenlabs.io/docs/eleven-api/resources/zero-retention-mode

OpenAI
- https://developers.openai.com/api/docs/guides/speech-to-text
- https://developers.openai.com/api/docs/models/gpt-4o-transcribe-diarize
- https://developers.openai.com/api/docs/models/gpt-transcribe
- https://developers.openai.com/api/docs/pricing
- https://developers.openai.com/api/docs/changelog
- https://developers.openai.com/api/docs/deprecations
- https://community.openai.com/t/introducing-gpt-4o-transcribe-diarize-now-available-in-the-audio-api/1362933 (2차)
- https://ai.azure.com/catalog/models/gpt-4o-transcribe-diarize (출시일 보조)

Google
- https://docs.cloud.google.com/speech-to-text/v2/docs/chirp_3-model
- https://docs.cloud.google.com/speech-to-text/docs/release-notes
- https://cloud.google.com/dotnet/docs/reference/Google.Cloud.Speech.V2/latest/Google.Cloud.Speech.V2.SpeakerDiarizationConfig
- https://docs.cloud.google.com/ruby/docs/reference/google-cloud-speech-v2/latest/Google-Cloud-Speech-V2-SpeakerDiarizationConfig
- https://ai.google.dev/gemini-api/docs/audio
- https://ai.google.dev/gemini-api/docs/generate-content/transcribe.md.txt
- https://ai.google.dev/gemini-api/docs/models/gemini-3.5-transcribe
- https://ai.google.dev/gemini-api/docs/pricing

AssemblyAI
- https://assemblyai.com/blog/universal-3-5-pro-async
- https://www.assemblyai.com/llms/models.md
- https://www.assemblyai.com/md/pricing
- https://www.assemblyai.com/docs/pre-recorded-audio/label-speakers.md
- https://assemblyai.com/docs/data-retention-and-model-training
- https://www.assemblyai.com/docs/faq/are-files-submitted-to-the-api-used-for-model-training

Deepgram
- https://developers.deepgram.com/docs/models-languages-overview
- https://developers.deepgram.com/docs/diarization
- https://developers.deepgram.com/changelog/2026/5/13
- https://developers.deepgram.com/changelog/2026/8/4
- https://deepgram.com/learn/introducing-batch-diarization-v2
- https://deepgram.com/pricing
- https://developers.deepgram.com/docs/the-deepgram-model-improvement-partnership-program

Speechmatics
- https://docs.speechmatics.com/speech-to-text/batch/batch-diarization
- https://docs.speechmatics.com/speech-to-text/batch/speaker-identification
- https://docs.speechmatics.com/speech-to-text/languages
- https://speechmatics.featurebase.app/changelog
- https://www.speechmatics.com/pricing
- https://speechmatics.com/company/articles-and-news/introducing-melia-multilingual-speech-to-text-model

Microsoft
- https://learn.microsoft.com/en-us/azure/ai-services/speech-service/mai-transcribe
- https://microsoft.ai/news/mai-transcribe-2
- https://learn.microsoft.com/en-us/azure/ai-services/speech-service/fast-transcription-create
- https://learn.microsoft.com/en-us/rest/api/speechtotext/transcriptions/transcribe
- https://learn.microsoft.com/en-us/azure/ai-services/speech-service/language-support?tabs=stt

AWS
- https://docs.aws.amazon.com/transcribe/latest/dg/diarization.html
- https://docs.aws.amazon.com/transcribe/latest/dg/supported-languages.html
- https://aws.amazon.com/transcribe/pricing/
- https://aws.amazon.com/transcribe/faqs/

Mistral
- https://mistral.ai/news/voxtral-transcribe-2
- https://docs.mistral.ai/capabilities/audio/speech_to_text
- https://docs.mistral.ai/studio/audio/speech_to_text/offline_transcription

xAI
- https://x.ai/news/grok-stt-and-tts-apis
- https://www.unite.ai/it/xai-releases-grok-voice-transcribe-2-0-speech-to-text-model/ (2차)

Gladia · 기타
- https://www.gladia.io/pricing
- https://docs.gladia.io/chapters/audio-intelligence/speaker-diarization
- https://docs.smallest.ai/models/changelog/pulse-stt/2026/6/16

독립·학술 벤치마크
- https://arxiv.org/abs/2509.26177 , https://arxiv.org/html/2509.26177v1 (ETH Zurich)
- https://arxiv.org/abs/2607.23808 , https://arxiv.org/html/2607.23808v1 (Indic DiarBench, Sarvam AI·AI4Bharat)
- https://arxiv.org/abs/2507.16136 (SDBench, 2025-07, 수치 미추출)

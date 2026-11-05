# 리서치 B: 한국어 특화 STT·화자분리 공급자 (2025–2026)

- 조사일: 2026-10-14 (모든 "확인일"은 이 날짜에 1차 출처를 직접 열어 확인한 것)
- 범위: 읽기 전용 웹 조사. 가입·로그인·업로드·약관 동의 없음. 실측 없음.
- 환율: NAVER Cloud 사이트가 쓰는 환율 API 값 1 KRW = 0.0007362 USD (2026-10-14 조회, 약 1,358원/USD). USD 환산은 참고용.
- 우선순위 반영(조정자 지시): 화자 수 붕괴 > E1 오귀속 > E2 병합. 화자 수 파라미터(정확/범위), 화자 등록·식별, 한국어 화자 수 추정 정확도 근거에 무게를 둠.

## 0. 결론 요약

1. **한국어 API 중 화자 수를 범위(min/max)로 넘길 수 있는 곳은 NAVER CLOVA Speech뿐이다.** 단 `speakerCountMin`/`speakerCountMax`는 응답 스키마와 공식 Java 예제에만 있고 요청 파라미터 표에는 빠져 있다. 실제로 반영되는지는 실측해야 한다. 2026-09-17부터 장문 인식 화자 상한이 10명에서 30명으로 올랐다.
2. **RTZR(리턴제로)은 정확한 화자 수 하나(`diarization.spk_count`, 0=자동)를 받는다.** 목표가(USD 0.78/h) 안에 드는 유일한 한국어 후보다(1,000원/h, VAT 별도, 약 USD 0.74/h). 다만 `use_disfluency_filter` 기본값이 true라서 "어/음" 같은 군더더기가 지워진다. DAMA에서는 반드시 false로 보내야 한다.
3. **한국 공급자 중 API로 화자 등록(voiceprint)·식별을 제공하는 곳은 찾지 못했다.** 클로바노트 Business 이상 플랜에만 "화자 자동 식별"(주소록 지정으로 목소리 학습)이 있고 API는 없다. API 수준 등록 기능은 현행 pyannote.ai `/v1/voiceprint`·`/v1/identify`가 유일한 근거다(repo `ssot/api/pyannote-verified.md` 기준, 본 트랙에서 재검증 안 함).
4. **한국어 다화자 음성의 화자 수 추정 정확도나 DER을 공급자 간 비교한 독립 공개 자료는 찾지 못했다.** 존재하는 한국어 비교는 RTZR이 측정한 CER(전사 오류율)뿐이고 화자분리는 측정하지 않았다. 결국 자체 녹음으로 직접 재야 한다.
5. **TIRO는 자체 엔진이 아니라 다중 공급자 오케스트레이션이다.** 2026-07-25 서브프로세서 목록에 STT로 Deepgram, AssemblyAI, ElevenLabs, NAVER Cloud(Clova), Google Speech-to-Text가 올라 있다. 클로바노트는 NEST(음성인식)와 WISE(화자인식) 엔진을 쓴다고 네이버가 2021-09-07에 밝혔다.

판정: **즉시 시험 2곳(CLOVA Speech, RTZR)**, 관찰 2곳(Daglo, SKT A.X K2 ALM), 나머지 제외.

## 1. 후보 표

| 공급자/모델 | 최근 업데이트 (날짜·출처) | API | 화자분리 파라미터 | 타임스탬프 단위 | 가격/h (확인일) | 데이터 정책 | 벤치마크 (측정 주체) | 판정 |
|---|---|---|---|---|---|---|---|---|
| **NAVER CLOVA Speech 장문 인식** (NEST 엔진) | 2026-09-17 장문 인식 화자 상한 10→30명 (NCP 사용 가이드 릴리스 노트). 2025-11-20 Streaming 2.0 출시. API 문서 갱신 2026-09-17 | Y. REST. 로컬 업로드 `POST /recognizer/upload`, 외부 URL, Object Storage. sync 최대 2시간, Batch(async) 최대 6시간, 파일 2GB. async는 callback URL 또는 `resultToObs` 필요, 상태 조회 `GET /recognizer/{token}` | `diarization.enable`(요청 표 기본값 true, Java 예제 기본값 false로 문서끼리 불일치). `speakerCountMin`/`speakerCountMax`: 응답 스키마와 공식 Java 예제 `Diarization` 클래스에만 존재, 응답 예시 기본값 -1(자동). 요청 표에는 미기재 → **실측 필요**. 화자 상한 30명. 화자 등록 API 없음 | 세그먼트 단위 화자 라벨(`diarization.label`) + `words: [startMs, endMs, text]`. 단어별 화자 라벨 없음. ms 단위 | 음성 인식(Batch) 5원/15초 + 화자 인식(Batch) 2원/15초 = **7원/15초 = 1,680원/h ≈ USD 1.24/h**. 15초 단위 올림. Free 플랜 월 20분. VAT 포함 여부 미확인 (NCP 가격 API, 2026-10-14) | 한국 리전에서만 제공(사용 가이드). 고객 음성의 학습 사용 여부·보관 기간: **미확인**(공개 문서에 명시 없음). 제품 페이지에는 "네이버의 풍부한 데이터를 바탕으로 … 지속적으로 … 개선" 문구만 있음. TIRO는 NAVER Cloud를 ZDR 계약으로 쓴다고 표기(협상 여지 시사, CLOVA 기본 약관 근거 아님) | CER 평균 7.52%, 회의 7.63%, 주요 영역별 회의 8.38% (RTZR가 측정한 GitHub 표, 경쟁사 측정, 날짜 미표기). 2023-08-25 RTZR 블로그판은 평균 9.52%. **화자분리 측정치 없음** | **즉시 시험**. 화자 수 범위 지정이 가능한 유일한 한국어 API이고 한국 리전. 단 목표가 초과(약 1.6배), min/max 실제 반영 여부와 세그먼트 단위 라벨의 E2 위험 확인 필요 |
| **RTZR STT** (`sommers` 자체 모델, `whisper` 한국어 파인튜닝) | 모델 업데이트 공지 없음. 최근 공지 2026-03-29 점검. 2026-05-27 BPO 기업 유베이스그룹이 리턴제로 인수 발표(디지털투데이). 블로그 2026-09-17 스트리밍 FINALIZE 튜토리얼 | Y. REST `POST /v1/transcribe`(multipart), `GET /v1/transcribe/{id}` 5초 간격 폴링 권장. 파일 2GB, 4시간. 기본 동시성 2 | `use_diarization`(기본 false), `diarization.spk_count`(정수 ≥0, 0=자동 추정). **범위(min/max) 없음, 정확 지정만**. 멀티채널 사용 시 화자분리 비활성(spk=채널). 최대 화자 수 문서 미기재(자사 사이트 비교표에 "~10") | 발화(utterance) 단위 `spk` + `start_at`/`duration`(ms). `use_word_timestamp=true`면 utterance 안에 `words[{start_at, duration, text}]`. 단어별 화자 라벨 없음. 응답에 `spk_type: "NORMAL"` 필드 존재(다른 값 의미 미확인) | 0–1,000h/월 **1,000원/h**, 1,000–10,000h 500원, 그 이상 400·300원. VAT 별도. **≈ USD 0.74/h**(VAT 포함 약 0.81). 가입 시 무료 10시간. 화자분리 추가요금 언급 없음 (개발자 Pricing, 2026-10-14) | Batch 결과 3일 보관 후 삭제(개발자 Getting Started). 고객 음성의 모델 학습 사용 여부: **미확인**. 2025-10-13 개인정보처리방침은 홈페이지 문의 데이터만 다룸. 처리 서버 위치 미확인. 온프렘 플랜 있음 | CER 평균 5.91%, 회의 6.74%, 주요 영역별 회의 5.98% (자사 측정, GitHub). 자사 사이트 "경쟁사 대비 35–46% 낮은 오류율"(비교 대상·지표 불명). **화자분리 측정치 없음** | **즉시 시험**. 정확 화자 수 지정 + 목표가 이내. 주의: `use_disfluency_filter` 기본 true(감탄사·반복 제거), `use_paragraph_splitter` 기본 true, `use_itn` 기본 true. DAMA 원문 보존 원칙상 disfluency는 false 필수. 인수 후 API 지속성 불확실 |
| **ActionPower 다글로(daglo) API** | 개발자 문서 ver1.0 2024-09-02, ver1.1 2024-09-24(FAQ 이력). 그 이후 API 변경 공지 못 찾음 | Y. REST `POST /stt/v1/async/transcripts`, 폴링·콜백. 2GB, 4시간. Stream STT는 요청 고객만 | `sttConfig.speakerDiarization.enable` **하나뿐**. 화자 수 파라미터 문서상 없음. 문서가 "화자 수가 많을수록 정확도가 떨어질 수 있으며", 중첩·저음질·소음 한계 명시 | **단어 단위** `speaker` + `startTime`/`endTime`(seconds+nanos) + `segmentId` | **미확인**(공개 단가 못 찾음). 가입 시 약 10시간 분량 포인트 | 미확인 | 제품 페이지 "화자분리 정확도 90% 이상"(측정 방법 미공개, 마케팅) | **관찰**. 단어 단위 화자 라벨은 DAMA 병합 구조와 잘 맞지만 화자 수 제어가 없어 최우선 실패(화자 수 붕괴)를 막을 수단이 없음. 가격·데이터 정책 확인 후 재검토 |
| **TIRO Voice File API** (더플레이토) | 서브프로세서 목록·개인정보처리방침 2026-07-25 | Y. REST `POST /v1/external/voice-file/jobs` → presigned 업로드 → `GET .../transcript`. 1GB, 5시간(업로드 가이드) | 요청 파라미터: `workspaceGuid`, `transcriptLocaleHints`(최대 1), `translationLocales`. **화자 수 파라미터 없음**. 앱 UI 업로드에만 `[Number of Speakers]` 입력(자동 감지 가능) | 문장 단위 `segments[{startTimeMillis, endTimeMillis, text, speakerLabel}]`, `speakerLabel`은 job 내부에서만 의미, 미배정 시 null | 종량 API 단가 미공개(플랜·크레딧 기반) | "Your data will never train AI models", STT·LLM 공급자 ZDR 계약, 저장은 AWS Korea, STT 공급자 위치는 대부분 Global(NAVER만 Korea), 오디오는 전사 후 폐기 | 자사 블로그 정성 비교(2024-10-10 작성, 2026-08 개정), 수치 없음 | **제외**. 원천 엔진을 감싼 계층이고 API에서 화자 수를 못 넘김. 원천 엔진(Clova, ElevenLabs, AssemblyAI, Deepgram)을 직접 시험하는 편이 낫다 |
| **클로바노트** (개인/NAVER WORKS) | NAVER WORKS 클로바노트 v2.7.0 2025-09-25, v2.8.0 2025-11-27 (릴리스 노트). 화자 엔진 변경 공지 없음 | **N** (공개 API 없음) | UI에서 녹음 종료·업로드 후 '음성 종류'와 '참석자 수' 선택. Business·Business Plus·Enterprise 플랜은 "화자 자동 식별": 음성 블록에 주소록 참석자를 지정하면 해당 구간 음성이 저장돼 학습되고 다음 회의부터 자동 식별 | 해당 없음 | 해당 없음 | 화자 자동 식별은 지정 구간 음성을 저장해 학습에 사용한다고 명시. 개인판 "데이터 활용 동의 시 월 300분 추가"는 2차 출처만 확인(미확인) | 공개 수치 없음 | **제외**(API 없음). 사람 비교 기준으로만 사용 |
| SKT A.X K2 ALM (오디오 언어모델) | 2026-07-29 A.X K2 공개, Hugging Face 링크에 A.X K2 ALM 포함 (SKT 뉴스룸) | 미확인. 기사에는 "상담, 회의, 현장 음성" 인식·분석 가능, 고객센터 적용 "검토" 단계 | 화자분리 언급 없음 | 미확인 | 미확인 | 미확인 | 음성 지표 없음 | **관찰**. 화자분리·타임스탬프 근거가 생기면 재검토 |
| KT 믿:음 | 믿:음 2.0 LLM 오픈소스(2025-07). STT·화자분리 근거는 2022-07 KT AI API 연동 규격서(지니노트 서버 기준)뿐 | 현행 공개 API 근거 없음 | 2022 규격서 처리 상태에 "화자 분리" 단계 표기, 현행 여부 미확인 | 미확인 | 미확인 | 미확인 | 없음 | **제외**(2025–2026 공개 API 근거 없음) |
| LG EXAONE / K-EXAONE 2.0 | K-EXAONE 2.0 2026-07-31 공개(750B, Apache 2.0 보도). EXAONE 4.5는 VLM | STT 아님 | 없음 | 없음 | 없음 | 없음 | 없음 | **제외**(목적 불일치) |
| Upstage, Kakao, Samsung | 2025–2026 공개 STT+화자분리 API 근거 못 찾음. Kakao '커스텀 STT'는 2022-01 보도 | 미확인 | 미확인 | 미확인 | 미확인 | 미확인 | 없음 | **제외**(근거 없음) |
| 셀바스AI(셀비노트), 소리자바, 솔트룩스, 미디어젠 | 셀비노트는 2022 기사 중심(실시간·비실시간 화자 구분, 장비형·노트북형). 나머지는 공개 개발자 문서 못 찾음 | 셀프서브 공개 API 문서 못 찾음(B2B·온프렘 영업형으로 추정, 미확인) | 미확인 | 미확인 | 미확인 | 미확인 | 없음 | **제외**(공개 API 근거 없음) |
| NAVER HyperCLOVA X SEED 8B Omni (오픈 가중치) | 2025-12 말 공개 보도. 모델 카드에 공개일 없음, 지식 컷오프 2025-05 | 로컬 모델 | 음성 인식·번역·TTS 지원, **화자분리·타임스탬프 언급 없음** | 미기재 | 별도 라이선스(hyperclovax) | 로컬 실행 | KsponSpeech 평가셋 언급, 수치는 텍스트에 없음 | **제외**(화자 귀속 목적 불일치) |
| batispeak-diarize (HF, 소규모 개발사) | 컬렉션 "Updated Jun 22"(연도 미표기) | 로컬 모델(pyannote) | pyannote `segmentation-3.0`의 분할 단계만 한국어로 파인튜닝. 임베딩(wespeaker resnet34)·군집은 원본 | pyannote 출력 | BatiAI Community License v2.0(매출 10억 원 이상 등 상업 대규모 사용은 별도 계약) | 로컬 | 한국어 8kHz 전화 3건, `num_speakers=2`, collar 0.5, **기준 RTTM이 Clova 결과**: DER 25.9% → 13.2% (작성자 측정) | **관찰(방법론만)**. 8kHz 2인 전화라 16kHz 다화자 회의와 도메인이 다르고, 정답이 Clova 출력이라 Clova 정확도 근거로도 못 씀 |

## 2. 화자 수 제어·화자 등록 비교 (최우선 실패 대응)

| 공급자 | 정확 화자 수 | 범위 (min/max) | 문서상 상한 | 화자 등록·식별 | 비고 |
|---|---|---|---|---|---|
| CLOVA Speech | min=max로 정확 지정 가능할 것으로 보이나 **미검증** | `speakerCountMin`/`speakerCountMax` (요청 표 미기재, 예제·응답 스키마에만) | 30명 (2026-09-17~) | API 없음 | 응답 `params.diarization`이 요청값을 되돌려주므로 반영 여부를 응답으로 확인 가능 |
| RTZR | `diarization.spk_count` | 없음 | 미기재 (사이트 표 "~10") | 문서 없음 | 회의 앱 '콜라보'의 목소리 등록 여부도 미확인 |
| Daglo | 없음 | 없음 | 미기재 | 없음 | 단어 단위 화자 라벨만 장점 |
| TIRO API | 없음 (UI 업로드만 `[Number of Speakers]`) | 없음 | 미기재 | 없음 ("Conversation Participants"는 이름 저장 기능, 음성 등록 여부 미확인) | |
| 클로바노트 UI | '참석자 수' 선택 | 미확인 | 미확인 | Business 이상 "화자 자동 식별"(주소록 지정 구간 음성 학습) | API 아님 |
| (참조) pyannote.ai precision-2 | `numSpeakers` | `minSpeakers`/`maxSpeakers` (배타) | - | `/v1/voiceprint`, `/v1/identify` | repo `ssot/api/pyannote-verified.md` 기록 기준, 본 트랙 재검증 안 함 |

한국어 화자 수 추정 정확도 근거:

- **독립 측정: 없음.** 한국어 회의 음성에서 공급자별 화자 수 오차·DER·JER을 비교한 공개 자료를 찾지 못했다(한국어·영어 검색 모두).
- 공급자 주장: Daglo "화자분리 정확도 90% 이상"(정의·데이터 미공개). RTZR 사이트 표의 "Speakers ~10 / NAVER ~10 / Google ~6"은 지원 상한이지 정확도가 아니다.
- 사용자 후기(2차, 비검증): 클로바노트에서 목소리가 비슷하거나 같은 성별이면 한 화자로 묶인다는 커뮤니티 글. 표본 1건 수준.
- 공급자 문서 예시 관찰(성능 근거 아님): CLOVA Speech 응답 예시의 한 세그먼트가 "입장료가 얼마예요? 5천 원이에요. 감사합니다."를 화자 1 하나로 묶고 있다. 질문과 답이 한 세그먼트에 들어간 E2 형태로 읽힌다. 세그먼트 단위 라벨 구조에서는 화자 수가 맞아도 E2가 남을 수 있다는 실측 가설로만 쓴다.

## 3. TIRO와 클로바노트는 무엇을 쓰나

**TIRO (tiro.ooo, 더플레이토)**
- Trust Center 서브프로세서 목록(2026-07-25 기준)의 Speech-to-text 항목: Deepgram, AssemblyAI, ElevenLabs, NAVER Cloud (Clova), Google Speech-to-Text. 모두 ZDR 표기. 위치는 NAVER만 Korea, 나머지 Global. LLM은 Azure OpenAI, Anthropic, Google Vertex AI, AWS Bedrock.
- 어떤 녹음에 어떤 엔진을 쓰는지(언어별·요금제별 라우팅)는 **미공개**. 자체 엔진이라는 1차 근거는 없다.
- 화자분리: Pro 플랜 이상. 실시간 녹음 중에는 화자를 나누지 않고 종료 후 전체 음성을 다시 분석해 라벨을 붙인다(도움말). 파일 업로드 시 `[Number of Speakers]`를 넣으면 정확도가 오른다고 안내한다.
- API: 있다(REST, MCP, Webhook, CLI). Voice File Job API는 문장 단위 세그먼트와 `speakerLabel`을 주지만 화자 수 입력이 없고 단어 단위 타임스탬프도 없다. DAMA의 엔진 대체재로는 부적합하다.
- 시사점: TIRO의 품질 우위가 있다면 단일 엔진이 아니라 다중 엔진 선택·후처리·전체 재분석 구조에서 나올 가능성이 크다(추정, 미검증).

**클로바노트 (NAVER)**
- 네이버 보도자료(2021-09-07): 음성인식 엔진 NEST(Neural End-to-end Speech Transcriber)를 클로바노트에 우선 탑재, 참석자별 분리는 화자인식 엔진 WISE(Who Is Speaking)가 담당하며 Interspeech 2021에 관련 연구 발표.
- NCP CLOVA Speech 개요는 CLOVA Speech가 NEST 기술을 쓴다고 밝힌다. 따라서 **ASR 계열은 같다.** CLOVA Speech API의 화자분리가 클로바노트의 현행 WISE와 같은 버전인지는 **미확인**.
- 클로바노트는 사용자에게 '참석자 수'와 '음성 종류'를 받는다. API 대응물: 참석자 수 → CLOVA Speech `speakerCountMin/Max`(미검증). 음성 종류에 대응하는 공개 파라미터는 없다(도메인 부스팅·`domain: general`만 보임).
- 화자 등록: NAVER WORKS 클로바노트 Business 이상에만 있고 API로는 열려 있지 않다.

## 4. 공급자별 보충

**CLOVA Speech**
- 요청 옵션 중 DAMA에 영향 큰 것: `noiseFiltering` 기본 true(짧은 감탄사 손실 여부 미확인, false 비교 필요), `wordAlignment` 기본 true, `fullText` 기본 true. 키워드 부스팅은 1음절("네", "응") 미지원.
- 응답 `version` 예시는 `ncp_v2_v2.3.0-...-20231205_...`. 현행 엔진 버전은 미확인.
- async는 callback URL이나 Object Storage(`resultToObs`)가 없으면 오류를 반환한다고 문서에 적혀 있다. 서버 없는 macOS 앱에서는 sync(최대 2시간) 또는 Object Storage 경유가 필요하다. 상태 조회 API(`GET /recognizer/{token}`)만으로 결과를 받는 경로가 되는지 실측 필요.
- 사용 신청은 NCP 콘솔에서 도메인을 만들고 도메인별 Invoke URL과 Secret Key를 받는 구조.

**RTZR**
- 엔드포인트 호스트 `openapi.vito.ai`. 인증은 client_id/secret으로 토큰 발급.
- `use_refinement`(오디오 대조 텍스트 교정)는 Enterprise 라이선스 전용이며 발화 타이밍·화자는 보존한다고 명시.
- 처리 지연: 긴 파일·혼잡 시 시작까지 30분 이상 걸릴 수 있다고 문서에 명시.
- 2026-05-27 인수 발표 기사에 API 지속 여부 언급 없음.

**Daglo**
- 문서 예시에서 단어 `startTime`/`endTime`이 인접 단어와 겹친다(예: "액션 " 0.82–1.42초, "파워입니다. " 1.38–2.02초). 단어 시간 겹침 처리 로직이 필요할 수 있다(문서 예시 관찰).

## 5. 반론과 실패 경로

1. **min/max가 무시될 수 있다.** CLOVA의 `speakerCountMin/Max`는 요청 표에 없다. 받아들이지 않거나, 받아도 엔진이 범위를 강제하지 않으면 화자 수 붕괴를 못 막는다. 응답 `params.diarization`에 요청값이 되돌아오는지와 결과 화자 수가 범위를 지키는지 둘 다 봐야 한다.
2. **정확 화자 수 강제는 양날이다.** RTZR `spk_count`에 사용자가 넣은 수가 틀리면(말 안 한 참석자, 중간 입장자) 엔진이 억지로 한 사람을 둘로 쪼개거나 두 사람을 합칠 수 있다. 범위 지정이 없는 RTZR에서는 자동(0)과 정확 지정을 모두 돌려 비교해야 한다.
3. **화자 수가 맞아도 E2는 남는다.** CLOVA(세그먼트 단위)와 RTZR(발화 단위)은 화자 라벨 단위가 단어보다 크다. 짧은 끼어들기("네", "어")는 앞뒤 발화에 흡수될 구조적 위험이 있다. 단어 단위 라벨은 Daglo만 문서로 확인됐다.
4. **원문 보존과 기본값 충돌.** RTZR는 군더더기 제거·문단 분할·ITN이 기본 ON이다. 기본값으로 비교하면 RTZR가 "깨끗해 보이는" 대신 DAMA가 지켜야 할 짧은 발화를 지운다.
5. **가격.** CLOVA는 화자 인식 포함 약 USD 1.24/h로 목표(0.78)를 넘는다. 운영 기본값 후보가 되려면 정확도 이득이 커야 한다.
6. **데이터 정책 공백.** CLOVA Speech와 RTZR 모두 API 입력 음성을 학습에 쓰지 않는다는 문구를 공개 문서에서 찾지 못했다. 운영 전 서면 확인(또는 DPA)이 필요하다. 한국 리전은 CLOVA만 문서로 확인됐다.
7. **벤더 지속성.** RTZR는 2026-05 인수됐고, Daglo API 문서는 2024-09 이후 갱신 흔적이 없다.
8. **벤치마크 편향.** 한국어 공개 비교는 RTZR가 직접 측정한 CER뿐이다. Soniox는 그 표에 없고, 화자분리는 아무도 공개 측정하지 않았다.

## 6. 시험 설계 제안 (실행 전 사용자 승인 필요: 유료 API 호출·음성 전송)

- 표본: 이미 정답을 만들 수 있는 자체 녹음 3–5건(2·3·4·6인, 20분 이상, 짧은 맞장구 포함). 외부 전송 동의 필요.
- 조건: CLOVA {자동, min=max=정답, min/max=정답±1}, RTZR {spk_count=0, spk_count=정답, disfluency=false 고정}, 기준선 Soniox+P2.
- 지표 우선순위: ① 화자 수 오차(추정 수 − 정답 수, 쪼개짐/합쳐짐 구분) ② 화자 오귀속 시간 비율(E1, DER의 confusion 성분, collar 0, 겹침 포함) ③ E2 병합 수(정답상 화자 전환이 있는데 한 세그먼트·발화로 묶인 횟수) ④ 1초 이하 짧은 발화 재현율.
- 비용 감: CLOVA 1,680원/h, RTZR 1,000원/h. 무료분 CLOVA Free 월 20분, RTZR 가입 10시간, Daglo 약 10시간.
- DAMA 계약과의 정합: 공급자별 결과는 별도 Run으로 두고 Run 간 화자 자동 매핑은 하지 않는다(INV-09).

## 7. 출처 (모두 2026-10-14 확인)

NAVER Cloud CLOVA Speech
- API 개요(갱신 2026-09-17): https://api.ncloud-docs.com/docs/ai-application-service-clovaspeech
- 로컬 파일 인식(요청·응답 스키마, speakerCountMin/Max 응답 필드, 응답 예시): https://api.ncloud-docs.com/docs/ai-application-service-clovaspeech-longsentence-local
- Object Storage 파일 인식: https://api.ncloud-docs.com/docs/ai-application-service-clovaspeech-longsentence
- 작업 상태 확인: https://api.ncloud-docs.com/docs/ai-application-service-clovaspeech-longsentence-getjobstatus
- 장문 인식 예제(Java `Diarization` 클래스): https://api.ncloud-docs.com/docs/ai-application-service-clovaspeech-example01
- 장문 인식 API 릴리스 노트: https://api.ncloud-docs.com/docs/ai-clovaspeech-longsentence-releasenote
- 사용 가이드 릴리스 노트(2026-09-17 화자 상한 30명): https://guide.ncloud-docs.com/docs/clovaspeech-releasenote
- 사용 준비(길이·용량 한도): https://guide.ncloud-docs.com/docs/clovaspeech-spec
- 개요(한국 리전): https://guide.ncloud-docs.com/docs/clovaspeech-overview
- 장문 인식 빌더(최대 30명): https://guide.ncloud-docs.com/docs/clovaspeech-builder-long
- 일반 문제(스트리밍 화자분리 미지원): https://guide.ncloud-docs.com/docs/clovaspeech-troubleshoot-common
- 도메인: https://guide.ncloud-docs.com/docs/clovaspeech-domain
- 제품·요금 페이지(요금 예시, Free 월 20분): https://www.ncloud.com/product/aiService/clovaSpeech
- 단가 원자료(사이트가 쓰는 공개 엔드포인트, 상품코드 CLSPH.LONG.BASIC.V001): https://www.ncloud.com/api-cache/product-bill-list
- 환율 원자료: https://www.ncloud.com/api/fees/exchange-rate/KRW/USD

RTZR (리턴제로)
- Getting Started(결과 3일 보관): https://developers.rtzr.ai/docs/en/
- Batch STT 파라미터: https://developers.rtzr.ai/docs/en/stt-file/
- 화자분리: https://developers.rtzr.ai/docs/en/stt-file/diarization/
- 단어 타임스탬프: https://developers.rtzr.ai/docs/en/stt-file/word_timestamp/
- 군더더기 필터: https://developers.rtzr.ai/docs/en/stt-file/disfluency/
- 멀티채널: https://developers.rtzr.ai/docs/en/stt-file/multi-channel/
- 교정(Enterprise): https://developers.rtzr.ai/docs/en/stt-file/refinement/
- 모델: https://developers.rtzr.ai/docs/en/stt-file/model/
- 요금: https://developers.rtzr.ai/docs/en/pricing/
- 공지: https://developers.rtzr.ai/docs/en/notice/
- 제품 페이지(자사 벤치마크 표): https://www.rtzr.ai/en/stt
- 플랜: https://www.rtzr.ai/en/pricing
- 개인정보처리방침(2025-10-13판, 홈페이지 문의 대상): https://rtzr.notion.site/2025-10-13-28b3077f85aa80f0a7badcc1f6cd4b8e
- 자사 CER 벤치마크: https://github.com/rtzr/Awesome-Korean-Speech-Recognition , https://blog.rtzr.ai/korean-speechai-benchmark/ (2023-08-25)
- 블로그 목록: https://blog.rtzr.ai/
- 인수 보도(2026-05-27): https://www.digitaltoday.co.kr/news/articleView.html?idxno=669302

ActionPower 다글로
- 화자분리 등 부가기능: https://developers.daglo.ai/guide/STT-Subfeatures.html
- 긴 음성 변환: https://developers.daglo.ai/guide/STT-Async.html
- FAQ(문서 이력, 한도): https://developers.daglo.ai/guide/FAQ.html

TIRO
- 서브프로세서(2026-07-25): https://tiro.ooo/trust/subprocessors
- 메인(데이터 정책 문구): https://tiro.ooo
- 화자분리 도움말: https://docs.tiro.ooo/en/guide/recording/diarization.md
- 개발자 문서 인덱스: https://docs.tiro.ooo/_llms/en/developer-docs.txt
- Voice File Job 생성: https://docs.tiro.ooo/api-reference/voice-file/create-voice-file-job.md
- Transcript 조회: https://docs.tiro.ooo/api-reference/voice-file/get-transcript.md
- 자사 비교 블로그: https://tiro.ooo/ko/blog/-%EC%9D%8C%EC%84%B1-%EC%9D%B8%EC%8B%9D-ai-%EC%A0%95%ED%99%95%EB%8F%84-%EB%B9%84%EA%B5%90-%ED%81%B4%EB%A1%9C%EB%B0%94%EB%85%B8%ED%8A%B8-vs-%EB%8B%A4%EA%B8%80%EB%A1%9C-vs-%ED%8B%B0%EB%A1%9C-31174

클로바노트 / NAVER
- 화자 자동 식별(NAVER WORKS): https://help.worksmobile.com/ko/use-guides/clovanote/view/speaker-identification/
- 새 노트 생성(참석자 수 선택): https://help.worksmobile.com/ko/use-guides/clovanote/create/note/
- 릴리스 노트: https://naver.worksmobile.com/release-notes/clovanote_20250925/ , https://naver.worksmobile.com/release-notes/clovanote_20251127/
- NEST·WISE 보도자료(2021-09-07): https://navercorp.com/media/pressReleasesDetail?seq=30550
- HyperCLOVA X SEED 8B Omni: https://huggingface.co/naver-hyperclovax/HyperCLOVAX-SEED-Omni-8B

기타
- SKT A.X K2 공개(2026-07-29): https://news.sktelecom.com/228501
- KT AI API 연동 규격서(2022-07): https://cloud.kt.com/download/KT_AI_API_standard_v1.1.pdf
- K-EXAONE 2.0 보도(2026-07-31): https://www.g-enews.com/article/Industry/2026/07/202607311311089451112616b072_1
- batispeak-diarize: https://huggingface.co/batiai/batispeak-diarize
- 셀비노트 기사(2022): https://news.mtn.co.kr/news-detail/2022032114242751303

미확인으로 남긴 항목: CLOVA·RTZR·Daglo의 API 입력 음성 학습 사용 여부와 보관 기간(RTZR 결과 3일 제외), RTZR·Daglo 처리 서버 위치, Daglo 단가, CLOVA 가격의 VAT 포함 여부, CLOVA min/max 실제 반영 여부, CLOVA API 화자분리와 클로바노트 WISE의 동일성, TIRO의 엔진 라우팅 규칙, 한국어 화자 수 추정 정확도의 독립 근거.

# 리서치 A2: Google AI Edge Foresight 검증 (2026-10-14)

- 범위: 읽기 전용. 설치·다운로드(.dmg)·가입 없음. 공식 페이지는 iframe 본문까지 열어 확인했다.
- 표기: **[1차]** Google 공식 페이지·블로그·문서, **[2차·미검증]** 언론·리뷰·블로그. 2차 출처의 사실 주장은 Google이 확인하지 않은 것으로 취급한다.
- NVIDIA Nemotron-3-Diarization 자체는 이 조사 범위 밖이라 확인하지 않았다.

## 결론

Foresight는 **SDK·API·CLI가 없는 실험용 Mac 앱**이다. 다른 앱의 부품으로 쓸 수 없다. ASR 모델은 공식적으로 이름이 공개되지 않았고 별도 배포도 확인되지 않는다. 한국어 지원, 타임스탬프, 화자분리, 전사 내보내기 모두 공식 근거가 없다. 실사용 리뷰(2차)에 따르면 화자 구분은 마이크/시스템 오디오 두 스트림 기준의 "you / everyone else"뿐이다. 따라서 "Foresight 전사 + Nemotron 화자분리" 결합은 현재 공개 정보로는 성립하지 않는다.

같은 계열에서 macOS Swift 앱이 쓸 수 있는 것은 **Gemma 4 E2B/E4B/12B Unified의 오디오 입력**(Apache 2.0, LiteRT-LM Swift early preview 또는 MLX)이다. 다만 클립당 30초 제한이 있고, 타임스탬프·화자분리 언급이 없으며, 한국어 ASR이 공식 지원 언어로 명시되지 않았다. 단어 타임스탬프 기반 원문 스크립트 용도로는 부적합하다.

## 1. Foresight 정체

| 항목 | 내용 | 출처 |
|---|---|---|
| 정의 | "experimental app that brings a context-aware meeting companion directly to your device". 로컬 AI로 노트·색인·회의 전사와 개인 파일 회상. 시스템 오디오와 마이크를 받아 어느 회의 플랫폼이든 동작, 오프라인 | [1차] Google Developers Blog, 2026-10-06 |
| 기능 | 약식 메모를 회의 전사로 확장, 로컬 폴더·Google Drive·캘린더 연결, 채팅 검색·요약, Live Assistance(통화 중 질문 감지·자동 답변), 실시간 시스템 오디오 전사와 인용 카드 | [1차] developers.google.com/edge/foresight (iframe 본문) |
| 입력 지원 형식 | PDF, Google Docs, MS Office, 일반 텍스트, Markdown, 웹 북마크 (지식베이스 입력용. 출력 형식 아님) | [1차] 동일 |
| 발표일 | 2026-10-06 (EmbeddingGemma 2와 함께) | [1차] 블로그 날짜 |
| 플랫폼 | macOS 전용, "Optimized for Apple Silicon". 최소 macOS 버전·RAM 미기재 | [1차] 제품 페이지 FAQ |
| Intel Mac | 미지원 | [2차·미검증] heise 2026-10-07 |
| 배포 | 직접 다운로드 `https://dl.google.com/foresight-mac/foresight_mac.dmg`, 버전 번호 미표기, Mac App Store 아님 | [1차] 제품 페이지 |
| 설치 크기 | 앱 153MB 다운로드/376MB 설치, 첫 실행 시 음성인식·검색용 소형 모델 약 800MB + Gemma 4 E4B 3.41GB(또는 12B 선택), 합계 약 4.2GB | [2차·미검증] talat 블로그 2026-10-09/11 (경쟁 제품 작성) |
| 모델 | EmbeddingGemma 2(740M, 검색) + Gemma 4(생성). ASR 모델명 없음 | [1차] 블로그·제품 페이지 |
| 약관·라이선스 | Google 일반 Terms of Service(policies.google.com/terms)와 Privacy Policy 링크만. 앱 전용 라이선스·EULA 미기재. 앱은 비공개 소스 | [1차] 제품 페이지 / 비공개 소스는 [2차] |
| 개인정보 | 추론 100% 로컬, 오디오·전사·파일이 컴퓨터를 떠나지 않음 | [1차] 제품 페이지 FAQ |
| 관찰된 부수 동작 | 분석 라이브러리 이벤트 송신(2분에 약 74건), 4시간마다 앱을 다시 여는 launch agent `com.google.ai_edge.foresight.refresh_calendar_events` | [2차·미검증] talat 정적 분석 |
| SDK·API·CLI | 공식 페이지·블로그 어디에도 없음. 리뷰에서도 공개 API 없음 | [1차] 부재 확인 + [2차] |
| 지원 연락처 | ai-edge-support@google.com | [1차] |

## 2. ASR 모델

| 질문 | 답 | 근거 |
|---|---|---|
| 이름 | **미공개.** Google 블로그·제품 페이지 모두 ASR 모델명을 밝히지 않음 | [1차] 부재 |
| Gemma 기반 여부 | 불명. 2차 보도는 "Gemma 4가 전사" 설과 "별도 소형 음성모델이 전사" 설로 갈림. talat 실측은 설치 시 별도 음성인식 모델 다운로드를 관찰. 형제 앱 Eloquent는 "Gemma-based ASR models"를 받는다고 보도됨 | [2차·미검증] |
| 별도 공개 여부 | Hugging Face `google/*`, LiteRT 커뮤니티, MediaPipe에서 Foresight용 ASR 모델 공개를 찾지 못함. 블로그가 링크한 공개 모델은 `litert-community/embeddinggemma-2-740m-litert-lm`(임베딩) 뿐 | [1차] 블로그 링크 확인 |
| 언어 | 공식 미기재. 실사용: 영어 양호, 프랑스어는 악센트 문자 누락, 아랍어 실패, 언어 설정 없음. 일본어는 영어 기본 전사라는 X 게시물 보고. **한국어 근거 없음** | [2차·미검증] talat, note.com |
| 타임스탬프 | 공식 미기재, 리뷰도 언급 없음 | 미확인 |
| 화자분리 | 공식 미기재. 리뷰: 마이크·시스템 오디오 2스트림으로 "you / everyone else"만 구분, 음성 기반 화자 식별 없음 | [2차·미검증] talat |

## 3. 전사 내보내기

- 공식 페이지·블로그에 내보내기 기능 언급 없음. 전사를 앱 안에서 "recall"하는 것만 서술.
- 리뷰·보도에서도 내보내기 형식(JSON/TXT/SRT), 타임스탬프, 화자 라벨을 확인한 사례를 찾지 못함.
- 결론: 다른 앱이 소비할 수 있는 전사 출력은 **미확인**. 설치 후 메뉴·로컬 저장소를 직접 봐야 확정 가능하나 이번 범위(다운로드 금지)에서는 하지 않았다.

## 4. 2026년 Google 온디바이스 음성 모델 (macOS Swift 사용 가능성)

| 모델·런타임 | 날짜 | 한국어 | 타임스탬프 | 화자분리 | macOS Swift 경로 | 판정 |
|---|---|---|---|---|---|---|
| Gemma 4 E2B / E4B / 12B Unified 오디오 입력 | Gemma 4 2026-04-02 출시(2차, 다수 일치). 모델카드 2026-07-30 갱신, 오디오 가이드 2026-10-10 갱신 | "multilingual speech recognition"이라고만 기재, 언어 목록 없음. 한국어는 문서 예시에서 번역 대상으로만 등장. 공식 한국어 ASR 근거 없음 | 언급 없음 | 언급 없음(12B 화자분리 주장은 2차, 미검증) | LiteRT-LM Swift API "Early Preview"(iOS·macOS, Metal), 오디오 입력을 Swift에서 받는지는 미기재. 오디오 가이드가 MLX·llama.cpp도 나열 | **부적합**: 클립당 30초 제한, 타임스탬프 없음, 한국어 미명시. 단어 타임스탬프 정렬이 필요한 DAMA 계약과 맞지 않음 |
| Gemma 3n 오디오 | 2025 (Gemma 오디오 최초) | 미확인 | 없음 | 없음 | LiteRT-LM 지원 목록에 있음 | 부적합 (위와 같은 이유) |
| EmbeddingGemma 2 (오디오 인코더 포함) | 2026-10-06 | 100+ 언어 텍스트 임베딩(2차 heise) | 해당 없음 | 해당 없음 | LiteRT-LM `.litertlm`, MediaPipe | 전사 모델 아님. 검색·색인 용도 |
| LiteRT-LM 런타임 | GitHub 최신 v0.18.0(날짜 미표기), Apache-2.0 | 해당 없음 | 해당 없음 | 해당 없음 | Swift early preview, CLI는 macOS 지원 | 런타임만 제공 |
| AI Edge Eloquent (iOS 2026-04-06, Mac 2026-06경) | 형제 앱. Gemma 기반 ASR 사용 보도 | iOS v1.4.0(2026-08-13)에 다국어 추가, 한국어 포함 여부는 2차 출처 간 불일치. Mac판 다국어 적용 미확인 | 미확인 | 없음(받아쓰기 앱) | 앱 전용, SDK 없음 | 부품으로 사용 불가 |

## 5. 반론과 실패 경로

- "Gemma 기반이니 한국어도 될 것"은 추론이다. 실사용 보고에서 프랑스어 악센트 누락·아랍어 실패가 나온 만큼 비영어 품질을 가정할 수 없다.
- 앱 내부 ASR 모델 파일을 추출해 쓰는 방식은 약관상 허용 근거가 없고, 버전 고정·업데이트가 Google 재량이며, 실험 앱이라 중단될 수 있다.
- "You / everyone else" 2스트림 구분은 원격 회의에서 내 목소리와 상대를 나누는 데만 쓸모 있고, 대면 회의 2~6인 화자분리(E1·E2)는 전혀 해결하지 않는다.
- 분석 이벤트 송신 관찰(2차)은 "완전 오프라인·데이터 미전송" 공식 문구와 긴장 관계가 있다. 기밀 회의용으로 쓰려면 네트워크 동작을 직접 검증해야 한다.

## 6. 출처 (2026-10-14 열람)

1차
- https://developers.googleblog.com/google-ai-edge-with-embeddinggemma-2/ (2026-10-06)
- https://developers.google.com/edge/foresight (iframe 본문: https://developers-dot-devsite-v2-prod.appspot.com/edge/foresight/index_f6628b655479a346d90cc08d72035181ec6738e36ff1619c7b5c637c8f295547.frame)
- https://ai.google.dev/gemma/docs/capabilities/audio (2026-10-10 갱신)
- https://ai.google.dev/gemma/docs/core/model_card_4 (2026-07-30 갱신)
- https://developers.google.com/edge/litert-lm/overview (2026-10-06 갱신)
- https://github.com/google-ai-edge/LiteRT-LM

2차·미검증
- https://www.heise.de/en/news/Google-s-macOS-app-Local-AI-to-capture-notes-and-work-with-files-11479591.html (2026-10-07)
- https://talat.app/blog/google-ai-edge-foresight (2026-10-09, 10-11 갱신, 경쟁 제품 블로그)
- https://note.com/yyylab/n/n7cc77c01ca08 (설치 파일 크기 2026-10-09 측정)
- https://gigazine.net/gsc_news/en/20261009-google-ai-edge-foresight/
- https://www.eweek.com/news/google-ai-edge-foresight-mac/
- https://androidauthority.com/google-ai-edge-foresight-embedding-gemma-2-3719906
- https://www.progressiverobot.com/2026/10/08/ai-edge-foresight-google-offline-ai-note-taking-app/
- https://www.speechtechmag.com/Articles/News/Speech-Technology-News/Google-Launches-AI-Edge-Eloquent-174257.aspx (Eloquent, 2026-04)
- https://jetstream.blog/2026/08/22/ios-google-ai-edge-eloquent-v1-4-1-release/ (Eloquent v1.4.x)
- https://www.apfeltalk.de/magazin/news/google-bringt-ai-edge-galerie-und-eloquent-mit-gemma-4-12b-auf-den-mac/ (Eloquent Mac, Gemma 4 12B)
- https://en.wikipedia.org/wiki/Gemma_(language_model) (Gemma 4 출시일 2026-04-02)

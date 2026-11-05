# 리서치 C: 오픈소스·온디바이스 화자분리와 화자귀속 ASR (2025-06 ~ 2026-10)

- 조사일: 2026-10-14. 웹 1차 출처(모델 카드, GitHub, arXiv, 릴리스 노트) 위주. 모델을 내려받거나 실행하지 않았다.
- 우선순위(코디네이터 2026-10-14 갱신): ① 화자 수 붕괴(3명→2명, 1명→2명) ② E1 오귀속 ③ E2 병합. 아래 판정은 이 순서로 가중했다.
- 표기: "미확인" = 1차 출처에서 확인하지 못함. DER은 측정 주체·참조 라벨·collar가 다르면 서로 비교할 수 없다. 특히 NVIDIA·Argmax의 AMI/AliMeeting/NOTSOFAR1 수치는 forced-alignment 참조 라벨이라 pyannote 모델 카드의 AMI 수치와 직접 비교 불가.

---

## 0. 결론 요약

1. **즉시 시험 1순위: NVIDIA Nemotron-3-Diarization (2026-09-23, OpenMDW-1.1, 상업 이용 가능, 최대 8명).** 같은 참조 라벨로 여러 시스템을 돌린 제3자 표(Argmax OpenBench, 2026-09-22)에서 화자 수 정확도(SCA) 평균 71%로 pyannoteAI precision-3(64%), community-1(50%)보다 높고 평균 DER 0.19로 precision-3(0.20)과 비슷하다. FluidAudio가 CoreML 포트를 2026-09-23 머지했고 M5 Pro에서 offline 프리셋 904x RTFx(AMI, FluidInference 측정). 단 oracle 화자 수 입력 파라미터가 없고, 한국어 학습·평가 근거가 없다.
2. **즉시 시험 2순위: pyannote community-1 (2025-09-29, CC-BY-4.0) + oracle/범위 화자 수.** 자동 화자 수 추정은 약하다(OpenBench SCA 50%, FluidAudio AMI 12/16). 그러나 `num_speakers`/`min/max_speakers`를 받는 유일한 성숙한 로컬 파이프라인이고, 화자별 임베딩(centroid)을 내므로 등록(enrollment) 기반 E1 교정의 토대가 된다. Swift 경로는 Argmax OSS SpeakerKit(MIT, `numberOfSpeakers`)과 speech-swift(Apache-2.0, `speakerBounds`)가 확인됨. FluidAudio의 offline 파이프라인 문서에는 화자 수 파라미터가 없다.
3. **관찰: 엔드투엔드 화자귀속 ASR (MOSS-Transcribe-Diarize, VibeVoice-ASR).** 한국어 수치는 둘 다 MLC-SLM(2인 대화) 기반뿐이고, 타임스탬프가 세그먼트 단위라 DAMA의 단어 단위 병합 계약과 맞지 않으며, 60분(VibeVoice)·90분(MOSS) 상한이라 2시간 회의는 청크 간 화자 연결이 필요하다. VibeVoice는 실사용 1건에서 1명을 2명으로 분할한 사례가 보고됐다.
4. **관찰(라이선스 제약): DiariZen.** 공개 DER은 오픈소스 중 최상위권(AliMeeting far 10.8, AMI-SDM 13.9, collar 0, BUT 측정)이나 가중치가 CC BY-NC 4.0이고 Apple Silicon 포트가 미확인.
5. **제외: Sortformer 4spk v1/v2/v2.1(4명 상한, Nemotron 3로 대체), multitalker Parakeet(영어 전용), SpeakerLM·TagSpeech(가중치 공개 미확인), SoulX-Transcriber(중·영), DiarizationLM(영어 Fisher, 그리고 문맥 기반 화자 교정은 DAMA 경계 4와 충돌).**
6. 한국어 다자(3–6인) 회의에 대한 공개 화자분리 벤치마크는 찾지 못했다. 어떤 후보든 DAMA 자체 한국어 녹음(정답 화자 수·턴 라벨 포함)으로 직접 재야 한다.

---

## 1. 후보 표

### 1-A. 화자분리 전용 모델·파이프라인

| 모델 | 공개일 (출처) | 라이선스 | 핵심 DER (측정 주체, 조건) | 화자 수 추정 / oracle | 최대 화자 | Apple Silicon 런타임 | 한국어·아시아어 근거 | 판정 |
|---|---|---|---|---|---|---|---|---|
| **Nemotron-3-Diarization** (NVIDIA, Sortformer 계열 ~100M) | 2026-09-23 (HF 카드, Baseten 블로그) | OpenMDW-1.1, "ready for commercial or non-commercial use" | NVIDIA, 30.4s 버퍼, collar 0 (CALLHOME 0.25), overlap 포함: DIHARD III 12.73, AliMeeting Near 6.40 / Far 10.47, AMI MHM 9.25 / SDM 11.14, NOTSOFAR1 MHM 6.77 / SC 11.00, CALLHOME-p2 9.10. AMI·AliMeeting·NOTSOFAR1은 forced-alignment 참조. Argmax OpenBench(같은 참조로 6개 시스템): 평균 0.19, AISHELL-4 0.11, AliMeeting 0.18, DIHARD-III 0.13, VoxConverse 0.08. Baseten 자체 측정: AISHELL-4 low 프로필 9.8%(v2.1은 27.2%), AMI에서는 community-1에 짐(수치 비공개) | SCA(NVIDIA): DIHARD III 81.5%, CALLHOME 91.6%, AliMeeting Far 100%, NOTSOFAR1 MHM 93.8% / SC 78.1%, AMI 87.5%. OpenBench 평균 71%(최고). **oracle 화자 수 입력 파라미터 문서 없음** | 8 (출력 [T,8]). 8명 초과 시 동작 문서 없음 | FluidAudio CoreML(v0.17.3+, 프리셋 offline/fast128/low 등, 190MB 또는 W8A8 95MB). M5 Pro AMI MHM: offline DER 9.47·SCA 87.5%·904x, fast128 9.36·100%·546x (FluidInference 측정). speech-swift CoreML/MLX INT8. sherpa-onnx PR #4032 미머지(2026-10-10). Argmax Pro SDK 3(유료) | 학습 데이터에 AISHELL-4·AliMeeting(중국어), DISPLACE(인도어) 포함. **한국어 명시 없음** | **즉시 시험** (화자 수 정확도 최상위, 로컬 속도 압도적, 상업 라이선스) |
| **pyannote community-1** (powerset 분할 + WeSpeaker + VBx) | 2025-09-29 (pyannote.audio 4.0.0 릴리스, HF 갱신일) | 가중치 CC-BY-4.0, 코드 MIT | pyannote 측정, collar 0, overlap 포함: AISHELL-4 11.7, AliMeeting ch1 20.3, AMI IHM 17.0 / SDM 19.9, DIHARD3 20.2, MSDWild 22.8, VoxConverse 11.2. 같은 표의 precision-2: 11.4 / 15.2 / 12.9 / 15.6 / 14.7 / 17.3 / 8.5. OpenBench(Argmax SpeakerKit 실행): 평균 0.28 | 자동 추정 약함: OpenBench SCA 평균 50%(AISHELL-4 60, AliMeeting 65, DIHARD 44), FluidAudio CoreML AMI SDM 12/16 일치, speech-swift VoxConverse 5파일 중 3개 일치. **`num_speakers`, `min_speakers`, `max_speakers` 지원** | 상한 없음(카드에 미기재) | FluidAudio offline(VBx, ANE, M5 Pro AMI SDM 323x, 화자 수 파라미터 문서 없음). Argmax OSS SpeakerKit(MIT, `PyannoteDiarizationOptions(numberOfSpeakers:)`). speech-swift(Apache-2.0, `Community1SpeakerBounds`, 화자별 256차원 centroid 반환, M5 Pro 25x, 피크 863MiB–1.54GB) | 한국어 근거 없음. 중국어 데이터셋 DER은 위 표 | **즉시 시험** (oracle 화자 수 + 임베딩 기반 등록의 기준선) |
| **DiariZen Large-s80-v2** (BUT, 가지치기 WavLM + Conformer + VBx) | 벤치마크 갱신 2025-12-09, 사전학습 모델 2025-06-03 (GitHub Updates) | 코드 MIT, **가중치 CC BY-NC 4.0** (연구·학술 전용, 상업 사용 시 법적 위험 부담 명시) | BUT 측정, collar 0: AMI-SDM 13.9, AISHELL-4 10.1, AliMeeting far 10.8, NOTSOFAR-1 16.7, MSDWild 15.8, DIHARD3 14.5, VoxConverse 9.1. ETH 벤치(2509.26177): 전체 13.3 (pyannoteAI 11.2), 5명+ 7.1 | README에 화자 수 파라미터 언급 없음(미확인). ETH 표에서 화자 수 증가에 강건 | 미확인 | 공식 Apple 포트 없음. CUDA 설치 안내만 있음 | 일본어 15.6, 중국어 10.1 (ETH, CALLHOME 위주 2인 통화) | **관찰** (성능 근거는 강하나 NC 라이선스와 Swift 경로 부재) |
| Streaming Sortformer 4spk v2 / v2.1 (NVIDIA) | 논문 2025-07-24, v2.1 날짜 미확인 | v2 CC-BY-4.0, v2.1 NVIDIA Open Model License | NVIDIA: v2.1 30.4s AliMeeting near 11.73, AMI SDM 17.80, NOTSOFAR1 ≥5명 34.81. FluidAudio AMI SDM 31.7%(구 체크포인트, M2) | v2.1 SCA NOTSOFAR1 33% (5명 이상 회의 붕괴). OpenBench AISHELL-4 SCA 0% | **4** | FluidAudio·speech-swift·mlx-audio | 영어 위주 학습 명시 | **제외** (4명 상한이 화자 수 붕괴의 직접 원인, Nemotron 3로 대체) |
| Sortformer diar_sortformer_4spk-v1 | 2024 | CC-BY-4.0 | ETH: 4명 21.3, 5명+ 23.9 | 4명 상한 | 4 | mlx-audio | 일본어 16.5 | **제외** |
| NeMo MSDD + TitaNet + MarbleNet | 2022–2023 | TitaNet CC-BY-4.0 | TitaNet 카드(oracle VAD): AMI MixHeadset 1.73–1.89 | 군집 기반, known # 지원 | 상한 문서 없음 | 공식 포트 없음 | TitaNet은 영어 학습 | **제외** (2025-06 이후 갱신 없음, Sortformer 계열로 무게중심 이동) |
| 3D-Speaker 파이프라인 (Alibaba, CAM++ / ERes2NetV2) | 마지막 뉴스 2024-12 | Apache-2.0 | 3D-Speaker 측정(collar 미기재): overlap 검출 시 AISHELL-4 10.30, AliMeeting 19.73, AMI_SDM 21.76 | 군집 기반 | 미확인 | ONNX 런타임 스크립트, sherpa-onnx 임베딩으로 사용 가능 | 중국어 20만 화자 데이터로 학습한 임베딩 | **관찰** (파이프라인보다 등록용 임베딩 후보로) |
| WeSpeaker | w2v-bert2 2025-12-05, U³-xi 2026-09-22 | Apache-2.0 | 웹 페이지에 DER 없음 | UMAP+HDBSCAN 레시피 | 미확인 | community-1 내부 임베딩이 WeSpeaker ResNet34 | CNCeleb 등 중국어 모델 존재 | **관찰** (임베딩 소스) |
| LS-EEND (Westlake, FluidAudio 내장) | 논문 2024-10 | 미확인 | 논문 온라인 AMI 20.76. FluidAudio M4 Max AMI SDM 20.7% | SCA AMI 15/16 | 10 (FluidAudio) | FluidAudio CoreML | 없음 | **제외** (스트리밍용, 배치에선 Nemotron 3가 우위) |
| mago-ai ultra_diar_streaming_sortformer_8spk_v1 | 미확인 | 미확인 | 벤치마크 없음 | 미확인 | 8 | speech-swift "experimental" | 없음 | **제외** (근거 없음) |

### 1-B. 화자귀속 ASR (누가·언제·무엇을 한 번에)

| 모델 | 공개일 (출처) | 라이선스 | 화자 지표 (측정 주체) | 최대 길이 / 화자 | Apple Silicon | 한국어 근거 | 판정 |
|---|---|---|---|---|---|---|---|
| **MOSS-Transcribe-Diarize 0.9B** (MOSI.AI/OpenMOSS, Whisper-Medium 인코더 + Qwen3-0.6B형 디코더) | 2026-07-09 (HF 카드), arXiv 2601.01554 (v7 2026-07-17) | Apache-2.0 | 저자 측정 cpCER: AISHELL-4 15.83, AliMeeting 22.17 (같은 표 VibeVoice 24.99 / 29.33, Gemini 3 Pro 27.43 / 32.84). DER 미보고. 2nd MLC-SLM(Interspeech 2026) Task1 1위 tcpMER 14.93 (주최측 요약 2609.27514) | 단일 패스 90분. 화자 상한 미기재. **타임스탬프는 세그먼트 단위, 단어 단위 아님** | speech-swift MLX INT5/INT8(가중치 ~1.0–1.2GB), CoreML은 1,024 토큰 단문용. 속도 수치 없음 | MLC-SLM 14개 언어에 한국어 포함. 단 **MLC-SLM은 전부 2인 대화**(주최측 논문). speech-swift는 정확도를 영어로만 측정 | **관찰** (작고 상업 라이선스지만 한국어 다자 근거 없음, 단어 타임스탬프 없음) |
| **VibeVoice-ASR 9B** (Microsoft) | 2026-01-21 오픈소스 (GitHub News), 기술보고서 arXiv 2601.18184 (v2 2026-03-14) | MIT. 단 README가 "추가 테스트 없이 상업·실사용 권장하지 않음" 명시 | 저자 측정: MLC-Challenge 한국어 DER 4.52 / cpWER 15.35 / tcpWER 16.07. AISHELL-4 DER 6.77, AliMeeting 10.92, AMI-SDM 13.43. 비교 대상은 Gemini 2.5/3 Pro만 | 단일 패스 60분(64K 토큰). 화자 상한 미기재 | mlx-audio 4bit(5.71GB)/bf16. 100분 파일이 59분으로 잘림, 59분 처리 524.8s (M5 Max 128GB), 피크 30.4GB(Activity Monitor 프리필 61.5GB). Simon Willison 2026-04-27 | 한국어 수치는 MLC-SLM 2인 대화이고 **MLC-SLM 학습 split을 SFT에 사용** (인도메인) | **관찰** (48GB에서 60분 처리 메모리 여유 불확실, 2인 데이터 근거, 실사용에서 1명→2명 분할 사례) |
| Nemotron 3.5 ASR streaming 0.6B + Nemotron 3 Diarization | ASR 2026-06-04 (HF 카드) | OpenMDW-1.1 | 한국어 FLEURS CER 7.12–8.31 (NVIDIA, 단일 화자 ASR). 화자귀속 지표 미보고 | ASR 최대 길이 GPU 메모리 의존 | speech-swift에 Nemotron Streaming 다국어(40 locale) 포트. 결합 파이프라인 포트는 미확인 | ko-KR "transcription-ready" | **관찰** (Soniox 대비 한국어 ASR 품질 미검증, 화자분리는 Nemotron 3 단독 시험으로 충분) |
| multitalker-parakeet-streaming-0.6b-v1 (NVIDIA) | 미확인 (관련 논문 2025-06/07) | NVIDIA Open Model License | cpWER AMI IHM 21.26 / SDM 37.44 | 화자당 인스턴스 | 미확인 | **영어 전용** (NVIDIA 직원 HF 답변) | **제외** |
| SE-DiCoW / DiCoW v3.3 (BUT, Whisper large-v3-turbo 기반 target-speaker ASR) | SE-DiCoW 논문 2026-01-27 (arXiv 2601.19194), ICASSP 2026 | SE-DiCoW Apache-2.0, DiCoW v3.3 CC-BY-4.0 | tcpWER AMI SDM 18.5, NOTSOFAR-1 26.2 (DiariZen 분할 사용, BUT 측정) | 화자분리 결과 필요 | 미확인 (remote code 필요) | 학습 데이터 전부 영어. 한국어 평가 없음 | **관찰** (자기 등록으로 겹침 구간 E1을 줄이는 방향은 유효하나 한국어 미검증) |
| SpeakerLM (Alibaba Tongyi) | arXiv 2508.06372 (2025-08), AAAI | 미확인 | cpCER AliMeeting 16.05 vs DiariZen+Paraformer 23.20 (저자 측정). 화자 등록 시 saCER 15.57 | 평가 최대 7명 | 없음 | 중국어 실데이터 | **제외** (가중치 공개 미확인) |
| SoulX-Transcriber (Soul AI Lab) | arXiv 2606.02400 | 미확인 | AISHELL-4/AliMeeting SOTA 주장 | 미확인 | 없음 | ZH/EN만 (2차 출처) | **제외** |
| TagSpeech | arXiv 2601.06896 (ACL 2026) | 미확인 | AMI·AliMeeting DER | 미확인 | 없음 | 미확인 | **제외** (가중치 미확인) |
| Google DiarizationLM (8b/13b Fisher) | 2024 (HF 컬렉션 2024-09 이후 갱신 없음) | Llama 2/3 라이선스 | Fisher·Callhome 영어 WDER | 해당 없음 (후처리) | 없음 | 없음 | **제외** (영어, 그리고 텍스트 문맥으로 화자를 고치는 방식은 DAMA 경계 4와 충돌) |
| Qwen3-ASR / Qwen3-Omni | Qwen3-ASR 2026-01 | Apache-2.0 | 네이티브 화자분리 기능 문서 없음. Qwen3-Omni는 프롬프트 기반 시도만 논문에 등장 | 해당 없음 | speech-swift MLX/CoreML | 한국어 ASR 지원 | **제외** (화자분리 대안 아님) |
| Kimi-Audio / Step-Audio 2 / MiMo-Audio | 2025 | 각자 | 화자분리·화자귀속 지표 발견 못함 | 해당 없음 | 해당 없음 | 해당 없음 | **제외** |
| Voxtral Transcribe 2 (Mistral) | 2026-02-04 | 화자분리는 비공개 API 모델에만 있음, 오픈 가중치 Realtime은 화자분리 미기재 | 미확인 | 미확인 | 해당 없음 | 13개 언어에 한국어 포함 (2차 출처) | **제외** (이 트랙 범위 밖, 클라우드) |

### 1-C. Apple Silicon 런타임·Swift 통합

| 런타임 | 라이선스 | 포함 화자분리 | oracle 화자 수 | 등록(enrollment) | 비고 |
|---|---|---|---|---|---|
| **FluidAudio** (FluidInference) | Apache-2.0 | community-1 offline(VBx), Nemotron 3(2026-09-23 머지, v0.17.3+), Sortformer(4), LS-EEND(10), 레거시 DiarizerManager | offline 문서에 없음 | Sortformer/LS-EEND `enrollSpeaker` (스트리밍 전용, 문서상 Sortformer는 비슷한 목소리도 매핑, LS-EEND는 실패 가능). `DiarizationResult.speakerDatabase` 임베딩 노출 | macOS 14+, 단 macOS 14.x는 ANE BNNS 버그로 15+ 권장. Swift 패키지·CocoaPods. 한국어 ASR 모델 없음 |
| **speech-swift** (soniqo) | Apache-2.0 | Pyannote(경량), community-1(CoreML+Swift VBx), Sortformer, Nemotron 3(CoreML/MLX), Ultra-Sortformer 8spk(실험), MOSS-Transcribe-Diarize(MLX) | community-1만 `--num-speakers`, `--min/max-speakers` | Pyannote 엔진만 `--target-speaker enrollment.wav` (코사인 최고 군집 선택). Nemotron 3·Sortformer는 임베딩이 없어 등록 불가 | macOS 15+, Swift 6+. Qwen3-ASR·Qwen3-ForcedAligner MLX/CoreML도 포함 (현 DAMA 로컬 비교 경로와 같은 모델) |
| **Argmax OSS (SpeakerKit)** | MIT | community-1 (pyannote v4) | `numberOfSpeakers` | 미확인 | SpeakerKit macOS 13+. Pro SDK 3(2026-09-23, 유료)는 OpenBench에 Nemotron 3 실행 결과 게시 |
| sherpa-onnx | Apache-2.0 | pyannote seg-3.0 / Reverb + 3D-Speaker·NeMo 임베딩, 군집 | `num_clusters` (데모 코드 기준) | 임베딩 추출기 별도 제공 | Nemotron 3 PR #4032 미머지, Swift XCFramework 갱신 필요 |
| mlx-audio / mlx-audio-swift | MIT (미확인 세부) | Sortformer v1/v2.1, VibeVoice-ASR | 없음 | 없음 | VibeVoice MLX가 59분 상한으로 자름 |

---

## 2. 화자 수 붕괴(우선순위 1) 관점 정리

### 2.1 같은 참조로 잰 화자 수 정확도(SCA, %) 비교: Argmax OpenBench (2026-09-22 실행, M2 Ultra / 클라우드)

| 데이터셋 | pyannoteAI precision-3 (클라우드) | community-1 (SpeakerKit) | Sortformer v2.1 | Nemotron 3 |
|---|---|---|---|---|
| AISHELL-4 (중, 회의) | 70 | 60 | 0 | 90 |
| AliMeeting (중, 회의) | 95 | 65 | 70 | 100 |
| AMI-SDM | 75 | 69 | 94 | 88 |
| CallHome | 82 | 42 | 82 | 92 |
| DIHARD-III | 78 | 44 | 70 | 83 |
| MSDWild | 50 | 28 | 45 | 59 |
| Earnings-21 | 64 | 57 | 2 | 25 |
| 평균 | 64 | 50 | 46 | 71 |

- 해석: 2–6인 대면 회의에 가까운 AISHELL-4·AliMeeting에서 Nemotron 3가 가장 높다. Earnings-21(통화 참여자 다수)에서 25%로 급락하는데, 8명 상한의 영향으로 추정되나 원인 분석은 미확인.
- precision-2는 이 표에 없다. pyannoteAI 자체 주장으로 precision-2는 "가장 어려운 벤치마크"에서 화자 수 70% 정확(2025-09-02 changelog), precision-3는 precision-2 대비 평균 DER 16.02→14.35, 화자 오귀속 18.7% 감소(2026-09-17 changelog, 자사 측정). 현 운영 기준을 precision-3로 올리는 것은 이 트랙 밖이지만 가장 싼 개선 경로일 수 있어 기록한다.
- 이해상충: Argmax는 Pro SDK 3에서 Nemotron 3를 판매하고 pyannote와도 제휴하고 있다. 독립 측정이라 보기 어렵다.

### 2.2 oracle 화자 수와 상한

| 후보 | 정확 화자 수 지정 | 범위 지정 | 상한 |
|---|---|---|---|
| community-1 (pyannote 원본, SpeakerKit, speech-swift) | 예 | 예 | 없음 |
| community-1 (FluidAudio offline) | 문서상 없음 | 없음 | 없음 |
| Nemotron 3 | 없음 | 없음 | 8 |
| Sortformer v2/v2.1 | 없음 | 없음 | 4 |
| sherpa-onnx 군집 | `num_clusters` | 없음 | 없음 |
| VibeVoice-ASR / MOSS | 프롬프트·hotword로 맥락 주입은 가능, 화자 수 강제 파라미터는 미확인 | 미확인 | 미확인 |

- Nemotron 3에서 참석자 수를 알 때 상위 N개 채널만 남기는 후처리는 기술적으로 가능해 보이나(출력이 [T,8] 확률) 검증된 방법이 아니다. 시험 시 별도 arm으로 두고 결과를 비교해야 한다.

### 2.3 장시간(2시간+) 녹음 위험

- Nemotron 3 카드: 청크 추론에 고정 최대 길이 없음. 다만 Streaming Sortformer v2 카드는 "매우 긴 녹음에서 성능 저하 가능"을 명시하고, 화자 캐시 크기가 고정(Nemotron 3 FluidAudio 포트 기준 speaker cache 264행)이다. 오래 말이 없던 화자가 돌아올 때 새 화자로 분할되거나 기존 화자로 흡수될 가능성은 2시간 데이터로 검증된 바 없다(미확인).
- VibeVoice 60분, MOSS 90분 상한: 2시간 회의는 청크 분할 후 청크 간 화자 연결이 필요하며, 이 단계가 바로 화자 수 붕괴·E1의 원천이 된다.

### 2.4 비슷한 목소리

- 비슷한 목소리에 대한 정량 벤치마크는 찾지 못했다(미확인). FluidAudio 문서는 스트리밍 등록에서 Sortformer가 비슷한 목소리도 높은 신뢰로 매핑하고 LS-EEND는 "too close to existing speaker"로 등록이 실패할 수 있다고 적었지만 수치는 없다.

---

## 3. E1(오귀속)·화자 수 교정을 위한 등록(enrollment)·target-speaker 접근

| 접근 | 상태 | DAMA 적합성 |
|---|---|---|
| pyannoteAI voiceprint + identify (클라우드) | precision-2 전용. voiceprint 30초 이하, 단일 화자 음성, `matching.threshold`·`exclusive` 옵션. 식별 confidence는 화자별 map | 현 스택에서 즉시 가능. 이 트랙 밖이지만 E1·화자 수 교정 효과가 가장 직접적일 수 있음 |
| community-1 centroid + 참석자별 등록 음성 임베딩 비교 (로컬) | speech-swift가 화자별 256차원 centroid와 `--target-speaker` 제공. FluidAudio는 `speakerDatabase` 노출 | 군집 2개가 같은 등록 화자에 붙으면 "1명이 2명으로 분할" 후보, 한 군집 안 세그먼트가 두 등록 화자에 나뉘어 붙으면 "병합" 후보로 표시 가능. 자동 확정이 아니라 검수 플래그로 쓰면 경계 3(모르는 화자 null)과 양립 |
| 임베딩 모델 교체 (CAM++ / ERes2NetV2 / WeSpeaker w2v-bert2 / TitaNet / ECAPA) | CAM++·ERes2NetV2는 중국어 20만 화자 학습, TitaNet·ECAPA는 영어 VoxCeleb 계열 | 한국어 화자 변별력 근거 없음. 등록 매칭용으로 2–3개를 같은 데이터로 비교하는 소규모 실험 가치 있음 |
| SE-DiCoW 자기 등록 target-speaker ASR | 영어 학습만. remote code 필요 | 관찰 |
| SpeakerLM 화자 등록 | 등록 시 saCER 개선 보고, 가중치 미확인 | 제외 |
| DiarizationLM류 LLM 후처리 | 텍스트 문맥으로 화자를 바꿈 | DAMA 경계 4(문맥만으로 화자 귀속 추정 금지)와 충돌. 제외 |

---

## 4. 2025-06 이후 새로 나온 것 (시간순)

| 날짜 | 항목 | 비고 |
|---|---|---|
| 2025-06-03 | DiariZen 새 사전학습 모델·가지치기 레시피 | 가중치 CC BY-NC |
| 2025-07-24 | Streaming Sortformer 논문 (arXiv 2507.18446) | v2 / v2.1 카드의 근거 |
| 2025-08 | SpeakerLM 논문 (arXiv 2508.06372) | 가중치 미확인 |
| 2025-09-02 | pyannoteAI precision-2 API (클라우드) | 비교 기준 |
| 2025-09-29 | pyannote.audio 4.0 + community-1 | VBx, exclusive 모드 |
| 2025-09 | ETH "Benchmarking Diarization Models" (arXiv 2509.26177) | 언어별·화자 수별 DER |
| 2025-12-05 | WeSpeaker w2v-bert2 지원 | |
| 2025-12-09 | DiariZen Large-s80-v2 벤치 | |
| 2026-01-21 | VibeVoice-ASR 오픈소스 | 60분, 50+ 언어 |
| 2026-01-27 | SE-DiCoW 논문 (arXiv 2601.19194) | Apache-2.0 |
| 2026-01-31 | DiariZen 다채널 WavLM 지원 | |
| 2026-06-04 | Nemotron 3.5 ASR streaming 0.6B | 한국어 transcription-ready |
| 2026-07-09 | MOSS-Transcribe-Diarize 0.9B | Apache-2.0, 90분 |
| 2026-07-23 | VibeVoice-ASR-BitNet (CPU) | |
| 2026-09-03 | VibeVoice-ASR-Streaming | 10개 언어, 한국어 포함 여부 미확인 |
| 2026-09-17 | pyannoteAI precision-3 (클라우드·온프레미스) | 이 트랙 밖 |
| 2026-09-22 | Argmax OpenBench 재실행 (Nemotron 3, precision-3, community-1) | SCA 표 |
| 2026-09-23 | **NVIDIA Nemotron-3-Diarization**, FluidAudio CoreML 포트 머지, Argmax Pro SDK 3 | 8명, 상업 가능 |
| 2026-09 | 2nd MLC-SLM 결과 요약 (arXiv 2609.27514) | MOSS 1위, 데이터는 2인 대화 |
| 2026-10-10 | sherpa-onnx Nemotron 3 PR 열림 | 미머지 |

---

## 5. 반론과 실패 경로

1. **한국어 근거 공백.** 모든 화자분리 DER은 영어·중국어(일부 일본어·인도어)다. 화자분리가 언어 독립적이라는 통념은 있으나, Nemotron 3·community-1 모두 한국어 학습 데이터 명시가 없다. ETH 벤치에서 같은 모델의 언어별 DER 편차가 크다(pyannote 3.1: 영어 11.5, 일본어 28.8). 한국어에서도 이런 편차가 있을 수 있다.
2. **벤치 비교 불가 문제.** Nemotron 3의 AMI·AliMeeting 수치는 forced-alignment 참조라 pyannote 카드의 수치(사람 라벨)보다 낮게 나온다. "Nemotron 3 AMI 9.25 vs precision-2 AMI 12.9" 식 비교는 무효. 같은 참조로 잰 비교는 OpenBench뿐이고, 그 측정 주체(Argmax)는 Nemotron 3 판매사다. Baseten 측정에서는 AMI에서 community-1에 졌다.
3. **화자 수 지정 불가.** Nemotron 3는 참석자 수를 알아도 강제할 수단이 없다. 사용자가 가장 싫어하는 실패(화자 수 붕괴)가 나왔을 때 사용자가 개입할 손잡이가 없다는 뜻이다. community-1은 손잡이가 있지만 자동 추정이 약하다. 두 모델을 함께 돌려 화자 수·단어별 화자 불일치를 검수 플래그로 쓰는 구성이 필요할 수 있다.
4. **E2E 화자귀속 ASR의 구조적 불일치.** MOSS·VibeVoice는 세그먼트 단위 타임스탬프와 생성형 디코딩이라 짧은 끼어들기 누락(경계 2)과 문장 병합(E2)을 숨길 위험이 있다(정량 근거 없음, 미검증). DAMA의 단어 단위 시간 겹침 병합 계약과도 맞지 않는다.
5. **메모리·길이.** VibeVoice 4bit가 59분에 피크 30GB(프리필 시 61.5GB 관측, 128GB 기기)라 48GB M5 Pro에서 60분 처리가 가능한지 미확인.
6. **라이선스.** DiariZen 가중치 NC. VibeVoice는 MIT지만 상업 사용 비권장 문구. Nemotron 3(OpenMDW-1.1)와 community-1(CC-BY-4.0, 귀속 표기 필요), MOSS(Apache-2.0)는 상업 가능.
7. **포트 정합성.** FluidAudio 문서 간 Sortformer DER이 31.7%와 26.4%로 다르고, CoreML Nemotron 3는 NVIDIA 대비 DER +0.2–0.3, 저지연 프리셋에서 SCA 하락(75% vs 81.25%). 포트별로 원본과 결과가 다를 수 있어 PyTorch 원본과의 대조가 필요하다.

---

## 6. 시험 제안 (판단 재료, 실행 아님)

- 데이터: DAMA 사용자 동의를 받은 한국어 실녹음 중 화자 수가 확실한 3–6인 회의, 정답 RTTM(사람 라벨) 작성. 공개 대안은 AI Hub "주요 영역별 회의 음성인식 데이터"(3인 이상, 약관 확인 필요).
- 지표 우선순위: ① SCA와 화자 수 오차 방향(과소/과대) ② DER의 confusion 성분(collar 0, overlap 포함) ③ 단어별 화자 정확도(현 Soniox 단어 타임스탬프에 병합 후) ④ 0.5초 이하 끼어들기 재현율.
- arm: (a) 현 precision-2 (numSpeakers 지정/미지정) (b) Nemotron 3 offline, FluidAudio CoreML (c) community-1 oracle/범위 화자 수, speech-swift 또는 SpeakerKit (d) (b)+(c) 불일치 플래그 (e) 관찰용 MOSS-Transcribe-Diarize MLX.
- 판정 기준을 감지 인원 일치 하나로 두지 않는다(운영 기준 계약과 동일).

---

## 7. 출처 URL (접속일 2026-10-14)

pyannote
- https://huggingface.co/pyannote/speaker-diarization-community-1
- https://github.com/pyannote/pyannote-audio/releases
- https://pyannote.ai/blog/community-1
- https://www.pyannote.ai/changelog
- https://huggingface.co/pyannote/speaker-diarization-precision
- https://docs.pyannote.ai/tutorials/identification-with-voiceprints

NVIDIA
- https://huggingface.co/nvidia/Nemotron-3-Diarization
- https://huggingface.co/nvidia/Nemotron-3-Diarization/blob/main/ASR_INTEGRATION_GUIDE.md
- https://huggingface.co/nvidia/diar_streaming_sortformer_4spk-v2
- https://huggingface.co/nvidia/diar_streaming_sortformer_4spk-v2.1
- https://huggingface.co/nvidia/multitalker-parakeet-streaming-0.6b-v1
- https://huggingface.co/nvidia/nemotron-3.5-asr-streaming-0.6b
- https://huggingface.co/nvidia/speakerverification_en_titanet_large
- https://docs.nvidia.com/nemo-framework/user-guide/latest/nemotoolkit/asr/speaker_diarization/models.html
- https://arxiv.org/html/2507.18446v1
- https://www.baseten.co/blog/nvidia-nemotron-3-diarization/
- https://www.unite.ai/nvidia-releases-nemotron-3-diarization-open-weight-speaker-model/ (2차)

DiariZen / BUT
- https://github.com/BUTSpeechFIT/DiariZen
- https://huggingface.co/BUT-FIT/diarizen-wavlm-large-s80-md
- https://huggingface.co/BUT-FIT/SE-DiCoW
- https://huggingface.co/BUT-FIT/DiCoW_v3_3

Alibaba / WeSpeaker / SpeechBrain
- https://github.com/modelscope/3D-Speaker
- https://github.com/modelscope/3D-Speaker/tree/main/egs/3dspeaker/speaker-diarization
- https://github.com/wenet-e2e/wespeaker
- https://huggingface.co/speechbrain/spkrec-ecapa-voxceleb
- https://arxiv.org/html/2508.06372v3 (SpeakerLM)

화자귀속 ASR
- https://huggingface.co/microsoft/VibeVoice-ASR
- https://github.com/microsoft/VibeVoice
- https://arxiv.org/abs/2601.18184 , https://arxiv.org/html/2601.18184v2
- https://simonwillison.net/tags/prince-canuma/ (VibeVoice MLX 실측, 2026-04-27)
- https://huggingface.co/OpenMOSS-Team/MOSS-Transcribe-Diarize
- https://arxiv.org/abs/2601.01554
- https://arxiv.org/html/2609.27514 (2nd MLC-SLM 요약)
- https://arxiv.org/pdf/2509.13785 (1st MLC-SLM 요약, 2인 대화)
- https://arxiv.org/abs/2601.06896 (TagSpeech)
- https://arxiv.org/pdf/2606.02400 (SoulX-Transcriber)
- https://arxiv.org/html/2401.03506v5 (DiarizationLM)
- https://mistral.ai/news/voxtral-transcribe-2

벤치마크
- https://github.com/argmaxinc/OpenBench/blob/main/BENCHMARKS.md
- https://arxiv.org/html/2509.26177 (ETH Benchmarking Diarization Models)
- https://arxiv.org/abs/2609.23114 (SpeechLM 전체 회의 화자분리 한계)

Apple Silicon 런타임
- https://github.com/FluidInference/FluidAudio
- https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Benchmarks.md
- https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Diarization/GettingStarted.md
- https://github.com/FluidInference/FluidAudio/pull/883
- https://huggingface.co/FluidInference/nemotron-3-diarization-coreml
- https://docs.fluidinference.com/diarization/offline-pipeline
- https://docs.fluidinference.com/diarization/sortformer
- https://github.com/soniqo/speech-swift
- https://soniqo.audio/guides/diarize
- https://raw.githubusercontent.com/soniqo/speech-swift/main/docs/models/moss-transcribe-diarize.md
- https://huggingface.co/aufklarer/Pyannote-Community-1-CoreML
- https://github.com/argmaxinc/argmax-oss-swift
- https://www.argmaxinc.com/blog
- https://github.com/k2-fsa/sherpa-onnx/pull/4032
- https://k2-fsa.github.io/sherpa/onnx/speaker-diarization/index.html
- https://github.com/Blaizzy/mlx-audio

한국어 데이터
- https://aihub.or.kr/aihubdata/data/view.do?dataSetSn=464

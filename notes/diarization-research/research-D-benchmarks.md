# 트랙 D: 독립 벤치마크와 방법론 근거 (2025–2026)

- 조사일: 2026-10-14 (웹 1차 출처 조회일 동일)
- 범위: 화자분리(diarization)와 화자 귀속 ASR의 교차 벤더 벤치마크, E1/E2 원인 분해 근거, 개선 레버와 효과 크기, 한국어 평가
- 가중치: 사용자 우선순위 갱신에 따라 **화자 수 붕괴(3명→2명, 1명→2명) > E1 > E2** 순으로 근거를 배치했다.
- 증거 등급 표기
  - [독립]: 평가 대상과 이해관계 없는 학술·챌린지
  - [벤더]: 평가 대상 회사가 직접 수행
  - [경쟁 벤더]: 경쟁사가 수행 (자사 제품 포함)
  - [자가 시스템 포함]: 저자가 만든 시스템이 비교 대상에 포함
- 숫자는 출처 원문 값. 상대 변화율(%)은 원문 값으로 내가 계산한 것이고 "계산"이라고 적었다. 확인 못 한 값은 "미확인".

---

## 0. 결정에 직접 영향을 주는 결론 (요약)

1. **화자 수 오류는 DER로 잘 안 보인다.** DER은 시간 가중이라 발화량이 적은 화자를 놓쳐도 작게 잡힌다(Samarakoon & Zhu, arXiv 2609.27315, SLT 2026). 화자 수 정확도(SCA), 평균 화자 수 오차(MSCE/MAE), JER를 따로 재야 한다. ETH 벤치마크에서는 0.5초 미만 구간이 전체 오류의 5% 미만이라 짧은 끼어들기(E2의 원인)는 DER에서 거의 사라진다.
2. **정답 화자 수(oracle)를 주면 얼마나 좋아지나:** NTT CHiME-8 시스템에서 추정 화자 수를 정답으로 바꾸기만 했을 때 eval macro DER 18.03→16.66(계산 −7.6%), 2인 대화인 Mixer 6는 DER 8.26→6.41(계산 −22%), tcpWER 15.32→12.04(계산 −21%). 반대로 dev처럼 추정 화자 수가 이미 100% 맞으면 개선은 0이었다. **이득은 "추정이 틀린 녹음"에 몰린다.**
3. **pyannote 쪽 화자 수 근거는 벤더 수치뿐이다.** Precision-2는 내부 250+파일(2–10명)에서 정확한 화자 수 70%(Precision-1 약 50%) [벤더]. 2026-09-17 공개된 Precision-3는 15개 데이터셋 평균 DER 16.02→14.35(−10.4%), 화자 혼동 −18.7%를 주장하지만 화자 수 정확도는 공개하지 않았다 [벤더]. 현재 API 기본값은 여전히 precision-2이고 precision-3는 opt-in, 가격 동일.
4. **pyannote voiceprint(identify)는 화자 수 붕괴를 고치지 않는다.** 공식 문서 원문: "Voiceprints are used only for identification. They do not improve diarization accuracy." 분리가 먼저 끝나고 그 결과에 이름만 붙인다.
5. **E1/E2의 주범은 대개 merge 정책이 아니라 diarization 자체다.** MLC-SLM 2026 2위 Transsion 시스템 ablation(한국어 포함 14개 언어, 2인 대화): 도메인 내 EEND 미세조정 22.78→16.40 tcpMER(계산 −28%), 단어-화자 병합 정책 교체(중점 기준→overlap 우선+0.3초 최근접 fallback) 16.40→16.01(계산 −2.4%). 다만 문단 첫·끝 단어 오귀속은 타임스탬프 부정확이 원인이라는 분류(Kirakosyan & Karamyan 2024)도 있어 경계 단어 E1은 정렬 문제일 수 있다.
6. **앙상블은 3개 이상일 때만 정석이다.** DOVER-Lap은 AMI test 21.5→20.5, LibriCSS 7.4→5.4 DER(최고 단일 대비). 구현체 문서는 2개 시스템 투표를 "will almost certainly lead to performance degradation"이라고 경고한다. **Soniox+P2 두 개라면 투표가 아니라 불일치 표시(→ null/검수 대상)로 써야 한다.**
7. **한국어 공개 근거는 매우 얇다.** 확인된 것은 MLC-SLM 2025 baseline(3D-Speaker)의 한국어 DER 23.25(겹침 제외)로, 15개 언어 평균 16.44보다 나쁘고 일본어(26.46) 다음으로 나쁘다. 단 이 데이터는 조용한 실내 휴대폰 녹음 2인 대화라 다자 회의와 다르다. 한국어 다자 회의 diarization 공개 벤치마크(2025–2026)는 찾지 못했다(미확인).
8. **마이크 거리 효과가 모델 교체 효과와 비슷하거나 크다.** P2 모델카드 AMI 근접(IHM) 12.9 vs 원거리 단일(SDM) 15.6 DER, Nemotron AliMeeting near 6.40 vs far 10.47, NOTSOFAR 다채널 우승 tcpWER 10.8 vs 단일채널 우승 22.2.

---

## 1. 벤치마크 표

| 이름 | 날짜 | 수행 주체 / 등급 | 데이터·언어 | 비교 시스템 | 헤드라인 수치 | 주의점 |
|---|---|---|---|---|---|---|
| Benchmarking Diarization Models (Lanzendörfer 외, ETH Zurich) arXiv 2509.26177 | 2025-09-30, ICML 2026 워크숍 포스터 | ETH Zurich [독립] | CALLHOME(영·중·일·독·스), VoxConverse, AMI, AliMeeting, 196.6h. **한국어 없음** | pyannote 3.1, pyannoteAI(precision-2 기반), Sortformer v1/v2/v2-stream, DiariZen | 전체 DER: pyannoteAI 11.2, DiariZen 13.3. 언어별 pyannoteAI: 중 10.0, 영 6.6, 독 8.3, 일 13.8, 스 14.3. 화자 수별 pyannoteAI: 2명 9.9, 3명 9.1, 4명 10.1, 5명+ 6.6. Sortformer(4명 상한) 5명+ 23.9 | collar 0.25s, 겹침 포함. 누락(miss)이 최대 오류원. 0.5초 미만 구간은 오류의 5% 미만. JER 미보고. 화자 수 정확도 미보고 |
| SDBench (Argmax) arXiv 2507.16136 v2 | 2025-08-06 | Argmax [자가 시스템 포함: SpeakerKit] | 13개 데이터셋(CALLHOME, DIHARD-III, AMI, AliMeeting, AISHELL-4, Ego4D 등), 영·중·다국어 | pyannote 3.1, Picovoice Falcon, AWS, Deepgram, Pyannote AI API, SpeakerKit | 본문에 데이터셋별 DER 수치 없음(그림만). "Pyannote AI API가 최저 DER" 정성 서술 | collar 없음. Picovoice는 2개 데이터셋만, Deepgram은 일부 타임아웃. cpWER 미평가 |
| pyannote community-1 모델카드 벤치마크 | 2025-09 갱신 | pyannote [벤더] | AISHELL-4, AliMeeting, AMI, AVA-AVD, CALLHOME, DIHARD 3, Ego4D, MSDWild, RAMC, REPERE, VoxConverse | 3.1 / community-1 / precision-2 | precision-2 DER: AISHELL-4 11.4, AliMeeting 15.2, AMI IHM 12.9, AMI SDM 15.6, CALLHOME 16.6, DIHARD3 14.7, RAMC 10.5, VoxConverse 8.5 | "fully automatic, no collar, overlap 포함". oracle 화자 수 사용 여부 명시 없음 |
| pyannote 공개 benchmark 페이지 | 페이지 표기 2026-10-12(사이트 공통 렌더 날짜일 가능성) | pyannote [벤더] | DIHARD 10개 도메인, 259 녹음 | Precision-3, Community-1, AssemblyAI U-3.5 Pro, Deepgram Nova-3, ElevenLabs Scribe v2, **Soniox stt-async-v5**, Speechmatics | 수치는 차트로만 제공, 텍스트 추출 실패(미확인) | "We did not provide the number of speakers for any of them." Soniox v5가 포함된 유일한 비교지만 벤더 수행 |
| Precision-3 changelog | 2026-09-17 | pyannote [벤더] | 15개 벤치마크 데이터셋(목록 미공개) | precision-2 vs precision-3 | 평균 DER 16.02→14.35(−10.4%), 화자 혼동 −18.7% (DER 개선의 53%) | 화자 수 정확도, 언어별 수치 미공개 |
| Picovoice speaker-diarization-benchmark | 갱신일 미확인 | Picovoice [벤더] | VoxConverse test 영어 | AWS, Azure, Google, Falcon, pyannote.audio | DER: pyannote 9.0, Falcon 10.3, AWS 11.1, Azure 15.7. JER: Falcon 19.9, pyannote 27.4, AWS 29.8 | 엔진 버전 미기재. 영어만 |
| Gladia 화자분리 제품 페이지 | 미확인(©2025) | Gladia [경쟁 벤더] | DIHARD III | Gladia(Solaria-1, pyannote Precision-2 결합 제품), NeMo, pyannoteAI, Speechmatics, AWS, **Soniox**, ElevenLabs, AssemblyAI, Deepgram | DER: Gladia 16.6, NeMo 20.4, pyannoteAI 23, Speechmatics 30.1, AWS 33.8, **Soniox 37.8**, ElevenLabs 39.5, AssemblyAI 43.9, Deepgram 46.9 | 기본 설정, 화자 수 제공 여부·collar 미기재. Soniox 모델 버전 미기재. pyannote 자체 표(14.7)와 프로토콜이 달라 비교 불가 |
| AssemblyAI cpWER 내부 벤치마크 | 2026-06/07 | AssemblyAI [벤더] | 비공개 "real-world" 혼합, 영어 중심 | Universal-3.5 Pro, Scribe v2, Gladia, Deepgram Nova-3 | 평균 cpWER 30.17 / 35.26 / 36.87 / 37.92 | 같은 모델에 35.21이라는 다른 수치도 공개되어 불일치. cpWER에 직접 최적화했다고 명시 |
| NVIDIA Nemotron-3-Diarization 모델카드 | 2026-09-23 | NVIDIA [벤더] | DIHARD III, CALLHOME p2, AliMeeting, AMI, NOTSOFAR1 | Nemotron-3-Diarization vs Streaming Sortformer v2.1 | CALLHOME p2 SCA 91.6(기준 84.4), MAE 0.084. DER 화자 수별 2명 5.98, 3명 9.26, 4명 11.03, 5명 15.82. NOTSOFAR1 단일채널 SCA 78.12(기준 33.12), DER 11.00(기준 30.49) | 최대 8명. 오픈 웨이트(OpenMDW 1.1). 한국어 미기재. AMI·AliMeeting·NOTSOFAR는 forced-alignment 기준 라벨 |
| NOTSOFAR-1 (CHiME-8) 요약 arXiv 2501.17304 v2 | 2025-03-09 | 챌린지 조직 [독립] | 실제 회의, 영어, 원거리 | 참가 5팀 | 단일채널 우승 tcpWER 22.2 / tcorcWER 17.7, 다채널 우승 10.8 / 9.5. BUT/JHU는 24.9 / 15.6 | tcpWER−tcorcWER = 화자 귀속 비용(1.3–9.3pt). "lower DER does not necessarily translate to lower tcpWER" |
| CHiME-7/8 DASR 리뷰 arXiv 2507.18161 | 2025-07-24 (v2 2025-11-01) | 챌린지 조직 [독립] | CHiME-6, DiPCo, Mixer6, NOTSOFAR | 9팀 32시스템 | 상위 시스템 모두 target-speaker diarization 정제 사용 | "Accurate speaker counting in the first diarization pass is thus crucial to avoid compounding errors." |
| MLC-SLM 2025 (Interspeech 2025) 요약 arXiv 2509.13785 | 2025-09-17 | 챌린지 조직 [독립] | 11개 언어 약 1,604h, **한국어 train 100.68h / dev 2.03h**, 2인 대화 약 20분, 조용한 실내 휴대폰 16kHz | 78팀 | Task II tcpMER: baseline 60.39(Eval-2), 1위 MegaAIS 16.53. baseline 한국어 DER 23.25(겹침 제외)/25.45, 15개 언어 평균 16.44/17.16 | 한국어는 tcpCER. 언어별 top 결과 미공개. 2인 고정이라 화자 수 붕괴 근거로는 약함 |
| MLC-SLM 2026 (Interspeech 2026) arXiv 2609.27514 | 2026-09-23 | 챌린지 조직 [독립] | 14개 언어 약 2,100h(한국어 포함, 한국어는 tcpCER), 2인 대화 | 91팀 | Task 1 Eval tcpMER: MOSS Transcribe Diarize 14.93, trasr 15.41 | 언어별 수치 미공개. "diarization one of the most influential components in cascaded systems" |
| MISP 2025 arXiv 2505.13971 | 2025-05 (Interspeech 2025) | 챌린지 조직 [독립] | 중국어 회의, 시청각 | 다수 팀 | 최고 DER 8.09(baseline 15.52), 최고 cpCER 11.56 | 영상 사용이라 DAMA에 직접 이식 불가 |
| DISPLACE-M 2026 arXiv 2603.02813 | 2026-03 | 챌린지 조직 [독립] | 의료 현장 다국어·코드믹스 2인 대화 | 12팀 | DER 수치 텍스트 미확인 | 한국어 없음 |
| Artificial Analysis STT | AA-WER v2.2 (2026-05) | Artificial Analysis [독립] | AgentTalk(비공개), VoxPopuli, Earnings22, 영어만 | 다수 STT | **화자분리 지표 없음** | WER·속도·가격만 |
| HF Open ASR Leaderboard arXiv 2510.06961 | v4 2026-03-30 | HF·NVIDIA·Cambridge·Mistral [독립] | 12개 데이터셋, 영어 short/long-form, 다국어 short-form | 86 시스템 | **화자분리·화자 귀속 지표 없음** | 한국어 포함 여부 미확인 |

**표에서 읽을 점**
- 교차 벤더 diarization 비교 중 Soniox가 들어간 것은 경쟁 벤더(Gladia)와 pyannote 자체 페이지뿐이고 둘 다 독립 평가가 아니다. **Soniox 화자분리에 대한 독립 수치는 없다(미확인).**
- 독립 평가(ETH)에서 pyannoteAI(precision-2)는 화자 수 증가에도 DER이 안정적이었다(2명 9.9, 5명+ 6.6). 반면 Sortformer류는 4명 상한 때문에 5명+에서 급격히 나빠진다.
- 같은 DIHARD III라도 pyannote 자체 14.7, Gladia 측정 pyannoteAI 23. collar·겹침 처리·화자 수 제공·API 버전 차이로 숫자가 1.5배 벌어진다. 벤더 숫자는 같은 프로토콜 안에서만 비교한다.

---

## 2. 화자 수 붕괴(최우선 실패) 근거와 레버

### 2.1 화자 수 추정이 실패하는 메커니즘
- 클러스터링 기반(pyannote 계열)은 화자 수를 직접 세지 않고 임베딩 클러스터 개수로 정한다. 유사도 임계값이 너무 느슨하면 실제 두 사람이 합쳐지고(과소), 너무 엄격하면 한 사람이 나뉜다(과다) (pyannote 블로그 "How diarization models count speakers", 조회 2026-10-14) [벤더 설명].
- 과소 추정 유발: 같은 성별·비슷한 목소리, 화자가 많을수록 악화. 과다 추정 유발: 같은 사람의 음향 변화(마이크 거리·방), 긴 녹음. 짧은 응답·맞장구는 임베딩이 불안정해 사라지거나 유령 화자를 만든다 (같은 출처).
- 짧은 세션·다수 화자에서 과소 추정이 체계적: NTT CHiME-8 baseline은 NOTSOFAR-1(평균 6분, 최대 8명)에서 SCA 13.8%, 추정 평균 3.0명 vs 정답 4.7명. 원인을 "less reliable clustering because of the limited number of speaker embeddings available"로 설명 (arXiv 2502.09859) [독립].
- 5명 이상 혼잡 녹음에서 EEND는 체계적으로 과소 추정하고 DER은 이를 숨긴다. 화자 가중 정규화로 JER 약 6%, DER 약 9% 상대 개선 (Samarakoon & Zhu, arXiv 2609.27315, 2026-09-23, SLT 2026) [독립].
- Soniox 공식 문서: "Accuracy may decrease when many speakers have similar voice characteristics." 최대 15명. 현재 문서에서 화자 수 지정 파라미터는 확인 못 함(미확인) [벤더].

### 2.2 레버별 근거와 효과 크기

| 레버 | 근거 | 효과 크기 | 등급 | 메모 |
|---|---|---|---|---|
| 정답 화자 수 고정(oracle / numSpeakers) | NTT CHiME-8 (arXiv 2502.09859) 추정→정답 교체만 | eval macro DER 18.03→16.66(계산 −7.6%), Mixer6(2인) 8.26→6.41(−22%), CHiME-6 32.59→30.29(−7.1%). dev(SCA 100%)는 변화 0 | 독립 | 추정이 이미 맞으면 이득 없음. 틀린 녹음에만 이득 |
| numSpeakers 권장 | pyannote 블로그: "setting numSpeakers typically results in better overall diarization performance" | 수치 없음 | 벤더 | API상 numSpeakers = minSpeakers==maxSpeakers와 동등 |
| 모델 세대 교체 | Precision-1→2 정확한 화자 수 50%→70%(내부 250+파일, 2–10명) | +20pt | 벤더 | Precision-3의 화자 수 정확도는 미공개 |
| 모델 세대 교체 | Sortformer v2.1→Nemotron-3: CALLHOME SCA 84.4→91.6, NOTSOFAR1 SC 33.12→78.12 | 큼 | 벤더 | 오픈 웨이트, 8명 상한 |
| 클러스터링 개선 + 짧은 구간 임베딩 제외 후 재할당 | Pálka 외 (arXiv 2510.19572, 2025-10-22) | DiariZen-Large MSCE 0.78→0.38, DER 14.5→13.0. pyannote 3.1 + cVBx DER 19.9→18.1. 8초 창에서 2초 미만 구간 제외 시 MSCE 0.58→0.16 | 독립(BUT·NTT) | **짧은 구간 임베딩이 화자 수를 흔든다는 직접 근거.** API 사용자는 직접 못 바꾸지만, 로컬 비교 diarizer를 둘 때 설정 근거가 됨 |
| 고정 최소 클러스터 크기의 부작용 | arXiv 2606.08505 (2026-06): 가속한 pyannote 3.1에서 VoxConverse DER 0.075→0.113 상승, 원인은 고정 최소 클러스터 크기로 인한 과소 추정 | +51%(악화) | 독립 | 소수 발언자가 "작은 클러스터"로 버려지는 경로. 본문 전체는 미확인(초록·발췌 기준) |
| 의도적 과다 추정 | ByteDance VoxSRC 2021 (arXiv 2109.02047): dev 녹음의 42.19%에서 추정 화자 수가 정답보다 적어, 추정치를 일부러 늘렸더니 DER 하락 | 크기 미확인 | 독립(대회 시스템) | 과소 추정이 더 흔한 실패라는 방증. 2021 자료 |
| 임계값 튜닝 | pyannote 2.1 문서: 화자가 적게 잡히면 임계값을 낮추라. 자기지도 diarization 논문은 dev에서 튜닝한 임계값이 test로 일반화 | 수치 없음 | 벤더/독립 | pyannoteAI API는 임계값 노출 안 함(api-reference 조회 2026-10-14) |
| voiceprint 등록(identify) | pyannote 문서: "They do not improve diarization accuracy." | 0 (분리 품질에 대해) | 벤더 | 최대 50개(FAQ), 30초 이하 단독 음성, matching.threshold 기본 0(문서는 50–70 권장), matching.exclusive 기본 true, 미매칭은 SPEAKER_xx + match null, 결과 24시간 후 삭제 |
| target-speaker 정제(TS-VAD/NSD) | USTC NOTSOFAR-1 (arXiv 2409.02041): 단계별 DER 23.43→19.09→14.19(ASR 디코딩 포함), SpkErr 2.36→1.50→2.21 | DER −39%(계산) | 독립(대회 시스템) | 1차 클러스터링 결과로 화자 프로필을 만든 뒤 재추정. 다채널 조건 |
| 앙상블(DOVER-Lap) | Raj 외 (arXiv 2011.01997, SLT 2021) | AMI test 최고 단일 21.5→20.5(−4.7%), LibriCSS 7.4→5.4(−27%), 혼동 2.9→2.0 | 독립 | 3개 이상 시스템. 2개 투표는 구현체가 성능 저하 경고. 화자 수는 영역별 가중 평균으로 정함 |
| 사람 검수 결합 | HAL 2021 active correction: 제한된 질의로 DER 최대 36.5% 상대 감소. Kili 정리(McKnight 2022): 구간 경계를 주면 사람 DER 1.41%, 맨손 15.60% | 큼 | 독립(구 자료) | DAMA 검수 창 방향과 일치 |

### 2.3 화자 수 평가에 써야 할 지표
- SCA(정확한 화자 수 비율), MSCE/MAE(평균 절대 오차), 과소/과다 방향(bias), JER(화자 가중). Nemotron 모델카드와 NTT 논문이 이 지표를 쓴다.
- DER만으로는 "3명→2명"이 몇 % 녹음에서 일어나는지 알 수 없다.

---

## 3. E1/E2는 어느 단계에서 생기나: diarization vs 타임스탬프 정렬 vs 병합 정책

### 3.1 단계 분해 근거

| 근거 | 내용 | 시사점 |
|---|---|---|
| Transsion, MLC-SLM 2026 2위 (arXiv 2609.20833, 2026-07-24) [독립 대회 시스템] | 단계별 누적 ablation, Eval tcpMER: baseline 22.78 → 도메인 EEND 미세조정 16.40 → 병합 정책(중점 기준 → overlap 우선 + 0.3초 최근접 fallback) 16.01 → 임베딩·PLDA 교체 15.72 → diarization 조건부 분할 15.41 | diarization 개선(−28%)이 병합 정책 개선(−2.4%)의 10배 이상. 한국어 포함 2인 대화 |
| MLC-SLM 2026 요약 (arXiv 2609.27514) | "diarization one of the most influential components", 장시간 녹음에서 타임스탬프 drift와 청크 간 화자 불일치. "accurate speaker–time–text alignment"가 E2E vs cascade 선택보다 결정적 | diarization과 정렬이 둘 다 핵심, 아키텍처 선택은 부차적 |
| NOTSOFAR-1 요약 | tcpWER − tcorcWER(화자 귀속 비용): 다채널 우승 1.3pt, 단일채널 우승 4.5pt, BUT/JHU 9.3pt. 낮은 DER이 낮은 tcpWER을 보장하지 않음 | 단일 마이크일수록 화자 귀속 비용이 커진다 |
| ETH 벤치마크 | 누락이 최대 오류원, 혼동은 Sortformer에서 두드러짐. 0.5초 미만 구간은 오류의 5% 미만, 실패는 긴 구간의 시작·끝 경계 부정확 | DER 관점의 "주범"은 경계와 누락. 짧은 끼어들기는 DER에 거의 안 잡힘 |
| Kirakosyan & Karamyan (arXiv 2409.00151, 2024-08-30) [독립] | 단어 단위 화자 오류 3분류: (a) 문단 내부 오태깅, (b) 문단 첫·끝 단어 오태깅, (c) 문단 전체 오귀속. (a)(b)는 균일 세그먼트화, (b)는 부정확한 단어 타임스탬프도 원인, (c)는 화자 수 추정·클러스터링 오류 | **E1 중 경계 단어형은 정렬, 문단 전체형은 화자 수·클러스터링.** 비율은 미보고 |
| Yu 외, Interspeech 2022 (arXiv 2203.16834) [독립, 구 자료] | diarization 결과와 인식 결과를 타임스탬프로 맞추는 과정이 오류를 만든다. 단어 단위 diarization(WD-SOT)으로 AliMeeting SD-CER 10.7% 상대 감소 | 중국어 회의에서 정렬 자체가 오류원이라는 직접 근거 |
| pyannote STT orchestration 블로그 [벤더] | "Slight timestamp mismatches mean words are attributed to the wrong speaker", 근거 수치 없음 | 정성 주장만. 수치 미공개(미확인) |

### 3.2 LLM 기반 화자 교정 방법과 DAMA 규칙의 충돌

| 방법 | 입력 | 효과 | DAMA 규칙과의 관계 |
|---|---|---|---|
| DiarizationLM (Google, arXiv 2401.03506, Interspeech 2024) | ASR+diarization 결과를 **텍스트로만** LLM에 입력 | v5 기준 WDER Fisher −55.5%, Callhome −44.9% (v1은 −25.9% / −31%, 버전 간 차이 원인 미확인) | **텍스트 문맥만으로 화자를 바꾸므로 규칙 위반.** 채택 불가 |
| SEAL (Amazon, arXiv 2501.08421, ICASSP 2025) | 텍스트 + EEND의 단어별 화자 사후확률(저/중/고 3단계) + 제약 디코딩(단어 변경 금지) | Δcp 기준 Fisher 3.72→2.12, CHAE test 5.41→4.68, RT03 test 3.87→2.34 (계산 −13.5~−43%) | 음향 근거를 쓰지만 어휘 문맥도 결정에 기여. 영어 전화만 평가. **자동 귀속이 아니라 "의심 구간 표시"로만 쓰는 것이 규칙과 양립** |
| Speaker Tagging Correction (Krisp, arXiv 2409.00151) | 비자기회귀 LM, 텍스트 기반 | Fisher WDER 2.8→2.42, GenSEC cpWER 24.64→23.97 | 텍스트 기반이라 규칙 위반 |

---

## 4. 기타 레버 (겹침, 전처리, 녹음 조건, 신뢰도)

| 레버 | 근거 | 효과 | 등급 |
|---|---|---|---|
| 근접 마이크 vs 원거리 단일 마이크 | precision-2 모델카드 AMI IHM 12.9 vs SDM 15.6 | SDM이 계산 +21% DER | 벤더 |
| 근접 vs 원거리 | Nemotron AliMeeting near 6.40 vs far 10.47 | far가 계산 +64% DER | 벤더 |
| 다채널 vs 단일채널 | NOTSOFAR-1 우승 tcpWER 10.8 vs 22.2 | 다채널이 51% 상대 개선 | 독립 |
| 디노이즈 전처리 | ByteDance 2021: SNR은 올랐지만 화자 특성 손상으로 DER 악화, 최종 제거. 교실 2025(arXiv 2505.10879): 누락 감소에는 도움, VAD와 혼동 사이 트레이드오프 | 혼재 | 독립 |
| 겹침 검출 | MLC-SLM 2025: 겹침 검출 없는 baseline이 더 좋았음(데이터의 겹침이 짧음). DOVER-Lap 개선은 주로 겹침 영역 누락 감소 | 조건 의존 | 독립 |
| Precision-3 감도 파라미터 | vadSensitivity, crosstalkSensitivity (−5.0~5.0, 기본 0). 높이면 recall↑ | 효과 수치 미공개 | 벤더 |
| 신뢰도로 검수 대상 선별 | Plaquet & Bredin (arXiv 2409.15885, Interspeech 2024): powerset 모델의 top-label confidence가 고오류 구간을 신뢰성 있게 예측. 단 Meeting·Restaurant 도메인은 차이가 덜 뚜렷. 수치는 그림에만 있음(미확인) | 정성 | 독립(pyannote 저자) |
| 오디오 샘플레이트·라우드니스 정규화 | 2025–2026 독립 효과 크기 근거 못 찾음 | 미확인 | |

---

## 5. 한국어 평가 근거 (2025–2026)

| 출처 | 내용 | 한계 |
|---|---|---|
| MLC-SLM 2025 baseline repo (github.com/mubingshen/MLC-SLM-Baseline) | 3D-Speaker 기반 한국어 dev DER 23.25(겹침 제외) / 25.45(포함). 15개 언어 평균 16.44 / 17.16. 한국어는 일본어(26.46) 다음으로 나쁨. 한국어 tcpCER 59.55 / 78.68 | baseline 하나. 원인 분석 없음. 2인·조용한 실내·휴대폰 |
| DKU 시스템 (arXiv 2507.09499) | 한국어 dev: baseline 59.55 → MS-ASR 27.04 → 언어별 어댑터 24.95. diarization 전단 오프라인 DER 14.27(전 언어 dev) | 표 머리글은 tcpWER로 표기되었으나 대회 규정상 한국어는 tcpCER. 한국어 DER 별도 미보고 |
| MLC-SLM 2026 | 한국어 포함, tcpCER 평가 | 언어별 수치 미공개 |
| 한국어 유아 발음 평가 (arXiv 2606.10213, 2026-06-08) | 한국어 유아+보호자 53 녹음, NeMo SortFormer 화자 수 정확도 88.69%, DER 33.04% | 도메인 불일치. pyannote·SpeechBrain 수치는 100% 초과로 보고되어 신뢰 어려움 |
| 리턴제로·액션파워·클로바노트 | 2025–2026 화자분리 기술 성능 공개 글 찾지 못함 | 미확인. 클로바노트 사용자 게시글에 "비슷한 목소리·같은 성별이면 뭉친다"는 비공식 보고만 있음 |
| AI Hub 회의 음성 기반 KCI 논문 | 찾지 못함 | 미확인 |

**결론:** 한국어 다자 회의(3명 이상, 단일 마이크) diarization 공개 벤치마크는 2025–2026 범위에서 확인되지 않았다. 의사결정은 자체 한국어 골드셋 없이는 근거가 없다.

---

## 6. Soniox + pyannote 단어 병합 파이프라인에 대한 함의

현재 DAMA 상태(코드 확인, 2026-10-14): `model: "precision-2"`, `exclusive: true`, `turnLevelConfidence: true`, 사용자가 화자 수를 입력하면 `numSpeakers` 전달, min/max는 보내지 않음 (`/Users/gazitofu/Developer/Dama/Packages/DamaCore/Sources/DamaManaged/ManagedProcessor.swift`).

### 6.1 먼저 할 일: 붕괴가 어느 단계에서 생기는지 실측 (비용 0)
- 같은 Run의 기존 저장 결과만으로 단계별 고유 화자 수를 센다: (1) P2 `diarization`, (2) P2 `exclusiveDiarization`, (3) 병합 후 단어에 실제로 붙은 화자(예: 단어 N개 이상), (4) Soniox 자체 speaker.
- (1)에서 이미 2명이면 diarization 문제, (1)·(2)는 3명인데 (3)에서 2명이면 병합·타임스탬프 문제다. 3.1의 Transsion·Kirakosyan 근거상 대부분은 (1)이겠지만, 소수 발언자의 발화가 짧으면 exclusive 변환이나 "최대 겹침" 규칙에서 지워질 수 있다.
- 반론: numSpeakers=3을 줬는데도 "3→2"로 보이면 diarization은 3개 클러스터를 냈지만 한 클러스터가 거의 비어 있을 가능성이 크다. 이 경우 화자 수 지정은 이미 소진된 레버다.

### 6.2 화자 수 입력 정책
- 근거: 정답 화자 수는 추정이 틀린 녹음에서 DER을 7–22% 줄인다(NTT). 단 **지정 숫자가 틀리면 반대 실패(1명→2명 분할)를 강제**한다. 참석자 목록에 말하지 않은 사람이 있으면 numSpeakers가 유령 화자를 만든다.
- 제안: 사용자가 "전원 발언"을 확신할 때만 numSpeakers. 아니면 maxSpeakers=참석자 수, minSpeakers=확실히 말한 사람 수. 현재 코드는 min/max 경로가 없다.
- 실패 경로: 사용자가 화자 수를 대충 입력하면 오히려 분할 오류가 늘어난다. 입력값의 출처(확신/추정)를 Run 입력에 기록해야 비교가 된다.

### 6.3 Precision-3 비교 Run
- 근거는 벤더 수치뿐(평균 DER −10.4%, 혼동 −18.7%). 가격 동일, turnLevelConfidence 유지, frame-level `confidence`는 미지원(DAMA는 현재 사용 안 함). API enum에 `precision-3`가 있음을 2026-10-14 api-reference에서 확인.
- INV-09에 따라 새 Run으로만 비교. 화자 수 정확도는 미공개이므로 DAMA 자체 지표로 판정해야 한다.
- 반론: 한국어 근거 0, 15개 데이터셋 목록 미공개. vadSensitivity를 올리면 짧은 끼어들기 recall은 오를 수 있지만 오탐도 늘어난다(수치 미공개).

### 6.4 voiceprint는 화자 수 문제의 해법이 아니다
- 공식 문서상 분리 정확도를 올리지 않는다. 반복 참석자의 이름 붙이기와 Run 간 동일인 "제안"(음향 근거 + 신뢰도, 사용자 확인 필수)에만 쓸 수 있다. INV-09(다른 Run의 SPEAKER_00 자동 매핑 금지)와 충돌하지 않도록 자동 확정은 하지 않는다.
- 비용·기밀: 등록 음성(30초 이하) 업로드가 필요하고 결과는 24시간 후 삭제되므로 voiceprint 원본 보관 주체가 DAMA가 된다.

### 6.5 두 diarizer 불일치를 검수 신호로
- Soniox speaker와 P2 speaker는 이미 둘 다 보존 중이다. 2개로 투표하면 성능이 떨어진다는 구현체 경고가 있으므로, **단어·턴 단위 불일치 구간을 "확인 필요"로 표시**하는 용도가 근거와 규칙 모두에 맞는다. 화자 수 자체가 다르면(예: Soniox 3, P2 2) 녹음 단위 경고를 띄운다.
- 3번째 시스템을 두면 DOVER-Lap이 가능하다. 후보: pyannote community-1(호스팅 또는 로컬 pyannote.audio 4.0), Nemotron-3-Diarization(오픈 웨이트, 8명 상한, OpenMDW 1.1), DiariZen(가중치 비상업 라이선스라 제외 검토). 효과 근거는 2020년 영어 실험(−4.7%~−27%)뿐이다.
- 반론: 세 시스템이 같은 약점(비슷한 목소리)을 공유하면 다수결이 틀린 답을 굳힌다. 비용·처리시간도 늘어난다.

### 6.6 병합 정책
- 근거상 병합 정책 개선의 상한은 작다(Transsion −2.4%). 현행 "최대 겹침, 동률 → unknown"은 규칙에 맞고 유지가 맞다.
- Transsion의 "0.3초 최근접 fallback"은 성능에 도움이 됐지만 **겹침 없는 단어를 가장 가까운 화자로 채우는 것**이라 "모르는 화자는 null" 규칙과 충돌한다. 쓰려면 별도 비교 정책으로 두고 결과에 추정 표시를 남겨야 한다.
- 경계 단어 E1(분류 b)은 Soniox 단어 타임스탬프와 P2 경계의 어긋남이 원인일 수 있다. Soniox 타임스탬프 정확도의 공개 수치는 찾지 못했다(미확인). 자체 골드셋으로 경계 ±200ms 안 단어의 오귀속 비율을 따로 재면 정렬 문제의 크기를 알 수 있다.

### 6.7 평가 지표
- DER 단독 금지. 녹음 단위 SCA·과소/과다 방향, JER, tcpCER(한국어는 문자 단위), WDER, 그리고 DAMA 고유의 "A-B-A에서 B 누락/병합 건수(E2)"를 같이 본다.
- ETH 근거상 0.5초 미만 발화는 DER에서 5% 미만이라 E2 개선이 DER에 안 보인다. CSSD(arXiv 2208.08042)의 발화 단위 conversational DER 같은 지표가 E2 측정에 더 가깝다.

### 6.8 녹음 조건 안내
- 근접/원거리 차이가 21–64% DER로, 모델 세대 교체(10–28%, 벤더)와 같은 크기다. 녹음 시 마이크를 화자들 가운데 두라는 안내는 비용이 가장 작은 레버다.
- 디노이즈는 근거가 혼재하므로 diarization 입력에 기본 적용하지 않는다(녹음 원본 보존 원칙과도 일치).

---

## 7. 미확인 목록
- Soniox stt-async-v5 화자분리의 독립 수치, 화자 수 지정 파라미터 존재 여부, 단어 타임스탬프 정확도
- Precision-3의 화자 수 정확도, 언어별(한국어) 성능, 15개 데이터셋 목록
- pyannote benchmark 페이지의 차트 수치(텍스트 추출 실패)
- 한국어 다자 회의 diarization 공개 벤치마크(2025–2026)
- pyannote 계열에서 numSpeakers 고정 vs 자동의 통제 실험 수치(NTT CHiME-8은 다른 시스템)
- Kirakosyan 분류 (a)(b)(c)의 비율
- 오디오 샘플레이트·라우드니스 정규화의 diarization 효과 크기
- DiarizationLM v1과 v5 수치 차이의 원인

---

## 8. 출처 (조회일 2026-10-14)

벤치마크·리더보드
- https://arxiv.org/html/2509.26177v1 (ETH Zurich, Benchmarking Diarization Models, 2025-09-30)
- https://icml.cc/virtual/2026/77326 (ICML 2026 workshop poster)
- https://arxiv.org/html/2507.16136v2 (SDBench, Argmax, 2025-08-06)
- https://huggingface.co/pyannote/speaker-diarization-community-1 (모델카드 벤치마크, 2025-09)
- https://www.pyannote.ai/benchmark
- https://www.pyannote.ai/changelog , https://www.pyannote.ai/changelog/precision-3 , https://docs.pyannote.ai/models.md
- https://www.pyannote.ai/blog/precision-2
- https://github.com/Picovoice/speaker-diarization-benchmark
- https://www.gladia.io/product/audio-intelligence/speaker-diarization
- https://www.assemblyai.com/blog/universal-3-5-pro-async
- https://huggingface.co/nvidia/Nemotron-3-Diarization (2026-09-23)
- https://artificialanalysis.ai/speech-to-text/methodology
- https://arxiv.org/abs/2510.06961 (Open ASR Leaderboard, v4 2026-03-30)

챌린지
- https://arxiv.org/html/2501.17304v2 (NOTSOFAR-1 요약)
- https://arxiv.org/abs/2507.18161 (CHiME-7/8 DASR 리뷰)
- https://arxiv.org/abs/2407.16447 (CHiME-8 DASR)
- https://arxiv.org/html/2502.09859 (NTT CHiME-8, oracle 화자 수 비교)
- https://arxiv.org/pdf/2409.02041 (USTC NOTSOFAR-1)
- https://arxiv.org/html/2509.13785v1 (MLC-SLM 2025 요약)
- https://github.com/mubingshen/MLC-SLM-Baseline (언어별 baseline DER)
- https://arxiv.org/pdf/2507.09499 (DKU, MLC-SLM 2025)
- https://arxiv.org/html/2507.18051v1 (TEA-ASLP, MLC-SLM 2025)
- https://arxiv.org/html/2609.27514v1 (MLC-SLM 2026 요약)
- https://arxiv.org/pdf/2609.20833 (Transsion, MLC-SLM 2026)
- https://arxiv.org/pdf/2505.13971 (MISP 2025)
- https://arxiv.org/pdf/2603.02813 (DISPLACE-M)

방법론
- https://arxiv.org/pdf/2011.01997 (DOVER-Lap)
- https://pypi.org/project/dover-lap/ (2개 시스템 경고)
- https://arxiv.org/html/2510.19572v1 (VBx for EEND-VC, MSCE)
- https://arxiv.org/abs/2609.27315 (Beyond DER: speaker counting)
- https://arxiv.org/pdf/2606.08505 (relative minimum cluster size)
- https://arxiv.org/pdf/2109.02047 (ByteDance VoxSRC 2021)
- https://arxiv.org/html/2409.15885v1 (powerset 보정, Plaquet & Bredin)
- https://arxiv.org/html/2409.00151 (Speaker tagging correction, 오류 분류)
- https://arxiv.org/pdf/2203.16834 (Yu 외, 타임스탬프 정렬 오류)
- https://arxiv.org/html/2501.08421v1 (SEAL)
- https://arxiv.org/html/2401.03506v5 (DiarizationLM)
- https://arxiv.org/html/2505.10879v2 (교실 디노이즈)
- https://arxiv.org/pdf/2208.08042 (CSSD conversational DER)
- https://arxiv.org/pdf/2601.01554 (MOSS Transcribe Diarize)
- https://hal.archives-ouvertes.fr/hal-03262923 (human-in-the-loop 교정)
- https://kili-technology.com/blog/speaker-diarization-models-guide-benchmarks-and-failure-modes-2026 (2차 정리, 수치 출처 확인용)

벤더 문서
- https://docs.pyannote.ai/api-reference/diarize
- https://docs.pyannote.ai/tutorials/identification-with-voiceprints.md
- https://docs.pyannote.ai/support/faqs.md
- https://docs.pyannote.ai/tutorials/confidence-scores.md
- https://www.pyannote.ai/blog/how-diarization-models-count-speakers-(and-why-it-s-hard)
- https://www.pyannote.ai/blog/stt-orchestration
- https://soniox.com/docs/stt/concepts/speaker-diarization

한국어
- https://arxiv.org/abs/2606.10213 (한국어 유아 음성)

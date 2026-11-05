# 리서치 C2: Nemotron-3-Diarization과 단어 단위 ASR 결합 검증

- 조사일: 2026-10-14. 1차 출처만 사용(NVIDIA HF 모델 카드·블로그, NeMo 소스, FluidAudio·speech-swift 소스와 문서). 모델을 내려받거나 실행하지 않았다.
- "미확인" = 1차 출처에서 확인 못함. "추정" = 출처 사실에서 내가 계산·추론한 것.
- 결합 대상: Soniox 토큰(ms 타임스탬프) 또는 로컬 Qwen3-ASR + Qwen3-ForcedAligner(MLX).

---

## 0. 요약

1. **출력**: `[T, 8]` 화자별 활동 확률(0–1), 기본 10 ms 프레임(인코더는 80 ms, Conv1D로 8배 업샘플). 채널은 각 화자의 첫 발화 순서(arrival order). 화자별로 독립 이진화하므로 **세그먼트끼리 겹칠 수 있고, exclusive(비중첩) 출력은 없다.**
2. **장시간**: 청크 추론 + 고정 크기 화자 캐시(264 × 80 ms 프레임)로 길이 제한이 없고, 한 번 호출하는 동안 화자 ID가 파일 전체에서 유지된다. NVIDIA는 "긴 대화에서 정확도 저하 가능"이라고만 적었고, 1–2시간 녹음 평가 수치는 없다(미확인).
3. **FluidAudio**: `Nemotron3Diarizer.processComplete([Float] 16 kHz mono)`가 `(probabilities: [Float], frameCount: Int)`를 반환한다. 즉 확률을 그대로 쓸 수 있다. 세그먼트 변환 함수의 기본값은 임계 0.5(히스테리시스 없음), 최소 0.2 s. macOS 14+, Apache-2.0 코드, OpenMDW-1.1 가중치. PyTorch 대비 offline DER +0.22(9.47 vs 9.25), SCA 동일(87.5).
4. **화자 수 지정·임베딩**: NeMo, FluidAudio, speech-swift 어디에도 oracle 화자 수 강제 수단이 없다. FluidAudio `segments(numSpeakers:)`는 앞쪽 N개 채널만 읽는 파라미터라 oracle이 아니다(잘못 쓰면 늦게 등장한 화자를 버린다). 화자 임베딩도 노출되지 않는다. NVIDIA는 별도 화자 검증 모델로 채널을 신원에 매핑하라고 권고한다.
5. **단어 결합 공식 예시**: NVIDIA 블로그(2026-09-23)는 단어 중점(midpoint)에서 활성 화자가 1명이면 배정, 2명 이상이면 `"overlap/ambiguous"`, 0명이면 `"unassigned"`로 둔다. 이 규칙은 DAMA의 "모르는 화자는 null" 원칙과 같은 방향이다. FluidAudio 문서는 "단어 구간에서 활동이 가장 큰 슬롯"을 고르라고만 적었다. NeMo 구형 OfflineDiarWithASR은 전진 커서 방식이라 공백·겹침에서 오배정 위험이 있다.

---

## 1. 모델 출력과 공식 후처리

### 1.1 출력 텐서
- 형태: `[T, 8]`, 각 값은 "per-speaker activity probability in the range [0, 1]" (모델 카드).
- 활성화: NeMo `SortformerEncLabelModel.forward_infer`에서 `preds = torch.sigmoid(logits) * output_mask...`. 모델 카드의 NeMo 로딩 클래스가 `SortformerEncLabelModel`이므로 Nemotron 3도 같은 sigmoid 경로를 탄다고 판단(추정, 클래스 일치 근거).
- 프레임 해상도: 카드는 "default frame stride is 10 ms", 10 ms 배수로 변경 가능(30, 80, 240 ms 예시). 아키텍처는 10 ms Mel을 8개씩 묶어 80 ms 인코더 프레임을 만들고 Conv1D로 다시 10 ms로 업샘플한다. FluidAudio `Nemotron3Config`: `subsamplingFactor = 8`, `upsampleFactor = 8`, `outputFrameSeconds = 0.01`.
- 화자 순서: "ordering its output channels according to each speaker's first arrival in the input audio." 채널 0이 가장 먼저 말한 사람이다. 라벨은 녹음 안에서만 유효한 익명 ID다.

### 1.2 세그먼트 변환(NeMo 공식)
- `diarize()` 반환: `'begin_seconds, end_seconds, speaker_index'` 형식 문자열. `include_tensor_outputs=True`면 확률 텐서를 함께 반환.
- 변환 경로: `_diarize_output_processing` → `predlist_to_timestamps(cfg_vad_params=postprocessing_params)` → `generate_diarization_output_lines`.
- **YAML 미지정 시 기본값** (`vad_utils.PostProcessingParams`): `onset 0.5`, `offset 0.5`, `pad_onset 0.0`, `pad_offset 0.0`, `min_duration_on 0.0`, `min_duration_off 0.0`. 로그 문구: "No postprocessing YAML file has been provided. Default postprocessing configurations will be applied."
- 이진화: 화자 열마다 `binarization_vectorized`로 onset/offset 히스테리시스 적용 후 패딩, 최소 길이 필터. **화자별 루프가 독립이라 다른 화자의 세그먼트와 시간이 겹칠 수 있다.**
- Nemotron 3 전용 후처리 YAML: HF 저장소 파일 목록에 없음. NeMo 저장소에는 이전 모델용만 있다. 예: `diar_streaming_sortformer_4spk-v2_dihard3-dev.yaml` = onset 0.56, offset 1.0, pad_onset 0.063, pad_offset 0.002, min_duration_on 0.007, min_duration_off 0.151 (DIHARD3 dev 튜닝값). Nemotron 3에 그대로 쓸 수 있는지는 미확인.
- exclusive 출력: Nemotron 3 카드·NeMo 코드·FluidAudio·speech-swift 어디에도 없음. pyannote의 `exclusive_speaker_diarization`에 해당하는 기능은 직접 만들어야 한다.

### 1.3 포트별 후처리 기본값
| 구현 | 이진화 | 최소 길이 | 겹침 |
|---|---|---|---|
| NeMo 기본(YAML 없음) | onset/offset 0.5 히스테리시스 | 0 | 허용 |
| FluidAudio `Nemotron3Diarizer.segments(probabilities:frameCount:numSpeakers: = 8, threshold: = 0.5, frameSeconds: = 0.01, minDurationSeconds: = 0.2)` | 단일 임계 `> 0.5`, 히스테리시스·패딩 없음 | 0.2 s 미만 세그먼트 삭제 | 허용(화자별 독립, 시작 시각순 정렬) |
| speech-swift `SortformerConfig` 프리셋(`.nemotron3Offline` 포함) | onset 0.5, offset 0.5 | minSpeech 0.3 s, minSilence 0.15 s | 미확인 |

- 주의: FluidAudio의 0.2 s, speech-swift의 0.3 s 최소 길이는 **짧은 끼어들기를 지우는 설정**이다. DAMA 경계 2(짧은 발화를 놓쳐도 앞뒤를 합치지 않음)를 지키려면 세그먼트 함수 대신 확률을 직접 써야 한다.

---

## 2. 장시간 처리(1–2시간)

| 항목 | 내용 | 출처 |
|---|---|---|
| 최대 길이 | "With chunked inference, the maximum audio duration is not limited." | 모델 카드 |
| offline 프로필 | `CHUNK_LEN 340`, `RIGHT_CONTEXT 40`, `FIFO_LEN 40`, `SPKCACHE_LEN 264`, `UPDATE_PERIOD 300` (80 ms 단위, 지연 30.4 s) | 모델 카드, FluidAudio `Nemotron3Config.offline` 동일 |
| 화자 캐시 동작 | Arrival-Order Speaker Cache. 화자 순으로 프레임 임베딩을 저장하고, 캐시가 차면 점수 상위 M개 프레임만 남긴다. 각 화자에 최소 K 프레임을 보장하고, 무음 임베딩을 화자 블록 뒤에 둔다. FIFO에서 밀려난 프레임이 캐시 갱신 대상이 된다 | Streaming Sortformer 논문(arXiv 2507.18446, 학습 시 캐시 188 프레임·K=33/66) |
| Nemotron 3의 K 값 | 미확인 | |
| 캐시 용량 | 264 × 80 ms ≈ 21.1 s 분량 임베딩을 최대 8명이 나눠 씀 | 계산(추정) |
| 파일 전체 화자 ID 유지 | FluidAudio `processComplete`는 시작 시 `reset()` 후 Mel을 파일 전체로 한 번 계산하고, 청크 루프에서 `state`를 넘겨가며 갱신한다. 한 호출 안에서는 화자 ID가 유지된다. speech-swift `diarize`도 `while startFrame < totalMelFrames` 루프에서 `state: &state`를 넘긴다 | FluidAudio·speech-swift 소스 |
| 장시간 저하 | NVIDIA 블로그: "Accuracy can drop with ... long conversations". v2 카드: "performance may degrade on very long recordings". 정량 수치 없음 | NVIDIA 블로그 2026-09-23, v2 카드 |
| 오래 침묵한 화자가 돌아올 때 | 논문·카드 모두 언급 없음(미확인). 화자 수 붕괴·분할의 핵심 위험 지점 | |
| 학습 세그먼트 길이 | Streaming Sortformer 학습은 90 s 세그먼트. 오프라인 Sortformer가 긴 녹음에서 약한 이유를 저자가 이 불일치로 설명하고, 스트리밍은 고정 창으로 회피한다고 적음 | arXiv 2507.18446 |
| 메모리(FluidAudio) | Mel은 파일 전체 선계산. 2시간이면 약 72만 프레임 × 128 × 4 B ≈ 369 MB, 출력 확률 약 23 MB | 계산(추정) |
| ANE 장시간 실행 | 청크마다 `autoreleasepool` 필요(IOSurface 풀 고갈 방지, 소스 주석) | FluidAudio 문서·소스 |

---

## 3. Swift 통합

### 3.1 FluidAudio (권장 경로)
- 패키지: `swift-tools-version: 6.0`, **macOS 14 / iOS 17 / visionOS 2**, 외부 SPM 의존성 없음. 사전 빌드된 `NemoTextProcessing` xcframework 바이너리 타깃을 포함한다. 라이브러리 제품명 `FluidAudio`. 코드 라이선스 Apache-2.0.
- 버전: v0.17.0(2026-09-23)에서 Nemotron 3 추가. v0.17.2는 v0.17.0/0.17.1의 첫 추론 크래시를 수정했다. v0.17.4(2026-09-25)는 M3 계열에서 ANE 컴파일되도록 `monolithic/v2/`로 교체했고 첫 실행 시 1회 재다운로드한다. 최신 v0.17.7(2026-10-08). 따라서 v0.17.4 이상을 써야 한다.
- 타입·API (소스 `Sources/FluidAudio/Diarizer/Nemotron3/`):
  - `Nemotron3Config`(Sendable). 프리셋 `offline`, `low`, `veryLow`, `ultraLow`, `fast`, `efficient`, `fast24`, `fast32`, `fast128`, split·int8 변형. `preset(named:)`.
  - `Nemotron3Models.loadFromHuggingFace(config:cacheDirectory: = nil, computeUnits: = .all, progressHandler: = nil) async throws`, `Nemotron3Models.load(config:directory:computeUnits:) async throws`. 캐시 기본 경로 `~/Library/Application Support/FluidAudio/Models`.
  - `public final class Nemotron3Diarizer`, `init(config:models:)`. 문서상 thread-safe 아님(한 actor/task에 고정).
  - 배치: `processComplete(_ audio: [Float], speechMask: [Bool]? = nil) throws -> (probabilities: [Float], frameCount: Int)`. 확률은 `frames × 8` 평탄 배열, 10 ms/프레임.
  - 스트리밍: `reset()`, `appendAudio(_:)`, `processBufferedAudio() throws -> [Nemotron3ChunkResult]`, `finishStream()`. 문서는 스트리밍 결과가 `processComplete`와 프레임 단위로 같다고 적었다(max |Δ| = 0.0).
  - 출력 타입: `Nemotron3Segment { speakerIndex: Int, startSeconds: Float, endSeconds: Float }`, `Nemotron3ChunkResult { probabilities: [Float], frameCount: Int, numSpeakers: Int }`.
  - `@available` 표기는 소스에서 보이지 않음. 패키지 최소 macOS 14.
- 입력: 16 kHz mono `[Float]`. 파일 URL 입력 API는 Nemotron3 경로에서 확인 못함(CLI는 파일 입력).
- `speechMask`: 10 ms 프레임 단위 `[Bool]`. 음성 없는 청크는 모델을 건너뛰고 상태를 갱신하지 않으며 0을 출력한다. 소스 주석은 음성 구간을 약 1 s 패딩하라고 권고한다.
- 모델: HF `FluidInference/nemotron-3-diarization-coreml`. 모놀리식 프리셋 190 MB, split W8A8 95 MB. 변환 가중치도 OpenMDW-1.1(상업 가능). 게이트 여부는 문서 간 불일치: Nemotron3.md는 "NVIDIA 공개 전까지 gated, HF_TOKEN 필요", PR #883은 "public and ungated", HF 페이지에는 게이트 표시가 없다. 현재 상태는 실접속으로 확인 필요.
- 연산 장치: Nemotron3.md는 `offline`을 "GPU-only", HF 카드는 "ANE 컴파일러 한계로 offline은 ANE 미사용"이라고 적었다. split W8A8은 ANE 상주.
- PyTorch 대비 차이 (FluidInference 측정, AMI MHM 16회의, collar 0, M5 Pro):

| 프리셋 | FluidAudio DER / SCA | NVIDIA 공개 DER / SCA | 차이 |
|---|---|---|---|
| offline (30.4 s) | 9.47 / 87.5 | 9.25 / 87.5 | DER +0.22, SCA 동일 |
| low (1.04 s) | 9.75 / 75.0 | 9.48 / 81.25 | DER +0.27, SCA −6.25 |
| fast128 (10.56 s) | 9.36 / 100.0 | 해당 프로필 없음 | |

  - 확률 수준 parity: CoreML fp16 ≤ 1.9e-4. 실음성에서 NeMo 대비 프레임 일치 99.995%. 저자는 DER 차이를 fp16 vs bf16으로 설명한다.
  - W8A8은 2.56 s 창에서 화자 수 정확도를 18.8포인트 잃었다(PR 저자 보고).

### 3.2 speech-swift (soniqo)
- 패키지: `swift-tools-version: 5.10`, **macOS 15 / iOS 18**, Apache-2.0. Nemotron 3는 라이브러리 제품 `SpeechVAD` 안에 있다(`Nemotron3Diarizer.swift`, `Nemotron3CoreMLModel.swift`, `Nemotron3MLXModel.swift`).
- 패키지 선언 의존성이 무겁다: mlx-swift, mlx-swift-lm, swift-transformers, WhisperKit, Hummingbird, MCP SDK, XGrammar 등. SPM은 선언된 의존성을 모두 해석하므로 Xcode 앱에서 SpeechVAD 하나만 써도 의존성 해석·다운로드 비용이 크다(추정, SPM 일반 동작).
- API: `public final class Nemotron3Diarizer`. 문서상 `fromCoreMLPretrained()`, `fromMLXPretrained()`, `fromCoreMLDirectory(_:)`, `fromMLXDirectory(_:)`. 소스에서는 `diarize(audio: [Float], sampleRate: Int, ...) -> DiarizationResult` 확인. `DiarizedSegment { startTime, endTime, speakerId }`. **프레임 확률은 반환하지 않는다(내부 사용).** `speakerEmbeddings`는 항상 `[]`.
- 모델: `aufklarer/Nemotron-3-Diarization-100M-CoreML-INT8`(약 103 MiB), `...-MLX-INT8`. OpenMDW-1.1. 원본 대비 평균 절대 확률차 0.00046–0.00082, 0.25 임계에서 프레임·채널 결정 불일치 0.03–0.06%.
- 다국어 자체 벤치(2026-09-23, 132개 내부 녹음 12.82 h, 8개 언어, 한국어 없음, collar 0.25, 자동 화자 수): DER MLX 10.98%, CoreML 11.20%. VoxConverse 전체: MLX 17.26% · 333x · 피크 498 MB, CoreML 17.55% · 51x · 782 MB.
- 판단: 확률을 직접 받을 수 없고, macOS 15 요구와 의존성 부담이 있다. DAMA에는 FluidAudio가 더 맞다.

### 3.3 NeMo Python (참고, Apple 비대상)
- `SortformerEncLabelModel.from_pretrained("nvidia/Nemotron-3-Diarization")`. 스트리밍 파라미터는 `diar_model.sortformer_modules.chunk_len` 등으로 설정. NVIDIA 블로그는 Linux + NVIDIA GPU(Ampere/Hopper/Blackwell) 전제라고 명시한다. Apple Silicon 공식 지원은 없고 서드파티 포트만 있다.

---

## 4. 화자 수 강제와 화자 임베딩

| 질문 | 결과 |
|---|---|
| NeMo에서 화자 수 지정 | `DiarizeConfig.max_num_of_spks`는 존재하나 `_setup_diarize_dataloader`의 `num_spks` 기본값으로만 쓰인다. 추론 출력 채널은 `sortformer_modules.n_spk`로 고정되고 슬라이스하지 않는다. 화자 수 강제 효과는 확인 못함 |
| ASR 통합 스크립트 `max_num_of_spks=8` | "Maximum number of speaker streams maintained for the session", 상한일 뿐 보장 화자 수가 아님(ASR 통합 가이드) |
| FluidAudio | `segments(numSpeakers:)`는 평탄 배열에서 앞쪽 N개 채널만 읽는다. arrival order라서 N을 참석자 수로 넣으면 **늦게 등장한 화자를 통째로 버린다**. oracle 아님. `Nemotron3Config.numSpeakers = 8`은 `let` 고정 |
| speech-swift | 화자 수 입력 파라미터 없음. 화자 수는 출력 `speakerId` 집합 크기로 계산 |
| 후처리로 강제하는 방법 | 공식·문서화된 방법 없음(미확인). 출력이 [T,8] 확률이므로 채널별 총 활동량·채널 간 유사도로 병합 후보를 만드는 것은 가능하나 검증된 방법이 아니다 |
| 화자 임베딩 | Nemotron 3·Sortformer는 화자 임베딩을 내지 않는다(speech-swift 문서 명시, FluidAudio는 `state`가 private). 화자 캐시는 인코더 프레임 임베딩이라 화자 검증용이 아니다(추정) |
| NVIDIA 권고 | 익명 채널을 신원에 매핑하려면 "meeting metadata, user profiles, or separate speaker verification models"를 쓰라고 권고(블로그 2026-09-23) |
| 재식별 구현 경로 | 채널별 단독 발화 구간(다른 채널 비활성)을 잘라 별도 임베딩 모델로 추출: FluidAudio의 WeSpeaker 기반 임베딩 추출(`DiarizerManager.extractEmbedding`, `speakerDatabase`), speech-swift의 WeSpeaker ResNet34·ReDimNet2·CAM++ 엔진. Nemotron 출력과 결합한 공개 레시피는 없음(미확인) |

---

## 5. 단어 단위 ASR 결합 레시피

| 출처 | 방법 | 겹침·공백 처리 | DAMA 시사점 |
|---|---|---|---|
| **NVIDIA 블로그 "Nemotron 3 Diarization" (2026-09-23)** | Parakeet TDT 0.6B v3 `transcribe(..., timestamps=True)` 단어 타임스탬프. `diarize()` 세그먼트로 turns를 만들고 `midpoint = (start+end)/2`, `start <= midpoint < end`인 화자를 active로 판정 | active 1명이면 배정, 여러 명이면 `"overlap/ambiguous"`, 0명이면 `"unassigned"` | 그대로 DAMA의 null 정책과 맞다. 단 세그먼트는 기본 후처리(0.5) 결과이고, 블로그는 "simple heuristic"이며 겹친 목소리를 분리하지 않는다고 명시 |
| FluidAudio Nemotron3.md | 스트리밍 ASR `StreamingUnifiedAsrManager.consumeWordTimings()`와 짝지어 "단어 구간에서 활동이 가장 큰 화자 슬롯" 선택 | 겹침 처리 미기재. 활동 측정 방식(평균·합·argmax) 미기재 | 확률을 직접 쓰는 방식. 다만 항상 1명을 고르므로 null 정책과 충돌. 그대로 쓰지 말 것 |
| NeMo 구형 `OfflineDiarWithASR` (`diarization_utils.py`, ClusteringDiarizer용) | `word_ts_anchor_pos` 기본 `"start"`(옵션 `mid`, `end`), `word_ts_anchor_offset` 기본 null→0.0. 정렬된 세그먼트 목록을 **전진 커서**로 훑어 anchor가 현재 세그먼트 끝을 넘으면 한 칸 전진 | 공백에 떨어진 단어는 다음 화자에게 붙는다. 겹침은 목록 순서로 결정. 한 단어당 한 칸만 전진 | E1을 만드는 구조. 참고만 하고 채택하지 않는다 |
| NVIDIA ASR 통합 가이드 (Nemotron 3 HF) | 화자별 ASR 스트림(Multitalker Parakeet: 조건 입력, Nemotron 3.5 ASR: 마스킹). 출력은 SegLST(세그먼트 텍스트, 시간, 익명 화자) | 겹침 구간도 화자별 전사. 단어 타임스탬프 언급 없음 | 외부 ASR(Soniox, Qwen3) 결합 레시피가 아니다. 세그먼트를 잘라 단일 화자 ASR을 돌리는 방식은 "not an equivalent replacement"라고 경고 |
| NeMo-Speech.cpp CLI | `nemo-speech transcribe meeting.wav --diarize --json`로 "word-level speaker tags" | 배정 방식 미확인 | 미확인 |
| Sortformer 논문 (arXiv 2409.06656) | 화자 감독 신호를 ASR 토큰과 연결(Sort Loss) | 해당 없음 | 외부 ASR 타임스탬프 병합 방식이 아님 |

### 5.1 DAMA 결합 시 확인할 점 (판단 재료)
1. **0 길이 단어**: Qwen3-ForcedAligner의 약 13% 0 길이 타임스탬프에는 "구간 최대 활동" 방식이 정의되지 않는다. 중점 방식은 한 점(10 ms 프레임 1개)으로 동작한다. 단 한 프레임 판정이라 잡음에 민감하다(추정).
2. **세그먼트 대신 확률 사용**: FluidAudio 세그먼트 함수의 0.2 s 최소 길이는 짧은 끼어들기를 지운다. `processComplete` 확률로 단어별 판정을 직접 하는 편이 경계 2에 맞다.
3. **판정 규칙**: NVIDIA 규칙(1명=배정, 2명 이상=ambiguous, 0명=unassigned)을 확률 버전으로 옮기면 "임계를 넘는 채널이 정확히 1개일 때만 배정"이 된다. 임계값·마진은 출처 없는 초기 설계값이므로 `algorithmVersion`과 벤치마크를 함께 남겨야 한다(프로젝트 규칙 함정 9).
4. **화자 ID 범위**: 채널 번호는 Run 안에서만 유효하다(INV-09와 일치). 다른 Run이나 Soniox 자체 화자 ID와 자동 매핑하지 않는다.
5. **장시간**: 한 번의 `processComplete` 호출로 전체 파일을 처리해야 화자 ID가 유지된다. 30초 저장 청크를 따로 넣으면 안 된다(함정 5와 같은 이유).

---

## 6. 출처 (접속일 2026-10-14)

NVIDIA
- 모델 카드: https://huggingface.co/nvidia/Nemotron-3-Diarization (공개 2026-09-23)
- 파일 목록: https://huggingface.co/nvidia/Nemotron-3-Diarization/tree/main
- ASR 통합 가이드: https://huggingface.co/nvidia/Nemotron-3-Diarization/blob/main/ASR_INTEGRATION_GUIDE.md
- 평가 프로토콜: https://huggingface.co/nvidia/Nemotron-3-Diarization/blob/main/diarization_evaluation.md
- 블로그(단어 중점 배정 예시): https://huggingface.co/blog/nvidia/nemotron-diarization (2026-09-23)
- Streaming Sortformer 논문: https://arxiv.org/html/2507.18446v1 (2025-07-24)
- v2 카드: https://huggingface.co/nvidia/diar_streaming_sortformer_4spk-v2

NeMo 소스 (main 브랜치, 2026-10-14 열람)
- https://raw.githubusercontent.com/NVIDIA/NeMo/main/nemo/collections/asr/models/sortformer_diar_models.py
- https://raw.githubusercontent.com/NVIDIA/NeMo/main/nemo/collections/asr/parts/mixins/diarization.py
- https://raw.githubusercontent.com/NVIDIA/NeMo/main/nemo/collections/asr/parts/utils/vad_utils.py
- https://raw.githubusercontent.com/NVIDIA/NeMo/main/examples/speaker_tasks/diarization/conf/post_processing/diar_streaming_sortformer_4spk-v2_dihard3-dev.yaml
- https://raw.githubusercontent.com/NVIDIA/NeMo/main/nemo/collections/asr/parts/utils/diarization_utils.py
- https://raw.githubusercontent.com/NVIDIA/NeMo/main/examples/speaker_tasks/diarization/conf/inference/diar_infer_meeting.yaml

FluidAudio
- https://raw.githubusercontent.com/FluidInference/FluidAudio/main/Documentation/Diarization/Nemotron3.md
- https://raw.githubusercontent.com/FluidInference/FluidAudio/main/Sources/FluidAudio/Diarizer/Nemotron3/Nemotron3Diarizer.swift
- https://raw.githubusercontent.com/FluidInference/FluidAudio/main/Sources/FluidAudio/Diarizer/Nemotron3/Nemotron3Types.swift
- https://raw.githubusercontent.com/FluidInference/FluidAudio/main/Sources/FluidAudio/Diarizer/Nemotron3/Nemotron3Models.swift
- https://raw.githubusercontent.com/FluidInference/FluidAudio/main/Package.swift
- https://github.com/FluidInference/FluidAudio/releases (v0.17.0 09-23, v0.17.2 09-24, v0.17.4 09-25, v0.17.7 10-08)
- https://github.com/FluidInference/FluidAudio/pull/883 (2026-08-30 열림, 2026-09-23 머지)
- https://huggingface.co/FluidInference/nemotron-3-diarization-coreml

speech-swift
- https://raw.githubusercontent.com/soniqo/speech-swift/main/Package.swift
- https://raw.githubusercontent.com/soniqo/speech-swift/main/Sources/SpeechVAD/Nemotron3Diarizer.swift
- https://raw.githubusercontent.com/soniqo/speech-swift/main/Sources/SpeechVAD/SortformerConfig.swift
- https://raw.githubusercontent.com/soniqo/speech-swift/main/docs/models/nemotron3-diarization.md
- https://raw.githubusercontent.com/soniqo/speech-swift/main/docs/benchmarks/diarization.md (2026-09-23)
- https://huggingface.co/aufklarer/Nemotron-3-Diarization-100M-CoreML-INT8

2차(참고만)
- https://notes.nicolasdeville.com/ai/nemotron-diarization/ (중점 배정 서술, NVIDIA 블로그로 1차 확인함)

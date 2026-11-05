# Qwen 로컬 비교 엔진

2026-09-11 사용자 승인 구성. 앱 선택: `로컬 Qwen + Precision-2 (비교)`. 기본 엔진 자동 변경 없음. 한국어, float16, AI 교정 OFF. Qwen 전사와 정렬은 이 Mac에서 실행한다. Precision-2는 기존 동일 오디오/화자 수 결과가 있으면 재사용하고, 없으면 앱 확인 뒤 전체 음성을 전송한다. 완전 오프라인 엔진은 아니다.

## 고정 구성 및 재현 설치

Apple Silicon, Python 3.12.14. 이 Mac의 M5 Pro/48GB에서 확인했다. 최소 사양이나 다른 Mac의 속도 보증은 아니다. 앱 번들에 Python/모델은 포함하지 않는 개발용 비교 구성이다. `.build` 환경을 지우면 다시 설치해야 한다. 프로젝트를 옮긴 뒤에는 runtime JSON을 재생성하고 앱의 `엔진 연결…`에서 선택한다.

- 커뮤니티 구현: https://github.com/moona3k/mlx-qwen3-asr — `1e28932dac8e2c68b34c29f32e2be338ffc1c852`, 0.4.0.
- 모델: https://huggingface.co/Qwen/Qwen3-ASR-1.7B — `7278e1e70fe206f11671096ffdd38061171dd6e5`.
- 정렬: https://huggingface.co/Qwen/Qwen3-ForcedAligner-0.6B — `c7cbfc2048c462b0d63a45797104fc9db3ad62b7`.
- 의존성: [qwen-requirements.lock](../../scripts/qwen-requirements.lock). 한국어 soynlp 포함, 로컬 diarization 의존성/옵션 없음.

아래 명령은 repo 루트에서 새 환경을 만들 때 사용한다. 다운로드 단계에는 네트워크가 필요하며, 전사 단계는 Hugging Face offline으로 실행된다. 이미 설치한 환경을 덮어쓰기보다 별도 비교 환경을 만든다.

```sh
python3 -m pip install --target .build/qwen-bootstrap uv==0.12.13
git clone https://github.com/moona3k/mlx-qwen3-asr.git .build/qwen-source
git -C .build/qwen-source checkout --detach 1e28932dac8e2c68b34c29f32e2be338ffc1c852
UV_PYTHON_INSTALL_DIR="$PWD/.build/qwen-python" UV_CACHE_DIR="$PWD/.build/qwen-uv-cache" .build/qwen-bootstrap/bin/uv venv --python 3.12.14 .build/qwen-venv
UV_CACHE_DIR="$PWD/.build/qwen-uv-cache" .build/qwen-bootstrap/bin/uv pip install --python .build/qwen-venv/bin/python -r scripts/qwen-requirements.lock
UV_CACHE_DIR="$PWD/.build/qwen-uv-cache" .build/qwen-bootstrap/bin/uv pip install --python .build/qwen-venv/bin/python --no-deps ./.build/qwen-source
.build/qwen-venv/bin/python scripts/qwen_download.py
```

DAMA는 `.build/qwen-runtime.json`을 기본 탐색한다. 다른 경로는 `엔진 연결…`로 지정한다. 런타임 확인 후에만 새 클라우드 작업을 허용한다. 실행 중 Python/의존성 환경을 변경하지 않는다. 각 Run에 runtime JSON과 worker 코드를 복사해 재개 시 동일 입력인지 확인한다.

## 처리 계약

- 분석 WAV 16kHz mono, 전체 SHA256·frame 수 검증. 60~120초 사이 저에너지 지점에서 자르며 무음이나 샘플을 삭제하지 않는다. 이 길이는 초기 실험값이다.
- 각 청크 4,096 출력 토큰, temperature=0, 실제 context 전달. EOS 완료만 채택한다. 반복/한도 종료는 원문과 사유를 보존하고 더 짧게 2단계까지 재시도한다. 이후 실패는 완료로 표시하지 않는다.
- ASR 모델을 해제한 뒤 정렬 모델을 로드한다. 정렬용 한국어 토큰화 후 원 ASR의 문자 위치에 다시 대응한다. `H&Q`, `15.38%`, 반복 응답, 공백과 기호를 보존한다. 매핑 불일치 또는 0길이/역행/범위 초과 시간은 null로 남긴다.
- 단어가 두 화자의 경계에 걸치거나 겹말이면 최대 겹침만으로 사람을 확정하지 않는다. 원문에 없는 짧은 화자 구간은 missing_speech 장벽으로 남겨 A→B→A를 합치지 않는다. `algorithmVersion=qwen-p2-v1`.
- Precision-2 새 호출은 `transcription:false`. 같은 세션·오디오 hash·precision-2·exclusive·turnLevelConfidence·numSpeakers 요청/실제 응답이 확인된 경우만 재사용한다. 재사용 source Run ID를 입력과 Markdown에 기록한다. 새 Run의 화자 ID에 기존 사람 이름을 자동 승계하지 않는다.
- 프로세스 취소 시 SIGINT, 2초 후 필요 시 SIGKILL. 한 모델 호출 900초, 부모 진행 정지 960초는 초기 워치독값. 완료된 청크는 재개 가능하다. 과금 POST의 접수 불명확 상태를 자동 재제출하지 않는다.

## 보존 및 검증 위치

각 Run의 `qwen/`에 worker/runtime/request, 청크 원출력·정렬·실패 사유·진행 기록을 보존한다. `raw/qwen-response.json`, `raw/pyannote-response.json`, `normalized/model.json`을 별도 보존한다. 이 파일에는 실제 발언이 있으므로 Git에 넣지 않는다. 앱 Script는 기존 결과를 덮어쓰지 않는다.

진행률의 세부 청크는 private progress.json에 기록한다. 앱은 로컬 전사·정렬 단계와 경과 시간을 표시한다. 품질 검토 전에는 기본 엔진으로 승격하지 않는다. 97분 실행·수정 시간·정답 CER/E1/E2는 별도 평가 대상이다.

# pyannote.ai API 계약 · 1차 출처 실검증 기록

검증일 **2026-09-09** · 검증자 = Dama 메인 세션 · 방법 = 공식 문서 직접 조회 (계정 없음, 실호출 0건)

요금 절 갱신 **2026-09-10** · Codex 직접 공식 Billing/Pricing 조회 및 사용자 제공 계정 요금 설명 대조. Dashboard·checkout 직접 확인 및 실호출은 하지 않았다. API 계약의 최초 검증일은 위와 같다.

`ssot/design/03_ENGINE_AND_API_CONTRACT.md`는 외부 LLM이 공개 문서를 읽고 쓴 계약 초안이며, 그 패키지 자신이 "실계정 호출은 실행하지 않았다"고 밝힌다. 이 파일은 그 초안을 1차 출처와 대조한 결과다. **충돌하면 이 파일이 우선한다.**

## 1. 검증 결과 요약

| 항목 | 03 문서의 주장 | 1차 출처 대조 | 판정 |
|---|---|---|---|
| Base URL | `https://api.pyannote.ai` | OpenAPI 경로 `/v1/…`, `/v2/…` | 일치 |
| 업로드 | `POST /v1/media/input` body `{"url":"media://…"}` → 서명 PUT URL | 동일 | 일치 |
| 업로드 PUT | `Content-Type: application/octet-stream` | 동일 | 일치 |
| 작업 제출 | `POST /v1/diarize` | 동일 | 일치 |
| `model` | `precision-2` | enum `["precision-2","community-1"]`, default `precision-2` | 일치 |
| `transcriptionConfig.model` | `faster-whisper-large-v3-turbo` | enum `["parakeet-tdt-0.6b-v3","faster-whisper-large-v3-turbo"]`, default `parakeet-tdt-0.6b-v3` | 일치. 명시 설정 필요하다는 지적도 맞음 |
| `transcriptionConfig.language` | "공개 스키마에 없으므로 추측해 추가하지 말 것" | 요청 스키마에 language 필드 없음 | **맞음** |
| 화자 수 | `numSpeakers` / `minSpeakers`·`maxSpeakers` 배타 | 세 필드 모두 존재, `minimum: 1` | 일치 |
| 작업 조회 | `GET /v1/jobs/{jobId}` | 동일 | 일치 |
| status enum | `pending / created / running / succeeded / failed / canceled` | `["pending","created","succeeded","canceled","failed","running"]` | **완전 일치** |
| output 필드 | diarization · exclusiveDiarization · wordLevelTranscription · turnLevelTranscription · warning · error | 동일 | 일치 |
| segment `confidence` | 스칼라가 아니라 화자별 map | 화자 라벨 → 숫자 map (예 `{"SPEAKER_00":16,"SPEAKER_01":93}`) | **맞음. 설계의 핵심 전제 확인** |
| 결과 보관 | 완료 후 24시간 | "Job results are retained for **24 hours**" | 일치 |
| 업로드 보관 | 48시간 이내 삭제 | "automatically deleted within **48 hours**" | 일치 |
| 학습 사용 | 고객 데이터 미사용 | "We never use your audio data, outputs … to train our AI models" | 일치 |
| 처리 지역 | 기본 Any / EU 제한 옵션 | EEA 밖 허용 기본 + EEA 한정 옵션 | 일치 |
| 취소·삭제 endpoint | "확인 없이 만들어내지 말 것" | OpenAPI 경로 목록에 없음 | **맞음. 존재하지 않는다** |

**결론: 03 문서의 API 계약은 1차 출처와 어긋나지 않는다.** 아래 2·3절의 누락분만 보완하면 구현 입력으로 쓸 수 있다.

## 2. 03 문서에 없는 실재 endpoint (보완)

OpenAPI 전체 경로는 다음 10개다. 03 문서는 이 중 3개(`/v1/media/input`, `/v1/diarize`, `/v1/jobs/{jobId}`)만 다룬다.

```
POST /v1/media/input      POST /v1/media/output     GET  /v1/test
POST /v1/diarize          POST /v1/voiceprint       POST /v1/identify
GET  /v1/jobs/{jobId}     GET  /v2/jobs
POST /v1/live             GET  /v1/live/{id}
```

구현에 직접 영향이 있는 것:

- **`GET /v2/jobs` (작업 목록)**. 03 문서는 `submissionUncertain`(POST 응답 유실로 접수 여부 불명) 상태에서 "자동 재제출 금지"만 정하고 해소 경로를 두지 않았다. 작업 목록 조회로 **재제출 없이 접수 여부를 확인**할 수 있다. 02의 상태기계에서 `submissionUncertain → (목록 조회) → remotePending | queued` 전이를 검토한다. 다만 요청 해시와 목록 항목을 어떻게 대조할지는 응답 필드 실측이 필요하므로 미확정으로 둔다.
- **`GET /v1/test`**. 키 유효성 확인 경로 후보. 온보딩의 키 검증을 `POST /v1/diarize` 시도로 대신하면 과금이 발생할 수 있다. 실제 동작은 미확인.
- **`POST /v1/voiceprint` · `POST /v1/identify`**. 화자 지문 등록·식별. 01 문서가 P0 비범위로 뺀 기능이며 그 판단은 유지한다. 다만 INV-09(Run 사이 화자 자동 매핑 금지)의 근본 해법이 이 경로라는 사실은 기록해 둔다. 요금 별도(§4).
- **`POST /v1/live` · `GET /v1/live/{id}`**. 실시간 스트리밍. 01의 비범위(실시간 자막)와 일치.
- **`POST /v1/media/output`**. 용도 미확인. 결과 전달 위치 지정으로 추정되나 확인하지 않았다.

## 3. 문서로 확인되지 않는 것 (구현 전 실측 필요)

| 미확인 항목 | 상태 | 처리 |
|---|---|---|
| 서명 PUT URL의 만료 시간 | 문서에 명시 없음 | 만료를 타이머로 추정하지 않는다. PUT 실패 응답으로 판정 (03의 정책 유지) |
| PUT 요청에 Bearer 헤더를 보내는지 | 문서가 언급하지 않음 | **보내지 않는다는 것은 앱의 보안 정책이지 공급자 사양이 아니다.** 03의 서술을 그대로 유지하되 근거를 "앱 정책"으로 표시 |
| 파일 크기·길이 상한 | 문서에서 확인 못 함 | 첫 실연동에서 5~10분 샘플 1개로 확인 (03 §5 유지) |
| `GET /v2/jobs` 응답 필드 | 미확인 | 요청 해시 대조 가능 여부를 실측 후 결정 |
| rate limit 구체 수치 | 미확인 | `Retry-After` 우선 정책 유지 |
| `output.confidence` (sample-level) | `{score: array, resolution: number}` 형태 확인 | P0는 `confidence:true`를 켜지 않는다. 켤 때 이 형태로 decode |

2026-09-10 진행 UI 보완 조회: 공식 OpenAPI의 `DiarizationJob`은 `jobId/status/createdAt/updatedAt/output`을 정의하며 숫자 진행률·ETA 필드는 없다. DAMA는 실제 상태·클라이언트에서 정상 응답을 받은 시각(`ManagedRun.lastServerCheckAt`, optional)·이번 추적 경과만 표시한다. 오디오 길이 대비 처리시간 실측이 없어 예상 완료율은 산출하지 않는다. 기존 Run 파일은 새 optional 필드가 없어도 읽는다. 공급자의 `updatedAt`과 클라이언트 확인 시각을 혼동하지 않는다. 실서버 조회 없이 [공식 OpenAPI](https://docs.pyannote.ai/openapi.json)만 확인했다.

## 4. 요금 (2026-09-10 갱신)

### 공식 Billing 문서 확인

- `/diarize`에서 `transcription=true`이면 **STT Orchestration 단가만 적용**되며 diarization 결과는 추가 비용 없이 포함된다. 이전 기록의 ‘두 항목 합산 가능, €0.28/h’ 추정은 폐기한다.
- batch 작업은 `succeeded`만 과금한다. 제출 거절·실패·취소 상태는 비과금이다. 취소 상태 설명이 취소 API의 존재나 로컬 추적 중단의 환불을 뜻하지는 않는다.
- `/diarize`·`/identify`는 처리 음성의 초 단위, 최소 20초 과금이다. `/live`도 최소 20초이며 종료 방식과 무관하게 성공적으로 처리한 음성 길이에 과금한다. DAMA는 live를 사용하지 않는다.
- Developer/Starter에는 월 포함 사용량이 있고 소진 후 같은 단가로 초과분을 청구한다. **계정의 정확한 단가·플랜 조건은 Dashboard Plans가 정본**이다. [공식 Billing](https://docs.pyannote.ai/administration/billing)

### 사용자 계정 참고값과 미확인 사항

| 항목 | 사용자 제공 설명의 USD 값 | 검증 수준 |
|---|---|---|
| Developer | US$19/월 | 사용자 전달값, 이번 세션에서 checkout 직접 열람 안 함 |
| STT Orchestration Precision | US$0.000055/s = US$0.198/h | 사용자 전달 단가·시간당 산술 환산 |
| 월 포함 크레딧 | 액수 미확인 | US$19라고 확정하지 않음 |

US$19 크레딧이 실제 포함되고 전부 이 서비스에 쓰인다는 조건이면 약 95.96시간이다. 이는 사용량 환산이며 세금·환율 등을 포함한 실제 청구 보장이 아니다. 성공한 작업별 참고 계산은 `max(음성 초, 20) × 계정의 초당 단가`; 이를 월정액에 무조건 더하지 않는다. 포함 크레딧 차감 뒤 초과분만 별도다.

공개 Pricing은 현재 Developer €19/월·€19 사용 크레딧, STT Orchestration €0.168/h를 표시하지만 이 EUR 값을 사용자 USD 계정에 대입하지 않는다. 지역별 통화 차이가 발생한 이유는 확인하지 않았다. [공개 Pricing](https://www.pyannote.ai/pricing)

### DAMA 적용

- 현재 managed `precision-2` + `transcription=true` + `faster-whisper-large-v3-turbo` 경로 유지. 중간 폴더·다른 서비스 모드·로컬 WhisperKit은 이번 참고자료 수령만으로 추가하지 않는다.
- App/UI 및 Packages/DamaCore/Sources 검색에서 고정 과금 단가 없음. 가격·크레딧·계정 한도는 처리 로직에 하드코딩하지 않는다(03 §5 유지).
- 추후 로컬 STT 경로는 비용 절약만으로 채택하지 않고 한국어 화자 경계·원문 보존 성능 비교와 별도 승인으로 판단한다.
- 사용자 실사용 검증 중 앱 코드·실행 프로세스 변경 없음. 비용 수용은 실제 음성 업로드·유료 호출의 건별 승인을 대체하지 않는다.
- 트라이얼 한도를 P0 검증 예산으로 가정하지 않는다.

## 5. 출처

| 확인 대상 | URL |
|---|---|
| 전체 경로·요청/응답 스키마·enum | https://docs.pyannote.ai/openapi.json |
| 통합 전사, 기본 STT 모델, 응답 형태 | https://docs.pyannote.ai/tutorials/speech-to-text-diarization |
| 업로드 흐름, `media://` 형식 | https://docs.pyannote.ai/tutorials/how-to-upload-files |
| 보관 기간·학습 사용·처리 지역 | https://docs.pyannote.ai/data-retention |
| 요금 | https://www.pyannote.ai/pricing |
| 과금·포함 사용량·최소 과금·계정별 가격 정본 | https://docs.pyannote.ai/administration/billing |

## 6. 이 문서가 보장하지 않는 것

공개 문서와 OpenAPI 스키마를 읽은 결과일 뿐이다. 실계정 인증, 실제 응답 바이트, 한국어 화자 분리 정확도, 계정별 한도, 청구 실적은 **전부 미검증**이다. `/build` 단계에서 사용자 키와 전송 승인을 받은 뒤 별도로 실측하고 이 문서에 부칙 1줄로 갱신한다.

---

부칙: 2026-09-09 최초 작성 (Dama 문서 정리 세션 · 외부 설계 패키지 채택 검증).

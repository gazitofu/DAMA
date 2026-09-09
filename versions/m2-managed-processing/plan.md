---
unit: m2-managed-processing
branch: work/m0-fixture-review
status: building
decisions_resolved: true
resume: "T-01–03 구현·Core+managed 71건·Debug build PASS. 실제 마이크와 키체인/API는 미측정. 사용자 파일 경로를 받은 뒤 짧은 구간을 정하고 실전송·유료 호출을 건별 확인."
spec: notes/review-workspace/review-workspace.src.html
created: 2026-09-09
updated: 2026-09-09
---

## 근거·범위

- 사용자: M1 이후 M2 managed API 연결, 실음성 전송·유료 호출 실행 전 별도 확인. 키 보유를 전송 승인으로 해석하지 않음.
- M1 plan·DamaAudio 실물, M0 FileSessionRepository·TranscriptEditingSession·ReviewWorkspace. M0 기본 여정 재검사 없음; M1 실기기 미측정은 유지.
- 기존 closed 스펙 §02 동의·키·처리 상태와 §03 UI, `ssot/design/{00,02,03,04,05,06,07}`, 계약 Swift·schema, `ssot/api/pyannote-verified.md`, `ssot/dev.md`, plan/build/spec 및 M1에서 읽은 공통 규율 재사용.
- 2026-09-09 [공식 OpenAPI](https://docs.pyannote.ai/openapi.json)와 [upload](https://docs.pyannote.ai/tutorials/how-to-upload-files), [통합 전사](https://docs.pyannote.ai/tutorials/speech-to-text-diarization) 재조회. 필수 API·model·word/confidence map 계약 일치. 새 언어 요청 필드 추가 없음.
- 같은 branch, 기존 3개 혼합 문서 존치. 새 `DamaManaged` target은 HTTP·Keychain·Audio 의존, Core에는 Foundation normalizer와 기존 repository managed 반입만 추가. App/UI·Package/Xcode·entitlement network.client·README 변경 허용.
- 실제 API 호출, 음성 전송, 키 원문 읽기/로그, 서버 취소·삭제, WhisperKit, 시스템 오디오, 서명·배포 제외.

## 구현 계약·단위

- 기본 매번 확인. 녹음별 로컬 저장만 우선. 초기 제품은 건별 확인 경로로 연결하며 자동 전송 설정·재처리 UI는 후속으로 명시한다. 키는 Keychain com.gazitofu.Dama.pyannote, UserDefaults·파일·로그 금지. 저장=연결 검증 아님.
- `POST /v1/media/input` → HTTPS signed PUT (별도 URLSession, Bearer 없음, redirect 거부) → `POST /v1/diarize` precision-2/exclusive/turnLevelConfidence/transcription/faster-whisper-large-v3-turbo 명시 → GET 같은 jobId.
- 파일 업로드는 fromFile 스트리밍. request에는 media key만, 키/서명 URL 저장 금지. submitting 전 attempt UUID·요청 SHA256 저장; 응답 jobId 즉시 저장. response 불명·timeout·5xx는 submissionUncertain, 재시작도 자동 재제출 없음.
- 400 failed, 401/403 credentials, 402 billing, 429 waiting; GET 5xx/network는 같은 jobId로 제한 재시도. Retry-After 초·HTTP-date 우선. polling 10초→최대60초±20%는 기존 초기 설계값. 모르는 원격 status는 원값 보존하고 중단·안내.
- 성공 raw bytes 먼저 immutable 저장, 그 다음 DTO decode·normalize·repository model/revision. parsing 실패도 raw 유지. words 없는 성공은 partialResult로 멈춤, sentence fallback 금지.
- 공급자 초 Double→유효성·범위 검사→Int64 µs 1회. 0.85초=850000µs. 잘못된 word timestamp는 null 2개. 화자 ID는 Run별 새 mapping, provider label 보존, 알려지지 않은 화자는 null. prefix는 원문 선행 공백을 보존하고 없으면 표시용 공백 별도 기록.
- 일반·exclusive interval과 confidence map 보존, 실제 서로 다른 화자의 양의 시간 겹침만 overlap. P0는 공급자 귀속을 P1 기준으로 덮지 않음. missing marker 길이 제한 삭제 없음; 150ms warning/미만 info, Turn gap 300ms 초기값. A→짧은 B→A 장벽, 원문 반복 유지. algorithmVersion=managed-v1.
- 새 Run/model/revision 불변; 기존 활성 수정본이 있는 경우 자동 교체하지 않음. 초기 실제 결과 없는 세션만 검수 연결. 재처리/Run 전환 UI는 별도 후속.

## AC·태스크·QA

- [x] AC-01 키·동의: 키 파일 저장 없음, 전송 동의 없거나 never 정책이면 HTTP 0; 녹음 독립. Keychain 실접근은 사용자 설정 동작에서만.
- [x] AC-02 HTTP mock 여정: upload→submit→poll→raw→normalized. PUT auth 없음·redirect 거부. 400/401/402/429/5xx·접수 불명·같은 jobId GET·재실행 state·중복 click 차단.
- [x] AC-03 normalizer: RC-01/03/04/05/07/08/09/11/12/14/16, INV-01–10; 단어 보존, 140ms marker, A 재병합 방지, map/null, zero/bad time, boundary와 overlap 구분. 기존 fixture와 메모리 변형.
- [x] AC-04 저장/검수: 실제 raw bytes 불변 설치→model/revision→기존 editor open; source hash와 기존 수정본 유지. 네트워크/키/원문 로그 없음.
- [x] AC-05 앱: 키 입력·동의 창·로컬 저장만·처리 상태·ready 검수 연결, Swift 6 tests/Debug build. 앱 실음성 조작과 별도.
- [ ] AC-06 실연동: 사용자 확인한 짧은 파일 업로드·비용·계정 제한·한국어 결과 검수. 승인 전 미실행 유지.

T-01 Core normalizer·repository; T-02 영속 processing + HTTP adapter/mock; T-03 Keychain·동의·UI 연결; T-04 변경 검산·README·AC 갱신.
QA는 ① mock 전송→저장→검수 ② 앱 설정→건별 동의→처리→검수의 2묶음. 수정 후 영향 축만 재검사. 키 없음·실전송 보류는 구현 중단 사유 아님.

## Follow-ups·막힘

- 사용자 90분 파일 경로 요청 중. 파일 경로·실측·사용할 짧은 구간을 정한 뒤 전송/유료 호출 건별 확인.
- M1 10분·장기·접근성, M0 미측정 UI는 기존 plan에 유지. 원음 seek·재생·Run 전환·자동 전송·화자 수 설정 확장·삭제·release gate는 m2-review-release 후속. 이 단계에서 미지원 컨트롤을 만들지 않음.

## 검증·현재 제한 (2026-09-09)

- T-01–03 직접 구현. 하위 Codex·서브에이전트 없음. M1 `d989895`, 앱 연결 `7ca0075` 로컬 커밋. 원격 없음.
- `ManagedJourneyTests` 8건 + 변경 영향을 받는 기존 Core 63건 = 71건 PASS, `.build/check-logs/m2-core-managed-final.log`. 샌드박스 내부 실행, Swift 6.3.3. 필터 `ManagedJourneyTests|DamaCoreTests`; module/cache/config/security 경로는 check.sh와 같은 `.build/`.
- 검산 축: 140ms marker·4개 원문·3 Turns, map/null, invalid time·unknown·반복 ‘네’, duplicate interval과 실제 동시발화/순차 경계 분리. 기존 수정 이름·revision을 둔 뒤 새 Run 반입해 이전 active와 raw가 불변임을 확인.
- HTTP는 actor transport mock으로 upload/submit/poll·400/401/402/429/503·timeout·GET 3회 같은 jobId·POST 1회·재시작 uncertain을 확인. URLProtocol은 실제 URLSession의 API auth/401 경로, PUT 요청의 auth 부재 및 redirect delegate 거부를 확인. 실제 서버·signed PUT 응답은 미측정이다.
- 명시적 동의 없거나 never이면 transport 호출 0; 키 없으면 consent를 유지한 waitingForCredentials, 키 준비 뒤 같은 Run을 재개. Keychain 코드는 compile 확인이며 실제 저장·조회·삭제는 미실행이다.
- raw 설치 초기에 Foundation의 atomic+withoutOverwriting 조합이 fatal인 것을 확인해, 같은 폴더 임시 파일→exclusive hard link로 교정했다. 재시작 파일 열거 URL은 standardization 후 symlink 검증한다. 실패 검사를 삭제·완화하지 않았다.
- M2 앱 초기/최종 Debug compile PASS. 키 없음의 동의 보존 수정 뒤 앱 compile만 재실행했다. `.build/check-logs/m2-xcodebuild.log`, `BUILD SUCCEEDED`. 서명 없음, 기존 SDK target/AppIntents 경고 유지. Info.plist·entitlement·project plutil 검사 PASS.
- 계약 29건·Swift 계약 smoke·nullable 왕복·파생물 SHA256 일치. 새로운 모델 임계값의 정확도 benchmark는 없고 초기값을 유지한다. `language=und`는 공급자 언어 응답 부재 표시이며 한국어 고정 전사 요청을 추가한 것이 아니다.
- **AC-01–05 체크는 구현·합성/mock·compile 층위다.** 실제 앱 키 입력·동의/전송·마이크·한국어 품질은 미측정이며 AC-06 미체크, status building 유지.
- 재시작 후 알려진 jobId는 패널에서 조회 재개. 접수 불명·최종 실패·부분 결과의 새 Run 재제출 UI와 자동 재개는 후속. 기존 기록을 다시 보내는 우회 버튼을 만들지 않았다. 원음 검수와 종합 release gate는 아직 끝나지 않았다.
- 다음 실행에 필요한 사용자 입력은 실제 파일 경로와 짧은 평가 구간이며, 전송/유료 호출은 그 파일·구간을 제시한 뒤 별도로 확인한다. 실제 파일·키를 아직 읽지 않았다.

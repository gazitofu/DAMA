# 백엔드 전수 검수와 공통 문단 분절 진단

2026-09-11 · 기준 HEAD `fb08330` · `work/m0-fixture-review` · 제품 코드 변경 없음.

기존 공통 읽기 규칙은 실제 화면과 Markdown에서 작동한다. 결합본의 과분절은 주로 화자 미확정 증가에서 발생한다. 별도로 **분리된 종결 구두점 때문에 완성 문장을 붙여 읽는 결함**을 재현했다. 녹음과 로컬 추론이 겹치는 수명주기, 손상 파일의 영향 범위, 화면에서 반복되는 문단 계산을 다음 소규모 수정 대상으로 정한다. 전면 재작성의 근거는 없다.

상태는 [backend-audit plan](../../versions/backend-audit/plan.md), 요청·후속 범위는 [operating-baseline 다음 세션 착수](../../versions/operating-baseline/plan.md)에 둔다. 이 문서는 해당 작업의 검수 증거다.

## 1. 모집단·방법·검증 경계

[파일별 모집단](inventory.md)은 82파일이다. App 8, UI 연결 5, Core 18, Audio 8, Managed 7, 테스트 18, 기존 scripts 9, 계약·프로젝트 설정 9개를 경로·줄 수·SHA-256으로 고정했다. UI 디자인·아이콘 비트맵은 제외하고 데이터 소비·빌드 연결만 확인했다. 새 진단 도구 2개는 별도 산출물이다.

구현은 호출 경로와 상태·실패 분기를 검수했다. 테스트는 사례 목록과 주요 보존/경계 assertion을 대조하고 전체 실행했다. 모든 테스트 assertion을 독립 재증명했다는 의미는 아니다. 실기기 동시 녹음/추론, 프레임 지연, 공급자 실호출, 실제 음성의 E1/E2 정답·능동 수정시간은 이번에 측정하지 않았다.

적용 기준은 plan에 기록한 홈·도메인·프로젝트 규칙, spec/plan/build 절차, 설계02·03·04, 운영/LibraryScript/직렬화 계약이다. Qwen 기존 plan·runtime·evaluation과 comparative-evaluation의 집계/결론, 사용자 학습 지침을 확인했다. 기존 0길이 정렬 관측을 새 원응답 재측정으로 확인했으며, 학습 지침의 기술·약관 제안을 이번 검수 결과로 승계하지 않는다.

## 2. 데이터 흐름과 유지할 책임

| 단계·소유자 | 확인한 경계 | 유지/후속 |
|---|---|---|
| RecordingWorkspace → MicrophoneCapture → CaptureBufferPool/CaptureWriter | callback은 확보된 버퍼를 큐에 넘기고 저장은 writer가 담당. 순서/overflow 오류는 중단·복구 상태로 남김. AudioLibrary가 원본 보존과 analysis 파생을 분리 | callback을 모델/네트워크 조정자에 흡수하지 않음. 동시 추론·종료 정책은 F-01 |
| LibraryWorkspace/FolderLibraryStore | 외부 Speeches/Scripts, 내부 원본·분석·revision을 구분. 북마크·선택 폴더와 변경 hash, 휴지통 확인·연결 원본 보존 | actor I/O 유지. 파일별 실패 격리는 F-04 |
| ProcessingWorkspace → ManagedProcessor | 사용자 확인·키체인은 앱, Run 상태·요청 스냅샷·원응답은 processor. 완료 Soniox source는 parent 결합 실패와 별도로 저장/열기 | 운영 parent 조정과 provider transport 경계 유지. 파일500ms 스캔은 향후 실제 부하 기준 최적화 |
| Soniox/Pyannote transport, QwenRunner | 공급자 인증과 서명 PUT을 구분. 불명 POST는 submissionUncertain, 동일 요청 자동 재제출 없음. GET/기존 job 재개와 완료 소스 재사용 분리 | 서버 취소를 로컬 정지로 오인하지 않음. Qwen 실제 runtime 동일성은 F-05 |
| Provider normalizer → TranscriptDocument | 원 ASR·시간·후보 화자·confidence와 최종 배정을 분리. null/겹말/경계/누락 marker를 보존. source run 간 화자 ID 자동 동일시 없음 | 공급자별 토큰 해석 유지. 중복 근거 계산만 F-06 |
| FileSessionRepository / TranscriptEditing | 모델·raw 불변 저장, revision chain·active pointer 복구, stale base/변조 거부. 사용자 편집·undo와 모델 시간 분리 | 내부 normalized 저장과 외부 LibraryScript 저장은 계약이 달라 무리하게 통합하지 않음 |
| LibraryScript → blocks → LibraryShell/Markdown | 원 Turn/word 보존 위에 표시 이름·텍스트·문단 경계를 적용. 수정 저장은 expectedHash로 외부 변경 검사 | 읽기 판정 F-02, 재계산 F-03. null을 이름으로 추정하지 않음 |
| CorrectionWorkspace / ScriptCorrection·Spans·Terms | 녹음별 전송 동의, source anchor 검증, 교정과 사람 수정 병합, 원문 보존. 평가 기록의 audioChecked/시간/비용 nil 분리 | 교정·품질 평가·학습 정답을 동일시하지 않음 |

키·로그 검수: 키는 provider별 Keychain, 오디오 callback에는 키/네트워크가 없다. transport 오류는 분류형으로 전달하며 worker의 최종 오류는 종류만 출력한다. 음성·원문·문맥은 의도된 raw/request/result 파일에 로컬 보존된다. 이를 일반 로그·Git 자료로 취급하지 않는다. worker가 사용하는 외부 라이브러리 자체의 모든 stdout을 감사한 것은 아니므로 자식 프로세스 로그의 절대적 무유출을 보증하지 않는다.

## 3. 우선순위별 결과

P1은 다음 기능 확장 전 수정·검증할 항목, P2는 순차 정리할 항목이다. 아래 정적 발견을 실기기 장애 재현으로 표현하지 않는다.

### F-01 · P1 · 녹음/로컬 추론의 동시 실행과 종료 조합

**정적 호출 경로 확인.** [AppLifecycle.swift](../../App/AppLifecycle.swift) L25–44는 녹음 중 저장 종료를 선택하면 capture.stop 후 즉시 terminate reply를 보낸다. 뒤의 localInferenceActive → pauseAndWait 분기에 도달하지 않는다. [RecordingWorkspace.swift](../../App/RecordingWorkspace.swift)의 녹음 시작은 Qwen 실행을 막지 않으며, [LibraryWorkspace.swift](../../App/LibraryWorkspace.swift) L241 convert와 [ProcessingWorkspace.swift](../../App/ProcessingWorkspace.swift)의 reviewTransmission/resume에도 capture busy 검사가 없다. canRetranscribe의 녹음 검사는 다른 진입점이다.

따라서 Qwen 실행→녹음 시작→저장 종료 조합에서 자식 추론의 정지 대기가 생략될 수 있다. 실제 원본 손실·자식 잔류는 미재현이다. 수정은 녹음 저장과 로컬 작업 정지를 하나의 종료 절차로 합치고, 새 로컬 추론/재개는 녹음 중 대기시키는 방향이다. 이미 실행 중인 추론은 녹음 우선으로 checkpoint를 보존하며 정지하는 정책을 구체화한다. 회귀 검증은 녹음 저장 실패 시 종료 거부, Qwen 단독 취소, 동시 상태의 자식 종료·원본 재열기다. cloud job까지 취소됐다고 표시하면 안 된다.

### F-02 · P1 · 토큰 단위 종결 구두점의 문장 경계 누락

**합성 입력으로 재현.** [LibraryPresentation.swift](../../Packages/DamaCore/Sources/DamaCore/LibraryPresentation.swift) L151 이후 mayJoin은 누적 문단이 아니라 직전 underlying Turn의 text만 completesReadingSentence에 넘긴다. Soniox+P2는 토큰마다 Turn을 만든다. 같은 A의 `완료했습니다.` / ` 다음입니다.`는 2문단인데, 같은 문자·같은 화자의 `완료했습니다` / `.` / ` 다음입니다` / `.`는 1문단이다. 양수 시간·연속 A 구간을 사용해 null/marker 영향과 분리했다.

실제 결합본에는 현재 규칙이 합친 경계 중 누적 텍스트로 보면 종결인 후보가 84개 있다. **84개가 사람 검수로 확정된 오류라는 뜻은 아니다.** 누적 문장 기반 판정과 닫는 따옴표·소수점·말줄임표를 함께 검사해야 한다. 수정은 reading policy 버전을 올리고 UI/Markdown에 공통 적용한다. 원 word·시간·화자/Turn은 그대로 둔다. A→짧은 B→A, null, 누락, manual split/join, AI/사람 수정이 우선하는 순서를 유지한다. 이 결함은 과도한 병합이며 아래 주된 과분절 원인과 별개다.

### F-03 · P2 · 재생 tick과 전체 읽기 계산의 결합

**정적 호출 경로 + 함수 단회 계측.** [LibraryShell.swift](../../UI/LibraryShell.swift) L200에서 playback 전체를 관찰하고 L537에서 body 안에 file.script.blocks()를 호출한다. [SegmentPlayback.swift](../../Packages/DamaCore/Sources/DamaAudio/SegmentPlayback.swift)는 약30ms마다 위치를 publish한다. 이 구조는 위치 변화로 전체 문단 계산이 반복될 가능성이 있다. 실제 SwiftUI body 실행 빈도·프레임 지연은 미측정이다.

처음 최적화 컴파일 단회 blocks는 결합본 약68ms였다. 기존 plan의 Debug 약444ms와 컴파일 조건이 달라 개선율 비교에 쓰지 않는다. 표시 내용의 revision/AI표시/수동 경계를 키로 문단 snapshot을 재사용하고 재생 위치 관찰을 좁히는 것이 다음 안이다. 캐시가 오래된 수정본을 표시하지 않는 회귀 검사가 필요하다. 추가로 LibraryWorkspace.exportEvaluation L390의 hash·검증/encoding·write가 MainActor Task 안에 있으므로 저장 actor로 옮길 후보다. 파일 크기별 실제 UI 지연은 미측정이다.

### F-04 · P2 · 손상 파일 하나가 정상 목록·새 저장까지 막음

후속 완료 (2026-09-12): [storage-isolation](../../versions/storage-isolation/plan.md),0.4.6(16). 파일별 실패 표시/정상 파일 조회, 중복 ID 전부 제외, 해당 session의 불완전한 이력 제출 차단을 구현·검증했다. 아래는 발견 당시 근거다.

**정적 오류 전파 확인.** [FolderLibraryStore.swift](../../Packages/DamaCore/Sources/DamaAudio/FolderLibraryStore.swift) L124 scripts는 각 파일 decode/validate 실패를 전체 throw로 올린다. createScript/saveCorrection도 전체 scripts 조회에 의존한다. LibraryWorkspace.refresh L126은 Speeches→Scripts를 하나의 do에서 실행해 잘못된 음성 하나가 Scripts 갱신도 막을 수 있다. 첫 실행에는 유지할 이전 목록도 없다.

[ManagedProcessor.swift](../../Packages/DamaCore/Sources/DamaManaged/ManagedProcessor.swift) L80 runs도 모든 session의 state를 읽다 한 파일에서 실패하면 전체 조회에 실패하며 begin/resume/reusable이 이 조회에 의존한다. 이 동작은 안전한 차단이지만 영향 범위가 넓다. 파일별 오류 목록과 정상 항목을 함께 반환하도록 분리하되, 손상 Run의 접수 여부를 임의로 초기화하거나 재제출하면 안 된다. 합성 임시 폴더의 정상+손상 파일, 중복 ID, symlink, stale hash, 접수 불명 복구 검증을 다음 구현에 포함한다. 이번에 실제 사용자 파일을 손상시키지 않았다.

### F-05 · P2 · Qwen runtime 스냅샷의 재현성 한계

**정적 확인.** [QwenRunner.swift](../../Packages/DamaCore/Sources/DamaManaged/QwenRunner.swift) L29–57은 모델 ID·선언된 upstreamCommit·실행파일/config 존재를 검사하고 runtime.json·worker.py를 Run에 고정한다. [qwen_worker.py](../../scripts/qwen_worker.py)는 요청+runtime+worker bytes로 checkpoint identity를 만든다. 하지만 JSON이 가리키는 Python package·모델 가중치 자체는 공유 경로이며 실제 bytes를 고정/검증하지 않는다.

현재 응답이 오염됐다는 발견은 아니다. 환경/모델 파일이 같은 경로에서 바뀌면 선언상 동일 runtime이라도 실제 실행은 달라질 수 있다는 경계다. 학습 환경 추가 전에 운영 runtime을 분리하고 실제 package/모델 manifest 검증을 설계한다. 모델을 다시 내려받거나 학습을 실행하는 것은 이번 범위가 아니다.

### F-06 · P2 · Qwen/결합 normalizer의 공통 근거 계산 중복

[QwenNormalizer.swift](../../Packages/DamaCore/Sources/DamaCore/QwenNormalizer.swift)와 [SonioxPrecisionNormalizer.swift](../../Packages/DamaCore/Sources/DamaCore/SonioxPrecisionNormalizer.swift)는 P2 interval 변환·겹말·coverage union·경계 보류·누락 marker 계산을 반복한다. 토큰 추출/원문 보존 방식은 다르다. 공통 시간 근거 계산을 순수 함수로 추출할 수 있지만 결합 경고나 원 source 필드까지 하나로 만들지 않는다. [ManagedNormalizer.swift](../../Packages/DamaCore/Sources/DamaCore/ManagedNormalizer.swift)의 별도 초기 margin/Turn 정책도 자동 통합하지 않는다.

추출 전에 세 경로 raw→normalized golden을 고정하고 전후 byte/semantic 동일성을 검사한다. 정책/임계값을 변경하는 실험과 단순 코드 이동은 별도 작업이다.

### F-07 · P2 · 기존 SwiftPM scratch에서 전체 검사 충돌

후속 완료 (2026-09-12): [storage-isolation](../../versions/storage-isolation/plan.md). check.sh 기본 독립 scratch·명시 경로 선택·실행별 실패 로그 보존, 전체160 PASS. 보존 실패 바이너리는 단일 테스트도 signal11 재현, 같은0.4.5 코드 독립 빌드 바이너리는 동일 테스트 PASS. 빌드 산출물 차이로 진단 범위를 좁혔으며 구체적인 컴파일러/캐시 결함은 미확정이다. 아래 당시 FAIL 기록은 보존한다.

check.sh가 재사용한 `.build/swiftpm`에서 ContextAudioTests 시작 직후 signal11이 재현됐다. 새 `.build/backend-audit-clean`에서는 전체145건이 통과했다. 새 경로 성공만으로 캐시 손상이 원인이라고 단정하지 않는다. 실행 스크립트에 독립 scratch 경로 선택·실패 로그 보존을 제공할 후속이 필요하다. 이번 check.sh 전체 결과는 FAIL로 남긴다.

## 4. 같은 원응답의 분절 단계별 재측정

원음은 21분53.280초, `1,313,280,000µs`. 같은 analysis SHA-256을 검증했고 Qwen/결합의 P2 응답 bytes도 같다. 세 normalizer 재실행 결과는 저장 Script의 embedded TranscriptDocument와 canonical encoding 기준 완전히 일치한다. 보관된 Script 8개와 읽은 raw/analysis 파일은 실행 전후 hash가 같다. 선택 Run은 진단 CLI 인자로 고정한다.

| 단계/값 | Soniox 자체 | Soniox+P2 | Qwen+같은 P2 |
|---|---:|---:|---:|
| 알고리즘 | soniox-v1 | soniox-p2-v2 | qwen-p2-v1 |
| 원/정렬 토큰 | 6,008 | 6,008 | 2,587 |
| lexical / punctuation | 5,135 / 873 | 5,135 / 873 | 2,587 / 0 |
| normalized 0길이 / null 시간 | 145 / 0 | 145 / 0 | 0 / 336 |
| 화자 미확정 토큰 | 0 | 662 | 566 |
| speech Turn / missing marker | 449 / 0 | 6,008 / 72 | 2,587 / 81 |
| speech 읽기 문단 | 434 | 1,123 | 1,013 |
| 1초 미만 speech 문단 | 146 | 886 | 415 |
| 구두점만인 speech 문단 | 0 | 272 | 0 |
| 화면·Markdown 전체 block | 434 | 1,195 | 1,094 |

1초 미만은 시간이 있는 speech block에서 endUs−startUs < 1,000,000이다. marker와 null시간 문단은 이 수에 포함하지 않는다. 공급자별 토큰 단위가 달라 열 간 비율은 정확도 순위가 아니다. Qwen의 punctuation=0은 구두점 문자가 없다는 뜻이 아니라 모든 정렬 항목의 tokenKind가 lexical이라는 뜻이다.

**ASR→정렬:** Soniox의 145개 0길이 원시간은 자체/결합 모두 보존된다. 이 중106개는 lexical,39개는 punctuation이므로 0길이를 모두 단순 구두점으로 처리할 수 없다. Qwen raw의19청크는 모두 EOS complete이며 저장된2,587개 정렬 항목을 worker map_alignment로 다시 매핑했다. 336개 모두 start_time==end_time여서 null로 채택됐고, 나머지2,251개는 유효했다. 텍스트 불일치·역행·chunk 범위 초과는 이 raw에서0개다. 매핑된 word 배열·원문 연결이 저장본과 완전히 같다. 이는 upstream 후처리 이후 값이므로 모델의 시간 예측과 timestamp repair 기여는 기존 자료로 분리할 수 없다. EOS는 음성 내용 누락이 없다는 보장이 아니다.

**정렬→배정:** null 화자의 배타적 1차 이유는 다음과 같다. 코드의 우선순위대로 시간→겹말→경계→coverage/공급자 없음으로 분류하므로 중복 issue 건수와 다르다.

| null 원인 | 결합 | Qwen |
|---|---:|---:|
| 0길이 lexical / punctuation | 106 / 39 | 0 / 0 |
| null 시간 | 0 | 336 |
| 겹말 | 294 | 161 |
| 다른 화자 경계 | 27 | 37 |
| coverage 부족 또는 P2 후보 없음 | 196 | 32 |
| 합계 | 662 | 566 |

**Turn→문단:** 모든 인접 Turn 경계에서 첫 차단 이유를 기록하고 실제 blocks의 시작 ID와 전부 대조했다. `joined`는 병합 성공이며 다른 열은 차단 이유다. 한 null이 앞뒤 두 경계에 영향을 줄 수 있으므로 null 토큰 수와 같지 않다.

| 인접 경계 1차 이유 | Soniox | 결합 | Qwen |
|---|---:|---:|---:|
| joined | 15 | 4,885 | 1,574 |
| missing marker | 0 | 127 | 138 |
| unknown speaker | 0 | 961 | 814 |
| known speaker change | 272 | 72 | 72 |
| sentence end | 161 | 34 | 69 |
| 합계 (= 전체 Turn−1) | 448 | 6,079 | 2,667 |

분리된 구두점과 미확정 토큰의 표시를 개선할 여지는 있지만, null 장벽을 없애거나 가장 가까운 화자로 채워 문단 수만 줄이는 수정은 계약 위반이다. 합성 same-A 미완성은1문단, 짧은 B가 낀 ABA는3문단, 누락 B는 speech/marker/speech, 수동 split은2문단으로 확인했다. 기존 LibraryPresentationTests의 null·역행 시간·사람 수정 장벽 검사도 통과했다. 선택 실제3본은 이름/텍스트 override·수동 문단 경계·legacy humanEdited가 모두0이다. 결합본의 reviewRecords 1건은 기존 동작 확인 메모이며 정확도 표본이 아니다.

**문단→소비:** App/DamaApp와 StatusBarController의 현행 창은 LibraryShell이다. LibraryShell과 LibraryScript.markdown은 모두 blocks()를 사용하고 실제 block 수·Turn/word 순서가 일치했다. 옛 ReviewShell은 underlying turns, 호환 TXT exporter도 turns를 사용하지만 현행 UI의 생성 호출 경로는 없다. library-script 계약상 JSON/TXT는 호환 경로로 남아 있다. 이를 활성 화면 과분절의 원인으로 분류하지 않는다. 추후 다시 노출한다면 공통 정책 또는 명시적 원구조 export 구분을 먼저 정해야 한다.

## 5. 실행 결과와 재현

- `bash scripts/check.sh`: 계약 Python30건, contract 사본 일치, Swift roundtrip, xcodebuild Debug PASS. 기존 scratch 전체 테스트 signal11로 **전체 backpressure FAIL**. `.build/check-logs/backend-audit-check.log`, `backend-audit-stale-cache-tests.log` 보존.
- 동일 소스에서 새 scratch `.build/backend-audit-clean` 전체 **145건 PASS / 0 failures**. `.build/check-logs/backend-audit-clean-tests.log`. macOS 오디오 테스트는 sandbox 밖에서 실행. 합성 오디오/transport 테스트이며 실제 화자 정확도 검증이 아니다.
- `.build/qwen-venv/bin/python scripts/test_qwen_worker.py`: **4건 PASS**, `.build/check-logs/backend-audit-qwen-worker.log`. 모델·네트워크 실행 없음.
- [diagnose-reading.swift](../../scripts/diagnose-reading.swift): Swift6 최적화 컴파일, 저장3본 재구성·hash·화면/Markdown 계측 대조·6개 합성 사례 성공. 구두점 사례의1문단은 결함 재현 성공이지 정책 합격이 아니다. 최초 합성 입력은 구두점만인 P2 구간을 만들어 누락 marker가 개입했으므로 연속 A 구간으로 고쳐 격리했다.
- [diagnose-qwen-alignment.py](../../scripts/diagnose-qwen-alignment.py): 저장 정렬 재매핑·원문 동일·input hash 불변 확인. 새 output만 생성하고 기존 output 덮어쓰기를 거부한다.

로컬 증거는 `.build/diagnostics/backend-audit/reading-final.json`, `qwen-alignment-final.json`이다. 입력 경로·해시 manifest는 ignored에 두고 원문을 Git 산출물에 복제하지 않았다. 집계의 근거 Run은 Soniox `1FEB45DB-D609-491D-B6FA-ADE188883C67`, 결합 `DF6F46D1-D574-4493-8CA9-C7289F94EB92`, Qwen `5E0B2593-549B-48BC-9AED-A5C94B809B8C`이다.

```sh
swiftc -O -swift-version 6 -module-cache-path .build/modulecache -parse-as-library Packages/DamaCore/Sources/DamaCore/*.swift scripts/diagnose-reading.swift -o .build/diagnostics/backend-audit/diagnose-reading
.build/diagnostics/backend-audit/diagnose-reading /Users/gazitofu/DAMA/Scripts '/Users/gazitofu/Library/Application Support/com.gazitofu.Dama' .build/diagnostics/backend-audit/reading-rerun.json DF6F46D1-D574-4493-8CA9-C7289F94EB92 5E0B2593-549B-48BC-9AED-A5C94B809B8C
```

Qwen 진단은 `python scripts/diagnose-qwen-alignment.py <해당 Run/raw/qwen-response.json> <새 출력.json>`이다. 모델 의존성 없이 표준 라이브러리와 worker의 순수 매핑 함수만 사용한다. 실제 모델 weights/package 무결성이나 새 추론 재현성을 이 검사로 증명하지 않는다.

## 6. 문서 차이·다음 수정 순서

README의 pyannote 중심 현재 단계 설명과 Vault Dama 인덱스의 옛 이름/키 미확보 서술은 현행 operating-baseline의 Soniox+P2/0.4.3과 다르다. ssot/dev의 초기 테스트 수·검증 상태 역시 최신 유닛 결과와 구분해야 한다. README·ssot/dev·Qwen evaluation은 착수 dirty 소유 파일이므로 이번에 고치지 않았다. UI 표현을 포함한 안내 정리는 해당 owner 변경과 합칠 때 현행 계약/실행 상태로 갱신한다.

1. **안전 수명주기(F-01)**를 작은 수정 단위로 처리한다. 동시 상태 회귀와 원본 보존을 먼저 확인한다.
2. **읽기 종결(F-02)**을 reading policy 새 버전으로 수정하고 같은 저장3본 전후 비교, 원문/시간/화자/수동 경계 불변 검사를 수행한다. 분절 감소 목표치부터 정하지 않는다.
3. **읽기 snapshot·메인 I/O(F-03)**를 별도 변경으로 처리하고 긴 실제 Script의 재생/편집/재열기 반응을 계측한다.
4. **파일별 실패 격리·검사 실행 경로(F-04/F-07)**를 정상 데이터 접근/불명 제출 차단을 함께 검증하며 정리한다.
5. **공통 근거 계산(F-06)**은 동일성 검증 아래 추출한다. **runtime 고정(F-05)**은 후속 Mac-only 학습 유닛의 선행 계약으로 넘긴다. 구두점/미정렬 어절의 표시 단위 변경과 pre/post 정렬 계측은 따로 설계한다.

범위1·2의 검수·진단은 완료했다. 결함 수정·UI 시안·학습은 아직 실행하지 않았다. 운영 알고리즘, 앱 버전/설치, 원음·Script·사람 수정본을 변경하지 않았고 API/음성 전송0건이다. 기존 dirty7과 운영 유닛 built를 유지한다.

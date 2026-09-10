# LibraryScript · DAMA 라이브러리 편집 파일

사용자 2026-09-10 화면 확정 및 제목/Markdown 요청. 구현 정본은 `Packages/DamaCore/Sources/DamaCore/LibraryScript.swift`다. 기존 `transcript.v1.schema.json`·`DomainContracts.swift`·normalized 파일은 변경하지 않는다.

- 파일 확장자 `.dama.json`, `format = dama-library-script-1`. 기존 normalized v1과 구분되는 envelope다.
- 기본 라이브러리는 실제 사용자 홈의 `DAMA/Speeches`, `DAMA/Scripts`. 기존 폴더 bookmark가 있으면 그대로 사용하며 파일을 자동 이동하지 않는다. App Sandbox가 접근을 허용하지 않으면 NSOpenPanel에서 기본 DAMA 부모 폴더를 선택한 뒤 하위 폴더를 생성/재사용한다.
- `id`는 내장 `transcript.runId`와 동일, `revisionID`는 저장할 편집마다 새 UUID. 파일 이름은 안정 UUID로 만들어 제목 수정으로 바꾸지 않는다.
- `title`, `createdAt`, `recordedAt?`, `dateSource`, `timeZoneID`, `input`, `transcript`, `turnNames`, `turnTexts`를 보존한다.
- 날짜는 Foundation JSONEncoder/Decoder Date 표현(2001-01-01 UTC 기준 초)이며 JSON의 숫자를 Unix epoch로 읽지 않는다. Markdown 표시에는 `timeZoneID`와 UTC offset을 함께 쓴다.
- `recordedAt`은 마이크 녹음 시작 시각 또는 반입 파일 creationDate다. 후자는 실제 녹음 시각과 다를 수 있음을 `dateSource`에 명시한다. 불명은 nil이며 생성 시각으로 추정하지 않는다.
- `input` = `speakerCount: Int?`, `context: String`, `reference: String`, optional `participants`, `aiCorrection`, `referenceExcerpts`. 변환 시작 때 ManagedRun에 snapshot 저장. nil count는 자동, 지정은 1 이상. pyannote에는 numSpeakers만 연결한다. 승인된 후속 AI 교정은 아래 별도 계약을 따른다. optional 필드가 없는 기존 파일도 읽는다.
- 내장 `transcript`는 기존 normalized v1 검증을 통과해야 한다. 모델 원문·시간·원 화자 ID·구간·점수·불확실성은 불변이다.
- `turnNames`와 `turnTexts`는 Turn ID → 사용자 입력 원문 map이다. 알 수 없는 Turn ID는 거부한다. 화자 이름의 부분/이후/전체 변경은 같은 원 화자 ID의 Turn 집합에 이름 override를 기록한다. 문자열 동명이인 병합 없음. null 화자는 한 Turn만 변경한다.
- 문장 override는 모델 단어를 덮어쓰지 않고, 새 단어 시간을 추정하지 않는다. 모델 원문 보기는 word.text로, baseline 표시에는 기존 word.editedText를 존중한다.
- 저장은 내부 `LibraryRevisions/<revisionID>.dama.json` 기록 후 외부 활성 파일을 atomic 쓰기한다. 읽었을 때의 SHA256과 다르면 기존 외부 편집을 덮지 않고 실패한다. 중복 Run ID 파일이 있는 폴더는 임의 하나를 택하지 않고 오류를 표시한다.

## 재전사·라이브러리 삭제 (2026-09-10 사용자 추가 요청, T-15)

- Speeches의 ‘재전사…’와 Scripts의 ‘재전사…’는 내부 보존 원음으로 새 ManagedRun을 생성한다. 기존 ‘변환 재개’는 같은 Run을 이어간다. 새로운 제출은 매번 음성 전송·비용·선택한 자동 교정 발췌를 확인받는다. 기존 local-only는 유지한다.
- 기존 Run이 모두 readyForReview/failed/partialResult/resultExpired/submissionUncertain일 때만 새 제출을 허용한다. 접수 불명 기록이 하나라도 있으면 중복 처리·과금 가능성을 확인창에 명시한다. 미완료/paused/unknownRemoteStatus Run은 새 제출로 우회하지 않는다.
- 새 결과는 session의 active revision이 아닌 해당 runId의 model을 로드한다. 서로 다른 Run의 Script는 별도 파일이며 이름·문장 override를 자동 이식하지 않는다(INV-09). 기존 파일·원문·수정본·원음은 보존한다. 제목이 같아도 생성 시각과 목록 항목으로 각각 열 수 있다. 실행 상태와 로컬 저장 버튼은 최신 Run에 대응한다.
- ‘삭제…’와 목록 우클릭의 ‘Speech 삭제…’/‘Script 삭제…’는 선택 폴더의 해당 파일 또는 `.dama-audio` 묶음을 macOS 휴지통으로 보낸다. 확인창 기본 버튼은 ‘취소’, 실행 버튼은 ‘휴지통으로 이동’. 연결 항목·내보낸 Markdown·내부 녹음/Run/LibraryRevisions/index는 남긴다. 내부 원음이 있으므로 Speech를 휴지통으로 보내도 Script의 재생·재전사가 가능하다. 완전 삭제/서버 삭제와 구별해 설명한다.
- 편집/미저장 입력/녹음/변환/교정/Script 저장 중 삭제를 차단한다. 대상은 선택 폴더 바로 아래여야 하며 symlink·내부 저장소 중첩을 거부한다. 선택 시 hash와 실행 시 hash가 다르면 삭제하지 않는다. 녹음 묶음은 manifest뿐 아니라 원본 청크 hash도 확인한다. 휴지통 이동 실패를 영구 삭제로 대체하지 않는다.
- 휴지통에서 원래 위치로 복원하면 새로고침으로 다시 표시한다. index를 보존하므로 같은 Speech의 session/입력 연결을 유지한다. 내부 녹음 복구 또는 완료 Run의 ‘스크립트 저장’은 사용자가 명시적으로 보존 사본을 다시 만드는 동작이다.

## Markdown 내보내기

제품 내보내기는 `.md` 하나다. 코드의 기존 Core JSON/TXT exporter는 기존 계약 호환용으로 남지만 새 라이브러리 UI에서 노출하지 않는다.

1. 수정 제목.
2. 녹음 날짜·시각·offset·시간대·날짜 근거·녹음 길이·스크립트 생성일.
3. 변환 전 입력 화자 수(미입력=자동), 맥락, 참고 정보.
4. 각 발화의 현재 화자 표시 이름, 시작–끝 `HH:mm:ss.SSS`, 현재 대화/marker, 사용자 수정 및 검수 이슈.

내부 µs는 ms 이하를 절삭해 표시한다(850000µs → 00:00:00.850). null/음수는 ‘시간 미확인’. 제목/본문의 Markdown 특수문자는 escape해 입력 내용이 문서 구조나 외부 링크로 변하지 않게 한다. 내보내기 자체는 다른 AI에 전송하지 않는다.

검증: `LibraryJourneyTests`, `ManagedJourneyTests.testConversionInputSnapshotSurvivesCredentialResume`, `testFolderToMockProcessingScriptEditAndMarkdownJourney`. 실제 음성·실제 서버·청구 검증과 별도다.

## 연속 발화 표시 (2026-09-10 실사용 수정)

- `LibraryPresentation.swift`의 `ScriptBlock`은 화면·Markdown 공통 읽기 모델이다. 저장된 Turn이나 schema를 병합하지 않는다.
- 인접한 speech Turn의 원 화자 ID·현재 이름이 같고 시간 순서가 확인되면 한 문단으로 연결한다. 첫 시작과 마지막 종료를 표시하고, 두 문자열 사이 공백이 없을 때만 한 칸을 추가한다. 원 문장은 윤문하지 않는다.
- 다른 화자, missingSpeech, null 화자, 불명/겹친 시간은 경계다. 텍스트가 없는 다른 diarization 화자도 경계다. legacy normalized revision에 humanEdited가 있으면 사람이 만든 분할을 보존하기 위해 묶지 않는다.
- 묶음의 이름 ‘이 부분만’은 포함된 원 Turn 전부, ‘이 부분부터’는 첫 Turn부터 동일 원 화자, ‘전체’는 같은 스크립트의 동일 원 화자다. 서로 다른 이름으로 수정된 인접 Turn은 합치지 않는다.
- 묶음 대사 편집창은 원 시간 구간별 입력을 제공한다. 각 변경은 기존 turnTexts로 저장하므로 포맷 마이그레이션이 없다.
- 화자 최초 등장 순서로 10개 색 슬롯을 지정한다. 원 ID가 같으면 이름 수정 뒤에도 색이 같고, null은 중립색이다. 11번째 이후는 색을 재사용하므로 이름을 계속 함께 표시한다.
- open 이슈만 노란 이벤트 아이콘으로 노출한다. 단어·Turn 참조가 없는 이벤트는 시간상 대응 구간(녹음 끝의 중단은 마지막 구간)에 연결한다. 시간도 없으면 첫 구간에서 볼 수 있다. acknowledged/resolved 이슈도 데이터·Markdown에는 보존한다.
- 검증: `LibraryPresentationTests`의 묶음 편집/왕복/MD, 경계, 10색·이벤트 여정.

### 읽기·검수 개선 (2026-09-10 T-11)

- 표시 정책 `ScriptReadingPolicy.algorithmVersion = reading-v2`. 모델의 `managed-v1` provenance와 저장 normalized를 변경하지 않는다. 기존 파일도 새 읽기 정책으로 표시/MD를 생성한다.
- 다른 화자 구간이 인접 두 Turn의 시작부터 끝까지 연속으로 덮는 경우, 동일 겹말 내부의 같은 화자/이름 단어는 묶을 수 있다. 다른 화자 구간의 시작·끝이 이웃 범위 안에 있으면 경계로 유지한다. 짧은 B·누락/미확정·시간 역전/겹침·legacy 사람 분할은 유지한다. 경고가 있다는 이유만으로 모두 개별 행으로 만들지 않는다.
- 읽기 휴지 최대1.5초, 문단 최대30초는 품질 최적값이 아닌 초기 표시값. 원 단일 Turn은 쪼개지 않으므로 30초 초과 가능. 원 단어·시간·화자 귀속에 영향 없음.
- 노란 아이콘은 open 경고의 겹치거나 닿는 시간 범위를 `ScriptReviewEvent`로 묶는다. 종류별 설명을 한 번씩 표시하고 세부 펼침에 원 이슈 종류/시간을 보존한다. AI 확인 건수는 별도다. 팝오버는 스크롤 가능하며 이벤트의 ‘앞뒤 원음 듣기’로 ±2초 문맥을 재생/정지한다. 원 이슈와 Markdown의 전체 이슈 기록은 삭제하지 않는다.
- 0길이 발화의 재생도 ±2초 문맥으로 대체하고 그 이유를 안내한다. nil·음수·역전·음원 범위 밖 시작은 거부한다. 재생 범위만 원음 길이 안으로 제한하며 transcript 시간은 수정하지 않는다. 정상 발화 재생은 기존 자체 범위 유지. 원음 끝의 0길이도 앞 문맥 청취 가능하다.
- 검증: 합성 영향 8개 distinct test, 실제 1건 읽기 전후 벤치마크, Debug compile. 수치/미측정/로그는 `versions/library-workspace/plan.md` T-11 기록. 원음 기반 정확도나 실제 청취 판정은 아니다.

### 표시 공백·교정 이력 분리 (2026-09-10 T-12)

- 읽기 정책은 `reading-v3`. v2의 묶음/시간/화자/이슈 규칙은 유지하고 문단 바깥 공백만 UI/Markdown 표시에서 제거한다. 원 word.text/prefix 및 `originalText`·교정 입력은 보존한다. 해당 문단에 turnTexts·legacy editedText 또는 humanEdited revision이 있으면 사람이 입력한 공백을 그대로 표시한다.
- `ScriptCorrection.visibleEdits`는 기존 저장 이력 중 applied=true이면서 원문/후보의 앞뒤공백 제거 결과가 같은 항목만 제외한다. UI와 Markdown이 같은 목록을 소비하며 저장된 이력을 지우지 않는다. applied=false는 공백만 다르거나 원안이 같아도 남긴다. 원 시간/화자/겹말/누락 이슈와 AI 불확실성은 별개로 보존한다.

## AI 문맥 교정 · 사용자 후속 결정 2026-09-10

- `correction?`는 `ScriptCorrection` 별도 overlay. 상태(running/completed/failed), 엔진/알고리즘, 시작/완료, 입력 snapshot, Turn ID별 원문/제안/이유/자동 적용 여부, 화자 이름/자기소개 인용, 완료/전체 청크 수를 보존한다. 원 normalized 계약은 변경하지 않는다.
- 표시 우선순위: 사람이 입력한 turnNames/turnTexts → 적용된 AI 교정 → 기존 원문. `showsOriginal? = true`는 AI 교정 전 표시로 전환하며 사람 수정은 유지한다. 애매한 교정의 ‘교정안 적용/원문 유지’는 해당 Turn의 사람 선택으로 저장하며 AI 확인 표시를 해소한다(기존 음성 이슈는 별개). 이전 AI 교정 기록도 내부 immutable LibraryRevisions에 남는다.
- 현행 정책은 아래 T-13의 `context-correction-3`이며 형식 allowlist는 T-12에서 유지한다. 모든 소유 Turn ID가 순서대로 정확히 한 번 반환되어야 한다. 형식 동등성 비교는 유효한3자리 천단위 comma 양옆 ASCII 공백, 독립된 안되니까/안되는데/안해도의 안 뒤 공백, 숫자 뒤 조/억/만/천/백과 원 사이 공백에만 한정한다. 숫자 계산·단위 변환·부호/구두점 삭제·전체 공백 제거는 하지 않는다. 예: `1 ,000억→1,000억` 허용, `3 ,40억→3,40억` 보류. 이는 형식 정책이며 발화의 정답 검증은 아니다.
- 검증된 명시적 용어 대응 외의 새 어휘/약어/구두점 또는 다른 내부공백 변경은 원문 유지+후보/이유+노란 이벤트로 남긴다. LLM certain/reason·참고 자료에 후보가 존재한다는 사실만으로 허용하지 않는다. v1의 보호 토큰 동등 비교는 제거했다. 새 정책은 새 응답 검증에 적용하고 기존 저장 교정본의 적용 판정을 재해석하거나 사용자 수정본을 덮지 않는다.
- 새 응답이 앞뒤공백만 바꾸고 certain=true이면 edit를 만들지 않는다. certain=false이면 앞뒤공백 제안은 원문 문자열로 유지하고 불확실성/이유를 남긴다. 모델에는 변경 후보마다 이유를 요구하며, 앱은 자동/보류 판정 이유와 모델 설명을 구분해 기록한다. 이유가 있어도 독립 근거가 되는 것은 아니다.
- AI는 원음 대신 텍스트만 받는다. 화자 ID/타임스탬프/단어/누락 장벽을 수정하는 출력 필드는 없다. 이름은 참석자 목록(한 줄에 이름+소속/역할)과 명시적 자기소개 인용이 일치할 때만 매핑한다. 다른 청크의 이름 충돌은 자동 매핑을 제거한다.
- 5분 또는 100발화 또는 16k자에서 청크 경계를 만든다. 앞뒤 최대 20초/10발화 문맥은 읽기 전용, 소유 발화만 반환/검증한다. 숫자 진행률은 완료 청크/총 청크이며 서버 내부 토큰 진행률/오디오 비율이 아니다. 한 청크 요청 제한 300초, 프롬프트 512kB, 응답 2MB는 초기 자원 한도다.
- 참고 폴더는 사용자 선택 bookmark 아래 Markdown/plain-text만 읽는다. 숨김·패키지·symlink 제외, 탐색 300항목/깊이3/파일200kB, 관련 키워드 문단을 최대8파일/12k자로 발췌한다. 전문은 업로드하지 않고 확인창의 파일명/발췌 snapshot만 교정 입력으로 사용한다. SHA256은 읽은 바이트 기준. PDF/DOCX 및 OCR은 이번 구현 범위 밖이다.
- 자동 교정 기본 선택은 켜져 있지만 전송 동의는 아니다. 변환 확인창에서 음성→pyannote와 전사/입력/발췌→OpenAI를 함께 확인한 Run만 후속 자동 교정한다. 기존 Script는 AI 교정 버튼에서 별도 확인한다. 요청별로 추론이 이루어져 Codex 계정 사용량이 소모될 수 있다.
- CLI는 Process 인자 배열과 stdin 파일로 실행. 임시 디렉터리 0700/입력0600, 진단 stdout/stderr는 원문 노출 방지를 위해 버린다. 완료/실패 시 해당 임시 디렉터리를 정리한다. 앱 강제 종료 시 임시 잔여 가능. API 키/인증파일을 앱에서 읽거나 Git에 저장하지 않는다.
- 확인한 CLI 0.153.4: `--ignore-user-config --ignore-rules --ephemeral --sandbox read-only --skip-git-repo-check --output-schema --output-last-message`. shell/unified exec/apps/plugins/hooks/agents/skills discovery/web/image/code-mode 비활성화. 모델은 CLI 기본값이며 실제 모델 버전/품질은 아직 실측하지 않았다. 사용자 전체 Codex 설정/샌드박스/앱 signing entitlement를 바꾸지 않는다.
- 최초 시작 상태를 먼저 저장하며 모든 청크 성공 후 교정본을 한 번에 적용한다. 기존 성공 교정본의 재교정은 원문+사람 수정을 입력으로 다시 계산하고 새 성공 전까지 기존 성공본을 유지한다. 중단/오류는 원문/이전 성공본 유지, 자동 재호출 없음. 앱 재시작 시 남은 running 상태는 미완료로 표시하며 재승인 후 다시 시도한다. 저장은 최신 Script를 다시 읽어 AI layer만 병합해 사람 수정을 보존하고, 원 normalized 내용 변경 또는 외부 hash 충돌은 실패로 남긴다.
- Markdown에는 교정 전/반영 표시, 사람 수정 우선, 교정 입력/참고 발췌와 파일 hash, 각 원문/교정안/이유, 이름 근거를 함께 출력한다. AI가 교정한 문장을 모델 원문인 것처럼 내보내지 않는다.
- 원음은 내부 보존된 `audio/analysis.wav`의 해당 범위를 재생한다. 시작~끝 범위를 검증하며 녹음 시작 시 재생을 멈춘다. 출력 장치의 실제 지연/경계 청취는 별도 실기기 검증이다.

근거: 로컬 CLI `--version`, `exec --help`, `features list`; [OpenAI non-interactive](https://learn.chatgpt.com/docs/non-interactive-mode), [configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference). `ContextCorrectionTests`, `CodexCorrectionTests`(가짜 프로세스), `ContextAudioTests`. 실제 추론·인증·서명 샌드박스·한국어 정확도는 미측정.

### 수정별 근거와 독립 미해결 (2026-09-10 T-13)

- 새 CLI 응답의 Turn은 기존 id/text/certain/reason과 함께 `changes`, `unresolved` 배열을 필수 반환한다. change는 `quote`, `occurrence`, `replacement`, `certain`, `reason`, `termID?`; unresolved는 `quote`, `occurrence`, `reason`이다. occurrence는 해당 원문 인용의 비중첩 literal 출현을 **0부터** 센다. 예: `30억원 30억원`의 occurrence=1은 두 번째 `30억원`이다. 음성 시간이나 글자수 비례 시간으로 환산하지 않는다.
- 인용이 없거나 빈 인용·음수/초과 위치·중첩 수정·전체 제안 text와 수정 재구성의 불일치는 응답 실패다. change/unresolved는 각 최대100개로 초기 자원 제한을 둔다. 미해결 이유는 비어 있을 수 없다. Turn certain=false인데 개별 불확실 수정/미해결 항목이 없으면 원 Turn 전체를 미해결로 남긴다.
- 각 수정이 certain=true이고 자기 범위와 미해결 인용이 겹치지 않을 때, 원문 전체에 **그 수정 하나만 적용한 결과**가 기존 제한 형식과 동등하거나 아래 명시적 용어 대응이면 반영한다. 다른 부분의 미해결은 이 수정을 막지 않는다. source quote 바깥 원문은 그대로 연결한다. 후보 전체·자동 반영 본문·수정별 판정·미해결을 각각 저장하고 원 normalized는 보존한다.
- 용어는 기존 **사용자 참고 정보** 필드에 `용어 | 주제 | 원표기 | 표준표기` 한 줄 형식으로 지정한다. 예: 맥락 `원자로 검토`, 참고 `용어 | 원자로 | 에스엠알 | SMR`, 원 발화 `원자로 에스엠알 검토`이면 대응 가능하다. 주제/두 표기는 2~60자이며 두 표기는 문자·공백만 허용, 알려진 부정/수량/단위 독립 토큰은 제외한다. 맥락에 주제 문자열이 있고, **동일 원 Turn에서 수정 범위 바깥에 주제 문자열이 있어야** 한다. 교체할 인용의 양옆이 다른 문자/숫자면 거부하므로 조사가 붙은 형태는 대응에 함께 지정해야 한다. 같은 원표기에 다른 표준표기가 지정되면 전부 보류한다. 이는 사용자 지정 표기 정규화이며 주제 문자열 출현이 의미나 원음 정답을 증명하지 않는다.
- 앱이 참고 정보 전체 UTF8 SHA256+행번호로 termID를 만들고 프롬프트에 검증 가능한 terms 목록을 전달한다. 응답의 termID·원표기·표준표기·원 발화 범위를 다시 대조한다. 다른 입력/발화/주제의 대응, 위조 ID, 일반 참고 문서에서 표기가 등장한 사실만으로는 허용하지 않는다. 선택 참고 발췌는 모델의 후보 생성 자료이며 자동 용어 대응으로 파싱하지 않는다. 참고에서 대응/주제를 자동 추출하는 확대와 실제 어휘 정확도 평가는 후속이다.
- 저장은 기존 CorrectionEdit의 Turn당1개 구조를 유지하며 optional `changes`, `unresolved`, `appliedText`를 추가한다. `applied`는 모든 수정 반영+미해결 없음일 때 true; 일부만 반영되면 false여도 `appliedText`를 표시한다. 새 레코드 로드 시 후보/반영 본문을 원문과 개별 수정으로 재구성해 일치 여부를 검증한다. 새 필드가 없는 이전 저장본은 기존 적용 판정을 유지하며, 기존 raw reply 로컬 재생 경로도 T-12 정책을 유지한다. 실제 CLI 어댑터는 새 필드가 빠진 응답을 거부한다.
- UI와 Markdown은 부분 반영 본문·수정별 반영/보류·미해결을 보여 주며 source issue는 유지한다. 기존 원문 전환과 사람 수정 우선순위를 유지한다. 수동 선택은 현재 **원 Turn 전체** 범위이므로 버튼을 ‘전체 교정안 적용 / 전체 원문 유지’로 명시한다. 개별 수정 수동 선택 UI는 추가하지 않았다. 새 형식의 실제 모델 생성 성공·한국어 교정 품질은 합성 응답/가짜 CLI/빌드 결과로 대신 판정하지 않는다.

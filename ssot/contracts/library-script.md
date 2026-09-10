# LibraryScript · DAMA 라이브러리 편집 파일

사용자 2026-09-10 화면 확정 및 제목/Markdown 요청. 구현 정본은 `Packages/DamaCore/Sources/DamaCore/LibraryScript.swift`다. 기존 `transcript.v1.schema.json`·`DomainContracts.swift`·normalized 파일은 변경하지 않는다.

- 파일 확장자 `.dama.json`, `format = dama-library-script-1`. 기존 normalized v1과 구분되는 envelope다.
- `id`는 내장 `transcript.runId`와 동일, `revisionID`는 저장할 편집마다 새 UUID. 파일 이름은 안정 UUID로 만들어 제목 수정으로 바꾸지 않는다.
- `title`, `createdAt`, `recordedAt?`, `dateSource`, `timeZoneID`, `input`, `transcript`, `turnNames`, `turnTexts`를 보존한다.
- 날짜는 Foundation JSONEncoder/Decoder Date 표현(2001-01-01 UTC 기준 초)이며 JSON의 숫자를 Unix epoch로 읽지 않는다. Markdown 표시에는 `timeZoneID`와 UTC offset을 함께 쓴다.
- `recordedAt`은 마이크 녹음 시작 시각 또는 반입 파일 creationDate다. 후자는 실제 녹음 시각과 다를 수 있음을 `dateSource`에 명시한다. 불명은 nil이며 생성 시각으로 추정하지 않는다.
- `input` = `speakerCount: Int?`, `context: String`, `reference: String`. 변환 시작 때 ManagedRun에 snapshot 저장. nil은 자동, 지정은 1 이상. 클라우드에는 numSpeakers만 연결하며 맥락/참고는 로컬 메타데이터다.
- 내장 `transcript`는 기존 normalized v1 검증을 통과해야 한다. 모델 원문·시간·원 화자 ID·구간·점수·불확실성은 불변이다.
- `turnNames`와 `turnTexts`는 Turn ID → 사용자 입력 원문 map이다. 알 수 없는 Turn ID는 거부한다. 화자 이름의 부분/이후/전체 변경은 같은 원 화자 ID의 Turn 집합에 이름 override를 기록한다. 문자열 동명이인 병합 없음. null 화자는 한 Turn만 변경한다.
- 문장 override는 모델 단어를 덮어쓰지 않고, 새 단어 시간을 추정하지 않는다. 모델 원문 보기는 word.text로, baseline 표시에는 기존 word.editedText를 존중한다.
- 저장은 내부 `LibraryRevisions/<revisionID>.dama.json` 기록 후 외부 활성 파일을 atomic 쓰기한다. 읽었을 때의 SHA256과 다르면 기존 외부 편집을 덮지 않고 실패한다. 중복 Run ID 파일이 있는 폴더는 임의 하나를 택하지 않고 오류를 표시한다.

## Markdown 내보내기

제품 내보내기는 `.md` 하나다. 코드의 기존 Core JSON/TXT exporter는 기존 계약 호환용으로 남지만 새 라이브러리 UI에서 노출하지 않는다.

1. 수정 제목.
2. 녹음 날짜·시각·offset·시간대·날짜 근거·녹음 길이·스크립트 생성일.
3. 변환 전 입력 화자 수(미입력=자동), 맥락, 참고 정보.
4. 각 발화의 현재 화자 표시 이름, 시작–끝 `HH:mm:ss.SSS`, 현재 대화/marker, 사용자 수정 및 검수 이슈.

내부 µs는 ms 이하를 절삭해 표시한다(850000µs → 00:00:00.850). null/음수는 ‘시간 미확인’. 제목/본문의 Markdown 특수문자는 escape해 입력 내용이 문서 구조나 외부 링크로 변하지 않게 한다. 요약·윤문·다른 AI 전송은 하지 않는다.

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

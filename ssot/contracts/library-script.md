# LibraryScript · DAMA 라이브러리 편집 파일

## 검수 이슈 표시 (2026-11-05 사용자 확정 · usage-bundle1)

- 읽기 화면 문단에 자동 경고 8종(`ambiguous_speaker`·`overlapping_speech`·`missing_speech`·`boundary_conflict`·`unrepresented_speaker`·`invalid_timestamp`·`low_confidence`·`provider_disagreement`)을 표시하지 않고, 구간 정보의 «자동 경고 N건»에서 종류별 건수로 연다. 대상은 문단 `block.issues` 중 상태 open이며, 기본 닫힘·건수 내림차순·같으면 종류 이름 오름차순·0건 종류 제외다. 구간 정보는 하단 «정보»로 연다.
- 녹음 중단(`capture_interrupted`)·일부 결과(`partial_result`)·화자 미배정은 계속 표시한다. 중단·일부 결과는 그 문단 본문 아래와 구간 정보 맨 위 경고 줄에 ⚠ 기호와 문장으로 남는다(open만).
- Markdown은 문단별 이슈 줄(`> 검수: …`)을 쓰지 않고 머리말 한 줄(`- 검수: …`)에 자동 경고 총수와 종류별 건수를 적는다. 총수는 `transcript.reviewIssues` 중 자동 경고 8종 전부이고 상태·삭제 문단을 따지지 않는다. 녹음 중단·일부 결과는 머리말(종류당 1줄)과 그 문단 아래(`> 녹음 중단: …`·`> 일부 결과: …`)에 상태와 무관하게 남기며, 삭제된 문단의 것은 머리말에만 남는다. 문구 정본은 `ssot/tone/usage-bundle1.md`.
- `reviewIssues` 생성·보존·평가 JSON·`blocks()`·`ScriptReviewEvent`는 바뀌지 않는다. 두 번째 읽기 레이어 예외이고(선례 2026-09-13 missingSpeech), 경고를 숨긴 것은 그 구간이 맞다고 확정한 것이 아니다.
- 이 절은 «연속 발화 표시»의 «open 이슈만 노란 이벤트 아이콘으로 노출» 항과 «Markdown 내보내기» 4항의 «검수 이슈» 부분보다 우선한다.

## 녹음 표시 제목 (2026-11-05 · usage-bundle1)

- 데이터: 인덱스(`library-index.json`) 항목 `LibrarySpeech`에 선택 필드 `displayTitle: String?`를 더한다. 없는 항목은 nil로 읽고, nil이면 키를 쓰지 않는다. 녹음 파일 이름·`capture-manifest.json`·기존 `title`은 건드리지 않는다.
- 해석: 녹음 제목 = `displayTitle ?? title`(자동 제목 또는 가져온 파일 이름). 연결 = 인덱스 항목 id와 스크립트 `transcript.sessionId`가 같음이며, Speech 파일이 휴지통에 있어도 인덱스 항목이 있으면 연결이다. 스크립트 제목 = 연결 녹음의 `displayTitle`, 없으면 스크립트 파일 `title`. AI 버전 보기는 그 버전 파일의 당시 제목을 그대로 보인다.
- 쓰는 곳: 녹음 직후 입력창·Speech 상세 제목칸·연결 있는 스크립트 제목칸은 인덱스 `displayTitle`에만 쓰고 스크립트 파일은 쓰지 않는다(파일 `title` 불변). 연결 없는 스크립트 제목칸은 현행 `saveTitle`(파일)이다. 새 스크립트 파일의 `title`은 해석한 녹음 제목으로 만든다. 평가 JSON `script.title`은 파일 기록 그대로다.
- 해석 제목을 쓰는 자리: Speech 목록·상세, Script 목록·읽기 제목칸, AI 검수/보정 창 머리, 삭제 확인창, 변환·재전사 확인창, Markdown `# 제목`, 내보내기 파일 이름.
- 저장 시점(T2a-5): Enter·입력칸 이탈·입력창 «저장»일 때만 저장하고 0.5초 자동 저장은 없다. 한글 조합 중에는 저장하지 않고, Esc는 마지막 저장값으로 되돌리며, 빈값·공백뿐이면 저장하지 않는다. 저장 값은 입력 그대로다.
- 기존 데이터는 자동으로 합치지 않는다(무이관). `displayTitle`이 없는 녹음은 지금처럼 보이고, 어느 쪽이든 제목을 한 번 고치면 그때부터 하나가 된다.

## 스크립트별 등록 화자·발화 삭제 (2026-09-13 사용자 승인 · T-08)

- optional `registeredSpeakers: [ScriptSpeaker]?` = UUID `id`, 공백을 다듬은 비어 있지 않은 고유 `name`,0~9 `colorIndex`. `turnSpeakerIDs: [TurnID: 등록ID]?`는 사용자가 지정한 인물 연결이다. 원 transcript speakerId와 구분하며 다른 Script/Run에 복사하지 않는다. 구 파일의 누락 필드는 nil로 읽는다.
- 화자 모달의 이름 저장은 새 인물을 등록한다. 같은 이름을 다시 입력하거나 ‘등록된 화자’ 목록에서 선택하면 같은 등록ID/이름/색을 쓴다. legacy turnNames도 목록에서 선택 가능하고, 사용자가 같은 이름을 명시적으로 저장할 때 해당 기존 이름들을 등록ID에 연결한다. 파일을 읽기만 해서는 쓰거나 병합하지 않는다. 기존 원 Turn 이름 수정 API의 원 화자 범위는 하위 호환으로 유지한다.
- 문단 화자 범위 (2026-09-21 사용자 규칙으로 개정): ‘이 부분만’은 해당 원 ID 집합, ‘이 부분부터/전체’는 **항상 원 speakerId(Speaker A/B/C)가 같은 Turn 집합**이다. 등록ID·이름은 대상 선정에 쓰지 않는다. 그래서 Speaker A·B를 모두 같은 이름으로 지정한 뒤 Speaker B 문단에서 다른 이름으로 전체 변경하면 Speaker B 문단만 바뀐다. 원 speakerId가 null인 문단은 등록 여부와 무관하게 선택 문단만 지정한다. 이름/색이 같아도 서로 다른 원 화자/미배정 문단을 자동 병합하지 않는다. 등록ID의 이름은 AI 이름보다 우선하며 raw 화자·정렬·점수·원음은 불변이다. 화자 모달은 문단의 원 라벨(`originalSpeakerLabel`)을 함께 표시한다.
- optional `nameHistory: [ScriptNameChange]?` (2026-09-21 사용자 요청): 저장된 화자 이름 변경의 되돌리기 스택. 항목은 UUID `id`, 적용한 `name`, 영향받은 원 `turnIDs`, 그 직전 값 `previousNames`/`previousSpeakerIDs`, 이 변경이 새로 만든 `addedSpeakerID?`다. `turnIDs`에 있는데 map에 없으면 그때 값이 없었다는 뜻이다. ‘이름 변경 취소 (N)’는 마지막 항목만 되돌리고, 그 변경이 만든 등록 인물은 남은 이름·이력이 더 이상 참조하지 않을 때만 지운다. 상한은 초기 설계값 `nameHistoryLimit = 20`이며 넘으면 오래된 항목부터 버린다. 과거 snapshot에서는 되돌릴 수 없다. 원문·시간·원 화자 ID·본문 수정·삭제 상태·AI 이력은 바뀌지 않는다. 구 파일의 누락 필드는 nil로 읽는다.
- optional `deletedParagraphs: [ScriptDeletedParagraph]?` = 삭제 순서 배열(UUID `id`, 순서 있는 원 `turnIDs`). 실제 표시된 한 문단 전체를 삭제 대상으로 저장하며 원문/시간/사람 본문·화자 수정/AI 이력을 지우지 않는다. 화면과 Markdown에서 제외하고 ‘삭제 취소 (N)’로 마지막 삭제부터 복구한다. 마지막 발화를 삭제해도 Script 파일은 남고 빈 상태·삭제 취소를 표시한다.
- 삭제 구간은 전후 읽기 그룹을 합치는 통로가 아니다. 모든 원 Turn을 보존하고 삭제 경계는 분리한다. 사람 본문을 다른 문단에 붙여 넣은 뒤 삭제하는 수동 통합을 지원한다. 취소 시 삭제 직전의 사람 수정 내용이 다시 나타난다. 삭제한 원 ID는 새 AI의 대상과 참고 본문 모두에서 제외하며 이미 진행 중인 AI 완료도 삭제 레이어를 보존한다.
- 현재 버전만 변경, revisionID·불변 로컬 revision·원자 저장·외부 해시 충돌 방어를 그대로 사용한다. 과거 AI snapshot은 당시 등록 화자와 삭제 상태를 보존하며 현재의 삭제/취소로 바뀌지 않는다. 현재 모델 원문 보기에서도 사용자 삭제는 적용한다. 구조화 envelope에는 원문과 삭제 상태 모두 포함된다.
- `ScriptPeopleAndDeletionTests`와 `ScriptVersionTests`에서 등록/범위/동일 색/legacy/잘못된 참조, 수동 통합·삭제/취소/전부 삭제/AI 입력 제외, 재실행·Markdown·AI 완료·과거 snapshot·충돌을 검증한다. 상태/실물 QA는 [uiux-reading T-08](../../versions/uiux-reading/plan.md).

## uiux-reading 문단 직접 편집 (2026-09-12 승인 · D-02)

- optional `paragraphEdits` = UUID, 순서 있는 `turnIDs`, 정렬 JSON으로 계산한 불변 transcript의 `sourceSHA256`, 편집 시작 `baseRevisionID`/`baseTextSHA256`, 사람 입력 전체 `text`. 기존 JSON은 필드 없이 읽는다.
- 원래 읽기 문단 전체만 편집한다. ID는 연속된 speech Turn이며 기존 같은 화자·시간·누락 장벽 검사를 통과해야 한다. 여러 수정본의 ID 중복, 원문 fingerprint 불일치, 순서 변경은 파일 오류다. 빈 문자열/공백/개행도 사람 입력 그대로 보존한다.
- 수정한 문단은 원 ID 집합을 고정하여 구두점·AI·표시 이름 변경으로 다른 문단과 합쳐지지 않는다. 화면과 Markdown은 같은 blocks()의 사람 문단 전체를 사용한다. 원 Turn 텍스트에 재분배하거나 첫 Turn에 몰아 쓰지 않는다. 개별 Turn 수정/분절 변경으로 이 레이어를 우회하지 않는다.
- 사람이 소유한 문단·기존 turnTexts·legacy editedText/수정 revision은 AI 편집 대상에서 제외한다. 가까운 사람 문단은 `humanParagraphs`의 전체 텍스트/원 ID 집합으로 읽기 전용 제공한다. AI 응답은 대상 ID만 허용한다. source 텍스트/시간/화자/이슈와 기존 검수 기록은 보존한다.
- 새 일반 편집은 검수 완료·학습 정답 기록을 자동 생성하지 않는다. 과거 reviewRecords를 삭제하지 않는다. 아래 과거 UI·원 Turn 편집 설명 중 충돌하는 부분은 본 절과 확정 r4 스펙이 우선한다.

## AI 결과 버전·필드 저장 (2026-09-12 승인 · D-01)

- 현재 파일에 optional `versions` 목록(revisionID/SHA256/number/correctionID/createdAt). number0은 첫 기록 가능한 성공 직전 결과, 1부터 각 성공 결과다. 기존에 기록하지 않은 과거 결과는 만들어 내지 않는다. 당시 제목/사람 수정/AI/입력/원문을 snapshot에 고정한다.
- 새 ScriptCorrection은 optional UUID `id`를 만든다. 구 id 없는 결과는 읽기/병합 가능하지만 과거 이력으로 추정 승격하지 않는다. 같은 성공 ID는 목록에 한 번만 추가한다. 실패/취소/진행 중은 완료 버전 없음, 기존 성공 결과 교체 없음.
- snapshot은 `LibraryRevisions`에 별도 UUID로 선저장한다. snapshotTitle을 기록하고 versions를 비워 self-hash/순환 참조를 피한다. 현재 파일의 목록은 snapshot 실제 바이트 SHA256을 참조한 뒤 원자 저장한다. 도중 실패로 남은 파일은 메뉴에 드러내지 않는다.
- 조회는 현재 목록/현재 파일 해시, snapshot UUID 경로/해시/같은 Run·불변 transcript를 검증한다. 누락/손상은 오류이며 현재 내용을 대체해 보여 주지 않는다. snapshot은 수정 저장 API로 덮어쓸 수 없다. Markdown에는 결과 이름과 revision을 기재한다.
- 제목/문단/AI는 저장 actor에서 최신 원문을 다시 확인하고 해당 필드만 병합한다. 현재 actor가 저장한 변화만 병합하며 알 수 없는 외부 바이트 변경, 다른 Run/원문, 같은 제목 필드 충돌은 거부한다. 제목과 본문을 별도 저장해도 서로의 수정을 되돌리지 않는다.

## Speeches 소비 입력 표시 (2026-09-12 r5)

- 새 전사 설정과 용어/참고는 Speeches 안에서 접어 둔다. Soniox의 기본 문맥 ON일 때 맥락·참석자·직접 참고·용어·폴더 선택을 보이고, OFF이면 숨긴다. Soniox 단독/OFF에는 사용하지 않는 화자 수 입력도 숨긴다. P2를 사용하는 운영/Qwen/pyannote 경로는 화자 수 제약 입력을 유지한다.
- Qwen은 맥락·참석자·직접 참고·용어와 선택 발췌를 로컬 worker context로 보낸다. pyannote 통합 전사는 화자 수만 사용하므로 이외 참고 입력을 숨긴다. 기존 녹음에 저장된 숨긴 필드는 삭제하지 않는다.
- 새 전환 입력은 `ConversionNotes.forTranscription`에서 엔진별 용어를 복사하고 source 재사용 ID를 초기화한다. 신규 변환의 자동 AI 보정은 OFF이며 Scripts의 수동 모달에서 실행한다. 기존 Run 재개는 당시 동의/입력/설정을 그대로 따른다.
- 폴더 발췌 query에는 녹음 맥락·참석자·직접 참고와 회의 공통 용어를 포함한다. md/txt/깊이3/300항목/200KB·파일/상위3문단/8파일/총12,000자 기존 한도는 유지한다. Soniox는 7,500바이트 내에 포함된 발췌만 전송하며 확인창에 실제 JSON과 제외 이름을 표시한다. 연결 자체는 전송·학습이 아니다.

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

## 읽기 계산·파일 I/O (2026-09-12)

- `LibraryScriptFile`은 같은 파일 bytes의 해시·검증된 Script·불변 `ScriptReadingSnapshot`을 함께 보관한다. 저장 actor에서 blocks()/검수 사건을 계산하고 UI는 결과를 재사용한다. 메모리 파생물이며 `.dama.json`에 직렬화하지 않는다. 현재 읽기 정책은 아래 `reading-v8`이며 앱 재시작 시 기존 파일에도 적용된다.
- 새로고침은 파일을 읽어 실제 bytes 해시를 비교한다. 표준화 경로/해시가 모두 같을 때만 디코딩·검증·읽기 계산을 재사용한다. revisionID가 같아도 bytes가 다르면 새로 검증·계산한다. 사람 대사/이름·문단 경계·AI 교정·원문 보기·검수 이력은 해당 Script bytes에 포함되므로 함께 무효화된다. 성공한 폴더 조회 때 목록 밖 캐시를 비운다. 중복 ID·손상 파일·symlink 검사를 우회하지 않는다.
- 2026-10-30 `library-loading`: 목록은 `LibraryScriptSummary`(id·url·bytes SHA256·title·createdAt·sessionId·engine·sourceAudioSHA256)로 만든다. 내부 저장소 `library-script-summaries.json`(`version`=`summaryVersion`, 원자 쓰기)은 이전에 디코딩·검증을 통과한 bytes의 요약만 담는 파생 캐시이며 Scripts 폴더나 `.dama.json`에 쓰지 않는다. 매 새로고침에서 모든 파일을 읽어 해시를 비교하고, 표준화 경로·해시·`summaryVersion`이 모두 같을 때만 디코딩·검증을 생략한다. 다르거나 새 파일은 그 자리에서 디코딩·검증해 손상·중복 ID를 보고한다. 캐시가 없거나 손상·버전 불일치면 빈 캐시로 보고 전량 재구성하며 사용자 파일은 바꾸지 않는다. `LibraryScript.validate()`나 요약 필드의 의미가 바뀌면 `summaryVersion`을 올린다.
- 본문(`LibraryScriptFile`: 검증된 Script·읽기 계산)은 선택·열기·편집·내보내기·재전사 직전에 `loadScript`로 읽는다. 파일을 다시 읽어 요약 해시와 다르면 `changedFile`로 실패하고 호출자는 새로고침한다. 저장 병합(`latestForMerge`)과 Script 생성은 요약 목록으로 같은 id·경로·해시·중복 판정을 하며 열지 않은 다른 Script를 디코딩하지 않는다. 기존 `expectedHash` 충돌 방어와 stale 저장·내보내기 차단은 그대로다.
- 앱은 Speech 스캔 결과를 Script 스캔보다 먼저 반영한다. Script 목록을 읽는 동안에는 변환·재전사·Script 삭제·‘스크립트 열기/저장 다시 시도’·폴더 변경을 막고, Speech 상세의 변환 상태 두 줄은 기존 문구 ‘불러오거나 저장하는 중’으로 대신하고 Speech 목록의 변환 배지는 표시하지 않는다. 선택한 Script 본문을 읽는 동안 Script 화면도 같은 기존 문구를 쓴다. Script 목록이 불완전한 동안 새 전사 제출이나 Script 생성이 일어나지 않게 하기 위해서다.
- 화면은 재생 ID/안내 메시지만 구독한다. 약30ms 위치 갱신은 전체 Script 화면을 다시 계산하는 구독이 아니다. 재생 범위/정지/녹음 우선 규칙은 유지한다.
- 평가 JSON은 선택 시 Script와 월 비용을 고정하고 저장 actor에서 목적지·원본 해시 검증, encoding, atomic 쓰기를 수행한다. 보안 범위 접근은 완료까지 유지한다. 내부 저장소·`.dama.json`·알려진 Speech/묶음 안·symlink 대상에는 내보내지 않는다. 자동 전송은 없다.

## 2026-09-11 승인 후속: 기본 문맥·화자 힌트·문단 조정

- 새 Soniox 입력의 `sonioxSpeakerCountHint: Int?`는 사용자의 예상 발화자 수를 실제로 전송하는 snapshot이다. 기본 문맥 OFF/미입력은 nil. 과거 Run의 nil에는 전송 주장을 붙이지 않는다. 기존 speakerCount는 예상 인원으로 재사용하며 인원 일치/불일치는 검수 안내다.
- `sonioxReferenceExcerpts: [ReferenceExcerpt]?`는 Soniox에 실제 포함한 발췌, `sonioxOmittedReferences: [String]?`는 선택/용량으로 제외한 발췌 이름이다. 구 Run의 nil은 기존 referenceExcerpts 계약을 따른다. 새 Run의 빈 배열은 폴더 미전송이며 AI 교정용 referenceExcerpts와 섞지 않는다. 기본 문맥 ON·폴더 OFF 초기값과 사용자 설정 영속 저장, 전송 전 실제 payload 미리보기.
- 과거 `reading-v6`의 누적 문장 종결 휴리스틱은 2026-09-13 사용자 후속 승인으로 아래 `reading-v7`가 대체한다. 원문 문장부호는 그대로 보존한다.
- envelope optional `paragraphBreaks: [TurnID: Bool]?`: 해당 기존 Turn 앞 true=새 문단, false=앞 문단과 합치기, 키 없음=자동. 다른 원 화자/표시 이름/null/불명·시작 역행 시간/humanEdited legacy 장벽은 수동 합치기도 넘지 않는다. 조정은 기존 모델 Turn 경계에서 제공한다. 단일 모델 Turn 안의 임의 단어 분할은 제공하지 않는다.
- 수동 경계는 revisionID 갱신 및 기존 atomic 저장/외부 수정 충돌 검사를 따르고 원 normalized는 불변. 같은 blocks()를 UI와 Markdown에 사용한다. 사용자 ‘자동’ 복원은 해당 override 키 삭제. 재전사에는 복사하지 않는다.

## 재전사·라이브러리 삭제 (2026-09-10 사용자 추가 요청, T-15)

- Speeches의 ‘재전사…’와 Scripts의 ‘재전사…’는 내부 보존 원음으로 새 ManagedRun을 생성한다. 기존 ‘변환 재개’는 같은 Run을 이어간다. 새로운 제출은 매번 음성 전송·비용·선택한 자동 교정 발췌를 확인받는다. 기존 local-only는 유지한다.
- 2026-09-11 운영/실험 분리 후속: 결합 자식은 parent와 함께 관리하고, 중단된 Qwen 비교는 새 운영 전사를 막지 않는다. 나머지는 기존 제한을 유지한다.
- 기존 Run이 모두 readyForReview/failed/partialResult/resultExpired/submissionUncertain일 때만 새 제출을 허용한다. 접수 불명 기록이 하나라도 있으면 중복 처리·과금 가능성을 확인창에 명시한다. 미완료/paused/unknownRemoteStatus Run은 새 제출로 우회하지 않는다.
- 새 결과는 session의 active revision이 아닌 해당 runId의 model을 로드한다. 서로 다른 Run의 Script는 별도 파일이며 이름·문장 override를 자동 이식하지 않는다(INV-09). 기존 파일·원문·수정본·원음은 보존한다. 제목이 같아도 생성 시각과 목록 항목으로 각각 열 수 있다. 실행 상태와 로컬 저장 버튼은 최신 Run에 대응한다.
- ‘삭제…’와 목록 우클릭의 ‘Speech 삭제…’/‘Script 삭제…’는 선택 폴더의 해당 파일 또는 `.dama-audio` 묶음을 macOS 휴지통으로 보낸다. 확인창 기본 버튼은 ‘취소’, 실행 버튼은 ‘휴지통으로 이동’. 연결 항목·내보낸 Markdown·내부 녹음/Run/LibraryRevisions/index는 남긴다. 내부 원음이 있으므로 Speech를 휴지통으로 보내도 Script의 재생·재전사가 가능하다. 완전 삭제/서버 삭제와 구별해 설명한다.
- 편집/미저장 입력/녹음/변환/교정/Script 저장 중 삭제를 차단한다. 대상은 선택 폴더 바로 아래여야 하며 symlink·내부 저장소 중첩을 거부한다. 선택 시 hash와 실행 시 hash가 다르면 삭제하지 않는다. 녹음 묶음은 manifest뿐 아니라 원본 청크 hash도 확인한다. 휴지통 이동 실패를 영구 삭제로 대체하지 않는다.
- 휴지통에서 원래 위치로 복원하면 새로고침으로 다시 표시한다. index를 보존하므로 같은 Speech의 session/입력 연결을 유지한다. 내부 녹음 복구 또는 완료 Run의 ‘스크립트 저장’은 사용자가 명시적으로 보존 사본을 다시 만드는 동작이다.

## Markdown 내보내기

일반 스크립트 내보내기는 `.md`다. 2026-09-11 최종 운영안 승인으로 별도 평가 JSON(원문/입력/검수 기록/월 비용)을 추가하며 [운영 계약](operating-baseline.md)을 따른다. 코드의 기존 Core JSON/TXT exporter는 기존 계약 호환용으로 남지만 새 라이브러리 UI에서 노출하지 않는다.

1. 수정 제목.
2. 녹음 날짜·시각·offset·시간대·날짜 근거·녹음 길이·스크립트 생성일.
3. 변환 전 입력 화자 수(미입력=자동), 맥락, 참고 정보.
4. 각 발화의 현재 화자 표시 이름, 시작–끝 `HH:mm:ss.SSS`, 현재 대화, 사용자 수정 및 검수 이슈. 누락 의심 marker는 본문 문단으로 내보내지 않는다.

내부 µs는 ms 이하를 절삭해 표시한다(850000µs → 00:00:00.850). null/음수는 ‘시간 미확인’. 제목/본문의 Markdown 특수문자는 escape해 입력 내용이 문서 구조나 외부 링크로 변하지 않게 한다. 내보내기 자체는 다른 AI에 전송하지 않는다.

검증: `LibraryJourneyTests`, `ManagedJourneyTests.testConversionInputSnapshotSurvivesCredentialResume`, `testFolderToMockProcessingScriptEditAndMarkdownJourney`. 실제 음성·실제 서버·청구 검증과 별도다.

## 연속 발화 표시 (2026-09-10 실사용 수정)

### 제공자 비교 (2026-09-11)

- ConversionNotes에 optional transcriptionProvider/sonioxContext/sonioxTerms 추가. 구 파일의 nil 제공자는 pyannote로 읽는다. 실제 Run 생성 시 선택값과 AI/context 입력을 snapshot하며 재개 때 변경하지 않는다.
- normalized EngineKind에 managedSoniox 추가, Word에 optional asrConfidence(0~1)/language 추가. 기존 필수 nullable 키는 그대로이며 두 신규 필드는 구 JSON에 없어도 된다. 원 Soniox token이 subword이면 words의 한 항목도 subword다. ASR confidence는 speaker confidence/alignmentScore가 아니다.
- Script 목록·상세·Markdown에 공급자/모델을 표시한다. Markdown은 Run/음성 SHA256/context 전송 여부도 표시해 동일 음성의 독립 결과를 비교한다. 원응답·실제 작업 상태/서버 보고 모델은 Run 내부에 보존한다. 상세는 `ssot/api/soniox-verified.md`.
- 같은 화자 Soniox 문자열 연결은 원 토큰의 공백 그대로이며, reading-v4에서 새 공백을 만들지 않는다. 문단 표시 바깥의 앞뒤 공백 trimming은 기존 공통 표시 규칙이고 원 토큰은 불변이다.

### 부호·미배정 어절 표시 (2026-09-13 T-05, 현행)

- `reading-v8`은 v7의 같은 화자 연속 읽기에 부호와 어절 처리를 추가한다. 원문 부호를 삭제하지 않고 닫는 부호/공백은 왼쪽, 여는 괄호/따옴표는 오른쪽 본문에 붙인다. 부호만의 원 Turn은 음성 화자 경계로 사용하지 않는다. 앞뒤 실제 lexical 화자가 다르면 계속 별개 문단이다.
- Soniox/Qwen처럼 원문 공백이 보존된 입력의 미배정 조각은 원 ordinal이 인접하고, 중간 공백 없이 같은 ASR label의 한 어절이며 시작 시간이 순행할 때만 묶는다. 화자 배정은 null 그대로다. 서로 다른 미배정 어절이나 실제 화자 전환을 문맥으로 합치지 않는다.
- 표시 이름·색·이름 수정 범위는 문단의 첫 lexical 원 Turn을 기준으로 한다. ‘이 부분만’은 부호를 포함한 전체 원 Turn, ‘이 부분부터/전체’는 lexical 화자 범위와 선택 문단의 원 ID 집합에 적용한다. 표시/재생 시작·끝은 lexical 원시간의 최솟값/최댓값이며 부호 시간으로 늘리지 않는다. 저장된 모든 토큰·시간·원 화자 ID는 불변이다.
- 명시적 사람 문단/수동 경계/이름 override, word.editedText/turnTexts, legacy humanEdited를 보호한다. 사람이 의도적으로 저장한 부호 문단은 남길 수 있다. 자동 부호만 문단은 표시하지 않는다. 공통 `ScriptReadingStructure`의 연결 검증을 문단 저장에도 적용하며, 숨긴 marker 이외의 speech ID를 건너뛰는 저장은 거부한다.
- UI와 Markdown은 동일한 blocks()를 사용한다. 모델 재호출이나 기존 Script 쓰기가 필요 없다. B2의 화자 꼬리 보완은 별도의 `soniox-p2-word-v4` 비교 Run이며 이 읽기 정책과 구분한다. 검증은 `ReadingDecorationTests`와 [T-05](../../versions/soniox-p2-alignment/plan.md).

### 화자 기준 연속 발화 (2026-09-13 T-04, v8의 기반)

- 사용자: 누락 의심 문구 전부 제거, 같은 화자 연속 발화를 합치고 문단을 세분화하지 않는다. `reading-v7`는 아래 v2~v6의 읽기 분절 조건을 대체한다. 인접한 **표시 speech**의 원 화자 ID·현재 이름이 같으면 문장 종결/휴지 길이/전체 길이에 관계없이 연결한다. Soniox 토큰 공백·문장부호를 그대로 사용하며 목표 문단 수를 맞추려고 화자를 바꾸지 않는다.
- `.missingSpeech`는 화면과 Markdown 본문에 나타나지 않고 연결도 막지 않는다. 전사 텍스트가 없는 다른 화자 diarization도 읽기 경계가 아니다. 원 normalized의 marker·단어·시간·화자·경고와 INV-06 분할은 그대로 보존한다. 이것은 읽기 레이어의 사용자 승인 예외이며, 누락된 말을 복구하거나 해당 감지가 틀렸다고 확정한 것이 아니다.
- 실제 텍스트의 A→B→A, null 화자, 서로 다른 표시 이름, 불명 시간/시작 시각 역행, legacy humanEdited 분할은 보존한다. 종료 시각이 앞 토큰 안에 들어가는 부호는 같은 화자 문단에 포함하고, 재생 범위는 포함 Turn 시작 최솟값/종료 최댓값이다. 원시간은 바꾸지 않는다.
- 사람 문단의 원 ID 집합과 저장 텍스트, 명시적 수동 분절은 고정한다. 숨긴 marker 사이를 건너뛴 speech ID 집합도 문단 저장·검증·왕복을 지원한다. 실제 speech ID를 건너뛰거나 다른 화자를 포함하는 편집은 거부한다.
- 모든 엔진의 기존 Scripts 및 Markdown에 같은 `blocks()`를 적용한다. 재전사·데이터 마이그레이션·AI 호출은 필요 없다. 실제 두 시간대, 전체 문단 수, 원본6개 해시 및 합성 회귀 근거는 `versions/soniox-p2-alignment/plan.md` T-04.

### 문장 기준 연속 발화 (2026-09-11 T-18, 과거 기록)

- `reading-v4`는 아래 T-11/T-12의 분절 조건을 대체한다. 원 화자 ID·표시 이름이 같은 연속 speech는 기존 본문의 문장 종결부호까지 연결한다. 30초 길이와1.5초 간격 제한을 제거한다. 종결부호는 `.?!。？！` 및 뒤 닫는 따옴표/괄호를 인식하며 말줄임표·숫자만 있는 `3.`은 명확한 종결로 간주하지 않는다. 기존 Turn 내부 문장을 새로 쪼개거나 종결부호를 생성하지 않는다.
- 다른 화자의 실제 Turn, missingSpeech, null 화자, 불명/역행 시간, 별도 이름 수정, legacy humanEdited 분할은 보존한다. 같은 화자 Turn의 시작/끝이 앞으로 진행하면 시간 겹침 자체만으로 분절하지 않는다. 원 시간은 그대로 보존한다.
- 다른 화자 diarization이 앞 speech 종료 이상·뒤 speech 시작 미만의 시간에 새로 시작하면 텍스트가 없어도 A→B→A 경계를 지킨다. 이미 A와 겹쳐 말하던 화자의 종료·A Turn 내부의 겹말 시작·끝/경고만으로 인접한 A를 쪼개지 않는다. 모든 원 Turn·단어·이슈를 보존하고 노란 이벤트에서 접근할 수 있다.
- 기존 Script를 열 때와 Markdown 내보내기에서 같은 `blocks()`를 사용한다. 저장 데이터 마이그레이션·재전사·AI 호출은 필요 없다. 음성 인식·화자 판정·교정 정책은 변경하지 않는다. 검증은 plan T-18의 구 구현 실패/새 검사·실제 C 읽기 전후 수치와 파일 불변 기록을 따른다.

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

### 현행 기본 반영 정책 (2026-11-05 · usage-bundle1)

- `context-correction-6`: 수정(change) 하나마다 ① certain이 아니거나 미해결 인용과 겹치면 원문 유지 ② 원문에 그 수정 하나만 적용한 결과가 원문과 형식 동등하면 반영 ③ 인용과 대체의 보호 표식(숫자·단위·부정·조건 순)이 하나라도 다르면 원문 유지, 근거 «{분류} 표현이 바뀌는 수정이라 자동 반영하지 않았습니다. 원음으로 확인해 주세요.»(분류를 «·»로 이음) ④ 나머지 반영. 표식 정의는 `notes/usage-bundle1/usage-bundle1.src.html` §02-4 표와 단위 목록이며 신규 후보·한국어 실측 전이다. 새 응답 검증과 «저장된 AI 교정 반영» 재검증이 같은 규칙을 쓰고, 열기·과거 버전 조회는 저장된 판정을 바꾸지 않는다. 고유어 수사·낱자 한자어 수사·숫자 없는 단위·표식 글자 없는 의미 변경은 잡지 못한다.

### 이전 기본 반영 정책 (2026-09-13 사용자 승인)

- `context-correction-5`: ‘반영이 안되는 특별한 이유가 없으면 반영’ 요청에 따라 구조화된 수정은 **certain=true이고 미해결 인용과 겹치지 않으면 본문에 반영**한다. 아래 T-12/T-13의 형식/명시적 용어 대응 필수 조건을 대체한다. 참고자료와 문맥을 이용한 회사명·전문용어·오자·공백·구두점 교정에 별도 용어 등록을 요구하지 않는다.
- 원문 인용/occurrence/비중첩/전체 후보 재구성·Turn 소유 검증은 유지한다. 불확실한 수정과 미해결 범위는 원문을 유지하며 이유를 표시한다. 용어 대응은 검증된 경우 근거에 명시하지만 자동 반영의 필수 조건은 아니다. 원문 위치가 없는 legacy 응답 검증은 이전 형식 제한을 유지한다.
- 이는 AI 교정본의 표시 정책이며 실제 원음의 정답 확인을 뜻하지 않는다. 요약·윤문·필러/반복 삭제·숫자/단위/부정/조건의 의미 변경 금지는 프롬프트 계약에 유지한다. 원 normalized/시간/화자/사람 수정 우선순위는 유지한다.
- 저장된 구조화 후보는 현재 결과의 **저장된 AI 교정 반영**으로 로컬에서 재검증한다. 새 AI 호출/외부 전송 없이 새 correction ID와 AI 버전을 저장한다. engine에는 원 생성 엔진과 재반영 정책 버전을 함께 남긴다. 사람 소유/삭제 Turn은 제외하고 원 모델 텍스트와 후보 원문이 불일치하면 실패한다. 변경할 후보가 없으면 새 버전을 만들지 않는다.
- 로드/과거 버전 조회 자체로 기존 판정을 바꾸지 않는다. 이전 AI 버전의 바이트와 사람 수정은 보존한다. 동시 완료된 다른 AI 결과나 외부 파일 변경은 충돌로 차단하며, 같은 저장 actor의 최신 사람 수정은 다시 읽어 보존한다.
- 구간 정보에 자동 반영/일부 반영/원문 유지 상태와 수정별 반영·보류 사유를 표시한다. 본문·Markdown은 적용된 교정만 사용한다. 모델 원문 펼침은 항상 원 텍스트를 표시한다.

아래 2026-09-10 기록에서 v5와 충돌하는 자동 반영 제한은 과거 정책이며 나머지 보존·입출력 계약은 유지한다.

- `correction?`는 `ScriptCorrection` 별도 overlay. 상태(running/completed/failed), 엔진/알고리즘, 시작/완료, 입력 snapshot, Turn ID별 원문/제안/이유/자동 적용 여부, 화자 이름/자기소개 인용, 완료/전체 청크 수를 보존한다. 원 normalized 계약은 변경하지 않는다.
- 표시 우선순위: 사람이 입력한 turnNames/turnTexts → 적용된 AI 교정 → 기존 원문. `showsOriginal? = true`는 AI 교정 전 표시로 전환하며 사람 수정은 유지한다. 애매한 교정의 ‘교정안 적용/원문 유지’는 해당 Turn의 사람 선택으로 저장하며 AI 확인 표시를 해소한다(기존 음성 이슈는 별개). 이전 AI 교정 기록도 내부 immutable LibraryRevisions에 남는다.
- 현행 정책은 아래 T-13의 `context-correction-3`이며 형식 allowlist는 T-12에서 유지한다. 모든 소유 Turn ID가 순서대로 정확히 한 번 반환되어야 한다. 형식 동등성 비교는 유효한3자리 천단위 comma 양옆 ASCII 공백, 독립된 안되니까/안되는데/안해도의 안 뒤 공백, 숫자 뒤 조/억/만/천/백과 원 사이 공백에만 한정한다. 숫자 계산·단위 변환·부호/구두점 삭제·전체 공백 제거는 하지 않는다. 예: `1 ,000억→1,000억` 허용, `3 ,40억→3,40억` 보류. 이는 형식 정책이며 발화의 정답 검증은 아니다.
- 검증된 명시적 용어 대응 외의 새 어휘/약어/구두점 또는 다른 내부공백 변경은 원문 유지+후보/이유+노란 이벤트로 남긴다. LLM certain/reason·참고 자료에 후보가 존재한다는 사실만으로 허용하지 않는다. v1의 보호 토큰 동등 비교는 제거했다. 새 정책은 새 응답 검증에 적용하고 기존 저장 교정본의 적용 판정을 재해석하거나 사용자 수정본을 덮지 않는다.
- 새 응답이 앞뒤공백만 바꾸고 certain=true이면 edit를 만들지 않는다. certain=false이면 앞뒤공백 제안은 원문 문자열로 유지하고 불확실성/이유를 남긴다. 모델에는 변경 후보마다 이유를 요구하며, 앱은 자동/보류 판정 이유와 모델 설명을 구분해 기록한다. 이유가 있어도 독립 근거가 되는 것은 아니다.
- AI는 원음 대신 텍스트만 받는다. 화자 ID/타임스탬프/단어/누락 장벽을 수정하는 출력 필드는 없다. 이름은 참석자 목록(한 줄에 이름+소속/역할)과 명시적 자기소개 인용이 일치할 때만 매핑한다. 다른 청크의 이름 충돌은 자동 매핑을 제거한다.
- 5분 또는 100발화 또는 16k자에서 청크 경계를 만든다. 앞뒤 최대 20초/10발화 문맥은 읽기 전용, 소유 발화만 반환/검증한다. 숫자 진행률은 완료 청크/총 청크이며 서버 내부 토큰 진행률/오디오 비율이 아니다. 한 청크 요청 제한 300초, 프롬프트 512kB, 응답 2MB는 초기 자원 한도다.
- 참고 폴더는 사용자 선택 bookmark 아래 Markdown/plain-text만 읽는다. 숨김·패키지·symlink 제외, 탐색 300항목/깊이3/파일200kB, 관련 키워드 문단을 최대8파일/12k자로 발췌한다. 전문은 업로드하지 않고 확인창의 파일명/발췌 snapshot만 교정 입력으로 사용한다. SHA256은 읽은 바이트 기준. PDF/DOCX 및 OCR은 이번 구현 범위 밖이다.
- 자동 교정 기본 선택은 켜져 있지만 전송 동의는 아니다. 변환 확인창에서 음성→pyannote와 전사/입력/발췌→OpenAI를 함께 확인한 Run만 후속 자동 교정한다. 기존 Script는 AI 교정 버튼에서 별도 확인한다. 요청별로 추론이 이루어져 Codex 계정 사용량이 소모될 수 있다.
- CLI는 Process 인자 배열과 stdin 파일로 실행. 임시 디렉터리 0700/입력0600. stdout은 버리고 stderr는 줄 시작이 `ERROR: `·`error: `인 줄만 메모리에서 분류 표식과 대조한 뒤 버린다(줄당 64 KiB). 바이트 수만 기록한다. 시간 초과 중 네트워크 표식이 있었으면 네트워크로 분류한다(2026-11-05 usage-bundle1 · 실패 분류 8종 = 취소·실행 불가·시간 초과·인증·네트워크·설정·형식·미분류, 이전 «진단 stdout/stderr는 버린다»). 완료/실패 시 해당 임시 디렉터리를 정리한다. 앱 강제 종료 시 임시 잔여 가능. API 키/인증파일을 앱에서 읽거나 Git에 저장하지 않는다.
- 확인한 CLI 0.154.0: `--ignore-user-config --ignore-rules --ephemeral --sandbox read-only --skip-git-repo-check --model gpt-5.6-luna --output-schema --output-last-message`. `model_reasoning_effort=medium`; shell/unified exec/apps/plugins/hooks/agents/skills discovery/web/image/code-mode 비활성화. 앱은 사용자 전역 설정을 읽지 않으므로 이전 `기본 모델`의 실제 ID는 사후 확정할 수 없다. 새 교정만 GPT-5.6 Luna를 명시하며 저장 engine과 설정 화면에 모델명을 남긴다. 실제 사용자 전사 재추론·한국어 정답 정확도 비교는 미측정이다. 사용자 전체 Codex 설정/샌드박스/앱 signing entitlement를 바꾸지 않는다.
- 최초 시작 상태를 먼저 저장하며 모든 청크 성공 후 교정본을 한 번에 적용한다. 기존 성공 교정본의 재교정은 원문+사람 수정을 입력으로 다시 계산하고 새 성공 전까지 기존 성공본을 유지한다. 중단/오류는 원문/이전 성공본 유지, 자동 재호출 없음. 앱 재시작 시 남은 running 상태는 미완료로 표시하며 재승인 후 다시 시도한다. 저장은 최신 Script를 다시 읽어 AI layer만 병합해 사람 수정을 보존하고, 원 normalized 내용 변경 또는 외부 hash 충돌은 실패로 남긴다.
  - 시도 기록·이어서 교정 (2026-11-05 usage-bundle1): 진행 중이거나 끝나지 않은 교정은 스크립트 파일이 아니라 내부 저장소 `CorrectionAttempts/<스크립트 ID>.json`(스크립트당 1개, 원자 쓰기)에 둔다. 형식 버전·스크립트 ID·시도 ID·엔진·교정 입력 스냅숏·청크 계획 SHA256(AI 겹을 뺀 청크 목록 전체, 키 정렬 JSON)·청크별 SHA256·끝난 청크의 검증된 결과·실패 기록(최근 20건: 청크 번호·분류·종료 코드·경과 ms·stderr 바이트 수·시각)을 담고 원문·stderr 내용은 담지 않는다. 시작·청크 성공·실패·취소 때 쓰고, 모든 청크 결과를 저장한 직후와 새 교정 시작 때 지운다. 휴지통 이동·앱 재시작 뒤에도 남는다. «이어서 교정»은 현재 결과·남은 청크 1개 이상·다른 교정 없음·청크 계획 SHA256 일치·엔진 일치일 때만 보이고, 확인창(기본 «취소») 뒤 기록된 입력으로 남은 청크만 보낸다. 끝난 청크가 0개면 «같은 입력으로 다시 시도»다. 자동 재호출은 없다.
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

## 로컬 파일별 조회 실패 (2026-09-12)

- Speeches/Scripts 조회는 정상 항목과 파일별 오류를 함께 반환한다. 심볼릭 링크·손상·중복 ID 파일은 목록에서 제외하고 경로와 이유를 표시한다. 중복 ID는 어느 파일도 임의로 선택하지 않는다. 폴더 자체를 읽지 못하면 해당 이전 목록을 유지하며 다른 폴더 조회는 계속한다.
- 정상 Script 생성·교정은 무관한 손상 파일 때문에 중단하지 않는다. 대상 ID 중복, 대상 원문 변경, stale hash 저장·export 차단은 유지한다. 오류 파일은 삭제·자동 복구하거나 캐시의 이전 내용으로 대신 표시하지 않는다.
- 처리 이력 조회도 파일별로 격리하지만 실행·재사용은 해당 녹음의 이력이 완전해야 한다. 손상·누락·unsafe·중복·알 수 없는 Run 상태가 있으면 해당 녹음의 제출·재개를 차단한다. 정상 타 녹음은 사용할 수 있다. 접수 불명 상태를 초기화하지 않으며 기존 명시적 재전사 동의 정책을 유지한다.

## 운영 기본·검수 기록 (2026-09-11 최종안)

[operating-baseline.md](operating-baseline.md)가 현행 운영·실험·승격 계약이다. optional `reviewRecords`는 전후 텍스트/화자 표시·원음/Turn 범위·원음 확인·오류/표본 유형·능동 시간을 담는다. 구 파일의 nil은 미기록이다. `meetingTerms`는 녹음별 Soniox/Qwen 공통 용어. `sonioxSourceRunID`/`precisionSourceRunID`/`nemotronSourceRunID`는 결합 source Run이며 기존 Qwen source 필드는 유지한다. normalized v1의 optional asrSpeakerLabel, hybridSonioxPyannote, hybridSonioxNemotron(2026-10-30), provider_disagreement 확장은 원본 Soniox 후보를 보존한다.

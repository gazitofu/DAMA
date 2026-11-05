# DAMA 개선 방향 설계 검토 · advisor Fable (2026-11-05)

역할: 독립 설계 검토. 파일 수정 없음. repo 코드·계약(`CLAUDE.md`, `ssot/design/04·07`, `ssot/contracts/library-script.md`, `operating-baseline.md`, 각 주제의 코드 포인터)만 읽었고 사용자 데이터 폴더는 열지 않았다. 수치는 brief의 실측값을 그대로 쓴다. 외부 사실은 "미검증"으로 표시한다. 행 번호는 현재 작업 트리 기준.

---

## T1. 검수 이슈 숨김

**판정**: 조건부 동의. "데이터는 유지하고 화면만 끈다"에는 반대. 표시 단위와 등급을 바꾸는 쪽을 권한다.

**근거**
- 이슈는 토큰 단위로 생성된다. `Packages/DamaCore/Sources/DamaCore/SonioxPrecisionReconciler.swift:95–121`은 단어마다 invalid_timestamp·ambiguous_speaker·boundary_conflict·overlapping_speech를, 인접 토큰 쌍마다 provider_disagreement를 붙인다. Nemotron 경로도 같은 함수를 쓴다(`SonioxNemotronReconciler.swift:35`). severity는 전부 `.warning`, status는 전부 `.open` 고정(91–92행). Turn은 화자 연속 구간으로 합쳐지므로(149행 `speakerTurns`) "Turn의 68%"는 토큰 꼬리표가 문단에 모인 결과다. 5만 건은 문제 5만 개가 아니라 단위 불일치다.
- 묶음 계층은 이미 있다. `LibraryPresentation.swift:13, 45–47`의 `review-events-v2`(간격 1초·범위 30초)가 사건(event)으로 묶는다. brief에는 사건 수가 없다. 결정 단위는 이슈 수가 아니라 사건 수여야 한다.
- 해결 경로 부재 확인: `TranscriptEditing.swift:74`의 `acknowledgeIssue`를 호출하는 `ReviewShell`은 어디서도 생성되지 않고, App/UI에 `reviewed = true`를 쓰는 코드가 없다.
- Markdown도 같은 잡음을 낸다. `LibraryScript.swift:253–255`는 문단마다 이슈를 한 줄씩 내보낸다. 결과를 다른 AI에 넘기는 사용 방식에서 화면만 끄면 핵심 산출물의 잡음은 그대로다.

**놓친 위험·실패 경로**
- 전부 숨기면 음성 근거(diarization)에 기반한 유일한 E2 신호(missing_speech·unrepresented_speaker)를 버리고 텍스트만 보는 LLM 추정으로 대체하게 된다. LLM은 전사에 없는 짧은 끼어들기를 구조적으로 못 본다. 두 신호는 증거 종류가 달라 대체 관계가 아니다(INV-08의 취지).
- AI 목록이 유일한 채널이 되면 현재 교정 실패율 50%가 그대로 검수 불가율이 된다.
- 하이브리드 68% 대 Soniox 단독 21%는 하이브리드만 만드는 이슈 종류가 섞인 비교라 정확도로 읽으면 안 된다.
- invalid_timestamp 9,716건은 lexical 토큰의 nil/0길이 시간이다(102행, repairsWords 정책은 부호를 제외). 토큰의 약 20%가 0길이라면 공급자 응답이나 정규화의 결함 후보이며, 정렬 품질 문제라 숨길 게 아니라 조사할 대상이다.

**대안**
- 데이터 계약은 그대로, 읽기 정책만 `review-events-v3`로 올린다. 3등급: A = missing_speech(150ms 이상)·unrepresented_speaker·provider_disagreement, B = boundary_conflict·overlapping_speech, C = invalid_timestamp. 기본 화면은 문단당 A등급 사건 수만, B·C는 정보 패널에서 펼친다.
- Markdown 기본값은 A등급 사건만 쓰고 머리말에 "생략한 이슈: boundary_conflict N건 …" 한 줄을 남긴다. 불확실성을 지우지 않고 요약하므로 INV-10과 양립한다. `library-script.md`의 "Markdown에는 전체 이슈 기록" 문구 개정이 필요하다.
- AI 의심 목록은 별도 필드·별도 표시로 두고 음성 이슈와 섞지 않는다(T4 참조).

**결정 전에 확인·측정할 것**
- 스크립트별 `reviewEvents` 수와 등급별 분포. A등급 사건이 회의당 수십 건이면 LLM 호출 없이 목표를 이미 달성한다.
- 0길이 lexical 토큰의 출처(Soniox 원응답 vs 정규화).
- 문단 수정 73건이 이슈 표시 문단에서 일어났는지(이슈가 수정 위치를 예측하는지).

---

## T2a. 재전사 시 스크립트 보관 정책

**판정**: 반대(제시된 규칙 그대로). 후보 (b)·(c)는 조건부 동의.

**근거**
- 9.3GB의 원인은 재전사가 아니라 편집 저장이다. `FolderLibraryStore.swift:342–358, 368–381`의 `saveScript`는 호출마다 전체 바이트를 `LibraryRevisions`에 쓴다. 호출자는 제목·문단·삭제/취소·이름 변경·표시 전환·AI 상태 저장 전부다. 제목은 입력 멈춤 500ms마다 자동 저장된다(`App/ScriptEditingSession.swift:35–38`). 9/21 11–15시 339개 8.3GB는 이 경로로 설명된다. 재전사 산출물인 Script 파일은 38개, 중앙값 6.4MB라 합쳐도 수백 MB다.
- "앱에는 최신본만 표시"는 이미 구현돼 있다. `ScriptResultPresentation.primaryFiles`(66–90행)가 녹음당 한 행으로 접고 나머지는 "다른 결과 보기"에 둔다.
- 따라서 "재전사본 + 직전본만 보관"은 수백 MB를 줄이려고 INV-09, 경계 4(사람 수정 보존), "Soniox 비교본 항상 보존"을 깨는 규칙이다. 사람 수정 73건은 스크립트 5개에 몰려 있고 등록 화자·검수 기록도 그 파일 안에 있다.

**놓친 위험·실패 경로**
- revision 정리 시 `versions`가 참조하는 AI snapshot(`readVersion`, 454–465행, SHA256 대조)을 지우면 "다른 결과 보기"가 오류가 된다. `paragraphEdits.baseRevisionID`도 revision ID를 가리킨다.
- 델타 저장: `sourceFingerprint()`는 sortedKeys JSON의 SHA256이다(`ScriptParagraphEdit.swift:18–21`). Date·Double 직렬화가 OS나 Foundation 버전에 따라 달라지면 모든 델타가 복원 불가가 된다. 활성 파일이 손상되면 델타만으로는 아무것도 복원할 수 없다.
- 이전 Script 자동 삭제는 Nemotron 대 Soniox 승격 판정(operating-baseline)에 필요한 비교쌍을 없앤다.

**대안**
1. 보관 단위를 셋으로 나눈다. Script 파일(Scripts 폴더): 삭제 안 함. Run 원본(755MB): 유지. LibraryRevisions(내부): 정리 대상.
2. 1차, 형식 변경 없음: revision 보존 규칙을 "versions가 참조하는 것 + 스크립트당 최근 N개(초기 설계값 5) + 그 외 하루 1개"로 두고 저장 시점에 해시 검증 후 정리한다. 첫 정리는 사용자 확인 후 1회 수동. 내부 폴더라 Scripts 폴더 계약은 안 바뀐다.
3. 2차, 선택: revision 파일만 gzip. JSON 반복 키 특성상 5–10배가 예상되나 미측정. 델타보다 실패 경로가 적다.
4. 델타는 2·3으로 부족할 때만. 조건: transcript를 Run 폴더의 model + 저장된 fingerprint로 참조(재계산 금지), AI snapshot은 전체 사본 유지, 복원 실패 시 활성 파일을 정본으로 선언.
5. 제목 자동 저장은 디바운스 대신 포커스 이탈·Enter에서만 저장하고, 가능하면 revision 없이 활성 파일만 갱신한다. "저장은 revision 기록 후" 계약 문구 개정 필요.

**결정 전에 확인·측정할 것**
- 연속 revision 간 차이가 title/revisionID뿐인 비율(가설 검증).
- 현재 Script의 versions가 참조하는 revision 수.
- 표본 revision의 gzip 비율.

---

## T2b. 오래된 녹음 Google Drive 백업 후 로컬 삭제

**판정**: 목적(용량)에는 동의, 순서와 "앱이 자동 삭제"에는 반대. 묶음 3에서 빼고 대체안으로 바꾸기를 권한다.

**근거**
- 두 벌 중복은 설계다. 녹음 저장 직후 `recordingSaved`→`publishRecording`이 내부 `Sessions/<id>/audio/source`를 Speeches `<id>.dama-audio`로 복사한다(`App/LibraryWorkspace.swift:500–508`, `FolderLibraryStore.swift:200–213`). 재생은 내부 `analysis.wav`(`LibraryWorkspace.swift:453–455`), 재전사는 내부 세션(`prepareAnalysis`)을 쓴다. Speeches 사본은 앱 기능에 필요 없고 가시성·백업용이다. `trashSpeech` 안내 문구도 그렇게 말한다.
- 여유 253GB. 실측 속도(2개월 25시간)로 연 150시간 ≈ 내부 100GB + 사본 100GB. 중복만 없애도 2년 넘게 버틴다. Drive는 지금 필요한 기능이 아니다.
- 48kHz Float32는 시간당 약 690MB다. 마이크 입력 해상도는 24bit 이하라 Int24 ALAC는 실질 무손실에 가깝지만 비트 동일은 아니다. 변환하면 `AudioSource.sha256`·`sourceAudioSHA256`·분석 WAV 해시가 바뀌어 Soniox/P2/Nemotron 재사용 키와 `reviewRecords.audioSHA256`이 깨진다. 압축은 새 녹음부터만 가능하다.

**놓친 위험·실패 경로**
- "백업 후 삭제"는 백업이 아니라 이전이다. 삭제 순간 Drive가 유일본이 되고 계정 정지·동기화 사고·실수 삭제가 원본 손실로 직결된다. 경계 1과 양립하려면 "로컬 1벌은 남긴다"가 전제여야 한다.
- 타이머 자동 삭제는 이 앱에서 가장 위험한 동작이며 "되돌리기 어려운 삭제는 확인" 규율과 충돌한다.
- 로컬 파일이 사라지면 `scanSpeeches`(141–150행)는 폴더의 실파일만 목록화하므로 Speech 행 자체가 사라진다. "백업 위치만 인덱싱"은 목록 모델 변경이고, 이건 중복 제거에도 똑같이 필요하다.
- B안은 Drive 데스크톱 미설치이고, 온라인 전용 placeholder 파일을 샌드박스 앱이 읽다 실패하는 경로가 있다(미검증). A안은 OAuth 클라이언트 등록·토큰 보관·재개 가능 업로드·원격 체크섬 대조(Drive API의 SHA256 제공 여부 미검증)를 1인용 앱에 넣는 일이다.

**대안(순서)**
1. 목록 모델에 "Speeches 파일 없음 · 내부 보존본만" 상태를 추가한다.
2. 중복 제거: Speeches 사본을 사용자 선택으로 휴지통 이동(기존 `trashSpeech`), 내부본 유지. 즉시 약 12GB.
3. 새 녹음부터 Int24 ALAC 또는 Int16 PCM(설계값, 청취 비교 후 확정). 분석 WAV는 없으면 재생성하도록 바꾸고 삭제 허용(현재 `prepareAnalysis`는 해시 불일치를 오류로 낸다).
4. 외부 디스크/Drive로의 수동 "보관" 동작(건별 확인·해시 대조·로컬 1벌 유지). 자동 삭제는 넣지 않는다.

**결정 전에 확인·측정할 것**
- 세션별 내부/사본 크기와 양쪽 존재 여부.
- 오래된 세션의 재생·재전사 빈도(한 번도 안 열린 비율).
- 표본 청크의 ALAC·Int16 변환 비율과 청취 차이.

---

## T3. 녹음 제목 수정

**판정**: 동의. 입력 시점과 상속 규칙만 조정.

**근거**
- 마이크 녹음 제목은 `"<날짜 시각> 녹음"`으로 고정 생성된다(`Packages/DamaCore/Sources/DamaAudio/MicrophoneCapture.swift:57–58`). 불편은 실재한다. 묶음 폴더명은 `<UUID>.dama-audio`(`FolderLibraryStore.swift:202`)라 파일 이름은 원래 사람이 읽는 이름이 아니다. "파일 이름 유지"는 비용이 없다.
- 인덱스에 두는 것이 맞다. `library-index.json`은 이미 사용자 입력(`notes`)을 담는 사용자 데이터다. `LibrarySpeech.title`을 `var`로 바꾸고 `saveNotes`와 같은 저장 경로를 추가하면 된다.
- 묶음 manifest에 제목을 쓰면 안 된다. 인덱스 대조 키가 `fileURL + manifest 해시`라(150행) manifest가 바뀌면 재가져오기 경로로 들어가 `notes: ConversionNotes()`인 새 항목이 추가되고(176–180행) 기존 변환 입력이 목록에서 사라진다. 후보 방향은 이를 피하고 있으나 스펙에 명시해야 한다.

**놓친 위험·실패 경로**
- 녹음 종료 직후 입력 칸: 종료 시점은 finalizing→저장→publish가 도는 구간이다. 모달이 저장을 막거나 메뉴바 모드(`.accessory`)에서 창이 안 보일 수 있다. 종료 직후는 사용자가 바쁜 순간이라 입력률도 낮을 것이다.
- 인덱스는 Application Support 내부다. 재설치·폴더 이동 시 제목이 사라진다. notes도 같은 조건이라 수용 가능하지만 문구로 알린다.

**대안**
- 입력 시점을 둘로 둔다. 녹음 패널의 "제목(선택)" 필드는 녹음 전·중에 입력하고 저장 시 적용. Speech 상세 헤더는 스크립트 제목과 같은 인라인 편집(`InlineScriptText`)으로 언제든 수정. 종료 직후 모달은 두지 않는다.
- 상속: 새 Script는 생성 시점의 Speech 표시 제목을 받는다(`createScript`가 `speech.title`을 이미 쓴다, 337행). 기존 Script 제목은 소급 변경하지 않는다. Speech 제목을 바꿀 때 "연결된 Script N개 제목도 바꿀까요?"를 1회 묻는 선택 동작만 둔다.
- Speech 제목 저장은 Script revision을 만들지 않는다.

**결정 전에 확인·측정할 것**
- 없음. 기존 `library-index.json`의 Codable 호환(새 optional 필드)만 확인.

---

## T4. AI 교정 고도화 + 참고 폴더 재설계 + 입력란 정리

**판정**: 조건부 동의. 실패율 조치를 맨 앞으로, ⑤는 계약 결정 전까지 보류.

**근거**
- 실패 원인은 기록상 알 수 없다. `DamaManaged/CodexCorrectionClient.swift:47`이 stdout/stderr를 버리고 종료 코드·소요 시간도 남기지 않는다. 사용자 메시지는 고정 문구다(`App/CorrectionWorkspace.swift:134`).
- 청크 하나라도 실패하면 성공분을 전부 버린다(131행 `edits = []`). 12청크 중 4에서 정지한 건은 4청크분 사용량을 쓰고 아무것도 남기지 않았다. 재개 경로도 없다.
- 응답 검증은 id 순서·개수 완전 일치, 길이 3배 이내, `changes`/`unresolved` 필수다(`ScriptCorrection.swift:174–177`, `CodexCorrectionClient.swift:69`). 모델이 id 하나만 빠뜨려도 전체 실패다.
- 가설 순위: (1) 0번째 청크 실패 2회는 환경이다. 샌드박스 앱의 자식은 샌드박스를 상속하므로 홈의 `.codex/auth.json` 읽기, 로그 쓰기, CLI 갱신에 따른 `features.*` 설정 키 거부 중 하나일 가능성이 높다(미검증. 인자는 CLI 0.154.0 기준). (2) 중간 정지는 300초 timeout 또는 검증 실패.

**놓친 위험·실패 경로**
- ①의 전사 고빈도어는 오인식된 표기 그 자체라 참고 문서의 정표기와 부분 문자열로 안 맞는다(에스엠알 vs SMR). 재현율이 구조적으로 낮다.
- ② 기밀 폴더 478항목에 PDF·PPTX·DOCX를 더하면 전송 전 확인 부담이 커진다. XLSX는 발췌 가치가 없고 유출 면적만 넓힌다.
- ③ 브리프의 용어 대응·참석자가 틀리면 모든 청크에 같은 방향으로 번지고 이름 오매핑도 는다. 입력란을 안 쓰는 사용자가 브리프는 고칠지 불명이다. 안 고치면 LLM 출력이 LLM 입력이 되는 무검토 단계다.
- ⑤ 경계 4는 "문맥만으로 화자 귀속 추정은 하지 않는다"다. 표시만 해도 추정이다. ADR-010 후속은 "재귀속"만 금지해 해석이 갈린다. 사용자 결정과 계약 개정(새 필드, 음성 이슈와 분리, 인용 필수, 자동 반영 금지)이 먼저다.
- Claude CLI 동일 격리 조건: 도구 전부 비활성·프로젝트 설정/메모리 미로딩·세션 비영속·모델 고정·출력 스키마 강제. 비대화 모드·JSON 출력·도구 제한 옵션은 있지만 스키마 강제와 설정 소스 차단의 정확한 플래그는 미검증. 동의 문구의 "OpenAI"와 engine 문자열을 공급자명으로 일반화해야 한다.

**대안(순서)**
1. 진단: stderr를 0600 임시 파일로 받되 원문은 남기지 않고 종료 코드·소요 초·stderr 바이트 수·정규식 분류(인증/설정/네트워크/timeout/스키마)만 기록. 검증 실패도 규칙별로 센다.
2. 청크별 성공 결과를 `running` 상태에 누적 저장하고 "이어서 보정" 버튼을 둔다. "모든 청크 성공 후 적용"·"자동 재호출 없음"은 그대로다.
3. ①②는 로컬이라 진행하되 참고 폴더를 먼저 로컬 색인(제목·헤딩·고유명사, 읽은 바이트 상한)하고 양쪽 목록을 AI에 준다. 파일별 토글·발췌 보기(`UI/ScriptModalSheets.swift:115–119`) 유지.
4. ③의 용어 대응은 기존 `terms` 검증 경로(termID·동일 Turn 주제)로 넣고, 브리프 근거 변경은 `basis`에 "브리프"를 표기한다. 이름은 자기소개 인용 필수 유지.
5. Soniox 사전 맥락: 폴더 발췌 기본 OFF 동의. 참석자·용어까지 끄는 건 측정 없이 신호를 버리는 것이라 반대.

**결정 전에 확인·측정할 것**
- 같은 조건 10회 연속 실행으로 실패율·분류 재측정(진단 후).
- 회의 3건 표본: 적용된 변경의 원음 대조 정답률(operating-baseline 검수 기록 형식). 변경 수는 성공 지표가 아니다.
- `claude --help` 실측. 같은 원음 Soniox 맥락 ON/OFF 2 Run 비교(시간당 약 $0.10).

---

## T5. 설정 정리

**판정**: 동의. 단, 데이터 필드는 지우지 말 것.

**근거**
- `App/ProcessingWorkspace.swift:372, 378`: 기본값 `.pyannote`, 목록 [pyannote, soniox]. `UI/LibraryShell.swift:301–303, 333`: pyannote 3항목과 공식 문구.
- `MonthlyOperatingCost` 필드는 평가 JSON에 들어간다(operating-baseline). 구조체에서 지우면 과거 JSON과의 비교와 디코딩이 깨진다.

**놓친 위험·실패 경로**
- `KeychainStore.swift:8`은 qwen을 pyannote 서비스명으로 매핑한다. pyannote 키 삭제는 Qwen 경로 키도 지운다. 둘 다 퇴역이라 문제 없지만 문구에 적는다.
- `launch`의 `.sonioxPrecision → .pyannote` 매핑(294행)은 죽은 경로지만 재개 차단(`isRetired`)이 있으니 삭제보다 유지가 안전하다.

**대안**
- 키 화면: Soniox 기본·단독 목록. pyannote 키가 키체인에 있을 때만 "pyannote 키 삭제" 버튼을 보이고, 삭제 후 사라진다.
- 비용 시트: pyannote 3항목을 "퇴역 서비스(기록용)"로 접고 공식 문구를 "Soniox 사용액 + 기타"로 바꾼다. Nemotron은 현금 0이지만 시간·전력 미계상임을 한 줄 남긴다.

**결정 전에 확인·측정할 것**
- 저장된 pyannote 키 존재 여부(사용자 메모리: 2026-10-30 결제 안 함).

---

## 전체 우선순위 의견

- 순서 변경 제안: 묶음 1 = T5 → T3 → T4-0(실패 진단·청크 누적 저장, 제품 변경 없음) → T2a′(revision 정리·압축). T1은 "숨김"이 아니라 "사건 단위·등급 표시"로 바꿔 묶음 1 끝에 둔다. 묶음 2 = T4 ①②(로컬) → ③(측정 동반). 묶음 3 = T2b 대신 중복 제거·새 녹음 압축·수동 보관.
- 빼야 할 것: 타이머 자동 삭제, 이전 Script 자동 삭제, ⑤ 의심 목록(계약 결정 전).
- 빠진 주제:
  1. 측정 기반이 없다. 내보내기 횟수·검수 시간·정답률이 없으면 T1·T4의 효과를 영원히 판정할 수 없다. 내용 없이 횟수·시간만 세는 로컬 카운터부터.
  2. 0길이 lexical 토큰 9,716건은 정렬 품질 결함 후보라 별도 조사.
  3. 사람 수정이 5개 스크립트에 몰려 있고 reviewed Turn이 0이라는 건 검수 UI가 거의 안 쓰인다는 뜻이다. T1의 진짜 질문은 "사람이 뭘 보느냐"가 아니라 "내보내기를 받는 AI에 어떤 불확실성 신호를 남기느냐"다.
  4. 6분 이상 미전사 9건은 전사 진입 마찰 신호다. 범위 밖이지만 기록해 둘 가치가 있다.

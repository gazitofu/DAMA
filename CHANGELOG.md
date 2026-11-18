# Changelog

형식은 유닛 단위. `/ship`이 최상단에 엔트리를 추가한다. 안 잰 축을 반드시 함께 적는다.

## [v0.5.21] turn-continuity · 2026-11-18

Nemotron에 넣는 음성만 메모리에서 음량을 맞추고(`nemotron-input-level-v1`), 결합 `soniox-nemotron-word-v4`가 한 어절 안의 미상 조각을 그 어절의 단일 화자로 맞추고 어절 안 Turn을 잇는다. 읽기 `reading-v9`는 같은 ASR 라벨의 이웃 미상 어절을 한 문단으로 묶는다. AI 교정 `context-correction-8`은 일부 Turn이 빠진 응답을 받고, 실패 청크를 재시도하거나 원문 유지로 넘겨 «이어서 교정» 없이 끝난다. 모르는 화자는 null, 어절 사이 A → B → A 장벽, 모델 원문 · 사람 수정 보존은 그대로다. 앱 0.5.21(39).

같은 브랜치에 쌓인 이 유닛의 스펙 r1 · r2 · 게이트 ① 확정 문서 3커밋이 함께 main에 들어간다 (main 대비 18커밋 · 44파일 +3,463 / −214).

### Added
- `NemotronInputLevel` (DamaManaged): 0.1초 RMS의 90번째 백분위수(선형 보간)가 −20 dBFS가 되게 0–24 dB 이득, 무릎 0.7 소프트 리미터. 이득은 소수 2자리로 기록한 값을 그대로 적용하고, 0이면 표본을 건드리지 않는다. 분석 WAV · 원본 · Soniox 입력은 바꾸지 않는다. Nemotron 자식 meta에 `inputLevel` (version · gainDb · p90Dbfs), 없으면 키 생략.
- 교정 규칙 `missing`(응답에서 빠진 Turn) · `chunk`(재시도 소진으로 건너뛴 청크의 Turn) = «응답 없음». 형식 실패 세부 `CorrectionFormatDetail` 8종(noOutput · tooLarge · decode · missingArrays · idDuplicate · idUnknown · idOrder · idTooFew). 실패 기록 선택 키 `retry` · `detail` · `expectedTurns` · `returnedTurns`. 완료한 교정에 `failures`(최근 20건, 원문 없음).
- 문구(`ssot/tone/turn-continuity.md` 6–11): 구간 정보 «원문 유지 · AI 응답 없음», 완료 띠 «AI 응답을 받지 못한 {M}개 원구간은 원문을 유지했습니다.», Markdown «- 응답 없음으로 원문 유지: {M}개 원구간» · «> AI 응답 없음: …», 진행 줄 « · 응답 다시 받는 중 ({r}/2)». 응답 없음 0이면 현행과 같다.
- 측정 도구 `scripts/nemotron-combine`: `NemotronAppRun` 확률 · meta 저장, `NemotronV4Check` (replay · measure), `level_compare.py`. 읽기 전용 · 네트워크 0.

### Changed
- 결합 v3 → v4 (새 Run만): 어절 안 배정 화자가 한 명이면 미배정 조각을 그 화자로(근거 구간 합침, `alignmentScore` null), 같은 어절의 같은 화자 토큰 사이에서는 다른 화자 구간을 Turn 장벽으로 보지 않음, 같은 어절 · 순번 연속 · 같은 ASR 라벨의 미상 토큰은 한 Turn. 누락 marker · 중단 이슈는 어절 안에서도 장벽. 저장된 v1–v3 Run은 저장 버전으로 재개 · 재생한다.
- 계약: INV-06 단서(`ssot/design/04` :46 · :117, v4 어절 안 예외), `TranscriptValidator`도 같은 단서. `operating-baseline.md` Nemotron 재사용 키에 입력 음량 버전 추가 · v4 문장. `library-script.md` 8곳(v9 · v8 엔진 · 규칙 코드 · 실패 기록). `transcript.v1.schema.json` · `DomainContracts.swift` 변경 없음.
- 읽기 v8 → v9: 원문 공백 보존 엔진에서 앞뒤 미상 어절이 ASR 라벨이 같고, 사이가 문장부호뿐이며, 간격 ≤ 300 ms(외부 설계 초기값)면 한 «화자 미확정» 문단. 기존 결과 읽기에도 적용. Markdown 머리 «- 문단 표시: reading-v9».
- 교정 v7 → v8: 받은 Turn이 입력의 부분열이고 ⌈n/2⌉개 이상이면 받고, 빠진 Turn은 `missing`. 청크당 재시도 최대 2(형식 실패 즉시 · 시간 초과 · 네트워크 · 미분류는 5초 뒤), 소진하면 그 청크를 원문 유지로 건너뛰고, 연속 2청크 건너뜀이면 실패. 인증 · 설정 · 실행 불가 · 취소는 즉시 실패. 검증 실패 수(완료 띠 · Markdown 문구 4)는 검증 6종만 센다.
- 골든: Nemotron 15 → 20키(v4 5개), Markdown 지문 76키 이동(머리 버전 줄), 정규화 1키 읽기 지문 이동(v9 이음). normalized 지문 76/76 불변.

### Fixed
- 한 어절 안에서 Nemotron 화자 구간이 잠깐 끊기면 미상 조각과 Turn 경계가 생기던 것. 실데이터 6개 녹음(저장 Soniox 원응답 + 새 확률)에서 어절 중간 Turn 경계 175 · 374 · 567 · 305 · 995 · 1,611 → 7 · 39 · 61 · 44 · 76 · 67.
- 교정 응답에서 Turn 몇 개가 빠지거나 청크 하나가 형식 실패해 교정이 멈추고 «이어서 교정»을 눌러야 하던 것.

### 결정
- 게이트 ① D-01–D-05 전부 ⓐ(어절 안 조각 맞춤 · 읽기 v9 · INV-06 어절 안 단서 · 교정 재시도 · 건너뜀 · 입력 음량 v1). /plan D-NN 없음.
- 게이트 ② AC-17 실행 조건 문언 정정(사용자 승인): 실행 = 사용자 선택 46.6분 결합본, Soniox는 참고 발췌 3 → 0으로 context가 달라 동의 후 새 전송(`operating-baseline.md:38`대로). 같은 Soniox 응답을 고정한 비교가 아니다.

### 실측
- check.sh `run-20261117T113241Z-l5BPo4`(HEAD `b936d65`, /ship 재실행): 계약 31 · byte-exact · SmokeCheck · swift test 408 실행 = 406 통과 + skipped 2(환경변수 게이트, 기준선과 같은 2개) · 실패 0 · xcodebuild Debug PASS. 기준선 362 → 408(신규 46, 사라진 테스트 이름 0). 역뮤테이션 11종 전부 붉음, 복원 해시 일치.
- QA GPT-6.1-sol 판정 A · B · R · C · R2: AC-01–17 통과.
- 실데이터 측정(이 Mac, 읽기 전용, 네트워크 0, 6개 녹음): 이득 0.00 · 22.97 · 17.06 · 13.83 · 11.41 · 18.44 dB, 이득 0인 9분 녹음 확률 = 저장 확률 바이트 동일. 무음 판정 단어 비율(85 · 47 · 141분) 3.13 → 0.87 · 0.94 → 0.57 · 6.04 → 5.16 %. 저장 v3 Run 6/6 재생 바이트 동일. v4 결합 계약 6/6. 화자 미확정 문단(읽기 v9 기준) 25 → 17 · 20 → 4 · 45 → 18 · 52 → 16 · 94 → 44 · 357 → 285.
- 설치 앱 0.5.21(39): 실행 Bundle(`lsappinfo` Version 39 · Info.plist 0.5.21) 확인, 메뉴바 툴팁 사용자 관측. 백업 0.5.20(38) 파일 수 · 트리 SHA256 대조.
- 게이트 ② 실데이터 1건(사용자 실행, `8EF2322B` 46.6분): 새 parent v4 · 자식 meta `inputLevel` 17.06 dB(설치 앱 확률 = 측정 도구 확률 바이트 동일) · 저장 v4 재생 바이트 동일 · 교정 completed 10/10, 이어서 교정 없음 · 재시도 2(청크 1/10 형식 idUnknown, 기대 100에 반환 106 · 110, 세 번째 성공) · 건너뜀 0 · 원문 유지 `text` 4 · `quote` 2, 응답 없음 0 · 완료 띠 문구(N = 6) · 진행 줄 재시도 글자 사용자 관측 · 화자 미확정 문단 45(v3 현행) → 23.

### 안 잰 축
- 화자 배정 정확도(E1 · E2): 원음 대조 없음. 실데이터 지표(Turn · 문단 · 미배정 수)는 정확도가 아니다. 이 릴리스는 화자 분리 정확도에 대해 아무것도 주장하지 않는다.
- 관측된 악화(F-05, 원인 미분해): 141분 녹음 미배정 lexical 1,316 → 1,428개(3.69 → 4.01 %), 어절 하나가 두 화자 문단으로 갈린 경계 47분 9 → 16 · 80분 27 → 32, 85분 녹음 활성 채널 5 → 7.
- 게이트 ② 비교는 Soniox 응답이 새것이라 v4 효과와 섞여 있다. Soniox 재사용 경로는 이번 게이트에서 검증하지 않았다.
- 교정 품질 · 반환 Turn이 입력보다 많은 응답의 빈도와 원인(F-07) · «형식» 하위 원인 분포.
- 응답 없음 구간 정보 · Markdown 문단 줄의 실화면(코드 대조까지, 실데이터 1건은 응답 없음 0) · 새 문장 키보드 · VoiceOver · 다른 Mac.
- 141분 녹음 청취 밖 무음 81–87 %의 원인 · 입력 음량 v1 상수(−20 dBFS · 24 dB · 0.7)의 최적성(신규 후보값).

## [v0.5.20] correction-turn-isolation · 2026-11-09

AI 교정 응답에서 검증을 통과하지 못한 Turn은 그 Turn만 원문을 유지하고 `rejectedTurns`(Turn ID · 규칙 코드)에 남긴다. 같은 청크의 다른 Turn은 v6 판정대로 반영한다. 응답을 입력과 짝지을 수 없는 실패(해독 실패 · Turn id 순서/개수 불일치 · `changes`/`unresolved` 누락)만 청크 실패(형식)로 남는다. 엔진 `context-correction-7`. 앱 0.5.20(38).

같은 브랜치에 쌓인 이 유닛의 입력(사용 복기 묶음 3 측정 문서 4커밋 · 환경변수 게이트 진단 테스트 `CorrectionFormatProbeTests` 1커밋)이 함께 main에 들어간다.

### Added
- `ScriptCorrection.rejectedTurns`: `CorrectionRejectedTurn`(turnID · 규칙 `quote`·`overlap`·`text`·`limit`·`reason`·`other`), 없으면 키 생략. 저장 검증: 발화 밖 turnID · 같은 turnID 중복 · edits와 겹침은 손상(`invalidScript`), 모르는 규칙은 해독 실패. 기존 스크립트 파일은 바이트 그대로 읽고 다시 쓴다.
- 시도 기록 청크 결과 `rejected`(형식 버전 1 유지, 기존 기록 그대로 읽음). 이어서 교정 뒤 합친 목록은 한 번에 끝낸 결과와 같은 개수·순서.
- 문구(`ssot/tone/correction-turn-isolation.md` 1–5 · 2a, DamaCore `CorrectionRejectionText` 1곳): 구간 정보 «원문 유지 · AI 응답 검증 실패» + «AI 응답이 이 문단의 원문과 맞지 않아 쓰지 않았습니다.»(2개 이상이면 « ({k}개 원구간)»), 완료 띠 덧붙임 «AI 응답이 원문과 맞지 않은 {N}개 원구간은 원문을 유지했습니다.», Markdown 머리 줄 «- 검증 실패로 원문 유지: {N}개 원구간» · 문단 줄 «> AI 검증 실패: …». 버린 원구간이 0이면 현행과 같다.
- 환경변수 게이트 진단 테스트 `CorrectionFormatProbeTests`(`DAMA_PROBE_*`가 없으면 skip, 상시 테스트는 합성 분류기 1개).

### Changed
- 응답 검증 `context-correction-6` → `context-correction-7`: 인용 없음 · 위치 오류 · 겹침 · text 재구성 불일치 · 길이/개수 상한 · 미해결 이유 공백은 그 Turn의 실패(첫 위반 1개 기록). 수정별 반영 판정과 의미 보호는 v6 그대로.
- 저장된 AI 교정 반영(재반영)이 `rejectedTurns`를 그대로 옮긴다. 저장 재검증의 오류 형식은 현행 `invalidScript` 그대로.
- 계약(D-01): `ssot/contracts/library-script.md` 5곳(v7 줄 신설 · 응답 실패 문단 · overlay 보존 목록 · 재반영 · 시도 기록). `transcript.v1.schema.json` · `DomainContracts.swift` 변경 없음.
- 합성 QA fixture(`scripts/ReadingUIFixture.swift`)에 버린 원구간 추가.

### Fixed
- Turn 하나의 검증 실패로 청크 전체를 버려 교정이 형식 실패로 멈추던 것. 묶음 3 진단(140.6분 결합본 청크 0, 3회)에서 해독 · id · 배열 실패 0/3, Turn 13개 중 1–2개 규칙 위반으로 3/3 청크 폐기였다.

### 결정
- 게이트 ① D-01 ⓐ 엔진 v7 + 계약 문안 5곳 · D-02 ⓐ `rejectedTurns`.
- 게이트 ② AC-09 «미검증으로 닫기»(F-03) · AC-12 «미검증으로 닫고 built»(D-1 · F-06). AC-12 대상은 사용자 선택: 조건 «30–40분 Soniox + Nemotron 결합본» 실데이터 0개 → 28.0분 Soniox + pyannote 결합본.

### 실측
- check.sh `run-20261109T023854Z-yYAlik`(HEAD `ae0b1db`, /ship 재실행): 계약 31 · byte-exact · SmokeCheck · swift test 362 실행 = 360 통과 + skipped 2(환경변수 게이트) · 실패 0(Core 212 · Audio 84 · Managed 66) · xcodebuild Debug PASS. 기준선 343 + 2 → 360 + 2(신규 17, 사라진 테스트 이름 0, 가드 이동 8단정). 역뮤테이션 4종 붉음 23 · 2 · 1 · 2, 복원 해시 일치.
- Markdown 버린 원구간 0: SHA256 `5dc04eb6…` 1,564 B = 변경 전 코드 출력.
- QA GPT-6.1-sol 판정 A · A2 · D: AC-01–08 · AC-10 통과.
- 설치 앱 0.5.20(38): 실행 Bundle(`lsappinfo` Version 38 · Info.plist 0.5.20) 확인, 메뉴바 툴팁은 사용자 관측.
- 실데이터 1건(사용자 실행, `57C3F857` 28.0분 Soniox + pyannote, 발화 Turn 765): 1차 실행에서 청크 0의 Turn 1개 `text` 격리 + 편집 2 반영(v6였다면 청크 전체 폐기), 2번째 청크 형식 실패 → 이어서 교정 2회 → completed 8/8 · edits 28 · rejectedTurns 10(`text` 6 · `quote` 4, 전부 발화 Turn · edits와 겹침 0) · transcript 해시 8판 + 현재 동일. 완료 띠 문구 3(N = 10) 사용자 관측.

### 안 잰 축
- 구간 정보 새 문구 실화면(F-03): 배치 · 굵기 · k = 1 / ≥ 2 · 원문 보기 상태. 코드 대조(QA A)만. 원문 보기 전환 컨트롤은 현행 UI에 없다.
- 실데이터 두 번째 실패(5/8)의 분류 · 종료 코드 · 경과(D-1 · F-06): 교정이 완료되면 시도 기록이 실패 이력째 지워지는 계약(`library-script.md:207`)으로 소실.
- 실데이터 형식 실패 2회의 하위 원인(F-05): 응답 원문을 설계상 버려 기록 없음.
- 설치 앱 0.5.20 1회 종료(11-07 20:54, 크래시 리포트 0, 원인 미확정 · F-04). 11-09 재실행 정상.
- 교정 품질과 원음 대조 · 인용 불일치 원인 · Turn 실패율 변화(묶음 3 ①) · Nemotron 결합본과 30–40분 조건 · 새 문장 키보드 · VoiceOver · 다른 공급자 · 다른 Mac.
- 실패 분류 테스트 1건의 시간 경쟁 실패 1회 관측(F-02, 이 테스트가 든 check 40회 중 1회, 재실행 PASS).
- 한국어 화자 분리 정확도(이 유닛 범위 밖). 정확한 화자 분리를 주장하지 않는다.

## [v0.5.19] usage-bundle2 · 2026-11-07

사용 복기 묶음 2(T2a). 녹음마다 최근 결과 2세대와 사람이 고친 결과를 남기고, 그 밖의 이전 결과 스크립트는 휴지통으로 옮긴다. 대표 결과는 가장 늦은 결과다. 스크립트를 지우면 그 내부 수정 이력과 교정 시도 기록도 함께 지운다. 수정 이력은 스크립트별 폴더에 raw DEFLATE로 저장하고, 기존분은 설정 «저장 공간 정리…»로 한 번 옮긴다. 녹음 원음과 전사 원응답은 지우지 않는다. 앱 0.5.19(37).

### Added
- 녹음별 결과 보관 `ScriptRetention`: 세대 = 자식이 아닌 결과 + 그 Run이 가리키는 Soniox 자식(재사용 자식은 가리키는 세대 모두에 소속). 최근 2세대 보관(사용자 결정값, 상수 1곳), 사람이 고친 결과는 세대와 무관하게 보관. 새 결과를 처리 완료로 새로 저장한 직후 그 녹음만 정리한다. 열린 스크립트·저장 중·AI 교정 중인 결과와 실행 기록을 읽지 못한 녹음은 건너뛴다. 완료 문장에 휴지통으로 옮긴 수·실패 수.
- 재전사 확인창에 정리될 이전 결과 수 N(실제 정리와 같은 계산 함수). N = 0이면 현행 문구 그대로.
- 사람 수정 판정 `hasHumanEdits`(9필드 + `transcript.revision.humanEdited` + word `editedText`), 요약 캐시 `summaryVersion` 2.
- 설정 «저장 공간» 절: 내부 수정 이력 크기, «저장 공간 정리…» = 확인(쓰기 0) → 확인창(기본 «취소») → 보관 정리 · 고아 이력 삭제 · 구 배치 압축 이전 · 고아 시도 기록 삭제 → 완료 크기 «{전} → {후}». 건별 기록 `storage-cleanup-log.jsonl`, 중단 뒤 다시 실행하면 중단 없는 정리와 같은 최종 상태.

### Changed
- 대표 결과: 엔진 등급 우선 → 가장 늦은 createdAt(같으면 id 사전순 앞).
- 수정 이력 배치: `LibraryRevisions/<revisionID>.dama.json` → `LibraryRevisions/<스크립트 ID>/<revisionID>.dama.json.deflate`(raw DEFLATE, Apple zlib level 5). 읽기는 새 배치, 없으면 구 배치. 버전 sha256은 압축을 푼 바이트 기준. Scripts 활성 파일은 비압축 그대로.
- Script 삭제: 휴지통 이동 뒤 그 스크립트의 이력 폴더·시도 기록도 지운다. 확인창 설명과 이력 삭제 실패 시 완료 문장 변경.
- 시도 기록 경로 규칙을 DamaCore 한 곳으로 옮김.
- 계약(D-04): `CLAUDE.md` 최상위 경계 6, `ssot/contracts/library-script.md` «결과 보관» 절 신설 외 8곳, `ssot/contracts/operating-baseline.md:73`.

### Fixed
- `scripts/check.sh`: 소문자 cwd에서 실행하면 모듈 캐시가 두 경로 표기로 갈려 Swift 계약·xcodebuild가 실패하던 것(F-01).

### 결정
- 게이트 ① D-01 ⓐ 휴지통 이동(영구 삭제 기각) · D-02 ⓐ 재측정(지금 규칙으로 지울 스크립트 0)을 알고도 자동 정리 포함 · D-03 ⓐ 스크립트별 폴더 + 압축 · D-04 ⓐ 계약 10곳 개정.
- 게이트 ② F-04 · F-05 문언 정정(권고대로) · AC-10 «지금 상태로 닫기»(실화면 미검증 9 = F-07) · F-01 승인·해소.

### 실측
- check.sh `run-20261106T200901Z-1TuaQk`(HEAD `2d23b67`): 계약 31 · byte-exact · SmokeCheck · swift test 342 통과 + skipped 1(환경변수 게이트 실데이터 모의) · xcodebuild Debug PASS. 기준선 303 → 343, 기존 테스트 삭제 0, 가드 이동 3곳, 역뮤테이션 11종 붉음.
- QA GPT-6.1-sol 판정 A–D(재판정 포함 8회) · F01: AC-01–AC-09 · AC-11–AC-13 통과, AC-10은 사용자 결정으로 닫음.
- 설치 앱 0.5.19(37) 실행 Bundle·툴팁 확인. 사용자 실행 실데이터 정리 1회(2026-11-07 00:30:58–00:32:06 KST): 내부 수정 이력 574개 10,002,006,178 B → 512개 651,849,241 B(고아 62 삭제 · 512 압축 이전 · 실패 0). 풀어서 SHA256 512/512 일치, `Sessions/` 2,918파일 · Scripts 38 SHA256 불변, AI 버전 7/7 열림.

### 안 잰 축
- 실제 재전사 완료 뒤 자동 정리 실행과 재전사 확인창 실화면(합성 테스트와 코드 대조만). 현재 실데이터는 지금 규칙상 지울 스크립트 0.
- 설정 «저장 공간» 절 실화면 9항목(F-07): 다른 작업 중 꺼짐 · 녹음 중 켜짐 · 확인창 문구 13·15 분기 · 기본 «취소» · 진행 중 조작 차단 · 완료 조건부 문장 · 0 바이트 → «정리할 항목이 없습니다.» · 확인창 픽셀 · fixture Scripts 수.
- 실데이터 정리의 확인창 값·완료 크기 줄은 사용자 육안만(메인 캡처 없음).
- 작은 이력 수천 개 정리 중 접근성 응답 지연 관측 1회(F-08, 계측 안 함). 재사용 Soniox 자식이 정리된 뒤 다시 재사용되면 Soniox 단독 스크립트가 다시 만들어지지 않는 경로(F-03, 실데이터 해당 0).
- 앱 안 정리 소요 시간 · LZFSE/LZMA 비율 · Finder 휴지통 비움 시점 · 새 설정 절 키보드·VoiceOver · 다른 Mac.
- 한국어 화자 분리 정확도(이 유닛 범위 밖). 정확한 화자 분리를 주장하지 않는다.

## [v0.5.18] usage-bundle1 · 2026-11-06

사용 복기 묶음 1(T1 · T3 · T5 · T4-1 · T4-2 + T2a-5). 자동 경고는 화면·Markdown 문단에서 걷고 데이터는 보존한다. 녹음 표시 제목을 녹음과 연결 스크립트가 공유한다. 퇴역 pyannote 설정을 접는다. AI 교정 실패는 원인을 분류하고 진행분을 남겨 이어서 보낼 수 있다. 숫자·단위·부정·조건을 바꾸는 교정은 자동 반영하지 않는다. 앱 0.5.18(36).

이 머지는 로컬 main(2026-09-09) 이후 처음이라, 같은 브랜치(`work/m0-fixture-review`)에 쌓인 이전 유닛 16개가 함께 main에 들어간다. 각 유닛의 범위·검증은 해당 `versions/{유닛}/plan.md`가 정본이다. 그중 status building 5개(library-workspace · m0-fixture-review · m1-recording-safety · m2-managed-processing · nemotron-diarization)는 완료를 뜻하지 않는다.

### Added
- 녹음 표시 제목 `displayTitle`(인덱스 한 곳): 녹음·연결 스크립트 목록·읽기·확인창·Markdown·내보내기 파일 이름이 같은 제목을 쓴다. Enter·입력칸 이탈 때만 저장(0.5초 자동 저장 없음), 녹음 직후 제목 입력창(한 번에 하나, Enter 저장·Esc 나중에).
- AI 교정 시도 기록 `CorrectionAttempts/`와 «이어서 교정 (k/n)» / «같은 입력으로 다시 시도»(확인창 기본 «취소»). 실패 8분류(취소·실행 불가·시간 초과·로그인·연결·설정·형식·미분류)별 하단 줄과 안내 띠. stderr는 줄 시작 `ERROR: `·`error: ` 줄만 메모리에서 대조하고 내용은 기록하지 않는다.
- 의미 보호 `context-correction-6`: 숫자·단위·부정·조건 표현이 바뀌는 수정은 원문 유지 + 보류 근거.
- 월 비용 «AI CLI 구독료» 항목과 새 공식(퇴역 pyannote는 기록용 접힘).
- 합성 QA 앱 전용 창 이미지 장치(Debug · ReadingQA Bundle · fixture 인자일 때만)와 합성 fixture 확장.

### Changed
- 읽기 화면 문단의 «주의» 버튼 제거. 녹음 중단·일부 결과는 문단 아래 ⚠ 경고 줄, 자동 경고 8종은 구간 정보 «자동 경고 N건» 접힘(기본 닫힘).
- Markdown: 문단별 `> 검수:` 줄 제거, 머리말 검수 줄에 자동 경고 총수·종류별 건수(4형식), 녹음 중단·일부 결과는 머리말과 해당 문단 아래.
- 설정 API 키: 서비스 선택 제거, «Soniox API 키». 저장된 pyannote 키가 있을 때만 안내 줄과 «pyannote 키 삭제».
- 한글 제목: 반쪽 글자는 저장하지 않고, 입력기가 조합 중 Enter로 확정한 값을 한 번 Enter로 저장(2026-11-06 사용자 결정).

### Fixed
- 설정 API 키 머리·저장·삭제 문구가 «Soniox 단독 (비교)»로 나오던 것.
- 남아 있던 작업 공간 안내가 새 교정 실패 안내 띠를 가리던 것.

### 결정
- 게이트 ① D-01 ⓐ(시간 초과 중 네트워크 표식 → 네트워크) · D-02 ⓐ(줄 단위 표식 대조).
- 게이트 ② F-04 · F-05 · F-06 · F-07 · F-10 · F-11 · F-13 권고대로, 한글 한 번 Enter 저장.

### 실측
- check.sh `run-20261105T154341Z-A1NzJx`: 계약 31 · byte-exact · SmokeCheck · swift test Core 199 / Audio 44 / Managed 60 · xcodebuild Debug PASS, SKIP 0.
- QA GPT-6.1-sol 판정 A–J, AC-01–AC-16 통과. 실기기(설치 앱): pyannote 키 삭제, 가짜 CLI로 교정 실패 띠 8종(스크립트 파일 쓰기 0·외부 전송 0), 실제 결합본 1,411문단 순회 «주의» 0, 사용자 녹음·전사 1회와 제목 연결.
- 설치 앱 0.5.18(36) 실행 Bundle·툴팁 확인.

### 안 잰 축
- 실제 Codex 교정의 성공·이어하기 실행(합성 테스트만), 만료 토큰 때의 실제 인증 문구.
- 라이트 모드·다른 창 크기·VoiceOver 청취, 다른 Mac·공증.
- 내보낸 Markdown 파일 저장 여정(NSSavePanel), 장시간 녹음 성능.
- 한국어 화자 분리 정확도(이 유닛 범위 밖). 정확한 화자 분리를 주장하지 않는다.

## [Unreleased]

코드 없음. 설계 정리만 완료.

### Added (2026-09-09 · 프로젝트 개설)

- 외부 LLM 설계 패키지(가칭 SpeakerScript v1.0)를 Dama로 개칭·채택. `ssot/design/01~08` + `ssot/design/00_README.md`(읽는 순서·채택 범위·신뢰 등급).
- `ssot/api/pyannote-verified.md`: pyannote API 계약을 1차 출처와 대조한 실검증 기록. 어긋난 항목 0. 문서에 없던 endpoint 5종과 미확인 6항목, 요금표 기재.
- `ssot/contracts/`: `transcript.v1.schema.json`(`urn:dama:transcript:1`) · `DomainContracts.swift`.
- `ssot/dev.md`: 환경 실측 · backpressure · 검증 층위 · 외부 전제.
- `scripts/check.sh`: backpressure 4단계 (계약 29건 · Swift 계약 · swift test · xcodebuild).
- `CLAUDE.md` · `.claude/commands/{spec,plan,build,ship}.md` · `ssot/doc-template/`(GAIA 이식).

### 실측

macOS 26.6.2 · Xcode 26.6 · Swift 6.3.3 · arm64. 계약 29/29 통과, Swift 6 컴파일·왕복·명시적 null 보존 통과.

### 안 잰 축

macOS 앱 빌드, 마이크·권한·TCC, 코드 서명, pyannote 실호출, WhisperKit 추론, 한국어 화자 분리 정확도, 장시간 녹음 품질. 전부 미착수.

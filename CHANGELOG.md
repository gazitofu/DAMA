# Changelog

형식은 유닛 단위. `/ship`이 최상단에 엔트리를 추가한다. 안 잰 축을 반드시 함께 적는다.

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

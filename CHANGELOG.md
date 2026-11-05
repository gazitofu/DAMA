# Changelog

형식은 유닛 단위. `/ship`이 최상단에 엔트리를 추가한다. 안 잰 축을 반드시 함께 적는다.

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

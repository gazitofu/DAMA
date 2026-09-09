# Changelog

형식은 유닛 단위. `/ship`이 최상단에 엔트리를 추가한다. 안 잰 축을 반드시 함께 적는다.

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

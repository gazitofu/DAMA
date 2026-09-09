# Dama (담아)

macOS 메뉴바 원클릭 녹음 → 화자별 원문 스크립트 → 원음 검수 → JSON/TXT 내보내기.
요약·회의록 생성은 하지 않는다. 화자 귀속의 정확성과 불확실성 표시가 목적이다.

**현재 상태: 설계 정리 완료, 코드 없음.** 이 저장소에는 아직 `.xcodeproj`도 실행 가능한 `.app`도 없다.

## 무엇이 들어 있나

```
CLAUDE.md              프로젝트 최상위 규율 (구현 전 필독)
ssot/design/           설계 정본 8종 + 읽는 순서(00_README.md)
ssot/api/              pyannote API 1차 출처 실검증 기록
ssot/contracts/        JSON Schema + Swift 데이터 계약
ssot/dev.md            환경 실측 · backpressure · 검증 층위
ssot/doc-template/     /spec 문서 양식
fixtures/              합성 fixture 3종 (실제 음성·API 응답 아님)
scripts/check.sh       backpressure 4단계
scripts/validate_contracts.py   합성 계약·회귀 29건
scripts/SmokeCheck.swift        Swift 계약 컴파일·왕복 검사
```

## 검사 실행

음성을 업로드하지 않고 유료 API를 호출하지 않는다.

```sh
bash scripts/check.sh
```

2026-09-09 이 Mac(macOS 26.6.2 · Xcode 26.6 · Swift 6.3.3 · arm64) 실측:
계약 29/29 통과, Swift 6 계약 컴파일·왕복 통과, `swift test`·`xcodebuild`는 프로젝트 미생성으로 SKIP.

## 출처

설계 원안은 외부 LLM이 만든 패키지(2026-09-09 수령)이며 손대지 않은 원본은
`~/Vault/appdev/Dama/queries/2026-09-09-external-design-package/`에 있다.
채택 범위·개칭 내역·신뢰 등급은 [ssot/design/00_README.md](ssot/design/00_README.md) 참고.

## 보장하지 않는 것

macOS 앱 빌드, 마이크·권한·TCC, 코드 서명, pyannote 실호출, WhisperKit 추론,
**한국어 화자 분리 정확도**, 장시간 녹음 품질은 전부 미검증이다.

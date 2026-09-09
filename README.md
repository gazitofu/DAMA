# Dama (담아)

한국어 대화를 화자별 원문으로 검수하는 macOS 앱. 요약·회의록 생성은 하지 않는다.

현재 M0에는 **합성 데이터 열기 → 원문 검수·수정 → 저장 → JSON/TXT 내보내기**가 구현되어 있다.
실제 녹음·원음 재생·클라우드 전사는 후속 단계다. 상태 정본은
[versions/m0-fixture-review/plan.md](versions/m0-fixture-review/plan.md)이며, 실제 앱 조작·접근성 확인이 남아 `building`이다.

## 빌드와 검사

macOS 26.6.2 이상, Apple Silicon. `Dama.xcodeproj`의 공유 scheme `Dama`를 사용한다.

```sh
bash scripts/check.sh
```

합성 계약 29건, Swift 6 계약 컴파일·왕복, DamaCore 63건, 서명 없는 Debug 빌드를 검사한다.
모듈 캐시는 `.build/modulecache`로 고정한다. 음성·API·키체인 호출이나 `xcodebuild test`는 실행하지 않는다.
2026-09-09 앱 통합 검사: 4단계 PASS, SKIP 없음. 마지막 UI 연결 보완은 앱 컴파일만 재검증했다.
샌드박스 경로 거부와 재실행 결과는 [ssot/dev.md](ssot/dev.md)에 구분한다.

빌드 산출물: `.build/xcode/Build/Products/Debug/Dama.app`.
서명 없는 컴파일 성공을 실제 실행·배포 검증으로 취급하지 않는다.

## 실제 Mac에서 남은 확인

외부 메인/사용자가 Debug 앱을 열어 아래 여정을 한 묶음으로 확인한다. 이 세션은 앱을 실행하지 않았다.

1. 메뉴바의 **검수 창 열기** → **합성 테스트 데이터 열기**. 첫 실행에는 자동 반입하지 않는다.
2. 5개 단어·4개 발화·2개 이슈, 00:00:00.850–00:00:00.990의 독립된 누락 의심 행과 마지막 ‘네’의 미확정 화자를 확인한다.
3. 단어 클릭 또는 Shift와 함께 범위 선택 → 화자 변경. 수정 메뉴에서 이름·한 단어 수정·발화 나누기, 실행 취소/다시 실행을 확인한다. 원문 수정 창은 자동 교정하지 않는다.
4. 다음 확인 구간 → 확인함 → 미확인으로 되돌리기. 검색 결과 없음·선택 없음에서는 잘못된 단어 수정이 활성화되지 않는지 확인한다.
5. 저장 후 종료·재실행해 수정본을 확인한다. 자동본/현재 수정본 각각 JSON·TXT를 저장하고 내용을 비교한다. 저장 대화상자 취소는 파일을 쓰지 않는다.
6. 기본 1180×760과 최소 900×600, 좁은 창의 **근거 보기** 팝오버, 밝은/어두운 모드, 키보드와 VoiceOver를 확인한다. 검색은 ⌘F, 이슈 이동은 ⌥⌘J, 검수 Undo/Redo는 ⌥⌘Z / ⇧⌥⌘Z이며 텍스트 입력의 ⌘Z는 기본 편집 Undo다.

합성 fixture는 실제 음성·API 응답이 아니다. 저장·수정 실패는 Core fault injection으로 검사했으며,
네이티브 창의 실패 안내·종료 방지 동작은 실제 Mac 확인이 남아 있다.
녹음 안전성·한국어 화자 정확도·마이크 권한·서명·공증은 아직 검증하지 않았다.

## 지도

- `App/`, `UI/`: 공유 편집 세션, 메뉴바·설정, SwiftUI/AppKit 검수 창
- `Packages/DamaCore/`: 계약 로더·검증·불변 revision 저장·편집·내보내기와 pure tests
- `ssot/design/00_README.md`: 설계 읽는 순서와 채택 범위
- `ssot/contracts/`: 원본 JSON/Swift 계약. Core 사본은 바이트 일치를 검사한다.
- `ssot/api/pyannote-verified.md`: API 출처 기록. M0는 실제 호출하지 않는다.
- `fixtures/`: 기존 합성 원본. Debug 앱 리소스는 원본을 직접 참조한다.

외부 설계 원본은 `~/Vault/appdev/Dama/queries/2026-09-09-external-design-package/`에 보존되어 있다.

# DAMA · 확정 시안 01

2026-09-10 사용자 제공 `~/Downloads/DAMA_ICON_CODEX_BRIEF.md`의 SVG 3종을 좌표·색상 변경 없이 제작했다. 이름은 DAMA, 풀네임은 Distinguish Audio Memo Application. 앱은 흰 ㄷ·분리된 흰 막대·민트 원, 메뉴바는 막대 없이 ㄷ와 녹음 상태의 원을 쓴다. 광학 보정은 적용하지 않았다.

## 파일

- `source/`: 지시서와 동일한 1024×1024 앱, 22×22 대기·녹음 SVG.
- `app/dama-app-{1024,512,256,180,120,60}.png`: 각각 원본 SVG에서 직접 렌더한 RGB, 전체 불투명 배경. 둥근 모서리·외곽 투명도 없음.
- `app/DAMA.iconset/`, `app/DAMA.icns`: macOS 16·32·128·256·512pt의 1x/2x, 총 10슬롯. PNG는 동일한 앱 SVG로 직접 렌더한다.
- `menubar/`: 대기·녹음 22px/44px RGBA. 외곽 투명.
- `preview/dama-icons-preview.png`: 앱 280·120·60px(미리보기 전용 둥근 마스크), 밝은/어두운 배경 위 메뉴바 실제22px 및4배 픽셀 확대.
- `manifest.json`: 원본과 출력·연결 에셋의 SHA256, PNG 크기·모드.
- 앱의 실제 소비 위치: `Resources/Assets.xcassets/AppIcon.appiconset`, `DamaMenuIdle.imageset`, `DamaMenuRecording.imageset`. Xcode Resources build phase와 Debug/Release AppIcon 설정에 연결했다.

## 재생성

repo 루트에서 실행한다. 렌더러는 **CairoSVG 2.8.2 + Homebrew Cairo**이며 PNG/미리보기는 Pillow 11.3.0, ICNS는 macOS 기본 `iconutil`을 사용한다. 런타임 앱에는 Python/Cairo 의존성이 없다. 이 Mac의 Cairo는 `/opt/homebrew/lib/libcairo.2.dylib`에 설치되어 있다. 스크립트는 시스템 Python의 라이브러리 탐색을 이 경로로 보완하고 import 후 복원한다. 전역 설정은 변경하지 않는다.

```sh
python3 -m pip install --target .build/icon-tools -r assets/dama-icons/requirements.txt
python3 scripts/generate-dama-icons.py
```

첫 의존성 설치만 네트워크가 필요하다. 렌더링은 로컬이며 생성형 이미지 도구를 사용하지 않는다. 같은 SVG·렌더러·폰트 환경에서 반복 생성한39개 파일의 manifest가 일치했다. 미리보기 라벨은 macOS Arial을 사용한다.

Codex 샌드박스에서 `iconutil`은 정상 PNG에도 `Invalid Iconset`을 반환했으며 밖에서는 성공했다. 그 환경에서는 렌더링과 패키징을 분리한다.

```sh
python3 scripts/generate-dama-icons.py --png-only
/usr/bin/iconutil -c icns assets/dama-icons/app/DAMA.iconset -o assets/dama-icons/app/DAMA.icns
python3 scripts/generate-dama-icons.py --verify
```

## 토큰·상태 연결

| 용도 | 값 |
|---|---|
| 배경 좌상 → 우하 | `#1C2457` → `#131A40` |
| ㄷ·막대 | `#FFFFFF` |
| 앱 원 | `#35D7C9` |
| 녹음 ㄷ·원 | `#F53426` |
| 대기 미리보기 밝은 배경 / 어두운 배경 | `#262626` / `#FFFFFF` |

`App/StatusBarController.swift`에서 대기는 `isTemplate=true`, 녹음은 `false`. `contentTintColor=nil`로 녹음의 지정 RGB를 유지한다. NSStatusItem은 고정 squareLength, 두 NSImage는 같은 바깥 경계를 가진다. 2026-09-10 후속 요청으로 앱 내 표시만 기존22pt의90%인19.8×19.8pt로 축소했다(0.1.4/5). 원본 SVG·PNG와 위 미리보기는 제작 기준22px를 유지한다. `CapturePhase.recording`에서만 녹음 아이콘을 표시한다. authorizing/starting/finalizing/idle/failed에서는 대기 아이콘이다. 접근성 이름은 ‘DAMA, 녹음 대기’와 ‘DAMA, 녹음 중’. 기존 녹음 엔진과 상태 publisher를 그대로 사용한다.

## 검수 범위

RGB 마스터1024 정사각형·모서리 색/그라데이션·민트/흰 막대, 두 메뉴바 스케일의 RGBA/투명 외곽/같은 경계/녹음색/원 추가/원과 선 사이 틈을 스크립트로 검사한다. 원본 SVG와 지시서 바이트 일치, PNG 반복 생성 일치를 확인했다. 미리보기의 밝은/어두운 배경·실제22px·확대 이미지를 직접 열어 시각 검수했다. 설치/실행 및 앱 상태 검증 결과는 `versions/library-workspace/plan.md` T-16에 기록한다.

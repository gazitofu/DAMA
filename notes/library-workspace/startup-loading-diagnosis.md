# 앱 첫 실행 로딩 지연 진단 · 2026-10-30

사용자: "Dama를 처음 틀면 Speech를 불러오는 데 시간 소모가 너무 큼." 제안: 신규/기존/변환 녹음 구분 후 신규만 로딩. 코드·실데이터 측정만 했고 앱·데이터 변경 없음.

## 시작 경로 (코드)
`LibraryWorkspace.start()` → `refresh()`: `ProcessingWorkspace.refresh()`(별도 Task) 후 같은 Task에서 `scanSpeeches` → `scanScripts`를 **순서대로** 실행하고 둘 다 끝날 때까지 `busy=true`.
- `scanSpeeches`: m4a/wav는 파일 전체 SHA256, `.dama-audio`는 `capture-manifest.json`만 해시해 색인(`library-index.json`)과 경로+해시로 대조. 이미 색인된 항목은 디코딩·복사 없음.
- `scanScripts`: `*.dama.json` 전부를 읽어 SHA256 + `JSONDecoder` + `validate()`. 캐시(`scriptCache`)는 메모리에만 있어 **앱을 켤 때마다 전량 재디코딩**.
- `scanRuns`: 각 Run의 `state.json`만 읽음(작음).

## 실측 (릴리스 빌드, 실제 저장소, 읽기 전용, 디스크 캐시 웜)
측정 도구는 scratchpad의 `libtiming`(DamaAudio `FolderLibraryStore` 직접 호출). 실행 전후 `library-index.json` SHA256 동일.

| 단계 | 대상 | 시간 |
|---|---|---|
| scanSpeeches | 24개(m4a 6개 593MB, 번들 18개), 전부 색인 일치 | 0.24 s |
| scanScripts 첫 실행 | 32개 Script, 227MB(최대 31.1/25.4/24.5MB) | **6.70 s** |
| scanScripts 재호출 | 메모리 캐시 적중 | 0.09 s |

- 콜드 디스크·Debug 빌드에서는 더 길 수 있다(미측정).
- 지연의 주원인은 Speech 목록이 아니라 **Script 전량 디코딩**이다. Speech 화면이 Script 상태(`completedScript(for:)`)와 `busy`에 묶여 있어 Speech가 늦게 뜨는 것으로 보인다.

## 함의
- "신규녹음만 불러오기"는 Speech 스캔(0.24s)을 줄이는 효과가 거의 없다. Script 디코딩을 시작 경로에서 빼야 해결된다.
- 근본 수정 후보: Script 목록용 요약(제목·생성일·세션·Run·엔진 등)을 영속 캐시로 두고 전문 디코딩·해시는 열 때 지연 수행, Speech 스캔과 Script 스캔 분리(Speech 먼저 표시). 해시 기반 충돌 검사(`expectedHash`) 계약은 열 때 계산으로 유지 가능한지 /plan에서 확인.
- 분류(신규/기존/변환)는 화면 구성 변경이므로 /spec 대상.

## 사용자 결정 (2026-10-30)
- 근본 수정 먼저(화면 변화 없음, /plan 직행). 분류는 이후 별도 판단.
- 분류를 할 경우의 정의(사용자 원문 취지): **신규** = 첫 불러오기가 된 녹음(외부 파일 포함), **기존** = 이미 한 번 불러오기가 된 녹음(전사 전), **변환** = 전사가 진행된 녹음.

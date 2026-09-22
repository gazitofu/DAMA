# T-07 어절 원자성 비교 정책 구현 결과

2026-09-22 · 수탁 범위: `t07-word-atomicity.md` 변경 사양 1~4.

## 변경 파일

- `Packages/DamaCore/Sources/DamaCore/SonioxPrecisionReconciler.swift`
  - 비교 정책 `.wordAtomic = "soniox-p2-word-v5"` 추가.
  - `repairsWords`로 v4의 세 보완 분기를 v5에서도 활성화.
  - `sharePhraseTailEvidence` 뒤, `attachClosingPunctuation` 앞에 사양 그대로 `resolveWordAtomicity` 추가.
  - 필수 `Set(lexical.map { choices[$0].speaker }).count > 1` 가드 유지. 동률·후보 없음은 무변경, 토큰별 overlap/boundary 보존, coverage는 nil.
- `Packages/DamaCore/Tests/DamaCoreTests/SonioxPrecisionReconcilerTests.swift`
  - 지정 이름의 합성 테스트 7개와 보조 함수 추가. 기존 테스트 본문·기대값은 수정·삭제하지 않음.
  - A/A/B 통일과 문장부호 후행, 정확한 동률, 이미 동일 화자/전부 null/기존 근거 공유/문구 꼬리 보완의 바이트 보존, 공백 A→B→A 보존, 허용 여섯 필드 이외 직렬화 동일성, 토큰별 overlap/boundary, validator·버전·codec 왕복을 단언.
  - 바이트 비교는 동일 비교 Run ID와 정렬된 JSON 키를 사용하여 정책 차이만 비교한다.
- `notes/soniox-p2-alignment/codex/t07-word-atomicity-result.md` (이 결과 파일).

## 실제 명령과 결과

```sh
cd Packages/DamaCore && swift test --filter 'SonioxPrecision|P2TimeEvidence|Reconcil'
```

종료 코드 1. 패키지 manifest 컴파일 단계에서 샌드박스 쓰기 제한으로 종료했다. 테스트는 실행되지 않았으며 컴파일·테스트 PASS로 판정하지 않는다.

핵심 출력:

```text
warning: /Users/gazitofu/Library/org.swift.swiftpm/configuration is not accessible or not writable, disabling user-level cache features.
warning: /Users/gazitofu/Library/org.swift.swiftpm/security is not accessible or not writable, disabling user-level cache features.
warning: /Users/gazitofu/Library/Caches/org.swift.swiftpm is not accessible or not writable, disabling user-level cache features.
error: 'damacore': Invalid manifest
<unknown>:0: error: error opening '/Users/gazitofu/.cache/clang/ModuleCache/Swift-7JL1KBZ3A6V3.swiftmodule' for output: Operation not permitted
<unknown>:0: error: unable to load standard library for target 'arm64-apple-macosx14.0'
```

사양의 샌드박스 실패 처리에 따라 우회·외부 실행 없이 기록한다. 메인 세션의 샌드박스 밖 검증이 남아 있다. 실녹음·실음성·네트워크·유료 API는 사용하지 않았고 배경의 실제 녹음 기대 수치는 재측정하지 않았다.

추가 확인 명령:

- `pwd`, `git branch --show-current`, `git rev-parse --short HEAD`: 대상 repo, `work/m0-fixture-review`, `4ae706b` 확인.
- `git status --short` (착수·마감), `git diff --stat`: 공유 트리의 기존 수정 보존. 착수 시 발주문 목록 외 `versions/soniox-p2-alignment/plan.md` 수정과 `notes/soniox-p2-alignment/` untracked가 있었고, 마감 시 `scripts/CompareSonioxPrecision.swift` 수정도 관측했다. 이 세션은 이 경로들을 수정하지 않았다(명시된 결과 파일 제외).
- `git diff --check`: 출력 없음, 공백 오류 없음.
- `git diff -- Packages/DamaCore/Sources/DamaCore/SonioxPrecisionReconciler.swift`: 사양의 enum·계산 속성·세 분기·신규 패스만 변경됨을 확인.
- `rg -n 'struct TranscriptWord|var (speakerId|modelSpeakerId|assignmentSource|alignmentScore|sourceIntervalIds|reviewIssueIds)' Packages/DamaCore/Sources/DamaCore/DomainContracts.swift`: 테스트가 복원 비교하는 필드의 실제 선언 확인.

## 범위·사양 준수

사양에서 벗어난 구현 판단 없음. `normalize`의 `.wordRepair`, 두 `policy != .timeline` 분기, reconcile 가드, ManagedProcessor·combinationAlgorithmVersion은 변경하지 않았다. v5는 비교 전용이다. 커밋·브랜치 조작·하위 에이전트 생성·상태 정본 갱신·앱 버전 변경 없음.

발주문을 유일한 기능 사양으로 사용했다. 프로젝트 진입 지침과 관련 규율은 읽기·공유 트리 보존·수탁 결과 기록에 적용했으며, 일반 `/build`의 커밋·plan 갱신·위임 절차는 이번 명시적 금지 범위에 따라 수행하지 않았다.

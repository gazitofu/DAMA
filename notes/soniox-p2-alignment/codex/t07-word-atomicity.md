# T-07 발주: 어절 원자성 비교 정책 `soniox-p2-word-v5`

발주 2026-09-22 · 수탁 Codex CLI · 결과 파일 `notes/soniox-p2-alignment/codex/t07-word-atomicity-result.md`

## 배경 (메인 세션 실측, 재검증 불필요)

09-22 녹음 `국제금융로8길`의 현행 `soniox-p2-word-v4` 결과에서, **한 어절이 두 화자로 갈린 사례가 42건**이다. 전부 `해야지` `거예요` `차액이` `1600억` 같은 단일 어절이고, 두 단어가 공백 없이 붙은 사례는 0건이다. 한 어절을 두 사람이 나눠 말할 수는 없으므로 42건 모두 최소 한쪽이 확정적으로 틀렸고, 동시에 헛된 발화 구분 42개를 만든다.

메인이 Python으로 현행 v4를 정확히 재현한 뒤(문단 193 / 미배정 문단 12 / 단어중간절단 61 / null lexical 31 = 실제 파일과 일치) 측정한 기대 효과:

| | 문단 | 미배정 문단 | 단어중간절단 |
|---|---|---|---|
| 09-22 현행 v4 | 193 | 12 | 61 |
| 09-22 v5 기대 | 172 | 9 | 19 |
| 09-21 현행 v4 → v5 기대 | 323 → 312 | 39 → 35 | 73 → 43 |
| 09-15 현행 v4 → v5 기대 | 461 → 440 | 38 → 35 | 107 → 47 |

이 수치는 수탁자의 검증 대상이 아니다. 메인이 구현 후 실제 Core로 재측정한다.

## 변경 사양

대상 파일은 `Packages/DamaCore/Sources/DamaCore/SonioxPrecisionReconciler.swift` 하나와 테스트다.

### 1. 정책 추가

```swift
public enum SonioxPrecisionComparison: String, CaseIterable, Sendable {
    case timeline = "soniox-p2-timeline-v3"
    case word = "soniox-p2-word-v3"
    case wordRepair = "soniox-p2-word-v4"
    case wordAtomic = "soniox-p2-word-v5"
}
```

v4가 켜는 동작(문장부호 Choice 초기화, `sharePhraseTailEvidence`, `acoustic` 판정)은 v5에서도 **그대로** 켜야 한다. 현재 이 셋은 `policy == .wordRepair`로 판정하므로, enum에 계산 속성을 추가하고 세 곳을 모두 바꾼다.

```swift
extension SonioxPrecisionComparison {
    /// v4부터의 어절/문장부호 보완을 쓰는 정책.
    var repairsWords: Bool { self == .wordRepair || self == .wordAtomic }
}
```

`applying(_:runID:createdAt:policy:)`에서:
- `policy == .wordRepair && $0.tokenKind == .punctuation` → `policy.repairsWords && $0.tokenKind == .punctuation`
- `if policy == .wordRepair { sharePhraseTailEvidence(...) }` → `if policy.repairsWords { ... }`
- `let acoustic = policy != .wordRepair || w.tokenKind == .lexical` → `let acoustic = !policy.repairsWords || w.tokenKind == .lexical`

이 셋 외에 기존 `policy != .timeline` 분기(`shareWordEvidence`, `speakerTurns`)는 손대지 않는다. v5는 자동으로 둘 다 켜진다.

### 2. 어절 원자성 패스

`sharePhraseTailEvidence` 호출 **뒤**, `attachClosingPunctuation` 호출 **앞**에 삽입한다. 순서가 중요하다.

```swift
if policy == .wordAtomic {
    for group in orthographicGroups(doc.words) {
        resolveWordAtomicity(group, words: doc.words, choices: &choices,
            regular: doc.diarization, exclusive: doc.exclusiveDiarization)
    }
}
```

새 private 메서드:

```swift
/// 한 어절을 두 사람이 나눠 말할 수는 없다. v4가 어절 안에서 화자를 갈라 둔 경우에만,
/// 어절 전체 구간의 exclusive coverage 최대 화자로 통일한다. 동률이면 그대로 둔다.
private static func resolveWordAtomicity(_ group: [Int], words: [TranscriptWord], choices: inout [Choice],
                                         regular: [DiarizationInterval], exclusive: [DiarizationInterval]) {
    let lexical = group.filter { words[$0].tokenKind == .lexical }
    guard lexical.count > 1,
          Set(lexical.map { choices[$0].speaker }).count > 1,
          lexical.allSatisfy({ words[$0].startUs != nil && words[$0].endUs != nil }),
          let start = lexical.compactMap({ words[$0].startUs }).min(),
          let end = lexical.compactMap({ words[$0].endUs }).max(), start < end else { return }
    let evidence = P2TimeEvidence.token(startUs: start, endUs: end, regular: regular, exclusive: exclusive)
    guard let best = evidence.best,
          !(evidence.scores.count > 1 && evidence.scores[1].coverage == best.coverage) else { return }
    for i in lexical {
        choices[i].speaker = best.speakerID
        choices[i].sourceIDs = Array(Set(choices[i].sourceIDs + evidence.sourceIDs)).sorted()
        choices[i].coverage = nil // 어절 단위 근거는 이 토큰의 coverage가 아니다.
    }
}
```

사양 요점, 임의로 바꾸지 말 것:

- **`Set(lexical.map { choices[$0].speaker }).count > 1` 가드는 필수다.** 이미 한 화자(또는 전부 null)로 통일된 어절은 건드리지 않는다. v5는 v4에 대해 순수 가산이며, 이 가드가 빠지면 v4가 `shareWordEvidence`로 채운 배정과 null 보존이 뒤집힌다.
- 동률이면 **아무것도 하지 않는다**. 어절 전체를 null로 만들지 않는다.
- 후보가 없으면(`evidence.best == nil`) 아무것도 하지 않는다.
- `choices[i].overlap` / `choices[i].boundary`는 **건드리지 않는다**. `direct()`가 토큰별로 계산한 값을 보존한다.
- 문장부호 토큰은 이 패스의 대상이 아니다. 뒤따르는 `attachClosingPunctuation`이 앞 lexical을 따라간다.
- `shareWordEvidence`의 인접성·역행·끼어들기 가드는 이 패스에 복제하지 않는다. 어절 내부 통일은 그 가드들의 목적(다른 어절로의 근거 전파 방지)과 무관하다.
- 새 시간·새 텍스트·새 coverage 값을 만들지 않는다. `P2TimeEvidence.token`을 그대로 쓴다.

### 3. 운영 기본값은 바꾸지 않는다

- `SonioxPrecisionReconciler.normalize(...)`의 `policy: .wordRepair`는 **그대로 둔다**.
- `ManagedProcessor` / `ManagedRun.combinationAlgorithmVersion` / 새 Run 기본값은 **건드리지 않는다**.
- `reconcile(_:runID:createdAt:policy:)`의 기존 가드(새 Run ID, 사람 수정 거부, source 버전 확인)도 그대로다.

v5는 비교 전용이다. 운영 승격은 사용자 판정 후 별도 태스크다 (plan D-02).

### 4. 테스트

`Packages/DamaCore/Tests/DamaCoreTests/`의 기존 Soniox P2 정책 테스트 파일에 추가한다. 기존 v2/v3/v4 기대값은 **수정·삭제하지 않는다**. 충돌하면 결과 파일에 근거를 적고 멈춘다.

합성 fixture로 다음을 덮는다. 실제 녹음·실음성·네트워크 금지.

1. `testWordAtomicUnifiesSplitOrthographicWord` — 한 어절의 lexical 3개가 v4에서 A/A/B로 갈리고 어절 전체 coverage가 A 우세일 때, v5는 셋 다 A. 같은 입력의 v4 결과는 A/A/B 그대로(회귀 보호).
2. `testWordAtomicKeepsTiedWordUnchanged` — 어절 전체 coverage가 정확히 동률이면 v5 결과가 v4와 같다. 전체 null로 만들지 않는다.
3. `testWordAtomicLeavesUnanimousWordAlone` — v4에서 이미 한 화자로 통일됐거나 전부 null인 어절은 v5에서 바이트 동일. 특히 v4가 null로 남긴 어절이 v5에서 채워지지 않는지 확인한다.
4. `testWordAtomicDoesNotCrossWhitespace` — 공백으로 나뉜 두 어절이 서로 다른 화자일 때 v5가 둘을 합치지 않는다. 짧은 B 발화가 독립 어절이면 보존된다 (INV-06).
5. `testWordAtomicPreservesTokensAndTimes` — v5 결과의 `text`/`prefix`/`ordinal`/`tokenKind`/`startUs`/`endUs`/`asrConfidence`/`language`/`asrSpeakerLabel`이 v4와 완전히 동일하고, 바뀌는 건 `speakerId`/`modelSpeakerId`/`assignmentSource`/`alignmentScore`/`sourceIntervalIds`/`reviewIssueIds`뿐이다.
6. `testWordAtomicKeepsOverlapAndBoundaryFlags` — 통일된 어절의 각 토큰 `overlap`/`boundary` 파생 이슈가 `direct()` 계산값 그대로다.
7. `testWordAtomicRunPassesValidator` — v5 결과가 `TranscriptValidator().validate` 통과, `provenance.algorithmVersion == "soniox-p2-word-v5"`.

## 검증 (수탁자가 수행, 명령·출력 요약을 결과 파일에 기록)

```
cd Packages/DamaCore && swift test --filter 'SonioxPrecision|P2TimeEvidence|Reconcil'
```

샌드박스에서 못 돌면 그 사실만 적는다. 메인이 밖에서 전수 재실행한다.

## 금지

- `transcript` 원문·시간·원 화자 ID·직렬화 형식 변경 금지. 저장 파일 마이그레이션 없음.
- 운영 기본값(`normalize`의 `.wordRepair`, ManagedProcessor, `combinationAlgorithmVersion`) 변경 금지.
- `ssot/`·`versions/`·`CHANGELOG`·`pbxproj`·`scripts/`·`notes/` 외 문서 수정 금지 (메인 담당).
- 기존 v2/v3/v4 테스트 기대값 수정·삭제 금지.
- git 커밋·브랜치 조작 금지. 하위 codex/agent 생성 금지.
- 인라인 반환 불인정. 변경 파일 목록·검증 결과는 결과 파일에 쓴다.

## 메인 실측 전제 (2026-09-22)

HEAD `4ae706b`, branch `work/m0-fixture-review`, 사전검사 `.build/check-logs/word-v5-baseline/run-20260922T073822Z-nKVt5O` 계약30 / Swift205 / Debug PASS, SKIP 0. 기존 타 소유 dirty 8건(`.claude/commands/build.md`, `README.md`, `notes/qwen-local/evaluation.md`, `ssot/api/pyannote-verified.md`, `ssot/dev.md`, `versions/m0·m1·m2/plan.md`)과 untracked `ssot/api/nari-verified.md`는 보존한다.

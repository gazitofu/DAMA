# T-11 발주: 화자 이름 범위를 원 화자 ID 기준으로 고정

발주 2026-09-21 · 수탁 Codex CLI · 결과 파일 `notes/uiux-reading/codex/t11-speaker-scope-result.md`

## 사용자 규칙 (2026-09-21 확정)

- 전사에서 분리된 원 화자(Speaker A/B/C = `transcript.turns[].speakerId`)는 기록 값으로 그대로 유지한다 (이미 불변).
- Speaker A → "정연서 대표" 전체 지정, Speaker B → "정연서 대표" 전체 지정 후, Speaker B 문단에서 "윤현섭 이사"로 전체 변경하면 **Speaker B 문단만** 바뀐다. "정연서 대표"로 지정된 Speaker A 문단은 그대로다.
- 즉 ‘이 부분부터’·‘전체’의 대상은 **등록 인물(이름)이 아니라 원 화자 ID**가 같은 Turn 집합이다.

## 현행 결함

`Packages/DamaCore/Sources/DamaCore/ScriptPeopleAndDeletion.swift` `speakerTargets(_:scope:)`: 앵커 Turn에 `turnSpeakerIDs`가 있으면 같은 등록ID를 가진 모든 Turn을 대상으로 잡는다. 이름이 같아진 다른 원 화자까지 함께 바뀐다.

## 변경 사양

1. `speakerTargets(_:scope:)`
   - `.one` → 기존대로 `[turnID]` (삭제 문단이면 `[]`).
   - `.from`/`.all` → 앵커 Turn의 `speakerId`(원 화자 ID)가 nil이면 `[turnID]`만. nil이 아니면 `transcript.turns` 중 `speakerId == 앵커.speakerId`이고 삭제되지 않은 Turn (`.from`은 앵커 index 이상). `turnSpeakerIDs`/`turnNames`는 대상 선정에 사용하지 않는다.
   - 등록 인물 재사용(`registerName`의 같은 이름 → 같은 등록ID/색)은 유지한다. 단, `registerName` 안의 "legacy turnNames 같은 이름을 등록ID에 연결" 루프는 기존 동작 유지.
2. `Packages/DamaCore/Sources/DamaCore/LibraryScript.swift`
   - `public func originalSpeakerLabel(for turnID: String) -> String?` 추가. 해당 Turn의 원 화자 ID에 대해 `name(for:)`가 만드는 `"Speaker A"` 식 라벨을 돌려준다 (첫 등장 순서 기준 letters). Turn을 못 찾거나 speakerId가 nil이면 nil. `name(for:)`의 Speaker 라벨 계산을 private helper로 뽑아 두 곳이 같은 코드를 쓰게 한다. `name(for:)`의 우선순위(수동 이름 → AI 이름 → legacy displayName → Speaker 라벨)는 변경 없음.
3. `UI/ScriptModalSheets.swift` `SpeakerNameSheet`
   - `hasSpeaker`는 `block.speakerID != nil`만 본다 (등록 여부 무관). 초기 scope도 같은 조건으로 `.all`/`.one`.
   - 제목 아래에 캡션 한 줄 추가: 원 라벨이 있으면 `"원 화자 \(label) · 현재 이름 \(block.name)"`, 없으면 `"원 화자 미배정 · 현재 이름 \(block.name)"`. `label = edit.file.script.originalSpeakerLabel(for: block.speakerTurnID)`.
   - 기존 안내 문구 `"같은 등록 화자는 이름과 색을 함께 사용합니다."`를 `"‘이 부분부터’·‘전체’는 원 화자 \(label)로 분리된 부분에만 적용됩니다. 같은 이름의 다른 원 화자는 바뀌지 않습니다."`로 교체 (hasSpeaker일 때). 미배정 문구는 유지.
4. 테스트 `Packages/DamaCore/Tests/DamaCoreTests/ScriptPeopleAndDeletionTests.swift`
   - `testRegisteredScopeIncludesManuallyAssignedUnknownAndPreservesSourceBoundaries`를 새 규칙으로 고쳐 이름을 `testScopeFollowsOriginalSpeakerNotRegisteredPerson`으로 바꾼다. 기존 시나리오에서 `blocks[3]` (미배정, 등록ID 있음)에 `.all`로 "수정 이름"을 주면 blocks[3]만 바뀌어야 한다: 기대 `["동일 인물", "Speaker B", "동일 인물", "수정 이름", "화자 미확정"]`. 이어서 `blocks[2]` (원 화자 C)에 `.from` "부분 이름" → blocks[0]은 "동일 인물", blocks[2]는 "부분 이름", blocks[3]은 "수정 이름" 유지, blocks[4]는 "화자 미확정".
   - 새 테스트 `testRenamingOneOriginalSpeakerLeavesOtherOriginalSpeakerWithSameName`: 원 화자 C/B/C/미배정/미배정 source에서 `blocks[0]` (C)에 `.all` "정연서 대표" → `blocks[1]` (B)에 `.all` "정연서 대표" (등록 인물 1명, 같은 등록ID) → `blocks[1]` (B)에 `.all` "윤현섭 이사". 기대: blocks[0]·[2]는 "정연서 대표", blocks[1]은 "윤현섭 이사", `registeredSpeakers` 2명, `registeredSpeaker(for: blocks[0].speakerTurnID)?.name == "정연서 대표"`. `originalSpeakerLabel`이 blocks[0]→"Speaker A", blocks[1]→"Speaker B", blocks[3]→nil 인지도 확인. roundtrip 후 validate 통과.
   - 다른 테스트 파일은 새 규칙과 충돌하지 않는 한 수정하지 않는다. 충돌하면 결과 파일에 근거를 적고 최소 수정.

## 검증 (수탁자가 수행, 명령·출력 요약을 결과 파일에 기록)

```
cd Packages/DamaCore && swift test --filter 'ScriptPeopleAndDeletionTests|LibraryPresentationTests|ReadingDecorationTests|LibraryJourneyTests|ReadingSnapshotTests'
```

샌드박스에서 못 돌면 그 사실만 적는다. 메인이 밖에서 재실행한다.

## 금지

- `transcript` 원문·시간·원 화자 ID·`turnNames`/`turnSpeakerIDs` 직렬화 형식 변경 금지. 저장 파일 마이그레이션 없음.
- ssot/·versions/·CHANGELOG·pbxproj·tone 문서 수정 금지 (메인 담당).
- git 커밋·브랜치 조작 금지. 하위 codex/agent 생성 금지.
- 인라인 반환 불인정. 변경 파일 목록·검증 결과는 결과 파일에 쓴다.

## 수탁 결과 (2026-09-21)

Codex CLI 위임은 `ERROR: You've hit your usage limit ... try again at 3:38 PM`으로 실패했다 (exit 1, 파일 변경 0건). 사용량 복구를 기다리지 않고 메인 세션이 직접 구현·검증했다. 이것은 CLAUDE.md의 Codex 위임 규약에 대한 가용성 사유의 예외이며, 위임 재개 시 이 발주문을 그대로 쓴다.

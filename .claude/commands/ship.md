---
description: built 유닛을 main에 머지하고 태그·CHANGELOG까지 처리한다. GO 게이트 1회. 마무리 절에서 retro-queue 판정 + handoff 스냅숏 갱신.
argument-hint: <유닛 슬러그>
---

# /ship $1

`work/$1`을 **backpressure 재검증 → CHANGELOG → GO 게이트 → main 머지 → 태그 → 마무리 절**로 처리한다. 원격(GitHub)이 없으면 로컬 머지·태그까지이고, 원격 생성·push는 별도 사용자 확인 항목이다.

## 필수 로드

1. 규율 메모리 (`/spec` 필수 로드 1과 동일 목록) 2. `versions/$1/plan.md` + `CHANGELOG.md` 최근 엔트리

## 사전 확인 (실패 시 중단·보고)

1. 브랜치 = `work/$1`. 2. plan `status: built` + AC 전부 체크. 3. `git status --short` clean. 4. 태그 부재 (`git tag -l`, 원격 있으면 `git ls-remote --tags origin`).

## 동작 순서

1. 원격 있으면 `git fetch origin && git merge origin/main --no-edit` (충돌 시 중단). `bash scripts/check.sh`.
2. `CHANGELOG.md` 최상단 엔트리 초안 (유닛 · 요약 · Added/Changed/Fixed · D-NN 결과 · **안 잰 축**). 소스 = plan + diff.
3. **GO 게이트 1회**: diff 요약 + CHANGELOG 초안 상신. GO 없이 머지 금지. push 여부를 같은 게이트에서 함께 묻는다.
4. `git checkout main && git merge --no-ff work/$1 --no-edit && bash scripts/check.sh && git tag -a <태그> -m "<요약>" && git branch -d work/$1`. 원격 push는 GO에 포함된 경우에만.
5. plan `status: released`, `released_at`. `git status` 실측.
6. **마무리 절 (스킵 금지)**: ⓐ `~/Vault/_setup/retro-queue.md` 미판정 항목 승격/폐기/보류(1회) ⓑ `~/Vault/appdev/Dama/handoff/current.md` 1페이지 스냅숏 갱신 ⓒ `~/Vault/appdev/Dama/_index.md`의 status·다음 단계 반영 ⓓ 실호출·실기기로 새로 확인한 사실이 있으면 `ssot/api/pyannote-verified.md`·`ssot/dev.md`에 부칙 1줄 ⓔ 단계별 결과표 보고 1회.

## 가드레일

- 사전 확인 실패·충돌·backpressure 실패는 중단·보고. `--no-ff`. force-push 금지. 게이트는 GO 1회.
- 릴리스 노트에 미검증 성능을 쓰지 않는다. 한국어 실측(게이트 G-07) 전에는 "정확한 화자 분리" 문구를 쓰지 않는다.

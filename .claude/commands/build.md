---
description: plan.md대로 구현한다. 태스크별 backpressure, Codex 위임, 유닛별 자율 진행, 게이트 ②로 끝난다.
argument-hint: <유닛 슬러그>
---

# /build $1

`versions/$1/plan.md`가 SSOT다. **plan 외 작업은 받지 않는다** (발견 이슈는 Follow-ups에 적고 계속, rule-scope-stop).

## 필수 로드

1. 규율 메모리 (`/spec` 필수 로드 1과 동일 목록)
2. `versions/$1/plan.md` + 스펙 (`notes/$1/$1.src.html` 또는 계약 유닛의 `ssot/design/*`)
3. `CLAUDE.md` 최상위 경계·함정 · `ssot/dev.md` · `ssot/api/pyannote-verified.md` · `ssot/contracts/`

## 사전 확인 (어긋나면 중단·보고)

1. 현재 브랜치 = plan `branch:`. 2. `status: ready-to-build` + `decisions_resolved: true`. 3. `git status --short` clean. 4. plan 전제(경로·도구 실존·환경 버전·외부 전제) 재실측 (rule-carryover-remeasure).

## 자율 구간 규약

- 진입 전 plan `resume:`에 재개 지점 기록, 태스크 경계마다 갱신.
- 중간 보고 없음. 보고는 게이트 ② 상신 1회.
- **막힘만 사용자에게 직접 묻는다**: API 키, 음성 전송 승인, 마이크 권한, 코드 서명, 유료 실호출, 원격 push. 이들이 없어도 fixture·mock으로 갈 수 있는 데까지 간다. **키 부재를 이유로 멈추지 않는다.**

## 동작 순서

1. **구현** (`status: building`): T-NN 순차. 한 태스크 = 한 의도 = 한 커밋. 데이터·계약 먼저, UI 나중.
2. **Codex 위임**: 기계적 구현은 `codex exec`에 위임한다. 발주문은 파일로 (`notes/$1/codex/tNN.md` + 차수 공통 «계약» 파일), 출력 파일 경로를 명시하고 인라인 반환은 불인정 (rule-delegation-artifacts). **분할·diff 리뷰·통합은 메인.** Swift는 샌드박스에서 `xcodebuild test`가 안 돌 수 있으므로 **테스트 실행은 메인이 밖에서** 재실행한다 (GAIA 선례). 병행 발주는 메인이 인터페이스(타입·함수 스텁)를 선커밋해 파일 소유를 가른다.
3. **backpressure** (태스크마다, 통과 전 다음 금지): `bash scripts/check.sh`. SKIP 축은 통과가 아니라 "안 쟀음"이다.
4. **커밋**: `git diff --cached` 육안 + pathspec (rule-shared-tree-commits). 녹음 파일·키·서명 URL이 스테이징에 들어갔는지 확인.
5. **QA**: AC-NN 각 항목을 실물로 검증. 층위를 섞지 않는다 (`ssot/dev.md` §4). 계약 테스트 통과를 실기기 동작이나 한국어 정확도로 승격하지 않는다 (rule-negative-claims).
6. **게이트 ②** (보고 1회): AC 결과표 + 실행한 명령과 출력 + **실제 Mac/마이크/API를 썼는지** + 안 잰 축 + 남은 제한 + 읽은 근거. 작은 변경은 즉시 패치 → 재검증. 의도·AC 변경은 `/plan $1` 회귀.
7. **마무리**: AC 전부 체크 → `status: built`, `resume:` 비움, `git status` 실측 기재.

## 가드레일

- **녹음 안전성이 AI 처리보다 우선.** 이 순서를 뒤집는 구현은 plan에 있어도 중단·보고한다.
- 실제 녹음 파일·API 키·서명 URL을 저장소·로그·export에 남기지 않는다. 테스트 음성은 gitignored 폴더로만.
- 미구현 기능의 가짜 컨트롤·가짜 녹음 상태를 만들지 않는다. 미지원은 미지원으로 표시한다.
- 테스트 실패를 숨기려고 skip하거나 `@unchecked Sendable`로 덮지 않는다.
- 외부 사이드이펙트(원격 push·업로드·유료 호출·음성 전송·삭제)는 건별 확인.

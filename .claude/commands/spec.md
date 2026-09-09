---
description: 유닛의 정책·화면·문구를 자립 HTML 스펙 1장으로 작성한다. 코드 수정 없음, 게이트 ①로 끝난다.
argument-hint: <유닛 슬러그> [요구사항]
---

# /spec $1

요구사항을 받아 `notes/$1/$1.src.html`을 쓰고 `notes/$1/$1.html`로 빌드한다. **src.html 이 `/plan`과 `/build`의 스펙 입력 전부이고(AI용), 빌드된 .html 은 사람이 게이트에서 읽는 판이다.** 이 커맨드 동안 코드·`fixtures/`·`ssot/contracts/` 수정 금지 (읽기 전용 실측만).

## 필수 로드 (읽은 목록을 문서 하단 «참조 근거» 접힘에 기재)

1. 규율 메모리 `~/.claude/projects/-Users-gazitofu/memory/` 공통 10종 (rule-purpose-first · rule-ambiguous-instructions · rule-scope-stop · rule-gate-hygiene · rule-measurement · rule-negative-claims · rule-carryover-remeasure · rule-verify-at-consumption · rule-delegation-artifacts · rule-destructive-writes) + appdev 2종 (rule-shared-tree-commits · rule-numeric-test-integrity) + `rule-external-media-verify` · `rule-longrun-watchdog`
2. `ssot/doc-template/README.md` (양식) · 새 문서는 `template.src.html` 복제로 시작
3. `ssot/design/00_README.md` (채택 범위) → 해당 유닛에 걸리는 설계 문서. **`ssot/design/02·03·04`는 컨펌된 계약이므로 다시 묻지 않는다.** 화면·문구(`01`)만 재확정 대상
4. `ssot/api/pyannote-verified.md` (API 실검증. `03`과 충돌하면 이쪽이 우선)
5. `ssot/tone/` 확정 문구 · `notes/$1/`에 문서가 있으면 수정 모드 (r2, r3 · 부칙 1줄씩)

## 산출물 요건

- **정책**: 상태 전이·경계 케이스·기본값을 값으로. `/build`가 추가 질문 없이 구현할 수 있는 수준.
- **화면**: 영역 분할·조작 항목·상태별 표시·빈 상태·오류 상태. 색만으로 상태를 구분하지 않는다. 미구현 기능의 가짜 컨트롤을 넣지 않는다 (설계 01 §6).
- **문구**: 검수 이슈 6종(`ambiguous_speaker`·`overlapping_speech`·`missing_speech`·`boundary_conflict`·`capture_interrupted`·`result_expired`)을 포함해 화면에 뜨는 모든 문장을 확정 표기로. 더미 문구 금지. 확정분은 컨펌 후 `ssot/tone/`에 편입.
- **데이터 계약**: 새로 정하지 않는다. `ssot/contracts/`와 `ssot/design/04`를 **실측 인용**한다. 계약을 바꿔야 하면 그것 자체가 D-NN이다.
- **검산 자**: 축별 자·모집단·문턱 유무. 안 재는 축은 "안 잼"으로 선언.
- **시스템 영향**: 재사용 / 변경 / 신규 3분류. `/plan`의 입력.
- 서술은 최신 확정 규격만. 히스토리는 부칙 1줄. 산문에 줄표(—) 금지. 범위 밖은 "비범위" 1줄로 명시.
- 양식: 판정 블록 선두(`#s-verdict`, 열린 D-NN + 판정 축), 근거는 각주 `<span class="fn">`, 병렬 항목은 리스트, 읽은 목록은 `details.audit`.

## 동작 순서

1. 요구사항 번호 정리. 용도·소비 방식·수용 기준 확인. 두 갈래 지시는 질문 1개로 해소.
2. template 복제 → 판정 블록 → 절 채움 → `python3 ssot/doc-template/_build.py notes/$1/$1.src.html`.
3. 자기검수: 빌드 html 열어 판정 블록·각주 팝오버 1회. 규격표 값 ↔ 본문 대조. 설계 문서에서 옮긴 수치는 **초기 설계값**인지 **확정값**인지 표시했는지 확인.
4. 게이트 ① (사용자 컨펌): 빌드 html 경로 보고 후 대기. **컨펌 전 `/plan` 진입 금지.**
5. 컨펌 후: `data-state="closed"` + `.stamp` 날짜 + 각 `.vq` 확정 1문장 → 재빌드 → 확정 문구 `ssot/tone/` 편입 → `/plan $1` 제안.

## 가드레일

- 코드 수정 없음. 유닛 하나에 스펙 문서 하나.
- 수치는 근거(실측·출처) 없이 발명하지 않는다. 근거 없는 값은 "신규 후보"로 표시.
- 설계 문서의 임계값을 그대로 옮길 때도 "외부 설계 초기값 · 한국어 실측 전"이라고 각주에 남긴다.

---
description: 컨펌된 스펙을 입력으로 작업 브랜치와 versions/{유닛}/plan.md를 작성한다. 구현 금지, D-NN 해소 게이트로 끝난다.
argument-hint: <유닛 슬러그>
---

# /plan $1

컨펌된 스펙만 입력으로 `versions/$1/plan.md`를 만든다. **이 커맨드 동안 코드·`fixtures/`·`ssot/contracts/` 수정 금지.** plan.md는 AI 전용 파일이다. 서사 금지, 값·시그니처·경로·AC만 적는다.

## 필수 로드 (읽은 목록을 plan.md "근거" 절에 기재)

1. 규율 메모리 (`/spec` 필수 로드 1과 동일 목록)
2. 컨펌 신호 확인. 화면·문구 유닛은 `notes/$1/$1.src.html`의 `#s-verdict` `data-state="closed"`. **계약만 다루는 유닛**(데이터·API·저장소)은 `ssot/design/00_README.md`의 하이브리드 채택을 컨펌 출처로 명시하고 스펙 문서 없이 진입할 수 있다.
3. `ssot/dev.md` (환경·backpressure·검증 층위·외부 전제) · `ssot/api/pyannote-verified.md` · 해당 유닛의 `ssot/design/*`
4. `ssot/contracts/transcript.v1.schema.json` · `ssot/contracts/DomainContracts.swift` (**실측 인용**. 기억으로 쓰지 않는다)

## 사전 확인 (어긋나면 자동 해소하지 않고 중단·보고)

1. `git status --short` clean (타 소유 미커밋분은 실측해 사유 병기).
2. `versions/$1/plan.md` 있으면 수정 모드.
3. 브랜치: `git checkout main && git checkout -b work/$1` (원격이 있으면 pull 먼저. 이미 있으면 체크아웃만).
4. `bash scripts/check.sh` 통과. SKIP 축은 "안 쟀음"으로 plan에 기재.

## plan.md 양식

```markdown
---
unit: $1
branch: work/$1
status: planning        # planning → ready-to-build → building → built → released
decisions_resolved: false
resume:                 # 자율 구간 재개 지점. /build가 갱신
spec:                   # notes/$1/$1.src.html 또는 ssot/design/NN (계약 유닛)
---
## 근거 / ## 의도 (1~3문장) / ## 영향 범위 (경로 + 현행 실측값) / ## 수용 기준 (AC-NN 체크박스 · 자·모집단 명시)
## 작업 분해 (T-NN · 한 태스크 = 한 의도 · 데이터·계약 먼저) / ## 결정 항목 (D-NN · 진짜 갈리는 것만) / ## Follow-ups
```

- **시간·단위를 건드리는 태스크**는 입력 단위/내부 단위/출력 단위/부호를 명시하고 고정 테스트 1개를 AC에 박는다 (rule-numeric-test-integrity). 이 앱의 내부 시간은 Int64 마이크로초, 공급자는 초 단위 Double, 구간은 반열린 `[startUs, endUs)`다.
- **불변식이 걸리는 태스크**는 해당 INV 번호와 회귀 사례 RC 번호를 AC에 적는다 (`ssot/design/04` §3, `ssot/design/06` §2).
- 비자명 동작(기본값·차단 조건·경계값)은 값으로 박는다. 외부 의존(API 키·마이크 권한·서명 identity·실제 회의 파일)은 «막힘» 절에 사용자 실행 항목으로 적는다 (`ssot/dev.md` §5).
- 설계 문서에서 가져온 임계값은 «외부 설계 초기값»으로 표시하고 확정값과 섞지 않는다.

## 결정 게이트

D-NN만 올린다. 판정 축·선택지가 바꾸는 것·실측 근거·공통 전제를 선두에 (rule-gate-hygiene). 계약 문서가 이미 확정한 것을 D-NN으로 되묻지 않는다.

## 마무리

D-NN 해소 → `decisions_resolved: true`, `status: ready-to-build`. 자율 구간이면 사용자에게 묻지 않고 `/build $1`로 잇는다.

## 가드레일

- 구현 금지. 스펙·계약에 없는 정책 임의 추가 금지. plan 300줄·10태스크 초과 시 분할 제안.
- `ssot/design/`의 티켓 번호(T-001~013)와 plan의 T-NN은 다른 체계다. 인용할 때 `설계 T-001`로 쓴다.

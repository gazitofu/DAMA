# DAMA 설계 정본 · 읽는 순서와 채택 범위

이 폴더는 외부 LLM이 만든 설계 패키지(가칭 SpeakerScript v1.0, 2026-09-09 수령)를 Dama 이름으로 개칭하고 **채택 범위를 표시한 정본**이다. 손대지 않은 원본은 `~/Vault/appdev/Dama/queries/2026-09-09-external-design-package/`에 그대로 있다.

## 읽는 순서

| 파일 | 역할 | 채택 상태 |
|---|---|---|
| [01_PRODUCT_AND_UX.md](01_PRODUCT_AND_UX.md) | 요구사항 FR-01~16, 메뉴바 계약, 검수 창, 문구 | **참고**. 요구사항·비범위는 채택. 화면 치수·레이아웃·문구는 `/spec`에서 재확정 |
| [02_ARCHITECTURE_AND_STORAGE.md](02_ARCHITECTURE_AND_STORAGE.md) | 모듈 경계, 병행성, 녹음 경로, 시간축, 상태기계, 저장소 | **정본** |
| [03_ENGINE_AND_API_CONTRACT.md](03_ENGINE_AND_API_CONTRACT.md) | pyannote API 계약, 오류·중복 제출, WhisperKit(P1) | **정본**. 단 [../api/pyannote-verified.md](../api/pyannote-verified.md)가 우선 |
| [04_DATA_AND_RECONCILIATION.md](04_DATA_AND_RECONCILIATION.md) | 데이터 계층, 불변식 INV-01~10, 결합 규칙, TurnBuilder | **정본** |
| [05_IMPLEMENTATION_PLAN.md](05_IMPLEMENTATION_PLAN.md) | M0~M4, 티켓 T-001~013 | **참고**. 유닛 분할과 상태는 `versions/{유닛}/plan.md`가 정본 |
| [06_TEST_AND_RELEASE.md](06_TEST_AND_RELEASE.md) | 회귀 RC-01~16, 실기기 시험, 한국어 평가 지표, 게이트 G-01~08 | **정본** |
| [07_SECURITY_AND_DECISIONS.md](07_SECURITY_AND_DECISIONS.md) | 권한·entitlement, Keychain, ADR-001~010, 오해 방지 | **정본** |
| [08_SOURCES_AND_VERIFICATION.md](08_SOURCES_AND_VERIFICATION.md) | 출처 목록과 확인 범위 | **참고**. 실검증분은 `../api/pyannote-verified.md` |

계약 파일은 `../contracts/transcript.v1.schema.json`(normalized·export 구조)과 `../contracts/DomainContracts.swift`(Swift 타입·직렬화)다. 합성 fixture는 저장소 루트 `fixtures/`.

## 채택 결정 (사용자 확정 2026-09-09)

하이브리드 채택이다.

1. **데이터·API·아키텍처 계약(02·03·04 + schema + contracts)은 컨펌된 정본으로 간주한다.** `/spec`을 다시 돌리지 않는다.
2. **화면·문구(01)는 `/spec`으로 재확정한다.** 이 패키지에는 실제 비주얼이 없고 ASCII 와이어프레임뿐이며, 검수 창이 이 앱의 승부처다. 01의 치수(패널 360pt, 검수 창 1180×760pt 등)는 외부 LLM의 초기 제안값이지 확정 규격이 아니다.
3. 05의 티켓 번호(T-NN)는 유닛 plan의 T-NN과 **다른 체계**다. plan이 05를 참조할 때는 `설계 T-001`처럼 출처를 붙인다.

## 이 문서군의 신뢰 등급

원본 패키지는 자신의 `VALIDATION_REPORT.md`에서 다음을 명시했다. 채택 시 그대로 유지한다.

- **수행함**: 합성 데이터 29개 회귀·불변식 테스트, JSON Schema 적합성, Linux Swift 6 계약 컴파일·왕복.
- **수행 안 함**: macOS 앱 빌드, 마이크·권한·TCC, 코드 서명, pyannote 유료 API 실호출, WhisperKit 추론, **한국어 정확도**, 장시간 녹음 품질.

즉 **이 문서군은 설계이지 검증된 성능이 아니다.** 별도 출처 표기가 없는 수치·임계값(coverage 0.60, margin 0.20, gap 300ms, marker 150ms, polling 10~60초 등)은 전부 초기 설계값이며 한국어 실측으로 조정할 대상이다. 조정 시 `algorithmVersion`과 벤치마크를 함께 기록한다(04 §1).

## 이번 세션에서 추가로 확인한 것 (2026-09-09)

| 축 | 결과 |
|---|---|
| pyannote API 계약 | 1차 출처와 대조 완료. 어긋난 항목 없음. 누락 endpoint 5종과 미확인 6항목을 `../api/pyannote-verified.md`에 기록 |
| 요금 | Precision-2 €0.112/h + STT Orchestration €0.168/h. 비용은 제약이 아님 |
| 합성 계약 테스트 | 이 Mac에서 29/29 통과 (`python3 scripts/validate_contracts.py`) |
| Swift 계약 | **macOS arm64 · Swift 6.3.3에서 컴파일·왕복 통과**. 원본 보고는 Linux Swift 6.2.1 결과였음 |
| 개발 환경 | macOS 26.6.2 · Xcode 26.6 · Swift 6.3.3. 문서가 가정한 "macOS 15+"보다 상위. deployment target은 `/plan`에서 결정 |

## 개칭 내역

`SpeakerScript` → `Dama`. 파생: `SpeakerScriptCore` → `DamaCore`, `SpeakerScript.xcodeproj` → `Dama.xcodeproj`, `media://speakerscript/…` → `media://dama/…`, `urn:speakerscript:transcript:1` → `urn:dama:transcript:1`. 원본에 있던 합본 `DESIGN_SPEC.md`와 그 생성기 `build_spec.py`는 8개 원본 문서와 중복·드리프트 위험이 있어 채택하지 않았다. `START_PROMPT.md`·`AGENTS.md`는 저장소 루트 `CLAUDE.md`로 흡수했다.

---

부칙: 2026-09-09 최초 작성 (외부 패키지 채택·개칭·검증 세션).

명칭 갱신 (2026-09-09): 정식 표기는 DAMA(다마), 앱 번들은 `DAMA.app`. 위 개칭 이력과 기존 경로·모듈·계약 식별자는 유지한다.

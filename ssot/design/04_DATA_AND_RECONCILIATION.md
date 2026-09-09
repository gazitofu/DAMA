# 04. 데이터와 화자 결합 명세

이 문서의 시간 임계값은 전부 **초기 설계값**이다. 한국어 회의 성능을 실측한 최적값이 아니다. 변경할 때 algorithmVersion과 benchmark 결과를 함께 기록한다.

## 1. 데이터 계층

세 가지 계층을 분리한다: Raw(공급자 원본) → Model normalized(앱 표준 자동 결과) → Revision(사람 수정본). 이 패키지의 `schemas/transcript.v1.schema.json`은 normalized/export 계약이며 pyannote의 API 스키마가 아니다.

최상위 객체는 `schemaVersion, sessionId, runId, durationUs, language, provenance, speakers, diarization, exclusiveDiarization, words, turns, reviewIssues, revision`을 가진다. 내부 원본 경로나 API 인증정보는 export schema에 들어가지 않는다.

| 객체 | 의미 |
|---|---|
| Speaker | 한 Run 내부의 ID, 공급자 ID, 사용자가 지정할 표시명 |
| DiarizationInterval | 화자 시간 구간과 선택적 confidence map |
| Word | 모델의 최소 전사 단위, 원래 텍스트, 수정 텍스트, 시간, 원래 후보와 현재 화자 |
| Turn | 동일 화자 단어들의 표현 단위 또는 텍스트 없는 누락 의심 marker |
| ReviewIssue | 검수 이유/범위/연결된 단어/interval/확인 상태 |
| Revision | 어떤 Run/이전 revision을 기반으로 언제 수정했는지 |

여기서 Word는 공급자가 반환한 단위다. 한국어의 형태소/어절/문법적 단어와 정확히 일치한다고 가정하지 않는다.

## 2. 필드의 핵심 의미

`Word.text`는 모델 텍스트, `editedText`는 명시적 사용자 대체 텍스트 또는 null이다. 자동 맞춤법 교정은 없다. `prefix`는 표시/출력에 필요한 선행 구분 문자다. 화면의 텍스트는 prefix + (editedText ?? text)로 만든다. 공급자 원문과 표시용 공백 재구성은 구분한다.

`modelSpeakerId`는 P0의 공급자 후보 또는 P1의 최대 겹침 1순위 후보다. `speakerId`는 현재 사용 가능한 귀속이며 null은 '화자 미확정'이다. `assignmentSource`는 provider/reconciled/user/unknown으로 구분한다. 사용자가 변경해도 modelSpeakerId는 바뀌지 않는다.

`alignmentScore`는 시간 겹침 비율 0~1이며 화자 정답 확률이 아니다. 공급자 confidence는 interval의 map에 그대로 둔다. map의 key는 providerId이며 Speaker.providerId로 앱 내부 ID에 연결한다. 시간이 없거나 0길이면 alignmentScore=null이다. confidence map이 없으면 null이며 0으로 채우지 않는다.

`timingOrigin=model`은 ASR의 추정 시간, `userSelected`는 사람이 선택한 시간, `inheritedUnaligned`는 텍스트를 고쳤지만 재정렬하지 않은 시간, `none`은 사용할 시간이 없다는 의미다. 텍스트 수정을 했다는 이유만으로 기존 시간이 새 텍스트에 정확히 정렬되었다고 표현하지 않는다.

`Turn.kind=missingSpeech`는 실제 텍스트가 없는 검수 marker다. wordIds는 빈 배열이고 markerText를 별도로 가진다. 이 marker를 모델이 인식한 문장처럼 Words에 추가해서는 안 된다.

## 3. 반드시 유지할 불변식

INV-01: 모든 ID는 해당 배열 안에서 유일하며 참조는 같은 export 안에 존재한다.

INV-02: 시간은 정수 마이크로초, `[start,end)`이다. 정상 시간은 0≤start≤end≤duration이다. 잘못된 원본 시간은 raw에만 남기고 normalized에서는 start/end를 함께 null로 둔다.

INV-03: ASR 단어의 ordinal은 원래 순서를 보존한다. 정렬 과정에서 같은 텍스트를 deduplicate하지 않는다. '네 네'는 두 발화일 수 있다.

INV-04: 모든 Word는 정확히 하나의 speech Turn에 속한다. 누락 의심 marker는 Word를 소유하지 않는다.

INV-05: speech Turn의 모든 Word는 현재 speakerId가 같아야 한다. null도 하나의 미확정 상태로 취급하되 서로 떨어진 unknown 구간을 무제한 합치지 않는다.

INV-06: A → B → A에서 B의 텍스트가 없어도 A의 앞뒤를 합치지 않는다. 다른 화자의 구간, 누락 marker, 중단 이슈를 병합 장벽으로 사용한다.

INV-07: 일반 diarization의 진짜 동시발화는 보존한다. exclusive는 결합용 보조 정보이며 raw 일반 결과를 대체하지 않는다.

INV-08: confidence, alignmentScore, 사람이 확인했는지는 서로 다른 필드다.

INV-09: 모델 결과 재처리는 새 Run이다. 이전 Run의 화자 라벨이나 사용자 수정을 무조건 재사용하지 않는다.

INV-10: JSON/TXT 내보내기는 모르는 화자를 알고 있는 것처럼 채우거나 불확실 marker를 삭제하지 않는다.

## 4. 일반/배타적 diarization

exclusive 출력은 동시에 여러 화자가 있는 구간을 단일 화자 시간축으로 표현하기 위한 별도 결과다. 일반 diarization과 함께 받을 수 있다. 이것은 겹친 음성을 각각의 오디오로 분리하는 기능이 아니다. [공식 exclusive 설명](https://docs.pyannote.ai/tutorials/speaker-configuration)

정렬용 exclusive 결과가 누락되거나 서로 다른 화자 interval끼리 중첩되는 등 계약이 깨졌으면 adapter issue를 표시한다. 일반 diarization을 exclusive라고 이름만 바꿔 쓰지 않는다.

## 5. P1 단어-화자 reconciliation

입력은 같은 analysis.wav의 단어 시간 W와 diarization D, exclusive E다. 모든 시간은 normalized 마이크로초다. 합성 fixture용 기준 구현은 `scripts/validate_handoff.py`에 있다. 이것은 Whisper/pyannote 정확도를 측정하는 코드가 아니라 결합 정책을 검증하는 코드다.

### 5.1 후보 점수

각 화자 s에 대해 E의 같은 화자 interval들을 union한다. 서로 겹치는 동일 화자 구간을 이중 계산하지 않는다.

```text
overlap_s = length( W ∩ union(E_s) )
coverage_s = overlap_s / length(W)
first = 최대 coverage 화자
second = 두 번째 coverage (없으면 0)
margin = coverage_first - coverage_second
```

시간이 null/0길이면 화자를 강제 배정하지 않고 invalid_timestamp 이슈를 남긴다. 겹침이 없으면 가장 가까운 화자로 채우지 않는다.

### 5.2 동시발화 판단

일반 D에서 **서로 다른 두 화자가 같은 순간에 양의 길이만큼 겹치고, 그 구간이 W와 겹칠 때만** overlapping_speech다. W가 A 다음 B를 순서대로 걸친 것은 경계 충돌이지 동시발화가 아니다. 같은 화자 interval의 중복도 동시발화가 아니다.

### 5.3 초기 결정 규칙

- coverage_first ≥ 0.60, margin ≥ 0.20, 진짜 동시발화 아님이면 speakerId=first.
- 동시발화, 점수 부족, 동률, 겹침 없음이면 speakerId=null; 1순위는 modelSpeakerId에 남긴다.
- 두 명 이상의 exclusive 후보와 겹치면 boundary_conflict를 표시한다. 기준을 통과했어도 검수 대상일 수 있다.
- 전환 경계 전후 50ms에 닿는 단어는 보조 검수 후보로 표시할 수 있다. 이 임계값으로 텍스트를 삭제하지 않는다.
- 선택 화자의 interval confidence가 제공되고 70 미만이면 low_confidence로 표시한다. 점수 누락은 낮은 점수가 아니다. 여러 interval에 걸친 경우 원본 각 값을 유지한다.

이 정책은 불확실할 때 배정을 보류하는 보수적 출발점이다. unknown 비율이 높아질 수 있으므로 정확도와 검수시간을 함께 평가한다. 시간 겹침만으로 완벽한 화자 분리가 된다고 주장하지 않는다.

### 5.4 P0와의 차이

P0는 공급자의 word-level 화자 귀속을 보존하고, raw 일반 diarization과의 충돌/겹침/누락 이슈를 덧붙인다. P1에서 쓰는 보류 규칙을 P0 결과에 조용히 적용해 서로 다른 결과를 같은 버전으로 보이게 하지 않는다. 정책을 바꾸면 별도 normalizationVersion 또는 Run으로 기록한다.

## 6. ASR에 없는 화자 전환

문제 예:

```text
D: A 0.0–1.0 / B 1.0–1.2 / A 1.2–2.0
W: A의 단어 0.2–0.8 / A의 단어 1.3–1.9
```

B와 시간상 겹치는 lexical Word가 전혀 없으면 B 구간에 missingSpeech marker와 missing_speech 이슈를 생성한다. B의 실제 텍스트를 '네'라고 추정해 쓰지 않는다.

150ms 이상은 warning, 그보다 짧은 구간은 info를 초기값으로 삼되 **짧다는 이유로 구간을 제거하지 않는다.** 모든 marker는 Turn 병합 장벽이다. 모델이 잘못 감지한 발화일 수도 있으므로 문구는 '누락 의심'이다.

B 구간을 A의 긴 Word가 덮고 있으면 시간만으로 누락을 확정할 수 없다. 이때는 missing marker를 무조건 만들지 않고 `unrepresented_speaker` 또는 `boundary_conflict`를 만들며 원음 검수로 보낸다. 부분적인 무음/호흡을 모두 누락 발화로 표시하는 고급 coverage 탐지는 P1 실험으로 분리한다.

## 7. TurnBuilder

provider의 sentence/turn 텍스트를 최상위 분할 기준으로 삼지 않는다. Words와 diarization 경계를 기준으로 출력용 Turn을 구성한다.

같은 화자, 시간적으로 연속, 최대 간격 300ms 이하, 다른 화자 구간/누락 marker/중단 이슈가 사이에 없음인 경우에만 병합한다. 중간 다른 화자 구간은 exclusive뿐 아니라 일반 diarization의 겹침 후보까지 확인한다. 300ms는 읽기 편의용 초기값이며 짧은 발화 삭제 조건이 아니다.

단어 하나가 경계를 걸치면 텍스트를 임의로 둘로 자르지 않는다. 해당 단어를 독립 Turn으로 두거나 기존 경계에 묶되 반드시 충돌 이슈를 남긴다. 마침표를 만들어서 완전한 문장처럼 고치지 않는다.

문장부호/0길이 토큰은 같은 공급자 segment 안의 이웃 lexical Word에 붙일 수 있지만 새로운 음성 증거로 취급하지 않는다. 정확히 붙일 수 없으면 별도 미정렬 항목으로 보존한다. 한국어 공백은 source text에 있으면 보존한다. 공백을 재구성할 때는 단어별 prefix로 변경 흔적을 남긴다.

## 8. 수정과 내보내기

MVP 수정 범위: 표시명 변경, Word 범위 화자 변경, 선택 Word의 텍스트 대체, Turn 분리, 이슈 확인, Undo/Redo. 누락 문장 입력은 사용자가 시간 구간을 선택한 수동 전사로만 추가하고 provenance를 userSelected로 둔다. 미구현이면 비활성화하고 가짜 작동을 만들지 않는다.

수정 이벤트는 기반 revision ID와 변경 전후 값을 기록한다. revision 저장을 완료한 다음 UI의 '저장됨' 상태를 바꾼다. 재처리 결과는 별도 탭/버전으로 열고 기존 검수본에 자동 덮어쓰기하지 않는다.

TXT는 다음 형식이다:

```text
[00:00:00.200–00:00:00.800] 화자 A
저희가

[00:00:01.000–00:00:01.200] 화자 B · 확인 필요
[음성 감지 / 전사 누락 의심]

[00:00:01.300–00:00:01.900] 화자 A
준비하고 있습니다
```

null 화자는 '화자 미확정'으로 출력한다. 모델 confidence를 정답 확률(%)로 표기하지 않는다. 불확실성이 있는 export에는 요약 AI가 화자를 추정해서 채우지 않도록 하는 짧은 안내문을 선택적으로 포함한다. 이 안내는 전사 콘텐츠와 구분된 metadata/header다.

# 07. 권한, 보안 및 의사결정 기록

## 1. 최소 권한

기본 앱은 메뉴바 에이전트로 설계하며 LSUIElement를 사용한다. [Apple LSUIElement](https://developer.apple.com/documentation/bundleresources/information-property-list/lsuielement)

샌드박스 설정에는 마이크 입력, 외부 API 통신, 사용자가 선택한 파일 읽기/쓰기가 필요하다. 실제 Xcode target에 entitlement를 설정하고 서명 결과로 검증한다. [audio-input](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.device.audio-input), [network.client](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.network.client), [user-selected.read-write](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.files.user-selected.read-write)

```xml
<!-- target 설정 예시. Bundle ID와 signing은 로컬 개발 환경에서 설정한다. -->
<key>com.apple.security.app-sandbox</key><true/>
<key>com.apple.security.device.audio-input</key><true/>
<key>com.apple.security.network.client</key><true/>
<key>com.apple.security.files.user-selected.read-write</key><true/>
```

Info.plist에는 `LSUIElement=true` 및 녹음 목적을 설명하는 `NSMicrophoneUsageDescription`을 넣는다. 카메라/화면 녹화/연락처/전체 디스크 접근 권한은 MVP에 요청하지 않는다. Apple 문서의 세부 SDK signature/availability는 로컬 Xcode에서 최종 확인한다. 이 전달 환경에서는 Apple의 일부 문서 본문이 JavaScript/Markdown 응답 제한으로 완전히 열리지 않았다.

선택 파일은 security-scoped access 범위 안에서 앱 저장소로 복사하고 즉시 접근을 해제한다. 지속 bookmark는 필요한 경우에만 추가한다. 샌드박스를 끄는 것을 권한 오류의 기본 해결책으로 삼지 않는다.

## 2. API 키와 로컬 민감정보

API 키는 Keychain 서비스에 저장한다. 일반 UserDefaults/환경 설정 JSON/Git/로그에 저장하지 않는다. [Apple Keychain services](https://developer.apple.com/documentation/security/keychain-services)

Keychain service/account 이름은 앱 전용 namespace를 사용한다. 키 삭제/교체가 있어도 이미 녹음된 원본과 스크립트를 삭제하지 않는다. 앱에 공용 API 키를 하드코딩하지 않는다. 향후 배포 제품이 되면 개인 키 방식 또는 별도 인증 backend를 다시 설계한다.

오디오/스크립트 파일은 P0에서 앱 자체의 end-to-end 암호화 저장소로 구현하지 않는다. 앱 샌드박스/OS 계정 보호와 별도 암호화는 다른 보장이다. 이를 '완전 암호화 금고'로 광고하지 않는다. 사용자의 백업/동기화 설정까지 앱이 통제한다고 표현하지 않는다.

## 3. 업로드 동의/보관

클라우드 업로드 전에 녹음별 유효한 정책을 확인한다. autoAfterStop을 명시적으로 켠 경우에도 세션별 neverUpload가 우선한다. local-only 세션을 디버깅 편의로 원격 API에 보내면 안 된다.

세션 삭제가 서버의 즉시 삭제가 아니라는 설명을 UI에 넣는다. 외부 서비스의 보관/지역 정책은 03의 확인 출처를 참고한다. 국내법이나 회사별 비밀유지 의무 충족을 앱이 자동 판정하지 않는다. 회사 자료는 소속 조직의 승인 조건과 별도로 관리한다.

## 4. 미지원/변경 방침

시스템 오디오 캡처는 ScreenCaptureKit을 사용하는 별도 확장으로 둔다. [Apple ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit)

마이크 트랙과 시스템 오디오를 별도 저장해도 원격 참석자 각각이 독립 트랙으로 분리되는 것은 아니라는 정책 설명을 둔다. 에코/시간 동기화/채널 경로 테스트 없이 트랙을 합쳐 P0 파이프라인에 넣지 않는다.

## 5. Architecture Decision Records

| ADR | 결정 | 이유/반대급부 |
|---|---|---|
| ADR-001 | NSStatusItem + SwiftUI | 아이콘 자체 원클릭 명령; AppKit 경계 코드 필요 |
| ADR-002 | P0 managed, P1 hybrid | 먼저 기준 결과 확보; P0는 클라우드 의존 |
| ADR-003 | 원본/Run/Revision 분리 | 재현/수정 추적; 저장량 증가 |
| ADR-004 | 단어 단위 모델과 Turn 파생 | 화자 전환 제어; UI/타임스탬프 처리 복잡 |
| ADR-005 | 미확정/marker 허용 | 틀린 확정 귀속 방지; 검수 건수 증가 |
| ADR-006 | 녹음과 후처리 독립 | 회의 중 신뢰성; 상태기계 복잡 |
| ADR-007 | 파일 기반 Repository | 최소 의존성; 대규모 검색은 후속 DB 필요 |
| ADR-008 | 앱 자체 polling | 별도 서버 불필요; 앱 장기 종료 시 결과 만료 위험 |
| ADR-009 | 화자 짧은 구간 독립 ASR 금지 | 문맥 없는 토막 처리 피함; 누락 복원은 별도 과제 |
| ADR-010 | 요약/LLM 호출 제외 | 사용자 목적에 집중; 문장 가독성 자동 개선 없음 |

### ADR-010 후속 변경 · 2026-09-10 사용자 확정

사용자는 사람의 수작업을 최소화하기 위해 문맥 기반 일부 자동 교정과 Codex CLI 제품 연동을 허용했다. 이전 LLM 전면 제외는 이 범위에서 대체한다. 원 normalized 결과는 그대로 두고 LibraryScript의 별도 교정 overlay로 저장한다. 참석자·맥락·로컬 폴더의 선택 발췌는 표기 교정 근거이며 녹음의 사실을 덮어쓰는 정답이 아니다. 문맥/직무만으로 화자 ID를 재귀속하지 않는다. 이름 매핑도 명시적 자기소개·참석자 일치와 원문 인용을 요구한다.

Codex CLI 실행은 로컬이지만 추론 입력은 OpenAI로 전송된다. 녹음별 변환 확인에서 pyannote 음성 전송과 후속 OpenAI 텍스트 교정을 함께 확인하거나 기존 스크립트의 AI 교정 버튼에서 별도 확인한다. 실제 데이터 전송/사용량을 수반하는 개발 실측은 별도 승인 대상이다. 자동 요약·액션아이템 생성·원문 삭제는 추가하지 않는다. 상세 계약과 제한은 `ssot/contracts/library-script.md`를 따른다.

## 6. 이전 대화에서 구현 시 오해하면 안 되는 항목

- exclusive는 음원 분리가 아니다. 겹친 말 두 개를 모두 복원한다고 보장하지 않는다.
- Whisper 모델이 바뀌면 단어 누락/시간이 바뀌므로 최종 화자 귀속도 달라질 수 있다.
- Precision-2 결과를 무조건 정답으로 보거나 최대 겹침 결합이 공급자 결합보다 낫다고 가정하지 않는다.
- confidence는 단일 숫자 필드로 가정하지 않는다. 공급자 발화별 map과 단어 정렬 점수는 다르다.
- faster-whisper Python 옵션을 WhisperKit Swift 함수에 그대로 복사하지 않는다.
- 참석자 수와 실제 발화자 수는 다를 수 있다.
- 같은 화자 앞뒤 사이에 짧은 다른 화자가 있으면 병합하지 않는다.
- 로컬 Whisper만 쓴다고 Precision-2 cloud 전송이 사라지는 것은 아니다.
- public source 확인, Linux 계약 검사, Mac build, 실음성 성능은 각각 다른 검증이다.

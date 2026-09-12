# uiux-reading 네이티브 검증

2026-09-12~13 · macOS 실제 AppKit/SwiftUI · 승인 Scripts r4/Speeches r5.

검사 축: 원 자리 입력·저장/취소·IME, 화자 변경, AI 모달/버전, Speeches 소비 입력, 재생·이동, 하위 호환과 저장 충돌, 전체 검사, 설치·원본 보존. 이 범위와 발견한 회귀의 재검증 후 닫는다. 정확도·학습·장시간 성능 전수 검토로 확대하지 않는다.

## 환경과 결과

별도 `com.gazitofu.Dama.ReadingQA` 앱과 `/private/tmp/dama-reading-qa-20260912-a`의 합성30초 무음/대사로 저장 조작을 했다. `scripts/ReadingUIFixture.swift`가 만든2 Speech, 최초1 Script, AI 보정 전/1의 합성 snapshot을 사용했다. 과거 snapshot은 합성 성공 상태이며 실제 AI가 생성한 결과가 아니다. 운영 Bundle/Release에서는 이 QA 경로가 활성화되지 않는다.

| 축 | 실제 확인 |
|---|---|
| 배치 | 1180×760 네이티브 다크 화면. 좌측 로고, 읽기 본문, 제목/결과/정보, 하단 재생·AI. 수정 진입 전후 같은 NSTextView·폭·글꼴·원점. 별도 편집창 없음 |
| 제목 | 직접 입력 후500ms 자동 저장, 목록 제목 동기화, 재시작 보존. 빈 제목 Enter는 오류와 draft 유지, Escape는 마지막 저장 제목 복구 |
| 문단 |3개 원 Turn의 한 문단을2줄로 고쳐 같은 버튼이 저장으로 변함. 원래 내용으로 되돌리면 수정 표시. Cmd-Return 저장, 재시작 후 내용 유지. 빈 draft의 저장 활성/ESC 취소 확인. 빈 문자열 실제 저장은 Core 회귀로 검증 |
| 탐색 보호 | 미저장 제목/본문에서 결과 변경·화자·AI·내보내기/목록 차단. 폴더 탭도 비활성화 표시 |
| 화자 | 이름 클릭 모달. 전체7 Turn/이 부분만3 Turn 대상 표시, 이 부분만 김가상으로 저장. 뒤의 Speaker A는 유지. 검수 기록 UI 없음 |
| 과거 결과 | AI 보정1 선택 시 당시 제목/원문 표시, title 편집·문단 수정·이름 변경·AI 비활성. 현재 수정 내용은 보존. 현재 복귀와 재시작 확인 |
| AI 참고 | 추가 문구 입력·취소 후 현재 결과/버전 목록 유지. OpenAI 최종 고지와 보정하기가 하단에 보임. 차단 빌드에서는 최종 버튼을 눌러도 enqueue 전에 명시적 차단 메시지, AI 실행 없음 |
| Speeches | 실제 화자 수2, 합성 맥락·참석자·용어 저장. pyannote 선택은 맥락/용어/참고 숨김, Qwen/운영 엔진 복귀 시 기존 입력 보존. 폴더 사용 기본OFF. 용어·참고/새 전사 설정 접기. Soniox 실제 JSON에 general/terms와211/7,500바이트, 폴더 발췌 없음 표시 |
| 재생 | 합성 무음 구간의 원음 듣기→재생 정지, 실제0.334초 위치 표시와 현재 문단 버튼, 구간 끝 자동 종료. 다음 문단으로 선택 액션 이동. 음성의 청취 정확도 검증 아님 |
| 내보내기 | native NSSavePanel 열림까지 확인. 아래 도구 제한 때문에 네이티브 파일 저장 완료는 미확인. 현재/과거/사람 문단 Markdown 내용·실제 파일 쓰기·stale export 차단은 Core 테스트 PASS |

`scripts/ReadingInputCheck.swift`를 `UI/InlineScriptText.swift`와 함께 Swift6으로 컴파일하여 **프로세스 안의 실제 NSTextView**를 검사했다. 조합 중 stale model 갱신 차단, 조합 종료 알림, 조합 중 Enter/Escape 가로채지 않음, 제목 Enter/본문 Cmd-Return, readonly 전환의 marked draft 폐기를 확인했다. `.build/check-logs/uiux-reading-input.log` PASS. OS 키보드 입력 소스를 바꿔 물리적으로 한글을 조합한 테스트와는 구분한다.

## 발견한 회귀와 전체 검사

- 첫 전체 검사 `uiux-reading-final/run-20260912T144740Z-VqHx4G`: 중복 Script identity에서 correction 저장을 막지 못한1건, 버전 표시가 추가된 Markdown golden21건 실패. 실제 원문/읽기 fingerprint는21건 모두 동일했다.
- 저장 경로에 같은 폴더의 identity 검증을 복구하고, 읽기 cache와 이 actor가 실제 쓴 hash를 분리했다. 외부 파일을 스캔한 것만으로 늦게 도착한 AI/제목 저장이 그 내용을 덮지 못하게 회귀 검증을 보강했다. Markdown은 `결과·revision` 한 줄 추가를 대조한 뒤 golden만 갱신했다.
- 재사용 scratch 전체 검사 `run-20260912T145601Z-vKs9AW`에서 xctest SIGBUS가 발생했다. 기존 기준과 분리한 **새 scratch** 전체 검사 `uiux-reading-final-clean/run-20260912T145840Z-iMQdTm`는 **계약30·Swift170·Debug build PASS, SKIP0**. SIGBUS 근본 원인 해결을 선언하지 않으며 재발 시 해당 async 테스트/런타임부터 진단한다.
- SDK26.5에 대한 기존 deployment target26.6.2 경고와 AppIntents metadata 경고 유지. 다른 Mac 호환성·공증 검증 아님.

## 검증 중 외부 전송 사건

2026-09-12 23:47 KST 무렵, native 변환 확인창의 접근성 트리에 표시된 **닫기**를 도구로 선택했지만 실제로는 결합 처리 경로가 실행됐다. 합성30초 무음과 합성 맥락/참석자/용어가 Soniox·pyannote에 전송되고 완료 Run이 생겼다. 실제 사용자 녹음은 아니다. 승인받은 유료 실험이 아니며 **검증 절차 오류**다. 발견 즉시 사용자에게 알렸다. 과금 금액은 미확인이고 서버 삭제를 임의 실행하지 않았다. 사건 결과는 정확도 성과로 계산하지 않는다.

수정: QA 앱에서 `ProcessingWorkspace.launch`는 keychain 접근 전에, `CorrectionWorkspace.enqueue`는 queue/저장 전에 모델 실행을 차단한다. QA 서명에서 network client와 microphone entitlement도 제거했다. 동일 서명 identity의 검증 복사본에만 적용했고 운영 앱의 처리 정책은 유지한다. 수정한 QA에서 AI 최종 버튼의 차단 메시지를 직접 확인했다. UI가 표시하는 닫기/확인 의도만으로 외부 실행 부재를 추정하지 않는다.

NSSavePanel/NSOpenPanel에서는 선택/저장 후 CUA가 `timeoutReached` 또는 `noWindowsAvailable`로 끊기는 현상이 반복됐다. 별도 QA와 설치 앱의 process sample은 메인 이벤트 루프 유휴 상태였다. 앱 deadlock으로 확정하지 않는다. 중복 클릭을 피하고 전체 AX 상태를 다시 조회했으나 native export 완료를 확인하지 못했다. QA 프로세스를 종료했고 저장 데이터는 보존했다. 설치 앱도 녹음·처리·미저장 입력이 없는 유휴 상태를 확인한 뒤 연결 복구를 위해 재시작했다.

## 설치와 원본 보존

- 저장 조작 전 `.build/diagnostics/uiux-reading-native/user-library-before.json`에 실제 사용자14파일의 hash를 고정했다. QA 후 `user-library-after.json`: **unchanged14 / changed0 / missing0**. 예전 r4 이전 manifest와 혼동하지 않는다.
- 0.4.7(17) 실행 앱을 정상 종료하고 `.build/backups/DAMA-0.4.7-17-before-reading-native.app`에 보존했다. Debug/Release 버전은 모두 **0.5.0(18)**.
- 첫 설치에서 통상 Xcode 서명 빌드가 sandbox를 활성화해 기존 앱과 다른 Application Support를 열었다. 원래 index/Run/원본은 그대로였고 데이터 이관·삭제는 하지 않았다. 기존 전달본이 `adhoc,linker-signed`, entitlement 없음인 것을 대조했다. 전달본은 기존 운영 기록과 같은 `CODE_SIGNING_ALLOWED=NO` 방식으로 독립 `.build/reading-delivery`에서 준비했다. 프로젝트의 entitlement 계약을 변경하지 않았다.
- 최종 설치본 `/Applications/DAMA.app`의 실제 About 창에서 **DAMA Version 0.5.0 (18)** 확인. 기존 화자 수3/맥락/참석자/변환완료 상태와 연결 Script가 그대로 열렸다. 실제 내용은 QA 문서에 복제하지 않았다. 최종 원본 해시도14/14 불변. 앱을 실행 상태로 전달했다.
- 전달 빌드 로그 `.build/check-logs/uiux-reading-delivery-build.log` PASS. 기존/최종 모두 `adhoc,linker-signed`, entitlement 없음으로 대조했다. 본 세션 중 임시 sandbox 저장 위치는 원래 라이브러리와 분리되어 있으며 임의 삭제하지 않았다.

## 미측정과 후속

물리 한글 IME, 네이티브900×600/라이트 모드, VoiceOver 청취, 긴 전사 프레임 성능, 이번 UI를 통한 실제 AI 품질, 추가 학습, 경쟁 제품과 정확도·정상 비용 비교는 측정하지 않았다. 공개 입력 경로와 화자 진단은 [별도 제안](speaker-context-diagnosis.md)에 정리했다. 새 모델 정책·개인 프로필 UI·학습을 이 화면 승인에 포함해 실행하지 않는다.

## 설정 화면 모드 보완 (2026-09-13 · 0.5.1/19)

사용자가 설정의 라이트/다크 선택 누락을 지적했다. 기존에는 macOS 모드를 자동으로 따르는 동작만 있었다. 설정 상단에 시스템 설정(기본)/라이트/다크 선택을 추가하고 `appearance.mode`를 저장하며 앱 시작 때 복원한다. `NSApplication.appearance`로 SwiftUI와 native 텍스트/모달에 공통 적용하며 macOS 전체 설정은 바꾸지 않는다.

`.build/check-logs/uiux-reading-appearance-build.log` Debug PASS, 기존 linker-signed 전달 방식 유지. CUA에서 라이트 설정과 실제 Script 본문, 다크 설정, 라이트 선택 후 정상 종료/재실행의 선택 및 밝은 화면 유지, 시스템 설정 복귀의 어두운 화면을 확인했다. 설정 하단 닫기까지 실제 화면에 보였다. About 창 `DAMA Version 0.5.1 (19)` 확인 후 설정 화면을 열어 두었다. 기존0.5.0은 `.build/backups/DAMA-0.5.0-18-before-appearance.app`에 보존했다. 이번 여정에는 전사/AI/녹음 실행·사용자 본문 수정·API 키 입력이 없다. 데이터 코드 변경이 없는 화면 설정 수정이라 Core 전수 검사는 반복하지 않았다. 위0.5.0 기록의 라이트 미측정은 이 여정에서 보완했으며 작은 창·VoiceOver 등 다른 축의 미측정은 유지한다.

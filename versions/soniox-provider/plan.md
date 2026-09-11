---
unit: soniox-provider
branch: work/m0-fixture-review
status: building
decisions_resolved: true
created: 2026-09-11
updated: 2026-09-11
resume: "fada176 구현 커밋을 GitHub main/work 브랜치에 push/원격 HEAD 대조 완료. 영향58개/계약30 및 Debug PASS, 0.2.0(7) 빌드 준비. 실행 앱 0.1.5가 녹음 중이라 설치/새 UI 확인 보류. 다음: 사용자 녹음 종료 확인 후 정상 종료→기존 앱 백업→새 앱 설치→선택/설정/버전 UI 확인."
---

## 근거와 범위
- 사용자 GitHub push 및 Soniox 선택 구현 요청, 이어하기 승인. 기존 library-workspace의 혼합 6문서 소유/변경분 보존, 기존 작업 브랜치 유지. 별도 main 머지·태그·정식 배포는 하지 않는다.
- 입력: 사용자 제공 DAMA_STT_Conversation_Summary_2026-09-11.md의 async v5/비교 단계. 회의 원문은 반입하지 않는다. 현재 계약 지도·build 절차·세션 열람 규율 재사용.
- 기존 pyannote 기본값 유지. Soniox는 전체 analysis.wav 1개를 async v5에 전송. ko/en 힌트, 화자분리/언어감지 ON. 실시간·자동 모델 선정·음원 평가·AI 교정 알고리즘 변경은 이번 범위 밖.
- 변환/재전사 전에 엔진 선택. Run 입력 snapshot으로 재개 엔진 고정. 키는 공급자별 Keychain. 같은 음성 SHA256와 독립 Run, 화자 ID, 원응답, 요청/서버 모델, 작업 상태를 보존.
- 비교용 새 변환은 기본 AI 교정 OFF. 기존 자동 교정 설정은 보존하고 비교 옵션을 끄면 활용. Soniox 문맥은 별도 opt-in 및 전송 미리보기, terms는 사용자가 입력. 특정 회의 사전 하드코딩 없음.
- Soniox 토큰의 공백/순서/시간/미확정 화자 보존. confidence는 ASR 값이며 화자 confidence map이나 alignmentScore로 둔갑하지 않는다. 독립 VAD/exclusive 자료는 제공된 척 만들지 않는다. 같은 화자 발화는 reading-v4 문장 기준, 토큰 사이 임의 공백 금지.
- 요청 접수 불명확 시 자동 POST 재시도 금지. 업로드/접수/완료 응답 먼저 저장. 앱 삭제와 원격 삭제를 구분해 안내, 이 버전은 원격 자동 삭제 없음.

## 태스크와 수용 기준
- [x] AC-01 제공자 선택과 구 Run/키/Script의 backward compatibility, 원본/사람 수정 보존.
- [x] AC-02 Soniox 업로드→접수→poll→원문 저장→정규화→Script/Markdown, 합성 여정 검증.
- [x] AC-03 401/402/429/5xx/네트워크/불명확 접수/재개 경로, 잘못된 ID 및 전송 동의 방어.
- [x] AC-04 서브워드·문장 끝·A→B→A·null·시간 오류·confidence 독립 보존 검증.
- [ ] AC-05 네이티브 앱 build 및 선택 UI 확인, 버전 표시, 로컬 설치. 실제 음성 전송·한국어 정확도는 미검증으로 명시.
- [x] AC-06 관련 코드만 커밋/push, 원격 HEAD 확인. 기존 혼합6문서 미포함.

## 검증 기록
- 최초 push: `03e7957`, private gazitofu/DAMA, main 및 work/m0-fixture-review. 과거 blob 274개 credential/음성 경로 검사 발견0. 실제 키·음성·전사 업로드 없음.
- 앱 내 실제 유료 호출은 사용자가 별도 전송 확인 후 진행한다. 테스트는 합성 HTTP/합성 audio와 native UI 설정 확인으로 한정.
- 구현: 기존 Swift 녹음/전체 WAV 준비 유지, 별도 SonioxTransport/SonioxNormalizer 및 ManagedProcessor 공급자 분기. Run 입력/업로드 UUID/요청 hash/보고 모델/음성 hash/원응답 저장. 미지원 화자수 강제값은 보내지 않음, 토큰 confidence/language optional 계약 확장과 strict codec 허용 키 동기화.
- 합성 distinct 영향58개 PASS(중복 실행을 더하지 않음): 기존 ContextCorrection9/LibraryPresentation9/ManagedJourney12/ProcessingPresentation2, TranscriptLoading17, 신규 Soniox9. `.build/check-logs/soniox-tests-fresh.log`의 기존32개 PASS, `soniox-tests-fixed.log`의 strict codec17개 PASS, `soniox-tests-final.log`의 신규9개 PASS. 두 엔진 동일 음성/기존 편집 보존은 `soniox-comparison-test.log` 및 final 동일여정 PASS.
- 첫 재사용 SwiftPM 산출물에서 ContextCorrectionTests가 SIGSEGV, 코드 변경 없이 별도 `.build/soniox-swiftpm` 전체 컴파일 후 기존32개 PASS. crash report는 타입 metadata 접근이며 증분 산출물 불일치 가능성으로 기록, 제품 오류로 단정하지 않음. 새 Soniox 여정에서는 strict JSON shape의 신규 필드 누락을 검출해 정상 필드만 optional allowlist로 추가. 표시 앞 공백 trim/Markdown escape 기대값도 실제 공통 계약에 맞게 수정. 임계값 완화·검사 skip 없음.
- `python3 scripts/validate_contracts.py`:30 PASS; `python3 scripts/check_contract_copy.py`:11991bytes SHA256 76e4b15a294ac6f2742551de2ea298475a4a33ef6942de7bbde8f09222a31fab. 최종 Debug arm64 build 명령은 기존 절대 캐시 경로/서명 정책 유지, 로그 `soniox-xcodebuild.log`.
- CUA에서 설치된 0.1.5 앱의 진행 중 녹음 표시(14:59→19:08) 실측. 종료/교체하지 않았고 녹음 중단 여부를 비동기 질문했다. 새 UI 조작·Keychain 저장/실호출·실제 전사 정확도는 미검증, AC-05와 building 유지.
- `fada17643a41d7eb11ae5652fb476475a7db846f` main/work/m0-fixture-review push 성공 및 `git ls-remote origin` 일치. 별도6혼합문서만 unstaged로 남음. 최종 빌드 Info.plist 0.2.0(7), 설치본 Info.plist 0.1.5 확인. 문서 상태 커밋은 별도이며 재빌드 사유 아님.

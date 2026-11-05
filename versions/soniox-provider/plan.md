---
unit: soniox-provider
branch: work/m0-fixture-review
status: built
decisions_resolved: true
created: 2026-09-11
updated: 2026-09-11
resume: ""
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
- [x] AC-05 네이티브 앱 build 및 선택 UI 확인, 버전 표시, 로컬 설치. 실제 음성 전송·한국어 정확도는 미검증으로 명시.
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
- 2026-09-11 사용자 ‘앱 교체하자’ 승인 후 설치 완료. 착수 시 이미 녹음 종료되어 21:53.280 Speech 표시. 정상 Quit 첫 시도는 저장 보호로 취소, 이후 재시도 종료·pgrep 프로세스 없음 확인. 기존 앱은 ignored `.build/app-backups/DAMA-0.1.5-before-soniox-20260911.app`에 백업, 검증 빌드를 `/Applications/DAMA.app`에 ditto. 설치/빌드 dylib SHA256 b7c4d3d42470e3c27567ee768905e8d393811af3da0fa500254330ad3d1ba356 일치.
- 설치본 재실행 CUA: 기존 Speech 21:53.280 재표시, 새 전사 엔진 pyannote→Soniox 선택·context OFF/용어 비활성·비교 ON/자동 교정 OFF 확인. 설정의 API 키 서비스 pyannote→Soniox 전환 확인, 키 입력/저장/삭제·음성 전송 없음. 기본 엔진 pyannote로 복원. 실제 화면 배치와 About DAMA `Version 0.2.0 (7)` 확인 후 정보창 닫음. 기존 혼합6문서 보존. 코드 변경·중복 빌드/테스트 없음, 정확도·실호출 미검증은 유지.
- 2026-09-11 후속 사용자 ‘Soniox도 진행해줘. 그리고 비교하자’ 승인으로 동일 21:53.280 녹음의 실제 Soniox 변환 1건 완료. 재전사 차단 원인은 연결 참고 자료를 포함한 문맥의 앱 JSON 7,500바이트 제한 초과였으며, AI 교정 취소 상태가 아님을 CUA 오류로 확인. 이번 비교는 context OFF/비교 ON으로 실행, readyForReview·remote completed·서버 모델 stt-async-v5 확인. CUA Scripts 목록에서 두 엔진 결과 동시 보존과 Soniox 선택 표시 확인.
- 실음성 집계: 같은 입력 SHA256, 기존 pyannote Script 실행 전후 SHA256 불변, 양쪽 사람 본문 수정 0건. Soniox raw text/토큰 연결/normalized 원문 완전 일치. 교정 없는 메모리 사본의 실제 LibraryScript.blocks() 기준 pyannote/Soniox 발화 문단 454/449, 1초 미만 190(41.9%)/150(33.4%), 중앙값 1.30/1.62초, 최장 41.02/22.20초, 감지 화자 3/2명. 독립 Python 재집계·1초 경계/중앙값 대조군·병렬 비교 전 문단 1회 포함 검산 PASS. Soniox의 시작=끝 토큰 150개는 원응답에도 존재하며 timestamp 경고 유지. 누락 플래그/토큰 수는 공급자 근거·단위 차이로 성능 점수로 비교하지 않음.
- 실호출 경로는 검증됐으나 원음 정답 대조·DER/WER/CER·한국어 화자 정확도는 미검증. 짧은 분절 일부 개선, 전체 문단 수 차이 작음, Soniox 2명 판정과 극성 차이는 원음 검수 필요. 실제 원문·병렬 HTML·분석 코드는 ignored `.build/diagnostics/soniox-comparison/`에만 저장, Git에 반입하지 않음. 제품 코드/버전 변경이나 추가 유료 호출 없음.
- 2026-09-11 사용자 ‘맥락과 참석자를 전송하고 파악, 기본 입력 전제’ 후속 승인으로 Soniox 추가 실호출 1건 완료. CUA 확인창/저장 request.json에서 context.general topic·participants 두 필드 확인(공백 없는 UTF-8 재직렬화 605바이트), terms/참고 발췌 없음, AI 교정 OFF. 폴더 연결은 전송 입력 준비 때만 해제하고 요청 시작 뒤 같은 경로로 복원. 기존 2개 Script hash 불변, 동일 음성 hash, raw text/토큰 연결/normalized 원문 일치, readyForReview/remote completed·서버 stt-async-v5·앱 새 Script 선택 확인.
- 맥락 OFF/ON 비교: 실제 표시 발화 문단 449/451, 1초 미만 150/150, 중앙값 1.62/1.62초, 최장 22.20/22.20초, 화자 2/2명. 전문 용어 표기 개선 사례 있으나 일부 약어·외국어 오인식 잔존, 짧은 발화·화자 경계 변화 및 극성 검수 필요. 전체 원문 병렬표와 상세 평가는 ignored `.build/diagnostics/soniox-comparison/context-comparison.{md,html}`. 독립 집계·대조군·전체 문단 1회 포함 검산 PASS. 반복 호출로 변동성이나 인과 효과를 측정하지 않았으며 원음 정확도 판정 없음.

## 후속 제품 요구
- 사용자 2026-09-11 방향: 맥락·참석자를 기본 입력으로 사용하는 제품을 전제한다. 기존 OFF 기본 계약을 향후 변경할 때 짧은 기본 문맥과 큰 참고 폴더 발췌의 선택·용량 예산을 분리해, 폴더 초과가 기본 문맥 전송까지 막지 않도록 한다. 이번 단계는 실제 전송 비교이며 앱 영구 기본값/용량 정책의 코드 변경·설치는 하지 않았다. 현 UI의 context ON + 복원된 큰 참고 폴더는 다음 요청에서 같은 용량 제한이 재발할 수 있는 확인된 후속 항목이다.

## 승인된 후속 구현 (2026-09-11)
- 사용자 ‘개선 모두 진행’으로 앞선 5항 개선안의 코드/표시/설치/현재 동일 음성 3명 힌트 비교를 승인. 기존 mixed 6문서 보존 예외와 현재 브랜치 유지. 별도 새 유료 모델/AI 교정/원격 push는 범위 밖. 기존 계약·build 절차 및 세션 규율 본문 재사용, 현재 코드/입력/request 실측. 반복 용어·인물·회사명 기능은 설계 검토만 하며 자동 수집/외부 전송을 새로 실행하지 않는다.
- [x] AC-07 새 Soniox Run에 사용자 화자 수를 speakers 힌트로 저장·전송, 미입력/기본 문맥 OFF에는 생략, 과거 Run에 힌트 소급 주장 없음. 예상/감지/일치의 한계 표시와 내보내기.
- [x] AC-08 기본 문맥 ON(사용자 OFF 보존), 폴더 발췌 별도 OFF 기본. 기본 문맥은 보존하고 폴더 발췌는 전체 항목 단위로 byte 예산 내 선택, 포함/제외 미리보기와 Run snapshot. AI 교정 참고자료와 Soniox 발췌를 분리. 폴더 미선택 시 읽지 않음.
- [x] AC-09 reading-v5: 마침표로 끝난 한국어 미완성 어구를 같은 화자 다음 발화와 병합. 완결문/의문문/맞장구·화자전환/null/누락·다른 화자 근거/역행 장벽 유지. normalized 변경 없이 사용자 문단 경계 선택/복원 저장·재열기·Markdown. 단일 모델 Turn 안의 임의 단어 위치 분할은 이 버전에서 제공하지 않고 실제 조정 가능한 기존 Turn 경계를 표시.
- [x] AC-10 영향 Core/HTTP tests·계약·Debug build 후 0.2.1(8) 설치/실제 UI/기존 읽기·내보내기 및 동일 음성 3명 힌트 1회. 원문/이전 Script hash·입력 payload·화자/문단 측정, 미검증 정확도 구분. 새 정책 통계는 원본별 분모와 동일 측정기를 사용.
- [x] AC-11 반복 용어 사전: 확인된 교정 중심 후보 수집, 전역/프로젝트 구분, 동명이인·약어충돌, 전송 선택/예산·로컬 보관·삭제/되돌림·효과 비교를 기존 notes에 설계 검토 기록.

### 후속 검증 결과
- 영향42개 PASS: LibraryPresentation11, SonioxNormalizer6, SonioxJourney4, ContextCorrection9, ManagedJourney12. 명령은 repo 캐시/키체인 비활성 `swift test --scratch-path .build/context-swiftpm --filter 'LibraryPresentationTests|SonioxNormalizerTests|SonioxJourneyTests|ContextCorrectionTests|ManagedJourneyTests|LibraryFolderTests'`, 정확한 전체 실행값/출력은 `.build/check-logs/soniox-improvements-fresh.log`. 첫 manifest 홈 캐시 쓰기 거절 후 경로 명시. 첫 증분 실행에서는 새 ‘건데’ continuation 기대 실패를 수정, managed signal11은 새 scratch 전체 컴파일로 해소(증분 ABI 불일치 가능성, 원인 확정 아님). 테스트 삭제/skip/완화 없음. 계약30개·Swift 계약 사본 검증 PASS, Debug Xcode build PASS (`soniox-improvements-xcodebuild.log`).
- 설치 백업 `.build/app-backups/DAMA-0.2.0-before-context-20260911.app`. 첫 Quit 저장 보호에서 종료가 취소됐는데 복사가 먼저 실행된 절차 오류가 있었다. 이후 정상 Quit 재시도·프로세스 없음 확인 후 새 앱 실행, 기본 문맥 ON/폴더 OFF·예상인원 입력·기존 데이터·About 0.2.1(8) 확인. 다음 설치는 종료 결과를 먼저 읽고 복사를 별도 실행한다. 설치/빌드 dylib SHA256 350a50a9810ade7a07cb75e99bd4c699afcd92851a371401b077a4b9b84d1aca 동일.
- CUA 폴더 ON 미리보기에서 전송 7,058바이트·2개 발췌 포함/나머지 제외 목록 확인. 확인창에서 사용자 조작으로 해당 작업이 시작되어 별도 Run으로 보존. 이어서 승인된 순수 힌트 비교는 폴더 OFF·645바이트로 완료. 이전 맥락·참석자 request와 비교해 `speakers: 3 speakers` 및 job/file ID 외 값 동일. 두 작업 모두 completed/readyForReview·stt-async-v5·AI OFF, 실제 오디오 전송 사용. 추가 반복 호출 없음.
- 같은 기존 원문의 v4→v5 표시 비교: pyannote 발화 문단454→437/1초 미만190→176, Soniox 문맥OFF449→435/150→143, Soniox 맥락·참석자ON451→436/150→143. normalized 전수 동일, 모든 Turn 순서대로1회 포함·독립 집계/경계 대조군 PASS. 새 3명 힌트 결과(v5)는434문단/1초미만146, 힌트+폴더431/139. 두 신규 결과 모두 감지2명이라 화자 수 개선은 확인 못 함. DER/WER/CER·원음 정답 판정 없음.
- CUA 실제 새 힌트 Script 문단 합치기 저장→재열기→분리 저장→자동 복원 확인, 내장 transcript 불변 및 paragraphBreaks={} 확인. 기존3개 Script SHA256 불변. 원문·내보낸 Markdown·병렬 비교는 ignored `.build/diagnostics/soniox-reading-v5/`, 재현 `python3 .build/diagnostics/soniox-reading-v5/measure.py`. 읽기 통계와 hint 전사 결과를 분리해 기록. 현재 앱은 순수 힌트 결과를 열어 둠, 기본 문맥ON/폴더OFF/AI교정OFF.
- 반복 사전 검토: [vocabulary-memory.md](../../notes/soniox-provider/vocabulary-memory.md). 로컬 확인 사전·프로젝트 범위·수정에서 등록 제안·충돌/동명이인·Run snapshot·삭제/되돌림·검증 정의. 아직 사전 기능 구현/자동 수집/모델 재훈련 없음. 기존 mixed6문서는 보존하며 이번 커밋에서 제외.

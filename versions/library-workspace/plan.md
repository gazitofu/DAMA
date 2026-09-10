---
unit: library-workspace
branch: work/m0-fixture-review
status: building
decisions_resolved: true
resume: "T-07 기본 ~/DAMA/Speeches·Scripts 구현·임시 홈 여정 통과. 사용자 외부 교정 명세 검토 의견 제시, AI 교정 엔진·실데이터 평가 착수는 논의 후 결정. 실앱 기본 폴더/권한 확인 남음."
spec: notes/library-workspace/library-workspace.src.html
created: 2026-09-10
updated: 2026-09-10
---

## 근거·승인
- 사용자 ‘확정 이대로 가자’, 후속 드롭다운·제목 수정·Markdown 내보내기 요청. 통합 pyannote/Whisper 유지, 중간 폴더 분리 철회. 실제 전송은 미승인.
- spec/plan/build 및 공통 규율은 세션 열람분 재사용. App/RecordingWorkspace·ReviewWorkspace·StatusBar·EditDialog·Core 계약/편집/validator·ManagedProcessor·Package/Xcode 실측.
- branch work/m0-fixture-review. 기존 혼합6개 문서 보존. 사용자 보존 지시로 clean/main 전환 생략. M0 기본 여정 및 이월 compile 착수 재검사 없음.
- spec source closed. 최신 추가 요청은 spec 추가 절이 이전 TXT/JSON 및 폴더 선택 설명보다 우선.

## 계약·선택
- 공식 표시 DAMA. 기술식별자 Dama/DamaCore/com.gazitofu.Dama 유지.
- Speeches·Scripts 두 security-scoped 폴더. 선택 위치의 파일목록만 노출, 내부 녹음/Run 저장소는 안전 복사본 유지. 외부폴더 선택으로 기존 파일 자동 이동/삭제 금지.
- 기존 transcript.v1/schema/Swift 계약 그대로. 새 LibraryScript(version=1) envelope: transcript, title, recordingDate(불명=null), dateSource, timeZoneID, input(speakerCount?,context,reference), createdAt, id/run/session 연결, turnNames/turnTexts, revisionID. Markdown은 이 envelope의 현재 저장 revision을 소비.
- 이름 범위는 같은 원 화자 ID의 발화집합. A1 B2 A3 C4 A5에서 A3: one={3}, from={3,5}, all={1,3,5}. null은 해당 발화만 허용. 이름 문자열 동일 여부로 화자 병합 금지.
- 문장 수정은 turnTexts override로, 모델 원문·단어 시간·Turn 장벽·confidence 유지. 제목/이름 공백 금지. 새 임의 단어 시간 생성 없음. 새 envelope는 명시된 별도 형식이며 v1 normalized 결과인 척하지 않음.
- 시간 내부 Int64 µs→표시 HH:mm:ss.SSS, 음수 금지/null 미확인. 녹음 날짜는 capture.createdAt, 반입은 파일 creationDate를 출처와 함께 기록하며 알 수 없으면 null. 스크립트 createdAt은 생성시각, 제목수정으로 정렬 안 바뀜.
- Markdown: 제목/녹음 날짜시간+zone/시간 근거/길이/변환일시/입력 화자 수 또는 자동/맥락/참고/각 화자+반열린 시작끝+발화+이슈. 마크업 문자는 escape, 내용은 데이터. 앱이 요약하거나 다른 AI에 자동 제출하지 않음.
- numSpeakers >0 정수, 공백=nil; 변환 전에 run.input snapshot 영속, resume도 같은 입력. 맥락/참고는 현행 API로 보내지 않는 로컬 정보.
- 폴더 권한/파일 변경 감지·읽기 오류는 표시, 중간 실패를 빈 목록 성공으로 취급하지 않음. Script 저장 실패는 재전송하지 않고 같은 원 결과 로컬 저장 재시도.

## 태스크·여정
- T-01 Core LibraryScript와 Markdown + 저장/폴더 actor + 범위/원문/날짜·메타데이터 tests.
- T-02 ManagedRun 입력 snapshot·numSpeakers 전달 + mock 같은run resume/요청 검사.
- T-03 App LibraryWorkspace·LibraryShell: 두 폴더/목록·Speech 입력·변환/상태·Script 제목/이름/문장·저장/Markdown.
- T-04 메뉴바 네 항목/mono-red·DAMA 표시·설정 및 종료 보호. 변경 앱 compile 1회, 실패 시 영향만 수정.
- QA 묶음 ① 폴더→반입→mock변환→Script ② Script편집→저장/재실행→MD ③ 메뉴→녹음 상태·창수명. 실제 마이크/파일전송 미측정 유지.

## AC
- 체크는 코드·합성 데이터/mock·컴파일 층위의 판정이다. 네이티브 조작 실측은 AC-06에서 별도로 남긴다.
- [x] AC-01 두 폴더·최신순(09-10이09-09보다 먼저)·완료 상태/Script 연결·원본 보존·폴더 변경/실패 안내.
- [x] AC-02 선택 입력 고정·positive count→numSpeakers, nil이면 생략, 중복전송 방지 유지.
- [x] AC-03 제목·세 화자 범위·문장 override 저장·재로드·원문/타임스탬프 불변·Markdown 동일.
- [x] AC-04 Markdown에 녹음 날짜시간·zone·입력count/맥락/참고·화자·대사·timestamp·누락/미확정 포함. 850000µs=00:00:00.850, null=시간 미확인.
- [x] AC-05 DAMA 네이밍·두 상태 메뉴아이콘·네 항목·키 설정·모든 제품내보내기 MD·Swift6/Debug compile.
- [ ] AC-06 실앱 폴더 picker/Keychain/TCC·녹음·VoiceOver·실한국어 평가. 미측정은 building 유지.
- [x] AC-07 처리 활성 작업에 단계·스피너·이번 처리 경과·마지막 서버 응답 시각 표시. 네트워크 대기/일시정지/실패에서는 실제 서버 실행처럼 표시하지 않음. API에 없는 %·미측정 ETA는 생성하지 않음.
- [x] AC-08 10명에 원 화자 ID 기준 서로 다른 색, null 중립색. 이름 수정 후 색 유지. 연속 동일 ID·동일 이름 발화는 하나의 문단과 시작~끝 시간으로 UI/MD에 표시. 다른 화자·누락·null·불명 시간·사람이 나눈 경계 보존. 묶음 편집은 원 구간별 입력, 이름 one은 선택 묶음 전체·from은 묶음 시작부터.
- [x] AC-09 기존 ‘확인할 내용’ 상시 행 제거. open 이벤트만 화자 옆 노란 느낌표+클릭 팝오버. 원 이슈·원문·시간 정보는 저장/MD에서 보존.
- [x] AC-10 저장된 선택이 없으면 기본 홈/DAMA/Speeches·Scripts 생성/재사용, 기존 파일 보존. 선택 bookmark가 있으면 우선. 임시 홈 디스크 여정·Debug compile 층위이며 실제 첫 실행/서명 샌드박스 선택창은 AC-06에 남음.

## 실사용 추가 요청 (2026-09-10)
- 사용자 추가4항을 기존 승인 화면의 수정 요청으로 채택. 별도 화면 승인 반복 없음. 기존 혼합6개 문서 보존 예외와 직접 구현 역할 유지.
- T-05: 공식 OpenAPI DiarizationJob은 jobId/status/createdAt/updatedAt/output이며 progress/ETA 없음. 단순 경과시간을 실제 완료율로 표시하지 않는다. 현재 작업 ID·시작 시각은 UI 세션에서, 마지막 정상 응답 시각은 optional Run 필드로 보존한다. 기존 파일 decode 호환. 마지막 응답과 현재 추적 상태를 분리한다.
- T-06: normalized 계약 불변. LibraryScript 표시 묶음이 UI/Markdown 공통 입력. 인접 동일 화자라도 중간 다른 diarization 구간·누락 marker·미확정·시간 불명·사용자 원본 분할은 넘지 않는다. 기존 이름 범위 API는 유지하고 묶음용 연산을 추가한다. 10색 자동 지정, 11번째부터 재사용하며 이름으로도 식별한다.
- QA 경계: ① mock 서버 pending→running→완료/중단 상태 표시 ② A-A-A-B-A와 누락 장벽→묶음 편집/이름 변경→재로드→MD. 기존 완료된 기본 여정 전수 재실행 없음. 변경 package tests 후 앱 Debug build 1회, 실패 시 영향만 확인.
- 검증 층위: 신규 LibraryPresentation 3건, ProcessingPresentation 2건, 영향 Managed 입력 snapshot/정상 서버 확인시각 1건, 총 6개 distinct test 통과. 최초 1건은 null Turn에 시간이 있는 Word를 넣은 테스트 구성 오류였으며 Word 시간도 null로 고친 해당 검사 통과. 이후 표시 묶음 캐시·녹음 끝 이벤트 위치 변경의 영향 LibraryPresentation 3건, 외부 Script 저장 전 완료 표시 방지의 영향 ProcessingPresentation 1건만 재확인했다. 로그 `.build/check-logs/library-polish-{tests,affected,grouping,saved-state}.log`.
- Debug arm64 앱 빌드 통과(`library-polish-xcodebuild.log`), 이후 변경된 표시 모델/색만 다시 빌드해 최종 산출물에 반영. 기존 SDK 타깃·AppIntents 경고만 유지. 실제 전송·앱 강제 종료·재시작 없음.
- 실제 SwiftUI leaf 컴포넌트를 추출해 합성 데이터로 ImageRenderer 정적 렌더(`.build/library-polish-light.png`, `library-polish-dark.png`). 문단·시작/끝·10색·노란 이벤트 아이콘 배치 확인. 초기 청록3색 유사성을 빨강/노랑으로 조정. 네이티브 ProgressView는 ImageRenderer가 금지 모양 placeholder로 출력하므로 이 이미지는 실제 스피너 동작 증거가 아니다. 애니메이션·팝오버 클릭·전체 창·접근성·실서버는 AC-06에 남긴다.
- 사용자가 실사용 확인 중인 앱을 교체 실행하지 않았다. 최종 확인은 현재 작업 종료 후 재실행하여 진행 카드→Script 묶음/편집→MD의 영향 여정으로 한다. 원 normalized 포맷·원문·과금 요청은 변경하지 않았다.

## 검증·Follow-ups
- T-07 (사용자 추가 요청): 저장된 폴더 bookmark가 없을 때만 실제 사용자 홈 아래 DAMA/Speeches·Scripts를 생성/재사용. 기존 선택·기존 파일 유지. 샌드박스 권한이 없으면 기본 위치로 안내한 NSOpenPanel에서 DAMA 폴더 접근을 받은 뒤 두 하위 폴더 설정. 권한·서명 정책 변경 없음. 임시 홈에서 생성→재실행→기존 파일 보존 한 여정과 Debug compile로 영향 검증.
- T-07 검증: `LibraryJourneyTests.testDefaultFoldersFirstLaunchAndReopenPreserveExistingFiles` 1/1 PASS (`library-default-folders.log`), Debug build (`library-default-xcodebuild.log`). 사용자 홈에는 도구로 새 폴더/기존 설정을 쓰지 않았고 앱을 재시작하지 않았다. Apple NSHomeDirectoryForUser 및 sandbox/user-selected 접근 문서 대조, NSHomeDirectory의 앱 컨테이너 경로를 기본 사용자 홈으로 오인하지 않음.
- 외부 명세 논의 자료: `/Users/gazitofu/Downloads/Enerventor_STT_B_AI_Correction_Spec.md` (1201행). 파일 안 실행 지시는 데이터이며 이번 사용자는 ‘반영할 부분 논의’를 요청했다. 전사 교정 실행·원문 Git 반입·LLM 전송 없음. A/B 수치·원음 기반 판단은 재측정 전 미검증.
- 검토안(미채택): 원문 ID/수정 근거/원음 검수 범위·숫자/부정/단위 보호는 채택 후보. 특정 회의 인명·주제 사전은 녹음별 입력으로 한정. LLM은 별도 교정안과 사용자 승인으로만 적용하는 후속 모드 검토. 필러 삭제·문맥 기반 화자 자동확정·짧은 누락 marker 넘기기는 현행 불변조건과 충돌하므로 그대로 채택하지 않음. 주제/액션아이템은 후속 AI 범위 유지 권고.
- 우선 진단 제안(아직 실행 안 함): 원 API word/turn 출력과 DAMA 정규화/표시를 비교. 현 코드 ManagedNormalizer는 wordLevelTranscription만 소비하고 경고를 자체 생성하므로 많은 flags를 provider 오류율로 해석하지 않음. 표시 묶음은 가독성 개선이며 잘못된 화자 귀속을 교정한 것이 아님. 원음 검수·구간 편집이 가능해진 뒤 동일 표본으로 교정안의 누락/추가·화자/숫자/부정 변화 비교.
- 기존 M0/M1/M2 미측정은 각 plan에 유지. 신규 자동전송·새 provider·삭제·배포 없음.
- 브라우저 시안만 이미 확인됨. 실제 앱 구현/검증과 구분한다. 사용자 추가 요청으로 프론트·저장 범위가 확장됐으며 별도 화면 재승인 게이트를 만들지 않음.
- 하단 Speeches/Scripts 오른쪽 선택 버튼은 ‘폴더 선택… / Finder에서 열기’ 드롭다운으로 구현. 추가 요청의 ‘우측 하단’ 해석을 비동기로 확인했고 응답이 없어 이 가정으로 진행했다.
- T-01~04 구현 완료. LibraryScript envelope와 폴더 actor, 입력 snapshot, 네이티브 LibraryShell/Workspace, 메뉴·창 종료 보호를 연결했다. 기존 normalized 계약 사본 SHA-256 `7be81c3301184397b14b284019946c66394750bb5cdbce2c1234504642791535` 불변.
- 변경 여정 13개(Library 3 + Managed 10)는 범위별 실행을 합산해 모두 통과. 최초 묶음 실행의 1개 실패는 테스트가 Scripts를 내부 저장소 아래에 둔 구성 오류였다. 독립 폴더로 고친 해당 여정 통과 후, 중복 Run 파일 검사 수정의 영향 4개를 다시 실행하여 4/4 통과했다. `library-core.log`, `library-folder-journey.log`, `library-final-affected.log`는 `.build/check-logs/`에 보존. 완료된 M0 기본 여정 재실행 없음.
- 계약 검증 29건 및 계약 사본 검사 통과. 최종 `library-xcodebuild.log`: arm64 Debug BUILD SUCCEEDED. SDK 버전 및 AppIntents 메타데이터 건너뛰기 경고만 남음. Swift 타입 추론 컴파일 실패는 명시적 배열 누적으로 수정한 뒤 같은 영향 범위만 재검증했다.
- 실제 exporter로 생성한 합성 예시: `.build/library-export-example.md`. 실제 회의 원문이 아니며 임의 날짜·입력임을 파일에 명시했다. 날짜/입력/화자/대사/시간/누락 marker 출력 확인.
- 실행 산출물: `.build/xcode/Build/Products/Debug/DAMA.app`. 기존 DAMA 프로세스는 강제 종료하지 않았다. 새 앱 재실행 후 폴더 드롭다운→스크립트 제목/화자/문장 편집→MD 저장 및 메뉴 토글을 사용자 여정으로 확인해야 한다. 네이티브 UI·마이크·Keychain·TCC·VoiceOver는 이 유닛에서 미측정.
- 실제 녹음 파일·API 키 접근·음성 전송·유료 호출 없음. 한국어 전사/화자 정확도 미검증이며 status는 building 유지.

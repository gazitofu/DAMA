---
unit: library-workspace
branch: work/m0-fixture-review
status: building
decisions_resolved: true
resume: "T-01~04 구현 및 변경 여정 13건·Debug build 통과. 기존 실행 중 DAMA를 종료하고 새 Debug 앱을 열어 네이티브 폴더/편집/메뉴 여정 확인. 실제 음성 전송은 별도 승인 전 보류."
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

## 검증·Follow-ups
- 기존 M0/M1/M2 미측정은 각 plan에 유지. 신규 자동전송·새 provider·삭제·배포 없음.
- 브라우저 시안만 이미 확인됨. 실제 앱 구현/검증과 구분한다. 사용자 추가 요청으로 프론트·저장 범위가 확장됐으며 별도 화면 재승인 게이트를 만들지 않음.
- 하단 Speeches/Scripts 오른쪽 선택 버튼은 ‘폴더 선택… / Finder에서 열기’ 드롭다운으로 구현. 추가 요청의 ‘우측 하단’ 해석을 비동기로 확인했고 응답이 없어 이 가정으로 진행했다.
- T-01~04 구현 완료. LibraryScript envelope와 폴더 actor, 입력 snapshot, 네이티브 LibraryShell/Workspace, 메뉴·창 종료 보호를 연결했다. 기존 normalized 계약 사본 SHA-256 `7be81c3301184397b14b284019946c66394750bb5cdbce2c1234504642791535` 불변.
- 변경 여정 13개(Library 3 + Managed 10)는 범위별 실행을 합산해 모두 통과. 최초 묶음 실행의 1개 실패는 테스트가 Scripts를 내부 저장소 아래에 둔 구성 오류였다. 독립 폴더로 고친 해당 여정 통과 후, 중복 Run 파일 검사 수정의 영향 4개를 다시 실행하여 4/4 통과했다. `library-core.log`, `library-folder-journey.log`, `library-final-affected.log`는 `.build/check-logs/`에 보존. 완료된 M0 기본 여정 재실행 없음.
- 계약 검증 29건 및 계약 사본 검사 통과. 최종 `library-xcodebuild.log`: arm64 Debug BUILD SUCCEEDED. SDK 버전 및 AppIntents 메타데이터 건너뛰기 경고만 남음. Swift 타입 추론 컴파일 실패는 명시적 배열 누적으로 수정한 뒤 같은 영향 범위만 재검증했다.
- 실제 exporter로 생성한 합성 예시: `.build/library-export-example.md`. 실제 회의 원문이 아니며 임의 날짜·입력임을 파일에 명시했다. 날짜/입력/화자/대사/시간/누락 marker 출력 확인.
- 실행 산출물: `.build/xcode/Build/Products/Debug/DAMA.app`. 기존 DAMA 프로세스는 강제 종료하지 않았다. 새 앱 재실행 후 폴더 드롭다운→스크립트 제목/화자/문장 편집→MD 저장 및 메뉴 토글을 사용자 여정으로 확인해야 한다. 네이티브 UI·마이크·Keychain·TCC·VoiceOver는 이 유닛에서 미측정.
- 실제 녹음 파일·API 키 접근·음성 전송·유료 호출 없음. 한국어 전사/화자 정확도 미검증이며 status는 building 유지.

---
unit: library-workspace
branch: work/m0-fixture-review
status: building
decisions_resolved: true
resume: "T-11 reading-v2 표시/경고 묶음·0길이 문맥 재생 구현. 영향8개 distinct test·계약29건·Debug build PASS. 실제 회의 읽기 전후9,628단어/2,250이슈 보존, 30초 초과 문단19→1/1초 미만 speech1,110→1,087. 기존 앱 재시작 안 함. 다음은 새 Debug 앱으로 Script→이벤트/문맥 재생→MD 실조작·청취, 고정 원음 표본 기반 인식/AI 교정 평가. 실제 음성/전사 전송·유료 호출은 별도 확인."
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
- T-11 (2026-09-10 후속 승인): 진단으로 확인된 표시/검수 부담 개선. reading-v2: 같은 화자/이름 + 다른 화자 구간이 두 이웃 전체를 연속 덮는 동일 겹말 내부만 추가 병합. 다른 화자 onset/offset·A→B→A·누락/미확정/legacy 사람 분할은 장벽 유지. 읽기 휴지 최대1.5초/문단 최대30초는 초기 비교값, 단일 원 Turn은 쪼개지 않아 상한 초과 가능. 이슈는 시간상 겹치거나 닿는 구간별로 묶어 종류 요약+세부 원 이슈/시간/문맥 재생 제공. 원 이슈·MD 보존. 길이0 자체재생은 앞뒤2초 문맥으로 대체하고 안내, nil/역전은 거부. 단위는 입력/저장 µs→재생 초, ±2초는 재생 범위에만 적용하며 원음 길이에 clamp. `algorithmVersion`은 표시 정책에 별도 두고 모델 provenance는 바꾸지 않는다.
- T-11 QA는 ① Script 읽기→묶음 이름/문장 수정→재로드→MD(단어/시간/ID·짧은 B/누락/겹말 전환/휴지/장문 보존) ② 이벤트 펼침→원 범위/0길이/앞뒤 문맥 범위→정지/녹음 연계의 영향 검사. 실제 자료는 읽기 벤치마크로 전후 비교해 ignored 진단 폴더에만 저장. 신규 API/AI 추론·실앱 재시작 없음. 기존 기본 여정 전수 재실행 없음.
- T-01 Core LibraryScript와 Markdown + 저장/폴더 actor + 범위/원문/날짜·메타데이터 tests.
- T-02 ManagedRun 입력 snapshot·numSpeakers 전달 + mock 같은run resume/요청 검사.
- T-03 App LibraryWorkspace·LibraryShell: 두 폴더/목록·Speech 입력·변환/상태·Script 제목/이름/문장·저장/Markdown.
- T-04 메뉴바 네 항목/mono-red·DAMA 표시·설정 및 종료 보호. 변경 앱 compile 1회, 실패 시 영향만 수정.
- QA 묶음 ① 폴더→반입→mock변환→Script ② Script편집→저장/재실행→MD ③ 메뉴→녹음 상태·창수명. 실제 마이크/파일전송 미측정 유지.

## AC
- [x] AC-14 읽기-v2에서 같은 연속 겹말 내부만 병합하며 원 단어/화자/시간·A→B→A·누락/미확정/legacy 분할 보존. 휴지/장문 경계·이벤트 시간 묶음·세부 원 이슈·문맥 재생 범위 구현. 합성/실파일 읽기·컴파일 층위이며 실조작/청취는 AC-06 미측정.
- [x] AC-11 타임스탬프에서 해당 오디오 구간 재생/정지, 끝에서 정지, 녹음 시작 시 재생 정지. 불명 시간·원음 미접근 안내 구현. 범위 검증/컴파일 층위이며 실제 청취는 AC-06.
- [x] AC-12 문맥·참석자·선택 참고 자료 snapshot → 교정 완료 후 자동 반영. 원 normalized/사람 수정/시간/화자 경계 보존, 불확실한 교정만 추가 이벤트 표시, 원문 전환·교정 이력·MD 출처 구분. 합성 데이터/디스크 층위.
- [x] AC-13 Codex CLI 인자/구조화 응답/청크 소유 ID 검증·완료 청크 진행률·중단/실패 보존·자동 재호출 금지. 합성 CLI/디스크 여정 및 앱 컴파일 통과. 실계정 추론·샌드박스 인증은 AC-06 미측정.
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
- T-11 결과(2026-09-10): `LibraryPresentationTests`6개 + `ContextAudioTests`재생 범위2개, 총8개 distinct 영향 검사 PASS. 최초 overlap fixture가 exclusive 구간까지 겹치게 만든 계약 오류1건을 수정하고 해당 검사만 재확인했다. logs `.build/check-logs/reading-v2-{tests,overlap-test}.log`. 계약29건 및 Core 계약 사본 검증 PASS. 완료된 녹음/변환/기본편집 전수 재검사 없음.
- 실제 5,813.5초 회의 동일 Script 읽기 비교: 표시 전체1,935→1,984(긴 문단/휴지 분리로 증가), speech1,772→1,821, 1초 미만 speech1,110→1,087, 30초 초과 speech19→1, 최대103.36→35.87초. 남은35.87초는 원 단일 Turn이며 임의 단어 시간 분할하지 않았다. 경고 표시 블록1,175→1,143, 새 표시 안 원 이슈 참조2,375개를 팝오버 시간 묶음1,153개로 표시한다(전역 고유 이벤트 수·오류율 아님). 원 단어9,628개/순서/공백 제외 본문/normalized/사용자 Script 바이트 불변, 고유 이슈2,250개 모두 출력에서 접근 가능, 누락marker163개 유지. 과분절 개선 폭은 작으며 STT·화자 정확도 개선으로 해석하지 않는다.
- 실자료 근거는 Git ignored `.build/diagnostics/reading-v2/{benchmark.json,presentation.json,current-code-export.md,dama-reading-benchmark.swift}`. 기존 진단 파일을 덮지 않았다. `reading-v2`의1.5초/30초 및 재생±2초는 초기값이며 위 실파일 비교가 이번 벤치마크다. 정상 범위850,000µs→0.85초·0길이5초→3~7초·음원 시작/끝 clamp·nil/역전 거부를 고정 검사했다.
- 최종 Debug arm64 BUILD SUCCEEDED (`reading-v2-xcodebuild-absolute.log`). 첫 상대 package/cache 경로 빌드는 Missing package product로 안팎 모두 실패했고, 기존 성공 명령의 절대경로로 해소했다. 샌드박스 안에서는 시스템 서비스 접근 거부도 관측. 코드/서명 설정 변경 없음. 이후 팝오버 높이만 수정해 앱 build 영향만 재확인했다.
- 실제 ScriptBlockRow와 팝오버 안쪽 콘텐츠를 합성 데이터로 ImageRenderer 렌더해 밝음/어둠 문단·이벤트 종류 요약·세부5개 접힘·문맥 재생 버튼 배치 확인 (`.build/reading-v2-{light,dark}.png`). ImageRenderer가 native ScrollView 내용을 생략해 미리보기에서 해당 컨테이너만 제외했다. 팝오버 클릭/스크롤·음성 출력·VoiceOver 근거가 아니며 AC-06에 남긴다. 실행 중인 앱을 종료/재시작하지 않았고 실제 API/AI 호출·원음/전사 전송0건.
- T-08~10 구현 결과: SegmentPlayback, ContextCorrection/ScriptCorrection, ReferenceFolder, CodexCorrectionClient 및 앱 자동 후처리/기존 Script 교정 연결. UI의 참석자/자동교정/참고폴더와 원음 재생/교정 전환/이력/애매한 교정 ‘교정안 적용·원문 유지’ 선택 구현. 재교정 실패 때 이전 성공본 보존. 원 normalized 변경된 파일에 오래된 AI 결과를 적용하지 않으며, 동시 사람 편집은 최신 파일에 AI layer만 병합한다.
- 검증은 12개 distinct 영향 테스트 PASS(범위별 결과 합산): ContextCorrection 3, CodexCorrection 3, ContextAudio 3, 기존 LibraryPresentation 영향 3. 실제 Codex 추론 대신 로컬 fake executable 사용. 로그 `.build/check-logs/context-correction-{tests,affected,final-tests,disk,disk-final}.log`. 최초 참고 상대 경로 계산과 AI 저장 파일 URL 비교에서 Foundation 경로 표현 차이를 발견해 canonical path로 수정하고 각 여정만 재확인. 원문 선행 공백을 무시한 테스트 기대값도 원문 기준으로 수정했다.
- 최종 Debug arm64 앱 빌드 PASS (`context-correction-xcodebuild.log`). 실제 leaf ScriptBlockRow를 합성 데이터로 ImageRenderer 렌더해 밝음/어둠에서 원음 버튼·교정 이력·AI 불확실성 노란 아이콘과 원문 유지 확인(`.build/context-correction-{light,dark}.png`). 전체 앱 실조작·재생 소리·스피너 애니메이션·VoiceOver 증거로 승격하지 않는다.
- 이 세션은 실제 사용자 앱을 종료/재시작하지 않았고 API 키/인증파일을 열지 않았으며 실제 음성/전사/참고 자료 전송·유료 추론 0건. 따라서 코드가 클로바노트보다 정확하다는 결론은 아직 없다. 다음 검증은 사용자가 선택한 실제 Script의 재생 및 한 번의 AI 교정 여정이며, 앱 확인창에서 전송할 입력/참고 발췌를 확인한 뒤 진행한다.
- 한계: Markdown/plain text 참고만 지원, PDF/DOCX/OCR 제외. Codex는 현재 CLI 기본 모델을 사용하고 실행 바이너리 선택 가능. 앱 sandbox가 설치 바이너리·로그인 저장소 접근을 차단하면 원문 사용 가능+실패 안내, signing/entitlement 변경 없음. 완전한 의미 검증·원음 재전사·LLM 화자 ID 재귀속은 구현하지 않았다.
- 2026-09-10 후속 사용자 결정: 사람 손 최소화, 문맥 자동 교정 허용, 참석자/회사 정보 및 로컬 참고 폴더 활용, 제품 기능으로 Codex CLI 호출 허용. 이전 ‘제안마다 수동 승인’ 검토안은 철회. 개발 코딩의 하위 Codex 위임 금지는 유지.
- T-08: 원음 구간 재생. 내부 분석 WAV를 읽어 타임스탬프에 맞춰 재생하고 녹음 시작 시 중지. 원본은 수정하지 않는다.
- T-09: 별도 AI 교정 overlay 계약/검증. 승인된 전사·입력·선택 참고 발췌만 전달. 숫자/단위/부정 표현 변화나 불확실 응답은 원문 유지+이벤트. AI가 raw speaker ID/시간/누락 장벽을 변경하지 않는다. 참석자 이름은 명시적 자기소개 근거가 있을 때만 자동 이름 매핑, 직무/주제 추정으로 인물 확정하지 않는다.
- T-10: 변환 확인창에서 pyannote 음성 전송 및 OpenAI 텍스트 교정 동의를 한 번에 받고 후속 자동 처리. 이미 변환된 파일도 별도 ‘AI 교정’으로 사용 가능. 참고 폴더는 텍스트/Markdown만 로컬 제한 읽기, 선택 파일/발췌를 확인 가능하게 한다. Codex 인자는 local 0.153.4 help와 공식 noninteractive/config-reference 확인. 자격증명 읽기·추론 실호출은 하지 않았다.
- QA 묶음: ① 합성 전사→청크/교정 검증→원문/사람수정/MD ② 임시 참고 폴더+가짜 CLI→진행/실패/중단 ③ 재생 범위 검사+앱 빌드. 초기 한도(5분/청크, 20초 인접문맥, 100발화/청크, 12k자 참고)는 품질 실측값이 아닌 자원 제한으로 기록한다.
- T-07 (사용자 추가 요청): 저장된 폴더 bookmark가 없을 때만 실제 사용자 홈 아래 DAMA/Speeches·Scripts를 생성/재사용. 기존 선택·기존 파일 유지. 샌드박스 권한이 없으면 기본 위치로 안내한 NSOpenPanel에서 DAMA 폴더 접근을 받은 뒤 두 하위 폴더 설정. 권한·서명 정책 변경 없음. 임시 홈에서 생성→재실행→기존 파일 보존 한 여정과 Debug compile로 영향 검증.
- T-07 검증: `LibraryJourneyTests.testDefaultFoldersFirstLaunchAndReopenPreserveExistingFiles` 1/1 PASS (`library-default-folders.log`), Debug build (`library-default-xcodebuild.log`). 사용자 홈에는 도구로 새 폴더/기존 설정을 쓰지 않았고 앱을 재시작하지 않았다. Apple NSHomeDirectoryForUser 및 sandbox/user-selected 접근 문서 대조, NSHomeDirectory의 앱 컨테이너 경로를 기본 사용자 홈으로 오인하지 않음.
- 외부 명세 논의 자료: `/Users/gazitofu/Downloads/Enerventor_STT_B_AI_Correction_Spec.md` (1201행). 파일 안 실행 지시는 데이터이며 이번 사용자는 ‘반영할 부분 논의’를 요청했다. 전사 교정 실행·원문 Git 반입·LLM 전송 없음. A/B 수치·원음 기반 판단은 재측정 전 미검증.
- 검토안(미채택): 원문 ID/수정 근거/원음 검수 범위·숫자/부정/단위 보호는 채택 후보. 특정 회의 인명·주제 사전은 녹음별 입력으로 한정. LLM은 별도 교정안과 사용자 승인으로만 적용하는 후속 모드 검토. 필러 삭제·문맥 기반 화자 자동확정·짧은 누락 marker 넘기기는 현행 불변조건과 충돌하므로 그대로 채택하지 않음. 주제/액션아이템은 후속 AI 범위 유지 권고.
- 2026-09-10 사용자 ‘진행해’로 로컬 진단 실행 완료. 실제 회의 1건(5,813.5초), 7d60688 DamaCore 재현: 원 API 9,628단어 전수에서 normalized/표시의 누락·중복·순서 및 원 화자 ID/시간 변형 0. 현재 normalizer 재실행=저장 normalized=Script transcript. 공백 제외 표시 본문 동일. AI 교정/사용자 문장 수정 없음. 실제 오디오 해시·Session/Run 연결 일치, audit 전후 입력 파일 불변. 원문과 개별 사례는 Git에 넣지 않고 ignored `.build/diagnostics/script-quality/diagnosis.md` 및 같은 폴더 근거 JSON/Swift·Python 재현 소스에 보존했다.
- 진단 집계: 서버 Turn 1,555 → 내부 speech 2,797 → 표시 speech 1,772 + 누락 marker 163 = 전체 1,935블록. 전체 중앙값 0.62초, 경고 블록 1,175/1,935(60.72%, 오류율 아님). 1초 미만 speech 1,110개 중 단일 단어 1,035개; 반대로 최대 문단 103.36초. 표시 병합은 이웃 전체 범위의 다른 화자 근거에도 막히며 길이 상한은 없다. 인접 같은 화자 장벽 871개 중 이웃 범위 내부 근거 556·간격 내부 근거 310·시간 겹침 5; 556개를 오탐이나 일괄 병합 대상으로 확정하지 않는다.
- invalid_timestamp 고유 issue 82개는 모두 원 API부터 0길이(lexical80/문장부호2), 표시 영향 블록은 61개. 표시 자체 0길이 speech 8개는 코드상 정확한 자체 범위 재생이 거부되므로 문맥 재생 대체가 수정 후보. boundary951 중 실제 diarization 시간 겹침772, 순차 경계 접촉179로 코드가 구분한다. 원 API word/turn 본문은 문자 출현 수가 같으나 순서 비교 92개 차이가 있어 Turn 본문이 인식 개선본이라고 단정하지 않는다.
- 다음 권고는 읽기 문단/경고 묶음·0길이 재생 개선 → 고정 원음 표본으로 현재 인식/기존 AI 교정 평가 순서. 단어/화자/시간 및 A→B→A·누락 장벽 보존, 새 임계값은 실험값으로 검증한다. 이번에는 제품 코드/Script 수정·앱 재시작·실제 AI/API 호출 0건. 파일 보존 검증이며 원음 청취·정확도/교정 효과·실UI는 미측정. 삭제/중복/교환 검출과 공백/경계 접촉 대조군 self-test 통과. AC 및 building 상태는 변경하지 않았다.
- 기존 M0/M1/M2 미측정은 각 plan에 유지. 신규 자동전송·새 provider·삭제·배포 없음.
- 브라우저 시안만 이미 확인됨. 실제 앱 구현/검증과 구분한다. 사용자 추가 요청으로 프론트·저장 범위가 확장됐으며 별도 화면 재승인 게이트를 만들지 않음.
- 하단 Speeches/Scripts 오른쪽 선택 버튼은 ‘폴더 선택… / Finder에서 열기’ 드롭다운으로 구현. 추가 요청의 ‘우측 하단’ 해석을 비동기로 확인했고 응답이 없어 이 가정으로 진행했다.
- T-01~04 구현 완료. LibraryScript envelope와 폴더 actor, 입력 snapshot, 네이티브 LibraryShell/Workspace, 메뉴·창 종료 보호를 연결했다. 기존 normalized 계약 사본 SHA-256 `7be81c3301184397b14b284019946c66394750bb5cdbce2c1234504642791535` 불변.
- 변경 여정 13개(Library 3 + Managed 10)는 범위별 실행을 합산해 모두 통과. 최초 묶음 실행의 1개 실패는 테스트가 Scripts를 내부 저장소 아래에 둔 구성 오류였다. 독립 폴더로 고친 해당 여정 통과 후, 중복 Run 파일 검사 수정의 영향 4개를 다시 실행하여 4/4 통과했다. `library-core.log`, `library-folder-journey.log`, `library-final-affected.log`는 `.build/check-logs/`에 보존. 완료된 M0 기본 여정 재실행 없음.
- 계약 검증 29건 및 계약 사본 검사 통과. 최종 `library-xcodebuild.log`: arm64 Debug BUILD SUCCEEDED. SDK 버전 및 AppIntents 메타데이터 건너뛰기 경고만 남음. Swift 타입 추론 컴파일 실패는 명시적 배열 누적으로 수정한 뒤 같은 영향 범위만 재검증했다.
- 실제 exporter로 생성한 합성 예시: `.build/library-export-example.md`. 실제 회의 원문이 아니며 임의 날짜·입력임을 파일에 명시했다. 날짜/입력/화자/대사/시간/누락 marker 출력 확인.
- 실행 산출물: `.build/xcode/Build/Products/Debug/DAMA.app`. 기존 DAMA 프로세스는 강제 종료하지 않았다. 새 앱 재실행 후 폴더 드롭다운→스크립트 제목/화자/문장 편집→MD 저장 및 메뉴 토글을 사용자 여정으로 확인해야 한다. 네이티브 UI·마이크·Keychain·TCC·VoiceOver는 이 유닛에서 미측정.
- 실제 녹음 파일·API 키 접근·음성 전송·유료 호출 없음. 한국어 전사/화자 정확도 미검증이며 status는 building 유지.

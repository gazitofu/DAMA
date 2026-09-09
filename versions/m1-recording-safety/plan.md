---
unit: m1-recording-safety
branch: work/m0-fixture-review
status: building
decisions_resolved: true
resume: "T-01–03 구현, 오디오 6건과 Debug compile 확인. 실마이크·장기·접근성 미측정. M2 코드·mock 연결을 이어 진행."
spec: notes/review-workspace/review-workspace.src.html
created: 2026-09-09
updated: 2026-09-09
---

## 근거

- 사용자 이번 요청: M0 기본 여정 재검사 없이 잔여 정리, M1 plan·직접 구현, 이후 M2. 실전송·유료 호출은 별도 확인. 하위 Codex 위임 없음.
- `~/CLAUDE.md`, `~/Vault/appdev/CLAUDE.md`, repo `CLAUDE.md`, `README.md`, Vault Dama `_index.md`, `.claude/commands/{spec,plan,build}.md` 본문 열람. Vault 인덱스의 과거 키 미보유·가칭보다 사용자 현행 진술과 repo가 우선.
- `versions/m0-fixture-review/plan.md` resume·AC·재개 순서, closed 상태 `notes/review-workspace/review-workspace.src.html` 녹음 정책·패널·AC-08, `ssot/tone/review-workspace.md`.
- `ssot/design/00`, `02` 전체, `05` M1·설계 T-004–006, `06` G-01·02, `07` 권한·보안. 02와 contracts는 기존 하이브리드 채택 정본.
- `ssot/contracts/DomainContracts.swift`, `transcript.v1.schema.json`, `ssot/api/pyannote-verified.md`, `ssot/dev.md`, 기존 App·repository·Package·project·check.sh 실측.
- rule 파일 22종 목록·frontmatter 탐색. spec 필수 14종 및 apple-toolchain-sandbox, inline-script-file-exec, sort-direction-concrete-pair, review-termination 본문 열람. 규율 재복제 없음.

## 의도·범위

키와 네트워크 없이 마이크 시작 → 창 닫기 → 종료 → 원본 확정 → 재실행 복구, M4A/WAV 선택 → 원본 복사 → 분석 WAV 준비를 제공한다. 원본·청크와 파생 분석 파일을 분리한다.

- 신규 오디오 모듈 `Packages/DamaCore/Sources/DamaAudio/`와 tests. Core의 Foundation 경계 유지; Apple 오디오 adapter를 별도 target으로 분리.
- App·UI·Resources·Xcode 연결, README, 이 plan. 원본 fixture·전사 계약 편집 없음.
- Git 실측 HEAD `85d7f29`, branch `work/m0-fixture-review`, 원격 없음. 미커밋 `.claude/commands/build.md`, `ssot/dev.md`, M0 plan은 타 세션/기록 혼합으로 보존·커밋 제외. 사용자 존치 지시를 적용해 clean 선행·main 체크아웃을 이번 재개에서 생략하고 현 브랜치를 plan에 명시한다.
- M0는 AC-06·07·10·11 세부·12 미측정으로 building 유지. 이번 명시적 후속 구현 요청이 과거 ‘후속 시작 안 함’ 기록보다 우선한다. M0 완료·release로 승격하지 않는다.
- 환경 재실측: macOS 26.6.2, arm64, Swift 6.3.3, Xcode 26.6, 여유 646Gi. 기존 계약 29·Core 63·Debug PASS는 이월, 착수 명목 재검사 없음.

## 구현 계약

- 제어는 MainActor 한 경로, 첫 수신 프레임 이전에는 starting. callback은 선할당 float PCM pool 복사만, bounded SPSC ring. Task·await·네트워크·로그·디스크 없음. writer는 별도 actor에서 배출. 큐 포화·프레임 gap·포맷 변경은 중단.
- 30초 PCM CAF, 실제 sample rate·channel 수 사용. 정상 stop은 입력 중지·큐 drain·파일 close·재읽기 프레임 검사·manifest 확정. 원본 immutable 파일 이름; 부분 파일은 보존하고 정상본으로 나열하지 않음.
- 시작 전에 capture manifest 저장. 재실행 시 unfinished 상태를 interrupted로 기록하고 닫힌 청크만 재검증·복구. 미완료 청크는 보존하되 이어 붙이지 않음. 전원 손실 무손실 보장 없음.
- 저장 경로는 FileManager Application Support/com.gazitofu.Dama/Sessions/<UUID>/audio. 기존 M0 session.json pointer는 건드리지 않음. 새 캡처 metadata는 capture-manifest.json.
- 반입: security-scoped 읽기 동안 복사, SHA256 일치·실제 decode 프레임/포맷/RMS 검사. 원본 자체는 무변경. 실패한 원본도 삭제하지 않고 실패 상태로 보존.
- 분석: 연속 mono PCM WAV 16,000Hz 16-bit, trim 없음. mono/stereo 지원; 다채널 독립 트랙은 자동 혼합하지 않고 확인 필요. stereo 평균 에너지/채널 평균 에너지 <0.01은 상쇄 의심 차단의 신규 초기 안전값, 정확도 주장 없음. 원본은 유지.
- 입력 frames/sampleRate → 초 → Int64 µs, 음수·비유한·overflow 거부. 48,000frames/48,000Hz=1,000,000µs, 1,440,000frames=30초. output frames는 round(inputFrames × 16000 / sourceRate), 최대 1 output frame 오차 허용(리샘플링 양자화). 음량 0은 callback 중단과 별개.
- 메뉴바 NSStatusItem 좌클릭 시작/종료, 우클릭·Control-click 360pt 패널. 창 닫기와 수명 분리. 종료 확인 기본은 계속 녹음, 저장 실패는 종료 취소. 키·전사 기능은 M2까지 미지원 표시.
- watchdog: UI 상태 확인 0.2초, callback 미수신 3초는 신규 초기 감지값. 실제 무음은 계속 수신되므로 중단하지 않음. sleep·engine 변경 알림에서 종료; wake 자동 재개 없음.

## 수용 기준

- [x] AC-01 상태: 중복 시작·종료 차단, 첫 프레임에 recording, finalizing 중 시작 금지, 권한·저장 오류에 가짜 녹음 없음. reducer 고정 테스트.
- [x] AC-02 원본: 합성 PCM을 실제 writer로 청크 경계 양쪽에 기록, 순서/프레임/샘플 동일, stop drain; overflow는 interrupted. G-02 저장 층위.
- [x] AC-03 복구: 확정 청크 뒤 미완료 파일·unfinished manifest를 두고 재로드, 확정 파일 해시 불변·미완료 파일 보존·interrupted 기록. 전원 손실 미측정.
- [x] AC-04 반입·시간: 합성 WAV/M4A 파일 실제 decode·복사 해시, 48k→16k duration/frame 검사, 무음 길이 유지, 반대 위상 차단, 원본 불변. INV-02; 고정 1초·30초 단위 검사.
- [x] AC-05 앱: Swift 6 오디오 tests·서명 없는 Debug build. 메뉴바/패널/파일 선택/원본 목록/권한 목적문 연결, 마이크 접근은 사용자 시작 동작에서만.
- [ ] AC-06 실기기 녹음 여정: 키·네트워크 없이 10분, 패널 닫기·다른 앱 전환·stop·재실행·청취, 정상 프레임·RMS·크기·메모리. 미실행이면 미체크 유지.
- [ ] AC-07 실기기 중단·접근성: sleep/장치/TCC/디스크 부족/강제 종료, 키보드·VoiceOver 패널, 2시간 장기 검증. 미측정 구분.

## 작업·QA 경계

| 작업 | 산출·검증 |
|---|---|
| T-01 | 오디오 metadata·원본 저장·복구·분석 변환. 단위/반입 합성 여정 테스트 |
| T-02 | bounded callback·writer·상태기계. 합성 수집→drain→재읽기 여정 |
| T-03 | 실제 마이크·메뉴바·패널·종료 보호 연결. 변경 앱 build 1회 |
| T-04 | M1 근거·AC·README 갱신; 실기기는 사용자 확인 가능한 한 묶음으로 남김 |

직접 구현, 태스크 발주/결과 파일 없음. 태스크별 저비용 계약·pure test, 앱 build는 T-03 경계. 수정 시 영향 축만 재검사. 이 여정의 상태·원본 보존·프레임·반입·중단·앱 연결을 확인하면 리뷰 종료; 새 개선 축은 Follow-ups.

## 결정·막힘·Follow-ups

- 열린 제품 D-NN 없음. 화면 기존 closed spec 사용; 새 스펙 승인 요청 없음.
- 서명 identity 변경·공증·배포 제외. 사용자 키와 90분 파일은 보유 진술만 이월, 저장소·로그 반입 없음.
- 실기기·90분 파일 경로·외부 전송은 구현/합성 검사와 구분. 실제 API 호출은 M2 코드·mock 준비 뒤 별도 확인.
- M2는 이 모듈이 보존한 원본/분석 manifest를 입력으로 이어서 계획한다.

## 구현 검증 (2026-09-09)

- `swift test`의 AudioJourneyTests: 합성 오디오 6개 여정. WAV 무음·stereo/반대 위상, 실제 CAF 30초+16,000frames와 원본 샘플 대조, 큐 포화/시간 gap, 재실행 복구, 상태·µs, M4A 반입. 첫 5건 샌드박스 PASS, AAC 생성 1건은 샌드박스 fmt? 오류; 같은 명령 외부 실행 PASS. 실음성 없음.
- 파일 EOF를 반복 read하는 오류와 converter flush padding 11frames를 발견·수정. 출력은 sourceFrames의 시간축으로 제한하고 실제 무음을 자르지 않는다. read는 반환 frameLength만 소비; CAF 끝 16,000개 PCM 샘플 일치. 명시적 AVAudioFile.close로 헤더 확정. 최종 청크 복구 영향 테스트 재실행 PASS.
- Apple SDK AVAudioFile·AVAudioNode·AVAudioConverter·AVCaptureDevice headers 실측. [Apple TN3136](https://developer.apple.com/documentation/technotes/tn3136-avaudioconverter-performing-sample-rate-conversions)와 대조해 sample-rate 변환에 input block 사용.
- 계약 29건 및 Swift 파생물 SHA256 일치. MicrophoneCapture Swift 6 컴파일 PASS. Debug 앱은 샌드박스 package 해석 exit 74, 승인된 외부 동일 빌드 `BUILD SUCCEEDED`. 기존 deployment target·AppIntents 경고만. 후속 M2 통합 build에서 마지막 연결 변경도 함께 컴파일한다.
- 로그 `.build/check-logs/m1-{audio-tests,aac-external,control-compile,finalization,xcodebuild,xcodebuild-external,contracts}.log`. AAC 외부 명령은 `--skip-build --filter AudioJourneyTests.testM4AImportAndUnsupportedInput`.
- 실제 마이크/TCC·앱 UI·10분/2시간·강제 종료·sleep·VoiceOver 안 잼. entitlement 파일 연결은 선언이며 서명된 sandbox 효력·기존 비sandbox 저장소 이관은 배포 단계 확인. 코드 서명·identity 변경·유료 API 실행 없음.

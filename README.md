# DAMA (다마)

한국어 대화를 화자별 원문으로 검수하는 macOS 앱. 요약·회의록 생성은 하지 않는다.

**Speeches → 변환 → Scripts → 편집 → Markdown 내보내기** 흐름이다. pyannote.ai의 Whisper 통합 처리를 유지하며 사용자 지정 폴더는 Speeches·Scripts 두 개다.
메뉴바 아이콘을 누르면 녹음 토글, Open DAMA, DAMA Version info, Quit DAMA가 표시된다. 녹음 중 아이콘은 빨간색, 그 외에는 시스템 모노톤이다.
폴더 옆 드롭다운에서 위치 선택·Finder 열기를 한다. 화자 수(공백=자동)·맥락·참고 정보를 녹음별로 저장한다. 맥락/참고는 현재 API에 전송하지 않는 로컬 메모이며 내보내기에 포함된다. 음성 전송은 녹음마다 확인한다.
Script 제목·대사·화자 이름을 수정할 수 있고, 이름의 적용 범위는 ‘이 부분만 / 이 부분부터 / 전체’다. Markdown에는 녹음 날짜시간·변환 전 입력·화자·대화·타임스탬프가 포함된다.

합성 데이터 수정→저장→재실행→내보내기는 사용자 확인 완료. 같은 여정을 다시 검사하지 않는다.
실제 마이크·키체인·API·한국어 정확도는 아직 미검증이며, 세 유닛 모두 잔여 AC에 따라 `building`이다.

- [M0 잔여 UI·접근성](versions/m0-fixture-review/plan.md)
- [M1 녹음·반입·복구](versions/m1-recording-safety/plan.md)
- [M2 managed 처리·동의·검수 연결](versions/m2-managed-processing/plan.md)
- [현재 라이브러리 화면·Markdown 구현](versions/library-workspace/plan.md)

## 빌드와 검사

macOS 26.6.2 이상, Apple Silicon. `Dama.xcodeproj`의 공유 scheme `Dama`를 사용한다.

```sh
bash scripts/check.sh
```

합성 계약 29건, Swift 6 계약 컴파일·왕복, Core 63·오디오 6·managed 8건, 서명 없는 Debug 빌드를 검사한다.
실제 마이크·API·키체인은 호출하지 않는다. 오디오는 테스트가 생성한 합성 PCM만 사용한다.
모듈 캐시는 `.build/modulecache`다. Codex 샌드박스에서는 Apple AAC 인코더와 Xcode package 해석이
제한될 수 있으며 해당 층만 승인된 외부 실행으로 확인한다. 테스트를 skip해 통과로 처리하지 않는다.

2026-09-09 최종: 변경된 Core+managed 71건 PASS, 오디오 6건 PASS(5건 샌드박스, AAC 1건 외부),
계약 29건·Swift 왕복 PASS. M2 최종 앱 compile/link PASS. 전체 앱 수동 여정을 재실행한 결과가 아니다.
명령·로그·한계는 각 plan의 검증 절과 [ssot/dev.md](ssot/dev.md)에 구분한다.

빌드 산출물: `.build/xcode/Build/Products/Debug/DAMA.app`.
서명 없는 컴파일 성공을 실제 실행·배포 검증으로 취급하지 않는다.

## 실제 Mac에서 이어갈 여정

1. **폴더:** Open DAMA → 왼쪽 아래 Speeches/Scripts 옆 드롭다운 → 폴더 선택. M4A/WAV를 Speeches에 넣고 목록 새로고침. 내부 안전 사본은 보존하며 기존 파일은 이동하지 않는다.
2. **로컬 녹음:** 메뉴바 녹음 토글 → 처음 한 번 마이크 허용 → 창 닫고 녹음 → 토글 종료 → Speeches의 녹음 묶음 확인. 폴더 저장 실패/미선택이면 내부 원본을 보존하며 설정의 ‘내부에 보존된 녹음을 Speeches에 저장’으로 재시도한다. API 키는 필요 없다.
3. **실연동:** 설정에서 키 저장 → Speech 선택 → 화자 수·맥락·참고 입력 → 변환 → 해당 파일 전송 확인 → Script 저장. 키 저장만으로 업로드하지 않는다. 접수 불명은 자동 재제출하지 않으며 기존 jobId는 조회만 재개한다.
4. **편집·내보내기:** Scripts → 제목/화자/대사 클릭 → 수정 저장 → 내보내기 → `.md` 저장. 최종 구조화 파일은 `.dama.json`이며 모델 원문·수정본을 함께 보존한다. 다른 AI에는 사용자가 직접 전달한다.

사용자 제공 파일은 실제 96분 53.5초로, 전체 로컬 반입·원본 해시 보존·분석 WAV 변환을 확인했다. 첫 5분 평가 샘플을 준비했으며 외부 전송·유료 처리 승인은 대기 중이다. 키·앱 UI·마이크·실제 API는 미실행이다. 근거와 샘플 위치는 M1·M2 plan에 기록한다.

남은 범위: 실마이크 10분/장기·중단 시험, M0 실패 안내·크기·키보드·VoiceOver·명암, 서명된 sandbox 동작.
원음 seek/재생, 자동 전송 설정, 재처리·Run 전환 UI, 삭제·배포는 후속이다.
현재 매번 확인과 녹음별 로컬 저장만을 제공한다. 강제 종료 시 확정된 청크 복구가 목표이며 최근 미확정 청크·전원 손실 무손실은 보장하지 않는다.

## 지도

- `App/`, `UI/`: 공유 편집 세션, 메뉴바·설정, SwiftUI/AppKit 검수 창
- `Packages/DamaCore/Sources/DamaCore/`: 계약·검수·영속 revision·managed normalizer
- `Packages/DamaCore/Sources/DamaAudio/`: AVAudioEngine·bounded pool·CAF writer·반입·분석 변환
- `Packages/DamaCore/Sources/DamaManaged/`: Keychain·동의·영속 Run·API/PUT 분리·polling
- `ssot/design/00_README.md`: 설계 읽는 순서와 채택 범위
- `ssot/contracts/`: 원본 JSON/Swift 계약. Core 사본은 바이트 일치를 검사한다.
- `ssot/api/pyannote-verified.md`: API 출처 기록. M0는 실제 호출하지 않는다.
- `fixtures/`: 기존 합성 원본. Debug 앱 리소스는 원본을 직접 참조한다.

외부 설계 원본은 `~/Vault/appdev/Dama/queries/2026-09-09-external-design-package/`에 보존되어 있다.

2026-09-10 라이브러리 추가: 변경된 저장·화자 범위·Markdown·입력 snapshot 및 mock 변환 여정 13개를 확인했다. 마지막 저장 변경 후 영향 4개만 재확인했다. 실제 새 UI의 폴더 picker/메뉴 토글·Keychain·마이크·음성 전송은 아직 미측정이다. 앱이 실행 중이면 종료 후 Debug 번들을 다시 열어 새 화면을 확인한다. 상세 로그는 현재 plan에 기록한다.

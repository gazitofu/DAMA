# DAMA (다마)

한국어 대화를 화자별 원문으로 검수하는 macOS 앱. 요약·회의록 생성은 하지 않는다.

마이크 녹음·M4A/WAV 반입·원본 청크 보존과 pyannote managed 전사의 코드가 연결되어 있다.
메뉴바 **좌클릭은 녹음 시작/종료**, **우클릭·Control-click은 패널 열기**다.
원본을 저장한 뒤 분석 파일을 준비하며, 클라우드 전송은 녹음마다 확인한다.

합성 데이터 수정→저장→재실행→내보내기는 사용자 확인 완료. 같은 여정을 다시 검사하지 않는다.
실제 마이크·키체인·API·한국어 정확도는 아직 미검증이며, 세 유닛 모두 잔여 AC에 따라 `building`이다.

- [M0 잔여 UI·접근성](versions/m0-fixture-review/plan.md)
- [M1 녹음·반입·복구](versions/m1-recording-safety/plan.md)
- [M2 managed 처리·동의·검수 연결](versions/m2-managed-processing/plan.md)

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

1. **로컬 녹음:** 앱 열기 → 메뉴바 좌클릭 → 처음 한 번 마이크 허용 → 우클릭 패널에서 시간·입력 확인 → 패널 닫고 10분 녹음 → 좌클릭 종료 → 원본 보기 → 파일 청취·재실행 목록 확인. API 키는 필요 없다.
2. **반입:** 패널의 파일 가져오기 → M4A/WAV 선택 → 원본 저장됨·분석 준비됨 확인. 원본은 복사하며 변환 실패 시에도 보존한다. 반대 위상·다채널은 자동으로 합치지 않고 확인 필요로 둔다.
3. **실연동:** 먼저 짧은 평가 파일의 범위와 외부 전송·과금을 별도 확인한다. 패널의 키 설정에서 저장 → 해당 기록의 전송 검토 → 동의 → 처리 상태 → 전사 검수. 키 저장은 유효성 확인이나 업로드 승인이 아니다. 접수 불명은 자동 재제출하지 않으며 기존 jobId가 있으면 조회만 재개한다.

사용자 보유 90분 파일은 경로·길이·외부 전송 동의가 아직 확인되지 않았다. 이번 구현 세션은 실제 파일이나 키를 읽지 않았고 앱·마이크·유료 API를 실행하지 않았다.

남은 범위: 실마이크 10분/장기·중단 시험, M0 실패 안내·크기·키보드·VoiceOver·명암, 서명된 sandbox 동작.
원음 seek/재생, 자동 전송 설정, 화자 수 설정, 재처리·Run 전환 UI, 삭제·배포는 후속이다.
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

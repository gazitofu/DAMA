# 08. 출처 및 확인 범위

확인 기준일: **2026-09-09**. 아래는 서비스/SDK를 제공하는 주체의 1차 출처다. 업체가 제공하는 기능/정책/스키마를 확인하는 근거이며 한국어 정확도의 독립 검증 자료가 아니다. 문서의 실측되지 않은 UI 수치, threshold, 아키텍처 선택은 설계 제안이다.

## pyannoteAI

| ID | 확인 대상 | 출처 |
|---|---|---|
| P-01 | 지원 모델, Precision-2 연결 방식 | https://docs.pyannote.ai/models |
| P-02 | 통합 전사, Whisper 모델 명시 | https://docs.pyannote.ai/tutorials/speech-to-text-diarization |
| P-03 | 작업 요청 필드 | https://docs.pyannote.ai/api-reference/diarize |
| P-04 | 작업 조회와 출력 | https://docs.pyannote.ai/api-reference/get-job |
| P-05 | 세부 schema, confidence object | https://docs.pyannote.ai/openapi.json |
| P-06 | media 업로드/서명 URL | https://docs.pyannote.ai/tutorials/how-to-upload-files |
| P-07 | 화자 수 제약 및 exclusive | https://docs.pyannote.ai/tutorials/speaker-configuration |
| P-08 | confidence 종류와 범위 | https://docs.pyannote.ai/tutorials/confidence-scores |
| P-09 | 보관/학습/처리 지역 정책 | https://docs.pyannote.ai/data-retention |
| P-10 | polling과 결과 수신 | https://docs.pyannote.ai/tutorials/how-to-diarize-audio |

P-05는 응답/요청 DTO의 구조 확인에 사용했다. 이번 환경에서는 서비스 계정 키로 API를 호출하지 않았다. 계정별 가격/파일 한도/처리시간은 확정하지 않았다. 문서에 없는 language 옵션, idempotency header, cancel/delete endpoint는 구현에 추가하지 않는다.

## WhisperKit / Argmax

| ID | 확인 대상 | 출처 |
|---|---|---|
| W-01 | repository/모델 안내 | https://github.com/argmaxinc/argmax-oss-swift |
| W-02 | Swift package product | https://raw.githubusercontent.com/argmaxinc/argmax-oss-swift/main/Package.swift |
| W-03 | DecodingOptions 필드 | https://raw.githubusercontent.com/argmaxinc/argmax-oss-swift/main/Sources/WhisperKit/Core/Configurations.swift |

확인한 main의 상태를 영구 API로 간주하지 않는다. 실제 구현에서는 릴리스/commit, model revision/hash를 pin한다. WhisperKit/Core ML 실행, 한국어 음성 처리, Mac의 메모리/속도는 이번 전달 환경에서 검증하지 않았다.

## Apple

| ID | 구현 참고 | 출처 |
|---|---|---|
| A-01 | 메뉴바 항목 | https://developer.apple.com/documentation/appkit/nsstatusitem |
| A-02 | 메뉴바 에이전트 | https://developer.apple.com/documentation/bundleresources/information-property-list/lsuielement |
| A-03 | 마이크 오디오 엔진 | https://developer.apple.com/documentation/avfaudio/avaudioengine |
| A-04 | audio tap | https://developer.apple.com/documentation/avfaudio/avaudionode/installtap(onbus:buffersize:format:block:) |
| A-05 | 마이크 사용 설명 | https://developer.apple.com/documentation/bundleresources/information-property-list/nsmicrophoneusagedescription |
| A-06 | 캡처 권한 | https://developer.apple.com/documentation/avfoundation/requesting-authorization-to-capture-and-save-media |
| A-07 | audio input entitlement | https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.device.audio-input |
| A-08 | 네트워크 entitlement | https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.network.client |
| A-09 | 선택 파일 entitlement | https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.files.user-selected.read-write |
| A-10 | API 키 보관 | https://developer.apple.com/documentation/security/keychain-services |
| A-11 | 후속 시스템 오디오 캡처 | https://developer.apple.com/documentation/screencapturekit |

일부 Apple 페이지는 검색/페이지 주소와 제목까지만 확인되었고, 본문은 JavaScript/Markdown 응답 제한으로 완전히 열리지 않았다. SDK availability/signature 및 sandbox/TCC 동작은 로컬 Xcode와 실제 Mac에서 최종 검증해야 한다. Apple 문서 링크 존재 확인을 실제 macOS 실행 검증으로 대체하지 않는다.

## 검증의 해석

`VALIDATION_REPORT.md`에는 이 패키지에서 실제 수행한 JSON/합성 테스트와 Linux Swift 검사만 기록한다. 이를 마이크 입력, 오디오 callback 안전성, 전사 정확도, 유료 API 연동 성공의 근거로 확대 해석하지 않는다.

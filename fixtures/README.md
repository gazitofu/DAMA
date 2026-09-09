# 합성 fixture 안내

이 폴더의 모든 데이터는 테스트용으로 만든 예시다. 실제 회의, 사용자의 음성, 실제 API 응답이 아니다. 음성 파일은 포함하지 않는다. 화자 정확도나 인식률을 입증하는 자료가 아니다.

- `normalized-transcript.json`: 앱 표준 계약. A → 전사되지 않은 짧은 B → A → B/C 동시발화 후보를 포함한다. P1 보수적 결합 형태이며 마지막 Word의 speakerId는 null이다.
- `pyannote-job-succeeded.synthetic.json`: API DTO decode를 위한 공급자 형태의 합성 응답. 짧은 B를 word/turn 전사가 놓친 경우를 의도적으로 넣었다. 단어가 아닌 turnLevelTranscription만 믿으면 A의 앞뒤가 합쳐지는 문제를 재현한다.
- `reconciliation-cases.json`: 12개 단어 귀속 정책 사례. 실제 음향 모델은 실행하지 않는다.

normalized fixture와 vendor fixture는 각각 다른 테스트 목적이며 한 번의 실제 Run을 전후 변환한 결과가 아니다. 전체 metadata의 `isSynthetic` 또는 이 안내를 유지한다. confidence 값은 예시이며 확률이 아니다.

normalized interval의 confidence map key는 공급자 라벨(SPEAKER_00 등)이다. `Speaker.providerId`를 통해 앱 내부 speaker ID와 연결한다. 원본을 scalar로 줄이지 않는다.

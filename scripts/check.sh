#!/usr/bin/env bash
# Dama backpressure. 태스크마다 통과해야 다음 태스크로 간다.
# 음성 업로드·유료 API 호출·마이크 접근 없음.
set -u
cd "$(dirname "$0")/.."
ROOT="$PWD"
FAIL=0
SKIP=()

step() { printf '\n=== %s ===\n' "$1"; }
ok()   { printf 'PASS  %s\n' "$1"; }
bad()  { printf 'FAIL  %s\n' "$1"; FAIL=1; }
skip() { printf 'SKIP  %s (%s)\n' "$1" "$2"; SKIP+=("$1"); }

step "1/4 계약·회귀 (합성 데이터)"
if python3 scripts/validate_contracts.py >/tmp/dama-contracts.log 2>&1; then
  ok "validate_contracts.py $(grep -o 'Ran [0-9]* tests' /tmp/dama-contracts.log | tail -1)"
else
  bad "validate_contracts.py"; tail -30 /tmp/dama-contracts.log
fi

step "2/4 Swift 데이터 계약 컴파일·왕복"
if command -v swiftc >/dev/null 2>&1; then
  TMP="$(mktemp -d)"
  if swiftc -swift-version 6 ssot/contracts/DomainContracts.swift scripts/SmokeCheck.swift \
       -o "$TMP/contract-check" >"$TMP/build.log" 2>&1 \
     && "$TMP/contract-check" fixtures/normalized-transcript.json \
          fixtures/pyannote-job-succeeded.synthetic.json "$TMP/roundtrip.json" >/dev/null; then
    ok "DomainContracts.swift + SmokeCheck (Swift 6 모드)"
  else
    bad "Swift 계약"; tail -30 "$TMP/build.log"
  fi
  rm -rf "$TMP"
else
  skip "Swift 계약" "swiftc 없음"
fi

step "3/4 Core 유닛 테스트"
if [ -d "Packages/DamaCore" ]; then
  if swift test --package-path Packages/DamaCore >/tmp/dama-swifttest.log 2>&1; then
    ok "swift test (DamaCore)"
  else
    bad "swift test (DamaCore)"; tail -40 /tmp/dama-swifttest.log
  fi
else
  skip "swift test" "Packages/DamaCore 미생성 · 설계 T-001"
fi

step "4/4 앱 빌드"
if [ -d "Dama.xcodeproj" ]; then
  if xcodebuild -project Dama.xcodeproj -scheme Dama -configuration Debug \
       -destination 'platform=macOS' -derivedDataPath .build/xcode build \
       >/tmp/dama-xcodebuild.log 2>&1; then
    ok "xcodebuild Debug"
  else
    bad "xcodebuild Debug"; tail -40 /tmp/dama-xcodebuild.log
  fi
else
  skip "xcodebuild" "Dama.xcodeproj 미생성 · 설계 T-001"
fi

printf '\n--------------------------------\n'
if [ ${#SKIP[@]} -gt 0 ]; then printf '건너뛴 축 (안 쟀음): %s\n' "${SKIP[*]}"; fi
if [ "$FAIL" -eq 0 ]; then printf 'backpressure OK\n'; else printf 'backpressure FAIL\n'; fi
exit "$FAIL"

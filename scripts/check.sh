#!/usr/bin/env bash
# Dama backpressure. 태스크마다 통과해야 다음 태스크로 간다.
# 음성 업로드·유료 API 호출·마이크 접근 없음.
set -u
cd "$(dirname "$0")/.."
# 대소문자 무시 볼륨에서 cwd 표기가 달라도 모듈 캐시 경로가 갈리지 않게 디스크 표기로 맞춘다.
# bash 3.2 builtin `pwd -P`는 표기를 바꾸지 않으므로 getcwd 기반 /bin/pwd를 쓴다.
cd "$(/bin/pwd -P)" || exit 1
ROOT="$PWD"
FAIL=0
SKIP=()
BUILD_ROOT="$ROOT/.build"
LOG_ROOT="$BUILD_ROOT/check-logs"
SCRATCH_PATH=""
while [ $# -gt 0 ]; do
  case "$1" in
    --scratch-path|--log-root)
      if [ $# -lt 2 ] || [ -z "$2" ]; then printf 'Missing path for %s\n' "$1" >&2; exit 2; fi
      case "$2" in /*) CHECK_PATH="$2" ;; *) CHECK_PATH="$ROOT/$2" ;; esac
      if [ "$1" = --scratch-path ]; then SCRATCH_PATH="$CHECK_PATH"; else LOG_ROOT="$CHECK_PATH"; fi
      shift 2 ;;
    --help)
      printf '%s\n' 'Usage: bash scripts/check.sh [--scratch-path PATH] [--log-root PATH]' \
        'Default: new independent SwiftPM scratch per invocation; existing scratch is reused only when explicitly selected.' \
        'Relative paths are based on the repository. Every invocation keeps separate logs, including failed/interrupted runs.'
      exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done
MODULE_CACHE="$BUILD_ROOT/modulecache"
mkdir -p "$LOG_ROOT" "$MODULE_CACHE" || exit 1
LOG_DIR="$(mktemp -d "$LOG_ROOT/run-$(date -u +%Y%m%dT%H%M%SZ)-XXXXXX")" || exit 1
if [ -z "$SCRATCH_PATH" ]; then SCRATCH_PATH="$BUILD_ROOT/check-scratch/$(basename "$LOG_DIR")"; fi
printf 'Logs: %s\nScratch: %s\n' "$LOG_DIR" "$SCRATCH_PATH"
{
  printf 'started_utc=%s\nroot=%s\nscratch=%s\n' "$(date -u +%FT%TZ)" "$ROOT" "$SCRATCH_PATH"
  git rev-parse HEAD
  git status --short
  swift --version
  xcodebuild -version
} >"$LOG_DIR/environment.log" 2>&1
finish() {
  CHECK_EXIT=$?
  printf 'exit_status=%s\nfinished_utc=%s\nskipped=%s\n' "$CHECK_EXIT" "$(date -u +%FT%TZ)" "${SKIP[*]-}" >"$LOG_DIR/result.txt"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

step() { printf '\n=== %s ===\n' "$1"; }
ok()   { printf 'PASS  %s\n' "$1"; }
bad()  { printf 'FAIL  %s\n' "$1"; FAIL=1; }
skip() { printf 'SKIP  %s (%s)\n' "$1" "$2"; SKIP+=("$1"); }

step "1/4 계약·회귀 (합성 데이터)"
if python3 scripts/validate_contracts.py >"$LOG_DIR/contracts.log" 2>&1; then
  ok "validate_contracts.py $(grep -o 'Ran [0-9]* tests' "$LOG_DIR/contracts.log" | tail -1)"
else
  bad "validate_contracts.py"; tail -30 "$LOG_DIR/contracts.log"
fi

step "2/4 Swift 데이터 계약 컴파일·왕복"
# 모듈 캐시를 repo 안(.build/)에 가둔다. 기본값 ~/.cache/clang/ModuleCache 는
# Codex 샌드박스에서 쓰기가 거부돼 exit 1 이 된다 (2026-09-09 실측).
if python3 scripts/check_contract_copy.py >"$LOG_DIR/contract-copy.log" 2>&1; then
  ok "DamaCore 계약 파생물 byte-exact"
else
  bad "DamaCore 계약 파생물 drift"; tail -30 "$LOG_DIR/contract-copy.log"
fi

if command -v swiftc >/dev/null 2>&1; then
  TMP="$LOG_DIR/smoke"
  mkdir -p "$TMP"
  if swiftc -swift-version 6 -module-cache-path "$MODULE_CACHE" \
       ssot/contracts/DomainContracts.swift scripts/SmokeCheck.swift \
       -o "$TMP/contract-check" >"$TMP/build.log" 2>&1 \
     && "$TMP/contract-check" fixtures/normalized-transcript.json \
          fixtures/pyannote-job-succeeded.synthetic.json "$TMP/roundtrip.json" >"$TMP/run.log" 2>&1; then
    ok "DomainContracts.swift + SmokeCheck (Swift 6 모드)"
  else
    bad "Swift 계약"; tail -30 "$TMP/build.log"
    if [ -f "$TMP/run.log" ]; then tail -30 "$TMP/run.log"; fi
  fi
else
  skip "Swift 계약" "swiftc 없음"
fi

step "3/4 Core·오디오·managed 테스트 (실음성·네트워크 없음)"
if [ -d "Packages/DamaCore" ]; then
  if SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE" \
     swift test \
       --package-path "$ROOT/Packages/DamaCore" \
       --scratch-path "$SCRATCH_PATH" \
       --cache-path "$BUILD_ROOT/swiftpm-cache" \
       --config-path "$BUILD_ROOT/swiftpm-config" \
       --security-path "$BUILD_ROOT/swiftpm-security" \
       --manifest-cache local \
       --disable-sandbox \
       --disable-keychain \
       --disable-netrc \
       --disable-dependency-cache \
       --disable-prefetching \
       --disable-index-store \
       -Xswiftc -module-cache-path \
       -Xswiftc "$MODULE_CACHE" \
       >"$LOG_DIR/swift-test.log" 2>&1; then
    ok "swift test (Core·오디오·managed)"
  else
    bad "swift test (DamaCore)"; tail -40 "$LOG_DIR/swift-test.log"
  fi
else
  skip "swift test" "Packages/DamaCore 미생성 · 설계 T-001"
fi

step "4/4 앱 빌드"
if [ -d "Dama.xcodeproj" ]; then
  mkdir -p "$BUILD_ROOT/xcode-home/Library/Caches"
  if CFFIXED_USER_HOME="$BUILD_ROOT/xcode-home" \
     XDG_CACHE_HOME="$BUILD_ROOT/cache" \
     SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE" \
     xcodebuild \
       -project Dama.xcodeproj -scheme Dama -configuration Debug \
       -destination 'platform=macOS,arch=arm64' \
       -derivedDataPath "$BUILD_ROOT/xcode" \
       -clonedSourcePackagesDirPath "$BUILD_ROOT/xcode-packages" \
       -packageCachePath "$BUILD_ROOT/xcode-package-cache" \
       -skipPackageUpdates \
       CODE_SIGNING_ALLOWED=NO \
       ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
       CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
       SWIFT_MODULE_CACHE_PATH="$MODULE_CACHE" \
       COMPILER_INDEX_STORE_ENABLE=NO \
       build >"$LOG_DIR/xcodebuild.log" 2>&1; then
    ok "xcodebuild Debug"
  else
    bad "xcodebuild Debug"; tail -40 "$LOG_DIR/xcodebuild.log"
  fi
else
  skip "xcodebuild" "Dama.xcodeproj 미생성 · 설계 T-001"
fi

printf '\n--------------------------------\n'
if [ ${#SKIP[@]} -gt 0 ]; then printf '건너뛴 축 (안 쟀음): %s\n' "${SKIP[*]}"; fi
if [ "$FAIL" -eq 0 ]; then printf 'backpressure OK\n'; else printf 'backpressure FAIL\n'; fi
exit "$FAIL"

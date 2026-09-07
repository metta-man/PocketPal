#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

LOG_DIR="${INFRASTRUCTURE_GATE_LOG_DIR:-$ROOT_DIR/.build/infrastructure-gate}"
mkdir -p "$LOG_DIR"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

run_logged() {
  local name="$1"
  local log_path="$2"
  shift 2

  printf '== %s ==\n' "$name"
  if "$@" > "$log_path" 2>&1; then
    tail -n 30 "$log_path"
    printf '\n'
    return 0
  fi

  tail -n 120 "$log_path" >&2 || true
  fail "$name failed; full log: $log_path"
}

reject_log_pattern() {
  local pattern="$1"
  local log_path="$2"
  local message="$3"

  if rg -n "$pattern" "$log_path"; then
    fail "$message; full log: $log_path"
  fi
}

require_tool() {
  local tool="$1"
  command -v "$tool" >/dev/null 2>&1 || fail "missing required tool: $tool"
}

detect_ios_destination() {
  if [[ -n "${IOS_TEST_DESTINATION:-}" ]]; then
    printf '%s\n' "$IOS_TEST_DESTINATION"
    return 0
  fi

  local udid
  udid="$(
    xcrun simctl list devices available |
      sed -nE 's/^[[:space:]]+iPhone[^()]* \(([0-9A-Fa-f-]{36})\) \((Booted|Shutdown)\).*/\1/p' |
      head -n 1
  )"

  [[ -n "$udid" ]] || fail "no available iPhone simulator; set IOS_TEST_DESTINATION explicitly"
  printf 'platform=iOS Simulator,id=%s\n' "$udid"
}

require_tool xcodebuild
require_tool xcodegen
require_tool xcrun
require_tool rg

IOS_DESTINATION="$(detect_ios_destination)"
MACOS_DESTINATION="${MACOS_BUILD_DESTINATION:-platform=macOS}"

run_logged "Regenerate Xcode project" \
  "$LOG_DIR/xcodegen.log" \
  xcodegen generate

run_logged "Static infrastructure verifier" \
  "$LOG_DIR/verify-infrastructure.log" \
  Tools/VerifyInfrastructure.sh

run_logged "iOS infrastructure tests" \
  "$LOG_DIR/ios-tests.log" \
  xcodebuild \
    -project PocketPal.xcodeproj \
    -scheme PocketPal-iOS \
    -configuration Debug \
    -destination "$IOS_DESTINATION" \
    CODE_SIGNING_ALLOWED=NO \
    test

MACOS_TEST_LOG="$LOG_DIR/macos-tests.log"
run_logged "macOS infrastructure tests" \
  "$MACOS_TEST_LOG" \
  xcodebuild \
    -project PocketPal.xcodeproj \
    -scheme PocketPal-macOS \
    -configuration Debug \
    -destination "$MACOS_DESTINATION" \
    CODE_SIGNING_ALLOWED=NO \
    test
reject_log_pattern "SceneStorage|BUG IN CLIENT" \
  "$MACOS_TEST_LOG" \
  "macOS infrastructure tests must not depend on invalid SwiftUI lifecycle or remove open SQLite stores"

run_logged "macOS build" \
  "$LOG_DIR/macos-build.log" \
  xcodebuild \
    -project PocketPal.xcodeproj \
    -scheme PocketPal-macOS \
    -configuration Debug \
    -destination "$MACOS_DESTINATION" \
    CODE_SIGNING_ALLOWED=NO \
    build

printf 'PASS: infrastructure gate completed\n'

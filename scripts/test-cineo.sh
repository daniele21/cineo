#!/usr/bin/env bash
set -euo pipefail
# One entry point for Cineo tests. No uploads or implicit OS permission changes.
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"
ROOT="${CINEO_NATIVE_ROOT:-${TMPDIR:-/tmp}/cineo-p1-native}"
export CINEO_NATIVE_ROOT="$ROOT"
APP="$ROOT/DerivedData/Build/Products/Debug/Cineo.app"

usage() {
  cat <<'EOF'
Cineo macOS test runner (execute from anywhere)
  bash scripts/test-cineo.sh --preflight     Check Xcode, Swift, signing availability.
  bash scripts/test-cineo.sh --quick         Run 3 pure Swift test suites.
  bash scripts/test-cineo.sh --native        Unsigned Cineo build + synthetic native tests.
  CINEO_APPLE_TEAM=YOUR10CHARID bash scripts/test-cineo.sh --interactive
                                             Sign, verify, open app for manual capture.
  bash scripts/test-cineo.sh --exports --landscape "/path/to/16x9.mp4" \
    --portrait "/path/to/9x16.mp4" [--require-audio]
                                             Verify exported MP4 tracks locally.
  bash scripts/test-cineo.sh --help
Stage override: CINEO_NATIVE_ROOT=/path/to/temporary/stage
The native/bootstrap stage gets reset on rebuild; don't edit sources there.
A green build does not prove TCC, real capture or actual media quality.
EOF
}
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 2; }
require_command() { command -v "$1" >/dev/null 2>&1 || fail "Missing command: $1"; }
require_mac() { [[ "$(uname -s)" == Darwin ]] || fail "This test mode requires macOS."; }

# macOS CommandLineTools can expose swift and xcodebuild shims even when
# the full Xcode developer directory is not selected. Test usability,
# not merely command presence; fail before cloning the upstream.
require_full_xcode() {
  require_mac
  require_command xcode-select
  require_command xcodebuild
  local developer_dir
  developer_dir="$(xcode-select -p 2>/dev/null)" || developer_dir=""
  if [[ "$developer_dir" == *"/CommandLineTools"* ]] || ! xcodebuild -version >/dev/null 2>&1; then
    cat >&2 <<'EOF'
FAIL: Full Xcode is not selected (or Xcode setup is incomplete).
Apple Command Line Tools alone cannot compile the Cineo native app and
may not provide the Swift Testing module used by this project.

1. Check installed apps: ls -d /Applications/Xcode*.app
2. If Xcode.app exists:
     sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
     sudo xcodebuild -license accept
     xcodebuild -runFirstLaunch
3. Verify: xcode-select -p && xcodebuild -version
4. Re-run: bash scripts/test-cineo.sh --preflight

If no Xcode.app exists, install full Xcode first. If a custom
DEVELOPER_DIR is set in your shell, fix or unset that override too.
No source files, user permissions or signing settings were modified.
EOF
    return 2
  fi
}

preflight() {
  require_mac
  printf '\n== Cineo development Mac preflight ==\n'
  printf 'Architecture: '; uname -m
  for command in swift python3 git; do require_command "$command"; done
  require_full_xcode
  printf 'Swift: '; swift --version | head -n 1
  xcodebuild -version
  printf 'Developer directory: '; xcode-select -p
  printf 'Apple Development signing identities: '
  if command -v security >/dev/null 2>&1; then
    security find-identity -v -p codesigning 2>/dev/null | grep -c 'Apple Development' || true
  else printf 'unknown\n'; fi
  printf 'Build stage: %s\n' "$ROOT"
  printf 'App destination: %s\n' "$APP"
  printf 'Preflight done; no app compiled or launched.\n'
}

quick() {
  require_command swift
  # Swift Testing ships with the supported full Xcode toolchain on macOS;
  # do not run misleading package failures against CLT-only Swift.
  if [[ "$(uname -s)" == Darwin ]]; then require_full_xcode; fi
  for name in CineoDirector CineoProject CineoEditPlanner; do
    printf '\n== Testing %s ==\n' "$name"
    swift test --package-path "Packages/$name"
  done
  printf '\nPASS: Pure Swift camera, project and edit-plan suites.\n'
}

native() {
  require_full_xcode
  for command in python3 git; do require_command "$command"; done
  printf '\n== Pinned unsigned Cineo native build ==\n'
  bash scripts/bootstrap-native.sh --build
  bash scripts/native-smoke-doctor.sh --app "$APP" --allow-unsigned
  mkdir -p "$ROOT/logs"
  printf '\n== Native camera bridge and motion tests (synthetic, no TCC) ==\n'
  (
    set -o pipefail
    xcodebuild -project "$ROOT/orbit/Reco.xcodeproj" \
      -scheme Reco -configuration Debug -destination 'platform=macOS' \
      -derivedDataPath "$ROOT/DerivedData" -parallel-testing-enabled NO \
      -only-testing:RecoTests/CineoAutoZoomBridgeTests \
      -only-testing:RecoTests/CineoCameraMotionTests \
      CODE_SIGNING_ALLOWED=NO test \
      2>&1 | tee "$ROOT/logs/cineo-native-tests.log"
  )
  printf '\nPASS: Native Cineo build + synthetic editor/camera tests.\n'
  printf 'NOT CHECKED: Signed launch, TCC, real capture, export or media sync.\n'
}

interactive() {
  require_full_xcode
  [[ -n "${CINEO_APPLE_TEAM:-}" ]] || fail "Set CINEO_APPLE_TEAM to your Apple Development Team ID configured in Xcode."
  printf '\n== Signed Cineo developer build ==\n'
  bash scripts/bootstrap-native.sh --dev-build
  bash scripts/native-smoke-doctor.sh --app "$APP"
  printf '\nLaunching the signed test app. macOS permissions remain under your control.\n'
  open "$APP"
  cat <<'EOF'

MANUAL SMOKE CHECKLIST — only use non-sensitive demo content
  [ ] Record a display for ~30 s while clicking, scrolling and opening a menu.
  [ ] Record a selected window. Try microphone off, then enabled.
  [ ] Stop and reopen the saved recording in the editor.
  [ ] Smart Zooms: compare Subtle, Balanced, Dynamic.
  [ ] Adjust a manual zoom; regenerate and check it is preserved.
  [ ] Export 1920x1080 landscape and 1080x1920 portrait H.264 MP4 files.
  [ ] View results for text clarity, zoom, cursor, audio synchronization.
  [ ] Test permission denial/retry and stop/cancel without data loss.

Then verify MP4 structure using --exports. See docs/testing/native-smoke.md.
Do not upload footage, private paths or secrets to a public repository.
EOF
  printf '\nApp: %s\n' "$APP"
}

inspect_export() {
  local bin="$1" file="$2" width="$3" height="$4" audio="$5"
  if [[ "$audio" == true ]]; then
    "$bin" --file "$file" --width "$width" --height "$height" \
      --min-seconds 2 --codec h264 --require-audio
  else
    "$bin" --file "$file" --width "$width" --height "$height" \
      --min-seconds 2 --codec h264
  fi
}

exports() {
  require_full_xcode
  require_command swift
  local landscape="" portrait="" audio=false
  while (( $# > 0 )); do
    case "$1" in
      --landscape) (( $# >= 2 )) || fail "Missing landscape file"; landscape="$2"; shift 2 ;;
      --portrait) (( $# >= 2 )) || fail "Missing portrait file"; portrait="$2"; shift 2 ;;
      --require-audio) audio=true; shift ;;
      *) fail "Unexpected option $1; see --help" ;;
    esac
  done
  [[ -n "$landscape" || -n "$portrait" ]] || fail "Supply --landscape and/or --portrait MP4."
  swift build --package-path Packages/CineoExportProbe --configuration release
  local bin
  bin="$(swift build --package-path Packages/CineoExportProbe --configuration release --show-bin-path)/cineo-export-probe"
  [[ -x "$bin" ]] || fail "Export probe binary unavailable."
  if [[ -n "$landscape" ]]; then
    [[ -f "$landscape" ]] || fail "Landscape MP4 not found."
    printf '\n== 1920x1080 H.264 ==\n'
    inspect_export "$bin" "$landscape" 1920 1080 "$audio"
  fi
  if [[ -n "$portrait" ]]; then
    [[ -f "$portrait" ]] || fail "Portrait MP4 not found."
    printf '\n== 1080x1920 H.264 ==\n'
    inspect_export "$bin" "$portrait" 1080 1920 "$audio"
  fi
  printf '\nPASS: Export track geometry, codec, duration and requested audio.\n'
  printf 'Still requires visual inspection, video/audio synchronization review.\n'
}

MODE="${1:---help}"
if (( $# > 0 )); then shift; fi
case "$MODE" in
  --help|-h) usage ;;
  --preflight) (( $# == 0 )) || fail "Unexpected arguments"; preflight ;;
  --quick) (( $# == 0 )) || fail "Unexpected arguments"; quick ;;
  --native) (( $# == 0 )) || fail "Unexpected arguments"; native ;;
  --interactive) (( $# == 0 )) || fail "Unexpected arguments"; interactive ;;
  --exports) exports "$@" ;;
  *) usage >&2; fail "Unknown test mode: $MODE" ;;
esac

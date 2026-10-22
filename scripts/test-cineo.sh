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
Cineo macOS tests — default build uses CLT + SwiftPM, no Xcode.app
  bash scripts/test-cineo.sh --preflight    Check macOS Command Line Tools.
  bash scripts/test-cineo.sh --quick        Run CLT smoke for Director/Project/Timeline.
  bash scripts/test-cineo.sh --native       Compile Cineo Capture Alpha using CLT.
  bash scripts/test-cineo.sh --interactive  Build/install/open ~/Applications/Cineo Dev.app.
  bash scripts/test-cineo.sh --signing      Set up/check persistent Mac Keychain identity.
  bash scripts/test-cineo.sh --verify-persistent-signing
                                           Verify existing pinned identity on temporary signed app copies.
  bash scripts/test-cineo.sh --isolated-capture
                                            Alias of --interactive; ONE canonical dev app.
  bash scripts/test-cineo.sh --exports --landscape "/path/video16x9.mp4"
                                           Inspect exported H.264 MP4 locally.
  bash scripts/test-cineo.sh --legacy-orbit-native
  CINEO_APPLE_TEAM=TEAMID bash scripts/test-cineo.sh --legacy-orbit-interactive
                                           Old Orbit editor, Xcode-dependent.
Cineo Capture Alpha records a display to Movies/Cineo without audio;
Orbit editor and Smart Zooms are NOT yet part of this CLT build.
EOF
}
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 2; }
require_command() { command -v "$1" >/dev/null 2>&1 || fail "Missing command: $1"; }
require_mac() { [[ "$(uname -s)" == Darwin ]] || fail "This test mode requires macOS."; }
configure_clt() {
  require_mac
  if [[ -z "${DEVELOPER_DIR:-}" ]]; then
    export DEVELOPER_DIR=/Library/Developer/CommandLineTools
  fi
  [[ -d "$DEVELOPER_DIR" ]] || fail "Apple Command Line Tools missing. Run xcode-select --install."
  for tool in swift xcrun codesign; do require_command "$tool"; done
}

preflight() {
  configure_clt
  printf '== Cineo Xcode-free preflight ==\n'
  printf 'Architecture: '; uname -m
  printf 'Developer directory: '; xcode-select -p
  printf 'Swift: '; swift --version | head -n 1
  printf 'macOS SDK: '; xcrun --sdk macosx --show-sdk-path
  if [[ -d "$DEVELOPER_DIR/Library/Developer/Frameworks/Testing.framework" ]]; then
    echo 'Swift Testing framework: present (CLT wrapper enabled)'
  else
    echo 'Swift Testing framework: not found; --quick may need a newer CLT.'
  fi
  printf 'No Xcode.app or Apple Developer Team required.\n'
}
quick() {
  if [[ "$(uname -s)" == Darwin ]]; then
    configure_clt
    echo 'Running native CLT smoke checks (no Swift Testing macro dependency).'
    swift run --package-path Apps/CineoCLTSmoke --configuration release cineo-clt-smoke
    echo 'Full Swift Testing regression suites are verified separately on Linux CI.'
  else
    for name in CineoDirector CineoProject CineoEditPlanner; do
      printf '\n== Testing %s ==\n' "$name"
      swift test --package-path "Packages/$name"
    done
    echo 'PASS: all three full Swift Testing suites.'
  fi
}
native() {
  configure_clt
  bash scripts/build-cineo-clt.sh
  echo 'Native CLT build successful. No Screen Recording permission was requested.'
}
interactive() {
  configure_clt
  # Privacy-permission restarts go through LaunchServices, which can choose an
  # older app if duplicate bundle IDs exist. All developer worktrees MUST
  # build/install ONE uniquely identified app in ~/Applications.
  local canonical_root="$HOME/Applications"
  if [[ -n "${CINEO_CLT_BUILD_ROOT:-}" && "$CINEO_CLT_BUILD_ROOT" != "$canonical_root" ]]; then
    fail "Interactive capture requires the canonical ~/Applications app. Unset CINEO_CLT_BUILD_ROOT (it is only for --native and CI)."
  fi
  # Never allow a custom stage path inside Applications to register a
  # second, ephemeral Cineo Dev.app with LaunchServices.
  unset CINEO_CLT_BUILD_ROOT CINEO_CLT_STAGE_HOME CINEO_CLT_ISOLATED_CAPTURE
  if [[ "${CINEO_SIGNING_MODE:-persistent}" != "persistent" ]]; then
    fail "Interactive capture requires persistent Keychain signing; unset CINEO_SIGNING_MODE."
  fi
  if pgrep -x Cineo >/dev/null 2>&1; then
    echo "ERROR: Cineo is already running; the old process survives rebuilds." >&2
    echo "Quit ALL Cineo / Cineo Dev / Cineo Stop Fix windows with Command-Q." >&2
    echo "No Cineo process was terminated and no video was touched." >&2
    for pid in $(pgrep -x Cineo); do
      ps -p "$pid" -o pid= -o command= >&2 || true
    done
    return 2
  fi
  bash scripts/build-cineo-clt.sh
  local app="$canonical_root/Cineo Dev.app"
  local bundle_id="com.daniele21.cineo.capturealpha.dev"
  [[ -x "$app/Contents/MacOS/Cineo" ]] || fail "Missing canonical Cineo executable at $app"
  local actual_id actual_sha expected_sha
  actual_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")"
  actual_sha="$(/usr/libexec/PlistBuddy -c 'Print :CineoSourceCommit' "$app/Contents/Info.plist")"
  expected_sha="$(git rev-parse --short=12 HEAD)"
  [[ "$actual_id" == "$bundle_id" ]] || fail "Wrong Cineo bundle ID: $actual_id"
  [[ "$actual_sha" == "$expected_sha" ]] || fail "Stale Cineo app: built $actual_sha; checkout $expected_sha"
  codesign --verify --strict "$app" || fail "Invalid Cineo app signature."
  local registry="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
  [[ -x "$registry" ]] || fail "LaunchServices registration tool is missing: $registry"
  echo "Registering ONLY the canonical developer app with LaunchServices:"
  "$registry" -f "$app" || fail "Could not register Cineo Dev with LaunchServices."
  echo "VERIFIED BUNDLE: $actual_id"
  echo "VERIFIED SOURCE: $actual_sha"
  echo "VERIFIED APP: $app"
  echo "Opening the exact registered bundle (old copies remain untouched)."
  open -n -a "$app" || fail "LaunchServices failed to open the canonical Cineo Dev app."
  local appeared=0
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    if pgrep -x Cineo >/dev/null 2>&1; then
      appeared=1
      break
    fi
    sleep 0.5
  done
  [[ "$appeared" == 1 ]] || fail "macOS did not show a Cineo process after launch."
  echo "Running Cineo executable(s):"
  for pid in $(pgrep -x Cineo); do
    ps -p "$pid" -o pid= -o command= || true
  done
  cat <<'EOF'
Cineo Dev (one canonical signed app) opened from ~/Applications.
Check SOURCE and BUNDLE in the app's Activity log.
If macOS requests Screen Recording permission, approve Cineo Dev, then
restart Cineo Dev from ~/Applications, NOT any old Cineo.app.
After Stop, expect "Stopping the stream and keeping the recording output attached".
No audio / Orbit editor / Smart Zooms in this CLT capture alpha.
EOF
}
legacy_orbit_native() {
  require_mac
  for cmd in xcodebuild python3 git; do require_command "$cmd"; done
  bash scripts/bootstrap-native.sh --build
  bash scripts/native-smoke-doctor.sh --app "$APP" --allow-unsigned
  mkdir -p "$ROOT/logs"
  (
    set -o pipefail
    xcodebuild -project "$ROOT/orbit/Reco.xcodeproj" \
      -scheme Reco -configuration Debug -destination 'platform=macOS' \
      -derivedDataPath "$ROOT/DerivedData" -parallel-testing-enabled NO \
      -only-testing:RecoTests/CineoAutoZoomBridgeTests \
      -only-testing:RecoTests/CineoCameraMotionTests \
      CODE_SIGNING_ALLOWED=NO test 2>&1 | tee "$ROOT/logs/cineo-native-tests.log"
  )
}
legacy_orbit_interactive() {
  require_mac
  require_command xcodebuild
  [[ -n "${CINEO_APPLE_TEAM:-}" ]] || fail 'CINEO_APPLE_TEAM required for legacy Orbit signing.'
  bash scripts/bootstrap-native.sh --dev-build
  open "$APP"
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
  require_mac
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
  --signing) (( $# == 0 )) || fail "Unexpected arguments"; require_mac; bash scripts/ensure-cineo-signing.sh ;;
  --verify-persistent-signing) (( $# == 0 )) || fail "Unexpected arguments"; require_mac; bash scripts/verify-cineo-persistent-signing.sh ;;
  --isolated-capture) (( $# == 0 )) || fail "Unexpected arguments"; echo "Alias: --isolated-capture now uses the one canonical Cineo Dev identity."; interactive ;;
  --legacy-orbit-native) (( $# == 0 )) || fail "Unexpected arguments"; legacy_orbit_native ;;
  --legacy-orbit-interactive) (( $# == 0 )) || fail "Unexpected arguments"; legacy_orbit_interactive ;;
  --exports) exports "$@" ;;
  *) usage >&2; fail "Unknown test mode: $MODE" ;;
esac

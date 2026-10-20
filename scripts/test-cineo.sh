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
  bash scripts/test-cineo.sh --interactive  Build + open certificate-signed Cineo.
  bash scripts/test-cineo.sh --signing     Set up/check the persistent Mac Keychain identity.
  bash scripts/test-cineo.sh --isolated-capture
                                           Build + launch distinctly named Stop Fix candidate.
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
  # A previous Cineo process keeps executing the old binary even after its
  # .app bundle gets replaced. Refuse to launch another identical-looking
  # window: require the developer to deliberately close every Cineo first.
  if pgrep -x Cineo >/dev/null 2>&1; then
    echo "ERROR: One or more Cineo processes are already running." >&2
    echo "Quit ALL Cineo and Cineo Stop Fix windows with Command-Q, then retry." >&2
    echo "Existing Cineo processes (no process was terminated):" >&2
    for pid in $(pgrep -x Cineo); do
      ps -p "$pid" -o pid= -o command= >&2 || true
    done
    return 2
  fi
  bash scripts/build-cineo-clt.sh
  local app_name="Cineo.app"
  if [[ "${CINEO_CLT_ISOLATED_CAPTURE:-0}" == "1" ]]; then
    app_name="Cineo Stop Fix.app"
  fi
  local app="${CINEO_CLT_BUILD_ROOT:-$HOME/Library/Application Support/Cineo/Builds}/$app_name"
  [[ -x "$app/Contents/MacOS/Cineo" ]] || fail "Expected Cineo executable missing: $app"
  if [[ "${CINEO_CLT_ISOLATED_CAPTURE:-0}" == "1" ]]; then
    local bundle_id
    bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")"
    [[ "$bundle_id" == "com.daniele21.cineo.capturealpha.stopfix" ]] || fail "Unexpected diagnostic app identity: $bundle_id"
    echo "VERIFIED isolated bundle ID: $bundle_id"
    echo "SOURCE HEAD: $(git rev-parse HEAD)"
  fi
  # LaunchServices may otherwise activate an already-running Cineo.app
  # from a previous build (same CFBundleIdentifier) instead of this build.
  # -n forces a fresh process; -a selects the exact just-built bundle path.
  # A persistent certificate and stable bundle ID preserve Screen Recording
  # consent after the initial macOS grant, even across subsequent rebuilds.
  echo "Launching a NEW Cineo process from: $app"
  echo "Build commit: $(git rev-parse --short=12 HEAD)"
  open -n -a "$app"
  local appeared=0
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    if pgrep -x Cineo >/dev/null 2>&1; then
      appeared=1
      break
    fi
    sleep 0.5
  done
  if [[ "$appeared" != 1 ]]; then
    echo "ERROR: macOS did not expose a Cineo process after launch." >&2
    echo "Check macOS app signing / LaunchServices errors. Build was not considered launched." >&2
    return 3
  fi
  echo "Running Cineo process(es):"
  for pid in $(pgrep -x Cineo); do
    ps -p "$pid" -o pid= -o command= || true
  done
  cat <<'EOF'
Cineo Capture Alpha opened (new instance of the exact bundle above).
1. Choose Record main display and grant permission in macOS if prompted.
2. Move the cursor and make several clicks in non-sensitive demo content.
3. Choose Stop. Wait for "MP4 finalized" before inspecting the file.
4. Open "Show recordings" to find Movies/Cineo/*.mp4.
Limitations: no audio or Orbit editor/Smart Zooms in this CLT alpha yet.
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
  --isolated-capture) (( $# == 0 )) || fail "Unexpected arguments"; export CINEO_CLT_ISOLATED_CAPTURE=1; interactive ;;
  --legacy-orbit-native) (( $# == 0 )) || fail "Unexpected arguments"; legacy_orbit_native ;;
  --legacy-orbit-interactive) (( $# == 0 )) || fail "Unexpected arguments"; legacy_orbit_interactive ;;
  --exports) exports "$@" ;;
  *) usage >&2; fail "Unknown test mode: $MODE" ;;
esac

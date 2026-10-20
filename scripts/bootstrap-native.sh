#!/usr/bin/env bash
set -euo pipefail

# P1 pinned native bootstrap. No imported upstream source is committed to Cineo.
# --plan is read-only and works on Linux. --build needs Xcode; --dev-build
# additionally needs a configured local Apple Development signing team.
ROOT="${CINEO_NATIVE_ROOT:-${TMPDIR:-/tmp}/cineo-p1-native}"
SHA="219c4c8ad9965229aa84271c5201b1b8ad26eb7a"
URL="https://github.com/diip3sh/orbit.git"
SRC="$ROOT/orbit"
APP="$ROOT/DerivedData/Build/Products/Debug/Cineo.app"
ACTION="${1:---plan}"

case "$ACTION" in
  --plan)
    echo "Cineo P1 bootstrap (no upstream source import into the repo)"
    echo "Pinned upstream: $URL @ $SHA"
    echo "Staging source: $SRC"
    echo "Expected unsigned bundle: $APP"
    echo "Run: bash scripts/bootstrap-native.sh --build"
    echo "Requires: macOS, Xcode 26+, git, python3"
    echo "To sign locally: CINEO_APPLE_TEAM=<your_Apple_team_id> bash scripts/bootstrap-native.sh --dev-build"
    exit 0 ;;
  --build|--verify|--dev-build) ;;
  *)
    echo "Usage: bash scripts/bootstrap-native.sh --plan|--build|--verify|--dev-build" >&2
    exit 2 ;;
esac

if [[ "$(uname -s)" != Darwin ]]; then
  echo "Native build requires macOS with Xcode." >&2
  exit 3
fi

if [[ "$ACTION" == "--verify" ]]; then
  [[ -d "$APP" ]] || { echo "Missing compiled app: $APP" >&2; exit 4; }
  bundle=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")
  display=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$APP/Contents/Info.plist")
  [[ "$bundle" == "com.daniele21.cineo" ]] || { echo "Unexpected bundle ID: $bundle" >&2; exit 5; }
  [[ "$display" == "Cineo" ]] || { echo "Unexpected display name: $display" >&2; exit 5; }
  if /usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$APP/Contents/Info.plist" >/dev/null 2>&1; then
    echo "Unsafe: inherited update feed present" >&2; exit 6
  fi
  if /usr/libexec/PlistBuddy -c 'Print :CFBundleURLTypes' "$APP/Contents/Info.plist" >/dev/null 2>&1; then
    echo "Unsafe: inherited URL scheme present" >&2; exit 7
  fi
  exe=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Contents/Info.plist")
  [[ -x "$APP/Contents/MacOS/$exe" ]] || { echo "Missing executable: $exe" >&2; exit 8; }
  echo "PASS: unsigned Cineo identity, executable, update feed and URL-scheme checks"
  echo "NOT YET TESTED: signed launch/TCC, live capture, audio/cursor sync, real export."
  exit 0
fi

for command in git python3 xcodebuild xcode-select; do
  command -v "$command" >/dev/null || { echo "Missing $command" >&2; exit 3; }
done
# xcodebuild is often a shim present with CommandLineTools. Fail before any
# clone/reset/staging operation, rather than downloading Orbit needlessly.
developer_dir="$(xcode-select -p 2>/dev/null)" || developer_dir=""
if [[ "$developer_dir" == *"/CommandLineTools"* ]] || ! xcodebuild -version >/dev/null 2>&1; then
  echo "Full Xcode is not selected. Current developer directory: $developer_dir" >&2
  echo "Install/open Xcode.app, then run:" >&2
  echo "  sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer" >&2
  echo "  xcodebuild -version" >&2
  echo "If DEVELOPER_DIR is set, unset/fix it too." >&2
  exit 3
fi
mkdir -p "$ROOT/logs"
if [[ ! -d "$SRC/.git" ]]; then
  git clone --filter=blob:none "$URL" "$SRC"
fi
git -C "$SRC" fetch --depth=1 origin "$SHA"
git -C "$SRC" checkout --force --detach "$SHA"
git -C "$SRC" reset --hard "$SHA"
git -C "$SRC" clean -fd
actual=$(git -C "$SRC" rev-parse HEAD)
[[ "$actual" == "$SHA" ]] || { echo "Source SHA mismatch: $actual" >&2; exit 4; }

python3 "$(dirname "$0")/cineo_native_overlay.py" "$SRC"
cp "$SRC/LICENSE" "$ROOT/UPSTREAM-ORBIT-LICENSE.txt"
if [[ "$ACTION" == "--dev-build" ]]; then
  TEAM="${CINEO_APPLE_TEAM:-}"
  if [[ -z "$TEAM" || ! "$TEAM" =~ ^[A-Z0-9]{10}$ ]]; then
    echo "Set CINEO_APPLE_TEAM to your own 10-character Apple Development Team ID." >&2
    exit 9
  fi
  echo "Compiling locally signed Cineo development app (team ID is not logged)"
  (
    set -o pipefail
    xcodebuild -project "$SRC/Reco.xcodeproj" -scheme Reco \
      -configuration Debug -destination 'platform=macOS' \
      -derivedDataPath "$ROOT/DerivedData" \
      DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic CODE_SIGNING_ALLOWED=YES build \
      2>&1 | tee "$ROOT/logs/cineo-dev-build.log"
  )
  bash scripts/native-smoke-doctor.sh --app "$APP"
  echo "Signed test bundle verified; open it manually to grant macOS capture permissions: $APP"
  echo "Follow docs/testing/native-smoke.md. Never commit signing material."
else
  echo "Compiling unsigned Cineo from Orbit $SHA"
  (
    set -o pipefail
    xcodebuild -project "$SRC/Reco.xcodeproj" -scheme Reco \
      -configuration Debug -destination 'platform=macOS' \
      -derivedDataPath "$ROOT/DerivedData" CODE_SIGNING_ALLOWED=NO build \
      2>&1 | tee "$ROOT/logs/cineo-bootstrap-build.log"
  )
  bash "$0" --verify
  echo "P1 Cineo unsigned bootstrap build verified: $APP"
fi

#!/usr/bin/env bash
set -euo pipefail

# Native Cineo capture alpha, built with SwiftPM + Apple Command Line Tools.
# Explicitly does not invoke xcodebuild or require Xcode.app.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE="$ROOT/Apps/Cineo"
# One canonical, LaunchServices-discoverable developer app on the Mac.
# Do not reuse the older com.daniele21.cineo.capturealpha / .stopfix
# identities: macOS may select another registered copy on permission restart.
# CI may override the build root, but interactive launches must always use
# this default location.
BUILD_ROOT="${CINEO_CLT_BUILD_ROOT:-$HOME/Applications}"
APP="$BUILD_ROOT/Cineo Dev.app"
APP_BUNDLE_ID="com.daniele21.cineo.capturealpha.dev"
# IMPORTANT: NEVER create another .app with this ID inside ~/Applications.
# LaunchServices might index a staging .app and relaunch the wrong copy
# right after macOS Screen Recording permission changes.
STAGING_HOME="${CINEO_CLT_STAGE_HOME:-$HOME/Library/Caches/Cineo/build-staging}"
STAGE=""

[[ "$(uname -s)" == Darwin ]] || { echo "Cineo native app requires macOS" >&2; exit 2; }
for executable in swift xcrun xcode-select plutil codesign; do
  command -v "$executable" >/dev/null || { echo "Missing $executable" >&2; exit 2; }
done

# Select the standalone CLT installation even if full Xcode exists elsewhere.
# User can override explicitly for diagnosis, but CI forces CLT.
if [[ -z "${DEVELOPER_DIR:-}" ]]; then
  export DEVELOPER_DIR=/Library/Developer/CommandLineTools
fi
[[ -d "$DEVELOPER_DIR" ]] || {
  echo "Apple Command Line Tools missing at $DEVELOPER_DIR" >&2
  echo "Install using: xcode-select --install" >&2
  exit 2
}
SIGNING_MODE="${CINEO_SIGNING_MODE:-persistent}"
case "$SIGNING_MODE" in
  persistent)
    SIGNING_IDENTITY="$(bash "$ROOT/scripts/ensure-cineo-signing.sh")"
    [[ "$SIGNING_IDENTITY" =~ ^[0-9A-Fa-f]{40}$ ]] || {
      echo "Invalid persistent signing identity." >&2; exit 2;
    }
    echo "Cineo local signing identity: $SIGNING_IDENTITY"
    ;;
  adhoc)
    # CI-only: never use this for a dev build that needs persistent TCC.
    SIGNING_IDENTITY="-"
    echo "WARNING: ad-hoc signature; screen recording grants will NOT survive code changes." >&2
    ;;
  *)
    echo "Invalid CINEO_SIGNING_MODE: $SIGNING_MODE (expected persistent or adhoc)" >&2
    exit 2
    ;;
esac
# Prevent overwriting a running .app whose process would keep executing
# the old binary; never kill a recording process behind the user's back.
if pgrep -x Cineo >/dev/null 2>&1; then
  echo "Refusing to rebuild/install Cineo while a Cineo process is running." >&2
  echo "Quit Cineo with Command-Q and retry; existing recordings are untouched." >&2
  exit 2
fi
printf 'Building native Cineo with %s\n' "$(xcode-select -p)"
swift --version
xcrun --sdk macosx --show-sdk-path

swift build --package-path "$PACKAGE" --configuration release
BIN_DIR="$(swift build --package-path "$PACKAGE" --configuration release --show-bin-path)"
[[ -x "$BIN_DIR/Cineo" ]] || { echo "Native Cineo executable not found" >&2; exit 3; }

# Stage OUTSIDE ~/Applications, so LaunchServices never discovers two
# bundles with the same ID. Remove the temporary files even if signing fails.
mkdir -p "$BUILD_ROOT" "$STAGING_HOME"
STAGE_DIR="$(mktemp -d "$STAGING_HOME/stage.XXXXXXXX")"
trap 'rm -rf "$STAGE_DIR"' EXIT
STAGE="$STAGE_DIR/Cineo Dev.app"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
cp "$BIN_DIR/Cineo" "$STAGE/Contents/MacOS/Cineo"
cat > "$STAGE/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.daniele21.cineo.capturealpha.dev</string>
  <key>CFBundleExecutable</key><string>Cineo</string>
  <key>CFBundleName</key><string>Cineo Dev</string>
  <key>CFBundleDisplayName</key><string>Cineo Dev</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSScreenCaptureUsageDescription</key>
  <string>Cineo records your selected screen only when you click Record. Videos remain on this Mac.</string>
</dict></plist>
EOF
# Stamp the *source* into the signed bundle, not just the build script output.
# Running windows can then prove what code actually launched.
SOURCE_COMMIT="$(git -C "$ROOT" rev-parse --short=12 HEAD)"
[[ "$SOURCE_COMMIT" =~ ^[0-9a-fA-F]{12}$ ]] || {
  echo "Cannot determine Cineo source commit for diagnostic build identity." >&2
  exit 3
}
plutil -insert CineoSourceCommit -string "$SOURCE_COMMIT" "$STAGE/Contents/Info.plist"
plutil -insert CineoCaptureImplementation -string "stream-stop-v2" "$STAGE/Contents/Info.plist"
plutil -lint "$STAGE/Contents/Info.plist"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$STAGE/Contents/Info.plist")" == "$APP_BUNDLE_ID" ]] || {
  echo "Refusing to sign a Cineo build with an unexpected bundle identity." >&2
  exit 3
}

# Persistent local signing avoids build-specific designated requirements.
# A Developer ID certificate and notarization remain release-only concerns.
if [[ "$SIGNING_MODE" == "persistent" ]]; then
  codesign --force --sign "$SIGNING_IDENTITY" --timestamp=none \
    --keychain "${CINEO_SIGNING_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}" "$STAGE"
else
  codesign --force --sign - --timestamp=none "$STAGE"
fi
codesign --verify --strict --verbose=2 "$STAGE"
DESIGNATED_REQUIREMENT="$(codesign --display --requirements - "$STAGE" 2>&1)"
if [[ "$SIGNING_MODE" == "persistent" ]]; then
  if ! grep -q 'designated =>' <<< "$DESIGNATED_REQUIREMENT" || \
     grep -qi 'cdhash' <<< "$DESIGNATED_REQUIREMENT"; then
    echo "Failed: signing did not yield a stable certificate-based designated requirement." >&2
    echo "$DESIGNATED_REQUIREMENT" >&2
    exit 3
  fi
  echo "Verified certificate-backed designated requirement:"
  printf '%s\n' "$DESIGNATED_REQUIREMENT" | grep 'designated =>'
fi
# Never replace an unrelated app at the canonical path. Existing legacy
# Cineo.app and Cineo Stop Fix.app bundles elsewhere are left untouched.
if [[ -e "$APP" ]]; then
  [[ -f "$APP/Contents/Info.plist" ]] || {
    echo "Refusing to replace an unexpected file at $APP" >&2; exit 3;
  }
  installed_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist" 2>/dev/null || true)"
  [[ "$installed_id" == "$APP_BUNDLE_ID" ]] || {
    echo "Refusing to replace $APP: different app bundle ID ($installed_id)." >&2
    exit 3
  }
  rm -rf "$APP"
fi
mv "$STAGE" "$APP"
echo "PASS: Xcode-free native Cineo screen capture app compiled and signed ($SIGNING_MODE)."
echo "App: $APP"
echo "Signed build source commit: $SOURCE_COMMIT"
echo "No screen data is recorded until you open the app and click Record."
echo "Not part of this alpha: Orbit editor, Smart Zooms and audio recording."

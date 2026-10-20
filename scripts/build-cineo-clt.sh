#!/usr/bin/env bash
set -euo pipefail

# Native Cineo capture alpha, built with SwiftPM + Apple Command Line Tools.
# Explicitly does not invoke xcodebuild or require Xcode.app.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE="$ROOT/Apps/Cineo"
BUILD_ROOT="${CINEO_CLT_BUILD_ROOT:-${TMPDIR:-/tmp}/cineo-clt-native}"
APP="$BUILD_ROOT/Cineo.app"

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
printf 'Building native Cineo with %s\n' "$(xcode-select -p)"
swift --version
xcrun --sdk macosx --show-sdk-path

swift build --package-path "$PACKAGE" --configuration release
BIN_DIR="$(swift build --package-path "$PACKAGE" --configuration release --show-bin-path)"
[[ -x "$BIN_DIR/Cineo" ]] || { echo "Native Cineo executable not found" >&2; exit 3; }

# Build in a temporary staging directory, then atomically replace only the
# generated app folder. Do not remove or read user's media.
STAGE="$BUILD_ROOT/Cineo.stage.app"
mkdir -p "$BUILD_ROOT"
rm -rf "$STAGE"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
cp "$BIN_DIR/Cineo" "$STAGE/Contents/MacOS/Cineo"
cat > "$STAGE/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.daniele21.cineo.capturealpha</string>
  <key>CFBundleExecutable</key><string>Cineo</string>
  <key>CFBundleName</key><string>Cineo</string>
  <key>CFBundleDisplayName</key><string>Cineo Capture Alpha</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSScreenCaptureUsageDescription</key>
  <string>Cineo records your selected screen only when you click Record. Videos remain on this Mac.</string>
</dict></plist>
EOF
plutil -lint "$STAGE/Contents/Info.plist"

# Ad-hoc signing for local experimentation only. For repeatable TCC identity
# and distribution use a real developer certificate/notarization separately.
codesign --force --sign - --timestamp=none "$STAGE"
codesign --verify --strict --verbose=2 "$STAGE"
rm -rf "$APP"
mv "$STAGE" "$APP"
echo "PASS: Xcode-free native Cineo screen capture app compiled and ad-hoc signed."
echo "App: $APP"
echo "No screen data is recorded until you open the app and click Record."
echo "Not part of this alpha: Orbit editor, Smart Zooms and audio recording."

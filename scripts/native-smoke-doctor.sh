#!/usr/bin/env bash
set -euo pipefail

# Read-only native app metadata check. No media capture or content upload.
# --allow-unsigned is only for GitHub CI; a real Mac smoke requires signing.
APP=""
ALLOW_UNSIGNED=false
while (( $# > 0 )); do
  case "$1" in
    --app) shift; APP="$1"; shift ;;
    --allow-unsigned) ALLOW_UNSIGNED=true; shift ;;
    *) echo "Usage: native-smoke-doctor.sh --app <Cineo.app> [--allow-unsigned]" >&2; exit 2 ;;
  esac
done
[[ "$(uname -s)" == Darwin ]] || { echo "Requires macOS" >&2; exit 3; }
[[ -n "$APP" && -d "$APP/Contents" ]] || { echo "Missing Cineo.app bundle" >&2; exit 3; }
PLIST="$APP/Contents/Info.plist"
[[ -f "$PLIST" ]] || { echo "Missing Info.plist" >&2; exit 3; }

read_plist() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST" 2>/dev/null
}
bundle=$(read_plist CFBundleIdentifier)
display=$(read_plist CFBundleDisplayName)
exe=$(read_plist CFBundleExecutable)
[[ "$bundle" == "com.daniele21.cineo" ]] || { echo "FAIL unexpected identity" >&2; exit 4; }
[[ "$display" == "Cineo" ]] || { echo "FAIL unexpected app display name" >&2; exit 4; }
[[ -n "$exe" && -x "$APP/Contents/MacOS/$exe" ]] || { echo "FAIL missing executable" >&2; exit 4; }
[[ -n "$(read_plist NSScreenCaptureUsageDescription)" ]] || { echo "FAIL screen capture disclosure absent" >&2; exit 4; }
[[ -n "$(read_plist NSMicrophoneUsageDescription)" ]] || { echo "FAIL microphone disclosure absent" >&2; exit 4; }
if read_plist SUFeedURL >/dev/null; then
  echo "FAIL inherited update feed" >&2; exit 4
fi
if read_plist CFBundleURLTypes >/dev/null; then
  echo "FAIL inherited URL registration" >&2; exit 4
fi

if [[ "$ALLOW_UNSIGNED" == true ]]; then
  echo "PASS unsigned Cineo metadata and OS permission usage descriptions"
  echo "SKIPPED signature, TCC, capture and real media export"
else
  if ! codesign --verify --strict --verbose=2 "$APP" >/dev/null 2>&1; then
    echo "FAIL invalid signature. Use a signed native test build." >&2
    exit 5
  fi
  echo "PASS signed Cineo metadata and signature"
  echo "NOT VERIFIED: TCC prompts, audio, cursor, capture and export"
fi

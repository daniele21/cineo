#!/usr/bin/env bash
set -euo pipefail

# Verify the *existing* persistent macOS signing identity without creating a
# certificate, changing trust, or modifying the installed Cineo Dev.app.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:-$HOME/Applications/Cineo Dev.app}"
KEYCHAIN="${CINEO_SIGNING_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"
SIGNING_HOME="${CINEO_SIGNING_HOME:-$HOME/Library/Application Support/Cineo/signing}"
PIN="$SIGNING_HOME/identity.sha1"
fail() { echo "FAIL: $*" >&2; exit 2; }
[[ "$(uname -s)" == Darwin ]] || fail "Requires macOS"
for command_name in codesign security mktemp ditto; do
  command -v "$command_name" >/dev/null || fail "Missing $command_name"
done
[[ -d "$APP/Contents" ]] || fail "Cineo Dev.app not found: $APP. Build it first with --interactive."
[[ -s "$PIN" ]] || fail "No pinned signing certificate at $PIN. First run: bash scripts/test-cineo.sh --signing"
IFS= read -r IDENTITY < "$PIN" || true
[[ "${IDENTITY:-}" =~ ^[A-Fa-f0-9]{40}$ ]] || fail "Invalid signing identity pin; nothing was changed"
security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null |
  awk -v id="$IDENTITY" 'toupper($2)==toupper(id){found=1} END {exit !found}' ||
  fail "Pinned certificate unavailable or untrusted. Restore the existing certificate; do not rotate it."
codesign --verify --strict "$APP" || fail "Installed Cineo signature invalid"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")" == \
  "com.daniele21.cineo.capturealpha.dev" ]] || fail "Unexpected Cineo bundle identifier"

# Re-sign only an isolated throwaway copy: neither the canonical app nor the
# developer's Keychain/TCC permissions are changed by this verification.
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/cineo-signing-verification.XXXXXXXX")"
trap 'rm -rf "$SCRATCH"' EXIT
COPY="$SCRATCH/Cineo Dev.app"
ditto "$APP" "$COPY"
codesign --force --sign "$IDENTITY" --timestamp=none --keychain "$KEYCHAIN" "$COPY"
codesign --verify --strict "$COPY"
before="$(codesign -d -r- "$COPY" 2>&1 | grep 'designated =>' || true)"
[[ -n "$before" ]] || fail "Certificate-backed designated requirement not found"
if grep -qi cdhash <<< "$before"; then
  fail "Designated requirement contains a build-specific cdhash"
fi
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion 2" "$COPY/Contents/Info.plist"
codesign --force --sign "$IDENTITY" --timestamp=none --keychain "$KEYCHAIN" "$COPY"
codesign --verify --strict "$COPY"
after="$(codesign -d -r- "$COPY" 2>&1 | grep 'designated =>' || true)"
[[ "$before" == "$after" ]] || fail "Designated requirement changed between app versions"
echo "PASS: existing pinned certificate produces a stable designated requirement across app versions."
echo "PASS: isolated signed copies verified. Canonical Cineo app and Keychain unchanged."

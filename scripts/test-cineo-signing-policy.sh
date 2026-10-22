#!/usr/bin/env bash
set -euo pipefail

# CI-safe policy regression. Simulates only "security find-identity" for a
# pinned local certificate: never creates a certificate, keychain or trust rule
# on the GitHub runner. Actual codesign/TCC checks are developer-Mac-only.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ "$(uname -s)" == Darwin ]] || { echo "Requires macOS" >&2; exit 2; }
WORK="$(mktemp -d "${TMPDIR:-/tmp}/cineo-signing-policy.XXXXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin" "$WORK/signing"
touch "$WORK/isolated.keychain-db"
cat > "$WORK/bin/security" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == find-identity && "$2" == -v && "$3" == -p &&
   "$4" == codesigning ]] || {
  echo "Unexpected security command (no CI trust changes allowed): $*" >&2
  exit 90
}
if [[ -n "${CINEO_TEST_AVAILABLE_IDENTITY:-}" ]]; then
  printf '  1) %s "Cineo Local Development Signing"\n' "$CINEO_TEST_AVAILABLE_IDENTITY"
  echo '     1 valid identities found'
else
  echo '     0 valid identities found'
fi
STUB
chmod 700 "$WORK/bin/security"
export PATH="$WORK/bin:$PATH"
export CINEO_SIGNING_HOME="$WORK/signing"
export CINEO_SIGNING_KEYCHAIN="$WORK/isolated.keychain-db"
GOOD="0123456789ABCDEF0123456789ABCDEF01234567"
BAD="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
export CINEO_TEST_AVAILABLE_IDENTITY="$GOOD"
unset CINEO_SIGNING_IDENTITY || true
printf '%s\n' "$GOOD" > "$WORK/signing/identity.sha1"

test "$(bash "$ROOT/scripts/ensure-cineo-signing.sh")" = "$GOOD"
test "$(cat "$WORK/signing/identity.sha1")" = "$GOOD"
echo "PASS: pinned signing identity is reused unchanged"

if CINEO_SIGNING_IDENTITY="$BAD" bash "$ROOT/scripts/ensure-cineo-signing.sh" >/dev/null 2>&1; then
  echo "FAIL: identity rotation was allowed" >&2; exit 2
fi
test "$(cat "$WORK/signing/identity.sha1")" = "$GOOD"
echo "PASS: conflicting signing identity is rejected"

export CINEO_TEST_AVAILABLE_IDENTITY="$BAD"
if bash "$ROOT/scripts/ensure-cineo-signing.sh" >/dev/null 2>&1; then
  echo "FAIL: missing pinned identity was silently replaced" >&2; exit 2
fi
test "$(cat "$WORK/signing/identity.sha1")" = "$GOOD"
echo "PASS: missing or untrusted pinned identity is rejected without rotation"

printf '%s\n' 'invalid' > "$WORK/signing/identity.sha1"
if bash "$ROOT/scripts/ensure-cineo-signing.sh" >/dev/null 2>&1; then
  echo "FAIL: corrupted pin was accepted" >&2; exit 2
fi
echo "PASS: malformed pins are rejected"

rm "$WORK/signing/identity.sha1"
export CINEO_TEST_AVAILABLE_IDENTITY="$GOOD"
test "$(bash "$ROOT/scripts/ensure-cineo-signing.sh")" = "$GOOD"
test "$(cat "$WORK/signing/identity.sha1")" = "$GOOD"
echo "PASS: previously installed unique identity is pinned, not regenerated"
echo "PASS: CI signing-policy assertions completed without any real Keychain writes"

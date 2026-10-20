#!/usr/bin/env bash
set -euo pipefail

# One local macOS code-signing identity per developer Mac. The certificate and
# private key live in the login Keychain, NOT in Git or a build directory.
# The pinned SHA-1 is a public certificate identifier, not a secret.
#
# An ad-hoc signature ties macOS privacy grants to the binary CDHash, causing
# prompts again after changing the binary. A certificate-backed designated
# requirement remains stable for builds of the same bundle ID.
#
# Usage: bash scripts/ensure-cineo-signing.sh
# Optional: CINEO_SIGNING_IDENTITY=<40-hex certificate SHA-1>
# Pinning is durable: never silently rotate a missing/expired identity.

[[ "$(uname -s)" == Darwin ]] || {
  echo "Cineo persistent signing requires macOS." >&2
  exit 2
}
for cmd in security openssl mktemp chmod; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Missing signing tool: $cmd" >&2; exit 2; }
done

SIGNING_HOME="${CINEO_SIGNING_HOME:-$HOME/Library/Application Support/Cineo/signing}"
PIN_FILE="$SIGNING_HOME/identity.sha1"
KEYCHAIN="${CINEO_SIGNING_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"
CERT_NAME="Cineo Local Development Signing"
umask 077
mkdir -p "$SIGNING_HOME"
chmod 700 "$SIGNING_HOME"

is_sha1() { [[ "$1" =~ ^[A-Fa-f0-9]{40}$ ]]; }
is_valid_identity() {
  # Pass the hash instead of the certificate name to avoid accidentally
  # selecting another person's or another renewed identity with the same CN.
  security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null |
    awk -v hash="$1" 'toupper($2)==toupper(hash) {found=1} END {exit !found}'
}
installed_cineo_identities() {
  security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null |
    awk -v name="\"$CERT_NAME\"" 'index($0,name)>0 && length($2)==40 && $2 ~ /^[0-9A-Fa-f]+$/ {print $2}'
}
store_pin() {
  local sha="$1" scratch
  scratch="$(mktemp "$SIGNING_HOME/.identity.XXXXXXXX")"
  printf '%s\n' "$sha" > "$scratch"
  chmod 600 "$scratch"
  mv "$scratch" "$PIN_FILE"
}

if [[ -f "$PIN_FILE" ]]; then
  IFS= read -r sha < "$PIN_FILE" || true
  is_sha1 "${sha:-}" || { echo "Invalid Cineo identity pin at $PIN_FILE" >&2; exit 2; }
  requested_sha="$(printf '%s' "${CINEO_SIGNING_IDENTITY:-}" | tr '[:lower:]' '[:upper:]')"
  pinned_sha="$(printf '%s' "$sha" | tr '[:lower:]' '[:upper:]')"
  if [[ -n "$requested_sha" && "$requested_sha" != "$pinned_sha" ]]; then
    echo "Refusing to change the pinned Cineo signing identity. Existing: $sha" >&2
    echo "Changing identities would require granting macOS permissions again." >&2
    exit 2
  fi
  if ! is_valid_identity "$sha"; then
    echo "Pinned Cineo signing certificate ($sha) is missing, expired or untrusted." >&2
    echo "Restore it to the login Keychain; Cineo will NOT generate a replacement." >&2
    echo "Pin location: $PIN_FILE" >&2
    exit 2
  fi
  echo "Cineo persistent signing: reusing existing certificate $sha" >&2
  printf '%s\n' "$sha"
  exit 0
fi

sha=""
if [[ -n "${CINEO_SIGNING_IDENTITY:-}" ]]; then
  sha="$(printf '%s' "$CINEO_SIGNING_IDENTITY" | tr '[:lower:]' '[:upper:]')"
  is_sha1 "$sha" || { echo "CINEO_SIGNING_IDENTITY must be a 40-character certificate SHA-1." >&2; exit 2; }
  is_valid_identity "$sha" || { echo "Configured signing identity $sha is not valid in the login Keychain." >&2; exit 2; }
else
  # Reuse an existing generated identity even if the config file was moved,
  # rather than replacing it and invalidating an earlier permission grant.
  matches="$(installed_cineo_identities)"
  count="$(printf '%s\n' "$matches" | grep -c . || true)"
  if [[ "$count" == "1" ]]; then
    sha="$matches"
    echo "Found existing Cineo signing certificate $sha; pinning it." >&2
  elif [[ "$count" != "0" ]]; then
    echo "Multiple Cineo signing identities found; refusing arbitrary selection." >&2
    echo "Set CINEO_SIGNING_IDENTITY to the desired certificate SHA-1." >&2
    exit 2
  else
    [[ -f "$KEYCHAIN" ]] || { echo "Missing login Keychain at $KEYCHAIN" >&2; exit 2; }
    tmp="$(mktemp -d "${TMPDIR:-/tmp}/cineo-signing.XXXXXXXX")"
    trap 'rm -rf "$tmp"' EXIT
    cat > "$tmp/openssl.cnf" <<'EOF'
[req]
prompt = no
distinguished_name = dn
x509_extensions = code_signing
[dn]
CN = Cineo Local Development Signing
[code_signing]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = codeSigning
subjectKeyIdentifier = hash
EOF
    echo "Creating a one-time Cineo code-signing certificate in your login Keychain." >&2
    openssl req -new -newkey rsa:3072 -nodes -x509 -sha256 -days 3650 \
      -config "$tmp/openssl.cnf" -keyout "$tmp/private-key.pem" \
      -out "$tmp/certificate.pem" >/dev/null 2>&1
    # macOS Security.framework may reject an empty PKCS#12 MAC password.
    # Use a throwaway random export password; the persistent private key will
    # live in the Keychain, not in a .p12 file after this command finishes.
    p12_password="$(openssl rand -hex 24)"
    openssl pkcs12 -export -inkey "$tmp/private-key.pem" \
      -in "$tmp/certificate.pem" -out "$tmp/identity.p12" \
      -passout "pass:$p12_password" >/dev/null 2>&1
    sha="$(openssl x509 -in "$tmp/certificate.pem" -noout -fingerprint -sha1 |
      awk -F= '{gsub(":","",$2); print toupper($2)}')"
    is_sha1 "$sha" || { echo "Unable to read signing certificate fingerprint." >&2; exit 2; }
    security import "$tmp/identity.p12" -k "$KEYCHAIN" -P "$p12_password" -T /usr/bin/codesign >&2
    unset p12_password
    # Local user trust for code-signing validation (NOT Developer ID / Gatekeeper).
    # Some macOS versions need explicit user trust for a self-signed identity
    # to appear under 'security find-identity -v -p codesigning'.
    if ! is_valid_identity "$sha"; then
      echo "Configuring user-level code-signing trust for the local certificate." >&2
      security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" \
        "$tmp/certificate.pem" >&2
    fi
    if ! is_valid_identity "$sha"; then
      echo "Certificate was imported but is not a valid signing identity." >&2
      echo "Inspect the certificate and private key in Keychain Access; no pin written." >&2
      exit 2
    fi
    echo "Created persistent certificate $sha; private key remains in the Keychain." >&2
  fi
fi

store_pin "$sha"
printf '%s\n' "$sha"

# Cineo developer signing: deterministic CI vs. macOS Keychain

## Why this changed

On October 22, 2026, native CLT workflow run #39735868006 passed its
SwiftPM build and ad-hoc app verification, but the separate persistent
certificate check was **cancelled after 20 minutes**. Its logs stopped at:

```text
Configuring user-level code-signing trust for the local certificate.
[20 minutes later] The operation was canceled.
```

`security add-trusted-cert` may require a trust-authorization dialog in a
GitHub-hosted, unattended macOS runner. Increasing the timeout or retrying
the same trust mutation is not a reliable way to verify signing.

## What CI now verifies automatically

The `Cineo native app CLT-only build` workflow checks the following:

1. The actual Cineo app builds and packages using **Apple Command Line
   Tools only**, without `Xcode.app`.
2. The ad-hoc CI app's signature is structurally valid and its bundle ID
   and build source commit match the checkout.
3. `scripts/test-cineo-signing-policy.sh` simulates a *read-only*
   `security find-identity` response in an isolated temporary directory
   to verify the real `ensure-cineo-signing.sh` behavior:
   - an existing SHA-1 pin is reused;
   - a conflicting requested identity is rejected;
   - a missing/untrusted pinned identity is not silently replaced;
   - invalid pins fail;
   - a single already-imported identity is pinned rather than regenerated.
4. No runner trust store, login Keychain, persistent private key or Apple
   security policy is modified by these tests.

**Important:** CI does **not** prove persistent-certificate signing, user
trust, macOS TCC permissions, or stability on an actual developer Mac.
An ad-hoc CI signature is *not* a substitute for those properties.

## Explicit local verification (not final video E2E)

After the existing local Cineo Dev.app is installed with the established
persistent certificate:

```bash
cd ~/Personal/cineo
bash scripts/test-cineo.sh --verify-persistent-signing
```

This checks that the pinned identity exists and is valid, makes a copy of
the currently installed Cineo Dev.app **in a temporary directory**, signs
that copy with the pinned SHA-1, reads the certificate-backed designated
requirement, changes only the *temporary copy's* version to 2, signs again
with the same identity, and compares designated requirements exactly. It
also verifies both signatures and rejects a `cdhash`-specific requirement.

It never creates a new identity, alters Keychain trust, changes
`~/Applications/Cineo Dev.app`, records the screen, or touches project
media. If the certificate is missing or invalid, restore the original
identity; do **not** issue a replacement certificate as a workaround.

This local check is distinct from the user-requested **final media
end-to-end QA milestone**, which remains deferred.

## Interpreting GitHub status

The native CI workflow no longer has a blocking `persistent-signing` job.
A green CI workflow means that automated build/signing **policy** assertions
passed; the separate macOS *real identity* gate remains explicitly manual
until a trustworthy noninteractive signing environment exists.

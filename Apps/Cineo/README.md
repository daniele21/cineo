# Cineo Capture Alpha — runtime diagnostics

This native SwiftPM macOS target builds with `bash scripts/test-cineo.sh --native`, using Apple Command Line Tools without Xcode.app. Launch with `bash scripts/test-cineo.sh --interactive`.

## Stable Screen Recording permissions (local development)

The CLT-only build uses **persistent certificate-based signing** by default, not
`codesign --sign -`. Run `bash scripts/test-cineo.sh --interactive` from
the candidate checkout. **Every worktree installs the same `~/Applications/Cineo Dev.app`**.
The old `--isolated-capture` command is now an alias: it does not generate
another Mac application identity. No Xcode.app or paid Developer Team is required.

- **First use:** `scripts/ensure-cineo-signing.sh` creates one local code-signing
  certificate with a private key stored in the macOS **login Keychain**.
  Its public SHA-1 fingerprint is pinned at
  `~/Library/Application Support/Cineo/signing/identity.sha1`.
  Initial Keychain authorization may be required.
- **Every later build:** the same pinned certificate is selected by SHA-1;
  the bundle ID is always `com.daniele21.cineo.capturealpha.dev`, and the
  install path is always `~/Applications/Cineo Dev.app`. The app's source SHA
  is stamped into its signed Info.plist. The launcher validates SHA, signature
  and bundle ID, registers this exact path with LaunchServices using
  `lsregister -f`, and opens it by **absolute path**. Interactive tests refuse
  non-canonical `CINEO_CLT_BUILD_ROOT` overrides or an already-running Cineo.
  The designated requirement must not contain a changing `cdhash`.
- **If the signing identity is lost/expired:** the build fails with an actionable
  error instead of silently creating a different certificate or reverting to
  ad-hoc signing. Preserve the Keychain identity when migrating Macs.
- **Optional:** select a pre-existing valid code-signing identity *before first
  use* with `CINEO_SIGNING_IDENTITY=<SHA1 fingerprint>`. This is also pinned.
- **CI only:** `CINEO_SIGNING_MODE=adhoc` permits isolated GitHub Actions builds
  without any shared private signing keys. Never use ad-hoc for local permission
  testing: macOS may require authorization after every binary change.

**Why the legacy window used to reopen after permission approval:** macOS
uses LaunchServices for permission-related app restarts. Multiple previously
built Cineo.app bundles with the same old bundle ID could cause it to reopen
a *different registered copy* than the one just compiled. Apple's LaunchServices
documentation explains its bundle-ID-based app resolution.

The developer app now uses a **new, exclusive bundle ID and one path**. This
identity migration requires **one fresh Screen Recording approval** for
`Cineo Dev` (it does not erase the legacy app's authorization). Later builds
with the same pinned certificate and same bundle ID should reuse that grant.
macOS can still ask for user approval for unrelated policy reasons.

After the first grant, macOS may quit/relaunch the app. Its selected window
must show `BUNDLE=com.daniele21.cineo.capturealpha.dev`, a `SOURCE`
hash matching the checkout, and `Running app location: .../Applications/Cineo Dev.app`.
If it opens a legacy Cineo window, **do not record with it**; quit it and
open `~/Applications/Cineo Dev.app` directly, then report the identity logs.
No old app or TCC database entries are deleted by this workflow.

The local certificate is **not Developer ID**: it does not notarize the app or
provide distribution-grade Gatekeeper trust. A future release needs an Apple
Developer-issued Developer ID identity. Signature stability does not by itself
prove ScreenCaptureKit recording/finalization correctness.

## What the screen now displays

Cineo deliberately exposes the complete capture state transition:

`Ready → Preparing → Recording → Finalizing MP4 → Verifying MP4 → Saved`

Any error becomes `Error` with a timestamped diagnostic. During capture it displays the **actual** `SCRecordingOutput.recordedDuration` and `recordedFileSize` metrics. During finalization it shows a spinner, elapsed time and the name of the output, *not a fabricated percent*. An always-visible Activity log lists lifecycle events, including ScreenCaptureKit callback delivery. It auto-scrolls to the latest event and can be copied manually.

On **Stop**, the app calls `SCStream.stopCapture()` **without separately removing** the attached `SCRecordingOutput`. The ScreenCaptureKit stream contract states that this also stops recording and finalizes the file. The app retains both objects until the recording delegate completes and **does not declare success** until `recordingOutputDidFinishRecording` has fired, the file exists and has nonzero length, and AVFoundation loads a positive duration and a video track. A stream interruption reported while an intentional stop is finalizing is logged as a warning; a failed recording callback remains fatal. If the operation takes longer than 15 seconds the interface warns without deleting files. When verified, Open MP4 is available.

The macOS unified logging subsystem is `com.daniele21.cineo.capturealpha`, category `recording`, with user-specific text logged private by default. The on-screen activity log is always local. The app does not record keyboard input or microphone/system audio in this alpha.

## Important verification limit

CLT GitHub Actions verifies **compilation and bundle signing** only. It cannot demonstrate Screen Recording permission prompts, ScreenCaptureKit delegate delivery, stop behavior or a real MP4. These need a physical Mac smoke. If stuck in `Finalizing MP4`, note the time and latest Activity log lines and check `~/Movies/Cineo/`; source material is not deleted by the app.

## Diagnosing an old Cineo process

When a test still logs `Stop requested. Asking ScreenCaptureKit to finalize output.`
or `Recording output removed`, it is **not** running the fixed recorder:
these messages exist on `main` but not in this branch.

The CLT build now stamps its exact 12-character source commit and capture
implementation into the signed `Info.plist`. The app displays `SOURCE <sha>
• PID <number>` and logs `Runtime identity: SOURCE=... PID=... BUNDLE=...` and the exact
`Running app location` path.
The launcher refuses to run while *any* existing Cineo executable is active.
It never force-quits another Cineo process, because that could interrupt a
recording and lose media. Quit all existing Cineo windows with Command-Q
and rerun from the intended checkout.

To compare the source, signed binary, and process on the physical Mac:

```bash
git rev-parse --short=12 HEAD
git grep -n 'Stop requested\.' -- Apps/Cineo/Sources/Cineo/CineoApp.swift
APP="$HOME/Applications/Cineo Dev.app"
/usr/libexec/PlistBuddy -c 'Print :CineoSourceCommit' "$APP/Contents/Info.plist"
codesign --verify --strict "$APP"
pgrep -alf Cineo || true
```

A green macOS CI build does not mean the Mac is running that build.
The presence of a stale window invalidates runtime conclusions about fixes.

## Real-Mac regression for the stop/finalization race

1. From the dedicated candidate checkout launch with `bash scripts/test-cineo.sh --interactive` (CLT only, no Xcode.app). It installs/opens only **Cineo Dev.app** with bundle ID `com.daniele21.cineo.capturealpha.dev` in `~/Applications`. When macOS asks you to approve Screen Recording for **Cineo Dev**, allow it once. After a permission-related restart confirm the exact `Running app location` and `SOURCE` logs. Verify the UI shows **Capture fix candidate • stream-stop finalization** and never logs `Recording output removed`.
2. Record a harmless desktop for at least 10 seconds; press Stop exactly once.
3. Expect `Capture stream stopped`, then `Finalization callback received`, then `Verified MP4`. Check the MP4 opens and has video, nonzero duration and nonzero size.
4. Repeat with short (3 s) and longer (60 s) recordings, and with a second recording in the same app session. Confirm no `RPRecordingErrorDomain -5814` / `-5815` and no stuck `Finalizing MP4` phase.
5. If a failure persists, copy the Activity log and record macOS version, launch method and the numeric error domain/code. Leave any failed media in place for recovery/inspection.

A green GitHub Actions CLT build proves compilation/signing, **not** the real ScreenCaptureKit capture-to-MP4 flow. This change remains a candidate until the physical-Mac regression passes.

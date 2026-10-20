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

## Try the manual and assisted post-production editor (PR #55)

This section describes the **candidate editor branch**, not features already merged to `main`. No Xcode.app is required. Work in the same checkout: `~/Personal/cineo`; never create a detached worktree solely to try the editor.

1. Quit every Cineo window using **Command-Q** (the builder refuses to replace running apps). Run `git status --short`, protect any uncommitted work, and `git fetch origin`.
2. Switch to `feat/cineo-interactive-editor`, tracking `origin/feat/cineo-interactive-editor` if it does not yet exist locally. This branch contains the still-unmerged fixed recorder, persistent identity and the editor.
3. Run `bash scripts/test-cineo.sh --interactive`. It recompiles and opens the **only** `~/Applications/Cineo Dev.app` using the same bundle ID and certificate; it does not install Xcode.
4. Click **Modifica MP4…** from the dashboard and select an already recorded video, or complete a new recording and choose **Apri editor**.
5. Select **Manuale** to scrub the source timeline, click directly on a rendered preview frame to set the focus, tune the 1–2.5× zoom and center XY, select background/margins/16:9 or 9:16. Camera keyframes appear as clickable timeline markers. The editor writes an **edit recipe** to `~/Movies/Cineo/Edits/` without modifying the original footage.
6. Select **Assistito** and select a point of interest in the preview, then **Suggerisci zoom qui**. Cineo generates an editable zoom-in/hold/zoom-out motion around the selected time; this does **not** claim to detect recorded clicks or understand screen content automatically.
7. Press **Esporta MP4**, monitor the real progress indicator, then **Mostra MP4**. A new MP4 appears in `~/Movies/Cineo/Edited/` after AVFoundation verification; the original file is retained.

**Known MVP limitations:** preview evaluates a real **individual composed frame** at the selected timeline position, not continuous edited-video playback yet. Automatic click detection and semantic storyboard generation are not implemented in this branch, and the current recorder has no audio. Only unrotated/supported sources accepted by the Core Image prototype exporter can be opened. No claim of complete production readiness until physical-Mac UI test + QuickTime output review. CI build and a synthetic encoded H.264 test are separate evidence.

To exit safely, close Cineo; switch branches as needed. Never manually clear Screen Recording grants or delete `Cineo Dev.app` just to open this prototype.

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


## Candidate G1 project round-trip — integration PR #56 (not yet Mac-verified)

This integration branch layers the existing `CineoProject` package over the PR #55 local Studio editor. All commands below use the **same local Cineo checkout and application identity**, not a cloned worktree or detached checkout.

```bash
cd ~/Personal/cineo
git status --short                       # preserve any local changes first
git fetch origin
git switch feat/cineo-mvp-integration    # existing branch; no git detach
git pull --ff-only
bash scripts/test-cineo.sh --interactive # CLT-only; only ~/Applications/Cineo Dev.app
```

In the app select **Apri MP4 / progetto…**, pick a verified unrotated H.264 MP4, apply one manual keyframe and change the stage background. Click **Salva progetto Cineo**. This creates a unique `~/Movies/Cineo/Projects/<uuid>.cineo` package with `Media/capture-*.mp4`, `manifest.json` and `scene.json`. The initial recording remains where it was. Exit the editor, choose **Apri MP4 / progetto…** again, and select that `.cineo` folder. Confirm the same keyframe positions, canvas, background and preview are restored. Export via **Esporta MP4**, check playback in QuickTime and ensure the source hash has not changed. **Annulla export** may be used during rendering; no original should ever be deleted.

This is not a multi-clip edit model yet. Studio intentionally rejects packages with edits, speed changes, or multiple media sources rather than silently producing inaccurate video. The integration does not yet attach click telemetry to ScreenCaptureKit, does not record audio, and does not expose CLI rendering. A CI synthetic H.264 smoke is not proof of a real macOS permission/restart or actual user recording. Do not merge PR #56 until physical-Mac G0/G1 checks pass, and do not merge both competing copies of CineoScene from #50 and #55.

## Import documented actions JSON (integration PR #56)

You can use Cineo Studio **manually as before** or supply a local, versioned **Cineo Actions JSON v1** file. See [format specification](../../docs/automation/cineo-actions-v1.md) and [sample](../../docs/examples/cineo-actions-v1.json).

1. Open a video **at least 13 seconds** long, or a supported `.cineo` project.
2. Click **Importa istruzioni…** in Cineo Studio. Select the example JSON or your custom plan.
3. When manual keyframes already exist, explicitly **Importa e sostituisci**, or cancel with no changes.
4. Cineo compiles `camera.zoom` actions to actual editable camera keyframes (overview → zoom-in → hold → zoom-out), updates the stage, moves to the first focus, and refreshes the real composed preview frame. Click the named action markers to inspect other segments.
5. Adjust keyframes, focus and stage as usual. The canonical scene is saved to `scene.json` for a Cineo project or the existing sidecar for an MP4; the original source remains untouched. Export with the regular CineoScene MP4 renderer.

The imported JSON is **not executed as code**, and unknown effects such as captions or cursor highlights are rejected instead of silently ignored. It is an import format rather than yet a two-way JSON editor; manual changes update the scene recipe. **The preview is still frame-at-a-time** until real-time Play/Pause is implemented. No validated Mac physical UI/video evidence is claimed solely from this branch.



## Show the matching instructions for the current Studio edit (candidate PR #56)

Open a supported MP4 or `.cineo` video and edit zoom/focus as usual. In Cineo Studio click **Mostra istruzioni**. A native sheet offers:

- **Montaggio attuale**: current camera keyframes and stage serialized as exactly reimportable Cineo Actions JSON, not a loose natural-language approximation.
- **Guida**: all v1 options, coordinate ranges, expected timing and unsupported action types.
- **Esempi**: a complete `camera.zoom` shot and an exact `camera.keyframe` sequence.
- **Copia JSON** / **Salva JSON…** on the first tab; **Importa istruzioni…** in Studio can reapply that JSON to the open media with confirmation before replacing existing camera keys.

The equivalent export writes `camera.keyframe` actions because arbitrary hand-authored keyframes cannot be reliably compressed back to one semantic `camera.zoom` shot. Each keyframe uses the same `time`, `target.x/y`, and `scale` as the underlying `CineoScenePlan`; the exporter recompiles its own JSON and refuses to show a recipe if the scene differs. `camera.zoom` remains the simpler way to author complete in–hold–out motion. Imported markers are cleared after manual camera changes to avoid stale action labels; the actual keyframes remain fully editable.

See [`docs/automation/cineo-actions-v1.md`](../../docs/automation/cineo-actions-v1.md). This candidate requires GitHub CLT CI and real Mac visual tests. The sheet describes snapshot frames and not animated Play/Pausa yet.


## Pre-export live preview and precise frame scrubbing (candidate PR #56)

Open an MP4 or `.cineo` in Cineo Studio, then use **Play / Pausa** next to the timeline. Cineo uses `AVPlayerItemVideoOutput` to decode actual source frames and evaluates every displayed frame with **the same `CineoSceneFrameRenderer.compose` used by final export**. The editor presents a bounded 960px-wide proxy of the canonical 1920×1080 (or 1080×1920) composition to reduce GPU cost. It never hides the original source or creates a temporary final MP4 merely for preview.

- The time indicator follows the video's actual playback clock and skips decoded frames when the device cannot render every frame; no fake smoothness or fabricated frame count. **Anteprima: N fps visualizzati** shows the number of frames actually presented each second.
- **‹ Frame** and **Frame ›** step by one source frame using the recording's nominal frame rate (default 30fps if unavailable). Manual dragging still displays correctly composited frames, with a shorter 35ms request-coalescing window and reused GPU context/image generator.
- Scrubbing or changing the camera pauses playback; export pauses playback too. Playback audio is intentionally muted because the current Cineo Capture Alpha does not record system audio. Source recordings are never modified.
- **Known limitations:** playable previews are provisional until measured on a real Mac. The preview may drop frames on large/high-rate footage and therefore is not promised at native 30/60fps. Frame stepping is approximate for variable-frame-rate sources. Rendered proxy frames use the same geometry and easing but lower raster resolution; exact output still needs MP4 quality checking. Only supported single-video, identity-transform sources are opened at present.

A suggested G1 verification on the physical Mac: import a 25s MP4, create 2 manual or JSON zooms, click **Play**, check visible zoom-in/hold/out without exporting, pause, step through 5 frames, switch 16:9→9:16, resume, export and compare representative timestamps. Verify after editing the original source hash is identical.

## Brand Kit v1.0 (supplied 2026-10-20)

The native capture/editor headers now use the **Cursor Zoom** layered mark, the ocean accent (`#107C99`), accessible native text and optional Inter only when already installed. The official supplied app icon and PNGs are embedded as signed bundle resources by `scripts/build-cineo-clt.sh`. **No runtime downloads or full Xcode.app are required**, and user video exports are **not automatically watermarked** with Cineo branding.

Asset source and provenance: [Assets/Brand/README.md](../../Assets/Brand/README.md). The phrase "Il focus su ciò che conta." is provisional source-kit copy and should be approved before commercial publication.

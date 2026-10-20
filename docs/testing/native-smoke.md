# P1 physical Mac recording and export test protocol

**Status:** executable preflight plus mandatory interactive tests; a green unsigned CI build is *not* recorded as a passing TCC or media validation.

## Preparation

Run the reproducible [pinned bootstrap](../../scripts/bootstrap-native.sh) on an Apple Silicon Mac with Xcode 26+. Open the generated `Reco.xcodeproj` from the **staging directory**, configure your own Apple developer Team and signed Debug app under `com.daniele21.cineo`. Do not copy developer credentials into CI or repository.

Run `bash scripts/native-smoke-doctor.sh --app /absolute/path/to/Cineo.app` **without** `--allow-unsigned`. The latter is limited to CI/static builds and skips signature verification. The doctor does not grant permissions or make a recording.

## Recording exercise

1. **TCC prompt:** select a display; verify visible Screen Recording permission request, deny once, retry and approve. Record exact macOS build and whether app restart is needed.
2. **Capture:** record ~30 seconds of a non-sensitive demo app, including moving cursor, clicking, opening a menu and scrolling; repeat for one browser window. Capture no private passwords, emails or customer data.
3. **Audio:** with microphone off verify no mic stream is collected; with microphone enabled make an obvious spoken clap/click cue and compare audio offset to video.
4. **Stop/save:** stop, reopen the saved source from Library/Editor, inspect duration, resolution, cursor geometry and file presence. Cancel another run; source must not be damaged.
5. **Camera/edit:** add or adjust one camera zoom and compare click target framing between preview and rendered export.
6. **Export:** export a real **1920×1080 16:9** and **1080×1920 9:16** H.264 MP4 at a chosen frame rate. Confirm UI text and resulting feature remain visible.
7. **Failure:** test denied permissions, disappearing target window, low free space/aborted export and restart where safe. Source media should survive.
8. **Privacy:** confirm no Orbit appcast, inherited `reco://` handler, legacy Orbit-container settings migration or unexpected local agent listener; inspect network connections only with consent and on test fixtures.

## Machine-readable report fields

Record only these redacted summary fields, never raw screen content, absolute paths, source footage, user profile data or tokens:

- `runDate`, `macOS`, `hardwareClass`, `xcode`, `cineoCommit`, `orbitPin`
- `signedLaunch`, `permissionDeniedRecovery`, `captureDisplay`, `captureWindow`, `micOptional`, `systemAudio`
- `sourceReopen`, `editorZoom`, `export16x9`, `export9x16`, `cancelPreservesSource`
- `audioOffsetMs`, `cursorMaxPixelError`, `droppedFrames`, `peakRSSMiB` (null if not measured)
- `blockingDefects[]`, `nonBlockingNotes[]`

The template below can be committed as **empty fixture only**. Completed reports should contain sanitized measurements, and sensitive full-resolution videos belong in restricted local evidence storage, not a public GitHub issue.

## Exit rule

P1 is not accepted until a signed real-Mac `Cineo.app` actually records, reopens and exports a readable video in both aspect ratios, with safe failure handling. If the capture or compositor fails, reopen the conditional [Orbit decision](../decisions/0001-native-foundation.md). Compilation and package tests alone do not satisfy the product milestone.

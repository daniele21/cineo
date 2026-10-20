# Cineo Capture Alpha — runtime diagnostics

This native SwiftPM macOS target builds with `bash scripts/test-cineo.sh --native`, using Apple Command Line Tools without Xcode.app. Launch with `bash scripts/test-cineo.sh --interactive`.

## What the screen now displays

Cineo deliberately exposes the complete capture state transition:

`Ready → Preparing → Recording → Finalizing MP4 → Verifying MP4 → Saved`

Any error becomes `Error` with a timestamped diagnostic. During capture it displays the **actual** `SCRecordingOutput.recordedDuration` and `recordedFileSize` metrics. During finalization it shows a spinner, elapsed time and the name of the output, *not a fabricated percent*. An always-visible Activity log lists lifecycle events, including ScreenCaptureKit callback delivery. It auto-scrolls to the latest event and can be copied manually.

On **Stop**, the app calls `SCStream.stopCapture()` **without separately removing** the attached `SCRecordingOutput`. The ScreenCaptureKit stream contract states that this also stops recording and finalizes the file. The app retains both objects until the recording delegate completes and **does not declare success** until `recordingOutputDidFinishRecording` has fired, the file exists and has nonzero length, and AVFoundation loads a positive duration and a video track. A stream interruption reported while an intentional stop is finalizing is logged as a warning; a failed recording callback remains fatal. If the operation takes longer than 15 seconds the interface warns without deleting files. When verified, Open MP4 is available.

The macOS unified logging subsystem is `com.daniele21.cineo.capturealpha`, category `recording`, with user-specific text logged private by default. The on-screen activity log is always local. The app does not record keyboard input or microphone/system audio in this alpha.

## Important verification limit

CLT GitHub Actions verifies **compilation and bundle signing** only. It cannot demonstrate Screen Recording permission prompts, ScreenCaptureKit delegate delivery, stop behavior or a real MP4. These need a physical Mac smoke. If stuck in `Finalizing MP4`, note the time and latest Activity log lines and check `~/Movies/Cineo/`; source material is not deleted by the app.

## Real-Mac regression for the stop/finalization race

1. Use the dedicated candidate checkout and launch with `bash scripts/test-cineo.sh --isolated-capture` (CLT only, no Xcode.app). This builds a separately signed **Cineo Stop Fix.app** with bundle ID `com.daniele21.cineo.capturealpha.stopfix`; it leaves existing Cineo.app and its macOS permission identity untouched. The command checks bundle ID and prints the exact source HEAD before opening a fresh instance. macOS may request Screen Recording permission again for the new identity. Verify the new app shows **Capture fix candidate • stream-stop finalization** and logs **Build variant: stream-stop finalization**. If either marker is missing, the recording does not test this fix.
2. Record a harmless desktop for at least 10 seconds; press Stop exactly once.
3. Expect `Capture stream stopped`, then `Finalization callback received`, then `Verified MP4`. Check the MP4 opens and has video, nonzero duration and nonzero size.
4. Repeat with short (3 s) and longer (60 s) recordings, and with a second recording in the same app session. Confirm no `RPRecordingErrorDomain -5814` / `-5815` and no stuck `Finalizing MP4` phase.
5. If a failure persists, copy the Activity log and record macOS version, launch method and the numeric error domain/code. Leave any failed media in place for recovery/inspection.

A green GitHub Actions CLT build proves compilation/signing, **not** the real ScreenCaptureKit capture-to-MP4 flow. This change remains a candidate until the physical-Mac regression passes.

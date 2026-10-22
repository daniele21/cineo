# Cineo V1: timeline, click effects and brand presets

Date: 2026-10-22. Feature branch staged on the integrated CLT Studio baseline.

## Delivered in this increment

1. **Smart Camera CI repair:** a result anchor is protected from accidental
   duplicate suppression and can use a shorter but bounded camera-wide gap.
   Dense *click-only* streams continue to suppress stale late zooms.
2. **Non-destructive cut model:** `CineoCutList` stores retained source
   intervals, validates duration/order/bounds, and maps edited output time to
   original source time and back. Removing time leaves the original MP4
   unchanged and is covered by unit tests and JSON round trips.
3. **Click ripple:** a subtle opt-in ring at click moments, using recorded
   click coordinates. The ring is drawn by the **same** CineoSceneFrameRenderer
   used in native preview and H.264 export. The original cursor is preserved;
   no second cursor is rendered. Older projects decode with effects absent.
4. **Cineo brand presets:** `Cineo Ocean` (#0B4F6A) and `Cineo Frost`
   (#DDF6F0) come from the existing `Assets/Brand/cineo.tokens.json` kit.
   Preset choice is persisted in the project's scene background.

## Not yet activated as a complete feature

**Cut UI and render/export:** although `CineoProject` already supports
source segments and `CineoCutList` maps them correctly, the Cineo Studio
preview and music/audio mux currently assume one continuous video source.
Do not show an operational Cut button until original narration, soundtrack,
click events, camera keyframes and rendered H.264 all use the same output
timebase. A cut that only edits `manifest.json` is NOT a finished feature.

**Cursor motion smoothing:** the current recorder saves click positions but
not high-frequency cursor movement. Click rings are supported; smooth
pointer paths require a separately opted-in, sampled movement sidecar and
a double-cursor-safe UI. Do not claim cursor smoothing from click-only data.

**Brand kit scope:** palette and stage background presets are integrated.
Brand typography/logo placement and saved cross-project style templates
remain work for the next iteration.

## Tests and user gate

```bash
swift test --package-path Packages/CineoDirector
swift test --package-path Packages/CineoProject
swift test --package-path Packages/CineoScene
bash scripts/test-cineo.sh --interactive
```

Acceptance: use an opt-in click recording, toggle click highlights, inspect
zoomed click location in preview, export MP4 and compare positions/timing.
Check new/old projects and Cineo Ocean/Frost in both aspect ratios. Confirm
no effect is added unless explicitly requested.

Separate final product E2E: mixed speech/system/music recording, full
non-destructive cuts, brand assets, 16:9 and 9:16 output and perceptual QA.

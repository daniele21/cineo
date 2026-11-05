# Imported MP4 → local Smart Camera (MVP)

## Scope and privacy

This is a **manual-seed Vision cursor tracking MVP**, not an automatic pointer
detector and not click reconstruction. Users may open any compatible MP4 in
Cineo Studio and choose the visible mouse cursor tip in one frame. Cineo analyzes
frames **on device** and records estimated normalized cursor coordinates, a
confidence score, and source timestamps in a separate local analysis report.

- No screen-recording permission, Accessibility access, remote inference,
  OCR, keyboard events or external network service is used for imported MP4s.
- The imported video already contains its own cursor. Cineo **never draws an
  independent second cursor** and does not attempt inpainting.
- Mouse positions are *inferences*, not native events. No click is fabricated.
- The analysis does not alter original video bytes, and camera proposals remain
  draft until explicitly approved.

## User path

1. Open **Apri MP4 / progetto…** and select a supported screen recording.
2. Pause at a frame where the cursor is clear.
3. Press **Analizza cursore nel video**, then click on the **tip** of the cursor
   inside the preview video area (not its background).
4. Watch the progress bar or press **Annulla**.
5. After tracking succeeds, press **Genera zoom da soste del cursore** to view
   proposed shots. Accept/reject shots, then apply the edits.
6. Optionally add manual zooms, press **Segui cursore negli zoom** to pan within
   the safe zone, and export a real MP4.
7. Save as a Cineo project to preserve report under
   `.cineo/Effects/imported-video-analysis.json`. When editing a raw MP4,
   the local cache is stored under Application Support/Cineo/VideoAnalysis,
   keyed by standardized source path, file size and modification time.

## Architecture

- `CineoVideoAnalysis`: bounded frame sampling via AVFoundation, native
  `VNTrackObjectRequest`, cancelable actor, source-time measurements.
- `CineoImportedPointerAnalysis`: strict Codable report, explicit
  `vision-manual-seed` provenance, normalized position and confidence;
  distinct from authoritative recorded pointer-events v1/v2 sidecars.
- `CineoImportedVideoAttentionPlanner`: confidence and temporal-gap filters,
  stable cursor **dwells** (not clicks), then existing `CameraPlanner` and
  `CineoAutoEditPlanner`.
- `CineoCameraFollowPlanner`: consumes qualified inferred movements with cut
  mapping, protecting manual authored keyframes.
- `CineoScene`: still the sole shared preview and export compositor.

## Known limitations

- Must be seeded manually, tracking only **forward** from the selected frame.
- Maximum of 6,000 samples and 10 minutes per run; 6 FPS default. For long
  recordings, select another starting frame and rescan as needed.
- A cursor moving over similar-looking UI elements can drift or be lost.
  Confidence filtering suppresses weak detections, but no claim of accurate
  per-frame mouse tracking or recovered clicks is made.
- Only stable dwell events can automatically create zoom shots in the MVP;
  no semantic scene change, OCR, action inference, or LLM model is integrated.
- Screen recordings with nonidentity track transforms are currently rejected
  by the existing Cineo Studio importer. Supporting arbitrarily rotated video
  is a separate feature.
- Cache fingerprints based on size/mtime are an optimization, not a
  cryptographic proof of identical file content.
- Manual visual acceptance is needed: test a real imported QuickTime/OBS MP4
  with cursor visible, fast moves, occlusions, cuts, zooms and export.

## Automated acceptance

- Linux Swift tests: deterministic report validation, provenance, no fake
  clicks, dwell segmentation, confidence/gap filtering, cut mapping, JSON.
- macOS CLT SwiftPM: compile Vision tracker and complete Cineo Studio.
- Native smoke: analysis cache roundtrip, stale cache invalidation, project
  report persistence and invalid seed rejection.
- Core smoke and H264 editor smoke: project non-destructive behavior, real
  Core Image preview/export rendering without Xcode.app.
- Self-hosted Mac: same checks on a real Mac mini with **no unattended TCC
  changes or personal-video capture**.

## Next phase

Add an automatically proposed cursor hotspot using an original, commercially
compatible detector and a real-video labeled benchmark. Keep manual seed
as fallback. Then add cautious UI-change attention signals, separate from
native click telemetry, with per-proposal confidence and user acceptance.

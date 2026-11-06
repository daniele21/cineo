# Cineo — assisted editing for imported MP4 (2026-11-06)

Status: **integration candidate**, not user-accepted. Source branches: #84 cursor coverage, #85 visual pixels, #86 attention fusion, integration #87. Based on responsive Studio #83. Do **not** merge into `dev` or `main` before native build and real-video acceptance.

## Why this differs from Recordly

Recordly's automated zoom path is strongest with **explicit recorded click telemetry**. Normal MP4s do not include those events. Our implementation studies interaction ideas, not AGPL source code. Cineo never fabricates clicks, reconstructs audio statements, removes the baked cursor or creates an additional overlay for an imported MP4.

## End-to-end user journey

1. Open a QuickTime/OBS MP4. Cineo Studio presents **one editor**, with Smart / Camera / Stile.
2. **Analizza video** scans visual changes locally via AVFoundation and low-resolution pixel differences. No manual cursor selection is required.
3. To add cursor context, pause at a clear cursor frame and choose **Aggiungi tracking cursore (facoltativo)**; click the pointer tip. Tracking runs both directions, retaining only qualified observations. Additional seeds can be merged without inventing missing data.
4. Visual cues + pointer dwells are fused conservatively; a correlated signal receives higher confidence. Strong visual-only changes can propose a zoom even without a cursor; low-signal changes never generate fake clicks.
5. Proposed edits are reversible, preview-only until approval. Each proposal has a confidence hint and can be accepted or rejected individually.
6. Existing CameraPlanner, Camera Follow, timeline cuts, undo, native preview/export and original media are preserved. On-device reports are cached or stored in the `.cineo/Effects` project directory.

## Data / execution flow

```
MP4 (original source clock)
 ├─ CineoVisualChangeAnalyzer (AVFoundation, <= 1200 sampled frames)
 │   └─ CineoVisualChangeReport (time, normalized focus, change fraction, confidence)
 └─ CineoVideoCursorTracker (optional, manually seeded)
     └─ CineoImportedPointerAnalysis (bidirectional, no gaps interpolated)
             │
             v
CineoImportedAssistedPlanner (cut-aware mapping + correlation + safe filtering)
             │
             v
CameraPlanner + CineoAutoEditPlanner → preview shot list + confidence hints
             │
             v
Approve / reject / adjust → existing native Core Image preview / H264 export
```

## Privacy / technical limits

- All scans run locally. Persist only timestamps, normalized positions and confidence. No pixel buffers, screenshots, OCR, transcript or inferred click telemetry stored.
- Visual scan samples the **entire source timeline** but is bounded to 1,200 frames; long videos receive lower temporal resolution. For high-precision editing, additional region-specific scans remain future work.
- Cursor tracking is backward+forward from a manually chosen seed, with up to 10 minutes per direction and 6,000 sampled frames each. Occlusion may terminate a run. There is **no claim** of automatic cursor discovery or precise tracking on arbitrary UI themes.
- Pixel changes may be scrolling, modal appearances, animation or compression artifacts, not proof of user interaction. High-confidence UI changes are only editing suggestions.
- `cutMapper` drops source cues inside excluded source ranges; it never invents a source-time event from an output-time gap.
- The imported cursor stays in the source pixels, and no inpainting, duplicate cursor overlay or cloud model is used.

## Parallel tracks and acceptance

| Track | Code | Automated gate | Real-video gate |
|---|---|---|---|
| A: tracking | #84 | Pure-Swift trace merge tests, native Vision compilation, synthetic H264 benchmark | Seed at 25% and 75%, forward+backward, occlusion, recovery with second seed |
| B: visual UI | #85 | Swift Testing with unchanged/noise/local change/flash fixtures, native SwiftPM build | QuickTime/OBS buttons, modal/dialog, scrolling, cuts, cursorless demos |
| C: fusion | #86 | Pure-Swift tests for visual-only, correlated cues, weak noise, cuts, full timeline | Precision of proposed zooms with curated review labels |
| Integration | #87 | All above + complete native Studio build and renderer smoke | 16:9 and 9:16 preview, proposal review, exported H264, cancellation, original SHA |

## Quality measures before approval

Annotate at least 5 representative real videos (including cursorless and difficult-pointer recordings). Log candidate start/end, intended target, confidence, source evidence, acceptance decision and final render parity. Report coverage/recall of meaningful moments, precision of proposals, false zooms per minute, cursor drift and end-to-end analysis duration by clip length. Synthetic tests alone do **not** prove semantic relevance or good cinematic motion.

## Commands on the Mac

```sh
git fetch origin
git switch integration/imported-video-assisted-20261106 \
  || git switch --track origin/integration/imported-video-assisted-20261106
git pull --ff-only
swift test --package-path Packages/CineoDirector
swift test --package-path Packages/CineoVideoAnalysis
swift build --package-path Apps/Cineo --configuration release
bash scripts/test-cineo.sh --interactive
```

Keep `dev` and `main` unchanged. All outputs are development candidates until physical Mac acceptance.

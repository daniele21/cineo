# Cineo V1 source-preserving cuts — developer acceptance

**Stack:** PR #70 → #71 → #72, all based on the integrated Cineo Studio CLT branch.
This is a **developer build**, not a distributed V1.

## What the editor now supports

1. Load a Cineo screen recording or a single-source `.cineo` project.
2. Use the playback timeline to choose a start and end point. Click **Inizio**
   and **Fine** to capture each mark, then **Rimuovi intervallo**.
3. Undo/Redo cuts using the supplied controls. No source video bytes are
   changed. A saved `.cineo` project stores retained clips in the existing
   `manifest.json.edits` schema. A standalone MP4 keeps atomic `cuts.json`
   alongside its scene state.
4. Preview, scrub and play the edited *output* timeline. Auto Edit proposals
   and click highlights map recorded **source timestamps** to the output
   clock. Deleted click events cannot influence the camera.
5. Export H264 with the same retained video spans and an original narration
   track assembled from exactly those spans. New music and cues are aligned
   to output time; original-audio ducking ranges are retimed after cuts.

**Intentional v1 restriction:** perform cuts **before** keyframes, cue markers
or adding/importing soundtrack. Cineo blocks both new cuts and cut undo/redo
after timing-sensitive camera/music edits are present. This avoids silent
data loss or pretending that modified cues are correctly retimed.

## CI

```bash
swift test --package-path Packages/CineoProject
swift test --package-path Packages/CineoDirector
swift test --package-path Packages/CineoScene
bash scripts/test-cineo.sh --native
```

The CineoScene synthetic smoke verifies that an actual H264 export becomes
shorter at the cut boundary, preserves original video SHA, and still
decodes. CineoAudioSmoke checks real AAC narration cuts alongside its music
fade/ducking controls.

## Remaining physical-Mac E2E gate

- Input with voice, system audio, generated music, no clicks, dense clicks,
  secondary Retina monitor, and both 16:9/9:16 output.
- Cuts spanning two prior segments, cut exactly at a sample/PTS boundary,
  repeated play-seek near cuts, trim all vs empty prevention.
- Compare audio/vocal timing on headphones and decoded MP4 frames. Ensure
  near-cut text remains legible and no AVPlayer audible burst occurs.
- Reopen a cut project, regenerate Smart Camera, apply zoom, add soundtrack,
  export, and confirm original source unchanged (SHA-256).
- Test insufficient disk capacity, cancel, app force quit while exporting and
  project stored on removable volume. No release claims before this gate.

CLT-only local checkout:

```bash
cd ~/Personal/cineo
git fetch origin
git switch feat/cineo-cuts-studio-v1-20261022
bash scripts/test-cineo.sh --interactive
```

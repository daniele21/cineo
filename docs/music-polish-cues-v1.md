# Cineo Music Director: loop crossfade, original-audio ducking, and manual cues

Stacked on PR #58, no Xcode.app requirement. Purely local, no separate LLM
recommendations, and no destructive source changes.

## What this implements

- **Crossfaded loops:** the music clip adds optional crossfade in seconds (0 to
  1.5s, also less than 45% of the source repetition length). Adjacent repeats
  overlap on two composition tracks rather than hard-cutting. The native
  preview runs two local AVPlayers, one per lane. Source files are untouched.
- **Original-audio ducking:** opt-in, enabled explicitly in Music Director.
  Detects RMS activity of the original recording; lowers music during activity,
  with configurable quiet volume and threshold. Attack/release are deterministic.
  This is **not speech classification**: application sounds also trigger it.
- **Manual cues:** place a named marker at the current video playhead, jump to
  it or remove it. Use "Allinea zoom" to propose moving a nearby existing zoom
  peak to the cue; confirmation is still required. Cues are not generated hits,
  sound effects or new audio tracks.
- **Versioned state:** all three additions persist in the existing music.json
  and the strict Cineo JSON instruction section. Absent optional fields
  preserve older project compatibility.
- **Offline implementation:** AVFoundation plus a pure Swift audio envelope
  and cue/clip model. No mandatory ACE-Step download for imported tracks.

## Instruction syntax

The optional `music` object now also accepts:

~~~json
{
  "crossfade": 0.5,
  "ducking": {
    "enabled": true,
    "quietVolume": 0.25,
    "thresholdDB": -35,
    "attack": 0.12,
    "release": 0.45
  },
  "cues": [{"id":"reveal", "time":6.5,"label":"Dashboard reveal"}]
}
~~~

This fragment belongs *inside* the existing `music.generate` object.
No automatic generation or camera rewrite occurs from importing these fields.

## Validation checklist before merge

1. Build on Apple Command Line Tools alone via `bash scripts/test-cineo.sh --interactive`.
2. Import a 5s music loop and a 20s recording. Enable looping and choose a
   0.5s crossfade. Listen at each seam, both preview and final MP4; compare.
3. Enable ducking on a recording with an original audio track. Listen during
   and outside the original-audio activity; verify threshold and reduced
   volume. Repeat with a recording with *no* original-audio track (must not
   falsely claim speech detection).
4. Add a cue at the reveal, move the video playhead to a nearby zoom-in peak,
   click Allinea zoom, inspect the suggested time, then apply or cancel.
5. Export and reopen a Cineo project; confirm cue positions, duck settings and
   crossfade are persisted; original files unchanged.
6. Test a silent source and very short clips. A 600s audio analysis bound
   means after minute 10 the ducking activity detector cannot see new activity.
7. Verify no false audio dropouts at 0.5/1.0/3.0s offsets and when the clip
   ends during crossfade. If drift or phase artifacts occur, do not merge.

## Still pending

Real Mac preview/audio comparison and listening test. This v1 uses **linear
amplitude** overlapping fades, not phase-aware loop matching or equal-power
cosine curves. Multi-track sound effects, stem mixing, and partial ACE-Step
inpainting are intentionally separate, later tasks.

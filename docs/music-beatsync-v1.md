# Cineo Music Director: waveform, trim, loop and BeatSync v1

This is an extension of music-director-v1.md. It uses only local PCM analysis, deterministic rules and explicit user confirmations. ACE-Step generation remains user-triggered. No LLM suggestions.

## Implemented
- Non-destructive source trim: sourceIn selects audio source start; clipDuration selects final play length; loop repeats from sourceIn to the end of source. No file rewritten.
- Preview/export parity: one CineoMusicClip computes source segments for playback and AVFoundation MP4 mix; fades are applied over the total clip, not per repetition.
- Waveform and detected accents: AVAssetReader decodes audio to mono float32 at 11.025 kHz, bounded to 600s. Peaks and candidate transients are drawn over video output time.
- BeatSync proposals: select an existing zoom-in peak on the camera timeline, choose Suggerisci allineamento, inspect the proposed edit and explicitly choose Applica BeatSync. Maximum adjustment 350ms, and neighbours retain valid ordering. No other zooms are moved.
- Existing music.json files remain readable: the clip is optional and defaults to no trim or loop. The source MP4 remains unmodified.

## Unified Cineo JSON clip fields
The existing optional music section additionally accepts sourceIn, clipDuration, loop. Example:
~~~json
{
  "version": 1,
  "timebase": "output",
  "actions": [],
  "music": {
    "type": "music.generate",
    "caption": "Subtle percussive electronic instrumental",
    "bpm": 115, "duration": 30, "keyscale": "A minor",
    "seed": 42, "volume": 0.4, "offset": 2,
    "fadeIn": 0.6, "fadeOut": 1.5,
    "sourceIn": 3, "clipDuration": 24, "loop": true
  }
}
~~~
Music duration is the generation request, not the edited final clip duration. JSON import does not trigger ACE-Step or BeatSync.

## Mandatory physical Mac verification before merge
1. In the *existing* ~/Personal/cineo checkout, fetch and switch normally to feat/music-timeline-beatsync-v1. Run bash scripts/test-cineo.sh --interactive; no Xcode.app.
2. Import WAV and MP3. Check actual waveform, markers, seek, audio/video preview; confirm imported audio also works without ACE-Step.
3. Set sourceIn=4, clipDuration=12 and output offset=3, export. Listen: music begins at video second 3 from audio source second 4, ends at video second 15, with correct fades.
4. Enable loop with clip duration longer than the source remainder. Verify multiple cycles and fade over the entire resulting clip. Loop is a hard replay, not crossfade; audible seam clicks are possible.
5. Create an existing editable zoom-in peak close to a detected accent. Suggest BeatSync but cancel: no edits. Confirm and re-export: only the chosen keyframe shifts, maximum 350ms. Try crowded keyframes and silent audio (should reject).
6. Save as .cineo project, quit and reopen; verify audio, trim/loop, zooms, waveform and offsets survive, and original files stay unchanged.
7. Listen for preview/export parity, narration presence, drift and error recovery. Repeat with real ACE-Step generated WAV, not only imports.

## Deliberate limits
- Energy/attack onset candidates are not a guaranteed beat grid or calibrated BPM.
- No loop crossfade, music stem splitting, silence cutting, narration ducking, per-beat cue scoring, multiple audio lanes, or automated model installation.
- No LLM suggestion system. Apple Silicon test and real export audio QA remain the release gates even when macOS CI is green.

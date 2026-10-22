# Cineo Music: repaint, cue SFX and speech-likelihood ducking

This draft branch builds on #63. **User-media end-to-end QA is intentionally
left for the final milestone.** Existing synthetic/CLT regression suites run in
CI; they do not replace listening to a real product demo.

## ACE-Step repaint (partial regeneration)

The upstream [acestep.cpp](https://github.com/ServeurpersoCom/acestep.cpp)
provides `task_type: repaint` via **POST /synth** with a
`multipart/form-data` body containing fields named `request` (JSON) and
`audio` (source WAV/MP3). Repaint is a **DiT + VAE** operation; it skips LM
and replaces the selected musical region while preserving the rest of the
source as modeled by ACE-Step.

Cineo exposes manual `Da` and `A` video-timeline markers. Both are
converted into **source-relative positions**, respecting clip offset,
sourceIn and loop. Selections crossing a loop or crossfade are refused,
as are selections under 1 second or over 120 seconds. The entire input
file must be at most 125 MB and the source duration at most 600 seconds.
There is no cloud call; ACE-Step only accepts loopback HTTP.

Click **Rigenera solo l'intervallo** and Cineo sends a direct /synth job,
polls server status and writes a new WAV only after checking the payload.
No source WAV/MP3 is overwritten; the old music remains in the Media
folder. Cancellation asks the local server to stop the work.

## Cue audio effects

Each existing `hit`, `crescendo` or `transition` cue has:
- an opt-in `soundEnabled` toggle (default off, including old projects);
- a `soundVolume` setting (0…1, default 0.28);
- an **Ascolta** audition button;
- a matching deterministic 48 kHz, 16-bit local sound used in both live
  preview and AVFoundation export.

The three simple sounds are synthesized locally in code (percussion,
riser, and transition whoosh). They do not require a model download,
licensed audio sample library or ACE-Step call. A 24-event limit avoids
unbounded composition tracks. Project `music.json` and the strict
instruction JSON preserve the opt-in state and level. Sound cues are
not enabled automatically when importing older projects.

## More selective ducking

Choose **Qualsiasi audio** for the existing RMS amplitude gate, or
**Parlato probabile** for Apple's built-in on-device SoundAnalysis
classifier, intersected with the local 20ms RMS windows.

The latter is **not guaranteed voice detection** or a transcript. It
may mistake some sound effects for voices, and it may miss quiet speech.
No audio is transmitted to a server and no transcription is stored.
If the built-in classifier does not expose a speech class, or analysis
fails, Cineo reports the limitation and disables ducking instead of
silently pretending to use speech recognition.

## Release gates

- Pure Swift contract tests for repaint region bounds, source semantics,
  binary multipart fields and legacy cue state.
- Unit tests for built-in Foley scheduling, volume validation and
  speech-window/RMS intersection.
- CLI-only macOS app build, native video render and synthetic audio
  regression jobs in GitHub.
- **Final milestone (deferred by request):** run on Apple Silicon with
  real voice, notification, music and cue footage; listen for loops,
  fades, repaint seam artifacts, Foley clipping and preview/export
  synchronization.

No merge into main has been performed by this branch. This is an
incremental functionality PR, not a final release.

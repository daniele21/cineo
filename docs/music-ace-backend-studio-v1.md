# ACE-Step from Cineo: local control and music editing improvements

This branch stacks on PR #61. It remains an experimental Studio feature
until Mac user-media E2E validation in the **final** release milestone.

## Backend panel

1. Open Cineo's Music Director.
2. Select your existing local `acestep.cpp` folder. Cineo also detects
   `~/Personal/cineo/acestep.cpp` and adjacent checkouts.
3. Select **Verifica**: Cineo tests the `GET /health` endpoint on
   `http://127.0.0.1:8080`. A running external server is accepted, but
   Cineo never claims to own or stop it.
4. The panel checks `build/ace-server` and the four GGUFs:
   `vae-BF16.gguf`, `Qwen3-Embedding-0.6B-Q8_0.gguf`,
   `acestep-5Hz-lm-4B-Q8_0.gguf`,
   `acestep-v15-turbo-Q8_0.gguf`.
5. **Avvia motore** explicitly starts the locally compiled binary with
   `--host 127.0.0.1 --port 8080 --models <chosen-folder>/models`.
   No `server.sh` because it exposes `0.0.0.0:8085`. The panel
   checks for readiness and offers bounded local stdout/stderr logs.
6. **Arresta** is only available for a process actually spawned by this Cineo
   session, never for one already running in a separate terminal.
7. **Scarica GGUF mancanti…** optionally downloads missing models after
   an explicit multi-gigabyte confirmation. It runs the user's installed
   Hugging Face `hf` CLI with fixed arguments directly (no shell and no
   automatic tokens); it checks free disk space and only displays *file
   count completed*, not invented per-file percentage. Partial/invalid
   downloads fail preflight; retry is allowed. The browser/token is not
   needed for public Hugging Face files. Cineo never downloads silently.

*Preflight validity* checks file length and the GGUF magic number, not full
hash integrity or that a model can load. A broken binary, missing Metal,
memory pressure, incompatible downloaded version, or backend crash can only
be identified at runtime; server logs are the source of truth.

## Editing workflow

- The waveform now shows the current video playhead, clip output offset and
  remaining duration. The separate timeline ruler can be clicked to **seek**
  without dragging or moving the music clip.
- Dedicated buttons nudge the music by **100 ms** per step.
- **Allinea il primo accento al playhead** computes the difference using the
  first *detected audio transient after sourceIn*. It moves only the music
  offset. It refuses impossible negative offsets. It never infers accents
  from the user-provided BPM and never rewrites source audio.
- Existing trim, duration, loop, crossfade, BeatSync, cues, ducking and export
  controls remain available.

## Validation and rollout

- Pure-Swift tests validate localhost binding, truncated GGUF detection and
  user-directory discovery.
- CI builds the macOS SwiftUI app with **Command Line Tools only**, without
  installing Xcode.app. Inherited unit and synthetic-audio regression tests
  remain enabled.
- A final real-device E2E pass is deliberately **deferred** until the feature
  roadmap is otherwise finished, per the requested release sequence.
- The new branch is stacked; do not merge PR #62 until ancestor PRs have been
  reviewed. No changes to `main` are made by this work.

## Known limitations / future work

- No full GGUF checksums, automatic build of upstream C++, model performance
  benchmark, hardware-aware recommendations or GPU RAM estimation yet.
- No speech-verified ducking, source-aware partial ACE-Step music repaint,
  automated Foley / music cue effects, or multi-track audio lane editing.
- Process ownership is local to the running Cineo instance. A server
  surviving an app restart appears as **external** and cannot be stopped by
  Cineo; stop it from its original terminal or system process manager.

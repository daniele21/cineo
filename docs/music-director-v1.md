# Cineo Music Director v1 (manual + ACE-Step)

**Scope:** music controls from Cineo Studio UI or the same strict JSON document
used for camera and stage effects. A real local ACE-Step engine generates the
track. **No user-facing LLM recommendations or AI interpretation of the video.**

## Backend prerequisites

Cineo is still a local-first, CLT-only macOS SwiftPM app. ACE-Step is an
**optional, separate local process**: Cineo does not download multi-GB model
files silently and does not connect to a hosted music API.

Cineo Music v1 targets the independent
[acestep.cpp](https://github.com/ServeurpersoCom/acestep.cpp) GGML/Metal port
of [ACE-Step 1.5](https://github.com/ace-step/ACE-Step-1.5).
Pin/verify an upstream commit and model weights/license before packaging.

Start the backend manually (needs CMake, Apple's Command Line Tools, ggml
submodule, and downloaded model GGUFs):

```bash
git clone --recurse-submodules https://github.com/ServeurpersoCom/acestep.cpp.git
cd acestep.cpp
./models.sh # requires Hugging Face CLI; downloads ~7.7 GB default Q8 models
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release -j4
./build/ace-server --host 127.0.0.1 --port 8080 --models ./models
```

Use the upstream README if you need a smaller GGUF quantization or customized
model selection. Test server health with `curl http://127.0.0.1:8080/health`.
Don't run the upstream `server.sh` as-is on an untrusted network: it binds
`0.0.0.0`; Cineo assumes a private loopback endpoint.

## UI workflow

1. Open Cineo Studio and choose **Musica**.
2. Enter a caption, tempo, key, duration, seed, mix volume, offset and fades.
3. Click **Genera con ACE-Step**. Cineo runs `/lm`, waits for its job,
   submits `/synth`, retrieves the WAV multipart and stores it locally.
   The internal model LM produces music codes, **not editing suggestions**.
4. Press Play to preview the music alongside Cineo's composed video frames.
5. Export MP4. Original narration, if present, is retained and mixed with music.

Alternatively, import WAV/MP3/M4A/AIFF/AAC. The music clip now appears directly below the video scrubber in Studio. Drag its timeline strip to move the music start, or use the offset slider in Musica for precise positioning. The Musica panel shows the source filename and length, playback duration, volume, fades, Play/Pause, remove, replace, show in Finder and 'Inizia qui' (align to current video playhead). Removing a track detaches it from the edit without deleting the original audio. Imported bytes and generated WAVs
live in the project package's `Media/` directory or under the user's
`Movies/Cineo/Music/` directory for standalone videos.

A `.cineo` project stores music settings in `music.json`; the source MP4 is
unchanged. The editor's existing `scene.json` stays the sole camera plan.

## Unified JSON instructions

```json
{
  "version": 1,
  "timebase": "output",
  "actions": [
    {
      "id": "dashboard", "type": "camera.zoom",
      "start": 8, "end": 13,
      "target": {"x": 0.7, "y": 0.4},
      "scale": 1.65,
      "transition": {"in": 0.4, "out": 0.5}
    }
  ],
  "music": {
    "type": "music.generate",
    "caption": "Elegant minimalist electronic instrumental with warm synth pads and subtle drums",
    "bpm": 110,
    "duration": 45,
    "keyscale": "C major",
    "seed": -1,
    "volume": 0.4,
    "offset": 0,
    "fadeIn": 0.8,
    "fadeOut": 1.8
  }
}
```

Importing this document updates both camera instructions and music settings.
Music import is **non-executing**: the user explicitly presses Generate to run
ACE-Step. Music-only imports preserve existing camera motion.

The `music` JSON describes a **generation recipe and mix controls**, not a
bitwise copy of already generated audio. Preserve the `.cineo` project assets
when an exact WAV must be retained. Exports are never written over originals.

## Known limits & release gates

- Manual alignment: visible clip on the same video timeline, draggable offset, duration, volume, fade and UI listening. The strip is a **clip envelope, not an analyzed waveform**. Generated
  audio is **not guaranteed** to hit a precise beat at a requested timestamp.
- No LLM suggestions, video detection, beat detection, automatic camera
  retiming, stem editing, waveform editor, built-in model downloads, automatic
  back-end launch or multiple parallel music tracks in this slice.
- Backend state has truthful phase labels, but the upstream job API exposes
  only `running/done/failed` and does **not** expose a percentage.
- The music panel may be driven by both UI and versioned Cineo Actions JSON.
- Verify on Apple Silicon: actual GGUF download, 30/60s generation, cancel,
  RAM pressure, preview A/V drift, voice mix levels, fade and MP4 validation.
  Linux tests cover only pure Swift contracts; Mac CLT CI covers compilation
  and synthetic rendering, **not** a real model inference run.

## Checks

```bash
swift test --package-path Packages/CineoMusic
swift test --package-path Packages/CineoScene
swift build --package-path Apps/Cineo --configuration release
bash scripts/test-cineo.sh --interactive
```

Neither successful compilation nor an API mock is proof of successful
ACE-Step music generation: run an end-to-end Mac smoke before shipping.

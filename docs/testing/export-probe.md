# Cineo — Inspect exported MP4 structure

This helper enables **read-only, on-device structural checks** after you test the application. It does not create a recording, inspect what appears on screen or measure smoothness, visual quality, timing accuracy or audio/video synchronization.

### Usage on macOS 15+

```bash
swift run --package-path Packages/CineoExportProbe -c release cineo-export-probe -- \
  --file "/path/to/export-landscape.mp4" --width 1920 --height 1080 \
  --min-seconds 2 --codec h264

swift run --package-path Packages/CineoExportProbe -c release cineo-export-probe -- \
  --file "/path/to/export-portrait.mp4" --width 1080 --height 1920 \
  --min-seconds 2 --codec h264 --require-audio
```

The command reports only measured dimensions, duration, codec, nominal frame rate and audio track count, without the source filepath. It exits with a failure status when metadata does not satisfy requirements.

**Quality release gate:** these checks are necessary but not sufficient. Open the videos on desktop and phone and verify text legibility, zoom pacing, cursor alignment and synchronisation. Follow [the native smoke protocol](native-smoke.md) and retain redacted test evidence. There is no claim that a real Cineo MP4 has yet passed this probe.

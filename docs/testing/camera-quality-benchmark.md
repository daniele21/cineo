# Cineo Smart Camera: deterministic quality gates

The Cineo Auto Edit implementation is built on one planner:
`Packages/CineoDirector` uses validated, **opt-in** click coordinates
from `CineoEvents`, then produces keyframes in `CineoScene`.
The preview and final export share that scene composition contract.

## Run locally (macOS CLT or Swift on Linux)

```bash
swift test --package-path Packages/CineoDirector
swift run --package-path Packages/CineoDirector cineo-camera-benchmark
```

Benchmark fixtures live at
`Packages/CineoDirector/Sources/CineoCameraBenchmark/Fixtures/autoedit-cases.json`.
Each case pins the video duration, camera preset, click sequence, and an
expected shot-count interval. The command emits JSON, returns a nonzero
exit code if a gate fails, and requires no user files, account or server.

**Measured:** valid scene/keyframe ordering, crop bounds, minimum wide gaps
(>= 0.20 s), maximum zoom, actual shots/min and rolling 60-second shot
budgets. Presets retain their distinct intensity parameters. This detects
many avoidable zoom storms, not their storytelling quality.

**Not measured:** whether a UI click is narratively meaningful,
whether the viewer can read text, visual appeal, actual video/PIP quality,
cursor alignment or audio/video drift.

## Studio review contract

1. Generate Smart Camera proposals with the desired preset from recorded
   clicks. No click telemetry means no suggestions.
2. Review the shot list. `Vai` seeks the animated preview; untick a shot
   to remove it from the tentative plan without touching manually saved
   keyframes or the source video.
3. `Applica zoom` applies the selected subset. If any manual keyframes
   exist, explicit replacement confirmation is required. Zero selection
   can never erase existing work.
4. The project persists only after a successful atomic `scene.json` save;
   failed persistence restores the previous camera. `Annulla` discards the
   transient proposals.

## Gate before public release

Use three real screen recordings (quiet/no clicks, dense form/dashboard,
and a UI with edge targets on a secondary display). Inspect both
16:9 and 9:16 visual output and the active audio mix. Confirm no double
cursor, excessive zooms, timing slips or unreadable text. Keep raw source
and project intact after export cancel/crash. This physical-Mac perceptual
end-to-end verification remains deliberately separate from pure Swift CI.

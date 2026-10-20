# Cineo

**Record naturally. Present beautifully.**

Cineo is a **planned native, local-first macOS application** for creating cinematic software demos from real screen recordings.

The goal: record a workflow, get a polished first edit with purposeful zooms and cursor motion, refine the details only when necessary, then export a clear product video for a website, launch post, presentation or tutorial.

> **Project status — native CLT-only Capture Alpha + experimental Orbit editor (October 2026).**
>
> `Apps/Cineo` is an independent SwiftPM/SwiftUI macOS screen recorder that compiles using **Apple Command Line Tools without Xcode.app**. It saves local H.264 MP4 captures and has not yet been validated with live TCC capture on a physical Mac. The larger Orbit-based editor/Smart Zooms integration currently remains a separate Xcode-dependent legacy path; it is **not** included in the CLT Capture Alpha. Cineo is not a released product.

## The experience we want

**Capture → Auto Edit → Studio → Export**

- **Capture:** choose a display or window, record screen/audio, optionally store time-coded cursor and click events.
- **Auto Edit:** get a suggested first cut, with sensible zoom/pan, click highlights, smooth cursor and less idle time.
- **Studio:** tune the timeline, focal regions, keyframes and callouts non-destructively.
- **Export:** preview and locally encode professional 16:9 or 9:16 video from the same composition.

Cineo should focus on **the feature's result**, not blindly zooming on every click. Good camera choreography is a tool for clearer product storytelling.

## Product values

- Fully native SwiftUI/AppKit macOS experience.
- Local-first capture, project storage and baseline rendering without accounts/uploads.
- One reliable render pipeline for both editor preview and export.
- Reversible edits, independent pointer metadata when available and explicit permission controls.
- Thoughtful default motion with progressive disclosure for advanced editing.
- Honest demonstration of real product functionality.

## Documentation

| Document | What it owns |
| --- | --- |
| [Product definition](docs/product.md) | Mission, audiences, problems, promises, non-goals and success signals |
| [Feature specification](docs/feature-spec.md) | MVP/V1/V2 behaviours and acceptance criteria |
| [UX & cinematic grammar](docs/ux-motion.md) | Capture/Auto Edit/Studio/Export UX and camera rules |
| [Architecture](docs/architecture.md) | Native module boundaries, event/time/geometry and compositing |
| [Open-source adoption](docs/upstream-evaluation.md) | Candidate repositories, license review, reuse strategy and audit gate |
| [Quality bar](docs/quality.md) | Native benchmark, E2E/golden-frame tests and release gates |
| [Development plan](docs/roadmap.md) | P0–P6 milestones, dependencies, backlog and no-go gates |

## Engineering strategy

**Orbit** ([diip3sh/orbit](https://github.com/diip3sh/orbit)) is the **conditionally selected P1 foundation** with a reversible pinned staging build. [BetterCapture](https://github.com/jsattler/BetterCapture) is the robust capture baseline, [CineScreen](https://github.com/jasonzh0/CineScreen) is a compositor/export comparison, and [OpenScreen](https://github.com/getopenscreen/openscreen) informs editor UX and programmable editing. Orbit is materialized externally by a repeatable script rather than committed wholesale; other projects remain references and alternatives. Repo READMEs are not treated as proof of running features.

[ADR-0001](docs/decisions/0001-native-foundation.md) authorizes only the **P1 Orbit staging experiment** based on verified source inspection and Xcode compilation. The final adoption/distribution decision remains blocked by signed real-Mac capture/export tests and asset-license review.

We intentionally will **not** introduce multiple parallel compositor/timeline implementations or mandatory AI into the MVP.

## Try Cineo without Xcode.app

The default test runner now uses SwiftPM plus **Apple Command Line Tools** only. No Xcode.app or Apple Developer Team is needed for the Capture Alpha.

```bash
bash scripts/test-cineo.sh --preflight
bash scripts/test-cineo.sh --quick
bash scripts/test-cineo.sh --native
bash scripts/test-cineo.sh --interactive
```

The interactive command opens the local recorder; you can capture your main display and save MP4 files under `~/Movies/Cineo/`. Real permission handling and video playback still require a physical Mac smoke test. **This alpha does not yet include the Orbit editor, automatic zooms or audio.**

See [Xcode-free Mac testing](docs/testing/local-test-runner.md), [SwiftPM capture source](Apps/Cineo) and [the build decision](docs/decisions/0002-xcode-free-build.md).

## Next step: finish CLT-first P1

1. Verify the real `Cineo.app` created by `scripts/build-cineo-clt.sh` launches and produces a playable H.264 MP4 from ScreenCaptureKit on an Apple Silicon Mac.
2. Migrate audio selection and cursor input telemetry to the SwiftPM app.
3. Port one cohesive editor/compositor/timebase from the pinned Orbit reference, then connect CineoProject and CineoDirector. Avoid importing a competing renderer.
4. Confirm 16:9/9:16 edits and export through real video evidence. Keep the legacy Xcode path as a temporary reference, never the required local build.

See [the roadmap](docs/roadmap.md) for task IDs, delivery phases, acceptance criteria and stop conditions.

## License and acknowledgements

**Cineo's own distribution license has not yet been selected or published.** Existing template files and future imported upstream modules may have their own notices or restrictions. Before copying code or redistributing a build, confirm licenses for the exact upstream SHAs and preserve required copyright and attribution. Refer to [upstream adoption](docs/upstream-evaluation.md).

## Contributing

The project is in discovery. For code contributions, use the [agent/development guidance](AGENTS.md) and the [quality gates](docs/quality.md). Do not claim native features are implemented until verified on the selected macOS target.

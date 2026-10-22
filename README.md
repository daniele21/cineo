# Cineo

**Record naturally. Present beautifully.**

Cineo is a **native, local-first macOS application in active development** for creating cinematic software demos from real screen recordings.

The goal: record a workflow, get a polished first edit with purposeful zooms and cursor motion, refine the details only when necessary, then export a clear product video for a website, launch post, presentation or tutorial.

> **Project status — integrated Studio + Music Director development candidate (October 22, 2026).**
>
> `Apps/Cineo` is a native SwiftPM/SwiftUI application built using **Apple Command Line Tools without Xcode.app**. It includes live edited preview, camera keyframes, H.264 export, an optional local ACE-Step Music Director and a durable music-job queue. The supervised ACE-Step lifecycle passed its macOS CI and a local user smoke. The stacked [lifecycle PR #66](https://github.com/daniele21/cineo/pull/66) and [Smart Camera/audio PR #67](https://github.com/daniele21/cineo/pull/67) have **not** been merged to `main`. Opt-in click recording and automatic zoom proposals are currently development candidates requiring physical-Mac verification; this is not a distributed release.

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

The default test runner uses SwiftPM and **Apple Command Line Tools**. No Xcode.app or Apple Developer Team is needed for local development.

```bash
bash scripts/test-cineo.sh --preflight
bash scripts/test-cineo.sh --quick
bash scripts/test-cineo.sh --native
bash scripts/test-cineo.sh --interactive
```

The interactive command builds and opens Cineo Studio with its built-in recorder, local editor, composited Play/Pausa preview, export and optional Music Director. The PR #67 capture controls can record system/microphone audio and opt-in click metadata (both off by default). Suggested click zooms must be previewed and applied explicitly; no source MP4 is overwritten. The editor/export and combined A/V output still require final real-video verification on an Apple Silicon Mac.

See [Xcode-free Mac testing](docs/testing/local-test-runner.md), [SwiftPM capture source](Apps/Cineo) and [the build decision](docs/decisions/0002-xcode-free-build.md).

## Next steps: integrated CLT Studio

1. Stabilize and integrate the stacked PR #44 → #56 → #57–#66 and the new Smart Camera/audio PR #67; CI plus real-Mac smoke are gates, not proof of released quality.
2. Verify opt-in click PTS alignment and Smart Camera proposals against a real 30/60-second demonstration, preserving manual overrides.
3. Verify system audio/microphone permissions and recorded stream sync, followed by separate polish of timeline/UX.
4. Run the end-to-end perceptual capture → Auto Edit → Music Director → 16:9/9:16 export only after the upstream unit/CI work is stable.

See [the roadmap](docs/roadmap.md) for task IDs, delivery phases, acceptance criteria and stop conditions.

## License and acknowledgements

**Cineo's own distribution license has not yet been selected or published.** Existing template files and future imported upstream modules may have their own notices or restrictions. Before copying code or redistributing a build, confirm licenses for the exact upstream SHAs and preserve required copyright and attribution. Refer to [upstream adoption](docs/upstream-evaluation.md).

## Contributing

The project is in discovery. For code contributions, use the [agent/development guidance](AGENTS.md) and the [quality gates](docs/quality.md). Do not claim native features are implemented until verified on the selected macOS target.

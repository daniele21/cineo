# Cineo

**Record naturally. Present beautifully.**

Cineo is a **planned native, local-first macOS application** for creating cinematic software demos from real screen recordings.

The goal: record a workflow, get a polished first edit with purposeful zooms and cursor motion, refine the details only when necessary, then export a clear product video for a website, launch post, presentation or tutorial.

> **Project status — P1 experimental native bootstrap (October 2026).**
>
> The documentation describes the **intended product**, not a released application. P0 selected Orbit **conditionally**, after a 3/3 successful Xcode compile matrix, and P1 now produces an **unsigned Cineo-named staging app** from a pinned upstream checkout. Real signed Mac launch, TCC capture/audio and edit/export video validation remain mandatory and unverified. Some engineering-template materials still need migration.

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

## Next step: P1 native app smoke

1. Run `bash scripts/bootstrap-native.sh --plan` to inspect the pinned native stage.
2. On a compatible Mac with Xcode 26+, run `bash scripts/bootstrap-native.sh --build` to generate and verify the **unsigned** prototype.
3. Sign/launch the staged native app with an authorized Apple development identity and execute the real TCC/capture/audio/export checklist in [development guide](docs/development.md).
4. Continue native Cineo UX and safe fork reduction only after that evidence; never treat green compile as proof of real recording.

See [the roadmap](docs/roadmap.md) for task IDs, delivery phases, acceptance criteria and stop conditions.

## License and acknowledgements

**Cineo's own distribution license has not yet been selected or published.** Existing template files and future imported upstream modules may have their own notices or restrictions. Before copying code or redistributing a build, confirm licenses for the exact upstream SHAs and preserve required copyright and attribution. Refer to [upstream adoption](docs/upstream-evaluation.md).

## Contributing

The project is in discovery. For code contributions, use the [agent/development guidance](AGENTS.md) and the [quality gates](docs/quality.md). Do not claim native features are implemented until verified on the selected macOS target.

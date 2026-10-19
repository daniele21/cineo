# Cineo

**Record naturally. Present beautifully.**

Cineo is a **planned native, local-first macOS application** for creating cinematic software demos from real screen recordings.

The goal: record a workflow, get a polished first edit with purposeful zooms and cursor motion, refine the details only when necessary, then export a clear product video for a website, launch post, presentation or tutorial.

> **Project status — Product definition / technical discovery (October 2026).**
>
> The documentation describes the **intended product**, not a released application. This repository currently contains engineering-template materials; it has **not yet adopted or validated a native Cineo codebase**, and the native upstream decision is still pending the P0 benchmark.

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

**Orbit** ([diip3sh/orbit](https://github.com/diip3sh/orbit)) is the leading candidate for the native application foundation. [BetterCapture](https://github.com/jsattler/BetterCapture) is the robust capture baseline, [CineScreen](https://github.com/jasonzh0/CineScreen) is a compositor/export comparison, and [OpenScreen](https://github.com/getopenscreen/openscreen) informs editor UX and programmable editing. None is yet integrated into Cineo, and repo READMEs are not treated as proof of build/feature maturity.

The decision to fork Orbit versus assemble a smaller native foundation will be made only after **P0 source audit, licensing verification and reproducible Mac builds and exported demo tests**.

We intentionally will **not** introduce multiple parallel compositor/timeline implementations or mandatory AI into the MVP.

## Next step: P0

1. Audit the inherited starter and adapt its engineering configuration for a Swift native product.
2. Pin and inspect Orbit / CineScreen / BetterCapture source, licenses and dependencies.
3. Build the candidates with Xcode and run comparable real capture/edit/export workflows.
4. Publish a decision record, build/test evidence and the chosen first vertical slice.

See [the roadmap](docs/roadmap.md) for task IDs, delivery phases, acceptance criteria and stop conditions.

## License and acknowledgements

**Cineo's own distribution license has not yet been selected or published.** Existing template files and future imported upstream modules may have their own notices or restrictions. Before copying code or redistributing a build, confirm licenses for the exact upstream SHAs and preserve required copyright and attribution. Refer to [upstream adoption](docs/upstream-evaluation.md).

## Contributing

The project is in discovery. For code contributions, use the [agent/development guidance](AGENTS.md) and the [quality gates](docs/quality.md). Do not claim native features are implemented until verified on the selected macOS target.

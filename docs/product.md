# Cineo — Product source of truth

**Status:** proposed product direction, not a claim of implemented functionality.  
**Updated:** 2026-10-19.  
**Product:** Cineo, a native, local-first macOS application for cinematic screen recordings and product demos.

## Mission

**Record naturally. Present beautifully.**

Make it easy for people who build software to turn an authentic screen interaction into an effective, polished product story. Cineo is not primarily a general-purpose NLE, a screenshot manager, a synthetic video generator, or a browser-only demo service. It is a focused native Mac workflow: **Capture → Auto Edit → Refine → Export**.

## Users and jobs

| Priority | User | Job to be done | Meaningful outcome |
| --- | --- | --- | --- |
| Primary | Indie developer, maker, technical founder | Present a real feature on a landing page or in a launch post | A short compelling demo without learning a complex video editor |
| Primary | Product manager, designer, developer advocate | Explain the value of a workflow to customers or teammates | Attention is guided to the correct interaction and result |
| Secondary | Creator, educator, documentation maintainer | Make readable tutorials and walkthroughs | Clear narration and controlled pacing, with limited editing work |
| Later | Product team / coding agent | Produce consistent demos repeatedly | Presets and automation shorten ongoing maintenance |

### Core problems

1. Raw recordings are visually noisy: wandering cursors, idle time, difficult-to-read UI, and distracting surroundings.
2. Manual zooms, cuts, annotations, framing and multi-format exports take longer than recording the feature.
3. Click-follow zooms alone are not storytelling: the viewer should see **why** the action matters and what changed.
4. Web/cloud workflows are awkward for native Mac apps and can expose confidential interfaces and data.

## Product promise and differentiation

- **Native Mac-first:** SwiftUI/AppKit interface and Apple's capture/media stack, not Electron or an embedded web editor.
- **Local-first:** capture, project storage, edits and baseline export stay on-device; no login or upload required.
- **Editorially intelligent:** suggest zooms, camera movement, tempo and focus based on interactions, while preserving manual control.
- **Non-destructive:** source media remains untouched; edits are reproducible and revisable.
- **Designed rather than embellished:** restrained motion, readable content, purposeful spotlight, tasteful backgrounds and consistent brand presentation.
- **Fast first result:** the default path requires minimal configuration; advanced controls live in a dedicated Studio view.

## Primary user journey

1. Select display, window or area; configure only the necessary audio/cursor options.
2. Record a real interaction; gracefully stop and save source media plus available event metadata.
3. Cineo opens an editable project and proposes a coherent first cut.
4. Preview, accept/reject generated zooms and cuts, or refine in the timeline.
5. Apply a consistent stage (backdrop, spacing, shadow, cursor, labels) and preview the intended aspect ratio.
6. Export locally to a shareable video, preserving the source project for revisions.

**MVP north-star scenario:** a user records a 30–90 second product flow, reviews an automatically generated demo, adjusts no more than a few segments, and exports a readable 16:9 or 9:16 video.

## Product principles

1. **Meaning over clicks.** Use action → wait → result as a narrative unit; never zoom at every click by default.
2. **Clarity before spectacle.** Every movement must improve comprehension, and effects must be optional/reversible.
3. **Preview equals export.** Framing, animation timing, cursor position and captions must match between the two.
4. **Source preservation.** Never require re-recording to alter a zoom, cursor, callout, crop or transition.
5. **Privacy by design.** Never record typed text as part of cursor telemetry; provide explicit microphone/system audio/camera permissions and recording visibility.
6. **One canonical pipeline.** Do not blend incompatible renderers or timeline models without a measured reason.
7. **Own the simple path.** Defaults make good videos; complexity is progressively disclosed.
8. **Evidence over assumptions.** Upstream README claims are candidates until proven by reproducible native builds and video artifacts.

## Scope: now, next, later

**V0 — technical foundation (not a user release):** assess native upstreams, licenses, build compatibility, data model and preview/export parity.

**MVP — Capture + Auto Edit + Export:**
- Display/window recording, system audio and optionally microphone; real recording indicator.
- Mouse positions/click events recorded as an optional sidecar, with time synchronization.
- Basic trim, intelligent click-cluster zoom suggestions, cursor smoothing/highlight, backgrounds and framing.
- Non-destructive save/reopen, simple playback/scrub, undo/redo for edits.
- Local H.264 MP4 at 16:9 and 9:16, progress, cancellation and recovery of source clips.
- A direct Capture → Auto Edit → Export path.

**V1 — expressive editor:** manual camera keyframes/pan/zoom, spotlight, speed ramps, annotations/callouts, better audio, additional export presets, reliable timeline editing.

**V2 — director and automation:** result-aware semantic focus, rule-based highlight planning, reusable branded stories, optional web workflow scripts, CLI/agent integration and optionally on-device AI assistance.

These are **planned capabilities**, not current features of Cineo.

## Explicit non-goals

- General-purpose Final Cut/Premiere replacement or arbitrary multitrack film editing at MVP.
- Browser-first or server-rendered video service.
- Cloud accounts, telemetry upload, subscriptions or mandatory AI to render a basic demo.
- Screen content OCR/accessibility inspection without opt-in and clear user control.
- Generative reconstruction or falsification of product functionality; demos represent real software behaviour.
- Copying code from incompatible copyleft/redistribution-restricted projects into a differently licensed distributable.

## Material unknowns and decisions

| Question | Risk | Evidence required | Decision gate |
| --- | --- | --- | --- |
| Which native upstream is strongest? | Feasibility / maintainability | Build both, review modules, run identical clips, compare defects/performance | Finish P0 before choosing a fork |
| Can a shared composition model cover editor and exporter? | Quality | Pixel/geometry parity golden frames; synchronized audio/video | P0 and P2 |
| How good is rule-based auto editing? | Value / usability | Blind assessment of identical 30–60 s demos vs raw recording | P3 |
| What permission set is minimally viable? | Trust | Tested permission-denial/rehabilitation flows on target macOS | P1 |
| Which audience pays or adopts? | Viability | Interviews and a small number of real demo creation sessions | After MVP |

## Success measures (initial hypotheses, not achieved metrics)

- **Time to first usable export:** median <= 5 min after a <= 90 s take, measured on chosen test machines with novice users.
- **First-cut utility:** >= 70% of tested flows judged understandable without a full manual re-edit; rate with a short human rubric.
- **Control:** every generated edit is reversible and its parameters editable; 100% of tested projects reopen without losing source/edit metadata.
- **Quality:** preview/export geometric parity in representative golden frames, and intelligible UI at required target formats.
- **Trust:** no content upload on the basic workflow; secrets never appear in logs or exported project metadata.
- **Reliability:** no loss of complete source media after an export failure; end-to-end smoke passes on target macOS.

Thresholds above are **proposed product acceptance targets**. Adjust with benchmark evidence, not intuition.

## Design partners and validation

Start with three different workflows: a native Mac app, a dashboard-style SaaS web interface, and a high-density form/report UI. For each produce raw, Cineo default and manually polished reference versions. Test whether observers understand the value, how much manual correction is required, and whether the export is readable on mobile. Document results and revisit scope accordingly.

## Documents

- [Feature specification](feature-spec.md)
- [UX and cinematic grammar](ux-motion.md)
- [Architecture proposal](architecture.md)
- [Upstream evaluation and reuse policy](upstream-evaluation.md)
- [Quality and verification](quality.md)
- [Execution roadmap](roadmap.md)

# Cineo — Development roadmap and implementation plan

**Status:** active implementation; baseline is a stack of unmerged feature branches, not a released app.  
**As of:** 2026-10-22.  
**North star:** first-class macOS capture → intelligent local Auto Edit → user-controlled refinement → publishable export.

## Active delivery snapshot (2026-10-22)

The new CLT-first integrated Studio has already gained real frame-based Play/Pausa preview, manual camera controls, music generation with durable queued jobs, and an ACE-Step supervisor. The lifecycle commit `d65f9e0a` has green macOS CI; the developer reports that it works on the Mac. These changes live in PR #66 stacked on #65 and earlier branches, **not in main**.

Parallel active work in [PR #67](https://github.com/daniele21/cineo/pull/67):
- **Camera:** deterministic, click-only zoom proposals from the existing CineoDirector planner, previewed before explicit apply, with no silent manual-keyframe overwrites.
- **Capture:** opt-in mouse click sidecar (first ScreenCaptureKit frame host time), optional system audio and microphone (off by default), no text/keystroke recording.
- **Integration:** preserve recorded click metadata across save as `.cineo` and reopen; one CineoScene renderer for preview and export.

### Next delivery gates

1. **Integration baseline:** green CLT build/music/events/director/scene/QA checks; resolve stacked PR ancestry and duplicate audio-polish proposals, without blind cherry-picks.
2. **Smart Camera quality:** actual click PTS and display normalization, zoom compositional quality, 30/60-second samples, explicit overrides, project reopening.
3. **Audio capture and Studio:** permission-denied behavior, system/microphone recording, A/V drift, frame/audio preview parity, cue/ducking handling.
4. **Final physical-Mac E2E:** capture → auto proposal → manual refine → music generation → 16:9 and 9:16 export, visual review and headphone listening. This is intentionally deferred until the earlier gates pass.
5. **Distribution:** license audit, Developer ID signing/notarization, compatibility and rollback after product gates.

## Planning rules

- Each milestone is a **vertical outcome** with a demo and measurable exit criteria, not a bucket of classes.
- Work from P0 to P3 on the critical path; later tracks may be researched in parallel without forcing premature integration.
- Do not assume Orbit is fully production-ready because its README lists a feature.
- When a spike fails, choose a smaller reliable foundation rather than adding a second live renderer.
- Mark code/migrations honestly: template files currently present in Cineo are **not** evidence of a working Swift app.
- Suggested effort levels are relative (S/M/L/XL), **not time commitments**.

## Execution status as of 2026-10-20

**P0 architecture selection is conditionally accepted for P1 experimentation** under [ADR-0001](decisions/0001-native-foundation.md). A three-candidate macOS/Xcode build matrix passed, and the pinned Orbit-based unsigned Cineo staging build passed identity/exec checks. This is a deliberately narrower P0 **selection** gate than the original interactive-media benchmark below: the unperformed signed capture, TCC, real export, media-quality comparison and complete third-party art license review were **not passed or waived for delivery**; they are moved to mandatory **P1-GATE-A–E** before calling the native workflow validated.

The old P0 engineering-template migration work remains open as P1 repository cleanup. [Issue #3](https://github.com/daniele21/cineo/issues/3) tracks the next real native capture-to-file milestone. This note does not claim Cineo is distributable.

## Critical path

| Milestone | Outcome | Main deliverable | Depends on | Exit gate |
| --- | --- | --- | --- | --- |
| **P0 Foundation decision** | Know what to reuse | Audited Orbit/CineScreen/BetterCapture comparison, exact refs, native build/export evidence | none | G0 |
| **P1 Native capture slice** | Record a usable clip reliably | Cineo-branded native shell, capture, permissions and local media | P0 | G1 |
| **P2 Editor core & correctness** | Edit/reopen/render deterministically | Versioned project, event sidecar, camera transform, single scene renderer | P1 | G2 |
| **P3 Publishable MVP** | One-click polished first draft | Click-cluster zoom, cursor smoothing, Auto Edit, framing, 16:9/9:16 export | P2 | G3 |
| **P4 Professional refinement** | User can correct and polish any edit | Keyframes, pan, spotlight, masks/callouts, speed and audio polish | P3 | G4 |
| **P5 Storytelling and automation** | Repeatable, result-aware product demos | Semantic anchors, director plan, brand presets, optional CLI/web workflows | P3/P4 | Benchmarked |
| **P6 Distribution** | Trusted public Mac release | Signing, notarization, update/recovery, docs and support | P3; P4 optional | G5 |

### P0 — Technical and product foundation

**P0.1 — Inspect Cineo starter.** Identify inherited repo-template-sw files and distinguish reusable engineering contracts from template-owner content. Adapt project-specific AGENTS/readme/.engineering files without deleting reusable checks indiscriminately. Ensure no CI job falsely assumes Cineo itself owns repo-template-sw.

**P0.2 — Pin upstreams and inventory code.** Inspect Orbit (diip3sh) and CineScreen at concrete SHAs; BetterCapture is the baseline/fallback. Inventory exact native capture, cursor, editing, persistence, output and Motion source. Mark shipped/partial/docs-only.

**P0.3 — License and provenance.** Read actual licenses and third-party dependencies/media assets; decide distribution options before any code transplantation. Maintain a per-file reuse ledger.

**P0.4 — Reproduce benchmark.** Same Mac, same capture scenes, audio, frame rate, export aspect ratio. Measure capture stability, audio sync, frame/geometry parity, CPU/GPU/RAM and reliability. Include a real 9:16 version and a failure case.

**Exit:** written architecture decision (ADR) with chosen foundation, commit pins, benchmark artifacts and explicit missing pieces. **No broad fork merge or rebrand before this exit.**

### P1 — Native capture slice

- **P1.1:** Add/configure Cineo Xcode project/app shell; macOS target, bundle identity, app menus and shortcuts.
- **P1.2:** Window/display capture with visible start/stop/countdown, permission state and errors.
- **P1.3:** Capture system audio, optionally mic, with timestamp validation; ability to opt out.
- **P1.4:** Persist raw recording to durable local storage; recover gracefully from cancellation/interruption.
- **P1.5:** Automated unit/integration tests + one physical-Mac end-to-end recording smoke.

**Exit:** clean build/test and reopenable recording on the chosen supported Mac; no network or account required.

### P2 — Non-destructive editing and rendering core

- **P2.1:** Define explicit event sidecar schema and source-to-event timebase mapping. Do **not** capture typed text.
- **P2.2:** Create versioned Cineo project package with immutable source and editable graph, safe autosave and migrations.
- **P2.3:** Normalize coordinates in all source/canvas/output spaces and enforce cursor-click alignment.
- **P2.4:** Prove one shared scene evaluation contract for scrub preview and offline export.
- **P2.5:** Minimal timeline trim + undo/redo; golden-frame and source-recovery tests.

**Exit:** edits reopen identically; sample golden frames and audio are synchronized; preview/export matching is documented and measured.

### P3 — The first publishable Cineo demo

- **P3.1:** Deterministic Smart Camera: click clustering, dwell candidate detection, zoom suppression, easing, hold, zoom-out and explainable suggestion types.
- **P3.2:** Cursor as independent overlay; smoothing, click rings and idle-hide option when available.
- **P3.3:** Auto Edit UX and preset selection. Suggestions visibly distinguished from overrides.
- **P3.4:** Stage styling: background, padding, radius and shadow with legible dark/light UI.
- **P3.5:** Local 16:9 and 9:16 MP4 export; progress/cancellation and source-preservation tests.
- **P3.6:** End-to-end examples: native Mac, SaaS dashboard, dense form/report. Produce source, Cineo edit and final video with inspectable evidence.

**Exit:** a new user can go from short take to usable export with a few actions. User evaluation and readable mobile output accompany technical success.

### P4 — Studio refinement

- Manual pan/zoom/keyframe lanes and meaningful easing inspector.
- Spotlight/masks with conservative defaults; callouts and labels with safe zones.
- Clip-level speed, silence handling, audio controls where stability permits.
- Brand presets; undo/redo of all editor operations, keyboard accessibility and reduced-motion mode.
- Regression corpus for text legibility, extreme aspect ratios and timeline continuity.

**Exit:** user can correct every auto-edit error non-destructively; manual edits are not lost when regenerating suggestions.

### P5 — Semantic director and programmable demo

- Define result/action narrative units and reusable storyboard schema with validated render plan.
- Add **manual focal anchors first**; evaluate Accessibility and DOM-derived anchors as opt-in extensions.
- Prefer deterministic plan generation and validation before local VLM/LLM experimentation.
- CLI and scripted web recording operate on canonical Cineo projects. Preview and export use identical renderer.
- Advanced Product Film compositions are an independent research track, gated by compositor and UX proof.

**Exit:** compare understood feature value and editing time against P3 rule-based baseline. Optional AI must improve measurable utility without compromising offline core.

### P6 — Distribution, maintenance and adoption

- Apple Developer signing, hardened runtime, entitlements, notarization, safe updates and rollback.
- Reproducible release build and explicit privacy disclosures.
- Accessibility QA, documentation, issue templates, troubleshooting bundle and privacy-safe diagnostics.
- Compatibility support policy for Apple Silicon and chosen macOS minimum; no App Store or commercial claim before final license review.

## Prioritized issue backlog

Each issue has a vertical deliverable; codes can be used as issue titles and acceptance links.

| ID | Title | Priority | Estimate | Dependencies |
| --- | --- | --- | --- | --- |
| [CINEO-001](https://github.com/daniele21/cineo/issues/1) | Audit native upstream builds, module maturity and licensing | P0 | L | — |
| [CINEO-002](https://github.com/daniele21/cineo/issues/2) | Finish native Cineo engineering-baseline migration | P1 | M | P0 selection |
| [CINEO-003](https://github.com/daniele21/cineo/issues/3) | Create native Cineo capture-to-file vertical slice | P1 | L | 001, 002 |
| [CINEO-004](https://github.com/daniele21/cineo/issues/4) | Time-synchronized cursor/click sidecar | P1/P2 | M | 003 |
| [CINEO-005](https://github.com/daniele21/cineo/issues/5) | Versioned, crash-safe project and undoable edit model | P2 | L | 003 |
| [CINEO-006](https://github.com/daniele21/cineo/issues/6) | Shared scene geometry and preview/export parity | P2 | XL | 005 |
| [CINEO-007](https://github.com/daniele21/cineo/issues/7) | Smart Camera zoom rules + independent cursor effects | P3 | L | 004, 006 |
| [CINEO-008](https://github.com/daniele21/cineo/issues/8) | Auto Edit and progressive Studio UX | P3 | M | 005, 007 |
| [CINEO-009](https://github.com/daniele21/cineo/issues/9) | Local portrait/landscape export and safe reframing | P3 | L | 006, 008 |
| [CINEO-010](https://github.com/daniele21/cineo/issues/10) | Native E2E, golden frames and benchmark fixture corpus | P0–P3 | L | 001 then continuous |
| [CINEO-011](https://github.com/daniele21/cineo/issues/11) | Manual keyframes, spotlight, callouts and editing polish | P4 | XL | 009 |
| [CINEO-012](https://github.com/daniele21/cineo/issues/12) | Semantic Director and repeatable demo automation | P5 | XL | 010, 011 |
| [CINEO-013](https://github.com/daniele21/cineo/issues/13) | Native signing, notarization and release readiness | P6 | L | 009, 010 |

## Workstreams and safe parallelism

**Track A — app/capture:** initial upstream audit, capture/session lifecycle, audio/permissions.  
**Track B — data/render:** model/timebase, geometry, renderer parity, golden frames.  
**Track C — product/editor:** demo rubric, preview, Auto Edit flow, design.  
**Track D — compliance/release:** provenance/licenses, privacy, signing/release.

Parallel work is safe while modules have stable interfaces and independent fixtures. Do **not** concurrently edit capture timestamps or compositor geometry from multiple uncoordinated branches. Integrate only after a full vertical journey runs.

## Decision gates / stop conditions

1. **After P0:** if Orbit cannot build/test reliably or its renderer fails parity, stop the fork plan and evaluate BetterCapture/CineScreen rather than patch around unknown defects indefinitely.
2. **After P2:** if preview/export differ on geometry/timing, do not add semantic AI or layered motion features.
3. **After P3:** if videos need extensive manual repair, spend the next iteration on deterministic focus/pacing before new effects.
4. **Before release:** unresolved licensing, opaque network dependencies, notarization failure, permission leaks or source-loss defects block distribution.

## Initial experiments to run before promising AI

- Compare raw clip, Orbit auto-zoom, Cineo rule-based camera and manually edited Screen Studio-style reference.
- Metric set: comprehensibility score, viewer attention, number of unwanted zooms, manual corrections, time to usable export, and CPU/GPU/memory.
- Use at least one sample with zero clicks, one dense dashboard and one long wait to avoid overfitting on a “happy path”.

## Definition of each milestone handoff

Attach: relevant commits, exact native toolchain/macOS, test command/result, generated video and representative frame screenshots, failure notes, any privacy/licensing deviations and updated product/architecture docs. Partial functionality should be labelled explicitly as prototype rather than shipping.

References: [product](product.md) · [features](feature-spec.md) · [architecture](architecture.md) · [upstreams](upstream-evaluation.md) · [quality](quality.md) · [motion](ux-motion.md).

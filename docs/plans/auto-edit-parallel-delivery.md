# Cineo — Auto / Assisted / Studio / CLI: parallel delivery plan

**Status:** execution plan (proposed; not an implemented feature). **Date:** 2026-10-20.  
**Baseline:** native macOS CLT-only `Apps/Cineo`. Real-Mac evidence: a **25 s screen recording was finalized** into a playable-structure H.264 MP4, 8.5 MB, with a video track, after the stream-stop candidate. This is **one successful recording**, not full P1 regression. Fix/signing/LaunchServices changes live in **draft [PR #44](https://github.com/daniele21/cineo/pull/44)** and are **not yet merged into main**.

## Product outcome, not just engineering activity

**Record → Auto Edit → optionally Refine → Export**, all offline and without Xcode.app. A user should open a recording, see a credible first cut, disable or tune suggested effects, and export a real, visually modified MP4. The **same canonical project and render engine** must also be consumable by an optional **headless CLI**. Three user modes share the same underlying data:

- **Auto:** apply conservative deterministic presets and suggestions; user can export immediately.
- **Assisted:** show why suggestions were generated and allow individual accept/reject/adjust controls; manual edits survive regeneration.
- **Studio:** direct timeline/keyframe/control editing, with the same preview and exported results.
- **CLI:** reproducible local plan/inspect/export; no hidden cloud inference or mandatory graphical app. Future agents operate by producing validated plans, not bypassing validation.

For the first slice, *Auto* means **style/framing presets and optional event-based camera suggestions**. Where pointer telemetry does not exist, use a static composition or manually chosen focus; do not fabricate clicks, semantic results or AI confidence.

## Reality check / reusable assets

| Component | Evidence in repository | Gap to close |
| --- | --- | --- |
| `Apps/Cineo` | SwiftPM/CLT ScreenCaptureKit recording, local MP4, live metrics, completion verification candidate | No editor, no post-production renderer, no synchronized pointer sidecar, no audio |
| `Packages/CineoProject` | `CineoManifest`, `CineoProjectStore`, `TimelineMapper`, `CineoEditHistory` | Native capture → `.cineo` lifecycle and app integration, extensible effect/style schema |
| `Packages/CineoDirector` | `CameraPlanner`, `CameraPreset` (subtle/balanced/dynamic) | Real event ingestion and visual validation, not just synthetic unit tests |
| `Packages/CineoEditPlanner` | `SourceAttentionEvent`, `SuggestedCameraPlan`, persistence and edit-aware time mapping | Suggested/manual layer merge, UI/renderer/CLI integration |
| `Packages/CineoExportProbe` | Read-only AVFoundation MP4 metadata validation | It does **not** export or compose a video |
| Legacy Orbit-based native editor | Prior experimental code and integration tests, but requires separate Xcode path | **Not** part of the current CLT app; reuse only after explicit licensing and compatibility evaluation |

**Non-negotiable:** SwiftPM + Apple Command Line Tools only; Apple Silicon macOS 15+ baseline; on-device/offline; single scene evaluator; deterministic effect plans; original media preserved; no typed text in telemetry; never pass off a simulated preview as actual rendered output.

## Mandatory source-reuse and CLT renderer decision

**Source-level evidence and pinned upstream SHAs:** [2026-10-20 Auto Edit repository research](../research/auto-edit-upstream-2026-10.md). Before implementing the Track B renderer, explicitly compare these approaches, rather than starting a greenfield compositor or attempting to import a full Xcode/Electron-based editor:

1. **Primary** — Orbit's Swift/Core Image `RenderPlan`, `FrameRenderer`, `CameraPath`, `TimeMap` model, with only a small audited and licensed subset considered for migration to the CLT-only Cineo SwiftPM target. Cineo's preexisting `CineoProject/CineoEditPlanner/CineoDirector` remain canonical data/planning owners; do not establish a second persistent editing schema.
2. **Independent reference** — CineScreen's shared `FrameCompositor` (single render pass implementation for live preview and offline export). This is an architectural pattern, not permission to introduce mandatory `.metal` shader compilation. A dedicated standalone **CLT-only** shader compiler probe is a prerequisite for the Metal variant.
3. **Automation** — OpenScreen's GUI/CLI shared export job and frame-progress contracts; Auto-Editor's activity/idle selection and dry-run; Palmier's validated agent tools/job cancellation. Cineo's CLI is native SwiftPM and does not start a hidden Electron window.
4. **Restricted code** — ArcShot's modified MIT license forbids App Store derivations, Recordly/Cap majority AGPL, Palmier GPL, Remotion custom terms. Treat code as read-only research unless the actual per-file license/redistribution conditions are intentionally accepted and documented.
5. **Model accuracy** — recording without pointer events is not equivalent to retrospective click recognition; silent video is not a valid input for automatic silence cuts. First G1 demonstration must work entirely without telemetry via style + manual camera.

**New Track B early exit gate:** 25-second real MP4 → Core Image/AVFoundation edited MP4 with an observable style+zoom, CLT-only successful build, source unchanged, output metadata and sampled frames verified. No Studio GUI or agent scripting is allowed to claim production readiness before this real output exists. **Metal is only a secondary measured spike**; if compiling shaders requires Xcode.app, fail/abandon that spike without blocking the primary renderer.

## Milestones and dependency graph

```text
G0: PR #44 integration + capture regression + frozen interfaces
 | 
 +--> A: project bridge / durable edit state ------+
 +--> B: scene evaluator & render spike -----------+---> G1: one real styled MP4
 +--> C: timecoded mouse telemetry ----------------+          |
 +--> D: Auto/Assisted/Studio UI prototype --------+---> G2: UI editor + suggestions
 +--> E: headless CLI/API contract ----------------+          |
 +--> F: fixture corpus, quality + CI -------------+---> G3: UI/CLI same edit/output
                                                       |
                                             G4: publishable first-cut MVP
```

G0 interface design can be documented and pure Swift experiments can branch from main **in parallel with** the real-Mac regression. Do not integrate new app capture/editor mutations on top of unmerged PR #44 unless they explicitly rebase on that branch and verify its latest head. Serial integration owns `Apps/Cineo/Sources/Cineo/CineoApp.swift`, `Apps/Cineo/Package.swift`, the app bundle/signing scripts, and the final rendering pipeline.

### G0 — serial 0: capture readiness + contract freeze

**Lead/integration owner; needed before cross-track merges.**

- [ ] Run real-Mac 3 s / 10 s / 60 s captures plus two consecutive sessions. Confirm the matching signed `Cineo Dev.app`, source revision, finalized MP4, actual playback, and retained permission. Record macOS/CLT/host, file dimensions/duration and sanitized logs. The supplied 25 s success is initial evidence only.
- [ ] Ensure current **PR #44** checks are green, code-reviewed and merged. **No silent merge** of a draft fix while evidence is pending.
- [ ] Freeze the *v0 interfaces* below via an ADR/check-in test fixture; specify who owns schema migrations and concurrency.
- [ ] Fix one canonical headless render/evaluation entrypoint and output media timebase; avoid adopting the old Orbit Xcode-only compositor without proof.

**v0 cross-track contract, to ratify before coding integration:**

| Contract | Owner | Consumers | Invariants |
| --- | --- | --- | --- |
| `CineoManifest` (`.cineo` package) | A | B/C/D/E | immutable media, versioned manifest, atomic save, explicit source ID/timebase |
| `SourceAttentionEvent` + `SuggestedCameraPlan` | C for capture; existing EditPlanner for semantics | A/B/D/E | normalized `[0,1]` source coordinates, source PTS, no typed text, explicit no-telemetry |
| `EditDecision` (new typed model) | A + B joint spec | D/E/B | separate `suggested` / `accepted` / `manualOverride` / `rejected` lanes, stable IDs and regeneration rules |
| `SceneState at output time t` | B | D/E/exporter | one time mapping, source→canvas→output transform, reproducible camera/cursor/stage |
| `EditJob` / `ExportJob` result | E with B | UI/CLI/CI | explicit progress, cancellation, errors, source preservation, output path, stable plan hash |

Don't extend the manifest independently in six branches. A schema-contract PR must land first; field names here are provisional interface concepts, not shipped Swift types.

## Wave 1 — independent parallel work, immediately after G0 schema proposal

| Track / ownership | Concrete tasks | Deliverable and acceptance | Dependency | Existing issue |
| --- | --- | --- | --- | --- |
| **A · Media/project bridge** — `Packages/CineoProject/**`, new app adapter files (integration-owned) | Import verified recording into `.cineo`, store media read-only, add style/effect lane versioning, undoable edit decision model, save/reopen, failure recovery | Pure Swift project tests; actual 25 s MP4 imported and reopened unchanged; crash/failed import never destroys source; migration fixture | G0 interface | [#5](https://github.com/daniele21/cineo/issues/5) |
| **B · Canonical scene/renderer spike** — new `Packages/CineoScene/**` + macOS render target, never modify recorder | Specify source pixels → scene → output coordinates and source PTS→output frame; implement background/padding/radius/shadow; animated zoom/pan; same `SceneState` evaluator for preview/export; bounded frame pipeline | First *real* 16:9 styled MP4 from an existing clip via AVFoundation; matching scene frames checked at start/mid/end; 9:16 spike with safe-crop proof; no mocked result | G0 scene contract; can use fixed synthetic project while A runs | [#6](https://github.com/daniele21/cineo/issues/6), [#9](https://github.com/daniele21/cineo/issues/9) |
| **C · Privacy-safe telemetry** — new `Packages/CineoEvents/**` and discrete capture adapter, no UI changes | Opt-in pointer/click event capture, monotonic clock→source PTS calibration, Retina/screen transform, robust no-click/no-permission fallback | Unit/integration fixtures for offsets, speed/trim, multi-display origin and no-click; actual Mac cursor→frame alignment; never collect typed text | G0 event contract; integrate recorder only under integration owner | [#4](https://github.com/daniele21/cineo/issues/4) |
| **D · UI/UX** — self-contained SwiftUI `AutoEditView`, `StudioView`, view models using mocks | Immediate preview after Stop, safe action choices Auto/Assisted/Studio, style presets, individual suggestion switches, manual edit controls, export/progress states, accessibility | Navigable native mock backed by shared model, screenshot and state/error tests; no duplicate renderer or fake export claims | G0 view-model contract; depends on B for real preview later | [#8](https://github.com/daniele21/cineo/issues/8) |
| **E · Headless workflow** — new `Tools/CineoCLI/**` / `Packages/CineoAutomation/**`, CLI parser/service only | Define `project create`, `plan --mode auto|assisted`, `plan inspect`, `render`, `validate`; deterministic JSON/progress/errors, local-only and no overwrite by default | CLI contract tests with fixture `.cineo`, same plan hashes as app; renderer supplied through B later; no Xcode.app | G0 job/API contract; can mock evaluator until B stable | [#12](https://github.com/daniele21/cineo/issues/12) (MVP CLI scope pulled forward) |
| **F · Benchmarks/quality** — `docs/testing/**`, `Tests/Fixtures/**`, dedicated CI | Build copyright-safe 3 scenarios (native, SaaS-like, dense form), no-click, cursor corners, 25 s real fixture instructions; MP4 probe, source hash, golden frames, memory/progress/failure instrumentation | Automated no-telemetry, frame geometry, cancel, file safety and CLI/UI plan consistency gates; real-Mac manual protocol | Can begin at G0 without runtime changes | [#10](https://github.com/daniele21/cineo/issues/10) |

**Safe parallelism:** A/C/B/E/F own separate package directories. D owns new SwiftUI files but not app root, and must not change render API unilaterally. Track B's scene/effect definitions require a small reviewed shared-contract PR before A/D/E compile against them. Track C must not modify the recorder in parallel with G0 capture fixes: submit isolated adapter + integration instructions.

## Wave 2 — integration checkpoints, serialized where files/lifecycle overlap

1. **G1 · Styled video without automation.** Integrate **A + B + F**: pick/open a source MP4, create/edit/reopen a `.cineo` project, render a visibly changed H.264 MP4 with preset frame/background, one optional manually placed zoom; source SHA unchanged. Validate with export probe, aspect/duration and sample frame comparison. This is the **shortest path to product value** and does not depend on telemetry or an AI model.
2. **G2 · Automated suggestions + human control.** Integrate **C + CineoDirector/EditPlanner + D**: optional click telemetry, deterministic clusters and camera suggestions, no-click fallback, per-suggestion explanation and accept/reject, manual focus target and regeneration preserving overrides. Then drive B's scene evaluator from the accepted plan. Validate two consecutive recordings plus reopening.
3. **G3 · UI/CLI equivalence.** Connect **E + B + A** through the *same* engine/service: a graphical export and a CLI export with the same canonical project, plan, output spec and frame evaluation must yield equivalent framing and timing (container binary bytes need not match). CLI cannot invent effects beyond those available in Studio.
4. **G4 · MVP quality gate.** Test 16:9/9:16 for 3 fixture flows, no-click, dense UI, high-DPI; progress/cancel/restart, insufficient storage, interrupted export and source recovery. Validate focus/readability with a human rubric; report first-cut manual corrections and time-to-export. **Do not claim complete automatic storytelling** based solely on click proximity.

## Suggested branch/PR lanes

- `feat/cineo-project-capture-bridge` — A, touches project package and its tests.
- `feat/cineo-scene-renderer` — B, new scene/render package and goldens.
- `feat/cineo-pointer-sidecar` — C, event package and fixtures; recorder touch only in an agreed integration PR.
- `feat/cineo-autoedit-ui` — D, new views and VM; first PR may use mocks.
- `feat/cineo-headless-cli` — E, CLI and typed service contract.
- `test/cineo-real-media-regression` — F, fixtures/probes/CI.
- `feat/cineo-autoedit-integration` — **one integration branch**, serial owner of app entrypoint/Package.swift, export plumbing, navigation and wiring; only cherry-pick/rebase verified unit PRs. Each track PR stays narrow.

Each PR must declare files/contract versions touched, tests run, CLT-only commands, fixture hash, failure modes and evidence. Require no overlapping app-root edits, no unreviewed schema changes, no Xcode.app dependency, no new network calls and no unlicensed media.

## Measurable acceptance / clear limits

| Gate | Objective evidence |
| --- | --- |
| G0 capture | 3/10/60 s, two sequential captures, TCC persists, no -5814, final MP4 decodes; CLT workflow green |
| G1 local editor | 25 s source import and reopen; styled before/after video; one manual zoom, one trim, undo/reopen; original source hash unchanged |
| G2 automatic+assisted | At least one genuine click-led camera edit from synchronized telemetry; explainable toggles, manual edit retained on regeneration; no-click still exports |
| G3 automation | Same `.cineo` + plan exported from CLI/UI; frame geometry/timing within calibrated tolerance, deterministic JSON plan, nonzero exit for corrupt inputs |
| G4 usable demo | 3 representative workflows in 16:9/9:16, understandable content, calibrated golden-frame parity, export cancellation and recovery, first-cut quality rubric |

**Performance targets, not measured claims:** 30–90 s source → first usable cut with minimal interaction; aim to eventually test median ≤5 minutes to export and ≥70% understandable first cuts, revising from real user evidence. Cursor/A-V sync thresholds calibrated from actual captures. No estimated dates until first renderer/capture measurements.

## Sequencing, risks and decisions

- **Highest risk:** B actual renderer/preview/export parity, followed by C timestamp/coordinate alignment, followed by signing/TCC regression and app integration. Run renderer feasibility and telemetry calibration early, not after fully designing the UI.
- **Source material:** `SCRecordingOutput` output has native screen content but not an independently reconstructable per-click history. Existing 25 s file supports style/manual-camera tests, **not accurate retroactive cursor click tracking**. Future captures need opt-in telemetry.
- **Audio:** absent from the current CLT recorder. A separate opt-in P1 audio track can start in parallel *after capture lifecycle is stable*, but do not block silent first vertical slice. Never claim audio mixing/silence-based cuts from silent inputs.
- **Semantic AI:** defer model-based narrative understanding until deterministic camera/editor baseline is measurable; manual focal targets are always supported. No mandatory on-device model download.
- **Failure modes:** absent telemetry ⇒ static/styled or manual focus; invalid/unsafe camera plan ⇒ validation error, not corrupted export; app restart/CLI failure ⇒ original media retained; cancel ⇒ remove only temporary render.
- **Merge policy:** pure package/test work may be merged independently after CI; integration merge requires actual Mac-produced MP4 and verified GUI state; PR #44 remains its own separately validated stop/signing fix.
- **Ownership:** G0 and integrations are serial. Parallel agents may work only within track-owned files and fixed shared interfaces; explicitly coordinate schema/API revisions.

## First actionable sprint (sequence, no speculative ETA)

1. G0: finish [PR #44](https://github.com/daniele21/cineo/pull/44) physical-Mac regression and review; freeze v0 contracts.
2. **Start B, A, F and E in parallel** against synthetic or already verified MP4 fixtures; D can build mock UI concurrently; C can implement the pure event contract without changing capture.
3. Reach **G1** first: style + manual camera + export real video from the verified 25 s source (no new permissions).
4. Integrate optional telemetry and rule-based Director for **G2**; prove user overrides survive regeneration.
5. Wire the same project/scene/export service to the CLI and native UI (**G3**).
6. Use quality results to decide whether to prioritize adaptive editing, more effects, or a future opt-in semantic Director.

**Definition of done:** one real Mac capture can be opened as a project, automatically styled, optionally manually corrected, and **exported as a different playable video**; the equivalent local headless workflow produces the same planned scene; original footage and user edits survive failure/reopen. A compiled library, isolated synthetic test or static UI mock alone does not qualify.

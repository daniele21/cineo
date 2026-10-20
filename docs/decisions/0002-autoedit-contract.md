# ADR-0002 — Auto Edit v0 module contracts

**Status:** PROPOSED (contract for independent prototype PRs, not shipped API)  
**Date:** 2026-10-20  
**Scope:** the *standalone SwiftPM/CLT Cineo Dev* application, not the older Xcode Orbit stage. Draft capture fix [PR #44](https://github.com/daniele21/cineo/pull/44) must pass real Mac regressions before app integration.

## Canonical ownership and invariants

- **CineoProject** owns versioned `.cineo/manifest.json`, source identifiers, reversible edits and **only** output↔source timeline mapping; source video is copied without alteration or overwritten.
- **CineoDirector/CineoEditPlanner** own deterministic suggested shots with reason and source PTS→output mapping. No second AI timeline. Sidecar suggestions never rewrite user-authored adjustments.
- **CineoEvents** is an opt-in, mouse-only sidecar and monotonic-host-clock→first-video-PTS calibrator. No keystrokes, clipboard contents or DOM text. Missing events never prevent basic import/edit/export.
- **CineoScene** owns a time-dependent `ScenePlan`, fixed output dimensions, camera target/zoom, canvas/style, and source-frame→output-frame transform. No UI-specific or CLI-specific compositor; one timeline `t` means one scene geometry in both.
- **CineoAutoEditUI** consumes project/edit/scene services from the integration app. It never writes MP4 directly or claims hypothetical suggestions were applied.
- **CineoCLI** is a native SwiftPM executable with stable JSON contracts for inspect/plan/validate; real `render` must call CineoScene's shared media renderer once available, not a separate FFmpeg exporter.
- **Test/QA** owns adversarial fixtures, project safety/cancel checks, real file probing and local CLT-only repeatability.

## Time/coordinate conventions (v0)

- Time always in **seconds from the first actual frame PTS** (not Date.now or app launch), except raw monotonic host event timestamps whose offset has explicit calibration.
- Events `(x,y)` normalized to **recorded content pixels**, top-left origin, x/y ∈ [0,1]. Multi-display translation and Retina scaling happen at capture adapter boundary, not in planners.
- `CineoProject.TimelineMapper` maps any edited output time to one source ID and source second. Zoom holds/suggestions refer to **output time**; raw click sidecar refers to **source time**.
- Camera zoom x1 means overview. `focusX/Y` represent source-relative normalized focus; crop clamps to content boundaries, avoiding offscreen black. Interpolate zoom in **log scale** and center smoothly.
- A project's persisted **manual overrides have precedence** over regenerated suggestions and rejected IDs remain excluded; no edits to source media.

## First integration acceptance

1. Actual ScreenCaptureKit H.264 MP4 from physical Mac imports into `.cineo`, save/reopen works and source is never mutated.
2. One CoreImage/AVFoundation rendered H.264 MP4 with observable styling and manual zoom, verified video track/duration/geometry, built using `DEVELOPER_DIR=/Library/Developer/CommandLineTools`; do not require Xcode.app, Metal shader compiler, Python or FFmpeg.
3. Before event capture, no-click Auto mode must fall back to style-only; do not hallucinate recorded clicks or semantic activities.
4. Human-readable + machine-readable progress states: `preparing`, `rendering`, `verifying`, `promoting`, `complete|failed|cancelled`. Percent only from real completed frames, ETA only from measurements.
5. Avoid dual running app identities: only `~/Applications/Cineo Dev.app`, pinned signature and exact source marker as in PR #44.

## Integration / repository

Six parallel PRs own separate new packages or files. A **single integration owner** can modify `Apps/Cineo/Package.swift`, `CineoApp.swift`, `scripts/build-cineo-clt.sh` and persistent signing after PR #44 validation. Prototype PRs from `main` are allowed before PR #44 merges; **do not** modify the recording app inside them. The source research and license matrix live in [upstream study](../research/auto-edit-upstream-2026-10.md).

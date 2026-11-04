# Cineo — Native motion, cursor and timeline upgrade (Recordly benchmark)

**Date:** 2026-11-04  
**Status:** execution plan + independent engineering tracks; no release claims  
**Starting integration candidate:** `feat/cineo-cuts-studio-v1-20261022` at `7dfb5a9a62eab07a65bec939505dd68987202b06` (PR #72). `main` remains untouched.  
**Goal:** high-quality demo editing with deterministic, local-first native Swift, preview/export parity, no Electron/PixiJS and no Xcode.app dependency.

## Evidence, scope, non-goals

Recordly (https://github.com/webadderallorg/Recordly, AGPL-3.0) informs behavior only. Inspected:
- `src/components/video-editor/timeline/zoomSuggestionUtils.ts`: explicit-click clusters, overlapping region protection, additional classification heuristics not enabled on the main auto-suggest path.
- `src/components/video-editor/videoPlayback/motionSmoothing.ts`: under/critical/over-damped spring solver.
- `src/components/video-editor/videoPlayback/cursorFollowCamera.ts`: cursor safe zone, edge clamp, release freeze.
- `src/components/video-editor/videoPlayback/cursorRenderer.ts`: cursor samples, state interpolation, click bounce/ripple, sway and blur.
- `src/components/video-editor/timeline/dnd/engine.ts`, `docs/timeline-sequence.md`: contiguous clip model, snapping/resize/move and source-time mapping.

Our independent implementation must not copy AGPL source, shaders, artwork or assets. A commercial/redistribution licensing decision remains pending. Native implementation choices derive from documented observable behavior and independent specifications.

Cineo existing source reviewed on PR #72: `CineoEvents/CineoPointerEvents.swift` (mouse-only sidecar v1; moved case present but capture records clicks), `CineoDirector/CameraPlanner.swift` (click/dwell/result grammar), `CineoScenePlan.swift` (smoothstep/log zoom and shared evaluator), `CineoSceneFrameRenderer.swift` (Core Image composition and click ring), `CineoManualEditor.swift` (separate slider, clip cut controls and keyframe buttons). Existing cut contract `CineoCutList` maps output<->source time; cuts are still gated when music/keyframes exist. No full perceptual E2E has passed.

## Global invariants / APIs

1. **Time:** stored media timestamps and edited-output timestamps explicitly named. Every feature consumes a single `outputTime -> sourceTime` mapping. At a removed source span, interpolation must not bridge the seam.
2. **Geometry:** source normalized point ([0,1], top-left), canvas/output transforms through `CineoScenePlan.evaluate` only; respect crop, padding, secondary display and Retina scaling. Do not infer target coordinates from screen frame dimensions.
3. **Determinism:** `scene.evaluate(t)` and `cursor.evaluate(t)` must return the same output after random seeks as during sequential playback. Spring effects should be precomputed to deterministic curves/keyframes or analytically evaluated from segment boundary conditions, not depend on mutable render history.
4. **No double cursor:** native `showsCursor=true` means embedded-pointer legacy mode. Overlay pointer is available only for newly captured pointer-hidden recordings with explicit movement telemetry and user opt-in.
5. **Privacy:** no keystroke values, text, window titles or captured accessibility contents. Cursor event collection starts/stops with capture. Audio and Accessibility permissions remain separate.
6. **Compatibility:** legacy `pointer-events.json` schema 1 and `scene.json` must decode unchanged, with no enabled motion by default.
7. **Reliability:** edits non-destructive, transactionally persisted, undoable; no new GPU renderer, no second timeline model; canceled/failed export cannot corrupt source/project.

## Workstreams and concrete PRs

### Track C0 — Contracts & tests (first, shared)
- Define exact output/source time semantic names, cursor sidecar v2 compatibility, interpolation and motion profile behavior, timeline region edit commands.
- Add fixtures for discontinuous cut, click hotspot, seek-order determinism, 16:9/9:16, 0 click, dense clicks and old project decode.
- Keep additive APIs where possible: avoid conflicts among module owners.
- Gate: unit tests with synthetic fixtures and CI paths documented; existing CameraPlanner and `CineoCutList` tests unchanged.

### Track C1 — Cursor Engine (parallel after C0; owns `CineoEvents` and `CineoCursor`)
- Phase C1a: add independent pure-Swift sample normalization, frame-time interpolation, bounded motion segment handling, discontinuity/no-telemetry safety and click-anchor exactness. New v2 sidecar only after migration tests.
- Phase C1b: app capture: opt-in `mouseMoved`/timed sampling, first video PTS anchoring, pause/resume and stop handling; optional capture with `showsCursor=false`; track source cursor mode to suppress duplicate pointer.
- Phase C1c: Core Image overlay composed in `CineoSceneFrameRenderer`, hotspot-aware image states, snap-to-click smoothing, bounce and optional idle fade. No cursor artworks from Recordly.
- Acceptance: click rendered at target with <= 1 output pixel geometry error in synthetic test, no second cursor, determinism after seeks, bounded memory with 15-min capture, pre-v2 project compatibility.
- Native gate: screen permission and cursor-hiding reality check on physical Mac.

### Track C2 — Cinematic Camera (parallel; owns `CineoScene` and camera-only `CineoDirector`)
- Phase C2a: stateless easing profiles (legacy smoothstep, fast focused, settled cinematic), clamped values, no NaN and backwards-compatible profile decoding. Evaluate at timestamp; prevent wall-clock driven export.
- Phase C2b: safe-zone cursor-follow in source frame space, hysteresis, hold on zoom-out, pan connection for adjacent compatible targets; all transitions are explicit reproducible camera keys.
- Phase C2c: augment shot ranking with result anchors only when evidence actually exists (manual/explicit event marker; do not fabricate semantic result from a click). Suppress excessive movement and preserve user-authored keyframes.
- Acceptance: seek-order equality, no crop overflow, no movement for stationary focus, reduced unwanted zooms in benchmark corpus, portrait crop respects focus.

### Track C3 — Timeline Studio (parallel pure model/UI; owns `CineoProject` + view-specific new files)
- Phase C3a: pure source/output clock and timeline edit utilities: pixel-to-time, time-to-pixel, snapping with threshold measured in screen pixels, drag/resize bounds, stable ordering and single undo history.
- Phase C3b: native SwiftUI multi-lane timeline (video filmstrip via AVAssetImageGenerator, zoom blocks, music waveform/cues); thumbnails cached with bounded count and cancellation.
- Phase C3c: shift `CineoManualEditor` to commands, drag/edit zoom regions, inspector with progressive disclosure. Break out oversized view-model. Tie cut ripple to all output-time tracks; remove pre-zoom cut restriction only after timing rebase is proven for music, video, click and scene keys.
- Acceptance: accurate scrub across cut seam, no synthetic gap, zoom block drag/resize and undo preserved on reopen, keyboard access, no lost edits and player->export parity.

### Track C4 — Integration/verification (serial, after C1–C3)
- Resolve ownership of `CineoScenePlan` / `CineoManualEditor` in one integration branch only; merge after focused track CI.
- Run on macOS Apple Silicon using `bash scripts/test-cineo.sh --preflight`, `--quick`, `--native`, targeted Swift tests, synthetic H.264 smoke and the real signed `--interactive` app. Never claim Mac execution without run artifacts.
- Three 30-90s scenarios: no click, dense settings/dashboard, form->waiting->result. Evaluate no-double-cursor, A/V sync, hold/readability, 16:9/9:16 and privacy/permission changes.
- Compare Cineo baseline vs enhanced pipeline on same input; record zooms/min, unwanted zoom count, edits-to-acceptable-video, seek vs linear frame parity, generated artifacts, peak RAM/CPU and export duration.
- Exit gate: source SHA unchanged after cut/export/cancel, old project loads, manual edits survive re-autoedit, audio remains aligned and release checklist explicitly completed.

## Sequencing / parallel ownership

```
C0 contracts + fixtures
  |--> C1 pointer normalization / capture / compositor overlay ----|
  |--> C2 camera curve + follow + shot-ranker ----------------------|--> C4 full editor integration + Mac E2E
  |--> C3 timeline model + SwiftUI native timeline ----------------|
```

All feature branches start at this plan branch, not at main; PRs target this plan branch and remain **draft** until tests and review pass. No auto-merge. Integrate via one owner to prevent simultaneous edits to `CineoManualEditor.swift` or `CineoSceneFrameRenderer.swift`.

## Initial development slices in this iteration

- **C1a:** pure-Swift pointer-trajectory evaluator and tests, no capture toggle yet.
- **C2a:** timestamp-pure camera easing evaluator and tests, without replacing legacy smoothing.
- **C3a:** timeline geometry/snapping core and tests, no UI toggle yet.

These are functional foundations, **not** claims that cursor overlay or multi-lane editor are already shipped.

## Test commands

```bash
swift test --package-path Packages/CineoEvents
swift test --package-path Packages/CineoScene
swift test --package-path Packages/CineoProject
swift test --package-path Packages/CineoDirector
bash scripts/test-cineo.sh --quick
bash scripts/test-cineo.sh --native
```

Linux is suitable only for the pure Swift packages; ScreenCaptureKit, AppKit/CoreImage and physical macOS UX need a macOS runner. Track PRs must report command results and outstanding gates.

## Risk log

| Risk | Mitigation |
| --- | --- |
| Recordly AGPL contamination | Independent design; no upstream source/assets copied; attribution to research only |
| Cursor double rendering | Explicit embedded vs independent cursor mode; opt-in pointer hiding only for new captures |
| Spring non-determinism | Analytical/time-indexed curves, random-seek parity fixtures |
| Cut/audio/keyframe drift | One output->source clock mapping and transactionally rebased edits |
| Scope/UI complexity | Pure models first, progressive disclosure, no Electron/PixiJS |
| Performance on 4K | Bounded sampling/cache and off-main-thread video work |
| Stale docs vs code | Pin PR #72 as starting base; do not confuse unmerged changes with main |

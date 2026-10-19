# Cineo — Proposed native architecture

**Status:** target architecture / ADR candidate; not an implementation report. Confirm during P0 against the chosen native upstream.

## Direction

Build a **true native macOS app** using Swift, SwiftUI + AppKit and Apple media frameworks. Reuse a single upstream as the application foundation (Orbit is the leading candidate) and borrow other source only after provenance, compatibility, licensing and measured quality reviews.

**Target compatibility:** Apple Silicon + macOS 15.2 or newer **provisional**, aligned with Orbit's published requirement; decide official minimum after P0. Avoid accidental upgrades to a higher deployment target without an explicit product decision.

## Logical ownership

| Boundary | Responsibilities | Dependencies |
| --- | --- | --- |
| AppShell | Window lifecycle, menu bar, permissions UX, settings, shortcuts | Native views + service protocols |
| CaptureCore | Screen/window stream, optional audio, session lifecycle, crash-safe source | ScreenCaptureKit, AVFoundation |
| InputTelemetry | Time-coded pointer/click/scroll markers, opt-in and filtering | Event taps/OS capabilities; no text capture |
| ProjectCore | Immutable source references, versioned edit graph, autosave/migrations | File coordination, durable storage |
| TimelineCore | Edit operations, time mapping, undo/redo, lane model | ProjectCore only |
| CameraCore | Focus targets, zoom/pan, smoothing, easing, constraints | TimelineCore + geometry |
| DirectorCore | Suggestion planning, grouping, rule-based storyboards | Event sidecar + semantic hints |
| ComposeCore | Single render-time scene evaluator for media, cursor, titles, backgrounds | Geometry/timebase + output pipeline |
| ExportCore | Codec, output destination, deterministic frame evaluation, progress | AVFoundation / chosen compositor |
| StudioUI | Capture, Auto Edit, Studio, export, inspector | Application view models |
| Later Automation | Versioned CLI and scripted web capture | Same project/edit/render APIs |

**One composition contract** is mandatory. Do not merge an OpenScreen renderer, a CineScreen Metal renderer and an Orbit Core Image renderer into the same first release. Use measured evidence to choose or replace exactly one.

## Conceptual data flow

~~~text
ScreenCaptureKit + (optional mic/system audio)
                   |
           Source media + PTS
                   |
 Event telemetry -> Timebase adapter -> Project package
                                             |
                                   Rule-based Director
                                             |
                                   Suggested edit graph
                                             |
       User edit operations -> Versioned timeline & camera graph
                                             |
                                  Scene evaluator at time t
                                       /             \
                               Interactive preview   Offline exporter
                                       \             /
                                 Same coordinates and rules
~~~

## Versioned project model (illustrative, not a finalized schema)

~~~text
CineoProject
  schemaVersion
  projectID
  mediaSources[]          # file/ bookmark, media dimensions, PTS and color
  audioSources[]          # track identity, offset and channel metadata
  eventSources[]          # time-coded pointer, click, scroll; opt-in
  canvas                 # output aspect ratio, dimensions, background, safe regions
  sourceEdits[]           # trim/cut/speed mapping from output time to source PTS
  cameraTracks[]          # zoom, pan, focal target, interpolation and override origin
  overlayTracks[]         # cursor, spotlight, callouts, text
  exportPresets[]
  provenance[]            # upstream data and migration versions
~~~

Persist with atomic writes into a project package (candidate extension: .cineo), retain source media immutably and use relative references/security-scoped bookmarks where appropriate. Temporary intermediates must be removable without damaging source or edit graph. Every edit command is reversible and serializable. A migration test fixture is required from the first persisted schema version.

## Geometry invariants

All coordinates are expressed with an explicit named space:
- **Display/global space:** macOS point coordinates and display origin.
- **Source pixel space:** actual captured frame pixels and crop.
- **Scene/canvas space:** composition position after padding, crop and camera.
- **Output pixel space:** final export resolution / aspect ratio.

Transforms between spaces must be explicit and testable (including scale, y-axis convention, display origin, window change and Retina scaling). A cursor click must remain aligned to the visual click target through crop, pan, zoom and aspect-ratio change. Camera framing constraints keep focal regions visible, with a fallback when they cannot fit.

## Timing invariants

- Canonical media timebase is source presentation timestamps, not Date()/wall-clock.
- Convert input event clock to source time via a measured mapping; detect drift and resynchronization gaps.
- Model scene-to-source time mapping for trims, speed changes and pause/resume. Cursor, audio, masks and callouts evaluate in the same mapped timeline.
- Export is frame-index driven at chosen timebase; source interpolation/drop handling must be deterministic and documented.
- Preview and export consume the **same scene evaluator**, while GPU rendering may use separate optimized transports only if parity tests pass.

## Renderer strategy

**Baseline:** keep the chosen upstream's working renderer; benchmark 1080p and 4K 30/60 fps on representative Apple Silicon hosts. Check color conversions, HDR/SDR, alpha, text sharpness, cached frames and memory.

**Contingency:** replace a compositor only if critical parity/performance requirements repeatedly fail and a proof-of-concept with CineScreen's Metal approach demonstrates a measurable gain. Reusing its design is not permission to paste unchecked cross-project code. Document a separate ADR before any rendering replacement.

Never encode off-screen frames through UI screenshots; compose from underlying media and vector overlays. Keep expensive image analysis out of the live capture callback.

## Smart camera algorithm (first version)

1. Normalize/correct event positions into source pixel space.
2. Identify time windows containing relevant interactions; merge nearby clicks/dwell and preserve idle spans.
3. Apply suppression: repeated clicks, incidental motion, already-visible focus, micro-spans, and near-duplicate targets.
4. Generate candidate scenes (wide → focus → hold → release) with clear reason codes.
5. Solve target rectangle and output crop with margin and limits. Interpolate position and zoom smoothly, with no jump at clip boundaries.
6. Produce editable keyframes in a **suggestion layer**. Respect manual overrides.
7. Render and validate target visibility, frequency and safe regions.

The MVP is deterministic and works offline without language models. Semantic meaning is limited when telemetry has no reliable target identity; tell the user rather than pretending to know results.

## Optional semantic anchors (post-MVP)

- Manual selection: always available and trustworthy.
- Browser DOM bounding rectangle: opt-in instrumented workflows; DOM IDs cannot be assumed stable, record fallback coordinates.
- macOS accessibility: explicit permission, ephemeral element recognition and confidence metadata, opt-in.
- On-device vision/LLM: optional, bounded in memory and model loading; suggested insights never override manual editing or become necessary for basic capture/export.

## Concurrency and resource budgets

Capture must never block on AI inference or expensive image transforms. Use separate bounded queues/tasks for capture, telemetry, autosave, scene generation, preview and export. Cancellation propagates, temporary file cleanup is enforced, and memory must not grow linearly with recording length. Export is allowed to be slower than real time but may not monopolize the UI event loop.

## Privacy/security model

No mandatory remote backend or account. Request Screen Recording only when recording; microphone/camera only when enabled; Accessibility separately when an advanced feature needs it. Capture raw screen pixels only within explicit user selection and show the active state. No typed text in sidecars, no raw user content or file paths in logs, no hidden uploads. Recordings remain in user-controlled local storage; opt-in features state exactly what they inspect.

## Testing boundaries

- Pure logic: time mapping, zoom grouping, pan constraints, edit operations, schema migrations.
- Golden frames: scene evaluator at representative timestamps, resolutions, Retina scale factors and aspect ratios.
- Native integration: permissions, screen/audio capture, project save/reopen, export.
- App E2E: capture → automatic demo → correction → 16:9 and 9:16 export, with continuous video evidence.
- Negative cases: revoked permissions, wrong clock, missing media, display disconnect, cancellation, full disk, failed export.

See [upstream evaluation](upstream-evaluation.md), [quality](quality.md) and [roadmap](roadmap.md).

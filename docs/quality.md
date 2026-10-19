# Cineo — Quality bar and verification plan

**Status:** proposed gates and targets; no Cineo build, Mac capture or export has yet been validated.  
**Principle:** shipping an app is not proof that it makes clearer product demos.

## Quality dimensions

| Dimension | Measurement | Proposed gate |
| --- | --- | --- |
| Correctness | Readable output, source fidelity, no incorrect zoom target | No severe framing or timebase defects in canonical clips |
| Preview/export parity | Same evaluated frame transform, cursor and annotations | Golden-frame geometry agreement within defined tolerance |
| Audio/video synchronization | Spoken cue vs visual click across full clip | Determine threshold from baseline, aim <= 100 ms at 10 min |
| Readability | Text/controls readable at intended viewing size | All key actions/results legible on desktop and smartphone review |
| Performance | Capture dropped frames, export throughput, memory behavior | No uncontrolled linear memory growth; establish host baselines |
| Reliability | Successful recovery from interrupted save/export | Original media preserved, error actionable |
| Privacy | No upload on baseline flow, no typed-text telemetry | Tested and documented; logs sanitized |
| UX | Time, corrections and confidence to first publishable video | Instrument test sessions locally without mandatory analytics |
| Accessibility | Keyboard paths, VoiceOver, contrast, reduced motion | Critical actions usable with native accessibility |

**Proposed product hypotheses:** <= 5 min median from completed short recording to first usable export; >= 70% first cuts accepted as understandable after only minor adjustment. These are test targets to calibrate, not observed results.

## Benchmark matrix

**Hosts:** primary Apple Silicon Mac with recorded CPU/GPU/RAM and macOS/Xcode versions; add lower-memory Mac before broad claims.  
**Clips:** 1080p30, 1080p60, 4K30, 4K60 where supported. Include 30 s, 2 min and 20 min samples.  
**Content:** dense dashboard, narrow dialog, scrolling form, native app, dual-display/Retina, silent clip, noisy cursor, minimal/no-click flow.  
**Outputs:** 16:9 and 9:16 H.264; additional codecs only when implemented.  
**Baseline comparisons:** raw source, chosen upstream unmodified, Cineo Auto Edit and a manual reference edit.

Record the exact project, source fixture hash, render configuration, platform, toolchain version and output hash for each run. Distinguish quality-review scores from deterministic execution metrics.

## Required tests by layer

**Unit (fast):** coordinate transforms, easing continuity, click clustering, merge/suppress logic, timeline mapping, project schema, migration, sanitization.

**Component/integration:** ScreenCaptureKit callback lifecycle; audio drift and frame PTS; cursor sidecar decoding; save/reopen; preview scene parity; export cancellation and temporary-file cleanup; permissions.

**Golden-frame:** same project at known frame indices across 1x and Retina scale, at 16:9 and 9:16, with corner targets, text overlays, cursor and dim regions. Numeric pixel tolerances should be calibrated for encoder and color-space differences; compare source composition before lossy encode when feasible.

**Native E2E:** capture → edit → export → inspect at least three real flows, recording screenshots plus continuous demonstration video when meaningful. Hardware-dependent release proof runs on a real Mac.

**Stress/failure:** 20–30 min take, limited disk, no mic, unplugged audio, source window disappearing, quit during export, project migration and malformed metadata.

## Acceptance gates by milestone

| Gate | When | Required evidence |
| --- | --- | --- |
| G0 — choose upstream | End P0 | Source/rights audit, green native build, comparable exported clips and decision |
| G1 — stable native shell | End P1 | Open/record/stop/save/reopen on Mac; permission flows |
| G2 — deterministic editor | End P2 | Unit + golden-frame parity, undo/redo and crash-safe project |
| G3 — publishable MVP | End P3 | 3 end-to-end product demos (native, SaaS, dense UI) in 16:9/9:16 |
| G4 — polished Studio | End P4 | Keyframes/spotlight/callouts and automated export/UX regression |
| G5 — automation/release | P5+ | Signed/notarized update path, clean uninstall, compatibility and consent |

## Observability and privacy

Default diagnostics are local and do not contain raw media, keystrokes, transcripts, secret tokens or absolute user paths. A troubleshooting bundle must be opt-in, scoped, inspectable and redacted. Error messages are actionable; never silently drop frames/track audio and claim success.

## Definition of Done

A task is complete only when:
- an observable user/system contract is demonstrated, not merely a class added;
- owner-level tests are green and the critical changed journey is exercised;
- failure/permission/cancellation states are handled where relevant;
- source media survives edit/export failures;
- important visual changes have inspectable screenshot/video evidence;
- docs match integrated behaviour, with unsupported claims marked as future;
- external dependencies and attribution are reviewed.

Keep iteration feedback lean; use stronger complete-journey gates at integration, and real-Mac/notarized distributable tests for release.

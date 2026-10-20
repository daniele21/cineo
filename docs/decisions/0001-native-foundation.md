# ADR-0001 — Native Cineo foundation

- **Date:** 2026-10-20
- **Decision:** ACCEPTED for **P1 prototype/bootstrap**, NOT production or release approval.
- **Scope:** P0 architecture and upstream selection decision.
- **Owner:** Cineo.
- **Primary upstream pin:** [diip3sh/orbit @ 219c4c8](https://github.com/diip3sh/orbit/tree/219c4c8ad9965229aa84271c5201b1b8ad26eb7a).

## Problem

Cineo needs a truly native Mac capture → cinematic edit → export workflow, with an editable cursor, restrained camera movement and privacy-preserving local operation. Adopting unrelated renderers or rewriting capture/timeline prematurely creates high integration risk.

## Considered options

| Candidate | Evidence | Trade-off |
| --- | --- | --- |
| **Orbit** (selected P1 source) | Native Swift/SwiftUI, code-level audit of InputTelemetry, AutoZoomGenerator, FrameRenderer, EditorCompositor; Xcode 26.6 native compile PASS | Broad scope (library, web/agent and Motion); signing/TCC, live capture, real exports and asset rights still need testing |
| CineScreen | SwiftUI+Metal project; native compile PASS | Dedicated renderer/time model not interchangeable; 2026 Xcode logs contain export-related concurrency warnings |
| BetterCapture | Narrower, native capture code; native compile PASS | Missing equally mature full cinematic editing integration |
| New blank Swift app | Total ownership | Highest delay/risk: capture, audio and renderer/timeline would need recreation |

**Source audit:** [P0 source study](../research/p0-source-audit.md).  
**Compile evidence:** [P0 native build matrix](../research/p0-native-build-results.md), successful [CI run 39352150386](https://github.com/daniele21/cineo/actions/runs/39352150386) on macOS 26/Xcode 26.6 (three independent Debug builds, `CODE_SIGNING_ALLOWED=NO`).

## Decision

**Select Orbit as a controlled, single-source native foundation for P1.** Begin with an exact-SHA out-of-tree staging bootstrap, not a wholesale merge of its repository into Cineo. Compile a Cineo-named, uniquely identified macOS staging bundle and preserve MIT attribution. Keep the existing Orbit editor compositor as sole renderer while evaluating it, and the original `Packages/CineoDirector` as an isolated experimental model (not integrated yet).

- Use a conservative brand/security overlay before compiling. Reset the stage to the immutable pinned source for each build; refuse drift rather than silently patching another upstream revision.
- Do not activate upstream's Sparkle release feed, local agent bridge, Reco URL scheme or legacy container migration in a Cineo app.
- Do not copy CineScreen/ArcShot/AGPL-derived source or merge competing timeline engines.
- Plan to migrate only the approved native code into a managed Cineo fork **after** signed-launch and real-video verification.

**License note:** the upstream root `LICENSE` is MIT and must be retained with copied substantial source; its bundled fonts, icon artwork, third-party packages and update/branding obligations need a distinct redistribution review. Disable Orbit-branded app icon in the bootstrap; remaining user-facing Orbit/Reco strings are known prototype limitations.

## P0 closure interpretation and exceptions

The original P0 roadmap required signed real-Mac capture and visual 16:9/9:16 exports **before any foundation commitment**. That evidence is **not available**: GitHub-hosted macOS CI compiled unsigned targets and cannot establish interactive Screen Recording (TCC) approval or reliable live capture.

In order to proceed with the user's requested next milestone while making the limitations visible, **the selection decision is closed as a conditional P1 experiment only**, and the missing validation is elevated to a **mandatory P1 gate**, not considered passed:

1. **P1-GATE-A:** signed/installed local Cineo staging app starts under its own bundle ID and requests only legitimate permissions.
2. **P1-GATE-B:** real screen/window capture and optional audio actually save an inspectable source video; stop/cancel/permission denial behave correctly.
3. **P1-GATE-C:** open recording in upstream editor, preview and export one real 16:9 and 9:16 video, verify cursor framing and audio sync.
4. **P1-GATE-D:** full third-party font/image/icon/dependency/license provenance and replacement/disabling of remaining upstream brand/paths before any external distribution.
5. **P1-GATE-E:** record resource/capture stability and no-data-loss evidence on target hardware, including a failure case.

**Do not call P1, the app, or its recording functionality validated until these pass.** If any hard gate fails, stop adopting Orbit and reopen the foundation decision; compare CineScreen and BetterCapture on the same scenario.

## Immediate consequences

- Positive: code reuse and compile feasibility; one source capture/editor stack and a safe place to iterate on custom cinematic UX.
- Negative: broad fork maintenance, branding refactor, untested interactive/macOS permissions, no production-ready app from CI alone.
- Not yet decided: ownership/license of final Cineo distribution; whether to bring all Orbit code into the repository, how to reduce unused web/motion agent features; whether Composer should remain Core Image long-term.
- Next output: reproducible local/CI bootstrap scripts and a P1 checklist with explicit human interactive smoke gate.

## Why conditional P0 closure is valid — and what is not valid

This ADR is the **foundation selection artifact**, not a false claim that the original research-stage media-quality benchmark was executed. It intentionally changes the execution order: selection is reversible, and the costly/permission-based test becomes a blocker for going past the P1 experimental integration. If this trade-off is not acceptable, retain P0 as open until a real Mac session is run.

Related issues: [#1](https://github.com/daniele21/cineo/issues/1), [#2](https://github.com/daniele21/cineo/issues/2), [#3](https://github.com/daniele21/cineo/issues/3), [#10](https://github.com/daniele21/cineo/issues/10).

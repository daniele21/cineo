# P0 code-level native upstream audit — first pass

**Updated:** 2026-10-20. **Stage:** source inspection complete for selected high-value modules; Mac compilation, instrumented recordings and export benchmarks **not executed**. This document does not authorize importing any upstream code.

## Pinned inspection references

The following commit IDs were discovered in GitHub's indexed source references and confirmed resolvable as commits. They are **inspection pins**, not yet verified build snapshots or immutable release selections.

| Candidate | Inspected commit | License file inspected | Operating requirements from README |
| --- | --- | --- | --- |
| Orbit | [219c4c8](https://github.com/diip3sh/orbit/tree/219c4c8ad9965229aa84271c5201b1b8ad26eb7a) | [MIT](https://github.com/diip3sh/orbit/blob/main/LICENSE), copyright Joshua Sattler | macOS >= 15.2, Apple Silicon, Xcode 26; development signing required |
| CineScreen | [ff4764b](https://github.com/jasonzh0/CineScreen/tree/ff4764b9ca50c6424f6746a05d7aff2abb70444b) | [MIT](https://github.com/jasonzh0/CineScreen/blob/main/LICENSE), copyright Jason Zhang | macOS >= 14, Xcode 15+, XcodeGen, Metal pipeline |
| BetterCapture | [ab852b4](https://github.com/jsattler/BetterCapture/tree/ab852b44c4dd09c8e2ae69e7858a1b67e1cd17af) | [MIT](https://github.com/jsattler/BetterCapture/blob/main/LICENSE), copyright Joshua Sattler | macOS >= 15.2, native Swift/ScreenCaptureKit |

Recheck HEAD/tag and dependency lockfiles immediately before forking. MIT source licenses do not automatically grant rights to all fonts/images/trademarks bundled in repositories.

## Actual code locations reviewed

### Orbit — most complete native product/editor candidate

| Function | Source | What was observed |
| --- | --- | --- |
| Telemetry representation | [Reco/Model/InputTelemetry.swift](https://github.com/diip3sh/orbit/blob/219c4c8ad9965229aa84271c5201b1b8ad26eb7a/Reco/Model/InputTelemetry.swift) | Codable versioned sidecar (v3, supports v2–v3), capture kind, geometry changes, cursor positions/clicks/scroll/keys, cursor sprites/shapes |
| Automatic zoom | [Reco/Editor/Service/AutoZoomGenerator.swift](https://github.com/diip3sh/orbit/blob/219c4c8ad9965229aa84271c5201b1b8ad26eb7a/Reco/Editor/Service/AutoZoomGenerator.swift) | Pure rule generator. Config includes zoom scale=2, event gap=2s, lead=0.5s, hold=1.5s, clustering, rest and circling detection; compare these defaults with Cineo's quieter desired look |
| Shared rendering | [Reco/Editor/Render/FrameRenderer.swift](https://github.com/diip3sh/orbit/blob/219c4c8ad9965229aa84271c5201b1b8ad26eb7a/Reco/Editor/Render/FrameRenderer.swift) | CIImage/CoreVideo per-time renderer for frame, click, cursor, camera, backdrop |
| AVFoundation compositor | [Reco/Editor/Render/EditorCompositor.swift](https://github.com/diip3sh/orbit/blob/219c4c8ad9965229aa84271c5201b1b8ad26eb7a/Reco/Editor/Render/EditorCompositor.swift) | AVVideoCompositing delegates frame composition to FrameRenderer for preview and export; shared CIContext and stateless request plan |
| Motion film rendering | [Reco/Motion/Render/MotionFrameRenderer.swift](https://github.com/diip3sh/orbit/blob/219c4c8ad9965229aa84271c5201b1b8ad26eb7a/Reco/Motion/Render/MotionFrameRenderer.swift) | Separate frame renderer for layered motion compositions, blur sampling and 3D plane projections; **not a unified editor renderer** |
| Sample tests | [RecoTests/WebTakeZoomsTests.swift](https://github.com/diip3sh/orbit/blob/219c4c8ad9965229aa84271c5201b1b8ad26eb7a/RecoTests/WebTakeZoomsTests.swift) | Source includes geometric zoom focus tests, viewport clipping and nearby zoom transitions |

**Notable engineering risks:**
- Orbit is a **wide fork** with capture + screenshot manager + web recording + local MCP/agent tooling + motion/films. Cineo is intentionally narrower; adopt only if lifecycle/build complexity is tolerable.
- The source documentation [CLAUDE.md](https://github.com/diip3sh/orbit/blob/main/CLAUDE.md) describes project-specific signing/TCC traps, concurrency/runtime crashes, Xcode/Metal toolchain constraints and release automation. These demand a clean Cineo bundle ID/signing strategy before copying app settings.
- The same document contains time-varying or conflicting advice about transient tests (e.g. removed tests versus currently indexed test files). **Verify actual test target/CI, never trust a blanket claim that all tests are retained or absent.**
- Motion and standard Editor appear to have different composition model/renderers; do **not** promise a unified product-film timeline in MVP.
- Default zoom 2x may be visually aggressive for dense UI. First compare against a restrained 1.3–1.6x Cineo preset without changing upstream internals.

### CineScreen — independent GPU/composition comparison

| Function | Source / proof | What was observed |
| --- | --- | --- |
| Render-pass ownership | [CineScreen/Compositor/FrameCompositor.swift](https://github.com/jasonzh0/CineScreen/blob/ff4764b9ca50c6424f6746a05d7aff2abb70444b/CineScreen/Compositor/FrameCompositor.swift) | Dedicated compositor; independent Metal pipeline, **not directly swappable** with AVVideoCompositing |
| Timeline and mapping | [CineScreen/Models/EditTimeline.swift](https://github.com/jasonzh0/CineScreen/blob/ff4764b9ca50c6424f6746a05d7aff2abb70444b/CineScreen/Models/EditTimeline.swift) | Dedicated edit/time mapping model |
| Camera/cursor state | [CineScreen/Editor/RenderSnapshot.swift](https://github.com/jasonzh0/CineScreen/blob/ff4764b9ca50c6424f6746a05d7aff2abb70444b/CineScreen/Editor/RenderSnapshot.swift) | Deterministic trajectory data model with dedicated audit harness |
| Actual app audit | [docs/SCREEN_STUDIO_AUDIT.md](https://github.com/jasonzh0/CineScreen/blob/main/docs/SCREEN_STUDIO_AUDIT.md) | Authors report partial automatic zoom/cursor parity, known motion defects and historical missing Metal toolchain for native tests |
| Maintenance remediation | [docs/MAINTAINABILITY.md](https://github.com/jasonzh0/CineScreen/blob/main/docs/MAINTAINABILITY.md) | GPU binding lifetime, single composition-state snapshot, single render-pass owner, bounded editor history; good checklist for Cineo |

**Risk:** CineScreen is compelling for preview/export correctness and a leaner editor, but its source and upstream audit show nontrivial toolchain/render resource issues. Do not transplant the compositor into Orbit before A/B measurement.

### BetterCapture — stable capture fallback

[BetterCapture/Service/AssetWriter.swift](https://github.com/jsattler/BetterCapture/blob/ab852b44c4dd09c8e2ae69e7858a1b67e1cd17af/BetterCapture/Service/AssetWriter.swift) has a distinct AVAssetWriter capture owner. Code normalizes frame presentation to a constant-rate grid, can duplicate previous frames across capture gaps with explicit upper bound, rebases audio against the first sample and tracks video writer drainage. This is valuable capture/audio lifecycle design even if Cineo adopts Orbit.

BetterCapture lacks Orbit's integrated cinematic editor in its published README, making it an attractive **fallback** if the bigger Orbit fork proves too brittle.

## First-pass recommendation

**Provisional: Orbit is the primary benchmark target; CineScreen is renderer comparison; BetterCapture is capture fallback.**

This is now supported by concrete source pathways, but **not yet by verified native execution**. Do not fork Orbit into Cineo's main without Mac benchmark. Native P0 is the blocking decision.

### Reuse versus reimplement

| Requirement | Initial strategy |
| --- | --- |
| Screen/window capture and system/mic audio | Reuse selected upstream complete capture lifecycle |
| Sidecar clock + coordinate mapping | Prefer Orbit implementation; preserve versioned import/migration |
| Original click/rest zoom suggestions | Compare with Orbit's AutoZoomGenerator; don't duplicate it unless quality evidence warrants |
| Semantic result-aware selection | New Cineo DirectorCore and manual anchors; isolated Swift spike can test planner before integration |
| Scene-to-pixel rendering | Keep one upstream renderer; parity tests before any replacement |
| Motion design / product films | Later capability, separate pilot only |
| External agent recording | Optional after MVP, not a blocking dependency |

## Next P0 tasks (not completed)

1. On Mac, run **Xcode build/test** for exactly pinned commits with developer signing. Capture full logs and selected Xcode version.
2. Run same 90s native app and browser dashboard sequence in Orbit/CineScreen; BetterCapture for raw capture quality, with hardware/OS specs noted.
3. Compare fixed 1080p/4K and 16:9/9:16 exports, audio drift, cursor geometry and cancellations; preserve media evidence.
4. Audit third-party package locks, asset licenses and bundled font/image rights, then publish a formal ADR.
5. Scope first Cineo fork and choose whether to maintain or remove screenshots/agent tooling. No wholesale copying before this gate.

## Evidence ledger

- **Verified from fetched source:** exact named files/algorithms/structs above.
- **Verified from upstream license text:** three candidate root license files are MIT.
- **Not verified here:** upstream macOS app compilation, telemetry capture live, export quality, benchmark performance, source code redistribution clearance of all dependencies, notarization.
- **Local Cineo code independent of upstream:** `Packages/CineoDirector` is a proposed separate experiment, not part of this audit branch.

For full acceptance see [upstream evaluation](../upstream-evaluation.md), [quality](../quality.md) and [roadmap](../roadmap.md).

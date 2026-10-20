# P0 native upstream compilation — verified baseline

**Recorded:** 2026-10-20  
**Evidence:** [GitHub Actions run #39351683676](https://github.com/daniele21/cineo/actions/runs/39351683676)  
**Source:** PR [#18](https://github.com/daniele21/cineo/pull/18) at `7f5a7144aab213440418fd574060abd7be437e2d`  
**Scope:** compile native upstream projects only; no Cineo app, signed launch, TCC screen recording, capture, editing or media-export benchmark.

## CI root cause fixed

The previous runs appeared as workflow-file validation failures with **zero jobs** (for example [run #39334794217](https://github.com/daniele21/cineo/actions/runs/39334794217)). The workflow referenced `${{ runner.temp }}` in `jobs.native-upstream-build.env`, where the `runner` context is not valid. In PR #18 that value now lives in `steps.env`, and the artifact path uses `runner.temp` in `steps.with`, where it is valid. A new **three-job** matrix was created and completed successfully.

## Reproducible build results

| Candidate | Source SHA | Runner/toolchain | Scheme | Result | Build log artifact |
| --- | --- | --- | --- | --- | --- |
| [Orbit](https://github.com/diip3sh/orbit) | `219c4c8ad9965229aa84271c5201b1b8ad26eb7a` | macOS 26, Apple Silicon, Xcode 26.6, Swift 6.3.3 | `Reco` | **BUILD SUCCEEDED** | [p0-orbit-build-logs](https://github.com/daniele21/cineo/actions/runs/39351683676) |
| [CineScreen](https://github.com/jasonzh0/CineScreen) | `ff4764b9ca50c6424f6746a05d7aff2abb70444b` | same | `CineScreen` | **BUILD SUCCEEDED** | [p0-cinescreen-build-logs](https://github.com/daniele21/cineo/actions/runs/39351683676) |
| [BetterCapture](https://github.com/jsattler/BetterCapture) | `ab852b44c4dd09c8e2ae69e7858a1b67e1cd17af` | same | `BetterCapture` | **BUILD SUCCEEDED** | [p0-bettercapture-build-logs](https://github.com/daniele21/cineo/actions/runs/39351683676) |

Each job invoked `bash scripts/benchmark-upstreams.sh --run <candidate>`. The script fetched a pinned commit, listed available Xcode schemes and executed `xcodebuild -project <project> -scheme <scheme> -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`. Xcode and package resolution were performed on GitHub-hosted macOS runners.

**Artifacts are temporary** (the run reported expiry on 2026-10-27). For durable evidence, preserve the source pins, job/run IDs and this summary; re-execute the matrix for new upstream pins or after significant changes.

## Warnings and caveats

- **Orbit:** its large native target compiled successfully. The compilation log has very few warnings in this run, but this is not evidence the app is smaller, faster or more stable. It includes more scope than Cineo needs (web recording / motion composition / agent tooling).
- **CineScreen:** successfully compiled, but the compiler emitted numerous warnings, including Swift concurrency Sendable and captured non-Sendable AVFoundation/ImageIO objects in `ExportPipeline.swift`. Several are explicitly reported as becoming errors in Swift 6 language mode. These require triage before selecting this renderer.
- **BetterCapture:** the capture-oriented project compiled successfully but has no demonstrated Cineo-style timeline/editing experience in this benchmark.
- All builds used **CODE_SIGNING_ALLOWED=NO**. Thus permissions, microphone/system audio routing, real capture, cursor timing, application launch, AVC capture fidelity, native media editing and AVAssetWriter/export correctness remain **unverified**.
- Different source trees and dependencies make wall-clock build times **not directly comparable** as an app runtime or rendering benchmark.
- A root MIT license does not eliminate third-party package/asset and trademark obligations.

## Decision

**Compile feasibility gate: PASSED for all three pinned candidates.**  
**Whole-app foundation decision: NOT YET APPROVED.**

Orbit remains the leading functional benchmark candidate because the source audit found capture, cursor events, zoom generator, timeline/compositor and product-motion modules in a single Swift-native project. Before choosing it as Cineo's fork:

1. Run signed, installed builds on a **real Mac**, with meaningful TCC Screen Recording and audio permission checks; do not equate an unsigned CI build with a functioning recorder.
2. Capture equal native app and browser sequences in Orbit and CineScreen; use BetterCapture as capture reference.
3. Exercise an actual edit and export, inspect 16:9/9:16 video and verify preview/export framing and cursor/audio synchronization.
4. Audit bundled assets/third-party licenses at these pinned SHAs.
5. Record the final ADR and only then move editor/capture implementation into Cineo.

## Next concrete test design

Create test fixtures of a 90-second browser demo with dense sidebar/click bursts and a native-app demo with menus/dialogs, plus a no-click control. Preserve original capture, event metadata, short rendered output, screenshots at designated timestamps and a machine-readable run manifest (host specs, Xcode, SHA, export geometry and errors). Test on a target Apple Silicon Mac; separate real permission-based tests from automated renderer-only fixture tests.

Do not close issue [#1](https://github.com/daniele21/cineo/issues/1) or [#10](https://github.com/daniele21/cineo/issues/10) merely because compilation succeeded.

Related: [static code audit](p0-source-audit.md), [upstream evaluation](../upstream-evaluation.md), [quality gates](../quality.md).

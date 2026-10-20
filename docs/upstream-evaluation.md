# Cineo — Native upstream adoption decision

**Status:** research shortlist, not an approved copy/fork decision.  
**Research date:** 2026-10-19.  
**Evidence classification:** public README = upstream claim; source audit = implementation evidence; local build + test/export artifact = validated for Cineo.

## Updated reference study — 2026-10-20

The original upstream shortlist has been expanded by a **source-level audit of 13+ repositories**, including mature continued [OpenScreen](https://github.com/getopenscreen/openscreen), headless `screenstudio-alt`, Auto-Editor, Cap, Recordly, Palmier Pro, Editly, Revideo and Remotion. See the [pinned-commit Auto Edit research and adoption matrix](research/auto-edit-upstream-2026-10.md), [parallel delivery plan](plans/auto-edit-parallel-delivery.md), and [CLT-only renderer experiment #48](https://github.com/daniele21/cineo/issues/48).

**Updated technical judgement:** Orbit's precomputed immutable `RenderPlan`/Core Image `FrameRenderer` is the strongest code-level reference for the current **SwiftPM/CLT-only** app, but the old benchmark built Orbit with **Xcode**, not CLT. CineScreen provides an elegant shared Metal GPU renderer; its `.metal` shader compilation may be impossible with standalone CLT, so use it only as a separate feasibility spike. OpenScreen offers an active MIT editor/CLI reference and uses the **same export pipeline for UI and CLI**, although it boots a hidden Electron renderer and is not a native Swift module. ArcShot is technically useful but its special license forbids App Store derivatives; Recordly/Cap are mostly AGPL and Palmier GPL. See the research table for exact licenses and file-level sources.

The user-provided 25-second final MP4 is evidence the new standalone Cineo ScreenCaptureKit recorder can finalize **one** session. It is **not** evidence that the older Orbit Xcode editor, its compositor, or any automatic/assisted post-production is integrated or validated. Preserve the distinction between prior Xcode-native prototype and current CLT-only app.

## Guardrail

**Do not mix repos by copying components opportunistically.** Select one primary native app foundation, preserve upstream attribution, and import additional code only when license, integration boundaries, upkeep and tests are documented. Use other repos freely as conceptual references; never treat a public GitHub project as automatically unrestricted.

## Candidate matrix

| Candidate | Public link | Strength | Constraints / status | Proposed role |
| --- | --- | --- | --- | --- |
| Orbit (diip3sh) | https://github.com/diip3sh/orbit | SwiftUI/AppKit, ScreenCaptureKit; README claims automatic zoom, cursor telemetry, timeline, canvas/export, scripted web recording, AI tooling | MIT per README; macOS >= 15.2, Apple Silicon; relatively small fork, no Cineo build done | **Leading whole-app fork candidate** |
| Orbit (YvanKOB fork) | https://github.com/YvanKOB/orbit | Alternative fork to compare changes/hardening | Relationship/current differences must be diffed, not assumed | Secondary audit |
| BetterCapture | https://github.com/jsattler/BetterCapture | Mature, native recording base, multiple codecs, system/mic audio, permissions, privacy, tests | MIT per README; less complete cinematic editor than Orbit | Capture fallback and maintenance reference |
| CineScreen | https://github.com/jasonzh0/CineScreen | Native SwiftUI + Metal compositor, offline AVAssetWriter export, zoom, cursor, backgrounds | MIT per README; smaller community; preview/export benchmark needed | **Renderer reference / fallback**, not automatic code import |
| OpenScreen | https://github.com/getopenscreen/openscreen | Mature editor/UX and CLI, helpful auto edit/camera concepts | MIT per project; Electron/Rust architecture, **not a native SwiftUI fork** | UX and algorithms/CLI design reference |
| ArcShot | https://github.com/mameshivaa/Arc-shot | Native editor, multiple lanes, detailed compositor testing | Special Mac App Store redistribution restriction claimed by project; legal review needed | **Study ideas only**, no code copy by default |

Other AGPL-licensed projects (including some screen recorder forks) are not default direct code donors to a potentially proprietary Cineo distribution. Check actual LICENSE files, bundled dependencies and asset rights at pinned commits before reusing any code. License statements above are upstream documentation, not legal clearance.

### Verification references

- Orbit public README: https://github.com/diip3sh/orbit
- BetterCapture README / LICENSE: https://github.com/jsattler/BetterCapture
- CineScreen README / LICENSE: https://github.com/jasonzh0/CineScreen
- OpenScreen README / LICENSE: https://github.com/getopenscreen/openscreen
- ArcShot licensing/distribution documents: https://github.com/mameshivaa/Arc-shot

Orbit also contains motion-editor documentation and proposed motion-design concepts; audit actual shipped source and execution separately. **Do not infer that a written proposal is production-complete code.**

## P0 code audit checklist

For Orbit and CineScreen (and BetterCapture as fallback):
1. Pin default branch **commit SHA**, release/tag, last significant update and dependency versions.
2. Verify LICENSE, copyright notices, third-party source, media assets, typography licenses, submodules and build scripts.
3. Build using recommended Xcode/macOS, inspect warnings and CI status, run tests and capture crash reports.
4. Locate exact files for recording lifecycle, cursor/event telemetry, media synchronization, timeline/edit model, renderer, exporter, persistence, UI navigation and update mechanism.
5. Record feature maturity from source and test: **working**, **partial**, **prototype**, **docs-only**, or **absent**.
6. Benchmark same representative 1080p/4K clips using same host/settings, export geometry and visual references.
7. Test core failure states: denied permission, no telemetry, audio loss, display disconnect, interruption, project reload, repeated export.
8. Estimate amount of fork-specific code to keep, rewrite or remove, including upstream sync cost.
9. Document package/entitlement/permissions signing constraints and notarization.
10. Make a decision with evidence and explicitly record what is excluded.

## Proposed adoption map

| Capability | Prefer | Secondary reference | Why |
| --- | --- | --- | --- |
| Capture and basic audio | Orbit (assuming passed tests) | BetterCapture | Works in a single app lifecycle |
| Event sidecar / cursor overlay | Orbit | ArcShot architecture (reference only) | Independent cursor allows clean reframing |
| Timeline / undo / persistence | Orbit | OpenScreen UX patterns | Avoid two competing project models |
| Zoom and easing | Orbit | OpenScreen/programatic-demo ideas | Extend with rules, don't mix runtimes |
| Preview/export compositor | Orbit initially | CineScreen Metal | Preserve parity, measure before replacing |
| Automated storyline | New Cineo DirectorCore | OpenScreen and programmatic-demo concepts | Differentiate on *result*, not clicks |
| Product film / motion compositions | Defer until code audit | Orbit Motion documentation, CineScreen | Avoid overbuilding an MVP |

## Fork vs transplant decision

Choose a **fork of Orbit** only if P0 proves: stable capture/audio on target Macs; independent telemetry; working usable timeline/undo/persistence; coherent preview/export compositor; valid redistribution rights; build and tests reproducible; expected maintenance reasonable.

Otherwise use **BetterCapture + one coherent editor/compositor** as a new assembly, or **CineScreen** if it provides a smaller reliable vertical path. A third option is a fresh Swift app with small audited modules; the objective is fewer lifecycle surprises, not maximal copied code.

No source code has been imported into Cineo by this research.

## Required contribution ledger (for every actual reuse)

Record: upstream URL, pinned commit/tag, source path, destination path, license and copyright, third-party notice, adaptation made, linked tests, and any future upstream-sync strategy. Keep copied LICENSE/NOTICE texts where required, and seek legal review before commercial distribution when rights are ambiguous.

## P0 decision record to publish

Decision: Orbit / BetterCapture-based / CineScreen-based / independent.  
Evidence: commit IDs, build outputs, test logs, native app demo video, preview/export comparisons, license inventory.  
Trade-offs: missing editor capabilities, long-term maintenance, deployment target, renderer change cost.  
Go/no-go: do not begin broad rebranding or merge wholesale fork history until this is approved.

See [roadmap](roadmap.md).

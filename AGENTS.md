# Cineo — Project and coding-agent guidance

This repository is **Cineo**, a planned native macOS product for cinematic product-demo screen recording. It currently contains **inherited repo-template-sw materials**. Do **not** treat their original upstream-product descriptions as Cineo's scope or mistake their generic contracts for working Cineo source code.

## Routing and source of truth

- **Product direction/outcomes:** docs/product.md
- **User workflows, features and acceptance:** docs/feature-spec.md
- **UX and motion grammar:** docs/ux-motion.md
- **Architecture/data invariants:** docs/architecture.md
- **Upstream licensing, evaluation and source provenance:** docs/upstream-evaluation.md
- **Verification and test evidence:** docs/quality.md
- **Milestones, priorities and dependencies:** docs/roadmap.md

When generic inherited contracts conflict with product-specific requirements, preserve their engineering intent but first document a Cineo-specific native mapping, rather than blindly treating Cineo as a template distributor. Any migration of inherited root/template files should be an explicit P0 work item, with affected checks updated together.

## Product rules

1. Native macOS: Swift / SwiftUI + AppKit, ScreenCaptureKit and AVFoundation; provisional target Apple Silicon and macOS 15.2+ pending P0.
2. Local-first: capture/editor/export must not require a login, cloud endpoint or AI model.
3. Real demos and purposeful motion: highlight the consequence of user actions, avoid zooming automatically on every click.
4. Source immutability, editable timeline and reversible generated suggestions.
5. No typed keystroke text in event sidecars; request audio/camera/Accessibility only when relevant; redact diagnostics.
6. Preview/export share a single scene evaluation and explicit geometry/timebase contract.
7. Never mix two capture lifecycles, timeline models or GPU renderers by default.
8. Do not claim a capability exists based solely on a repository README, a prototype, or documentation.

## Upstream reuse and licenses

- **Default native application:** `Apps/Cineo`, built with SwiftPM and Apple Command Line Tools (no Xcode.app) using `scripts/test-cineo.sh --native|--interactive`. Developer builds use a pinned persistent certificate-backed signing identity in the login Keychain; ad-hoc signing is CI-only and never a substitute for real TCC verification. ScreenCaptureKit Capture Alpha only; real TCC/MP4 tests pending.
- **Legacy editor reference:** diip3sh/orbit at pinned SHA `219c4c8ad9965229aa84271c5201b1b8ad26eb7a`, per `docs/decisions/0001-native-foundation.md`. Its Xcode build and Smart Zooms editor remain behind explicit `--legacy-orbit-*` commands until ported. Do not represent them as features of `Apps/Cineo`.
- Other evaluation references: jsattler/BetterCapture, jasonzh0/CineScreen, getopenscreen/openscreen.
- Do not copy ArcShot or AGPL-derived source just because it is readable; read exact source license/dependencies/asset notices and evaluate distribution consequences.
- Maintain provenance ledger (upstream, SHA, original path, license, copyright, changes, tests) before every imported source module.
- If P0 benchmarks contradict the chosen candidate, update the architecture decision before implementation.

## Delivery process

- Prefer small vertical slices tied to a user outcome. Follow docs/roadmap.md dependencies.
- In **iteration**, run focused logic/tests and an affected native compile when available.
- At **integration**, review full changes, prove the affected end-to-end user flow and attach screenshots/continuous video for visible UX changes.
- At **release**, verify all quality gates including real-Mac capture, signing/notarization, permission behaviour, privacy and source preservation.
- Use CLT-only macOS CI for all changes to `Apps/Cineo` and default test runner. Legacy Xcode CI is optional and limited to pinned Orbit compatibility. Do not invent green CI evidence or assert that local builds were run without actual output.

## Current gate: P1, with P2/P3 independent package spikes

1. Verify SwiftPM `Apps/Cineo` builds with `DEVELOPER_DIR=/Library/Developer/CommandLineTools` and uses certificate-based persistent signing locally. CI may build an ad-hoc `.app` and separately exercises the stable designated requirement using an ephemeral signing identity; the old Orbit staging is a separate compatibility suite.
2. On a real Mac run `scripts/test-cineo.sh --interactive`; confirm TCC approval and a playable MP4. Do not claim audio, editor, or Smart Zooms for this Capture Alpha; those remain migration tasks #39.
3. Independently improve pure Swift `CineoDirector` and `CineoProject` logic with tests; do not claim these are wired into the native app.
4. Keep inherited template validation marked as legacy engineering checks rather than app-level E2E.

## What does not count as done

A stub UI; a README feature claim; an editor preview without matching exported frames; saving a project that cannot be reopened; losing a source file after failed export; unmeasured AI-based auto camera; or a branch that compiles but fails the real capture → edit → export journey.

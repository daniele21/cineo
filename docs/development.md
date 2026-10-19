# Developing Cineo — current environment contract

**Stage:** P0 research and independent Swift package prototypes. There is **no Cineo.app or Cineo.xcodeproj yet**. The inherited repo-template-sw directories are kept as reference material while issue #2 gradually adapts engineering configuration.

## Current runnable commands

| Intent | Command | Evidence |
| --- | --- | --- |
| Environment diagnosis | `bash scripts/doctor.sh` | Host OS, Swift, Xcode presence |
| Pure camera prototype build | `swift build --package-path Packages/CineoDirector` | Swift package only; not macOS capture |
| Pure camera tests | `swift test --package-path Packages/CineoDirector` | Camera planner logic, cross-platform |
| Inspect upstream benchmark targets | `bash scripts/benchmark-upstreams.sh --list` | Pinned versions and planned Mac build commands |
| Fetch/compile selected upstream | `bash scripts/benchmark-upstreams.sh --run orbit` | macOS + Xcode 26 + network required |
| Fetch/compile CineScreen | `bash scripts/benchmark-upstreams.sh --run cinescreen` | macOS, XcodeGen and Metal toolchain may be needed |
| Fetch/compile BetterCapture | `bash scripts/benchmark-upstreams.sh --run bettercapture` | macOS + Xcode |

**Build is not E2E.** Upstream compilation with signing disabled checks source compatibility, not permissions, TCC, screen/audio capture, interactive app UX, video quality, signed launch or notarization. Those require a properly signed application tested on a physical Mac.

## Branch separation

- `research/upstream-source-audit`: evidence-only upstream audit / module comparison / ADR preparation.
- `chore/native-engineering-baseline`: native developer contracts and reproducible scripts.
- `feat/camera-planner-spike`: isolated Swift, deterministic suggestion prototype; keep out of the app target until P0 decision.

Workstreams have no overlapping source paths and can be reviewed independently. Do not merge an upstream fork before audit evidence is approved.

## Runtime/CI

`scripts/doctor.sh` does not install packages, alter signing credentials or make network requests. The upstream benchmark script prints its plan by default; `--run` explicitly fetches/pins sources, builds into a temporary `/tmp` location and saves the output logs locally.

Future native app commands, CI lanes, code signing and packaging will be added once the Xcode base is selected. No claim of test success is inferred from `swift --version` alone.

## Source and rights

See `docs/research/p0-source-audit.md` once merged and `docs/upstream-evaluation.md`. Third-party code, bundled fonts and logos must be evaluated independently before copying or distributing.

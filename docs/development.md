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


## P1 native Cineo bootstrap (experimental)

The [P0 native foundation decision](decisions/0001-native-foundation.md) selects Orbit **conditionally** for P1. Cineo now has an out-of-tree staging bootstrap, not an imported fork or completed `Cineo.app` release.

```bash
# Safe even on Linux: only shows the pinned source and output location
bash scripts/bootstrap-native.sh --plan

# macOS + Xcode 26+ required; clones the exact audited Orbit SHA,
# overlays a separate Cineo bundle ID/name and builds unsigned
bash scripts/bootstrap-native.sh --build

# Recheck the bundle without building
bash scripts/bootstrap-native.sh --verify
```

By default everything is staged in a temporary directory. Override with `CINEO_NATIVE_ROOT=/path/to/temporary-workspace` (outside the repository). The overlay **removes upstream Sparkle update feed, URL scheme/file associations and sandbox-data migration**, disables its local agent bridge and selects a neutral tray icon. The stage retains Orbit internal code/UI pending Cineo-specific UX work. The upstream MIT notice is copied into `UPSTREAM-ORBIT-LICENSE.txt`.

GitHub Actions runs [`Cineo P1 native bootstrap`](../.github/workflows/p1-native-bootstrap.yml) on `macos-26` for pull requests and uploads compile logs. A green workflow proves only that an unsigned bundle can be constructed with the right identity. It does **not** prove capture, TCC permissions, editing, export, image clarity, media sync, or redistribution rights.

### Interactive macOS gate (P1, not yet passed)

After a successful unsigned build, the app must be signed by an authorized Apple developer identity before the **physical Mac** capture/permission smoke. Open the staged `Reco.xcodeproj` in Xcode, configure the intended development Team and a unique Cineo bundle ID (the overlay sets `com.daniele21.cineo`), then build/run in Debug with automatic signing. Keep the original source checkout pinned and overlay applied. No developer credentials belong in the repository or GitHub logs.

On a real Mac, record the exact macOS/Xcode version and follow this checklist:

- [ ] App starts as Cineo under its own bundle ID and uses no legacy Orbit URL association or updater.
- [ ] Screen Recording permission request and denied/revoked recovery work; unexpected permission requests are investigated.
- [ ] Display and window capture produce playable clips; system audio/mic selection is explicit; A/V sync measured.
- [ ] Original media survives stop/cancel/abrupt exit and can be reopened in the editor.
- [ ] Export a short **16:9 and 9:16** clip, inspect cursor, transforms, compression and audio; compare actual outputs to a reference.
- [ ] Check application support paths, user defaults, no unwanted network/IPC, any remaining upstream branding and license notices.

Store **redacted** results with captured source hashes and exported video evidence. If launch/TCC/export fails, keep P1 blocked and revisit the Orbit choice per the ADR. Do not use GitHub-hosted CI alone as evidence of these physical-Mac requirements.

See [P0 provenance](research/p0-provenance-inventory.md) and [P1 roadmap](roadmap.md).

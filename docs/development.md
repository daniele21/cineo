# Developing Cineo — current environment contract

**Stage:** CLT-first **Cineo Capture Alpha** now builds from `Apps/Cineo` with SwiftPM and Apple's Command Line Tools, without Xcode.app. It compiles, creates an ad-hoc-signed bundle and contains an actual ScreenCaptureKit capture implementation; live TCC/recording must still be tested on a physical Mac. The fuller **Orbit-derived editor/Smart Zooms** currently remains an explicitly marked legacy Xcode-dependent reference, not yet incorporated into this CLT app. See [ADR-0002](decisions/0002-xcode-free-build.md) and [issue #39](https://github.com/daniele21/cineo/issues/39).
## Current runnable commands

**Default local workflow (no Xcode.app required):**

```bash
bash scripts/test-cineo.sh --preflight
bash scripts/test-cineo.sh --quick
bash scripts/test-cineo.sh --native
bash scripts/test-cineo.sh --interactive
```

The `--native` command invokes `scripts/build-cineo-clt.sh`, and `--interactive` opens an ad-hoc-signed local recorder. `--quick` on macOS uses a **limited executable smoke test** instead of Swift Testing macros (which are unreliable on certain CLT versions); full Swift regression suites remain in Linux CI. Do not claim that current Capture Alpha supports an Orbit timeline or Smart Zooms.

**Legacy reference only:** `bash scripts/test-cineo.sh --legacy-orbit-native` and `--legacy-orbit-interactive` require Xcode 26+. Their separate [legacy CI](../.github/workflows/p1-native-bootstrap.yml) does not run for changes to the preferred CLT build entry point.

The old table below documents commands for independently reproducing earlier source audits and Orbit builds, **not requirements for developing the current Cineo Capture Alpha**.


| Intent | Command | Evidence |
| --- | --- | --- |
| Environment diagnosis | `bash scripts/doctor.sh` | Host OS, Swift, Xcode presence |
| Pure camera prototype build | `swift build --package-path Packages/CineoDirector` | Swift package only; not macOS capture |
| Project persistence/time mapper tests | `swift test --package-path Packages/CineoProject` | Schema/timeline logic, cross-platform (Swift Testing Linux CI) |
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

# Real-Mac debug build: uses locally installed Apple Development identity,
# never GitHub CI credentials or a hard-coded team in source control
CINEO_APPLE_TEAM=YOUR10CHARID bash scripts/bootstrap-native.sh --dev-build
```

By default everything is staged in a temporary directory. Override with `CINEO_NATIVE_ROOT=/path/to/temporary-workspace` (outside the repository). The overlay **removes upstream Sparkle update feed, URL scheme/file associations and sandbox-data migration**, disables its local agent bridge and selects a neutral tray icon. The stage retains Orbit internal code/UI pending Cineo-specific UX work. The upstream MIT notice is copied into `UPSTREAM-ORBIT-LICENSE.txt`.

GitHub Actions runs [`Cineo P1 native bootstrap`](../.github/workflows/p1-native-bootstrap.yml) on `macos-26` for pull requests and uploads compile logs. A green workflow proves only that an unsigned bundle can be constructed with the right identity. It does **not** prove capture, TCC permissions, editing, export, image clarity, media sync, or redistribution rights.

### Interactive macOS gate (P1, not yet passed)

After a successful unsigned build, the app must be signed by an authorized Apple developer identity before the **physical Mac** capture/permission smoke. Set `CINEO_APPLE_TEAM` to the 10-character Team ID for the Apple Development identity already installed in Xcode, then run `bash scripts/bootstrap-native.sh --dev-build`. The bootstrap uses automatic signing and checks the resulting app with `scripts/native-smoke-doctor.sh`; it does not open the app or grant TCC automatically. Alternatively open the pinned staged `Reco.xcodeproj` in Xcode and configure the team manually. Never commit identities, keys or provisioning data.

On a real Mac, record the exact macOS/Xcode version and follow this checklist:

- [ ] App starts as Cineo under its own bundle ID and uses no legacy Orbit URL association or updater.
- [ ] Screen Recording permission request and denied/revoked recovery work; unexpected permission requests are investigated.
- [ ] Display and window capture produce playable clips; system audio/mic selection is explicit; A/V sync measured.
- [ ] Original media survives stop/cancel/abrupt exit and can be reopened in the editor.
- [ ] Export a short **16:9 and 9:16** clip, inspect cursor, transforms, compression and audio; compare actual outputs to a reference.
- [ ] Check application support paths, user defaults, no unwanted network/IPC, any remaining upstream branding and license notices.

Store **redacted** results with captured source hashes and exported video evidence. If launch/TCC/export fails, keep P1 blocked and revisit the Orbit choice per the ADR. Do not use GitHub-hosted CI alone as evidence of these physical-Mac requirements.

See [P0 provenance](research/p0-provenance-inventory.md) and [P1 roadmap](roadmap.md).

## Native smoke preflight

After creating an unsigned staging app on macOS, run `bash scripts/native-smoke-doctor.sh --app /path/to/Cineo.app --allow-unsigned` to inspect bundle metadata. After signing with your own developer identity, omit `--allow-unsigned`: the doctor checks actual signature validity. This still does not run interactive capture or export. Follow [native test protocol](testing/native-smoke.md) for mandatory TCC, audio and output acceptance.

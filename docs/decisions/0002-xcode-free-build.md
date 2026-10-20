# Decision experiment: build native macOS Cineo without Xcode.app

**Status:** CLT-only compile-and-sign feasibility **proven** in [macOS GitHub Actions run #39407952382](https://github.com/daniele21/cineo/actions/runs/39407952382), using **Apple Command Line Tools Swift 6.4**. Existing full Cineo/Orbit app remains Xcode-dependent until migrated. Owner goal: **no full Xcode installation required** for Cineo developers. Apple Command Line Tools (CLT), Swift compiler and macOS SDK remain required because Cineo uses SwiftUI, ScreenCaptureKit and AVFoundation.

## Why the previous Cineo bootstrap fails

The existing [Orbit staging script](../../scripts/bootstrap-native.sh) invokes `xcodebuild -project Reco.xcodeproj`, which Apple ships only with full Xcode.app. The user's Mac has active developer directory `/Library/Developer/CommandLineTools` and Swift 6.3.3, so it cannot run `xcodebuild` despite having a current compiler.

`no such module 'Testing'` during `swift test` is a **second CLT/SwiftPM module resolution issue**, not evidence that Swift libraries themselves depend on full Xcode. The Swift Testing project documents availability in CLT 16+; diagnose SDK/testing framework paths and package manager integration separately.

## Proposed long-term architecture

- `Packages/CineoDirector`, `CineoProject` and `CineoEditPlanner`: retain SwiftPM modules, run `swift build`; fix `swift test` for CLT-only usage.
- `Apps/Cineo`: a **SwiftPM executable** with SwiftUI root app; import ScreenCaptureKit, AVFoundation, CoreGraphics and AppKit via macOS SDK.
- `scripts/build-cineo.sh`: `swift build`, assemble `Cineo.app/Contents/{MacOS,Resources,Frameworks}`, maintain `Info.plist`, assets, permission descriptions, entitlements, nested code and `codesign`. Signed release can use Developer ID and notarization CLI; developer smoke can use ad-hoc signing.
- Keep one native video compositor and camera/timeline authority. Do **not** replace SwiftUI with Electron or rewrite ScreenCaptureKit to avoid Xcode.
- Keep current Orbit Xcode target as a **temporary reference** only, until its recording/audio/editor/source modules are ported and validated in a SwiftPM-owned app. We must assess generated files, asset catalogs, Sparkle, font licenses, sandbox and Swift package dependencies; the full migration is not a switch of one build command.

## First proof of concept (this PR)

A deliberately **minimal** `Examples/CineoCLTProof` executable imports SwiftUI, ScreenCaptureKit and AVFoundation and creates a visible SwiftUI window. `scripts/build-clt-proof.sh` uses `swift build`, assembles a normal `.app`, writes Info.plist and ad-hoc signs it with `codesign`. CI sets `DEVELOPER_DIR=/Library/Developer/CommandLineTools` on macOS and checks this selected path. No invocation of `xcodebuild`.

```bash
DEVELOPER_DIR=/Library/Developer/CommandLineTools bash scripts/build-clt-proof.sh
# Optional only after successful build and consent:
open "${TMPDIR:-/tmp}/cineo-clt-proof/CineoCLTProof.app"
```

**What proof would establish:** compilation against macOS frameworks and packaging/ad-hoc signing with no full Xcode toolchain selected. **What it does not establish:** running Orbit recording code, app launch on the user's host, Screen Recording/TCC, synchronous audio, actual video export, hardened signing, notarization or release readiness.

## Observed evidence and limits

- [x] CI explicitly selected `/Library/Developer/CommandLineTools` for the developer directory and `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk` for the SDK.
- [x] `swift build` compiled the small native SwiftUI app importing ScreenCaptureKit and AVFoundation.
- [x] Bundle creation, `plutil -lint`, `codesign --sign -` and `codesign --verify --strict` passed, without calling `xcodebuild`.
- [ ] Local CLT 6.3.3 (user host), Swift Testing compatibility, app launch and any real capture/preview/export remain unverified.

## Acceptance and migration steps

1. CI: ensure `xcode-select -p` is the CLT directory and `swift build` produces a runnable-signable bundle. If CI fails, fix the actual CLT compatibility limitation rather than silently selecting full Xcode.
2. On the user's host, verify bundle launch by `open`, with no screen capture requested by the proof app.
3. Adapt the standalone Swift Testing module resolution on CLT; do not mandate Xcode. Retain Linux Swift test CI during migration.
4. Port native capture (ScreenCaptureKit) with explicit permission handling into SwiftPM. Prove a saved playable file on the host.
5. Port Orbit editor and compositor **together**, with source pin, license/asset notice and preview/export parity tests. Do not claim app parity beforehand.
6. Replace existing `--native`/ `--interactive` Xcode-only scripts with CLT-native build entrypoints only when the full application is functionally equivalent.

**Security:** No automated Screen Recording permissions, no secrets/Developer ID in the repository, no bypass of macOS Gatekeeper. Ad-hoc bundle is strictly for local developer testing; signed distribution requires developer credentials/notarization process.

References: [Apple CLT documentation](https://developer.apple.com/documentation/xcode/installing-the-command-line-tools), [Swift Testing distributions](https://github.com/swiftlang/swift-testing/blob/main/Documentation/Distributions.md).

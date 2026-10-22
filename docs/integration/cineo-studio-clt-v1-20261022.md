# Cineo Studio — integrated baseline candidate

**Date:** 2026-10-22
**Branch:** `integration/cineo-studio-clt-v1-20261022`
**Release status:** unmerged, not ready to distribute

This is a *single linear history* from the current `main` through the
native capture/editor and Music Director work to click-based Smart Camera.
The GitHub compare API reported **ahead without divergence**; do not
blindly merge alternative PR implementations on top.

## Parent work integrated in this candidate

- `#44` screen capture finalization repair
- `#55–56` CLT Studio, scene model, pointer/CLI base and renderer
- `#57–58` Music Director, waveform, timeline and BeatSync
- `#60–62` audio polish, perceptual-smoke scaffolding, ACE UI lifecycle
- `#63–66` signing CI stability, repaint/SFX, durable music queue and
  ACE watchdog that reaps the child on owner exit
- `#67` opt-in click metadata, Auto Edit proposals and native audio toggles
- `#68` deterministic camera quality fixtures, per-shot approval and
  suppression of delayed/off-target zooms during dense interactions

`#59` is an alternative music polish branch and intentionally is **not**
merged: its crossfade/ducking/cue contracts diverge from the #60 lineage.

## Quality evidence, not marketing claims

| Dimension | Automated gate | Physical Mac still required |
| --- | --- | --- |
| CLI and Swift data model | SwiftPM tests on Linux | Real project restore |
| Smart Camera | Deterministic structural fixture and rate/crop checks | Text readability, actual pacing |
| Scene and MP4 | Synthetic H.264 + WAV render smoke on macOS | Actual captured product demo |
| Music backend | Watchdog normal/SIGKILL smoke; music contract tests | ACE-Step inference and actual audio |
| Audio capture | CLT compile; permission/format contracts | System/microphone permissions and drift |
| App integrity | CLT-only signed bundle build on macOS CI | Signed Mac TCC and relaunch behavior |

**Known limitations:** edit-plan still single untrimmed source clip;
click-only Smart Camera is rule-based and cannot identify result changes
without a user/semantic anchor; mouse-only event capture is opt-in;
full release signing/notarization, media licenses and physical Mac
perceptual 16:9/9:16 end-to-end QA are not passed by green CI alone.

## Integration and promotion policy

1. Freeze candidate SHA after all CI checks succeed.
2. Run focused physical-Mac smoke of Smart Camera shot review and system/mic
   permissions; repair edge cases without changing the source media.
3. Merge this candidate to `main` only after the agreed integrated
   verification gates pass. Keep stacked PRs linked for audit; do not
   re-merge their duplicate changes into main.
4. Run the final whole-product capture → review → music → preview → export
   E2E with varied real content as the last product acceptance gate.
5. Distribution requires additional license, Developer ID notarization and
   accessibility/security review.

To test in the developer's **existing** local checkout:

```bash
git fetch origin
git switch integration/cineo-studio-clt-v1-20261022
bash scripts/test-autoedit-gates.sh
bash scripts/test-cineo.sh --interactive
```

No detached worktree, Xcode.app or background daemon is needed.

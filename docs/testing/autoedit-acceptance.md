# Cineo Auto Edit — acceptance evidence, not mock success

This specification gates G1 (real frame rendering), G2 (genuine pointer suggestion), G3 (UI/CLI parity). It does not claim any test has run or passed yet. Research: [Auto Edit upstream code study](../research/auto-edit-upstream-2026-10.md).

## Test matrix

| Source | Input and expected behavior | Required evidence |
| --- | --- | --- |
| 3 sec active app | Export must be decodable, start/end captured | CineoExportProbe, start/end sampled frames |
| 25 sec valid source | Styled output with 1 manual zoom, preserved source | input SHA-256, output dimensions/duration, 3 sampled changed frames |
| 60 sec dense demo | Several separated clicks, no camera thrashing | event PTS/timeline logs, shot gaps, preview/export pixel locations |
| Still screen/no clicks | No invented cursor events; static composition exports | exact count zero, decodable file |
| Static content with loading spinner | Do not misclassify whole span as idle | sample-frame motion checker |
| Corner clicks + nonprimary display | Mouse indicator/zoom in content bounds | four corners, video PTS calibration and Retina scale |
| Existing export destination | Cancel/failure preserves destination **byte for byte** | before/after SHA-256 |
| Reopen after auto suggestions | Manual overrides and rejection preserved | JSON diff, undo, persisted schema version |
| CLI vs UI same project | Equal scene geometry and output-time mapping | output frame probes with tolerance |
| Denied pointer monitoring permission | Style-only fallback, without failing screen capture | safe fallback logs, no keystroke fields |

## Manual video QA
- Verify user can read text at final output resolution (not just at source resolution).
- No camera snap, no camera tremor and no change of focus during a loading state.
- No double cursor if the source already burned it in.
- No output with wrong aspect ratio, stretched window, reversed Y coordinates or omitted tail frames.
- No unverified "export complete" state: video codec, track, duration, dimensions, and playable sampled frames.
- Source capture, original current output and project folder must survive failed export/cancel.
- CLT only: `DEVELOPER_DIR=/Library/Developer/CommandLineTools`; no xcodebuild.
- Recording permission restart must target `~/Applications/Cineo Dev.app`, never old Cineo.

## Evidence collection
Record Git SHA, macOS version/host, Swift/CLT version, sanitized job phase progress, clip name alias, source/output SHA, source/output geometry/duration, 3 sample-frame image hashes, failure code and elapsed time. No private desktop video in CI artifacts without explicit opt-in. For reproducible CI use generated synthetic fixtures.

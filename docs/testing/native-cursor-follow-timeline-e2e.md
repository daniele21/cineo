# Cineo native cursor / Camera Follow / Timeline — E2E evidence checklist

**Candidate:** PR #77, based on plan #73 and pre-main Studio #72. **No release approval implied.**

## Automated checks (must be green)

- `swift test --package-path Packages/CineoEvents` — v1/v2 pointer sidecar compatibility, no untrusted cursor overlay on baked video, exact click anchors, random seek.
- `swift test --package-path Packages/CineoDirector` — safe-zone follow, keyframe preservation, no pan storms and no click-only phantom movement.
- `swift test --package-path Packages/CineoProject` — pixel snapping, region edit bounds and cut-clock mapping.
- `swift test --package-path Packages/CineoScene` — legacy smoothstep, cinematic curves, cursor source time, strict input.
- `swift run --package-path Packages/CineoScene --configuration release cineo-scene-smoke` on macOS — actual H.264 generated and decoded; pixel-level cursor/no-cursor Core Image comparator; original SHA unchanged.
- `bash scripts/test-cineo.sh --native` on macOS using only Apple CLT, including signing policy. Automated CI does not grant TCC or measure an interactive session.

## Physical macOS acceptance matrix

Use a real signed `~/Applications/Cineo Dev.app` built from the **exact integration SHA**, with the same bundle ID/certificate as the previous run; stop any old Cineo processes before building. Never launch two competing dev app identities.

| Scenario | Steps | Acceptance |
| --- | --- | --- |
| Legacy video | Import a pre-v2 MP4 with cursor baked into frames | Exactly one pointer; no overlay; old projects load |
| No telemetry | Capture with all pointer options OFF | Original MP4 usable; no synthetic path, no prompt for Accessibility |
| New independent pointer | Turn on only “Cursore ricostruito (beta)”, record 15–30s and move mouse | Original H.264 hides pointer; v2 sidecar stores only normalized mouse points; edited preview shows exactly one pointer |
| Pointer + click | Record left/right clicks on buttons while moving over a 2-display setup | Correct top-left cursor hotspot, no doubled cursor, click effect aligns with actual button |
| Missing source samples | Stop, reopen, scrub through beginning/end and long gaps | No extrapolation or nan; explicit failures/warnings if metadata unavailable |
| Camera follow | Add a zoom, then “Segui cursore negli zoom”; move pointer inside and outside focus safe zone | No pan inside; panning outside; keyframe originals untouched; “Annulla follow” recovers exact previous state |
| Dense input | 30s with rapid back-and-forth movement/clicks | No pan storm, no hangs, no click position jumps |
| Timeline drag | Drag zoom blocks left/right; undo; save and reopen .cineo | Output clock and keyframes match edit; no overlap/invalid time; source SHA intact |
| Source cut seam | Remove interval before zoom/music as permitted; scrub across boundary | No thumbnail from deleted source; preview/extracted frame maps to retained source; music stays synchronized |
| Playback vs export | Scrub random order, then play, export H264; check frames at same PTS | Equivalent cursor location, zoom crop, click pulse and color; one composition path |
| Portrait | Change to 9:16 and repeat zoom/overlay preview/export | Pointer never clipped incorrectly at stage edge; crop bounds valid |
| Audio & music | Record original audio, import music and optional cues, export | Decodable A/V, no obvious drift; no music process orphaned on close |
| Failure & recovery | Cancel export, force quit after save, reopen project | Input MP4 unmodified; last valid project/settings retained, no temporary target mistaken for final |

**Privacy gate:** never inspect/read keystrokes, window contents/titles or clipboard through pointer telemetry; TCC screen permission only on recording. Movement and independent-cursor capture must be separate explicit opt-ins; sidecar is local.

## Metrics to record (not yet measured)

- SHA-256 of recording before/after all actions.
- Export wall time and peak working-set memory for 1080p/4K input.
- Frame-by-frame position delta in output pixels for clicks, and count of missing overlay frames.
- Number of extra camera pan keys per minute, including high-frequency movement.
- Worst preview/export frame mismatch by timestamp, A/V start offset and drift after cuts.
- Studio interactions: scrub latency, filmstrip decode time, drag responsiveness, save/reopen.

**Exit status:** until a Mac runner or operator attaches actual build logs and an audiovisual capture, this is a developer candidate, not a passed real-world E2E.

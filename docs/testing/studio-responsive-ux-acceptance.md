# Cineo Studio — responsive UX acceptance (2026-11-05)

## Intent and design rules

Studio is a **canvas-first editor**, not a control panel with a video attached.
Keep one major action visually prominent at a time: preview/playback, Smart Camera proposals, then export.
Secondary operations belong in the **Strumenti** menu; cut markers and raw keyframe chips
are collapsed until requested. The editor maintains the existing Cineo ocean
accent and native macOS typography/materials.

Changes are deliberately presentation-only: source video, non-destructive
edit/save, AVFoundation/Core Image export, queued ACE-Step generation, and
cancel/undo rules keep their previous implementations.

## Capture dashboard contract

- No fixed 620-pt content width. The dashboard scrolls vertically and adapts
  from one column to two around 850 pt.
- Recording / opening a video is the principal action, clearly separated from
  optional microphone, system audio and pointer telemetry.
- The five recording options wrap into a responsive grid instead of overflowing
  on one row. Options remain visible by default.
- The recording phase, elapsed time, file size and progress explanation stay
  prominent. The Activity log stays visible and auto-scrolls as new entries arrive.
- Developer identity is retained but visually de-emphasized.

## Layout contract

- At widths >= 1060 pt: preview/timeline flexible on the left; 304-pt inspector
  on the right with independent scrolling. Playback and export remain visible.
- Below 1060 pt: single vertically scrollable reading order (preview, transport,
  timeline, inspector). No fixed 720×410 preview, no 245-pt non-scrolling sidebar.
- Window minimum: 720×560 pt. The preview scales with the content region and
  preserves 16:9 or 9:16; the click coordinate system is the **actual image
  bounds**, not the letterboxed background.
- Only one inspector section is visible: Smart / Camera / Stile.
- The status/export bar stays outside the workspace scroll area.
- Selection affordance appears visibly when Cineo is waiting for a cursor tip.

## Manual macOS acceptance matrix

Test **the exact PR SHA** on a physical Mac using the one canonical
signed ~/Applications/Cineo Dev.app. Close a running Cineo before installation.
Do not switch users or overwrite a running install.

| Window / media | Actions | Pass criteria |
| --- | --- | --- |
| 620×490, capture | Inspect primary controls, recording options and log | No horizontal overflow; options wrap; record/stop accessible |
| 900×700, capture | Resize, start and stop a short recording | Actions remain reachable, phase and logs visible |
| 720×560, landscape MP4 | Scroll preview → timeline → Smart inspector | Preview entirely visible; export remains visible; no horizontal window overflow |
| 980×700, landscape | Resize repeatedly across 1060-pt breakpoint | No clipped controls or jump to stale preview; inspector accessible |
| 1280×800, landscape | Switch Smart / Camera / Stile | Inspector scrolls, preview and export remain in place |
| 1440×900, 9:16 | Toggle portrait, scrub and select point | Letterboxing correct, selection matches the visible image hotspot |
| 720×560, 9:16 | Track cursor from a paused frame | Cursor-selection hint visible, click maps to image not black bars |
| Imported QuickTime/OBS MP4 | Analyze cursor → generate zooms → approve/reject | Progress and cancel available, no fabricated clicks, proposals preview correctly |
| Recorded Cineo clip | Click-driven Smart Camera and Camera Follow | Existing pointer telemetry is used; manual keys preserved |
| Any supported project | Toggle Tagli/Dettagli, move zoom, undo/redo | Tools discoverable; controls retain existing behavior |
| Music already queued | Navigate to Studio, open Musica/queue, export | Queue button accessible; no duplicate jobs or audio regression |
| Keyboard / VoiceOver | Tab to transport, inspector and export | Labels announced for timeline, zoom and export progress |
| Failure / cancellation | Cancel analyze/export, reopen project | Source hash unchanged, status and recovery still accessible |

## Smart Camera scope regression

- The Smart Camera scope defaults to **Intero video** when Studio opens.
- **Genera zoom per tutto il video** calls `proposeAutoEdit()`, not the playhead-local `applySuggestedZoom()`. It scans the complete output timeline (honoring any intentional cuts), regardless of selected time or scene.
- **Punto selezionato** explicitly calls `applySuggestedZoom()` and creates a single local manual zoom around the playhead. It must never be mistaken for the global suggestion command.
- For imported MP4s, global analysis needs the on-device cursor analysis first; the UI must explain why the global button is disabled.
- Global candidate review remains reversible. Switching to point mode must not silently apply or discard pending global candidates; switch back to review them.
- Regression: a 65-second source with click events around 3s, 27s and 55s must produce proposals across all three regions. Run `swift test --package-path Packages/CineoDirector`.
- On physical Mac test at playhead start, middle, and end; each global run should show the same total candidate set for the same source and settings.

## Automated checks to run on the branch

On a macOS CLT-only host:

```sh
bash scripts/test-cineo.sh --preflight
bash scripts/test-cineo.sh --quick
swift run --package-path Packages/CineoVideoAnalysis --configuration release cineo-import-video-smoke
CINEO_CURSOR_TRACE=1 swift run --package-path Packages/CineoVideoAnalysis --configuration release cineo-import-cursor-benchmark
swift build --package-path Apps/Cineo --configuration release
bash scripts/test-cineo.sh --native
```

A green compiler/build or synthetic benchmark **does not** mean the visual
acceptance matrix passed. The latter still needs physical macOS inspection,
including window resizing, accessible interaction and preview/export parity.

## Explicit exclusions

No automatic semantic detection, video transcription, new render engine,
automatic reconstruction of clicks or cursor removal from imported footage.
The Music Director sheet and JSON instruction sheet have their own fixed sizes
and should be reviewed separately if small-screen support is required.

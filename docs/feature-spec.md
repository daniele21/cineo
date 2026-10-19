# Cineo — Feature specification

**State:** target behaviours and acceptance criteria; not implemented or verified in Cineo unless stated otherwise.  
**Key:** MUST = release-blocking for named phase; SHOULD = valuable but deferrable; LATER = deliberate extension. Each behaviour has a visible outcome and failure handling.

## User experiences

### Journey A — Capture → automatic demo → export (MVP)

1. A menu-bar or application-level command opens the lightweight capture picker.
2. The user chooses a display/window (and later area), with explicit toggles for mic/system audio and pointer event telemetry.
3. The user starts/stops the capture with an unambiguous recording indicator; unavailable permissions are explained with a recovery action.
4. The clip and event sidecar are committed atomically into a local project package. If telemetry is unavailable, the clip still imports, but derived edits clearly degrade.
5. Auto Edit proposes a first cut with restrained camera movements and click highlights; the user can play it immediately.
6. The user can undo, edit or disable any suggestion.
7. Export presets include 16:9 and 9:16 H.264 MP4, with safe framing and clear progress/error messaging.
8. Project reopening restores the clip, timing and edit decisions without altering the source.

**MVP acceptance:** complete this journey on a target Mac without external accounts or network; denied permissions, cancellation, disk-full and failed export have understandable recovery paths.

### Journey B — Refine a feature highlight (V1)

A user scrubs the timeline, selects the moment a result appears, defines a target region, adjusts camera framing/hold/easing and adds a small annotation. The rest of the clip can be dimmed without blurring the highlighted result. All values are previewed and reversible.

### Journey C — Reformat once, publish twice (MVP → V1)

A user switches 16:9 to 9:16, sees where the content would be clipped, adjusts focal anchoring and exports two variants from a single project. Auto-reframing suggestions must not silently hide essential content.

### Journey D — Repeatable scripted demo (V2)

A user or agent provides a known browser workflow, collects captures and DOM target bounds, reviews a proposed storyboard, and exports without a cloud renderer. Script failures show the failed step and retain usable artifacts. This is not required for the MVP.

## Functional requirements and phase

| ID | Capability | Phase | Acceptance contract |
| --- | --- | --- | --- |
| CAP-01 | Display/window ScreenCaptureKit capture | MVP | Select/start/stop creates decodable source; clear recording UI |
| CAP-02 | System audio and optional mic | MVP | Explicit selection, synchronized and independently optional |
| CAP-03 | Event telemetry (pointer/click/scroll) | MVP | Time-coded sidecar; no typed text content; opt-out path |
| CAP-04 | Pause/resume/area capture and camera | V1 | Stable timestamps, graceful denied permission |
| PRJ-01 | Non-destructive local project | MVP | Save/reopen equivalent edits and media references |
| PRJ-02 | Project recovery | MVP | Failed export does not corrupt source; interrupted save detectable |
| CAM-01 | Smart auto-zoom suggestions | MVP | Group nearby actions; no default zoom storm; suggestions editable |
| CAM-02 | Smooth independent cursor and click feedback | MVP | Cursor aligns with clip and remains sharp when zoomed |
| CAM-03 | Manual keyframes, pan, zoom, easing | V1 | Arbitrary focus positions, deterministic interpolation |
| CAM-04 | Semantic focus / result-aware camera | V2 | Supports region/AX/DOM anchors with confidence, fallback |
| EDT-01 | Trim/cut and undo/redo | MVP | Every action undoable, edit graph remains valid |
| EDT-02 | Silence cuts, speed ramps | V1 | No sound pitch surprises; metadata maintained under retiming |
| EDT-03 | Spotlight, mask, annotations and titles | V1 | Editable overlay with safe-area-aware positioning |
| STY-01 | Background, padding, radius, shadow | MVP | Same geometry in preview and export |
| STY-02 | Preset packs and saved brand kit | V1 | Reusable non-destructive style parameters |
| EXP-01 | Local H.264 MP4 16:9 and 9:16 | MVP | Predictable frame rate, output dimensions and progress/cancel |
| EXP-02 | HEVC/ProRes, GIF, captions | V1 | Formats gated by verified platform support |
| AUT-01 | Native CLI/project schema for automation | V2 | Versioned commands, deterministic inputs, no upload |
| AUT-02 | Web workflow capture and optional agent director | V2 | Explicit user permission, inspectable plan and artifacts |

## Camera and attention behaviour

Auto zoom must not be a direct function of every click. Build an **attention model**:

- Detect clusters of pointer positions/clicks with a minimum temporal gap and spatial distance.
- Distinguish navigation, configuration, waiting and result segments when observable; otherwise classify as unknown.
- Prefer wide context at start, one focal interaction, sufficient hold on the changed result, then a wider recap.
- Limit zoom frequency and amplitude; avoid camera movement during critical reading time.
- Frame within content bounds at every aspect ratio; handle browser/sidebar edges deterministically.
- Expose reason codes: click cluster, manual target, dwell, result anchor, or user override.
- Generated edits remain recommendations saved separately from manually authored edits.

**Starting presets (tunable hypotheses):** subtle zoom around 1.15–1.35x; normal zoom around 1.35–1.65x; stronger magnification is manually available. Avoid hard-coding these as product truths. Animate with easing, allow reduced-motion presets, and hold until the target is readable.

## Input and metadata requirements

- Record source pixel dimensions, display scale, frame rate/timebase, window/display identity where safe, crop and display layout changes.
- Treat the source video presentation timestamps as canonical; map event timestamps to that timebase explicitly, with clock-offset validation.
- Store cursor events normalized to a known source coordinate system and preserve shape/visibility separately when supported.
- Store click or key-event markers only if user opted in. Keystroke text is never captured by Cineo telemetry; mask sensitive shortcuts/overlays.
- Audio tracks have distinct IDs and timestamp alignment; changes and gaps are explicit.
- Persist schema version and migration metadata in every project. Deleting an original clip must produce an understandable missing-media state.
- Recording screen content is inherently sensitive: show explicit recording controls and offer crop/blur before export.

## Editor rules

- **Simple first:** playback, one-button Auto Edit, zoom on/off, canvas preset, export visible by default.
- **Studio second:** timeline lanes for source, camera, cursor, audio and overlays; inspector only for selected clip/effect.
- Every mutation supports undo/redo; manual edits take precedence over regenerated auto suggestions.
- Mark unsaved state; autosave atomically; preserve original and rejected suggestions where practical.
- Show what was automatically changed rather than applying invisible edits.
- If background processing is running, preview remains responsive and accurately reports unfinished work.

## Export requirements

- One canonical compositing model (transforms, cursor, masks, text, backgrounds) evaluated at time t for preview and export.
- Explicit pixel dimensions, color space/HDR conversion policy, frame rate and audio mapping. No undocumented silent fallback.
- Render to a temporary destination and atomically move/replace only on success.
- Cancellation stops work, cleans transient assets and keeps source/project intact.
- Track export progress with current phase, target and actionable errors. No hidden cloud call.
- For vertical exports provide a manual focal adjustment if an important UI segment would be cropped.

## Negative / adversarial acceptance cases

- Permissions denied or revoked mid-session; recording monitor unplugged; window closes; screen layout changes.
- Audio device disconnects; intermittent audio; multi-display Retina scaling; long idle period.
- No clicks / no telemetry / cursor hidden: graceful default framing, not a failure.
- 4K source to 9:16 export; very small text; overlay crossing safe area.
- Project stored on external drive that becomes unavailable; insufficient disk space.
- Cancel and restart recording/export repeatedly; force quit during export then reopen.
- Reopen old project after schema upgrade; invalid effect keyframe; corrupted sidecar.
- Privacy leak attempts: keystrokes, local paths, document titles, audio transcripts or tokens in diagnostic logs.

## Future option: product films

Layered scenes, UI object animation, mockups, 3D/depth and sophisticated branded motion may become a separate composition mode **only after** the capture/editor/render pipeline proves stable. Do not force a second compositor into the MVP.

See [UX and cinematic grammar](ux-motion.md) and [quality acceptance](quality.md).

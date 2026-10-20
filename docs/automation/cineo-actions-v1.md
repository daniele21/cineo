# Cineo Actions JSON v1 — importable editing instructions

**Status:** v1 candidate in [integration PR #56](https://github.com/daniele21/cineo/pull/56). Requires Mac CLT app/preview tests before release. No Xcode.app, network, LLM, or external timeline interpreter is needed.

## Goal

Users can continue editing visually in **Cineo Studio** (timeline/zoom/keyframes/background). Alternatively, an agent, script, or human can write a **declarative JSON file**, then select **Importa istruzioni…**. Cineo validates the complete document, compiles it to the **existing CineoScenePlan**, saves the scene, moves the playhead to the first camera focus, and displays the result through **the same CineoSceneFrameRenderer** used for MP4 export. Imported camera keyframes are editable with ordinary Studio controls. This is **not yet animated Play/Pause**: the current CLT Studio preview updates one composited frame at a time when the playhead changes.

Try the versioned [sample configuration](../examples/cineo-actions-v1.json) with a video **at least 13 seconds** long.

## JSON v1 schema (documented contract)

| JSON property | Type | Meaning |
| --- | --- | --- |
| `version` | integer, exactly `1` | Major schema version; incompatible versions fail |
| `timebase` | string, exactly `"output"` | Seconds from the first rendered output frame (same timescale as Studio for untrimmed v0 single-clip projects) |
| `stage` | object, optional | Set composition properties; absent fields retain Studio settings |
| `stage.aspect` | `"16:9"` or `"9:16"` | Output canvas |
| `stage.background` | `"dark"`, `"black"`, `"light"` | Uses the same Cineo Studio color preset |
| `stage.padding` | number from 0 inclusive to 0.35 exclusive | Fraction of output canvas reserved for stage margins |
| `actions` | array of at most 200 action objects | V1 only supports `camera.zoom`. Use an empty array for a stage-only edit |
| `actions[].id` | unique nonempty ASCII id, max 80 chars | Letters, digits, `-`, `_`; shown as a navigation marker |
| `actions[].type` | `"camera.zoom"` | No other types currently accepted |
| `actions[].start`, `end` | number, seconds | Start/end of the complete zoom-in, hold, zoom-out shot, 0 ≤ start < end ≤ source duration |
| `actions[].target.x`, `y` | numbers in [0,1] | Focus point in original recorded content, origin at top-left |
| `actions[].scale` | number in [1.01,2.5] | 1 is unzoomed; a zoom action must be greater than 1 |
| `actions[].transition.in`, `out` | numbers ≥ 0.05 s | Zoom-in/out duration; at least 0.05 s hold between them |

All properties other than the optional `stage` and its fields are mandatory. Actions can be provided in arbitrary order; the compiler sorts them by start time. **Zoom intervals may not overlap or touch** in v1. Exact duplicates or invalid field names are rejected; unsupported action types/unknown fields are never silently discarded. Inputs over 1 MB, invalid types, out-of-bounds time, focus/zoom, duplicate identifiers or corrupt JSON are rejected **before changing the current edit**.

For each zoom shot, the compiler creates **four actual camera keyframes**: `start` (overview), `start + transition.in` (zoomed focal point), `end - transition.out` (zoom hold), `end` (overview). Existing CineoScene easing interpolates between keyframes. No separate exporter, special syntax runtime, or fake preview is created.

## Studio workflow

1. Open a captured MP4 or a supported single-clip `.cineo` project in Cineo Studio.
2. Select **Importa istruzioni…** and choose a JSON file such as `docs/examples/cineo-actions-v1.json`.
3. If there are existing manual keyframes, explicitly confirm **Importa e sostituisci** (or **Annulla** to keep the existing scene).
4. Cineo validates the entire file, sets the real scene/canvas, writes the updated `scene.json` (or the existing legacy MP4 sidecar), moves to the first zoom focus and refreshes the preview. Imported action names are visible as clickable navigation markers in the session; keyframes are visible and editable in the timeline.
5. Scrub to inspect frames; adjust zoom, target, padding/background with ordinary UI. Changes persist in the canonical scene plan. **Esporta MP4** renders them with the existing CineoScene pipeline. Source recording remains unmodified.
6. **Salva progetto Cineo** creates a durable local project. When reopening a `.cineo` package, the compiled camera and stage settings are restored from `scene.json` even though the transient source action-marker names are not yet persisted.

## Known v1 limits

- Current preview is frame-at-a-time: animated playback and editor/export visual parity remain independently gated work.
- No `cursor.highlight`, `text.callout`, `trim`, `speed`, audio edits, arbitrary scripting, AI interpretations, click-derived anchors, multi-clip timelines, or overlapping zooms. Sending these action types is a **validation error**, not an ignored request.
- Imported actions replace the existing camera keyframes **only with user approval**. Stage settings absent from the import are kept. Studio manual edits after import are ordinary scene keyframes; the original declarative JSON is not yet auto-updated or exported.
- Source media stays unchanged, and there is no arbitrary code execution. Future schema revisions require versioned migrations and CLI/UI parity tests.

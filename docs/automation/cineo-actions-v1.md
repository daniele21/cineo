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
| `actions` | array of at most 200 action objects | Supports `camera.zoom` shots or `camera.keyframe` exact timeline edits (do not mix) |
| `actions[].id` | unique nonempty ASCII id, max 80 chars | Letters, digits, `-`, `_`; shown as a navigation marker |
| `actions[].type` | `"camera.zoom"` or `"camera.keyframe"` | Descriptive shot or 1:1 manual keyframe |
| `actions[].start`, `end` | numbers (seconds), zoom only | Start/end of the complete zoom-in / hold / zoom-out shot |
| `actions[].target.x`, `y` | numbers in [0,1] | Focus point in original recorded content, origin at top-left |
| `actions[].scale` | 1.01–2.5 for zoom, 1–3 for keyframe | 1 = no zoom |
| `actions[].transition.in`, `out` | numbers ≥ 0.05 s, zoom only | Time to enter/leave zoom, at least 0.05 s hold |
| `actions[].time` | number (seconds), keyframe only | Exact time 0…duration; times must increase strictly |

Root fields `version`, `timebase` and `actions` are mandatory; `stage` is optional. Each action type has strictly validated fields and no unknown fields may be present. The importer sorts actions by time. Zoom intervals may not overlap or touch, and keyframes and zooms cannot be mixed in v1. Bad input is rejected before applying any edits.

Each `camera.zoom` compiles to four camera keyframes (overview, focus, hold, overview). Each `camera.keyframe` compiles to exactly one timeline keyframe at the specified time, focus and scale. Both render through the existing CineoScene engine.

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
- Imported actions replace current camera keyframes only after explicit confirmation. Missing stage properties keep their prior values. After editing visually, **Mostra istruzioni** regenerates equivalent exact keyframe JSON, available via Copy/Save; it does not attempt to reconstruct descriptive zoom boundaries or original imported labels.
- Source media stays unchanged, and there is no arbitrary code execution. Future schema revisions require versioned migrations and CLI/UI parity tests.


## Studio: Mostra istruzioni — the equivalent JSON dialog

The **Mostra istruzioni** button opens a dialog with three tabs:

- **Montaggio attuale:** actual current stage and every manually edited camera keyframe in versioned, importable JSON; use **Copia JSON** or **Salva JSON…**.
- **Guida:** supported types and fields, timelines, normalized coordinate ranges, validation and unsupported effects.
- **Esempi:** one complete `camera.zoom` shot and one direct `camera.keyframe` animation.

The dialog is read-only to avoid creating a competing edit model. Edit the timeline in Studio or edit a saved `.json` file in an external text editor, then use **Importa istruzioni…** to apply it.

### Exact camera.keyframe example

```json
{
  "version": 1,
  "timebase": "output",
  "stage": {"aspect":"16:9", "background":"dark", "padding":0.06},
  "actions": [
    {"id":"overview", "type":"camera.keyframe", "time":0,
     "target":{"x":0.5,"y":0.5}, "scale":1},
    {"id":"focus", "type":"camera.keyframe", "time":3,
     "target":{"x":0.8,"y":0.3}, "scale":1.8}
  ]
}
```

The importer enforces exactly the same `CineoScenePlan` evaluation after exporting and reimporting. For fidelity, the exact export uses keyframes even if the editing began as descriptive `camera.zoom` actions. Unsupported custom canvases, colors, more than 200 camera keyframes or points beyond the video duration produce an explicit error, not an approximate configuration. The current frame-at-a-time preview remains distinct from future Play/Pause.

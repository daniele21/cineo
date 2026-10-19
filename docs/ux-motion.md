# Cineo — Experience and cinematic grammar

**Purpose:** translate “modern, effective product demo” into repeatable editing rules rather than a pile of effects.

## Design principles

- **Start with a compelling default.** One clear primary action in each state; progressively disclose details.
- **The eye needs orientation.** Begin a scene wide enough to identify the application, then move toward a meaningful action.
- **Actions need consequences.** The most important frame is often the *result*, not the button click.
- **Comfortable camera.** Smooth easing, low movement frequency, deliberate holds, minimal distracting sound design.
- **Visible provenance.** “Suggested zoom” and “Manual zoom” are distinguishable, and all suggestions are reversible.
- **Accessibility:** keyboard control, VoiceOver-friendly actions, reduced motion option, high-contrast controls, safe captions.
- **Mac-native:** native menus/shortcuts, status and permission patterns, drag & drop, predictable undo/redo and standard export panels.

## Main surfaces

| Surface | Primary question | Primary controls | Advanced controls |
| --- | --- | --- | --- |
| Capture picker | What will I record? | Display/window/area, record, audio toggles | Frame rate/codec, cursor options |
| Recording HUD | Is recording active? | Timer, pause/stop | Mic/source status, cancel |
| Auto Edit | Is this ready to share? | Preview, auto on/off, style preset, export, customize | Why edits were suggested |
| Studio | What needs correction? | Timeline, playhead, clip, inspector, undo | Keyframes, audio lanes, masks |
| Export | Will it look right where shared? | 16:9/9:16, preview, destination, export | Codec/bitrate/color options |

## Motion vocabulary

**Establishing:** 0.8–2.0 seconds of context at 1x before major interaction, except very short teasers.  
**Focus-in:** pan + zoom to target before or alongside the important action, with ease-in/ease-out.  
**Hold:** stable composition long enough to read a form value, menu label or result.  
**Follow:** camera tracks a moving focal region only when it adds comprehension; apply dead zone/hysteresis to prevent jitter.  
**Reveal:** reframe to display the changed state/result.  
**Release:** ease back toward wider context after the viewer understands the result.  
**Cut / speed ramp:** compress waiting and navigation, preserving enough temporal context to trust the demo.  
**Spotlight:** dim non-target area subtly, without making the interface feel broken or hiding context.  
**Callout:** short label tied to a real visible element, not an unsupported marketing claim.

These are design heuristics to validate with actual viewing tests, not universal fixed durations.

## Camera motion constraints

- Use bounded zoom, controlled acceleration and minimum hold time; avoid overlapping contradictory camera intents.
- Smooth cursor independently from source capture when metadata supports it; do not accidentally smooth clicks off their targets.
- Translate focal rectangles through source → edited canvas → output space using one shared transform contract.
- Keep the target inside visible safe bounds and avoid clipping modal contents, text and callouts.
- On dense dashboards prioritize readability over dramatic zoom.
- Have a “quiet” preset with fewer effects, and a reduced-motion mode that favors cuts/short fades over pans.

## Visual design

Default stage: product frame against a restrained background, optional subtle shadow/radius, spacious safe margins. Support dark and light UIs equally: avoid applying color filters that change product colors. Titles and callouts must remain legible on both. Product branding (logo, accent, font choice) belongs in named reusable presets, not hardcoded in rendering.

## Reference storyboard (fictional)

| Time | Screen | Camera | Viewer takeaway |
| --- | --- | --- | --- |
| 0–3s | Full product workspace | Wide, gentle reveal | Recognize the app |
| 3–8s | User starts task | Smooth focus-in | Understand the action |
| 8–11s | Task processing | Brief accelerated segment | Skip uninformative waiting |
| 11–18s | Output panel | Stable zoom + subtle callout | See the capability's value |
| 18–23s | Full result context | Zoom-out | Connect result to product |
| 23–26s | Brand and call-to-action | Clean end card | Remember the product |

The demo must not fabricate completed actions or replace real UI outcomes with synthetically generated ones without disclosure.

## Human review rubric (1–5)

Evaluate: **clarity**, **readability**, **attention guidance**, **pacing**, **visual polish**, **faithfulness to original UI**, **manual effort**. Review on desktop and smartphone. A “looks cinematic” score is insufficient if the feature is not understandable.

## UX anti-patterns

Continuous click zooming; cursor chasing; overdone 3D; unlabelled transitions that imply false continuity; unreadable vertical reframes; mandatory AI setup; massive edit panels at first launch; hidden audio capture; auto-export without preview; forced uploads.

See [product direction](product.md) and [feature specification](feature-spec.md).

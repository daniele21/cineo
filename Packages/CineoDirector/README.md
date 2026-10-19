# CineoDirector — isolated spike

A small, independent Swift 6 prototype for deterministic camera shot suggestions. It **does not** record screens, produce keyframe transitions, detect UI state/results, or render video.

Input: normalized points (0…1) and seconds on the final clip timeline; event kind click/dwell/result. Output: editable focus/zoom hold proposals with reason codes. The result marker is provided by the caller, not discovered automatically.

This package is original Cineo spike code, not imported Orbit/CineScreen code. Compare its behavior against Orbit's `AutoZoomGenerator` during P0/P3 before integrating or adopting it. Do not duplicate the final production motion engine without evidence.

## Run

```sh
swift test --package-path Packages/CineoDirector
```

The initial six tests have been exercised in a Linux environment with Swift 6.2.1. That validates pure planning logic only, **not a macOS video application**.

## Known limitations

- Simple greedy grouping can suppress useful nearby non-overlapping scenes, and dense long recordings require smarter selection.
- No source-vs-output time mapping, animation keyframes, crop/viewport aspect math, accessibility targets or UI inference.
- No compatibility layer with Orbit's ZoomSegment/telemetry schema.
- Defaults are uncalibrated. Treat this as an isolated benchmark candidate, not production design.

# Cineo Brand Kit v1.0 — official source assets

This directory contains the original user-supplied Cineo Brand Kit (20 October 2026), sourced from the private [Cineo Drive Brand Kit](https://drive.google.com/drive/folders/1pKVcXbbnF0cw4IDUU1O6uzZTIK-gyR50?hl=it).

## Original sources

- `cineo.tokens.json`: original design tokens
- `cineo.css`: web-oriented token variables (not used directly by SwiftUI)
- `cineo-symbol-primary.svg`: official reconstructed Cursor Zoom master
- `cineo-logo-horizontal-dark.svg` and `cineo-logo-horizontal-white.svg`: horizontal logos with appropriate contrast
- `cineo-logo-stacked-dark.svg`, `cineo-logo-stacked-white.svg`, `cineo-symbol-flat.svg`, `cineo-symbol-ink.svg`, `cineo-symbol-white.svg`: official format and contrast variants for future surfaces
- `cineo-app-icon.icns.base64`: **exact Base64 encoding of the supplied .icns**, not a new logo; the CLT build decodes into `Cineo Dev.app/Contents/Resources/Cineo.icns`
- `cineo-symbol-primary-256.png.base64`: **exact Base64 encoding of supplied PNG**; decode to `CineoSymbol.png` at app packaging
- `cineo-logo-horizontal-dark.png.base64`: **exact Base64 encoding of supplied PNG**; decode to `CineoWordmark.png` at app packaging

These textual Base64 wrappers were chosen solely to preserve binary assets through the existing GitHub contents integration. They are not downloaded at runtime; packaging and signing are **local and offline**. No code generation, remote CDN, tracking or additional app identity is involved. No fonts are embedded.

## Identity rules

The official **Cursor Zoom** logo consists of four stacked, rounded frames in blue/turquoise/mint, a white central disc and an ocean-blue pointer. Never replace it with just one tile as the primary mark. Keep an exclusion zone of at least one-third of the white-disc diameter. Show the full mark at 48 px or more; at smaller sizes prefer the purpose-made app icon or simplified favicon.

Brand colors (from the token file):

| Token | HEX |
|---|---|
| ink | `#092D43` |
| deep_ocean | `#0B4F6A` |
| ocean | `#107C99` |
| lagoon | `#29BED1` |
| turquoise | `#55D2C8` |
| mint | `#98EACD` |
| frost | `#DDF6F0` |
| cloud | `#F5FAF9` |
| muted | `#5B7180` |

Use Inter Display 700 for display headlines and Inter 400/500/600 for other text **when installed**; otherwise use macOS system text. Do not embed or redistribute fonts. Primary app colors should respect macOS high-contrast, Dark Mode and Reduce Motion rather than hard-coded low-contrast surfaces.

Motion hints: 140 ms fast, 220 ms standard, 360 ms reveal; use purposeful transitions that draw attention without distracting. The phrase "Il focus su ciò che conta." is proposed in the source PDF and is **not legally verified or registered**.

## Brand vs customer video output

The logo, typography and app icon brand **Cineo the editor**, not every customer's exported demo. Do not watermark external recordings or automatically change their project background. Users keep control over exported video style and footage. A future per-project brand kit should be a **separate opt-in project asset** rather than a global Cineo watermark.

## Verification

On the target Mac, from the same repository checkout:

```bash
swift build --package-path Apps/Cineo --configuration release
bash scripts/test-cineo.sh --interactive
/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$HOME/Applications/Cineo Dev.app/Contents/Info.plist"
ls -lh "$HOME/Applications/Cineo Dev.app/Contents/Resources"/{Cineo.icns,CineoSymbol.png,CineoWordmark.png}
```

The app must retain its pinned local signing identity and bundle ID; packaging these assets must not cause repeated macOS TCC prompts. The SVG masters were reconstructed from the chosen visual direction and are not pixel-identical tracings; further optical refinements may be appropriate.

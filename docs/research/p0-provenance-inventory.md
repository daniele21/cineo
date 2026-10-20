# P0 third-party and brand provenance — initial inventory

**Date:** 2026-10-20. **Purpose:** permit a controlled **internal P1 bootstrap** without presenting full redistribution clearance. Inspected upstream at pinned SHA `219c4c8ad9965229aa84271c5201b1b8ad26eb7a`.

| Inventory | Observation | P1 decision |
| --- | --- | --- |
| Orbit root code | `LICENSE`: MIT, copyright Joshua Sattler (2026) | Retain full upstream MIT license in stage / any distributed copy; preserve attribution |
| Inter font | `Reco/Fonts/Inter-OFL.txt`: SIL Open Font License 1.1 | Retain OFL notice and reserved-name terms as required; candidate for reuse |
| JetBrains Mono font | `Reco/Fonts/JetBrainsMono-OFL.txt`: SIL Open Font License 1.1 | Retain OFL notice and reserved-name terms as required; candidate for reuse |
| App icon | `Reco/Reco.icon`, `Reco/Assets.xcassets/Reco.appiconset` | Brand not approved; Cineo bootstrap turns off upstream app icon; replace with own design before release |
| Menu-bar logo | `Reco/Assets.xcassets/MenuBarIcon.imageset` | Bootstrap replaces primary menu bar image use with an SF Symbol; inventory remaining references |
| Other image assets | ButtonIcons, LineIcons, Theme, ToolbarIcons folders | Inspect individual source and notices before public distribution |
| Sparkle updater | `2.9.6` in `Package.resolved` | Bootstrap removes feed and retains disabled key; not a Cineo auto-update mechanism |
| KeyboardShortcuts | `3.0.1` | Dependency retained in stage; actual upstream license must be checked before distribution |
| EventSource | `1.5.1` | License review needed |
| Apple swift-atomics / collections / log / nio / system | Versions pinned in `Package.resolved` | Standard library ecosystem; individually validate license and notices before release |
| Model Context Protocol swift-sdk | `0.12.1` | Agent bridge **disabled in bootstrap**; dependency may still be linked until feature removal |
| User settings/migration | Upstream's ContainerMigration reads old sandbox data | Cineo overlay disables automatic legacy import to prevent cross-product data migration |
| URL/style registration | Upstream `reco` URL scheme, `recostyle` file association | Cineo overlay unregisters upstream scheme/file associations |

**Source inventory evidence:** Orbit [root LICENSE](https://github.com/diip3sh/orbit/blob/219c4c8ad9965229aa84271c5201b1b8ad26eb7a/LICENSE), [Inter OFL](https://github.com/diip3sh/orbit/blob/219c4c8ad9965229aa84271c5201b1b8ad26eb7a/Reco/Fonts/Inter-OFL.txt), [JetBrains OFL](https://github.com/diip3sh/orbit/blob/219c4c8ad9965229aa84271c5201b1b8ad26eb7a/Reco/Fonts/JetBrainsMono-OFL.txt), and [SwiftPM pins](https://github.com/diip3sh/orbit/blob/219c4c8ad9965229aa84271c5201b1b8ad26eb7a/Reco.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved).

## Restrictions

- This is an **initial inventory**, not a legal assessment or clearance for binary distribution. Internal compile/smoke only.
- The stage still uses much of Orbit's interface and media assets. **Never call it a fully branded Cineo release** or distribute the unsigned test artifact to end users.
- Before a public/paid binary, provide per-dependency license texts and artwork provenance; replace remaining upstream visual branding and review user preference/data paths.
- Changing the project bundle ID must not silently cross-access original Orbit preferences, auth tokens, appcast, or local listeners.
- If upstream pins change, regenerate this inventory and recheck overlays.

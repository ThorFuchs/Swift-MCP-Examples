# Research Explorer — Liquid Glass & Editorial Design System

**Track C / visual-polish branch:** `track-c/liquid-glass-polish-2026-11-23`  
**Platform:** native SwiftUI on macOS 27 / Swift 6.4, Swift 6 language mode  
**Status:** source changes staged; native compilation, actual screenshots and accessibility review pending.  
**Scope:** example-app presentation only. No Core/HTTP SDK or wire-protocol changes.

## Design thesis

**Read the article. Trust the provenance. Explore the protocol when curious.**

Research Explorer should feel like a quiet native research instrument, not a
dashboard of translucent cards. The three persistent destinations remain
**Research**, **Server**, and **Activity**. Article, outline, evidence, pinning
and real MCP inspector have distinct responsibilities. Offline demo remains
the startup source; **nothing opens a connection or starts a listener on launch**.

## Apple HIG and Liquid Glass boundaries

Apple's [Materials HIG](https://developer.apple.com/design/human-interface-guidelines/materials)
describes Liquid Glass as a functional/navigation layer, not the content
background. The app therefore:

- Uses the native `NavigationSplitView`, sidebar `List`, system toolbars,
  grouped controls and SwiftUI `.glass` / `.glassProminent` button styles
  for selected interactive navigation/actions.
- **Never paints the reading body, provenance or metadata panels with custom
  Liquid Glass**. These use dynamic opaque AppKit-backed system colors to
  preserve text contrast and long-form legibility.
- Lets the system respond to Reduce Transparency, Increase Contrast and
  reduced motion for standard chrome. No bespoke glass animation, forced blur,
  shadow stack or timed motion is introduced.
- Uses native SF Symbols, system accent color and semantic roles instead of
  a hard-coded light-only palette or unsupported imitation window chrome.

References: [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass),
[Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views),
[Typography HIG](https://developer.apple.com/design/human-interface-guidelines/typography).

**HIG-aligned intent is not a certification.** Visual, VoiceOver, focus,
keyboard and accessibility-settings verification must still occur on macOS.

## Source-owned design tokens

`Sources/ResearchExplorerApp/Design/ExplorerDesign.swift` is the sole
source of app-level visual tokens and shared primitives.

| Token family | Source of truth | Usage |
| --- | --- | --- |
| `Space` | 4 / 8 / 12 / 16 / 24 / 32 / 48 pt | Consistent relationships and breathing room |
| `Radius` | 10 / 18 / 24 pt | Opaque paper/tonal content containers |
| `Layout` | 740 pt reading measure, 1,100 pt content width, 242 pt sidebar, 238/328 pt auxiliary columns | Adaptive editorial composition |
| `Palette` | macOS semantic `NSColor` + system `Color.accentColor` | Automatic light/dark appearance, genuine system tint |
| `Type` | Serif display/article headings; UI system sans for controls; monospaced technical details | Clear editorial/technical hierarchy |
| `ExplorerPanel` | Opaque paper + semantic hairline | Legible app content, *not* Liquid Glass |
| `ExplorerScreenHeading`, `ExplorerPill`, `ExplorerMetricTile` | Reusable native SwiftUI pieces | Research, Server, Activity, Settings |

The existing **Article text size** control continues to govern only the
reader, clamped to 14–26 pt; macOS does not provide the same system Dynamic
Type settings as iOS. Text selection and named accessibility controls remain.

## Screen treatment

**Research:** clear source badge, generous first-run invitation, editorial
results and an offline action deliberately initiated by the user. Errors,
truncation and live/offline distinctions remain explicit.

**Reading:** source and revision visible above the title; stable, readable
measure and ample leading; native section navigation and evidence affordance.
A pinned snapshot remains pinned until an explicit revision action.

**Server:** source selection, actual local-host phase, guarded explicit
Start/Stop/Restart, real HTTP client journey and opt-in metadata inspector.
Metrics mean **eligible tool-handler calls only**, never arbitrary network
requests. Local development access does not imply a production OAuth server.

**Activity:** real retained metadata, native filters, selectable redacted
details, user-triggered export; no payload/body/secret fields invented.

**Settings:** system appearance and independent reading-size preview.
Default window 1,440×900, minimum 820×620; test small and large windows.

## Local, CI-free review

This design branch is intentionally **not opened as a pull request**, so
there is no additional GitHub Actions workload while billing is blocked.

On a Mac Studio with a fresh checkout of the design branch:

```bash
bash Scripts/qualify-re04-local.sh
bash Scripts/snapshot-design-local.sh
```

The second script runs the actual `ReaderSnapshotTests` at ten review states
and captures their PNGs outside the repository. It does **not** provide
pixel-perfect evidence of system Liquid Glass: the known snapshot method
omits window-server sidebar materials/selection vibrancy. Capture real
window screenshots separately for visual approval.

Native acceptance checklist (not yet claimed):
- [ ] Clean Swift 6.4.2 / Xcode 27.2 / macOS 27 app build and all example tests.
- [ ] Wide 1440 pt and compact 900/820 pt, light and dark, high contrast.
- [ ] System Reduce Transparency and Reduce Motion; controls stay recognizable.
- [ ] VoiceOver labels/order, keyboard shortcuts and logical focus.
- [ ] Research initial offline launch sends no network request or listener.
- [ ] Revision changes, unavailable citation metadata and truncated text legible.
- [ ] Server host actions and real MCP inspector still pass RE-04 tests.
- [ ] Native window screenshots reviewed in addition to layer-rendered review images.
- [ ] No public release or SDK compatibility claim until Tracks A/B finish.

The standalone RE-03 screenshot files in `Docs/Screenshots/RE-03` remain
historical evidence, not claimed as renders of the new design branch.

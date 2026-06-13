# Screenshots — capture guide

This folder holds the marketing screenshots shown in the
[root README](../../README.md). The README gallery is already written and points
at the **exact filenames** below — capture each shot, save it here under the
matching name, then uncomment the gallery block in the README.

> Capturing requires a Mac with Xcode (watchOS + iOS simulators). It can't be
> done from the web/Linux session that scaffolded this folder.

## The shots

Capture them from a **single, realistic demo match** (e.g. a competitive
three-setter) so scores and stats stay consistent across images. Pick **one
primary theme** — `Classic` or `Hard Court (Night)` — for the hero and watch
shots so the gallery feels cohesive; only `06-themes.png` shows multiple themes.

| # | Filename | What to capture | Screen (source file) |
|---|----------|-----------------|----------------------|
| 1 | `01-hero-watch-iphone.png` | **Hero composite** — Apple Watch live scoreboard next to the iPhone live scoreboard/stats, both framed, side by side. The lead image: tells the watch→phone story at a glance. | Watch `DeuceMate/DeuceMate Watch App/ContentView.swift` + iPhone `DeuceMate/DeuceMate/Views/LiveScoreboardView.swift` / `DeuceMate/DeuceMate/Views/PointsGraphView.swift` |
| 2 | `02-points-momentum-graph.png` | iPhone **points-momentum graph** with the heart-rate and steps overlays on, set bands and outcome markers visible. The flagship "wow" shot. | `DeuceMate/DeuceMate/Views/PointsGraphView.swift` |
| 3 | `03-match-stats.png` | iPhone **match stats** tab — the Me-vs-Opponent split bars (serve %, break points, Aggression Index, rally depth). | `DeuceMate/DeuceMate/Views/MatchDetailView.swift` |
| 4 | `04-watch-scoreboard.png` | **Clean solo** Apple Watch live scoreboard mid-match — score rows, momentum strip, heart-rate badge. | `DeuceMate/DeuceMate Watch App/ContentView.swift` |
| 5 | `05-pulse-coach-hr-zones.png` | iPhone **PulseCoach** — win % by HR zone bars + the zone-banded HR timeline. | `DeuceMate/DeuceMate/Views/PulseCoach/PulseCoachSection.swift` |
| 6 | `06-themes.png` | *(Optional)* a strip of the watch scoreboard across the five court-inspired themes. | `DeuceMate/DeuceMate Watch App/AppTheme.swift` |

## How to capture

1. Run the iPhone scheme on a Pro-class iPhone simulator and the watch scheme on
   an Apple Watch (Series 9 / Ultra) simulator; play out the demo match so the
   live screens, graph, and stats are populated.
2. Save each simulator screen with **⌘S** (Simulator → File → Save Screen), or
   use Xcode's Debug → View Debugging for a clean frame.
3. Wrap bare simulator PNGs in official **Apple device frames** (Apple Design
   Resources) — unframed screenshots look unfinished.
4. Save each file here under the exact name in the table above (PNG).

## Finish

In [`README.md`](../../README.md), delete the "Coming soon" note and remove the
`<!-- ... -->` markers around the gallery block so the images render. Commit and
push to the same PR branch — the open pull request picks the images up
automatically.

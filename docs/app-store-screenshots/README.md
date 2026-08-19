# App Store screenshot upload package

Two kinds of asset live here:

- **Advertisement frames** ([`iphone-6.9-marketing/`](./iphone-6.9-marketing/)) —
  three art-directed frames with headlines and device framing, generated from
  [`marketing/`](./marketing/). These lead the gallery.
- **Raw product screenshots** (`iphone-6.9/`, `watch-45mm/`) — captured 6 August
  2026 from the current codebase and physical Watch hardware, with no device
  frames, marketing overlays, or alpha channel.

## iPhone upload order (8 slots)

The App Store shows roughly the first three screenshots in search results, so
the ad frames take those slots and the raw captures follow for anyone who taps
through. All eight are 1320 x 2868 with no alpha — a set must be one size.

| # | File | Kind |
|---|------|------|
| 1 | `iphone-6.9-marketing/01-watch-and-iphone.png` | ad — Watch scorer + iPhone companion |
| 2 | `iphone-6.9-marketing/02-match-analysis.png` | ad — momentum graph |
| 3 | `iphone-6.9-marketing/03-ai-coach.png` | ad — AI coach hand-off |
| 4 | `iphone-6.9/01-match-overview.png` | raw |
| 5 | `iphone-6.9/02-points-momentum.png` | raw |
| 6 | `iphone-6.9/03-match-stats.png` | raw |
| 7 | `iphone-6.9/04-coaching-insights.png` | raw |
| 8 | `iphone-6.9/05-match-archive.png` | raw |

Slot 1 exists because nothing in the previous all-iPhone gallery told a shopper
browsing on an iPhone that this is an **Apple Watch** app — the single most
important fact about the product.

The Watch set keeps its four raw captures unchanged: Apple shows those in the
Watch section, where framing a Watch inside a drawn Watch adds nothing.

## iPhone 6.9-inch

Directory: [`iphone-6.9/`](./iphone-6.9/)

All five PNGs are **1320 x 2868**, portrait, with no alpha. They were captured
on the iPhone 17 Pro Max simulator using the latest completed match with point
statistics, `44ACB61B-BBF0-444C-86BC-2A0125E0DF6D` (5 August 2026, 3-6 1-6,
124 tracked points), from `deucemate_archive_2026-08-06.json`.

1. `01-match-overview.png` - completed score, result, points split, and graph
2. `02-points-momentum.png` - full-screen point momentum, authentic health
   overlays, and outcome filters
3. `03-match-stats.png` - outcome and serve comparisons
4. `04-coaching-insights.png` - match duration and data-driven coaching
5. `05-match-archive.png` - match history and statistics availability

This one 6.9-inch set satisfies the iPhone screenshot-size requirement; do not
mix in the older 6.3/6.5-inch files from `docs/screenshots/` for this slot.

## Apple Watch

Directory: [`watch-45mm/`](./watch-45mm/)

All six PNGs are **396 x 484**, portrait, with no alpha. All were captured
manually on a physical Apple Watch Series 7 45 mm — the four new 1.1.0 shots
on 19 August 2026, the two carried over on 6 August 2026. None are simulator
captures.

1. `01-watch-home.png` - start screen: remembered setup row and the
   Points / Health / Pulse tracking chips
2. `02-watch-match-setup.png` - the Singles/Doubles + format sheet
3. `03-watch-live-scoreboard.png` - the primary live-scoring experience
4. `04-watch-changeover-prompt.png` - the set-complete changeover modal
5. `05-watch-changeover-sticky.png` - the sticky ends reminder that follows it
6. `06-watch-past-matches.png` - synced match history and statistics access

Reordered for 1.1.0 to run in the order a player meets them — set up, score,
change ends, review — rather than leading with the scoreboard. Items 1, 2, 4
and 5 are the 1.1.0 features; `03` and `06` carry over unchanged from the
6 August set (`03` is the former `01-watch-live-scoreboard.png`, renamed).

> **`03-watch-live-scoreboard.png` is a build input.** The App Store ad frame
> `01-watch-and-iphone.png` composites it, so `marketing/build.sh` reads it by
> path. Renaming it again breaks that build — loudly, at the staging `cp`, not
> silently — so update `marketing/build.sh` and its README in the same change.

All six were uploaded into the same 396 x 484 Watch set.

## Validation performed

Every PNG was opened for a visual check and verified with `sips` for its exact
pixel dimensions and `hasAlpha: no`. The iPhone capture UI test passed against
the seeded real archive; the current Watch images are physical-device captures.

The supplied full-fidelity archive restores the match's recorded steps,
calories, and heart-rate samples alongside its score and point outcomes. Those
real measurements are visible in the graph and Pulse Coach capture; no health
values were generated or invented for the screenshots.

These folders contain the screenshots uploaded to App Store Connect on 6 August
2026. The separate hardware demo/review video described in
`SUBMISSION_REVIEW.md` still needs to be recorded on the physical iPhone and
Apple Watch and attached in App Store Connect.

# App Store screenshot upload package

Captured on 6 August 2026 from the current codebase and physical Watch hardware.
These are raw product screenshots with no device frames, marketing overlays, or
alpha channel. They were uploaded to App Store Connect in filename order.

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

All four PNGs are **396 x 484**, portrait, with no alpha. They were captured
manually on a physical Apple Watch Series 7 45 mm.

1. `01-watch-live-scoreboard.png` - the primary live-scoring experience
2. `02-watch-match-format.png` - match-format setup
3. `03-watch-home.png` - start, settings, and guide entry points
4. `04-watch-past-matches.png` - synced match history and statistics access

All four were uploaded into the same 396 x 484 Watch set.

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

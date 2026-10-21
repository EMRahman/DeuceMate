# Try Me watch replica — handoff for the next session

**Branch / PR:** `feature/try-me-watch-replica` → PR #140 (docs/website only, no Swift).
**Goal (from the owner):** the website's "Try it" (`docs/website/try.html`) should be a
1:1 replica of the Apple Watch app, every screen working inside a JS watch window.
Heart rate, calories, steps and the compass heading are invented; everything else
should match. **Status: close, not exact.** The owner will review and send follow-ups.

## What exists

| File (`docs/website/assets/`) | Role |
|---|---|
| `watch-demo.js` | The live match (JS port of `ScoringEngine`, post-point sheet, stats overlay, ContentView layout: court, HR, compass, reminder, completion panel, swipe/pointer scoring). Exposes `root.__deuceMateApi` (`start`, `restore`, `snapshot`, `clear`, `configure`, `hasProgress`, `modalKind`, `hooks.change`, `hooks.endMatch`) and `window.DeuceMateStatsUI`, `window.DeuceMateWatchUI`, `window.DeuceMateScoring`. `appMode` = `data-app` attribute (try.html only; the compact practice watch in `setup.html` is unchanged). |
| `watch-demo-app.js` | The shell around the match: Health prompt, Home, Match Setup, Settings, Birth Year, Guide, warm-up / who serves / court side, alerts, status bar, sheet stack. State lives in `window.DeuceMateShell`. Themes + `--pt` (point unit) are set here. |
| `watch-demo-history.js` | Past Matches list, swipe-to-delete, detail (resume / End at Current Score / set filter / durations), seeded starter matches (`simulate()` plays seeded matches on the real engine). |
| `watch-demo-guide.js` | Animated guide (port of `WalkthroughSession`) and the first-use offer. |
| `watch-demo.css`, `watch-app.css` | Styles. Later blocks deliberately override earlier ones ("measured from the running app" sections at the end of each file). Sizes are `calc(N * var(--pt))` where 1 pt = screen width / 184. |

Design rules worth keeping: `data-shell-open` on the root blocks all scoring while a non-match screen is up; Track point outcome is **off by default** (as on the watch); scoring is swipe-only; nothing is persisted.

## How parity was measured (scratch scripts are gone — rebuild if needed)

1. **Simulator:** Xcode 27.1, watchOS 27 runtime, device *Apple Watch SE 3 (44mm)* = 184 × 224 pt (there is no 45 mm).
2. **Build:** `HomeView.swift:1003` fails on this toolchain ("ambiguous use of 'opacity'"). Build from a scratch copy with `.background(background).opacity(...)` instead; do not change the repo for it.
3. **Drive the real app** with a temporary XCUITest in the scratch copy (see `LiveMatchScreenshotTests` / `SetupGuideScreenshotTests` for the helper style): launch, `crown` to scroll, tap by label or coordinate, write `XCUIScreen.main.screenshot().pngRepresentation` **and** `XCUIApplication().debugDescription` to disk. The `.txt` dump gives exact element frames in pt — the most useful ground truth. Tap by *normalized coordinates* on the post-point sheet (labels aren't hittable): step 1 Winner ≈ (0.5, 0.65), step 2 first pill ≈ (0.28, 0.55); close button ≈ (0.15, 0.13); stats swipe = `press(forDuration: 0.1, thenDragTo:)` from x 0.08 to 0.97.
4. **Replica side:** Playwright + headless Chromium. Force the frame to 216 px wide (`.watch-frame{width:216px!important}`) so `.watch-screen` is 184 × 221 css px, screenshot the element at deviceScaleFactor 2 (≈ 368 × 448), diff against the simulator PNG in a canvas (mean |Δ|/255). Last results: who-serves 13.7, scoreboard 12.6, home 13.5, post-point step 2 17.6, empty stats 18.4, match setup 20.1, warm-up 21.3, Settings 21.8, history 19.5, guide 25.3, post-point step 1 25.4, detail 28.3.

## Measured facts about the real app (use these, don't re-derive)

- Home (pt): Start button 164×44 at (10, 36.5); setup row 164×32 at y 90.5; strip 164×25.5 at y 132.5; icon row y 168, 44 tall. Close button 34×34 at (10.5, 12.5).
- Scoreboard: Me/Op name text y 62 / 104.5 (rows 36.5 pt tall, 6 pt gap); cells and point badge pack **left** after the 30 pt name (no spacer); HR heart y 161; footer y 207; hint lines y 26 / 38.
- Text styles run larger than their nominal sizes on this OS: footnote ≈ caption2 ≈ 14.5 pt, caption ≈ 16 pt, headline 17 pt; fixed `.system(size:)` text is literal (history rows 11/12/10 pt).
- Settings switch is 36 × 22 pt; Birth Year row is a 51 pt rounded button; filter pills on stats are 82 × 51 pt capsules and always shown ("All | S1" even for one set).
- Past Matches rows are 180 × 47 pt at x = 2, starting y = 55. RootModal/setup sheets are opaque black; Settings/Guide/History/detail are translucent system sheets.
- Fresh install: first screen is the "Learn the controls" offer; Health is "Ask" until decided.

## Open items (best next steps)

1. Pixel gaps still non-zero everywhere (mostly font rendering/blur). Biggest: guide (25), detail (28), post-point step 1 (25), Settings (22).
2. Stats rows with real data matched by measurement only — capture a real tracked match and overlay (needs ~6 categorised points; use the coordinates above).
3. Compare Past Matches rows for a *completed* match and the "Score Only"/"Match Stats" tags; delete swipe; empty state.
4. 45 mm layout not separately checked (`--pt` scales from width, so the only difference is aspect/proportions).
5. Health permission pages: the read/write item lists are a guess (system sheet isn't scriptable in XCUITest).
6. Doubles flows, tiebreak scoreboard superscripts, compass badge and the sticky ends-switch banner were checked against the repo's 45 mm App Store screenshots by eye, not by overlay.
7. "Test iPhone speaker" is simulated by design.

## Review state

Codex's two P2 findings on PR #140 are fixed in the second commit (pointer capture deferred until a drag; stats swipe allowed after the match ends) and replied to. Re-run `@codex review` if desired.

## Quick verification checklist

Open `docs/website/try.html` in a browser: Health prompt → Review/Next/Allow; Settings toggles; Start Match flow; swipe up/down/left/right; double-click the scoreboard (2nd-serve badge); end a tracked match and swipe right for stats; Past Matches → detail → Resume; Guide → Animated guide (all nine steps finish and close itself). Then `setup.html`: the compact practice watch must still work.

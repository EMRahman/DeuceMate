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
- Real fresh install: first screen is the "Learn the controls" offer; Health is "Ask" until decided. **The demo deliberately differs (owner decision, third session):** it starts with Health already authorised and skips the launch-time Health Access sheet (`S.health = "authorized"`, `api.configure({ health: true })`, no `requestHealth(false)` in `S.boot`), so visitors land on Home with Health = On and live HR/kcal/steps. The permission pages still exist if Health is ever set back to `notDetermined`.

## Open items (best next steps)

1. Pixel gaps still non-zero everywhere (mostly font rendering/blur). Biggest: guide (25), detail (28), post-point step 1 (25), Settings (22).
2. Stats rows with real data matched by measurement only — capture a real tracked match and overlay (needs ~6 categorised points; use the coordinates above).
3. Compare Past Matches rows for a *completed* match and the "Score Only"/"Match Stats" tags; delete swipe; empty state.
4. 45 mm layout not separately checked (`--pt` scales from width, so the only difference is aspect/proportions).
5. Health permission pages: the read/write item lists are a guess (system sheet isn't scriptable in XCUITest).
6. Doubles flows, tiebreak scoreboard superscripts, compass badge and the sticky ends-switch banner were checked against the repo's 45 mm App Store screenshots by eye, not by overlay.
7. "Test iPhone speaker" is simulated by design.

## Owner follow-ups (second session)

- **Guide icon:** the website's `ICONS.book` was a closed-book path; it is now a filled open book. The watch app needs **no** change: `book.fill` is already the open book (`book.pages.fill`, the notebook, is the one to avoid — rendered both in AppKit and on the SE 3 simulator).
- **Footer 🔥/🕐:** measured against the SE 3 (44mm) simulator, the whole real line is ~0.84× the nominal 10 pt, emoji ~0.6× of the nominal size. `watch-demo.css` now uses 8.4 pt text, `.ft-ic` 0.73em, `.ft-dot` spacing and a −2 pt top margin; compared at 3× against the simulator crop and by ink-extent measurement (footer rows 415–430 vs 416–430 device px, flame 12 vs 11 px wide).
- **Live stats scroll:** the watch's `MatchStatsView` is one `ScrollView` (title, set pills and rows scroll together), but the replica pinned the header and scrolled only a ~93 px body, so on a real tracked match almost nothing was visible/scrollable. In app mode the whole `.stats-overlay` now scrolls (`overscroll-behavior: contain`, hidden scrollbar); mouse drag and ↑/↓/PgUp/PgDn scroll it on desktop. Verified in iOS Simulator Safari (iPhone 17, scratch XCUITest swiping) on a 10-point tracked match: the overlay scrolls to its end, the page doesn't move. On that content the old code also scrolled the 93 px body, so the fixed header — not touch handling — was the real defect.
  Traps found while verifying (both fixed): `display:block` on the overlay must be `:not([hidden])` or it covers the scoreboard when closed; and the mouse-drag handler must ignore `pointermove` unless button 1 is down, or a stale drag state resets `scrollTop` to 0 on any hover. Final checks: Chromium (short content 19/19 px; 10-point match 1287 px — wheel, drag, ↑/↓/PgDn, hover keeps position, page unmoved) and iOS Safari (1062/1189 px, page unmoved).
- Tooling: iOS Safari checks used `xcrun simctl openurl` + a scratch UI test in a copy of the repo; Playwright's Chromium (+ WebKit) via a scratch `npm i playwright`; the simulator capture used a scratch XCUITest in a copy of the repo (HomeView.swift:1003 still needs the `.opacity` workaround on this toolchain).

## Double fault + match simulation check (third session)

- **Double Fault option:** it is offered only when the *server lost on a second serve* (`pending.isSecondServe && winner != server` — identical in `PointCategorySheet.swift` and the replica). If the opponent is serving and you double-click then lose, there is no Double Fault (the opponent won their own serve); if you win that point it *is* offered ("Won — Their serve"). Reproduced on both: double-click (2nd badge) + swipe down on my serve → "Lost — Your serve 2nd" with Double Fault. The one real replica gap found: the double-click window was 350 ms, so a slower mouse double-click registered as two single taps (no 2nd serve ⇒ no Double Fault); it is now 450 ms.
- **Engine parity:** six seeded matches (standard ×2, superTiebreak, quick4Games, bestOf3FullFinalSet, perpetualSuperTiebreak; ~20 checkpoints each, with 2nd serves, double faults, all outcomes/shots) were generated from the replica and replayed through Core (`ScoringEngine` + `MatchStatsSummary`, scratch Swift package). Scores, server, completion, and ~30 stats fields per side (plus rally depth and score states) matched at every checkpoint — 0 differences. Tiebreak-only formats must be seeded like `prepareTiebreakOnlySet()` (done in `freshState`).
- **UI parity:** a 5-point tracked match was driven on the SE 3 simulator and in the replica; the live stats text matched (points won 3/5/2, winners 3, forced 1, DF 1, aggression 3/3, own errors 1/2, 1st serve in 3/5, 1st serve win 2/3, returns vs 1st 1/3, 30-All). Post-point sheet geometry measured from the sim (buttons 84×51 pt at x 6/94, y 65/120; Undo 163×51 at y 177) and matched to 0.2 pt; button text is 14.5 pt and wraps like the watch.
- **Watch-vs-replica matches (same script, driven by coordinates on the SE 3 sim, by label in the replica):** (1) Quick 4 Games, opponent serves first, 13 points / 4 second serves / 1 DF, played to the end (0–3); (2) Best of 3 Club, 30 points / 12 second serves / 1 DF (games 1–2, points 30–0, opponent serving). The watch's accessibility dump of the stats `ScrollView` lists every row (with absolute y) in its top snapshot, so the *complete* stats page was diffed row by row against the replica's: Quick 4 = 55 rows, Best of 3 = 60 rows, **identical** (values, order, labels). Final live-score screens and every stats row captured from the watch (winners, UE/FE, DF, aggression, 1st/2nd serve in/win, DF rate, return, break points, big/normal points, rally depth @ Rally/@ S+1/@ Return, score states) equal the replica and Core's numbers. The earlier "@ Serve 0/1 vs 75% 3/4" discrepancy was my first manual run tapping different pills on each side, not a code difference. Step-2 pill geometry was off by ~2 pt and the full-width pill wasn't inset; both now match the watch exactly (Ace 6,71.5 84×51; S+1 94,71.5; Rally 10.5,126.5 163×51).
- **Third match (Super Tiebreak, 16 points, 6 second serves incl. a DF) + a mid-match stats checkpoint at point 8:** final stats page 54 rows identical; the checkpoint page 51 rows identical except one row where the watch's accessibility dump also lists the live-scoreboard footer text (🔥 kcal · 🕐 time) that sits underneath the stats overlay — not a stats difference. Both apps skip the warm-up screen for tiebreak-only formats and go straight to "Who is serving first?". Gotcha for scripts: "Best of 3 Sets (Club / League)" has details text containing "Super Tiebreak", so match format buttons with BEGINSWITH / `^`.
- **Double-click on the watch:** `onTapGesture(count: 2)` uses the system's own timing (XCUITest `doubleTap()` toggled the 2nd badge and produced the 2nd-serve sheet in both matches), so there is nothing to tune there (two separately-issued taps with 150–800 ms requested gaps never registered on the watch — each automated tap carries more latency than the window — so a human-speed double-tap can't be measured by XCUITest); only the replica's JS window needed widening.
- **Measured on the watch (SE 3 sim):** two XCUITest taps issued back-to-back land 0.37–0.48 s apart (logged), and in 6/6 pairs the watch did **not** set the 2nd-serve badge, while `doubleTap()` (fast) always did. So the watch's real double-tap window is below ~0.37 s; the replica's 450 ms is intentionally *more lenient* than the watch (a mouse double-click should never be rejected), never stricter, so a double-click the watch accepts is always accepted in the replica.
- **Double-click window (450 ms) verified in the replica:** 150/300/420 ms gaps toggle the 2nd-serve badge; 600 ms does not (the old 350 ms window would have rejected 420 ms).
- Labelled sheet buttons on the watch are not hittable in XCUITest (infinite frames): tap by normalised coordinates (step 1: 4-button layout DF/UE at y .40, FE/Winner at y .65; 3-button layout UE/FE at y .40, Winner full-width at y .65; step 2: pills at y .433, third pill full-width at y .68).
- Note for scripting the real watch: with 3 buttons (won point, or lost on a first serve) the grid is Unforced/Forced over a full-width Winner; Double Fault appears as a 4th, first button only on a lost second serve.

## Review state

Codex's two P2 findings on PR #140 are fixed in the second commit (pointer capture deferred until a drag; stats swipe allowed after the match ends) and replied to. Re-run `@codex review` if desired.

## Quick verification checklist

Open `docs/website/try.html` in a browser: Health prompt → Review/Next/Allow; Settings toggles; Start Match flow; swipe up/down/left/right; double-click the scoreboard (2nd-serve badge); end a tracked match and swipe right for stats; Past Matches → detail → Resume; Guide → Animated guide (all nine steps finish and close itself). Then `setup.html`: the compact practice watch must still work.

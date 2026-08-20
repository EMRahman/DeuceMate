# Interactive Browser Demo — Watch-App Parity Plan

**Status:** All phases shipped, including the optional Phase 6 (tracking foundation + second-serve context; the post-point categorisation sheet; the live stats view; the completion panel, changeover overlay, and fit-&-finish polish; the copy refresh; doubles' 4-player service rotation).
**Audience:** an AI coding agent implementing this incrementally (phase by phase,
one PR per phase). The plan is deliberately prescriptive — exact strings, colors,
ordering, and conditional rules are spelled out so the implementer does not need
to re-derive them from the Swift sources (though every rule cites its source).
**Verification:** manual, by the repo owner, in a browser — each phase ends with
an acceptance checklist written for that purpose. There is no JS test
infrastructure and none should be added; pure logic is exposed on `window.*`
globals so it can be spot-checked from the browser console.
**Line references** were verified against the code on 2026-07-11 — re-grep for
the symbol if a reference has drifted.

---

## Why

The "Interactive demo" on the product site (`docs/try.html` +
`docs/assets/watch-demo.js`/`.css`) is the site's main conversion tool — it is
what a visitor plays with before deciding to install. Today it faithfully ports
the **scoring engine** (all six formats, tiebreaks, server rotation, undo) but
none of the app's headline differentiator: **post-point outcome tracking** and
the statistics that fall out of it. A visitor sees a plain score counter and has
no reason to believe the "full match stats / coaching" claims on the index page.

Goal: make the demo a faithful miniature of the *watch experience* — the
second-serve gesture, the post-point categorisation sheet, and a live stats view
— while staying a dependency-free static page.

---

## Current state vs. the watch app (gap matrix)

| Feature | Watch app behaviour | Demo today |
|---|---|---|
| Scoring engine (6 formats, tiebreaks, server rotation, side changes) | `ScoringEngine.swift` | ✅ ported faithfully (`watch-demo.js` top half) |
| Score display (set cells, point badge, AD, super-TB hiding rules) | `ContentView.swift` | ✅ ported |
| Undo | full game-state rollback incl. pending categorisation | ✅ ported (Phase 1) — rolls back score, 2nd-serve flag, and stats together |
| Momentum strip (last 8 points) | shown while match in progress, hidden when complete | ✅ ported (Phase 4) |
| Second-serve context | double-tap score card → yellow "2" badge on server ball; drives Double Fault availability | ✅ ported (Phase 1) |
| Break-point capture | computed per point, stamped on the point record (no scoreboard badge) | ✅ ported (Phase 1/2) — stamped on each `PointStat` |
| Post-point categorisation sheet | 2-step modal after every point when tracking on | ✅ ported (Phase 2) |
| Point records (`PointStat`) | outcome, ending shot, 2nd-serve, BP, score snapshot per point | ✅ ported (Phase 1/2) |
| Live stats view | swipe right → sectioned Me/Opp comparison | ✅ ported (Phase 3) |
| Match-complete panel | "You Won! 🏆" / "Opponent Won" + Match Complete + stats affordance | ✅ ported (Phase 4) |
| Changeover prompts | blocking "OK" overlay with 🔁 symbol + reason at every changeover boundary (not setting-gated) | ✅ ported (Phase 4) |
| First-game gesture hint | faint "↑ Win ↓ Lose / ← Undo → Stats" until first game ends | ✅ ported (Phase 4) |
| Swipe live-preview | target row lights green/red while finger is down | ✅ ported (Phase 4) — touch drag + a preview-only mouse-drag equivalent for desktop |
| Doubles (4-player rotation) | full support | ✅ ported (Phase 6) |
| HR / compass / calories / themes / phone sync | various | ❌ out of scope for the demo (see Non-goals) |

---

## Ground truth — where each behaviour lives in Swift

The implementer should treat these files as the specification of record. Do
**not** modify any Swift file for this feature; this is a docs/site-only change.

| Source | What to mirror |
|---|---|
| `DeuceMate/Packages/DeuceMateCore/Sources/DeuceMateCore/Models/PointStat.swift` | `PointOutcome` (order + labels + `userSelectable`), `EndingShot`, `GameScoreSnapshot`, `PendingPointInfo`, `PointStat` fields |
| `DeuceMate/DeuceMate Watch App/PointCategorySheet.swift` | the entire 2-step sheet: banner, button rows, conditional Double Fault, commit-delay checkmark beat, ending-shot pill routing, Undo point button |
| `DeuceMate/DeuceMate Watch App/ScoreViewModel.swift` — `selectOutcome` (~L1165), `commitEndingShot` (~L1180), `cancelOutcomeSelection` (~L1188), `commitPointStat` (~L1202), `toggleSecondServe` (~L1239), `autoRecordPointStat` (~L1257) | pending-point lifecycle, guards, uncategorised auto-record when tracking is off |
| `DeuceMate/DeuceMate Watch App/ContentView.swift` — score rows (~L400–535), match-complete panel (~L225–264), first-game hint (~L132–142), live-preview overlay (~L416–430), double-tap scope (~L163–169) | scoreboard anatomy and gestures |
| `DeuceMate/DeuceMate Watch App/MatchStatsView.swift` | stats view section order, headers, empty-state copy |
| `DeuceMate/Packages/DeuceMateCore/Sources/DeuceMateCore/Stats/MatchStatsSummary.swift` | the exact stat derivations (serve/return/BP/errors/pressure/rally/score-states) |
| `DeuceMate/DeuceMate Watch App/MatchStats.swift` (~L32–48) | outcome tint colors, `MatchFormat.displayLabel` |
| `DeuceMate/DeuceMate Watch App/HomeView.swift` — format sheet (~L399–483), server selection (~L218–268) | setup labels and flow |
| `DeuceMate/Packages/DeuceMateCore/Sources/DeuceMateCore/Scoring/ScoringEngine.swift` (~L340–552) + `ScoreViewModel.swift` (~L1111–1132) | changeover symbols + reason strings |
| `docs/USER_GUIDE.md` §"Point Outcome Tracking" | the human-readable routing table (matches the code; good cross-check) |

---

## Architecture

### Principles

1. **Derivation stays pure; the DOM code only paints.** Same split the repo
   already uses (engine vs. controller in `watch-demo.js`, and Core vs. views in
   the app). All new logic — pending-point construction, outcome availability,
   ending-shot pill routing, stat records, stats summary — must be pure
   functions over plain objects, exposed on a `window.DeuceMateTracking` global
   (mirroring the existing `window.DeuceMateScoring`) so the owner can verify
   from the console.
2. **New pure logic goes in a new file, `docs/assets/watch-demo-tracking.js`**,
   loaded in `try.html` *before* `watch-demo.js`. The existing engine block in
   `watch-demo.js` is stable and tested-by-use — do not refactor it. UI changes
   go in `watch-demo.js`'s controller section and `watch-demo.css`.
3. **Match the existing code style**: ES5 (`var`, `function`), IIFE wrapper,
   no modules, no build step, no dependencies, comments citing the Swift source
   being mirrored.
4. **The page must keep loading zero external resources.** No fonts, no CDNs.

### UI state machine (per demo instance)

The controller currently has two modes (setup / play) plus a match-over banner.
This plan extends play mode with modal sub-states, exactly like the watch:

```
setup ──start──► scoring ──point scored & tracking on──► sheet:outcome
  ▲                 │  ▲                                    │      │
  │                 │  └────────── commit / undo ◄──────────┘      │ (non-DF, always
  │                 │                                              ▼  2-step on watch
  │                 │                                        sheet:endingShot   when tracking on)
  │                 │                                              │
  │                 └──match complete──► complete ──"End match"──► setup
  │                                        │
  └────────────────────────────────────────┘
stats overlay: toggled from scoring OR complete (swipe right / S key); modal.
```

Rules, mirroring the watch:
- While `sheet:*` is open, **all scoring input is blocked** (taps, swipes,
  keys, buttons). The sheet cannot be dismissed except by choosing an option or
  pressing its "Undo point" button (`interactiveDismissDisabled` on the watch).
- The score updates **before** the sheet appears (the point is already applied;
  the sheet only classifies it).
- Toast/changeover messages queued during categorisation appear only after the
  sheet commits (the watch delays them 0.4 s past commit).

### Data model (mirror of the Swift types, plain JS objects)

```js
// PendingPointInfo (PointStat.swift L63)
{ server: "me"|"opponent", winner: "me"|"opponent", setIndex: n,
  isSecondServe: bool, isBreakPoint: bool,
  gameScoreAtStart: { server: n, returner: n, isTiebreak: bool } | null }

// PointStat (PointStat.swift L100) — demo subset; no HR/steps/id/timestamp
{ setIndex: n, server: p, winner: p,
  outcome: "doubleFault"|"winner"|"forcedError"|"unforcedError"|"uncategorized",
  isSecondServe: bool, isBreakPoint: bool,
  endingShot: "serve"|"return"|"servePlusOne"|"rally"|null,
  gameScoreAtStart: {...}|null }
```

`pending` fields are snapshotted from the **pre-reducer** state: `server` is
`prev.currentServer` (correct in tiebreaks too — the JS engine advances the
server *after* scoring), `isBreakPoint` from the existing `isBreakPoint(prev)`,
`gameScoreAtStart` from `prev`'s current-game/tiebreak points expressed from the
server's perspective, `isSecondServe` from the new second-serve flag.

### Undo model

Extend the existing history entries from `{snapshot, momentum}` to
`{snapshot, momentum, secondServe, statsLen}` (snapshot taken before the point
is applied, as today). Undo restores all four and always clears any open sheet
and pending point (`stats = stats.slice(0, statsLen)`). This reproduces the
watch semantics — undo rolls back the score *and* drops the pending or committed
categorisation — without porting the watch's stat-ID stamping machinery.
"New match" / `R` likewise clears sheet + pending + stats.

---

## Behaviour specifications

### A. Second-serve context (mirrors `toggleSecondServe`, ScoreViewModel ~L1239)

- A demo-level flag `isOnSecondServe`, default false. It is **captured into the
  pending point and then reset to false as soon as a point is scored** (the
  watch resets it in `winPoint`/`losePoint` and again in `commitPointStat`), so
  the badge never carries over to the next point.
- Toggle inputs: **double-click/double-tap on the scoreboard card** (the watch
  scopes the gesture to the score display, ContentView ~L167), keyboard **`2`**,
  and a small **"2nd serve" util button** next to Undo (demo-only affordance for
  discoverability — the watch help text equivalent lives in try.html's hint).
- To make double-click safe, single clicks landing **inside the scoreboard card**
  (`.w-card`) must no longer award a point; the tap-to-score zones become the
  screen area outside the card. Swipes and keyboard are unaffected. Update the
  on-page hint text accordingly.
- Guards (all from the watch): no-op when tracking is off, when the format is
  `perpetualPoints` (`disablesPointTracking`), while a sheet is open, or when
  the match is complete.
- Visual: yellow (`#FFD60A`) 10px circle badge with a black bold **"2"**,
  top-right of the server's tennis-ball icon (ContentView ~L470–479). Clears
  when the flag clears.

### B. Post-point categorisation sheet (mirrors `PointCategorySheet.swift`)

Presented as an absolutely-positioned overlay filling the watch screen (same
technique as the existing `.banner`), after **every** scored point when
tracking is on — including tiebreak points and the match-winning point —
except in `perpetualPoints` format (never).

**Step 1 — outcome**

- Header banner: `"{Won|Lost} — {Your|Their} serve"` from the demo player's
  perspective (`Won` when winner is `me`; `Your serve` when server is `me`).
  Background `#21472E` when won, `#52242E` when lost (PointCategorySheet
  ~L67–77). If the point was played on a second serve, append a `"2nd"` yellow
  capsule (black text) after the label.
- Buttons in this exact order (from `PointOutcome.userSelectable`,
  PointStat.swift L24): **Double Fault, Unforced Error, Forced Error, Winner** —
  laid out two per row; a trailing odd button stretches full-width.
- **Double Fault is only shown when** `pending.isSecondServe && winner !== server`
  (PointCategorySheet ~L51–57), so the usual case is a 3-button sheet with
  Winner full-width on row 2.
- Button tints (MatchStats.swift ~L34–37): Double Fault `#DB5C5C`, Winner
  `#4DC780`, Forced Error `#EBB34D`, Unforced Error `#A880EB`.
- Tap behaviour ("commit beat", PointCategorySheet ~L101–119 & L305): the chosen
  button shows a small white ✓ badge, the others dim to 35% opacity, further
  taps are ignored, and after **0.4 s** the selection is applied. Honour
  `prefers-reduced-motion` by skipping the dim/scale animation but keep the
  0.4 s beat.
- Applying the selection (mirrors `selectOutcome`, ScoreViewModel ~L1165):
  - **Double Fault** → commit immediately with `endingShot: "serve"`, close.
  - Otherwise → advance to **Step 2** (the watch always has detailed shot
    tracking on whenever tracking is on — `detailedShotTrackingEnabled`
    mirrors `statsTrackingEnabled`, ScoreViewModel ~L25 — so the demo always
    shows Step 2 for non-DF outcomes).
- Below the buttons: **"↶ Undo point"** (gray, bordered) — undoes the entire
  point (score + pending) and closes the sheet. Disabled during the commit beat.

**Step 2 — ending shot**

- Header: left-aligned back chevron (**‹**) returning to Step 1 (clears the
  stashed outcome only — the score stays applied; `cancelOutcomeSelection`);
  centered two-line title: the chosen outcome's label (bold) over the question:
  - Winner → **"Winning shot?"**
  - Forced Error → **"Shot that forced it?"**
  - Unforced Error → **"Shot of the error?"**
  Header background = the outcome tint at 30% opacity.
- Pills (two per row, trailing odd pill full-width; all tinted blue), routed by
  *who played the ending shot* (PointCategorySheet ~L173–191): for **winners
  and forced errors** that is the point's *winner*; for **unforced errors** the
  *loser*. If that player was the **server**:
  - Winner → `Ace` (=serve), `S+1`, `Rally`
  - Forced Error → `Serve`, `S+1`, `Rally`
  - Unforced Error → `S+1`, `Rally` (a serve UFE is a double fault, excluded)
  If that player was the **receiver** (any outcome): `Return`, `Rally`.
- Same 0.4 s commit beat, then the point commits with the chosen shot and the
  sheet closes. Same "↶ Undo point" button at the bottom.

**Sanity table** (all 15 combinations — matches USER_GUIDE §categorisation):

| Server | Winner | Outcome | Step-2 pills |
|---|---|---|---|
| Me | Me | Winner | Ace · S+1 · Rally |
| Me | Me | Forced | Serve · S+1 · Rally |
| Me | Me | Unforced | Return · Rally |
| Me | Opp | Winner | Return · Rally |
| Me | Opp | Forced | Return · Rally |
| Me | Opp | Unforced | S+1 · Rally |
| Me | Opp | Double Fault | *(none — auto-locks Serve)* |
| Opp | Me | Winner | Return · Rally |
| Opp | Me | Forced | Return · Rally |
| Opp | Me | Unforced | S+1 · Rally |
| Opp | Me | Double Fault | *(none — auto-locks Serve)* |
| Opp | Opp | Winner | Ace · S+1 · Rally |
| Opp | Opp | Forced | Serve · S+1 · Rally |
| Opp | Opp | Unforced | Return · Rally |
| Opp | Opp | *(no DF — winner === server)* | |

### C. Point recording

- Tracking **on**: every commit appends a PointStat-shaped record (§data model)
  to the match's `stats` array; second-serve flag resets.
- Tracking **off**: still append a record with `outcome: "uncategorized"`,
  `endingShot: null` — silently, no sheet (mirrors `autoRecordPointStat`,
  ScoreViewModel ~L1257). This keeps serve/BP stats meaningful either way.
- `perpetualPoints`: no sheet and no records at all (format's
  `disablesPointTracking`).
- There is deliberately **no skip path**: the watch sheet has no skip button
  and can't be dismissed; the only exits are committing an outcome or Undo
  point. Don't add one to the demo.

### D. Live stats view (mirrors `MatchStatsView.swift` + `MatchStatsSummary.swift`)

- Entry: **swipe right** on the watch screen, keyboard **`S`**, and a
  **"📊 Stats"** util button. The watch gates the swipe on
  `statsTrackingEnabled` (ContentView ~L112–119); mirror that for the
  swipe/key, but keep the util button always available (it opens onto the
  empty state below — better demo discoverability). Rendered as a scrollable
  overlay filling the watch screen with a close affordance (the watch presents
  a sheet; a top "Done"/× is fine).
- Header: title **"Live Stats"** while the match is in progress, **"Match
  Stats"** when complete (ContentView ~L316), with a format line under it —
  `{format display label} · Singles` (MatchStatsView ~L122).
- **Set filter** (MatchStatsView ~L155–169): segmented buttons **"All"**, then
  **"S1"**, **"S2"**, … per set, and **"TB"** for a deciding super-tiebreak.
  Selecting one recomputes every section from only that set's points (filter
  the stats array by `setIndex` before running the summary — cheap and exactly
  how the watch does it).
- Empty states (exact copy): tracking off → *"Point outcome tracking was off
  for this match."*; tracking on but no points → *"No tracked points yet."*
- Sections, in watch order, each a Me-vs-Opp comparison (side-by-side counts
  with a split bar, like the "TV-style" rows the repo already renders in the
  HTML export — `MatchWebStaticFallback`'s `comparisonCard`/`splitBar` are a
  good visual reference). Row labels are the watch's, verbatim
  (MatchStatsView ~L509–652):
  1. **Points Won** — points-won split bar (`{n} pts` / `{total} total` /
     `{n} pts`).
  2. **Outcome Breakdown** — **"Win:Unforced Err"** ratio (caption *"aim for
     > 1.0"*); count rows **"Winners"**, **"Unforced Errors"**, **"Forced
     Errors"**, **"Double Faults"**; **"Aggression Index"** (caption
     *"W ÷ (W + UE)"*); **"Own Errors %"**; and, if any points are
     uncategorised, a `"(N uncategorized)"` annotation.
  3. **Serve** — **"1st Serve In"**, **"2nd Serve In"**, **"1st Serve Win"**,
     **"2nd Serve Win"**, **"DF Rate (2nd)"**. Derive exactly as
     `MatchStatsSummary.swift` does (every service point is a first-serve
     attempt; `!isSecondServe` points are first serves in; a DF is a second
     serve that missed, so it is excluded from "2nd Serve In").
  4. **Return** — **"vs 1st Serve"**, **"vs 2nd Serve"**.
  5. **Break Points** — **"BPs Won (Returner)"**, **"BPs Saved (Server)"**
     (from `isBreakPoint` + server + winner).
  6. **Pressure vs Normal** (only when data exists) — **"Big Points"**,
     **"Normal Points"**. "Big" = break point, tiebreak point, or both players
     ≥ 3 points (deuce/ad territory) — MatchStatsSummary ~L194–198.
  7. **Rally Depth Won** (only when ending-shot data exists) — one row per
     shot, labelled **"@ Serve"**, **"@ Return"**, **"@ S+1"**, **"@ Rally"**.
  8. **Score States** (only when data exists) — rows **"At 30-All"**,
     **"At Deuce/Ad"**, **"In Tiebreak"** (all from `gameScoreAtStart`).
- Port only the derivations the demo can feed (no HR, no steps, no set
  durations/calories). Implement them as pure functions in
  `watch-demo-tracking.js` mirroring `MatchStatsSummary.swift`
  field-for-field; when in doubt about an edge case, copy the Swift, do not
  invent.

### E. Match completion panel (mirrors ContentView ~L225–264)

Replace the current banner content with the watch's structure:
- **"You Won! 🏆"** (green) or **"Opponent Won"** (white 85%), subtitle
  **"Match Complete"**.
- When tracking produced stats: a **"📊 View stats"** affordance (watch shows
  *"Swipe for Stats"*; the demo button can open the stats overlay directly).
- **"Play again"** (existing) and keep the util **"↻ New match"** path — these
  map to the watch's red **"End Match"** button returning to setup.

### F. Changeover prompts (mirrors `ChangeoverAckOverlay`, ContentView ~L861)

The watch does **not** use transient toasts for changeovers: at every
changeover boundary it shows a blocking dark overlay — a symbol line, a reason
line, and a green **"OK"** button — and scoring is blocked until acknowledged.
(This is *not* gated by the "Changeover Compass" setting; that only gates the
compass badge.) When a categorisation sheet is up, the overlay is queued and
appears 0.4 s after the sheet commits. Replace the demo's changeover toasts
with this overlay, using the watch strings (symbols from `ScoringEngine.swift`
~L340–552, reasons from ScoreViewModel ~L1111–1132):

| Symbol | Reason |
|---|---|
| `🔁 👥` | "Odd games – players change ends" / "Set complete – players change ends" |
| `🔁 🎾` | "Even games – balls change ends" / "Set complete – balls change ends" |
| `🔁 🎾` | "Odd tiebreak point – balls change ends" — after every tiebreak point where `pointCountInTiebreak % 2 == 1`, unless the 6-point branch below fired (`ScoringEngine.swift` ~L339–349, reason `.tiebreakOddPoint`) |
| `🔁 🎾 👥` | "Every 6 tiebreak points – players & balls change ends" / "Set complete – players & balls change ends" |
| `Tiebreak 🔁 🎾` | "Games at 6-6 – tiebreak begins" (or "Games at 2-2 – sudden death point" for Quick 4) |

The demo engine's changeover events currently carry demo-invented text
("Change ends", "New balls soon", "Tiebreak!", "Sudden death!") — map each
event to the watch symbol/reason pair instead (the engine already knows game
totals and tiebreak boundaries; extend the emitted event payload, don't rework
the reducer). One event is **missing entirely** from the JS reducer and must
be added: the odd-tiebreak-point row above (the JS `updateTiebreak` only
emits a changeover at the 6-point boundary today). Watch the branch order:
the 6-point check wins, and it is skipped for `fixedDeuceSide` formats — so
in Perpetual Points every odd point emits the odd-point prompt (the watch
really does show it there; the engine has no format guard on the odd-point
branch). Game/set-won toasts ("Game — you", "Set — opponent") are a
demo-only aid the watch doesn't have; keeping them is fine.

### G. Fit & finish parity (small items)

- **First-game hint**: faint two-line overlay at the top of the watch screen —
  `"↑ Win  ↓ Lose"` / `"← Undo  → Stats"` — visible until the first game
  completes or the match ends, non-interactive (ContentView ~L132–142).
- **Swipe live-preview**: while a touch/pointer drag is in progress past the
  swipe threshold, tint the row that would receive the point (green for Me,
  red for Opp, ~22% fill + 3px stroke); clear on release (ContentView
  ~L416–430). Pointer-drag equivalent for desktop.
- **Momentum strip**: hide when the match is complete (ContentView ~L171).
- **Footer**: optionally append a live `🕐 mm:ss` elapsed timer (the watch shows
  `🔥 kcal · 🕐 time`; calories are impossible in a browser — omit them).
- Update `try.html`'s hint paragraph (gestures now include double-tap = 2nd
  serve, → = stats) and the footer's "plays singles only" note if/when Phase 6
  ships. Keep the "simulated demo, not the actual product" disclaimer as is.

---

## Phases (one PR each, independently shippable)

### Phase 1 — Tracking foundation + second-serve context
Create `docs/assets/watch-demo-tracking.js` (pure: pending-point builder,
outcome availability, pill routing, stat-record constructors; export as
`window.DeuceMateTracking`). Wire the second-serve flag (§A), the `.w-card`
click-scope change, extended undo entries (§Undo model), and silent
uncategorised recording (§C). Add a **"Track point outcomes"** toggle to the
setup card (default **on** — the demo exists to show this feature off; note
this deliberately differs from the watch's off-default) plus keyboard `2`.
**Accept when:** yellow "2" badge toggles on double-click/`2` and clears after
the next point; single-click on the score card no longer scores; undo restores
the 2nd-serve flag; `DeuceMateTracking` is inspectable in the console;
`perpetualPoints` refuses the toggle.

### Phase 2 — Categorisation sheet
The full §B overlay + §C recording, blocking input while open, with the exact
labels, order, tints, conditional Double Fault, 0.4 s commit beat, back
chevron, and Undo point. Changeover/game toasts queue behind the sheet.
**Accept when:** every row of the §B sanity table can be reproduced in the
browser; DF appears only after marking a 2nd serve and losing as server and
skips Step 2; Undo point from either step fully rolls back; with the setup
toggle off no sheet ever appears; `perpetualPoints` never sheets.

### Phase 3 — Stats view
§D overlay with swipe-right/`S`/button entry, watch section order, split-bar
comparisons, empty states, live + complete titles.
**Accept when:** a scripted mini-match (below) produces the expected numbers;
the overlay opens mid-match and post-match; tracking-off shows the exact
empty-state copy.

### Phase 4 — Completion panel, changeover overlay + fit & finish
§E, §F and §G.
**Accept when:** match end shows the watch-style panel with a working stats
button; changeovers show the blocking symbol/reason overlay with the exact
watch strings (odd game, even game, set complete, odd tiebreak point,
6-point tiebreak boundary, 6–6 tiebreak start, Quick-4 sudden death) and
block scoring until OK'd; the first-game hint appears only before the first
completed game; drag-preview tints the correct row; momentum strip hides at
match end.

### Phase 5 — Copy refresh
Update `try.html` hints/lede (and the index.html demo blurb if it undersells
the new capability) to mention outcome tracking and the new gestures. Align
the setup card's format labels with the watch's own setup sheet (HomeView
~L413–476): "Best of 3 Sets (Club / League)" / "3 sets · Final set: Super
Tiebreak to 10", "Best of 3 Sets (ATP)" / "3 sets · Final set: Full set,
tiebreak to 7", "Quick 4 Games" / "First to 3 games · Sudden death point at
2-2", "Super Tiebreak" / "1 set · Single tiebreak to 10 pts", "Perpetual
Tiebreak" / "Continuous tiebreak until stopping", "Perpetual Points" / "Just
count points · server alternates every point · no stats or changeovers".
**Accept when:** owner proof-reads the page.

### Phase 6 (optional) — Doubles
Four-player service rotation, mirroring `startDoublesMatch` /
`resolveDoublesTeamServer` (ScoreViewModel ~L710–747):
- Setup gains a **Singles / Doubles** choice; doubles first-server options are
  **Me / Partner / Opponent** (HomeView ~L240–268).
- Rotation orders: Me first → `[me, opponentS1, partner, opponentS2]`; Partner
  first → `[partner, opponentS1, me, opponentS2]`; Opponent first →
  provisional `[opponentS1, me, opponentS2, partner]` **plus** a pending
  decision: after the opponents' first game, a blocking overlay asks **"Who
  serves next?"** with **Me / Partner** buttons (ContentView ~L901–934); if
  Partner is chosen the order is rebuilt so Partner serves before Me.
- The serving team's row shows the 🎾 ball with a small black capsule naming
  the current server — **Me / Partner / S1 / S2** (`DoublesServer.displayName`,
  ScoreTypes.swift ~L142–160); row names stay "Me"/"Op" (team-level).
- Server advances to the next rotation slot each game (and per the tiebreak
  serving pattern inside tiebreaks — the engine's existing tiebreak rotation
  generalises; check `ScoringEngine.swift` ~L369–397 when implementing).
- Stats headers use **"Our"** instead of "Me" in doubles (MatchStatsView ~L67)
  and the stats-view format line appends `· Doubles`.
- Update the footer's "plays singles only" note when this ships.

Out of order is fine only for Phase 5; Phases 2–4 each depend on Phase 1.

---

## Owner verification playbook

Quick scripted checks (browser console, after Phase 3):

1. **Serve/DF math** — new Best-of-3 match, me serving, tracking on. Score 4
   straight points for Opp; before point 4, double-tap to mark 2nd serve and
   pick Double Fault. Expected: Serve section shows 1st serve in 3/4 (75%),
   2nd serve in 0/1, double faults Me 1; Opp leads game 0–1. Undo the DF point
   and confirm the stat and the "2" badge state roll back.
2. **Break point** — with Opp at 40–0 on my serve, each of the next points
   should record `isBreakPoint: true` (inspect
   `DeuceMateTracking`-exposed match stats in the console); winning one as Opp
   increments "Break Points" conversions for Opp.
3. **Routing table spot-checks** — reproduce at least the four Ace/Serve/S+1
   corner rows of the §B table.
4. **Tiebreak** — force 6–6, confirm the sheet still appears each point with
   the correct server attribution, and Score States shows tiebreak win rates.
5. **Formats** — `perpetualPoints`: no sheet, no "2" toggle, stats view shows
   the empty state. `quick4Games`: sudden-death point at 2–2 still sheets.
6. **Changeovers** (after Phase 4) — game 1 shows `🔁 👥` "Odd games – players
   change ends" and blocks scoring until OK; game 2 shows `🔁 🎾` "Even games –
   balls change ends"; at 6–6 the tiebreak-begins prompt appears; inside the
   tiebreak, points 1, 3 and 5 each show `🔁 🎾` "Odd tiebreak point – balls
   change ends" and point 6 shows the `🔁 🎾 👥` six-point prompt; with a sheet
   pending, the prompt waits until the sheet commits.

---

## Constraints (hard)

- Zero dependencies, zero external resources, no build step — hand-written
  ES5-style JS matching the existing files.
- No Swift changes; no changes outside `docs/`.
- Keep `window.DeuceMateScoring` intact; add, don't reshape.
- Preserve existing accessibility affordances (aria labels, keyboard operation,
  `prefers-reduced-motion`) and extend them to the new UI (sheet buttons are
  real `<button>`s, overlay has `role="dialog"` and `aria-label`, stats overlay
  is keyboard-closable).
- The demo remains honest: it simulates the watch experience; keep the
  disclaimer block in `try.html`.
- `docs/architecture/file-inventory.md` covers app source only — no entry
  needed for new site assets; do update this plan's **Status** line as phases
  land.

## Non-goals

Heart-rate/steps/calories, the changeover compass, umpire announcements,
watch↔phone sync, appearance themes, RecCoach/PulseCoach insights, match
persistence across page reloads, and localisation. The set-duration stats
section is also omitted (the demo has no meaningful play clock). Revisit any of
these only after Phases 1–5 ship.

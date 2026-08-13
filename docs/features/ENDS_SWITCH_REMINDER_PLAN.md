# Plan: Sticky Ends-Switch Reminder

## 1. The report

> After a set is completed; even though there is a notice to change ends; I
> tap ok then go back a point just to see it again and confirm if we are
> switching ends. I usually get confused if we are supposed to or not. Can we
> update the GUI so there is more of a sticky notice before the first point
> of the next set that we need to switch? This isn't needed for tiebreakers;
> but can be added. It's just when you've had a break but already tapped
> "OK" when the announcement for if we are switching or not has already been
> accepted.

Translation: after a set ends, `ScoreViewModel` shows a full-screen
changeover popup ("Set complete – players change ends" / "... balls change
ends") with an OK button. Tapping OK dismisses it for good. By the time the
user is actually about to serve/return the first point of the new set —
after walking back from a break, changing ends (or not) — they've forgotten
what the popup said, and today the only way to re-check is to **undo the
last point**, which re-triggers the same popup, then redo the point. That's
the workaround this plan removes.

Scope, per the report: only the *set-boundary* case is confusing enough to
ask for. In-set odd/even-game changeovers and tiebreak six-point
changeovers are explicitly **not** part of this ask (see §6).

## 2. What happens today

- `ScoreViewModel.pendingChangeoverAck: ChangeoverInfo?` drives
  `ChangeoverAckOverlay` (`ContentView.swift`), a full-screen modal with an
  OK button. `acknowledgeChangeover()` nils it out permanently — nothing
  about the changeover survives past that tap.
- Separately, an **opt-in Changeover Compass** setting (`checkChangeover`,
  see `CHECK_CHANGEOVER_PLAN.md`) shows a small compass badge at *every*
  game start (not just set boundaries) — but it requires physical compass
  calibration at match start, needs watch hardware, and most users leave it
  off. It's the closest existing analog to "persistent changeover state,"
  but it's the wrong shape for this ask: heavier, opt-in, and fires every
  game rather than only at the one boundary that actually confuses people.
- Nothing today re-states "does this set start with an ends switch?" once
  the popup is dismissed.

## 3. The rule, confirmed

Whether players physically switch ends after a set is always exactly:

```
totalGames(justFinishedSet) % 2 == 1
```

This holds for **both** paths in `ScoringEngine.swift`:
- A normally-completed set (`handleSideChangesAfterSet`) — the formula
  directly.
- A set decided by a tiebreak (`handleSideChangesAfterTiebreakSetEnd`) — the
  same `totalGames % 2 == 1` check (its extra `ballsNeedToMove` flag only
  decorates which symbol/announcement fires, for doubles serve bookkeeping;
  it never changes whether players move). A tiebreak's winner always
  records `loserGames + 1` games, so the total is *always* odd — switching
  ends after a tiebreak-decided set is a mathematical certainty, not just a
  common case.

So the reminder doesn't need to re-derive the popup's full logic — a plain
parity check on the just-finished set's games is sufficient and always
agrees with what the popup already said.

## 4. Proposed design

A **sticky, non-blocking pill** on the live-match screen, occupying the
momentum strip's slot directly under the score card, that:
- Reads `🔁 Switch ends` or `📍 Same ends` — shown for **both** outcomes
  (never silent), so there's no ambiguity between "nothing to do" and "the
  app didn't load."
- Appears the instant a set completes (already true, underneath the OK
  modal — no pop-in delay after dismissing it).
- **Survives tapping OK.** This is the entire point.
- Stays on screen — the live-match screen doesn't scroll, so "sticky" is
  literal — until the first point of the new set is scored, then clears
  itself automatically and the momentum strip comes back.
- Never blocks swipe-to-score. The user can keep playing right through it;
  no dismissal required.
- Is **not** gated behind the Changeover Compass toggle. That toggle exists
  because compass calibration has real hardware/battery/UX cost; this
  reminder is a free, pure state readout with no such cost, and gating it
  behind the compass setting would hide it from exactly the users (like the
  one who filed this report) who don't want the compass hassle but still
  get confused about ends.
- **Takes the momentum strip's place rather than being added below it**, at
  the strip's exact height, so the live-match layout does not reflow by a
  single point on any watch size. §5 is the measured justification.

![Before/after: today nothing remains once the changeover popup is
dismissed; proposed swaps the momentum strip for a sticky pill that survives
the OK tap and clears itself at the new set's first
point](assets/ends-switch-reminder-before-after.svg)

## 5. Layout study (measured, not estimated)

The first draft of this plan specced the reminder as a *new* full-width
banner inserted **below** the momentum strip. Before committing to that,
the design was built as a throwaway prototype (exactly the code in §7),
run in the watchOS simulator across every screen class the watchOS 9
deployment target still reaches, and the resulting screenshots were
measured band-by-band in points. The prototype was then reverted; no code
from it is on `main`.

Scenario: singles, `.standard` format, set 1 won 6–1, OK already tapped on
the changeover popup. Re-run with a 6–0 set (the `📍 Same ends` copy) and
with the Changeover Compass both on and off.

![Vertical budget on the smallest supported screen: today, banner added
below the strip (clips), and the reminder swapped into the strip's slot
(pixel-identical)](assets/ends-switch-reminder-layout-budget.svg)

### 5.1 Width is never the constraint

`🔁 Switch ends` measures ~74 pt of glyphs, centred in a full-width pill that
is never narrower than ~150 pt — even on the 162 pt-wide screen it sits with
~38 pt of clear space on each side, and `minimumScaleFactor` never engages.
`📍 Same ends` is shorter still. **The sticky note is fine at every current
width**; the whole question is vertical.

### 5.2 Height is the constraint

The as-specced banner (11 pt semibold text, 5 pt vertical padding, 4 pt of
top spacing) measures **25.5 pt + 4 pt = 29.5 pt** of new layout. The
live-match screen does not scroll, and its `VStack` is centred inside a
full-screen `ZStack`, so that height is not simply taken off the bottom — it
is split roughly half up, half down. Measured on 46 mm: the banner moved the
momentum strip **up** 14 pt (into the close button and clock) and the court
row **down** 14.5 pt. So both ends of the screen pay.

| Screen (pt) | Devices | Space below the last row today | Banner added below the strip | Reminder swapped into the slot |
|---|---|---|---|---|
| 162 × 197 | 40 mm Series 4–6 / SE | none — the calorie/timer row already sits half off the bottom | calorie/timer row gone, court + heart-rate row clipped ~6.5 pt, score card pushed up under the clock | pixel-identical to today |
| 184 × 224 | 44 mm Series 4–6 / SE, SE 3 40 mm | ~9 pt | calorie/timer row reduced to a 2 pt sliver | pixel-identical |
| 187 × 223 | 42 mm Series 10/11 | ~13.5 pt | calorie/timer row cut at the screen edge | pixel-identical |
| 208 × 248 | 46 mm Series 10/11 | ~24.5 pt | fits, ~10 pt to spare | pixel-identical |
| 211 × 257 | 49 mm Ultra | ~29 pt | fits, ~14.5 pt to spare | pixel-identical |

45 mm (198 × 242, Series 7–9) has no installed simulator runtime here;
interpolating the margin column puts it around 21 pt, so added-below would
probably just fit there. **Every screen class at 42 mm and below clips —
measured, not extrapolated.** That is the 40, 42 and 44 mm classes outright,
and 41 mm (176 × 215) sits between two measured clipping sizes.

With the Changeover Compass enabled the badge row grows further, and the
162 × 197 screen is already over budget *today* (calorie/timer row gone,
heart-rate badge clipped). Adding the banner there pushes the score card
into the status bar; the swap leaves that pre-existing state untouched.

### 5.3 Verdict: swap, don't add

The reminder is drawn at the momentum strip's exact **15 pt** height and
takes its slot for as long as it is live. Every band below it — court, heart
rate, calorie/timer — lands on the same y as today, to within the ±0.5 pt of
measurement noise. Verified on 40 mm (both screen classes), 42 mm, 46 mm and
49 mm with the compass off, and on 42 mm with the compass on (the one
configuration where the badge row is also on screen at 0–0 of a new set).

Giving up the momentum strip for that window costs nothing real:

- The reminder is only ever on screen at 0–0 of a brand-new set, which is
  precisely when the strip is at its least informative — it is showing the
  last eight points of the set that just *ended*.
- It is self-clearing: the first point of the new set brings the strip back
  (and that point is also the first entry the strip would have to show).
- Zero reflow means no screen size can be pushed over budget, now or when a
  future row is added to the live screen.

### 5.4 Incidental findings (not part of this change)

Worth recording, since the simulator sweep surfaced them:

- On 162 × 197 the calorie/timer row is already clipped roughly in half, and
  the score card's rounded corners run off both screen edges. Both are
  pre-existing on `main`, unrelated to this feature.
- With the compass badge on, that same screen already loses the calorie/timer
  row entirely and clips the heart-rate badge.

## 6. Scope boundaries — why "not for tiebreakers"

Per the report, three related-but-distinct changeover moments are
explicitly **excluded**:

| Moment | Why excluded |
|---|---|
| In-set odd/even-game changeover (every regular game) | Not reported as confusing — it's a familiar, frequent rhythm, unlike the once-or-twice-per-set boundary case. |
| Mid-tiebreak six-point changeover | Same reasoning — happens often enough within a single breaker that the popup alone is enough. |
| The run-up to a match-deciding super-tiebreak set (e.g. `.standard` at 1-1 sets) | The "next set" here isn't a regular set at all — it's a breaker with its own frequent changeovers, so a one-time "switch/stay" reminder doesn't fit. |

The report says this last case "can be added" later if wanted — deferred,
not rejected. If a future iteration wants it, the natural extension point is
`ScoringEngine.nextSetRequiresEndsSwitch` (§7.1): today it returns `nil`
whenever the upcoming set `isTieBreak`; broadening scope means relaxing that
guard and deciding what "switch/stay" should mean for a breaker's own
internal changeover cadence.

## 7. Implementation plan

No code has been written yet — this section is the plan for the follow-up
PR(s). (The §5 prototype was reverted; nothing from it is on `main`.)

### 7.1 Core pure logic — `ScoringEngine.swift`

New static function, grouped with the file's other "derived UI fact from a
`ScoringState` snapshot" functions (after `isCurrentPointBreakPoint(_:)`,
before `tiebreakTargetPoints(forSetAt:in:format:)`):

```swift
public static func nextSetRequiresEndsSwitch(_ state: ScoringState) -> Bool? {
    guard state.sets.count >= 2 else { return nil }
    let upcoming = state.sets[state.sets.count - 1]
    guard !upcoming.isTieBreak,
          upcoming.gamesMe == 0,
          upcoming.gamesOpponent == 0,
          state.currentPointsMe == 0,
          state.currentPointsOpponent == 0
    else { return nil }

    let justFinished = state.sets[state.sets.count - 2]
    let totalGames = justFinished.gamesMe + justFinished.gamesOpponent
    return totalGames % 2 == 1
}
```

`nil` = the reminder doesn't apply right now. `true`/`false` = switch/stay.
Follows the existing `Bool?` / `Player?` / `GameScoreSnapshot?` idiom already
used by sibling functions in this file, rather than a bespoke enum. Pure
read of existing fields — no changes to `ScoringState`, `SetScore`, or any
reducer path.

### 7.2 `ScoreViewModel` wiring

One computed property, right after `isAtGameStart` (~line 565):

```swift
var pendingEndsSwitchReminder: Bool? {
    guard !matchFormat.config.fixedDeuceSide else { return nil }
    return ScoringEngine.nextSetRequiresEndsSwitch(scoringState())
}
```

Mirrors the existing `showCompassBadge` guard (`fixedDeuceSide` formats,
i.e. Perpetual Points, never change ends). Uses the existing
`scoringState()` builder that already feeds
`ScoringEngine.isCurrentPointBreakPoint`/`gameScoreSnapshotAtPointStart`.

**Deliberately implemented as a pure computed property, not an imperative
flag.** `sets`, `currentPointsMe`, `currentPointsOpponent`, and
`matchFormat` are already fully persisted (`AppState`) and fully restored by
`undo()` (from `HistoryEntry` snapshots) and by resume-from-`MatchRecord`.
A pure derivation therefore needs **zero new persistence code** — no
`AppState` version bump, no new null-out sites at `resetMatch()` / resume /
`undo()` — and is automatically correct across undo, resume, and app
relaunch mid-match. (Verified each of those three reset paths already
produces the correct `nil` for free: e.g. `resetMatch()` sets
`sets = [SetScore(isTieBreak: false)]`, a single-element array, so
`sets.count >= 2` is already false.)

### 7.3 ContentView SwiftUI integration

New view, grouped with the file's other small badge views (after
`MomentumBadgeView`, before `HeartRateBadgeView`):

```swift
struct EndsSwitchReminderBanner: View {
    let shouldSwitch: Bool

    var body: some View {
        HStack(spacing: 5) {
            Text(shouldSwitch ? "🔁" : "📍")
                .font(.system(size: 10))
            Text(shouldSwitch ? "Switch ends" : "Same ends")
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(shouldSwitch ? Color.orange : Color.white.opacity(0.75))
        .frame(maxWidth: .infinity)
        // 1 pt of vertical padding around an 11 pt line box == the momentum
        // strip's 15 pt height, so swapping one for the other reflows
        // nothing. Measured on 40/42/46/49 mm — see §5; don't grow this
        // without re-running that sweep.
        .padding(.vertical, 1)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill((shouldSwitch ? Color.orange : Color.white).opacity(shouldSwitch ? 0.16 : 0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke((shouldSwitch ? Color.orange : Color.white).opacity(shouldSwitch ? 0.55 : 0.12), lineWidth: 1)
                )
        )
    }
}
```

`🔁` reuses the app's existing changeover glyph (used in the popup's
symbols). `📍`, not `🎾`, for "stay" — `🎾` already means "balls change ends"
in the existing symbol vocabulary, so reusing it here would contradict
established meaning.

The existing `MomentumBadgeView` block inside `if !viewModel.isMatchComplete()`
becomes a two-state slot:

```swift
if !viewModel.isMatchComplete() {
    ZStack {
        if let shouldSwitch = viewModel.pendingEndsSwitchReminder {
            EndsSwitchReminderBanner(shouldSwitch: shouldSwitch)
                .transition(.opacity)
        } else {
            MomentumBadgeView(recentPoints: viewModel.history.suffix(8).map { $0.player })
                .transition(.opacity)
        }
    }
    .padding(.top, 4)
    .padding(.horizontal, 8)
    .animation(.easeInOut(duration: 0.25), value: viewModel.pendingEndsSwitchReminder)
}
```

`ZStack` rather than a bare `if`/`else` so the two states crossfade in place;
both children are the same 15 pt height, so the container's height is
constant through the transition and the rows below never move.

**Must not be added to `swipeScoringBlocked`.** The entire point of this
feature is that the user can keep scoring right through it with no
dismissal required — unlike `pendingChangeoverAck`, which does block swipes.

### 7.4 Tests (required — logic change)

**`DeuceMateCoreTests/ScoringEngineTests.swift`** — new `// MARK: - Ends-switch
reminder` section, reusing the file's existing `point`/`winGame`/
`winTiebreakPoints` helpers:
- nil before any set completes
- true after an odd-total-games set (e.g. 6-1)
- false after an even-total-games set (e.g. 6-0)
- true after a tiebreak-decided set (documents the "always odd" invariant —
  there is no false-parity tiebreak-ending case to test)
- nil when the next "set" is a match-deciding super-tiebreak
- nil once the first point of the new set has been played
- nil once the match is complete

**`DeuceMate_Watch_AppTests.swift`** — reusing `makeViewModel`/`winGame`/
`winGames`/`winPoint`:
- `pendingEndsSwitchReminderSurvivesAckAndClearsAfterFirstPoint` — the test
  that most directly encodes the bug report: win a set 6-1, assert the
  reminder is `true`, call `acknowledgeChangeover()` (tap OK) and assert the
  reminder is **still** `true` while `pendingChangeoverAck` is now `nil`,
  then score one point and assert the reminder is `nil`.
- false after an even-games set (6-0).
- nil for a `fixedDeuceSide` format (`.perpetualPoints`) regardless of score.

There is no snapshot/layout test target, so nothing here can assert the
15 pt footprint. The zero-reflow claim is held by the §5 simulator sweep and
by the comment on `.padding(.vertical, 1)` — re-run the sweep if the pill's
typography changes.

### 7.5 Docs

No `docs/architecture/file-inventory.md` update — no source file added,
removed, renamed, or repurposed; all changes land inside three existing
files already listed there (`ScoringEngine.swift`, `ScoreViewModel.swift`,
`ContentView.swift`).

## 8. Rejected alternatives

- **A new banner added *below* the momentum strip** (this plan's own first
  draft) — rejected on measurement: +29.5 pt of layout, which every screen
  at 42 mm and below fails to absorb. There it clips the calorie/duration
  row, and on 40 mm it also clips the court/heart-rate row and pushes the
  scoreboard under the status bar. Full numbers in §5.2.
- **Imperative flag, set once at the changeover event and cleared at reset
  sites** — considered and rejected in favor of the pure computed property
  (§7.2): it would need a new `AppState` field (version bump, decode
  default) and three new explicit null-outs, for no behavioral benefit over
  a derivation that's correct by construction.
- **Silent when nothing changes ("no badge = stay put")** — rejected. The
  report is specifically about ambiguity; a reminder that's sometimes absent
  reintroduces "did the app just not load, or is there really nothing to
  do?" Show both outcomes explicitly.
- **Squeeze into the existing compass/heart-rate badge row** — rejected.
  That row is already tight (its `ViewThatFits` exists precisely to reflow
  compass + heart rate on small screens) and can't fit phrase-length text.
- **Gate behind the Changeover Compass toggle** — rejected. That toggle's
  cost (hardware calibration) doesn't apply here, and gating would hide the
  fix from users who specifically don't want the compass but still get
  confused about ends.
- **Tap-to-recall the full popup again** — considered (the pill could
  re-open `ChangeoverAckOverlay` on tap) but dropped for v1: the passive
  persistent readout already solves "I need to re-check" without
  reintroducing a modal; adding a tap target is unnecessary scope for the
  reported problem.

## 9. Verification (once implemented)

1. `cd DeuceMate/Packages/DeuceMateCore && swift test` — new
   `ScoringEngineTests` cases pass alongside the existing suite.
2. `xcodebuild test -project DeuceMate/DeuceMate.xcodeproj -scheme "DeuceMate Watch App" -destination "platform=watchOS Simulator,name=Apple Watch Series 9 (45mm),OS=latest"`
   — new `DeuceMate_Watch_AppTests` cases pass; no regression in the
   existing changeover tests.
3. Manual, on the **smallest** simulator available (40 mm SE, 162 × 197 pt)
   and one large one (46 mm or 49 mm): play a set to an odd score (e.g.
   6-1), confirm `🔁 Switch ends` appears in the momentum strip's slot,
   survives tapping OK, stays visible while idle, and is replaced by the
   momentum strip again the instant the first point of the new set is
   scored. Repeat for an even score (6-0) to confirm `📍 Same ends`.
4. On the same two sizes, compare a screenshot before and after the reminder
   appears: the court, heart-rate and calorie/timer rows must not move.
   Repeat with the Changeover Compass on.
5. Confirm the reminder never blocks swipe-to-score, that nothing shows for a
   Perpetual Points match, and that nothing shows heading into a
   match-deciding super-tiebreak set.

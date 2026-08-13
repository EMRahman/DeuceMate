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
changeovers are explicitly **not** part of this ask (see §5).

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

A **sticky, non-blocking banner** on the live-match screen, under the score
and momentum strip, that:
- Reads `🔁 Switch ends` or `📍 Same ends` — shown for **both** outcomes
  (never silent), so there's no ambiguity between "nothing to do" and "the
  app didn't load."
- Appears the instant a set completes (already true, underneath the OK
  modal — no pop-in delay after dismissing it).
- **Survives tapping OK.** This is the entire point.
- Stays on screen — the live-match screen doesn't scroll, so "sticky" is
  literal — until the first point of the new set is scored, then clears
  itself automatically.
- Never blocks swipe-to-score. The user can keep playing right through it;
  no dismissal required.
- Is **not** gated behind the Changeover Compass toggle. That toggle exists
  because compass calibration has real hardware/battery/UX cost; this
  banner is a free, pure state readout with no such cost, and gating it
  behind the compass setting would hide it from exactly the users (like the
  one who filed this report) who don't want the compass hassle but still
  get confused about ends.

![Before/after: today nothing remains once the changeover popup is
dismissed; proposed adds a sticky banner that survives the OK tap and
clears itself at the new set's first point](assets/ends-switch-reminder-before-after.svg)

## 5. Scope boundaries — why "not for tiebreakers"

Per the report, three related-but-distinct changeover moments are
explicitly **excluded**:

| Moment | Why excluded |
|---|---|
| In-set odd/even-game changeover (every regular game) | Not reported as confusing — it's a familiar, frequent rhythm, unlike the once-or-twice-per-set boundary case. |
| Mid-tiebreak six-point changeover | Same reasoning — happens often enough within a single breaker that the popup alone is enough. |
| The run-up to a match-deciding super-tiebreak set (e.g. `.standard` at 1-1 sets) | The "next set" here isn't a regular set at all — it's a breaker with its own frequent changeovers, so a one-time "switch/stay" banner doesn't fit. |

The report says this last case "can be added" later if wanted — deferred,
not rejected. If a future iteration wants it, the natural extension point is
`ScoringEngine.nextSetRequiresEndsSwitch` (§6.1): today it returns `nil`
whenever the upcoming set `isTieBreak`; broadening scope means relaxing that
guard and deciding what "switch/stay" should mean for a breaker's own
internal changeover cadence.

## 6. Implementation plan

No code has been written yet — this section is the plan for the follow-up
PR(s).

### 6.1 Core pure logic — `ScoringEngine.swift`

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

### 6.2 `ScoreViewModel` wiring

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

### 6.3 ContentView SwiftUI integration

New view, grouped with the file's other small badge views (after
`MomentumBadgeView`, before `HeartRateBadgeView`):

```swift
struct EndsSwitchReminderBanner: View {
    let shouldSwitch: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(shouldSwitch ? "🔁" : "📍")
                .font(.system(size: 12))
            Text(shouldSwitch ? "Switch ends" : "Same ends")
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(shouldSwitch ? Color.orange : Color.white.opacity(0.75))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
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

Inserted right after the existing `MomentumBadgeView` block, inside the same
`if !viewModel.isMatchComplete()`:

```swift
if let shouldSwitch = viewModel.pendingEndsSwitchReminder {
    EndsSwitchReminderBanner(shouldSwitch: shouldSwitch)
        .padding(.top, 4)
        .padding(.horizontal, 8)
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.9, anchor: .top)),
            removal: .opacity
        ))
        .animation(.easeInOut(duration: 0.25), value: viewModel.pendingEndsSwitchReminder)
}
```

Transition/animation idiom matches the existing `ChangeoverAckOverlay` and
`DoublesTeamServerDecisionOverlay` pattern already in this file.

**Full-width banner, not a badge in the compass/heart-rate row.** That row
is already tight on a 41 mm watch (`ViewThatFits` exists there specifically
to reflow compass + heart-rate), and this feature needs to convey a short
*phrase*, not just an icon+number — a full-width slim banner (same
footprint class as `MomentumBadgeView`, directly above it) has room and
reads at a glance.

**Must not be added to `swipeScoringBlocked`.** The entire point of this
feature is that the user can keep scoring right through it with no
dismissal required — unlike `pendingChangeoverAck`, which does block swipes.

### 6.4 Tests (required — logic change)

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

### 6.5 Docs

No `docs/architecture/file-inventory.md` update — no source file added,
removed, renamed, or repurposed; all changes land inside three existing
files already listed there (`ScoringEngine.swift`, `ScoreViewModel.swift`,
`ContentView.swift`).

## 7. Rejected alternatives

- **Imperative flag, set once at the changeover event and cleared at reset
  sites** — considered and rejected in favor of the pure computed property
  (§6.2): it would need a new `AppState` field (version bump, decode
  default) and three new explicit null-outs, for no behavioral benefit over
  a derivation that's correct by construction.
- **Silent when nothing changes ("no badge = stay put")** — rejected. The
  report is specifically about ambiguity; a banner that's sometimes absent
  reintroduces "did the app just not load, or is there really nothing to
  do?" Show both outcomes explicitly.
- **Squeeze into the existing compass/heart-rate badge row** — rejected.
  That row is already tight on a 41 mm watch and can't fit phrase-length
  text; a full-width banner has room and is more legible at a glance.
- **Gate behind the Changeover Compass toggle** — rejected. That toggle's
  cost (hardware calibration) doesn't apply here, and gating would hide the
  fix from users who specifically don't want the compass but still get
  confused about ends.
- **Tap-to-recall the full popup again** — considered (banner could re-open
  `ChangeoverAckOverlay` on tap) but dropped for v1: the passive persistent
  banner already solves "I need to re-check" without reintroducing a modal;
  adding a tap target is unnecessary scope for the reported problem.

## 8. Verification (once implemented)

1. `cd DeuceMate/Packages/DeuceMateCore && swift test` — new
   `ScoringEngineTests` cases pass alongside the existing suite.
2. `xcodebuild test -project DeuceMate/DeuceMate.xcodeproj -scheme "DeuceMate Watch App" -destination "platform=watchOS Simulator,name=Apple Watch Series 9 (45mm),OS=latest"`
   — new `DeuceMate_Watch_AppTests` cases pass; no regression in the
   existing changeover tests.
3. Manual, on a 41 mm simulator/device: play a set to an odd score (e.g.
   6-1), confirm "🔁 Switch ends" appears, survives tapping OK, stays
   visible while idle, and disappears the instant the first point of the
   new set is scored. Repeat for an even score (6-0) to confirm "📍 Same
   ends". Confirm the banner never blocks swipe-to-score. Confirm nothing
   shows for a Perpetual Points match, and nothing shows heading into a
   match-deciding super-tiebreak set.

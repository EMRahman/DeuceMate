<!--
machine-readable summary (parse this block first)

status: planned
author: Claude (Opus 5), design session with the owner
date: 2026-08-03
closes_backlog_item: "TECHNICAL_DEBT.md #5 — Simplify first-run and match-start UX. It was Parked on the grounds that it was 'a product design decision… should be addressed in a product/UX conversation rather than a PR'. This document IS that conversation, so #5 moves Parked → Planned (Medium) in this PR, and → Done when both implementation PRs land."
prior_art_branch: "claude/initial-menu-tracking-settings-buxmcl @ 13ca6026c0ff4ce98ce57f9087232fbe08b44588 — a working prototype of Feature A only. Assessed file-by-file in §7. Keep the Core derivation, revise the presentation, do not merge as-is."
features:
  - id: A
    name: "Pre-match tracking status — Points / Health / Pulse stated on the start screen"
  - id: B
    name: "Remembered match setup — Singles + Best of 3 pre-resolved so Start Match is 3 taps, not 5"
relatedness_verdict: "Implementation-orthogonal, product-coupled, with one HARD data dependency and one HARD ordering dependency. Ship as one feature in two PRs, B first. Full reasoning in §3."
hard_couplings:
  - "MatchFormat.perpetualPoints sets disablesPointTracking: true (ScoreTypes.swift:135). A strip that reports statsTrackingEnabled without consulting the format will claim 'Points: On' for a format that records no point outcomes at all. Feature A is only CORRECT if it reads Feature B's resolved format."
  - "Ordering: today matchFormat is chosen AFTER leaving the start screen, so on the start screen it is whatever was left in memory (.standard on cold launch). The strip cannot be format-truthful until the format is known BEFORE the strip renders — which is exactly what B's persisted default provides. B must land first."
scope:
  in_scope:
    - "Packages/DeuceMateCore/Sources/DeuceMateCore/Settings/MatchSetupDefaults.swift (new — pure decode/validate of the remembered format + type, PR 1)"
    - "Packages/DeuceMateCore/Sources/DeuceMateCore/Settings/MatchTrackingStatus.swift (new — pure resolution of the three facets, PR 2; rebased from the prior-art branch + format awareness)"
    - "Packages/DeuceMateCore/Sources/DeuceMateCore/Stats/HRZone.swift (expose isUsableBirthYear so 'calibrated' is not inferred by comparing against 190, PR 2)"
    - "DeuceMate/DeuceMate Watch App/HomeView.swift (the pre-match card: default row + tracking strip; skip the format and match-type screens)"
    - "DeuceMate/DeuceMate Watch App/ScoreViewModel.swift (hydrate matchFormat/matchType from defaults when no live match is restored; persist on match start; expose trackingStatuses)"
    - "DeuceMate/DeuceMate Watch App/WorkoutManager.swift (publish healthAccess; refreshHealthAccess() on foreground)"
    - "DeuceMate/DeuceMate Watch App/DeuceMateApp.swift (refresh health access on scenePhase == .active)"
    - "DeuceMate/DeuceMate Watch App/TrackingStatusStrip.swift (new — presentation only)"
    - "docs/architecture/file-inventory.md, docs/features/KNOWN_LIMITATIONS.md, docs/features/TECHNICAL_DEBT.md (#5 status), CLAUDE.md §0 (watch-local key exceptions)"
    - "docs/features/assets/{home-screen-before-after,tracking-strip-states,match-setup-sheet}.svg — hand-written SVG mockups, drawn 1:1 at 45 mm using the real AppTheme Classic gradients. Diagrams, not screenshots."
  out_of_scope:
    - "iPhone app — the phone does not start live matches. No wire key, no MatchSyncKey, no phone settings row. See §5.6."
    - "Removing or repurposing the 'Warming Up' screen — it starts the HealthKit workout session before the match clock, which is a real function. Posed as open question OQ-2, not built."
    - "Reviving the dead MatchSyncKey.workoutSessionEnabled as a user-facing in-app Health toggle. Explicitly rejected in §9.2."
    - "Remembering who serves first — decided by coin toss every match; remembering it would be actively wrong. §5.5."
key_facts:
  - "Taps from start screen to first point today: 5 (Start Match → format → Warm Up Complete → Singles → Me), 6 with Changeover Compass on. Verified against HomeView.swift:337-343 + RootModal.body:66-154."
  - "matchFormat and matchType are @Published on ScoreViewModel (ScoreViewModel.swift:325-326) with NO UserDefaults didSet. They are part of the restored live-match state only; on a cold launch with no match in progress they reset to .singles / .standard and the UI forces a fresh choice anyway."
  - "THREE sites write matchType/matchFormat, and hydrating in ScoreViewModel.init works at none of them. init runs BEFORE the restore: DeuceMateApp.swift:16 calls loadState() in .onAppear. loadState()'s success path assigns from the saved AppState (1660, 1666) and its catch path hard-writes .singles/.standard (1696-1697), so both exits clobber init. resetMatch() also hard-writes .singles/.standard (1404-1405) and then saveState(), so finishing a match PERSISTS the fallback. Hydrate at the tail of loadState() and the tail of resetMatch() instead — see §5.4."
  - "There is NO in-app toggle for Health tracking. It is the HKHealthStore permission, requested once at launch (DeuceMateApp.swift:17) and revocable only from the Watch app on iPhone. The app can report it, not set it."
  - "Pulse Coach zones are derived at DISPLAY time — PulseCoachInsights.insights(..., maxHR:) takes maxHR as a parameter. Setting a birth year after a match recomputes that match's zones. Pulse calibration is therefore REVERSIBLE; point tracking and Health capture are NOT. This asymmetry drives §4."
  - "PointStat.heartRateBPM / .stepsCumulative are captured live on the watch (PointStat.swift:111,116). No workout session ⇒ those fields are nil forever for that match."
  - "SettingsCopy.workoutSession and SettingsCopy.iCloudSync are defined in Core but referenced by NO UI on main (verified by grep). The prior-art branch gives .workoutSession a home as the Health chip's 'On' detail — a genuine cleanup, keep it."
  - "MatchSyncKey.workoutSessionEnabled is decoded by SyncIncomingPayload but both WatchMatchSyncService.swift:239 and PhoneMatchSyncService.swift:444 `break` on it. It is a dead wire key. Leave it alone; do not repurpose it (§9.2)."
  - "Height budget (§6.1): rows are 44 pt with 10 pt spacing and HomeView's default .padding() costs 32 pt, against 215 pt on 41 mm. Keeping Past Matches as a full row (220 pt content) or keeping the card mid-match (220 pt) BOTH overflow even 45 mm — which is why the prior-art branch reached for a ScrollView. Demoting Past Matches to the icon row and hiding the card while a match is in progress bring every state to 184–198 pt, so no ScrollView is needed and Start Match stays centred."
  - "The card is a PRE-match card and must be hidden when matchInProgress: the format is locked and the point-tracking toggle is already .disabled(matchInProgress) (HomeView.swift:497), so mid-match it would show state the user cannot act on."
open_questions:
  - id: OQ-1
    question: "When Health is off, the Pulse chip is a second grey chip for the same single cause. Collapse to two chips, or keep three fixed?"
    recommendation: "Collapse. See §4.3."
  - id: OQ-2
    question: "Should the 'Warming Up' screen become skippable, taking the flow from 3 taps to 2?"
    recommendation: "Not in this feature. It touches workout-session semantics and the win is one tap. Revisit once B has shipped and the flow has been lived with."
  - id: OQ-3
    question: "Last-used format, or an explicitly configured default in Settings?"
    recommendation: "Last-used, made safe by being displayed on the card. See §5.2."
-->

# Plan: Match Start — Remembered Setup + Pre-Match Tracking Status

## 1. The report

> "With the current menu at the start, I forget if health tracking is on or if point
> tracking is on… when starting it is clear to see that Health tracking is off, point
> tracking is off, pulse coach off… We could also add in default of singles / best of 3
> which is my regular, to save time."

Two asks. This document treats them as **one feature shipped in two PRs**, and §3
justifies that decision rather than assuming it — the owner explicitly asked whether
they are related or orthogonal.

This is also the product/UX conversation that `TECHNICAL_DEBT.md` **#5 — Simplify
first-run and match-start UX** was parked awaiting ("This is a product design
decision, not a software engineering improvement… Should be addressed in a
product/UX conversation rather than a PR").

### 1.1 The proposal at a glance

![Watch start screen today versus proposed: the proposed screen adds a pre-match card
holding a remembered "Singles · Best of 3" row and a three-chip tracking strip, and
demotes Past Matches to the icon row](assets/home-screen-before-after.svg)

Mockups are hand-written SVG drawn 1:1 at 45 mm (198 × 242 pt) using the real Classic
theme gradients from `AppTheme.swift`. They are diagrams, not screenshots — no build
exists yet.

---

## 2. What the start flow does today

```
HomeView  (the start screen)
 ├─ ▶ Start Match ──────────────► sheet: "Match Format"  — 6 full-width buttons
 ├─ ■ End Match  (if in progress)      │   standard / bestOf3FullFinalSet / quick4Games
 ├─ ≡ Past Matches (if any)            │   superTiebreak / perpetualSuperTiebreak / perpetualPoints
 └─ [⚙︎ Settings] [📖 Guide]           ▼
                                  sheet: RootModal
                                       ├─ "Warming Up"      → [Warm Up Complete]   ← starts the workout session
                                       ├─ "Match Type"      → [Singles] [Doubles]
                                       ├─ "Who serves first?" → [Me] [Opponent]     (or Me / Partner / Opponent)
                                       ├─ "Correct court side?" → [✓ Confirmed]     (only if Changeover Compass on)
                                       └─ ContentView — live scoring
```

**Taps from start screen to first point: 5.** Six with Changeover Compass on.
(`HomeView.swift:337-343`, `RootModal.body` `HomeView.swift:66-154`.)

Two things are wrong with this, and they are mirror images of each other:

1. **The flow interrogates you about what rarely changes.** Format and singles/doubles
   are the same almost every match. They are asked every time, in full, as two blocking
   screens.
2. **The flow says nothing about what silently changes your data.** Whether the match
   will record point outcomes, heart rate, or usable Pulse Coach zones is decided by
   three settings that are set once and then invisible — and two of the three cannot be
   fixed after the match ends.

The pre-match screen is spending its taps on the reversible decisions and staying
silent on the irreversible ones. That inversion is the actual defect.

### 2.1 The three facets, and why they are the right three

| Facet | Controlled by | Changes what the finished match contains? | Fixable after the match? |
|---|---|---|---|
| **Point tracking** | `statsTrackingEnabled` toggle — watch Settings or iPhone Settings, synced | **Yes** — every derived stat comes from `[PointStat]` | **No.** There is no post-hoc categorisation path. |
| **Health tracking** | **No in-app toggle.** The `HKHealthStore` permission, requested at `DeuceMateApp.swift:17`, revocable only from the Watch app on iPhone | **Yes** — `PointStat.heartRateBPM`, `.stepsCumulative`, plus `MatchRecord.totalSteps` / `.totalDistanceMeters` / `.totalCaloriesKcal` | **No.** No workout session ⇒ those fields are `nil` forever.¹ |
| **Pulse Coach** | Needs Health, *plus* a calibrated max HR (`userBirthYear` or `userMaxHROverride`) | No — it consumes HR that Health already captured | **Yes.** `PulseCoachInsights.insights(…, maxHR:)` takes `maxHR` as a parameter; zones are computed at display time. Set your birth year next month and every past match recomputes. |

¹ The iPhone's `HealthKitHRFetcher` reads raw HR samples for the match window under its
own iOS authorization, so a Health-denied watch match may still surface sparse
background heart rate on the phone. It will never surface calories, distance, or
per-point HR. Treat "Health off" as "the match is thin", not "the match is empty".

**This asymmetry is the single most important design fact in this document.** Points
and Health are *capture* — miss them and the data does not exist. Pulse Coach is
*calibration* — get it wrong and you can fix it later. The three facets must be shown,
because the owner wants to know all three states, but they must not be shown as peers.

---

## 3. Are the two asks related? — the verdict

**Implementation-orthogonal. Product-coupled. Two hard dependencies.**

### 3.1 Orthogonal, mechanically
Feature A reads three settings and paints them. Feature B persists two enums and
short-circuits two setup screens. Different data, different files, no shared type.
Neither needs the other to compile.

### 3.2 Coupled, as product
They are the same defect seen from opposite sides — §2's inversion. B removes the
prompts that do not earn their tap; A adds the statement that does. They also compete
for the same scarce resource: **vertical pixels and taps on the pre-match path.** Doing
them separately means designing that path twice.

More sharply: **doing B alone makes the problem A solves worse.** Cut the flow from 5
taps to 3 and you now blast past the settings you cannot fix even faster. B *raises*
the value of A.

### 3.3 Two hard dependencies (this is what settles it)

**Data dependency.** `MatchFormat.perpetualPoints` sets `disablesPointTracking: true`
(`ScoreTypes.swift:135`), and `ScoreViewModel` honours it ahead of the user's setting
(`ScoreViewModel.swift:872, 933`). A strip that reads `statsTrackingEnabled` alone will
display **"Points: On" for a format that records no point outcomes at all.** Feature A
is only *correct* if it consults the resolved format — which is Feature B's data.

**Ordering dependency.** Today `matchFormat` is chosen *after* the start screen is
dismissed. On the start screen it is whatever was left in memory — `.standard` on a
cold launch. So a strip rendered there cannot be format-truthful today. Feature B's
persisted default is what makes the format knowable *before* the strip renders.

**⇒ Ship B first, then A.** The prior-art branch built A alone and inherits exactly
this bug (§7).

---

## 4. Feature A — pre-match tracking status

### 4.1 Which settings belong on the strip

The rule that decides membership:

> A setting earns a place on the pre-match strip **only if it changes what the finished
> match contains AND cannot be fixed afterwards.**

Applied honestly:

| Watch setting | Changes the record? | Fixable later? | On the strip? |
|---|---|---|---|
| Track point outcome | Yes | No | **Yes** |
| Health permission | Yes | No | **Yes** |
| Pulse Coach calibration | No | **Yes** | **Yes — by exception, see below** |
| Changeover Compass | No (in-match guidance only) | — | No |
| Announce scores on iPhone | No | — | No |
| iPhone Input | No | — | No |
| Appearance theme | No | — | No |
| Player name | No (announcements only) | Yes | No |

**So: not all settings. Three, not eight.** The five rejected settings change how the
match *feels while you play it*, never what you get to look at afterwards. Putting them
on the strip would dilute the two chips that genuinely cannot be undone.

**Pulse Coach is kept as a deliberate exception** to the second half of the rule. It
fails the "not fixable later" test, but it earns its slot for two reasons: it is the
*reason* a club player grants Health access at all, and the pre-match strip is the only
place the silent 190 bpm fallback would ever be surfaced before it matters. Its copy
must be honest that it is recoverable — see 4.2.

### 4.2 States and copy

Three facets × the states each can actually be in. `TrackingReadiness` is
`.on` (green) / `.partial` (amber) / `.off` (grey).

| Facet | Condition | Chip | Readiness | Detail line |
|---|---|---|---|---|
| Points | format sets `disablesPointTracking` | `—` | `.off` | "Perpetual Points doesn't record point outcomes." |
| Points | `statsTrackingEnabled` | `On` | `.on` | `SettingsCopy.trackPointOutcome.text` |
| Points | otherwise | `Off` | `.off` | "No shot or outcome stats will be recorded for this match." |
| Health | `.authorized` | `On` | `.on` | `SettingsCopy.workoutSession.text` |
| Health | `.notDetermined` | `Ask` | `.partial` | "DeuceMate will ask for Health access when the match starts." |
| Health | `.denied` | `Off` | `.off` | "No heart rate, steps, or calories. Allow DeuceMate under Privacy → Health in the Watch app on iPhone." |
| Health | `.unavailable` | `Off` | `.off` | "This watch cannot record Health data." |
| Pulse | Health off/unavailable | *(suppressed — see 4.3)* | | |
| Pulse | no birth year and no override | `Est.` | `.partial` | "190 bpm default — set your birth year for accuracy. **Past matches recompute if you set it later.**" |
| Pulse | calibrated | `On` | `.on` | "Heart-rate zones use your N bpm max HR." |

![Every state the tracking strip can be in: all-green steady state; point tracking off;
Health denied with the Pulse chip suppressed; Health permission not yet answered;
Pulse Coach on the 190 bpm default in amber; and the format-suppressed em-dash
state](assets/tracking-strip-states.svg)

The bolded clause is the change from the prior-art branch, and it is the copy that
encodes §2.1's asymmetry: Points and Health say *this match*, Pulse says *any time*.

**The state must never be inferred by comparing the resolved max HR against 190** — 190
is also a legitimate age-derived result (age 30). Use `HRZone.isUsableBirthYear` /
`HRZone.isValidOverride`. The prior-art branch got this right; keep it.

### 4.3 Collapse the Pulse chip when Health is off — OQ-1

When Health is `.denied` or `.unavailable`, Pulse Coach is off *because* Health is off.
Showing two grey chips for one cause is 33% of a 41mm watch screen spent on redundancy,
and it teaches the user that grey chips are noise.

**Recommendation: suppress the Pulse chip when Health is off**, and let the Health
chip's detail carry the consequence: *"No heart rate, steps, or calories — Pulse Coach
can't run. Allow DeuceMate under Privacy → Health in the Watch app on iPhone."* The
strip then shows two wide, legible chips in the degraded case and three when the third
carries information.

Counter-argument, stated fairly: a strip whose arity changes is less predictable to
scan, and the owner asked to see all three states. Mitigation: the **Settings rows**
(same `MatchTrackingStatus` values, full width, room for the detail) always show all
three, so the complete picture is one tap away and never disappears.

### 4.4 Known limitation to document, not fix

`HKHealthStore.authorizationStatus(for:)` can only report **share** authorization —
HealthKit deliberately hides read authorization so an app cannot infer what a user is
hiding. Workout share status is the honest proxy: no share, no workout session, no
samples. But a user who allows workout writing and denies heart-rate reading will see
**"Health: On" and still get no HR.** Uncommon, unresolvable pre-match, and strictly
better than showing nothing.

**Action: add as `KNOWN_LIMITATIONS.md` #2** with this reasoning, in the same PR.

---

## 5. Feature B — remembered match setup

### 5.1 What it does

On the start screen, under Start Match, a row states the setup the next match will use
and taps to change it:

```
Singles · Best of 3 (Club/League)          ⌄
```

Tapping opens the existing format sheet, extended with a Singles/Doubles choice. The
chosen pair is persisted and pre-applied, so `RootModal` skips both the format screen
and the Match Type screen.

**Taps to first point: 5 → 3** (Start Match → Warm Up Complete → Me).

![The Match Setup sheet on the watch: a Singles/Doubles segmented control above the
existing six-format list, with Best of 3 Club/League selected](assets/match-setup-sheet.svg)

### 5.2 Last-used, not a configured default — OQ-3

Persist whatever the last match used. Zero configuration, and it converges on "my
regular" without the owner ever visiting a settings screen.

The obvious objection: you play one Super Tiebreak with a friend, and next week your
league match silently starts as a Super Tiebreak. **That failure mode is exactly what
Feature A's card neutralises** — the format is stated on the start screen and is one tap
from being changed. A remembered default is only safe *because* it is displayed. This is
the third argument that these two ship together.

Rejected alternative: an explicit "Default match" entry in Settings. More surface, more
copy, more sync temptation, and the owner has to know to go set it.

### 5.3 Where it is stored

Two new **watch-local** `UserDefaults` keys:

| Key | Type | Value | Fallback |
|---|---|---|---|
| `defaultMatchFormat` | `String` | `MatchFormat.rawValue` | `.standard` |
| `defaultMatchType` | `String` | `MatchType.rawValue` | `.singles` |

Decoding must be total: an absent, empty, or unrecognised raw value (a format retired in
a future build) falls back rather than crashing. That is the entire content of the new
Core type, and it is why the type exists — so the fallback is unit-tested without a
simulator.

```swift
// Packages/DeuceMateCore/Sources/DeuceMateCore/Settings/MatchSetupDefaults.swift
public struct MatchSetupDefaults: Sendable, Equatable {
    public static let formatKey = "defaultMatchFormat"
    public static let typeKey   = "defaultMatchType"

    public let format: MatchFormat
    public let type: MatchType

    public static let fallback = MatchSetupDefaults(format: .standard, type: .singles)

    /// Total decode — unknown / absent / retired raw values fall back.
    public static func resolve(formatRaw: String?, typeRaw: String?) -> MatchSetupDefaults
}
```

> ⚠️ **`CLAUDE.md` §0 grep trap.** The §0 consistency check asserts that every
> `forKey:` string literal in the two apps matches a `MatchSyncKey` raw value. These two
> keys deliberately do **not** — they are watch-local (§5.6). Declaring them as constants
> on `MatchSetupDefaults` gives them one source of truth, and the PR **must** add them to
> the documented-exception list in `CLAUDE.md` §0 alongside the announcements aliases.
> Skipping that leaves a false positive that will confuse the next agent.

### 5.4 Where it is applied — three sites that all overwrite the pair

⚠️ **Do not hydrate in `ScoreViewModel.init`.** It runs *before* the restore, and both
exits of the restore hard-write the fallbacks, so anything seeded in `init` is silently
discarded. The three sites, in the order they fire:

| # | Site | What it does to `matchType` / `matchFormat` |
|---|---|---|
| 1 | `ScoreViewModel.init` | Leaves the property initialisers — `.singles` / `.standard` (`ScoreViewModel.swift:325-326`) |
| 2 | `loadState()`, called from `DeuceMateApp.swift:16` `.onAppear` — **after** `init` | **Success path:** assigns from the saved `AppState` (`ScoreViewModel.swift:1660, 1666`). **Catch path:** hard-writes `.singles` / `.standard` (`1696-1697`) |
| 3 | `resetMatch()` | Hard-writes `.singles` / `.standard` (`1404-1405`), then `saveState()` — so finishing a match *persists* the fallback |

Site 3 is the one that is easy to miss: without it the remembered pair survives launch
but is destroyed the moment the previous match ends, which is precisely when the next
match is about to be set up.

**Recipe.** One helper, called at two tails:

```swift
/// Seeds the next match's setup from the remembered pair. No-op while a match
/// is live, so resuming a Super Tiebreak is never rewritten to Best of 3.
private func applyRememberedSetupIfIdle() {
    guard currentServer == nil, currentMatchStats.isEmpty, history.isEmpty else { return }
    let d = MatchSetupDefaults.resolve(
        formatRaw: UserDefaults.standard.string(forKey: MatchSetupDefaults.formatKey),
        typeRaw:   UserDefaults.standard.string(forKey: MatchSetupDefaults.typeKey))
    matchFormat = d.format
    matchType   = d.type
}
```

- **Tail of `loadState()`**, outside the `do`/`catch` so it covers both exits.
- **Tail of `resetMatch()`**, after the `.singles` / `.standard` writes and **before**
  `saveState()`, so the persisted `AppState` carries the remembered pair forward and
  site 2's success path restores it on the next launch. The guard is a no-op there —
  `resetMatch` has just ended the match — but calling the same helper keeps one rule.

The idle guard is the same triple predicate `RootModal.startMatchTimerIfNeeded` already
uses to decide whether a match is genuinely new (`HomeView.swift:56-60`) — reuse it
rather than inventing a second definition of "no match in progress".

Persist on match start — in `commitServerSelection()` (`HomeView.swift:158`), the one
place both the singles and doubles paths funnel through, and the point at which the
choice is genuinely committed.

`RootModal.onAppear` then sets `matchTypeChosen = true` when a remembered type exists,
alongside the existing `isTiebreakOnlyFormat` warm-up skip (`HomeView.swift:141-146`) —
which is the established precedent for pre-resolving a setup screen.

### 5.5 What is *not* remembered

**Who serves first.** It is decided by a racquet spin every match. Pre-selecting it
would be wrong, and an over-eager implementation will be tempted — it looks like just
another setup screen. It is not. The server screen stays.

### 5.6 No sync, no wire key

The phone does not start live matches; the watch owns every match it has touched
(`CLAUDE.md` §1). Manual match entry on the phone picks its own format inline. There is
**no** `MatchSyncKey` for these values, no handler in either sync service, no phone
settings row.

This is a deliberate scope boundary, stated because the reflex when adding any setting
to this codebase is to run the §4 four-site recipe. Do not. If a shared default is ever
wanted for manual entry, that is a separate change and it must then follow that recipe
in full.

---

## 6. Layout — the real constraint

Both features want space directly under Start Match, on a screen that is already four
rows deep mid-match. The prior-art branch handled this by converting `HomeView`'s
centred `VStack` + `Spacer()`s into a `ScrollView` (`HomeView.swift:334`), which
un-centres Start Match and lets the primary action drift off-screen on a 41mm watch.
That is a regression, not a solution.

**Proposal: one combined pre-match card of 58 pt, replacing two full-screen setup
steps.** Drawn in §1.1.

### 6.1 The height budget

Screens are 176 × **215** pt (41 mm), 198 × **242** pt (45 mm), 205 × 251 pt (49 mm
Ultra). `HomeView` uses the default `.padding()` — 16 pt top and bottom, so **32 pt** of
the budget is gone before any button. Rows are 44 pt (`HomeButtonStyle` `minHeight`)
with 10 pt spacing; the card is 58 pt.

| State | Rows | Content | + padding | 41 mm (215) | 45 mm (242) |
|---|---|---:|---:|:---:|:---:|
| Today, no match in progress | Start · Past Matches · icons | 152 | **184** | ✅ | ✅ |
| **Proposed, no match** | Start · **card** · icons ×3 | 166 | **198** | ✅ | ✅ |
| **Proposed, match in progress** (card hidden) | Resume · End · icons ×3 | 152 | **184** | ✅ | ✅ |
| ✗ if Past Matches stays a full row | Start · card · Past · icons | 220 | 252 | ❌ | ❌ |
| ✗ if the card is kept mid-match | Resume · End · card · icons | 220 | 252 | ❌ | ❌ |

The two ❌ rows are why the prior-art branch reached for a `ScrollView`. Two decisions
remove the need for one entirely:

- **Past Matches moves into the icon row.** It is a navigational destination of the same
  class as Settings and Guide, and it is already conditional on having any history. That
  frees 54 pt (44 + 10), which pays for the 68 pt card with 14 pt of net growth.
  Trade-off, stated fairly: Past Matches is probably used more often than Guide, and
  demoting it costs it a label.
- **The card is hidden while a match is in progress.** It is a *pre*-match card: mid-match
  the format is locked, and the point-tracking toggle is already `.disabled(matchInProgress)`
  (`HomeView.swift:497`). Showing tracking state you cannot act on is noise.

**Keep the centred `VStack` + `Spacer()`s. Do not adopt a `ScrollView`** — with those two
decisions every state fits, including 41 mm, and the primary action stays centred.
Verify on a 41 mm simulator before merge; the content width there is 144 pt, not the
166 pt the mockups are drawn at, so the three chips get ~44.7 pt each.

### 6.2 Presentation decisions

- **Chips are icon + state on one line** — not the prior art's three-line
  icon/label/state stack. The icon carries the identity; the word ("Points", "Health")
  is redundant next to a heart on a screen this size, and the full names live in the
  Settings rows.
- **The card is two tap targets, not one.** The format row opens the setup sheet; the
  chip row opens Settings. Merging them would make the most common action (change
  format) collide with the rarest (change a tracking setting).
- **The strip is not inside the Start Match button.** Tempting for space; rejected —
  it makes the primary action's tap target ambiguous.

Net: the pre-match screen grows by 14 pt and the flow loses two full screens.

---

## 7. Prior art — `claude/initial-menu-tracking-settings-buxmcl` @ `13ca602`

A working prototype of **Feature A only** (712 insertions, 12 files). Assessment:

### Keep
- **`Core/Settings/MatchTrackingStatus.swift`** — derivation in the package, unit-tested
  with no simulator, HealthKit-free. Exactly the `SettingsCopy` / `ICloudBackupCopy`
  precedent. `HealthAccess` as a platform-independent enum the watch maps into is the
  right seam.
- **`HRZone.isUsableBirthYear`** — extracted so "calibrated" is not inferred by
  comparing against 190. Genuinely good; `resolveMaxHR` gets simpler as a side effect.
- **`WorkoutManager.healthAccess` + `refreshHealthAccess()` on foreground** — necessary,
  because the permission is revocable from the iPhone while the watch app is backgrounded.
- **Reusing the same statuses as full-width Settings rows** — one source, and it gives
  the orphaned `SettingsCopy.workoutSession` (defined in Core, referenced by no UI on
  `main`) a real home.
- **`MatchTrackingStatusTests` (206 lines) and the `HRZoneTests` additions.**

### Revise
1. **Not format-aware** — the §3.3 correctness bug. `MatchTrackingStatus.all(…)` must
   take the resolved `MatchFormat` and return the `—` / "doesn't record point outcomes"
   state when `config.disablesPointTracking`.
2. **Health/Pulse redundancy when Health is off** — two grey chips, one cause (§4.3).
3. **`HomeView` → `ScrollView`** — un-centres the primary action (§6).
4. **Three-line chips** — too tall once Feature B's row joins them (§6).
5. **Pulse "Est." copy** does not say the calibration is retroactive (§4.2).
6. **`LiveTrackingStatusStrip` takes `@ObservedObject var workoutManager` and never
   reads it.** It is load-bearing — `healthAccess` publishes on `WorkoutManager`, which
   is a plain stored property of `ScoreViewModel`, so without that observation the strip
   never redraws. It also looks like dead weight, and the next refactor will delete it
   and silently freeze the Health chip. **Fix properly:** forward
   `workoutManager.objectWillChange` into `ScoreViewModel`'s in `init`, then the strip
   takes the view model alone.

### Add
- Feature B in its entirety.
- `KNOWN_LIMITATIONS.md` entry for the share-authorization proxy (§4.4).
- `TECHNICAL_DEBT.md` #5 → **Done** (this PR already moved it Parked → Planned).

**Recommendation: do not merge as-is; rebase the Core derivation and rebuild the
presentation on top of Feature B.**

---

## 8. Implementation plan

### PR 1 — `[Watch] Remember the last match setup` (Feature B)
1. `Core/Settings/MatchSetupDefaults.swift` — keys, `resolve(formatRaw:typeRaw:)`, fallback.
2. `Core/Tests/MatchSetupDefaultsTests.swift` — absent / empty / unknown / retired raw
   values, and a round-trip for every `MatchFormat` × `MatchType`.
3. `ScoreViewModel` — one `applyRememberedSetupIfIdle()` helper called at the tail of
   **both** `loadState()` and `resetMatch()` (§5.4 — *not* in `init`); persist in a small
   `persistMatchSetupDefaults()`.
4. `HomeView` — the default row (hidden when `matchInProgress`); **Past Matches moves
   into the icon row** (§6.1); extend the format sheet with Singles/Doubles;
   `commitServerSelection()` persists; `RootModal.onAppear` pre-resolves `matchTypeChosen`.
5. Watch tests, one per §5.4 site: cold launch with saved defaults hydrates; a corrupt
   state file (the `catch` path) still hydrates; a restored **live** match is **not**
   overwritten; `resetMatch()` leaves the remembered pair in the saved `AppState`, not
   `.singles` / `.standard`.
6. `docs/architecture/file-inventory.md` (new Core file), `CLAUDE.md` §0 key exceptions.

### PR 2 — `[Watch] State what the next match will record` (Feature A)
1. `Core/Settings/MatchTrackingStatus.swift` — rebased from `13ca602`, **plus** the
   `MatchFormat` parameter and the format-suppressed Points state.
2. `Core/Stats/HRZone.swift` — `isUsableBirthYear` (as on the branch).
3. `WorkoutManager.healthAccess` + `refreshHealthAccess()`; `DeuceMateApp` foreground
   refresh; `ScoreViewModel.trackingStatuses` + `objectWillChange` forwarding (§7 item 6).
4. `TrackingStatusStrip.swift` — single-line chips, Pulse suppression, Settings rows.
5. `HomeView` — strip into the card; Settings sheet header rows.
6. Tests: `MatchTrackingStatusTests` extended for format suppression + Pulse suppression;
   `HRZoneTests`; `SettingsCopyTests` still passes `maxLength` for any new copy.
7. `file-inventory.md`, `KNOWN_LIMITATIONS.md` #2, `TECHNICAL_DEBT.md` #5 → Done.

**PR 1 must land first** (§3.3). PR 2 without it ships a Points chip that lies about
Perpetual Points and a card with nothing to state.

---

## 9. Rejected alternatives

**9.1 Warn-only strip.** Show nothing when all three are healthy; show a loud amber row
only on an exception. Better steady-state watch design — three green chips become
invisible within a week, which defeats the purpose. Rejected because it does not answer
the actual report: *"I forget if health tracking is on"* is a request for positive
confirmation, not an alarm. Middle path adopted instead: always state, but weight
colour and copy so exceptions dominate.

**9.2 Revive `MatchSyncKey.workoutSessionEnabled` as an in-app Health toggle.** The key
exists, `SyncIncomingPayload` decodes it, and both services `break` on it — it is dead.
Reviving it would make Health something the owner can *control* on the watch rather than
merely observe, and there is a real use ("score this match, don't log a workout").
Rejected: a second in-app switch gating something the system permission already gates is
two sources of truth for one behaviour, and the strip would then need a fourth state to
distinguish "you turned it off" from "iOS turned it off". Leave the key dead and
reserved; do not delete it either (it is part of the wire contract and both sides
already tolerate it).

**9.3 Show all eight settings on the start screen.** Answers the owner's "should all the
settings be shown?" — no. Five of the eight change how the match *feels* while you play,
never what you can look at afterwards (§4.1). Including them would dilute the two chips
that are genuinely irreversible, and would not fit.

**9.4 Sync the remembered setup to the iPhone.** §5.6.

**9.5 Remember who serves first.** §5.5.

---

## 10. Verification

Everything load-bearing is in Core and testable with `swift test` — no simulator:

- `MatchSetupDefaultsTests` — total decode, every enum pair, retired raw values.
- `MatchTrackingStatusTests` — the full state table in §4.2, including
  `disablesPointTracking` suppression and Pulse suppression when Health is off.
- `HRZoneTests` — `isUsableBirthYear` boundaries (age 5 / 100, `birthYear == currentYear`,
  0, 1900) and that `resolveMaxHR` is unchanged for every previously-covered input.
- `SettingsCopyTests` — `maxLength` still holds.

Watch target (`xcodebuild test`, needs `import DeuceMateCore`):
- cold launch hydrates defaults; a corrupt state file still hydrates; a restored live
  match is not overwritten; `resetMatch()` persists the remembered pair rather than
  `.singles` / `.standard` (§5.4 — all three write sites);
- `commitServerSelection()` persists the pair.

Manual, on a **41 mm** simulator or device — none of these are text-checkable, and the
§6.1 budget is arithmetic, not a measurement:
- Start Match still centred and reachable **without a `ScrollView`**, both with and
  without a match in progress, and with and without past matches.
- Three chips still legible at the 41 mm content width of 144 pt (~44.7 pt each).
- VoiceOver reads the strip as one element and the Settings rows individually.
- Revoke Health in the Watch app on iPhone → foreground DeuceMate → the Health chip
  flips to Off and the Pulse chip disappears.
- Choose Perpetual Points on the card → the Points chip shows `—`, not `On`.

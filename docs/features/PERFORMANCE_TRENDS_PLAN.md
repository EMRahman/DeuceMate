<!--
machine-readable summary (parse this block first)

status: implemented
author: Claude (Opus 5), design session with the owner
date: 2026-08-25
implemented_date: 2026-08-26
blocked_by: null
delivers: "docs/features/IPHONE_COMPANION_APP_PLAN.md §'Future work (explicitly deferred)' → 'Phone-only stats — career-level rollups across matches: serve % over time, W:UE trend lines, opponent-specific records. Add fields to MatchStatsSummary or a new CareerStatsSummary and surface a third screen on iOS.' This plan delivers the first two; opponent-specific records are NOT deliverable — see key_data_model_facts."
follow_on: "docs/features/HEALTH_TRENDS_PLAN.md — adds the Fatigue and Effort groups (5 metrics) from the movement data this plan's catalogue does not read, plus rally length split by serving side (4 metrics inside this plan's own Rally Depth group), along with the .steps TrendMetric.Unit case and the per-unit chart bucketing it needs. Its catalogue was cut from 13 metrics after review; that plan's section 3 records what went and why."
closes_backlog_item: "TECHNICAL_DEBT.md #7 — Convert formatted string stats to typed values in MatchStatsSummary. Its recorded trigger is 'Before localization, structured stats export, or graphing'. This feature graphs the W:UE ratio, so the trigger fires here. PR 1."
touches_backlog_item: "TECHNICAL_DEBT.md #13 — Split PastMatchesView. Its recorded trigger is 'Opportunistically on the next substantial edit, before the file crosses ~1k lines.' This is that edit, so all Trends UI lands in new files under Views/Trends/ and PastMatchesView grows by ~6 lines rather than ~300. #13 is not closed — the existing 745 lines are untouched."
scope:
  in_scope:
    - "Packages/DeuceMateCore/Sources/DeuceMateCore/Stats/MatchStatsSummary.swift (PR 1 — typed RatioStat replaces three pre-formatted String fields)"
    - "Packages/DeuceMateCore/Sources/DeuceMateCore/Stats/MatchTrendSample.swift (new — one match reduced to raw counters, PR 2)"
    - "Packages/DeuceMateCore/Sources/DeuceMateCore/Stats/TrendMetric.swift (new — the metric catalogue, PR 2)"
    - "Packages/DeuceMateCore/Sources/DeuceMateCore/Stats/PerformanceTrends.swift (new — windowing, filtering, pooling, deltas, PR 2)"
    - "Packages/DeuceMateCore/Tests/DeuceMateCoreTests/{MatchTrendSampleTests,TrendMetricTests,PerformanceTrendsTests}.swift (new)"
    - "Packages/DeuceMateCore/Tests/DeuceMateCoreTests/MatchStatsSummaryTests.swift (PR 1 — assert on typed values)"
    - "DeuceMate/DeuceMate/Views/Trends/{TrendsSection,TrendSparkline,TrendsView,TrendChart,TrendsSamples}.swift (new, PR 3)"
    - "DeuceMate/DeuceMate/Views/PastMatchesView.swift (PR 3 — one Section inserted, ~6 lines)"
    - "DeuceMate/DeuceMate/Views/MatchDetailView.swift, DeuceMate/DeuceMate/Export/MatchExporter.swift, DeuceMate/DeuceMate Watch App/MatchStatsView.swift, Packages/.../WebExport/MatchWebViewModel+Comparison.swift (PR 1 — mechanical .formatted call-site updates)"
    - "docs/architecture/file-inventory.md, docs/features/TECHNICAL_DEBT.md, docs/features/IPHONE_COMPANION_APP_PLAN.md, CLAUDE.md, AGENTS.md"
  out_of_scope:
    - "Watch app UI — the watch is the scorer with a 25-match rolling cap (WatchHistory.cap); the phone is the durable archive and the only device that HAS a long history to trend. No wire key, no MatchSyncKey, no watch screen."
    - "Per-opponent trends — MatchRecord has no opponent name or identity field of any kind. Not deferred; not derivable. See key_data_model_facts."
    - "Trends in the text / AI / interactive-HTML exports — every exporter is single-match (MatchExporter, MatchWebViewModel both take one MatchRecord). Cross-match export is a separate feature."
    - "Numeric rally length — PointStat has no shot count. 'Rally depth' means EndingShot phase and nothing else. See §4.3."
    - "Goals, targets, streaks, or any notification/nudge. This screen reports; it does not coach. Coaching stays in RecCoachInsights / PulseCoachInsights, which are per-match."
    - "Changing MatchRecord or PointStat. Trends derive entirely from data already persisted; no schema change, no migration, no backward-compat recipe (CLAUDE.md §4) needed."
key_data_model_facts:
  - "MatchStatsSummary(stats:focal:) exposes BOTH sides from one call: my*/opponent* pairs at MatchStatsSummary.swift:41-53. Trends needs one summary per match with focal: .me, not two."
  - "The my*/opponent* prefixes are relative to `focal`, NOT to the recorder. opponentForcedErrors with focal:.me means 'forced errors the recorder CAUSED' (winner == focal && outcome == .forcedError, MatchStatsSummary.swift:181); myForcedErrors means 'errors the recorder was forced into' (MatchStatsSummary.swift:177). This is the single easiest thing to get backwards in this feature."
  - "MatchRecord has no opponent name, venue, surface, notes, or tags (MatchRecord.swift:7-47). The only name in the app is the recorder's own playerName, held in phone UserDefaults. Opponent-specific records are not derivable."
  - "MatchRecord.iWon is Bool? where nil means in-progress OR draw; isInProgress (MatchRecord.swift:176) is the disambiguator (iWon == nil && endTime == nil)."
  - "MatchFormat.perpetualPoints sets disablesPointTracking: true (ScoreTypes.swift:135) — it never presents the categorisation sheet, so it records no outcomes at all. Including it would plot a permanent flat line of nothing."
  - "PointStat.endingShot and .gameScoreAtStart are Optional and decoded with decodeIfPresent (PointStat.swift:158-159). Matches archived before those fields existed decode with nil. Rally-depth and pressure metrics must be coverage-gated per match, not assumed."
  - "MatchStatsSummary.rallyDepth omits empty buckets via compactMap (MatchStatsSummary.swift:206-214), so its array length varies per match. Keying by EndingShot is required; indexing by position is a bug."
  - "MatchStatsSummary.scoreStates is keyed by hard-coded String labels ('At 30-All', 'At Deuce/Ad', 'In Tiebreak', MatchStatsSummary.swift:219-248). Too fragile to match on across matches — pressure trends use the typed bigPoint*/breakPoint* counters instead."
  - "wueRatio / aggressionIndex / ownErrorsPct are pre-formatted Strings and their numerators are discarded (MatchStatsSummary.swift:57-62). A W:UE trend line cannot be drawn from a String. This is TECHNICAL_DEBT #7."
  - "PhoneStatsStore.history is @Published private(set) [MatchRecord], already newest-first (PhoneStatsStore.swift:37). Trend series are oldest-first, so the derivation reverses it exactly once, in Core."
  - "PastMatchesView's `pastRecords` (PastMatchesView.swift:93-97) UNIONS store.history with syncService.watchMirror rows. Mirror rows are summaries and may carry no stats. Trends must read store.history alone."
  - "Outcome tracking is toggleable MID-MATCH, and when off the watch still records the point as .uncategorized (ScoreViewModel.swift:938, 'Stats off: silently record an uncategorized point for history/analytics'). MatchStatsSummary counts outcome numerators over the categorized subset (:143,176-182) but wonPoints/lostPoints/firstServeTotal over ALL points (:147-148,155). Pairing them depresses every outcome rate on a partially tracked match — so outcome-mix metrics use categorized-only denominators. See §3.6."
  - "Pooling must sum raw numerator/denominator pairs across every match in a block, not average the plotted dots. wueRatio is nil at zero unforced errors — nil meaning 'no errors', not 'no data' — so a 10W/0UE match has no dot but its 10 winners still belong in the pooled numerator. See §3.3 and §4.2."
  - "MatchStatsSummary.init is eager: ~30 filter passes plus PulseCoachInsights, StepsCoachInsights and RecCoachInsights (MatchStatsSummary.swift:325-349). Cheap for one match, wasteful across an archive — hence the equality-invalidated cache in §6.6, not new API (§8.1)."
decisions:
  normalization: "natural-rate-per-metric plus a Rate/Count toggle"
  headline: "sparkline row per metric on the archive screen"
  drill_in: "one screen, grouped sections"
  scope_controls: "window picker plus singles/doubles plus match-format filter"
  filter_order: "filter first, then window"
  block_aggregation: "pooled numerators/denominators for block figures; per-match rates for chart points"
  empty_denominator: "nil, never zero"
  x_axis: "ordinal match index, not date"
  name: "Trends"
open_questions:
  - id: OQ-1
    question: "Should a match the recorder lost 0-6 0-6 in 24 points count as one observation equal to a 3-hour three-setter?"
    recommendation: "Yes, for the chart dots — each match is one observation, and that is what 'per match' means to a player. No, for the block figures — those pool numerators and denominators so the long match carries proportionate weight. Both views are shown; see §3.3."
  - id: OQ-2
    question: "Rate/Count toggle: global for the screen, or per group?"
    recommendation: "Global, one segmented control in the screen header. Per-group state is more flexible and less predictable, and the Attack group contains a ratio-only metric (W:UE) that has no count form either way — see §4.2."
  - id: OQ-3
    question: "Should the inline section hide entirely below the minimum match count, per the house 'empty array = hide the section' idiom (RecCoachInsights.swift:30-32)?"
    recommendation: "No. Render the section with a one-line 'Needs 3 tracked matches — you have 2' explainer. The house idiom exists so a per-match panel does not show noise on thin data; here, hiding means a new user never learns the feature exists. This is a deliberate, stated departure."
  - id: OQ-5
    question: "Should a window whose trackingCoverage is low be labelled, or excluded outright?"
    recommendation: "Labelled, not excluded. §3.6's categorized denominators already make the rate honest for the tracked subset; excluding would throw away a real signal because part of a match went untracked. Surface trackingCoverage on the screen and let the player judge."
  - id: OQ-4
    question: "Aces over time — worth a metric?"
    recommendation: "Not in this feature. ServingPointCategory.ace requires endingShot == .serve (PointStat.swift:226-228), so ace counts are silently zero for every match archived without ending-shot data, which reads as 'you stopped hitting aces'. Revisit once ending-shot coverage is near-universal in a real archive."
-->

# Plan: iPhone Trends — Cross-Match Performance Over Time

## 1. The report

> "Currently where it states 'Past Matches' there should be a new top section called:
> 'Trends' or 'Trending Performance'. The idea is to take the past matches and provide
> graphs on the main areas of play: Double Faults; Unforced Errors; Forced Errors
> (Caused); Winners; as well as the opposite. The same can be done with rally depth
> stats. High level stats might be good on the iOS main page (say last 3 matches?); and
> then tapping into it reveals graphs for the many aspects there is a stat on. The idea
> is to see the trends over time."

The app can already tell a player that they hit 8 unforced errors on Tuesday. It cannot
tell them whether 8 is better or worse than their last ten Tuesdays. Every statistic in
DeuceMate is derived from one match's `[PointStat]`, and `Stats/` contains **zero**
functions taking `[MatchRecord]`. This is the first cross-match feature.

It is also reserved ground rather than a new idea. `IPHONE_COMPANION_APP_PLAN.md:395-398`
deferred it explicitly:

> "**Phone-only stats** — career-level rollups across matches: serve % over time, W:UE
> trend lines, opponent-specific records. Add fields to `MatchStatsSummary` or a new
> `CareerStatsSummary` and surface a third screen on iOS."

This plan delivers serve-percentage-over-time and W:UE trend lines. **Opponent-specific
records it cannot deliver**: `MatchRecord` has no opponent name, or identity field of any
kind (`MatchRecord.swift:7-47`). That bullet should be struck from the companion plan's
future-work list rather than left implying it is merely unbuilt.

### 1.1 The proposal at a glance

The archive screen gains one section above the existing two. Tapping it pushes a full
Trends screen onto `PastMatchesView`'s existing `NavigationStack`.

```
 Matches                    ⚙︎          <   Trends
┌────────────────────────────┐        ┌──────────────────────────────┐
│ TRENDS                  >  │        │ [Last 5│Last 10│Last 20│All] │
│  Double Faults  ▁▃▂▅▂▁▂  ↓ │        │ [All│Singles│Doubles]        │
│  Unforced Err   ▅▄▆▃▄▂▃  ↓ │        │ [All formats ▾]   [Rate│#]   │
│  Winners        ▂▃▄▃▅▆▅  ↑ │        │                              │
│  W:UE ratio     ▂▂▃▄▄▅▅  ↑ │        │ ERRORS                       │
└────────────────────────────┘        │ ┌──────────────────────────┐ │
                                      │ │ ╲    ╱╲                  │ │
 LIVE MATCH                           │ │  ╲__╱  ╲___              │ │
   ...                                │ └──────────────────────────┘ │
                                      │ ●DF ●UE ○FE caused ○FE conc  │
 PAST MATCHES                         │                              │
   12 Aug   6–4 6–2   Won             │ ATTACK  ...                  │
   05 Aug   3–6 6–7   Lost            │ RALLY DEPTH  ...             │
   ...                                └──────────────────────────────┘
```

The inline rows are the four headline metrics; the arrow compares the recent half of the
window against the prior half. The full screen groups every metric the app has a stat for.

---

## 2. What exists today

### 2.1 The archive screen is one screen

`ContentView.swift` is thirteen lines and renders `PastMatchesView()` — there are no tabs.
`PastMatchesView` owns the only `NavigationStack` and its `List` has exactly two sections,
**Live Match** (header, `PastMatchesView.swift:117`) and **Past Matches** (header,
`PastMatchesView.swift:138`). Both toolbar slots are taken: manual entry leading, settings
trailing (`PastMatchesView.swift:157-173`).

There is no filtering or sorting UI on this screen at all. Trends brings the first.

### 2.2 Every statistic is per-match

`MatchStatsSummary(stats:focal:setElapsedSeconds:maxHR:)` (`MatchStatsSummary.swift:135`)
is the whole reporting core, and it takes one match's points. The three insight engines it
drives — `RecCoachInsights`, `PulseCoachInsights`, `StepsCoachInsights` — are likewise
single-match.

The closest existing precedent for folding many records into one value is
`HealthExportConsent.archiveFields(in: [MatchRecord])`
(`Settings/HealthExportConsent.swift:105`) — a pure set-union over the archive. It is a
precedent for the *shape*, not the arithmetic.

### 2.3 What the data model can and cannot support

| Ask | Available? | Source |
|---|---|---|
| Double faults, mine and theirs | ✅ | `doubleFaults`, `opponentDoubleFaults` |
| Unforced errors, mine and theirs | ✅ | `myUnforcedErrors`, `opponentUnforcedErrors` |
| Forced errors **caused** | ✅ | `opponentForcedErrors` (with `focal: .me`) |
| Forced errors **conceded** | ✅ | `myForcedErrors` |
| Winners, mine and conceded | ✅ | `myWinners`, `opponentWinners` |
| Rally depth | ⚠️ as 4 phases | `rallyDepth: [RallyDepthStat]` keyed by `EndingShot` |
| Serve / return / break points / big points | ✅ | typed `Int` counters |
| W:UE ratio, aggression, own-error share | ⚠️ as `String` | pre-formatted; see §7 PR 1 |
| Aces | ⚠️ coverage-gated | needs `endingShot == .serve`; OQ-4 |
| **Per-opponent records** | ❌ | no opponent field exists |
| **Numeric rally length** | ❌ | `PointStat` has no shot count |

---

## 3. Design decisions

### 3.1 Normalizing: natural rates, not raw counts

A super-tiebreak match is ~20 points; a best-of-3 is ~150. Plotting raw double-fault counts
would produce a chart of **match length**, in which every long match reads as a collapse.
That is the single failure mode most likely to make this feature worse than useless.

Each metric therefore has the denominator a player actually thinks in:

- Double faults as a share of **service points**
- Unforced errors as a share of **points I lost**
- Winners as a share of **points I won**
- Forced errors caused as a share of **points I won**

This is not invented for this feature. `RecCoachInsights` already frames its UE rate the
same way and says why (`RecCoachInsights.swift:6-10`):

> "per-set unforced-error rate is computed as the share of own losses that were unforced
> errors (setUEs / setFocalLostPoints), not as a share of all points … This mirrors how
> recreational players think about 'errors as a fraction of points I gave away'."

A **Rate / Count** segmented control switches the whole screen to raw numerators for the
metrics that have one (§4). Rate is the default.

### 3.2 Filter first, then window

"Last 10 singles" means **the last 10 singles matches**, not the singles among the last 10.
The second reading silently yields 3 matches when the player has been playing doubles, and
the chart quietly gets shorter with no explanation. Filters apply first; the window slices
what survives. Tested explicitly (`PerformanceTrendsTests`).

### 3.3 Pooled blocks, per-match points — deliberately two different numbers

| Where | Rule | Why |
|---|---|---|
| Chart / sparkline dot | that match's own rate | each match is one observation; that is what "per match" means to a player |
| Headline figure and delta | pooled: Σnumerators / Σdenominators over the block | a 24-point thrashing must not swing the average as hard as a three-setter |

**Pooling sums every match in the block, including matches whose own dot is absent.** A
match with 10 winners and 0 unforced errors has no plottable W:UE dot (§4.2), but its 10
winners still belong in the pooled numerator: pooling `10W/0UE` with `1W/1UE` is
**11 : 1**, not `1 : 1`. Dropping the un-plottable match would discard real data and report
the player's cleanest match as their worst. Pooled is therefore Σnumerator / Σdenominator
over **all** matches in the block, `nil` only when Σdenominator is 0 — never a mean of the
plotted dots.

For percentage metrics the two formulations agree: a match with an empty denominator
contributes `0/0`, a no-op. They diverge only for `wueRatio`, where `nil` means "zero
unforced errors", not "no data". That narrowness is exactly what makes it easy to get
wrong, so §5.2 gives pooling its own accessor rather than reusing the plotting one.

Both are correct for their job, and they will not agree. The screen labels the pooled
figure with its window ("4.2% · last 10") so the two are never mistaken for each other.
This is OQ-1.

### 3.4 `nil` is not zero

Every metric returns `Double?`. It is `nil` — never `0` — when the denominator is empty or
the match lacks the coverage the metric needs (no `endingShot` data for rally depth, no
`isBreakPoint`/`gameScoreAtStart` for pressure, zero unforced errors for a W:UE ratio).

Charts skip `nil` dots. **Pooled blocks do not skip them** — they sum raw numerators and
denominators across every match and go `nil` only when the aggregate denominator is 0
(§3.3). Collapsing a `nil` to `0`
would draw a player a graph of their equipment history and label it their game. This is the
one rule most likely to be quietly violated during implementation, so it is asserted per
metric in `TrendMetricTests`.

### 3.5 Eligibility

A match contributes only if **all** hold:

1. `!record.matchFormat.config.disablesPointTracking` — excludes `.perpetualPoints`, which
   never presents the categorisation sheet (`ScoreTypes.swift:135`) and so has no outcomes.
2. At least **20 categorized points** — the same threshold `RecCoachInsights.generate`
   already uses to refuse thin data (`RecCoachInsights.swift:78`). One number, one
   precedent, cited rather than re-invented.

Ineligible matches are absent from the series entirely, not plotted as gaps.

⚠️ **Revised after initial implementation** (owner request): an in-progress match is
**eligible**, not excluded, once it clears rule 2 — its `isInProgress` flag (mirroring
`MatchRecord.isInProgress`, `MatchRecord.swift:176`) tells callers apart from a completed
draw (both have `recorderWon == nil`). Eligibility and *inclusion* are a deliberate split:
`MatchTrendSample.init?` owns eligibility (can this match ever produce a sample); whether an
eligible in-progress sample is actually shown is `TrendFilter.includeInProgress` (§6.4),
off by default everywhere. The original single-condition design below is kept for context on
why the split exists, not as the current rule.

### 3.6 Partially tracked matches: categorized denominators

Outcome tracking is a setting the player can toggle **mid-match**. When it is off the watch
still records the point, with `outcome: .uncategorized` — `ScoreViewModel.swift:938` is
explicit: *"Stats off: silently record an uncategorized point for history/analytics."*

So a match can hold 30 categorized points and 90 uncategorized ones and still clear §3.5's
threshold. That matters, because `MatchStatsSummary` counts outcome numerators over the
**categorized** subset (`MatchStatsSummary.swift:143,176-182`) while `wonPoints`,
`lostPoints` and `firstServeTotal` count **every** point
(`MatchStatsSummary.swift:147-148,155`). Pairing the two treats every untracked point as
"not an error and not a winner" and silently depresses the rate — a player who turned
tracking off for a bad patch would see their error rate *improve*.

**Outcome-mix metrics therefore divide by categorized-only denominators.** The rate then
reads honestly: "of the points I lost *that were tracked*, this share were unforced errors".

The flaw is confined to metrics whose numerator filters on `outcome` — double faults,
unforced errors, forced errors, winners, W:UE, aggression index, own-error share. Serve,
return, break-point, big-point and points-won metrics key off `winner`, `server`,
`isSecondServe` and `isBreakPoint`, every one of which is recorded for uncategorized points
too, so those are correct against all-points denominators. Rally depth is already safe by
construction: `endingShot` is `nil` on an uncategorized point, so `pointsWithEndingShot`
excludes it.

`MatchTrendSample` also carries `trackingCoverage` (categorized ÷ total) so the screen can
mark a thinly-tracked window rather than quietly averaging it in.

### 3.7 Naming

**"Trends"**, for the section header, the nav title and the doc. It fits an inset-grouped
header and a `.inline` nav title; "Trending" carries a social-media ranking connotation the
feature does not mean. Core types are named `PerformanceTrends` / `MatchTrendSample` /
`TrendMetric`, which keeps the namespace unambiguous next to `MatchStatsSummary`.

---

## 4. The metric catalogue

> **Extended since.** The catalogue below is the tennis half. The movement half — Fatigue
> and Effort, 5 metrics — plus rally length split by serving side (4 metrics that live
> inside §4.3's own Rally Depth group, behind a third "By Server" mode) landed separately in
> [`HEALTH_TRENDS_PLAN.md`](HEALTH_TRENDS_PLAN.md), which also introduced the `.steps`
> `TrendMetric.Unit` case and the one-chart-per-unit rule in `TrendChart`. The design rules
> stated here (nil-not-zero, filter-before-window, pooled Σnum/Σden, orientation by
> `betterDirection`) apply unchanged to those metrics.

`TrendMetric` is the single catalogue. Adding a metric is one case plus one `switch` arm
plus one test — the same data-driven shape `MatchFormatConfig` uses for match formats.

Below, all field names are `MatchStatsSummary` fields evaluated with **`focal: .me`**.

### 4.1 Errors

| Metric | Numerator / denominator | Better |
|---|---|---|
| Double Faults | `doubleFaults` / `categorizedServicePoints` | lower |
| Double Faults conceded | `opponentDoubleFaults` / `categorizedOpponentServicePoints` | higher |
| Unforced Errors | `unforcedErrorsHit` / `categorizedPointsLost` | lower |
| Unforced Errors drawn | `unforcedErrorsDrawn` / `categorizedPointsWon` | higher |
| Forced Errors conceded | `forcedErrorsConceded` / `categorizedPointsLost` | lower |
| **Forced Errors caused** | `forcedErrorsCaused` / `categorizedPointsWon` | higher |

Every denominator here is **categorized-only**, per §3.6. Pairing a categorized numerator
with an all-points denominator under-reports each rate on a partially tracked match.

Note also that `MatchStatsSummary.firstServeTotal`, which `servicePoints` mirrors, is
**every** service point, not "first serves that landed" — counter-intuitive, and documented
at `MatchStatsSummary.swift:151-154`.

### 4.2 Attack

| Metric | Numerator / denominator | Better |
|---|---|---|
| Winners | `winnersHit` / `categorizedPointsWon` | higher |
| Winners conceded | `winnersConceded` / `categorizedPointsLost` | lower |
| W:UE ratio | `winnersHit` / `unforcedErrorsHit` — **ratio unit, no count mode** | higher |
| Aggression index | `winnersHit` / (`winnersHit` + `unforcedErrorsHit`) | higher |
| Own-error share | (`doubleFaults` + `unforcedErrorsHit`) / `categorizedPointsLost` | lower |

W:UE is `nil` when `unforcedErrorsHit == 0`. The per-match display renders that as `∞ : 1`
(matching `MatchStatsSummary.swift:187`); the **chart cannot plot it**, and feeding
`Double.infinity` to Swift Charts destroys the Y domain for the whole series. `nil` and a
skipped dot is the only safe answer.

⚠️ **`nil` here means "zero unforced errors", not "no data".** That match's winners must
still enter the pooled numerator (§3.3). Pooling only the plottable matches would report a
flawless match as a mediocre one — `10W/0UE` then `1W/1UE` is **11 : 1**, not `1 : 1`.

### 4.3 Rally depth — four phases, not a length

`EndingShot` is `serve / return / servePlusOne / rally` (`PointStat.swift:30-46`): **where
in the rally the point ended**. There is no shot count anywhere in the model. So "rally
depth over time" means two families:

| Metric family | Value | Better |
|---|---|---|
| Share of points ending at each phase | `shot.total` / `pointsWithEndingShot` | neutral |
| Win rate at each phase | `shot.wins` / `shot.total` | higher |

The share family is genuinely **neutral** — more rally-phase points is neither good nor
bad — so those rows show no ↑/↓ arrow at all. `BetterDirection.neutral` exists for this.

Coverage gate: matches with `pointsWithEndingShot == 0` yield `nil` for every rally-depth
metric. Ending-shot capture postdates the earliest archives (`PointStat.swift:158`).

### 4.4 Serve & return

`firstServeIn / firstServeTotal`; `firstServeWins / firstServeIn`;
`secondServeWins / secondServeTotal`; `returnWinsOnFirst / returnOppsOnFirst`;
`returnWinsOnSecond / returnOppsOnSecond`. All higher-is-better. This is the "serve % over
time" the companion plan named.

### 4.5 Pressure

`breakPointWins / breakPointOpps` (converted);
(`breakPointsFaced` − `breakPointsLost`) / `breakPointsFaced` (saved);
`bigPointWins / bigPointTotal`; `pointsWon / totalPoints`. All higher-is-better.

Pressure metrics use the typed counters, **not** `scoreStates`, whose labels are hard-coded
`String`s (`MatchStatsSummary.swift:219-248`) and would have to be string-matched to
aggregate.

---

## 5. Core — the derivation layer

Three new files in `Packages/DeuceMateCore/Sources/DeuceMateCore/Stats/`. Pure, `Sendable`,
no SwiftUI, `swift test`-verifiable without a simulator — the house rule for anything
portable (`CONTRIBUTING.md`: "If your change affects scoring rules, stats calculations, or
sync behaviour, it likely belongs there — and needs tests").

### 5.1 `MatchTrendSample.swift`

One match reduced to raw counters. **Built from a single `MatchStatsSummary(focal: .me)`**
so not one counting predicate is ever restated — drifting from `MatchStatsSummary` is
exactly the failure class `CLAUDE.md` §5 warns about.

Its field names are **recorder-framed**, which is the point: `forcedErrorsCaused` cannot be
read backwards the way `opponentForcedErrors` can.

```swift
public struct MatchTrendSample: Equatable, Sendable, Identifiable {
    public var id: UUID { matchID }

    // Identity and grouping
    public let matchID: UUID
    public let startTime: Date
    public let matchType: MatchType
    public let matchFormat: MatchFormat
    public let recorderWon: Bool?           // nil == draw OR still in-progress — check isInProgress
    public let isInProgress: Bool           // mirrors MatchRecord.isInProgress at build time

    // Volume. The categorized* denominators are what outcome-mix metrics divide by
    // (§3.6); the all-points ones serve the serve/return/pressure metrics, which are
    // valid on uncategorized points too.
    public let totalPoints: Int
    public let categorizedPoints: Int
    public let pointsWon: Int
    public let pointsLost: Int
    public let categorizedPointsWon: Int
    public let categorizedPointsLost: Int
    /// categorizedPoints / totalPoints. 1.0 when tracking stayed on all match; lower
    /// when the player toggled it off mid-match (§3.6). Surfaced, not silently averaged.
    public var trackingCoverage: Double {
        totalPoints > 0 ? Double(categorizedPoints) / Double(totalPoints) : 0
    }

    // Serve and return
    public let servicePoints: Int           // summary.firstServeTotal — ALL service points
    public let categorizedServicePoints: Int
    public let categorizedOpponentServicePoints: Int
    public let firstServesIn: Int
    public let firstServeWins: Int
    public let secondServePoints: Int
    public let secondServesIn: Int          // added post-launch: "2nd Serve In" metric
    public let secondServeWins: Int
    public let doubleFaults: Int
    public let returnPointsOnFirst: Int
    public let returnWinsOnFirst: Int
    public let returnPointsOnSecond: Int
    public let returnWinsOnSecond: Int
    public let opponentDoubleFaults: Int
    public var opponentServicePoints: Int { returnPointsOnFirst + returnPointsOnSecond }

    // Outcome mix — recorder-framed, deliberately renamed
    public let winnersHit: Int              // summary.myWinners
    public let winnersConceded: Int         // summary.opponentWinners
    public let unforcedErrorsHit: Int       // summary.myUnforcedErrors
    public let unforcedErrorsDrawn: Int     // summary.opponentUnforcedErrors
    public let forcedErrorsConceded: Int    // summary.myForcedErrors
    public let forcedErrorsCaused: Int      // summary.opponentForcedErrors

    // Pressure
    public let breakPointOpps: Int
    public let breakPointWins: Int
    public let breakPointsFaced: Int
    public let breakPointsLost: Int
    public let bigPointTotal: Int
    public let bigPointWins: Int

    // Rally depth — keyed, never positional (buckets are omitted when empty)
    public struct DepthCount: Equatable, Sendable {
        public let total: Int
        public let wins: Int
    }
    public let rallyDepth: [EndingShot: DepthCount]
    public let pointsWithEndingShot: Int

    /// Minimum categorized points for a match to be worth trending.
    /// Same threshold RecCoachInsights uses to refuse thin data
    /// (RecCoachInsights.swift:78) — one number, cited not re-invented.
    public static let minimumCategorizedPoints = 20

    /// `nil` when the match is ineligible (§3.5): still in progress, a format
    /// that disables point tracking, or too few categorized points.
    public init?(record: MatchRecord)
}
```

A **failable init owning the eligibility rule** keeps "is this match trendable?" in exactly
one place, so no call site can forget a clause.

### 5.2 `TrendMetric.swift`

```swift
public enum TrendMetricGroup: String, CaseIterable, Identifiable, Sendable {
    case errors, attack, rallyDepth, serveReturn, pressure
    public var displayLabel: String         // "Errors", "Attack", "Rally Depth", …
}

public enum BetterDirection: Sendable { case higher, lower, neutral }

public enum TrendMetric: String, CaseIterable, Identifiable, Sendable {
    case doubleFaults, doubleFaultsConceded
    case unforcedErrors, unforcedErrorsDrawn
    case forcedErrorsConceded, forcedErrorsCaused
    case winners, winnersConceded, wueRatio, aggressionIndex, ownErrorShare
    case depthShareServe, depthShareReturn, depthShareServePlusOne, depthShareRally
    case depthWinServe, depthWinReturn, depthWinServePlusOne, depthWinRally
    case firstServeIn, firstServeWin, secondServeWin, returnWinFirst, returnWinSecond
    case breakPointsConverted, breakPointsSaved, bigPointWin, pointsWon

    public enum Unit: Sendable { case percent, ratio }

    /// A metric's value on one match, as the pair it came from so the UI can
    /// print "12/38" as well as "32%". Mirrors RatioDisplay (StatFormatting.swift:41).
    public struct Ratio: Equatable, Sendable {
        public let numerator: Int
        public let denominator: Int
        public var value: Double { Double(numerator) / Double(denominator) }
    }

    public var group: TrendMetricGroup
    public var displayLabel: String          // "Double Faults"
    public var denominatorLabel: String      // "of service points"
    public var betterDirection: BetterDirection
    public var unit: Unit
    public var supportsCountMode: Bool       // false for wueRatio, aggressionIndex, shares

    /// The raw pair for this metric on one match, WITHOUT the empty-denominator guard.
    /// `nil` only when the sample lacks the coverage the metric needs at all (e.g. no
    /// ending-shot data). Pooling sums these across a block (§3.3).
    public func rawPair(in sample: MatchTrendSample) -> (numerator: Int, denominator: Int)?

    /// One match's plottable value: `rawPair` plus the empty-denominator guard, so a
    /// 0-denominator match yields no dot (§3.4). Never use this for pooling — it would
    /// discard the numerator of a zero-denominator match (§4.2).
    public func ratio(in sample: MatchTrendSample) -> Ratio? {
        guard let p = rawPair(in: sample), p.denominator > 0 else { return nil }
        return Ratio(numerator: p.numerator, denominator: p.denominator)
    }

    public static func metrics(in group: TrendMetricGroup) -> [TrendMetric]
    /// The four rows on the archive screen.
    public static let headline: [TrendMetric] = [.doubleFaults, .unforcedErrors,
                                                 .winners, .wueRatio]
}
```

### 5.3 `PerformanceTrends.swift`

```swift
public enum TrendWindow: Hashable, Sendable {
    case last(Int)
    case all
    public var label: String                               // "Last 10", "All"
    public static let presets: [TrendWindow] = [.last(5), .last(10), .last(20), .all]
}

public struct TrendFilter: Hashable, Sendable {
    public var matchType: MatchType?        // nil == all
    public var matchFormat: MatchFormat?    // nil == all
    public static let all = TrendFilter()
    public func includes(_ sample: MatchTrendSample) -> Bool
}

public struct TrendPoint: Equatable, Sendable, Identifiable {
    public let id: UUID                     // matchID
    public let index: Int                   // ordinal, oldest == 0 (§6.3)
    public let date: Date
    public let ratio: TrendMetric.Ratio
    public var value: Double { ratio.value }
}

public struct TrendDelta: Equatable, Sendable {
    public enum Direction: Sendable { case improving, declining, flat }
    public let direction: Direction         // already oriented by betterDirection
    public let change: Double               // recent − prior, signed, in the metric's unit
    public let recent: TrendMetric.Ratio    // pooled
    public let prior: TrendMetric.Ratio     // pooled
}

public struct TrendSeries: Equatable, Sendable, Identifiable {
    public var id: TrendMetric { metric }
    public let metric: TrendMetric
    public let points: [TrendPoint]         // oldest-first, nil-valued matches omitted
    /// Σnumerator / Σdenominator over EVERY match in the window — including matches whose
    /// own dot is absent (§3.3). Built from `rawPair`, never from `points`. `nil` only
    /// when the aggregate denominator is 0. **This is not a mean of `points`.**
    public let pooled: TrendMetric.Ratio?
    public let delta: TrendDelta?           // nil when either block is too thin
}

public enum PerformanceTrends {
    /// Fewest eligible matches before the feature says anything at all.
    public static let minimumMatches = 3
    /// Fewest matches in EACH half before a delta is emitted.
    public static let minimumBlockMatches = 2
    /// Below this, a change is reported .flat: 1 percentage point, or 0.1 for a ratio.
    public static func minimumChange(for unit: TrendMetric.Unit) -> Double

    /// Eligible samples, **oldest-first**. `records` may be newest-first
    /// (PhoneStatsStore.history is) — this is the one place the order flips.
    public static func samples(from records: [MatchRecord],
                               excluding activeMatchID: UUID? = nil) -> [MatchTrendSample]

    /// Filter first, then window (§3.2). Order of these two operations is load-bearing.
    public static func scoped(_ samples: [MatchTrendSample],
                              filter: TrendFilter,
                              window: TrendWindow) -> [MatchTrendSample]

    public static func series(for metric: TrendMetric,
                              in samples: [MatchTrendSample]) -> TrendSeries?
    public static func series(for group: TrendMetricGroup,
                              in samples: [MatchTrendSample]) -> [TrendSeries]
    public static func headline(in samples: [MatchTrendSample]) -> [TrendSeries]
}
```

`TrendDelta.direction` is **already oriented**: a falling double-fault rate is
`.improving`. Orienting once in Core means no view can render a red down-arrow for good
news — the kind of bug that survives review because each half looks right on its own.

---

## 6. iOS — presentation

Five new files in `DeuceMate/DeuceMate/Views/Trends/`. No `project.pbxproj` edit: the app
targets are `PBXFileSystemSynchronizedRootGroup`s (`CLAUDE.md` §0).

The template is `Views/Coaching/RecCoachSection.swift` and
`Views/PulseCoach/PulseCoachSection.swift` — self-contained structs that emit their own
`Section` into a parent `List`, the second already hosting Swift Charts.

### 6.1 The inline section — `TrendsSection.swift`

Four `TrendSparkline` rows plus a `NavigationLink` to `TrendsView`. Inserted into
`PastMatchesView.swift` at **~L99**, after the `let pastRecords` prelude (L93-97) and
before the Live Match section, where the `List` builder's `let`s are already in scope.

⚠️ Records come from **`store.history`**, not `pastRecords`. `pastRecords` unions in
`syncService.watchMirror` rows (`PastMatchesView.swift:85-97`), which are mirror summaries
and may carry no `stats` at all — trending them would silently plot zeroes.

The whole edit to `PastMatchesView.swift` is about six lines, per `TECHNICAL_DEBT` #13.

### 6.2 The Trends screen — `TrendsView.swift`

Pushed onto the existing `NavigationStack` (not a sheet — `MatchDetailView` is a sheet
because it is a leaf; Trends is a sibling destination the user drills into and back out of).

Header: window picker, Singles/Doubles picker, format menu, Rate/Count toggle. Then one
`Section` per `TrendMetricGroup`, each containing one `TrendChart`.

The format menu **omits `.perpetualPoints`** — it can never contribute a sample (§3.5), so
offering it would be a filter that always empties the screen.

### 6.3 Chart design — `TrendChart.swift`

**X is the ordinal match index, oldest at left — not the date.** Play is irregular; a
date-scaled axis crushes a busy fortnight against an empty month and makes the shape
unreadable. The date appears in the axis label and in the selection readout.

Each group is one `Chart` with up to four `LineMark` series. Colours reuse the per-match
outcome palette already in `PointsGraphView` (`PointsGraphView.swift:77-92` — DF `.orange`,
winner `.yellow`, UE `.red`, FE `.purple`) so a trend line and a match scatter agree on what
red means. **Mine is solid; theirs/conceded is dashed on the same hue** — which is what
keeps the two forced-error series distinguishable when both are purple.

Opponent-side series are **off by default**. The player's own trend is the subject; "the
opposite" is one legend tap away.

House chart idiom, carried over verbatim from `PointsGraphView`:

- `.chartLegend(.hidden)` and a hand-built chip legend (`PointsGraphView.swift:844-887`);
  here the chips also toggle series visibility, as `PointsGraphScatterControls` does.
- A pre-computed, `Equatable` data bundle rebuilt on an `.onChange`, never per frame
  (`PointsGraphView.swift:186-189`).
- `ContentUnavailableView` for the empty state.

Rally Depth gets a normalized stacked `AreaMark` (`stacking: .normalized`) — the mix of
where points end, shifting over time — with a toggle to the win-rate-per-phase lines.
iOS 17 (`IPHONEOS_DEPLOYMENT_TARGET = 17.0`) supports it.

No `WebExportColors` coupling: trends are not exported, so the `CLAUDE.md` §2 "keep
`WebExportColors` in step" rule is not engaged by this feature.

### 6.4 Filter persistence

Five **phone-local** `@AppStorage` keys, all following the `MatchSetupDefaults` precedent
for device-local UI state — not synced, no `MatchSyncKey`, no wire key, no watch mirror:

- `trendsWindow`, `trendsMatchType`, `trendsMatchFormat` (`TrendsView`) — the original three.
- `trendsIncludeInProgress` (`TrendsView`) — owner-requested revision to §3.5's eligibility
  split: off by default everywhere (the archive-screen headline inherits the default
  silently, having no room for its own toggle).
- `trendsServeReturnFilter` (`TrendChart`) — narrows the Serve & Return group's six metrics
  to one pair (Serves In / Serves Win / Returns Win) at a time; persisted, unlike Rally
  Depth's Mix/Win Rate toggle which is plain `@State` and resets each time the screen opens.

⚠️ `CLAUDE.md` §0 runs a settings-key consistency grep that expects every `@AppStorage`
literal to match a `MatchSyncKey` raw value, with a documented exception list. **Every key
above must be in that list**, or the next agent to run the check will report a drift bug
that does not exist.

### 6.5 Accessibility

A sparkline is invisible to VoiceOver. Each row carries one combined
`.accessibilityLabel` — metric, current pooled value, direction, and what it is compared
against ("Double faults, 4.2 percent of service points, improving, down 1.1 points versus
the previous five matches") — with the chart itself `.accessibilityHidden(true)`. This is
the treatment `MatchDetailView`'s Points rows already use.

`TECHNICAL_DEBT` #7 is also an accessibility item: VoiceOver currently reads the literal
string `"1.4 : 1"`. PR 1 fixes that for every surface, not just this one.

### 6.6 Thin data, and computing samples once — `TrendsSamples.swift`

`MatchStatsSummary.init` runs ~30 filter passes plus three insight engines
(`MatchStatsSummary.swift:325-349`). Once per match is fine; once per match **per render**
is not. `TrendsSamples` is an `ObservableObject` holding an ordered `[MatchTrendSample]`,
invalidated by comparing the full incoming `[MatchRecord]` array for equality against the
last-seen array — not a hand-picked field subset. (An earlier `(id, endTime, iWon,
statsCount)` fingerprint missed a real case, caught in Codex review: a Backup & Transfer
import can replace a record's point-level content while those four fields stay identical.
Full `MatchRecord` equality — its stored fields include `stats` — closes that gap and stays
correct automatically if a future field is added.) Filtering and windowing then operate on
cached value types.

Below `PerformanceTrends.minimumMatches` (3), `TrendsSection` renders a single explanatory
line — "Track N more tracked matches..." — rather than disappearing. This is a **deliberate
departure** from the house "empty ⇒ hide the section" idiom (`RecCoachInsights.swift:30-32`):
that idiom stops a per-match panel showing noise, whereas hiding here means a new user never
discovers the feature. Recorded as OQ-3.

`TrendsSection`'s gate only checks the *unfiltered* total, though — the full `TrendsView`
screen re-checks `scopedSamples.count < minimumMatches` **after** type/format/window/
in-progress filtering, since a filter combination can legally leave 1-2 matches even when
the archive as a whole clears the gate. Missing this second check (caught in Codex review)
would let a single filtered match render as a multi-point "trend."

`TrendsView` also surfaces §3.6's `trackingCoverage` per OQ-5's recommendation: a caption
above the charts names how many matches in the current scoped window had tracking off for
part of the match, so their outcome rates aren't mistaken for full-match numbers.

---

## 7. Implementation plan

Four PRs, in order. PR 1 is independently useful and independently revertible.

### PR 1 — `[Core] refactor: typed RatioStat for winner and error ratios`

Closes `TECHNICAL_DEBT.md` #7.

1. `Stats/MatchStatsSummary.swift` — add `RatioStat { numerator, denominator, formatted }`
   as #7 specifies; change `wueRatio`, `aggressionIndex`, `ownErrorsPct` from `String` to
   it. Keep `pct(num:den:)` as the formatter so no output string changes.
2. `Stats/MatchStatsSummary.swift` — additively expose `categorizedPointsWon`,
   `categorizedPointsLost`, `categorizedServicePoints`, `categorizedOpponentServicePoints`,
   derived from the `categorized` subset it already builds
   (`MatchStatsSummary.swift:143`). §3.6's denominators then live in one place instead of
   being recomputed in `MatchTrendSample`. No existing field changes.
3. Update call sites to `.formatted`: `MatchDetailView.swift`, `MatchExporter.swift`,
   `MatchStatsView.swift` (watch), `WebExport/MatchWebViewModel+Comparison.swift`.
   Mechanical — #7 records it as such.
4. `MatchStatsSummaryTests.swift` — assert the typed numerator/denominator; that
   `.formatted` is byte-identical to today's strings for the ∞, `—` and normal cases; and
   that the categorized denominators exclude `.uncategorized` points.
5. `docs/features/TECHNICAL_DEBT.md` — move #7 to the archive as **(Done)**, keeping its
   write-up intact per that file's contract.

*Separable:* `MatchTrendSample` could compute W:UE from the public `Int` fields and skip
this. It lands first anyway because this feature **is** #7's recorded trigger, and stepping
around a backlog item you have just triggered is how backlogs rot.

### PR 2 — `[Core] feat: cross-match performance trends`

1. `Stats/MatchTrendSample.swift` — §5.1, including the failable eligibility init.
2. `Stats/TrendMetric.swift` — §5.2, the full catalogue.
3. `Stats/PerformanceTrends.swift` — §5.3, windowing / filtering / pooling / deltas.
4. `Tests/…/MatchTrendSampleTests.swift`, `TrendMetricTests.swift`,
   `PerformanceTrendsTests.swift` — §9.
5. `docs/architecture/file-inventory.md` — three rows in §3, bump its `(44 files)` heading;
   three rows in §4, bump `(41 files)`; add a **Trends** row to the §5 reverse index.

No app target is touched. Verifiable with `swift test` alone.

### PR 3 — `[iOS] feat: Trends section and screen`

1. `Views/Trends/{TrendsSamples,TrendSparkline,TrendsSection,TrendChart,TrendsView}.swift`.
2. `Views/PastMatchesView.swift` — one `Section` at ~L99, reading `store.history`.
3. The three `@AppStorage` keys, plus their entry in `CLAUDE.md` §0's exception list.
4. Re-run `DeuceMateUITests` — `ScreenshotTests.swift:48-49` and `DeuceMateUITests.swift`
   query `navigationBars["Matches"]` and tap `match-row-<id>`. A section above Past Matches
   pushes rows down; identifier-based taps should survive, but scroll-into-view must be
   confirmed, not assumed.
5. `docs/architecture/file-inventory.md` — five rows in §2, bump its `(19 files)` heading.

### PR 4 — `docs: record the Trends feature`

Fold into PR 2/3 where natural; otherwise:

- `docs/features/IPHONE_COMPANION_APP_PLAN.md` — mark the "Phone-only stats" future-work
  bullet delivered, and **strike "opponent-specific records"** as not derivable (§1).
- `docs/features/TECHNICAL_DEBT.md` — #13 note: `PastMatchesView` was extended without
  growing, the split still pending.
- `CLAUDE.md` / `AGENTS.md` — file map rows for the new Core and iOS files; §0 key
  exceptions.
- This document — `status: proposed` → `implemented`, `implemented_date` set.

`docs/features/*_PLAN.md` files are **not** added to `file-inventory.md` (`CLAUDE.md` §6).

---

## 8. Rejected alternatives

**8.1 A `generateInsights: Bool = true` opt-out on `MatchStatsSummary.init`** so trends
skip the three rule engines. Rejected as speculative API. `PulseCoachInsights` early-returns
without HR data, and the remaining cost is single-digit milliseconds across a whole archive
— the id-keyed cache (§6.6) removes the repetition, which was the actual problem. Revisit
only if profiling on a large archive says otherwise.

**8.2 A standalone lightweight counter type that re-implements the filters** instead of
going through `MatchStatsSummary`. Faster, and wrong: two implementations of "what is an
unforced error" would drift, and the trend chart would silently disagree with the match
detail screen. This is the duplication class `CLAUDE.md` §5 exists to prevent.

**8.3 Raw counts, no normalization.** Rejected in §3.1: the chart becomes a chart of match
length.

**8.4 A uniform "per 100 points" denominator** for every metric. Comparable across metrics,
but "6.1 double faults per 100 points" is not how anyone thinks about their serve. Natural
denominators won; the Count toggle covers the cases where a raw number is what is wanted.

**8.5 A date-scaled X axis.** Rejected in §6.3.

**8.6 A `TabView` root** with Trends as a second tab. Rejected: `ContentView` is thirteen
lines and `PastMatchesView` owns the only `NavigationStack`; a pushed destination preserves
that shape and costs nothing.

**8.7 Aggregating `MatchStatsSummary.scoreStates`.** Its labels are hard-coded `String`s
(`MatchStatsSummary.swift:219-248`); cross-match aggregation would mean string-matching
`"At 30-All"`. The typed `bigPoint*` / `breakPoint*` counters carry the same information.

**8.8 Trending aces.** OQ-4: `ServingPointCategory.ace` requires `endingShot == .serve`
(`PointStat.swift:226-228`), so every pre-ending-shot match reports zero aces, which reads
as a collapse in serving rather than a gap in data.

---

## 9. Verification

Confirm the toolchain exists before running anything (`CLAUDE.md` §0):

```bash
xcodebuild -version
```

**Core — PR 1 and PR 2, no simulator:**

```bash
cd DeuceMate/Packages/DeuceMateCore && \
  xcodebuild test -scheme DeuceMateCore \
  -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO
# or: swift test
```

| Test file | Must cover |
|---|---|
| `MatchTrendSampleTests` | eligibility accepts an in-progress match once it clears the categorized-points threshold (`isInProgress` distinguishes it from a completed draw) and rejects `.perpetualPoints` and <20 categorized points; counters equal a hand-built match; `rallyDepth` keyed correctly when buckets are missing; recorder-framed names map to the right `MatchStatsSummary` fields — **especially `forcedErrorsCaused` == `opponentForcedErrors`** |
| `TrendMetricTests` | `ratio(in:)` returns `nil` (not `0`) on an empty denominator; `wueRatio` is `nil` at zero UEs but `rawPair` still reports its winners; outcome-mix metrics divide by the **categorized** denominators, so a match that is half-untracked reports the same rate as a fully-tracked one with the same tracked points; every case has a group, label, denominator label and direction; rally-depth shares are `.neutral`; `supportsCountMode` is false exactly for ratio/share metrics |
| `PerformanceTrendsTests` | **filter-before-window ordering**; **pooled W:UE over `10W/0UE` + `1W/1UE` is 11:1, not 1:1** — the zero-UE match's winners must survive pooling even though it has no dot; pooled is `nil` only when Σdenominator is 0; pooled ≠ mean-of-rates on deliberately uneven matches; delta sign and percentage-point units; `.flat` below `minimumBlockMatches` and below `minimumChange`; `.improving` for a *falling* double-fault rate; window larger than history; single-match and empty history; newest-first input yields oldest-first output |

Add a mirror-image consistency test in the style of `SimulatedGameStatsTests.swift:184-185`:
build a synthetic match and assert the recorder-side and opponent-side metrics are proper
complements.

**iPhone — PR 3:**

```bash
xcodebuild test -project DeuceMate/DeuceMate.xcodeproj \
  -scheme "DeuceMate" -destination "platform=iOS Simulator,name=iPhone 15,OS=latest"
```

**Manual, on a simulator with a seeded archive** — none of these are text-checkable:

- An archive mixing a super-tiebreak with a best-of-3 **must not** make the short match
  read as a collapse. This is the one check that proves §3.1 works; if it fails, the
  feature is actively misleading and should not ship.
- A match with no `endingShot` data leaves a **gap** in the Rally Depth chart, not a zero.
- A match played with outcome tracking toggled off partway does **not** show an improved
  error rate (§3.6). This is the failure mode the categorized denominators exist to stop.
- Falling double faults show a **green** ↓, not a red one (§5.3 orientation).
- Switching Singles → Doubles with few doubles matches shows the thin-data line, not an
  empty chart or a crash.
- The archive list still scrolls to a specific match row with the new section above it.
- VoiceOver reads each sparkline row as one sentence (§6.5).

---

## 10. Notes for reviewing AI models

- The comment block at the top is a structured summary for quick parsing. Keep it in step
  with the prose if you edit this doc, and **verify its `file:line` claims before building
  on them** — `POINT_MATCH_SCORE_PLAN.md` records a case where that header was confidently
  wrong about a root cause.
- The highest-risk line in this whole plan is `forcedErrorsCaused == summary.opponentForcedErrors`
  (with `focal: .me`). The `my*`/`opponent*` prefixes are relative to `focal`, not to the
  recorder. Getting it backwards produces a plausible chart that says the opposite of the
  truth, and no test you write by reading the field names will catch it. Read
  `MatchStatsSummary.swift:176-182` before touching §4.1.
- The second-highest risk is `nil` quietly becoming `0` (§3.4) somewhere between Core and a
  `LineMark`. `Chart` will happily plot a zero.
- The third is pooling from `points` instead of from `rawPair` (§3.3). It looks like a
  harmless simplification, agrees with the correct answer for every percentage metric, and
  is wrong only for `wueRatio` — where it reports a player's cleanest match as their worst.
  That is why `pooled` is documented as "not a mean of `points`" at its declaration.
- Outcome-mix denominators are **categorized-only** (§3.6) and the rest are not. That
  asymmetry is deliberate and load-bearing; do not "tidy" it into one denominator.
- Do not "simplify" §3.3 by making the headline figure the mean of the chart dots. They are
  different numbers on purpose, and the reasoning is OQ-1.
- Flag anything in `open_questions` you would resolve differently, especially OQ-3 — it is a
  deliberate departure from an established house idiom.

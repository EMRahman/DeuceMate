<!--
machine-readable summary (parse this block first)

status: implemented
author: Claude (Opus 5), design session with the owner
date: 2026-08-26
implemented_date: 2026-08-26
blocked_by: null
delivers: "The movement half of docs/features/PERFORMANCE_TRENDS_PLAN.md, plus rally length split by serving side. Shipped first as three groups and 13 metrics; reduced in the same branch to two groups and 5 metrics after review — see section 3's 'What was cut, and why', which is the part to read before proposing a new metric here."
metric_count: "8 fatigue metrics in 1 group (2 charts of 4 series each), plus 8 per-serving-side rally-depth share metrics in their own group (1 mode-switched chart)."
scope:
  in_scope:
    - "Packages/DeuceMateCore/Sources/DeuceMateCore/Stats/MatchTrendSample.swift (health counters, a maxHR parameter, the fatigue set-pair rule)"
    - "Packages/DeuceMateCore/Sources/DeuceMateCore/Stats/TrendMetric.swift (one new Unit case (.steps), 2 new groups, 9 metrics, startsHidden, the coverage gates)"
    - "Packages/DeuceMateCore/Sources/DeuceMateCore/Stats/MatchStatsSummary.swift (rallyDepthOnServe / rallyDepthOnReturn)"
    - "Packages/DeuceMateCore/Sources/DeuceMateCore/Stats/PerformanceTrends.swift (minimumChange per unit)"
    - "Packages/DeuceMateCore/Tests/DeuceMateCoreTests/MatchTrendSampleHealthTests.swift (new), TrendMetricTests.swift"
    - "DeuceMate/DeuceMate/MaxHRSetting.swift (new — the phone's shared reader for the two stored max-HR settings)"
    - "DeuceMate/DeuceMate/Views/Trends/{TrendChart,TrendSparkline,TrendsSamples,TrendsSection,TrendsView}.swift"
    - "DeuceMate/DeuceMate/Views/PastMatchesView.swift (two pure ViewBuilder extractions — see implementation_notes)"
    - "DeuceMate/DeuceMate/Views/MatchDetailView.swift (adopts MaxHRSetting)"
    - "DeuceMate/DeuceMateTests/TrendsSamplesTests.swift"
  out_of_scope:
    - "Any schema change. No MatchRecord/PointStat field, so no CLAUDE.md §4 backward-compat recipe, no MatchSyncKey, no new UserDefaults key, no watch change."
    - "Heart rate in any form, zones included. Shipped, then cut — the reasoning is in section 3 and is the thing to read before re-adding it."
    - "Calorie-derived metrics. MatchRecord.totalCaloriesKcal is active + basal (WorkoutManager.swift:136); basal accrues with the clock, so 'calories per point' is substantially a duration measurement. Excluded, not deferred."
    - "Cardiac efficiency as one number (movement produced per heartbeat) — a quotient of two rates, and TrendMetric.Ratio is Int/Int. The two rates ship as separate series instead."
    - "Recovery between points. HR is one spot reading per point with no rest-interval samples; it is not in the data."
    - "Health data in any export. HealthExportConsent governs health LEAVING the phone; this feature only renders it on-device, so no disclosure surface is engaged."
    - "The archive-screen headline. It stays the four tennis metrics — health coverage is too variable to headline."
key_data_model_facts:
  - "MatchStatsSummary already reduces the sampled series into hrTimeline and stepsTimeline, both carrying setIndex and wonByFocal (MatchStatsSummary.swift:143-173). Every counter added here is a projection of those plus zoneWinRates, so MatchTrendSample stays ONE MatchStatsSummary(focal: .me) per match — never a second counting pass."
  - "StepsSeries.make falls back to spreading MatchRecord.totalSteps evenly across points when fewer than two real samples exist (StepsSeries.swift:66-79). Under that fallback steps-per-point is totalSteps/n BY CONSTRUCTION — a constant, not a measurement. Health metrics read stepsTimeline only."
  - "stepsTimeline's first entry is the BASELINE and carries a load of 0 (MatchStatsSummary.sampledStepLoads). stepSumLoad/stepSampledPoints therefore reproduces MatchStatsSummary.averageSteps exactly, which is what keeps the trend and the text export's 'Avg Steps / Point' in agreement."
  - "Health data is device-local and does NOT survive an iCloud restore: the canonical archive is health-stripped, the Health sidecar is backup-excluded, and ArchiveBackupPolicy.backupSnapshot strips the five HealthKit fields for Guideline 5.1.3(ii). After a fresh-install restore the tennis metrics come back and these do not."
  - "EndingShot records the PHASE a point ended in, never who served: a point ending on the return shot is still a point the recorder served. Rally-by-server therefore splits on PointStat.server, and the two axes must not be confused."
  - "MatchStatsSummary.rallyDepthOnServe + rallyDepthOnReturn sum back to rallyDepth, which is the cheapest assertion available that the partition is right."
  - "A private STORED property makes a SwiftUI View's synthesized memberwise init private too (unlike a private property-wrapped one), so views holding a MaxHRSetting declare it internal."
decisions:
  fatigue_basis: "set-based, one series per played set (Set 1/2/3), with a deciding super-tiebreak carried as its own series and colour since .standard plays its third set that way"
  zones: "cut. Shipped in the first pass at the owner's request, then removed with the rest of heart rate — a metric that needs a yardstick the user can change is not worth a chart"
  group_count: "two — Fatigue, and Rally Depth — By Service. The screen budget is the binding constraint, not the metric count: 8 of the per-side metrics share one mode-switched chart"
  keeping_a_chart: "a chart earns its place only if the number moving tells the player to do something differently. Load and duration are context, not instruction"
  pairs_not_deltas: "fatigue ships as first-set/final-set metric PAIRS on one chart; the gap between the lines is the fatigue. TrendMetric.Ratio is Int/Int and cannot carry a signed difference"
  empty_denominator: "nil, never zero — inherited from PERFORMANCE_TRENDS_PLAN.md §3.4"
implementation_notes:
  - "PastMatchesView gained two pure @ViewBuilder extractions (archiveList, screenContent). Its body had grown large enough that the Swift type-checker gave up on it as a single expression once TrendsSection gained a second stored property — the exact symptom TECHNICAL_DEBT #13 predicts for this file. No behaviour change, no reordering; #13 itself stays open."
  - "MatchTrendSample.init?'s ELIGIBILITY rule is unchanged. A match without Health data is still a valid sample that simply has no health dots — adding a health clause there would have dropped the match from the tennis charts too."
-->

# Plan: Heart Rate, Movement & Fatigue trends

## 1. The report

> "For the trends section; review what we can add in terms of heart rate/steps data for
> trends in aspects like 'energy efficiency' or analyzing for fatigue."

`PERFORMANCE_TRENDS_PLAN.md` shipped 28 cross-match metrics, all tennis-derived. The watch
has been recording heart rate and steps on every point for far longer, and that data was
used only *within* one match — `PulseCoachInsights`, `StepsCoachInsights`, the HR-zone
chart, the Points Graph overlays. Nothing asked whether the player is getting fitter.

Both requested angles are derivable, and both answer a question no existing screen can.
The catch is coverage: health data is sparser than point data, device-local, and
permanently lost on an iCloud restore, so every metric here needs a gate the tennis
metrics never needed.

## 2. What the data supports, and what it does not

Per match, recorder-only (the watch is the only recorder; Trends is already `focal: .me`):

| Source | Field | Nature |
|---|---|---|
| `PointStat.heartRateBPM` | one spot bpm per point | sampled — present only while HR streaming was live |
| `PointStat.stepsCumulative` | running workout step total | sampled; first sample is a baseline carrying load 0 |
| `MatchRecord.totalSteps` / `totalDistanceMeters` / `totalCaloriesKcal` | whole-workout totals | `HKWorkoutBuilder` statistics (`WorkoutManager.snapshotActivity`) |
| `MatchRecord.matchElapsedSeconds` | duration | **not** HealthKit — always available |

Not derivable, and deliberately not worked around: **recovery between points** (no
rest-interval samples), **cardiac efficiency as one number** (a quotient of two rates),
**calorie-based efficiency** (calories include basal, so it measures the clock), and
**opponent-adjusted effort** (`MatchRecord` has no opponent identity, so "you ran more
because they were better" is unknowable — every efficiency metric carries that confound).

### The five traps

1. **`nil` is never zero.** A match recorded with Health off must produce no dot, never a
   0 bpm one. Each metric's `rawPair` returns `nil` below its gate; `ratio(in:)` and the
   pooling loop already respect that.
2. **The `StepsSeries` fallback is circular here** — see `key_data_model_facts`.
3. **Per-set denominators are three different things.** Win rate counts every point in the
   set, HR only HR-sampled points, movement only step-sampled ones. Sharing one denominator
   would repeat §3.6's mixed-denominator mistake in a new place.
4. **Health does not survive an iCloud restore**, so health charts are always
   coverage-captioned and never the archive-screen headline.
5. **Zones are a moving yardstick** — handled by the composite cache key and a calibration
   caption, never by silently re-deriving behind the user's back.

## 3. The catalogue — 8 metrics, 2 charts, 1 group

The first cut of this feature shipped 13 metrics across three groups and **8 charts**, on a
screen that already had five groups. Most of them reported *load* rather than anything a
player can act on, so the catalogue was reduced to the ones that pass a single test: does
this number, moving, tell you to do something differently?

### Fatigue
| Metric family | series | numerator / denominator | unit | better |
|---|---|---|---|---|
| Points won | Set 1, Set 2, Set 3, Set 3 (Super TB) | points won in set / points in set | `.percent` | higher |
| Steps per point | Set 1, Set 2, Set 3, Set 3 (Super TB) | Σ steps in set / step samples in set | `.steps` | neutral |

Two charts, four series each. Together they separate *do I fade* from *why*: a win rate
that drops across the sets while step load holds is a decision or technique problem; both
dropping together is conditioning. The points-won chart needs **no HealthKit data at all**,
so it is the one thing here that still works for a player who never granted Health access
and for an archive restored from iCloud, where health data is permanently gone.

**The decider is its own series when the format plays it as a super-tiebreak.**
`.standard` — the app's default — plays its third set as a 10-point tiebreak, while
`.bestOf3FullFinalSet` plays a real one. Pooling the two would compare a dozen-odd points
against sixty, so `winRateDecidingTiebreak` / `stepsPerPointDecidingTiebreak` carry it
separately, labelled "Set 3 (Super TB)" and coloured **purple** — deliberately outside the
green → orange → red set-1-to-3 ramp, so it reads as a different kind of thing rather than
as the end of the progression. A match contributes to `winRateSet3` **or** to
`winRateDecidingTiebreak`, never both.

The two kinds also gate differently: a full set needs `minimumFullSetPoints` (20, cited
from `RecCoachInsights`), a super-tiebreak needs `minimumTiebreakPoints` (10). Holding the
tiebreak to the full-set bar would silently drop the decider from every `.standard`
three-setter — the format the app defaults to.

Each set gates **independently**. A match that went two sets simply has no Set 3 dot, and
that gap is the honest reading rather than missing data. This deliberately replaces the
earlier first-vs-final *pair*, where both lines were suppressed unless both sets had
coverage: half of a two-line comparison reads as the whole answer, but a gap in a named
"Set 1" line does not.

### Structural rules on the slices

Two rules live in `MatchTrendSample.setSlices` rather than in the metrics, because they are
about whether the match can support a per-set reading at all:

- **At least two sets.** A single-set match has nothing to compare across, which also
  excludes the tiebreak-only formats and `.quick4Games`.
- **Nothing from the set in play.** An in-progress match's current set would drift point by
  point, so it is dropped — but only it. Its earlier sets are finished and count normally,
  which is what the screen's "Include In-Progress Matches" toggle promises. Dropping the
  whole match (the first cut) made that toggle a lie for this group alone: every other group
  honoured it while Fatigue silently plotted nothing, so a live three-setter showed no
  fatigue at all despite having two completed sets.

The step slices drop each set's first sample: a `stepsTimeline` entry's load is measured from the previous sample, so a set's
opening entry is the match-wide baseline (load 0) in the opening set and spans the whole
inter-set changeover in every later one. Both distortions push the same way — "you moved more
when tired" — in the metric that exists to answer exactly that. Two sets of identical
movement read 3.87 vs 4.00 before the drop and equal after it.

### What was cut, and why

| Removed | Why |
|---|---|
| `avgHeartRate`, `hardZoneShare`, `hardZoneWinRate`, `avgHeartRateFirstSet`, `avgHeartRateFinalSet` | **Heart rate dropped entirely.** Zones depend on a max-HR yardstick that shifts under the user (see the retired trap 5 below), "win rate in Z4–Z5" largely restates the fade signal, and step sampling survives in cases where the HR stream doesn't. Dropping them removed the `maxHR` parameter, the `TrendsSamples` composite cache key and the calibration caption with them. |
| `metresPerPoint` | Collinear with steps per point — two charts saying the same thing. |
| `minutesPerMatch` | Match length is context, not performance, and every archive row already shows it. |
| `stepsPerPoint` (whole-match) | Running more is neither good nor bad on its own. |
| `stepsPerPointWon` (the Effort group) | Cut in a second pass, with the group it was alone in. It was the best available answer to "am I getting fitter", but it is confounded by opponent strength — a weak opponent hands out cheap points and the line falls without any change in the player — and one chart per season-scale question was not worth the screen. Its whole-match step counters went with it. |

Do not re-propose these without a reason that survives the test above. The `.bpm`, `.metres`
and `.minutes` `Unit` cases went with them, leaving `.steps` as the only unit this feature
added — the unit bucketing itself stays, because Fatigue holds a percent chart and a steps
chart.

## 3a. Rally Depth — By Service

The whole-match Mix chart answers "where do my points end?" — but it pools the two sides of
the serve, which are different games. **Rally Depth — By Service** is its own group showing
the same four-phase normalized stack, scoped to one serving side at a time via an
On Serve / On Returns picker.

Eight share metrics, four per side (`servedShare*` / `returnedShare*`), each taken against
**that side's own** ending-shot total so each stack fills to 100% of the side rather than to
some fraction of the match. Read across the picker: a rally slice that is large on your
serve and small on return says your service points are the ones going long.

An earlier pass shipped this as four metrics (rally share + rally win per side) behind a
third mode on the Rally Depth picker. It was replaced by the full per-side mix at the
owner's request: the mix shows the whole distribution rather than just the rally slice, and
a separate group gives it a heading rather than burying it in a picker. The per-side **win
rates** went with that change — the counters are still there (`DepthCount.wins`), so a
Win Rate mode on this group is a small addition if the shares turn out to raise the
question.

The split axis is **`PointStat.server`, not `EndingShot.serve`**. `EndingShot` records the
*phase* a point ended in, so a point ending on the return shot is still a point I served;
reading the side off the phase is the easiest mistake available here and puts those points
on the wrong side of the comparison. `MatchStatsSummary` gains `rallyDepthOnServe` /
`rallyDepthOnReturn`, the same `[RallyDepthStat]` shape as the existing `rallyDepth` and
summing back to it, carrying all four phases per side.

Both sides gate to `nil` when that side carries no ending-shot data, so a match archived
before `PointStat.endingShot` existed gaps rather than reading as "you never played a
rally". The per-side metrics reuse the whole-match phase colours, since only one side is on
screen at a time — "teal means the point ended on the serve" then holds everywhere.

## 4. Presentation

`TrendMetric.Unit` gained `.bpm`, `.steps`, `.metres`, `.minutes`. A metric's unit **is the
axis it belongs on**: plotted together, Swift Charts infers one domain and the
small-magnitude series flatten against the bottom. `TrendChart` therefore groups its series
by unit and renders one chart per unit present — generalising the escape hatch W:UE already
had. Ratio-unit metrics keep their sparkline treatment.

`TrendsView` skips a group whose every series is empty (`!groupSeries.isEmpty` is not the
right test — a Health-free archive still returns a full series array), and captions each
health group with how many scoped matches actually carry its data, plus a calibration note
on Heart Rate when the max HR is the 190 fallback.

## 5. Verification

```bash
cd DeuceMate/Packages/DeuceMateCore && swift test
xcodebuild build -project DeuceMate/DeuceMate.xcodeproj -scheme DeuceMate \
  -destination "platform=iOS Simulator,name=iPhone 17,OS=latest"
xcodebuild test  -project DeuceMate/DeuceMate.xcodeproj -scheme DeuceMate \
  -destination "platform=iOS Simulator,name=iPhone 17,OS=latest"
```

`MatchTrendSampleHealthTests` covers each trap by name: the no-fallback rule, nil-not-zero
(including pooling skipping a health-free match rather than counting it as 0), the set-pair
rule and its in-progress exclusion, per-family gating, and the zone yardstick moving with
`maxHR` while `hrSumBPM` does not.

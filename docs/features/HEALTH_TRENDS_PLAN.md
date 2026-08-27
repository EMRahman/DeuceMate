<!--
machine-readable summary (parse this block first)

status: implemented
author: Claude (Opus 5), design session with the owner
date: 2026-08-26
implemented_date: 2026-08-26
blocked_by: null
delivers: "The heart-rate and movement half of docs/features/PERFORMANCE_TRENDS_PLAN.md. That plan's catalogue was entirely tennis-derived and read none of the HealthKit data the watch already records; this adds three groups — Heart Rate, Movement, Fatigue — under coverage rules stricter than the tennis metrics need."
scope:
  in_scope:
    - "Packages/DeuceMateCore/Sources/DeuceMateCore/Stats/MatchTrendSample.swift (health counters, a maxHR parameter, the fatigue set-pair rule)"
    - "Packages/DeuceMateCore/Sources/DeuceMateCore/Stats/TrendMetric.swift (4 new Unit cases, 3 new groups, 13 new metrics, the coverage gates)"
    - "Packages/DeuceMateCore/Sources/DeuceMateCore/Stats/PerformanceTrends.swift (minimumChange per unit, samples(from:maxHR:))"
    - "Packages/DeuceMateCore/Tests/DeuceMateCoreTests/MatchTrendSampleHealthTests.swift (new), TrendMetricTests.swift"
    - "DeuceMate/DeuceMate/MaxHRSetting.swift (new — the phone's shared reader for the two stored max-HR settings)"
    - "DeuceMate/DeuceMate/Views/Trends/{TrendChart,TrendSparkline,TrendsSamples,TrendsSection,TrendsView}.swift"
    - "DeuceMate/DeuceMate/Views/PastMatchesView.swift (two pure ViewBuilder extractions — see implementation_notes)"
    - "DeuceMate/DeuceMate/Views/MatchDetailView.swift (adopts MaxHRSetting)"
    - "DeuceMate/DeuceMateTests/TrendsSamplesTests.swift"
  out_of_scope:
    - "Any schema change. No MatchRecord/PointStat field, so no CLAUDE.md §4 backward-compat recipe, no MatchSyncKey, no new UserDefaults key, no watch change."
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
  - "HRZone.resolveMaxHR is a CURRENT setting applied retroactively to archived matches, and 220−age drifts a bpm a year. Zone counters therefore depend on a value that can change without any record changing — hence MatchTrendSample.init?(record:maxHR:) and the composite TrendsSamples cache key."
  - "HRZone.resolveMaxHR falls back to 190 when uncalibrated. HRZone.isUsableBirthYear is the way to tell that apart from a legitimate age-30 result — it must never be inferred by comparing the resolved value against 190."
  - "A private STORED property makes a SwiftUI View's synthesized memberwise init private too (unlike a private property-wrapped one), so views holding a MaxHRSetting declare it internal."
decisions:
  fatigue_basis: "set-based — first played set vs last played set, both needing 20 points (owner decision over chronological halves)"
  zones: "in v1 (owner decision), with calibration captioned rather than gated"
  group_count: "three — Heart Rate, Movement, Fatigue. One 'Effort' group would have carried five units and therefore five charts"
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

## 3. The catalogue — 13 metrics, 3 groups

### Heart Rate
| Metric | numerator / denominator | unit | better | gate |
|---|---|---|---|---|
| `avgHeartRate` | Σ bpm / HR-sampled points | `.bpm` | neutral | ≥ 10 HR points |
| `hardZoneShare` | Z4+Z5 points / HR-sampled points | `.percent` | neutral | ≥ 10 HR points |
| `hardZoneWinRate` | wins in Z4+Z5 / Z4+Z5 points | `.percent` | higher | ≥ 10 HR points **and** ≥ 5 Z4+Z5 points |

### Movement
| Metric | numerator / denominator | unit | better | gate |
|---|---|---|---|---|
| `stepsPerPoint` | Σ per-point steps / step-sampled points | `.steps` | neutral | ≥ 10 step samples |
| `stepsPerPointWon` | Σ per-point steps / points won **among step-sampled points** | `.steps` | **lower** | ≥ 10 step samples |
| `metresPerPoint` | distance / total points | `.metres` | neutral | distance > 0 |
| `minutesPerMatch` | elapsed minutes / 1 | `.minutes` | neutral | completed, duration ≥ 1 min |

`stepsPerPointWon` is the energy-efficiency metric: **how much running one won point costs
you.** Falling means winning more cheaply. Its denominator counts wins **within the
step-sampled window**, not the whole match: `stepSumLoad` only covers sampled points, and
pairing a partial numerator with a full denominator made the rate fall as coverage fell —
which, in the one health metric with an orientation, reported a dropout as a fitness gain. `minutesPerMatch` is health-free by design — the
one series here that survives an iCloud restore and exists without Health access, so the
group is never wholly empty. It is also the only metric whose numerator is a whole-match
absolute rather than a rate, so it is `nil` for an in-progress match (whose duration is
still growing) and for a sub-minute one (which truncates to a 0 that would break the
nil-never-zero rule). Because it keeps the group rendering with no step or distance data
at all, the group's coverage footer names "step or distance data" specifically rather than
claiming the whole group is empty.

### Fatigue — first played set vs last played set
| Metric pair | numerator / denominator | unit | better |
|---|---|---|---|
| `winRateFirstSet` / `winRateFinalSet` | points won in set / points in set | `.percent` | higher |
| `avgHeartRateFirstSet` / `avgHeartRateFinalSet` | Σ bpm in set / HR points in set | `.bpm` | neutral |
| `stepsPerPointFirstSet` / `stepsPerPointFinalSet` | Σ steps in set / step samples in set | `.steps` | neutral |

The set pair is **a rule, not a search**: the first played set and the last played set, both
needing 20 points. Hunting for "the first two sets that qualify" would let the metric mean
set 1 vs set 3 on one match and set 2 vs set 3 on the next. Consequences, all deliberate:
single-set formats produce no fatigue dots; a ~15-point super-tiebreak decider is excluded
by the 20-point gate, so a full set is never compared against a 10-point tiebreak; and
**in-progress matches produce no fatigue dots at all** (their final set is still being
played) while still contributing to every other metric.

Each pair checks **both** slices before returning either, so a set that lacks coverage can
never leave its partner drawn alone — one line of a two-line comparison reads as a complete
answer.

The two **step** slices drop each set's first sample. A `stepsTimeline` entry's load is
measured from the previous sample, so a set's opening entry is not comparable to the rest:
in the first set it is the match-wide baseline (load 0 by definition), and in the final set
it spans the whole inter-set changeover. Both distortions push the same way — "you moved
more when tired" — in the metric that exists to answer exactly that. Two sets of identical
movement read 3.87 vs 4.00 before the drop and equal after it. The whole-match
`stepsPerPoint` deliberately keeps its baseline entry, so that figure still reproduces
`MatchStatsSummary.averageSteps` and agrees with the text export.

Thresholds are cited, not invented: 20 points per set from `RecCoachInsights`' set-duration
rule; 10 HR/step samples from `PulseCoachInsights.generate` and `StepsCoachInsights`.

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

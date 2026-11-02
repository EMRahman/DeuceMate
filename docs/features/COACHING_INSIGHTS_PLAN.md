# Compact coaching insights

Implemented November 2026. Keep up to three inline rows, with the factual prefix
before ` — ` emphasized on iPhone, in the demo and in the interactive HTML report.
No new cards or tracking requirements. Fewer rows are valid when evidence is thin.

User-facing overview: [Automated coaching insights in the user guide](../USER_GUIDE.md#automated-coaching-insights-reccoach).

## Selection

`RecCoachInsights.generate` takes full saved history, focal side, selected set,
set durations, and optional match type. Candidates have stable IDs, a heuristic
score (severity multiplied by a capped sample plus specificity), and overlapping
topic tags. Sort descending by score, break ties by ID, then select at most three
with disjoint topics. These scores rank observations, not predicted points saved.
Specific return/serve observations suppress overlapping generic error advice;
weak second-serve results embedded in a first-serve insight suppress a separate
second-serve observation. Exertion candidates share one topic so HR and steps
cannot produce duplicate rows.

All rules require at least 20 classified points in the selected scope.
Most rate rules require at least 80% relevant coverage: serving/receiving
classification, recorded ending phases or known score context, as appropriate.
Unclassified points never count as landed first serves. The set-duration win-rate
comparison uses all saved point winners and does not require outcome coverage;
exertion uses its own consecutive-sample and group-size gates below. Exact break-point double-fault events can bypass the frequency and
coverage requirements, but still require the 20-point gate. Include all points
when invoking the engine, even in exports that use classified-only summaries for
other sections.

## Candidates and initial thresholds

- **Double faults:** own serving losses only. Any recorded break-point double
  fault qualifies; known tiebreak scores cannot be called breaks. Otherwise at
  least 3 double faults, 4 service games, and 0.5 faults/game. Known tiebreak faults and tiebreak service runs
  are both excluded from the regular-service-game frequency calculation. Total
  faults remain available to the break-point-context observation. No claim that nerves caused the errors.
- **First serve:** fewer than 50% in over at least 30 classified service points.
  All double faults count as missed first serves, even on legacy records whose
  second-serve flag is false. If second-serve points won (including double faults)
  are below 45% over at least 8 attempts, suggest controlled pace or familiar spin;
  otherwise suggest testing a larger target and measuring overall results. The
  threshold is a tunable product heuristic, not an optimal percentage. Kick serves
  are never prescribed from stats that do not record spin or technique.
- **Second serve in play:** at least 8 first-serve and 8 second-serve-in-play points,
  with a win-rate gap of 20 percentage points. Advice concerns spin, placement and
  next-shot preparation; excludes double faults from the in-play denominator.
- **Serve/return balance:** at least 20 classified points on each side and a
  25-percentage-point gap. Show both counts and rates; a gap alone is not a diagnosis.
- **Missed returns:** known ending phases covering at least 80% of classified
  return points. At least 10 return attempts, 3 unforced misses, and 25% missed.
  Exclude aces/serve endings and opponent double faults. Require a receiver loss
  ending specifically on the return. Advice covers position and preparation.
- **Errors after the return:** at least 10 known-phase receiving losses, at least
  40% unforced errors ending at Serve+1 or Rally. Advice covers recovery, spacing
  and shot choice. Shares a topic with missed returns and serve/return balance.
- **General errors:** at least 25 classified points, 15 classified losses, and
  55% unforced errors/own double faults among losses. Lower-specificity fallback.
- **Pressure:** serving and receiving compared separately; at least 8 pressure
  and 15 ordinary points, 20-percentage-point drop. Known score context required
  for ordinary points; missing scores are not evidence of ordinary play.
  Break points, deuce/advantage and tiebreak points form the pressure group.
- **Rally phase:** own service points only, at least 8 Serve+1 and 8 Rally endings,
  with a 15-percentage-point gap. These are phases, not measured rally lengths.
  Suggest reviewing losses, never automatically trying to finish sooner.
- **Set change:** combine rising unforced-error share of losses (12 classified
  losses each set, +10 percentage points to at least 25%) with win-rate decline
  after a lengthy set (30-minute earlier set, both durations known, 20 points each,
  15-percentage-point decline). All scope evaluates adjacent transitions and picks
  the strongest; set scope compares the selected set to its predecessor. Never
  diagnoses fatigue from a set's duration or an error-share increase.
- **Serve after exertion:** see below.

## Displayed advice

Each row starts with the supporting counts/rates, then ` — ` and one of the
following suggestions. The factual prefix varies with the match. These are the
implemented strings, not claims that a particular technique caused the result.

| Finding | Exact advice after the factual prefix |
|---|---|
| Double faults on break point | “practise your second-serve routine under pressure.” |
| Frequent double faults | “practise a repeatable second-serve routine.” |
| Low first-serve percentage, weak second-serve results | “try slightly less pace or a familiar spin serve.” |
| Low first-serve percentage, stronger second-serve results | “test a larger target and compare your service-point results.” |
| Weaker second serves in play | “review spin, placement and next-shot preparation.” |
| Serve/return imbalance | “review returns and following rallies; the gap alone does not explain why.” |
| Missed returns | “review return position, split-step timing and preparation.” |
| Errors after the return | “review recovery position, spacing and shot selection.” |
| General errors | “review preparation, spacing and shot selection.” |
| Pressure-point drop, serving or receiving | “use your usual routine and a clear target.” |
| Serve+1 / rally-phase difference | “review how rallies were lost before changing tactics.” |
| Set change | “review preparation, positioning and shot selection.” |
| Any serve-after-exertion finding | “practise resetting your breathing and serve routine between points.” |

Examples with fictional figures:

- **4 double faults, including 2 on break points** — practise your second-serve routine under pressure.
- **First serves in: 45% (18/40); second-serve points won: 32% (7/22)** — try slightly less pace or a familiar spin serve.
- **6/20 tracked return attempts ended in an unforced error** — review return position, split-step timing and preparation.

A finding meeting its threshold is a candidate, not a promise that it will be
shown. The generator ranks candidates, skips any sharing a topic with an already
selected observation, and stops at three. For example, the low-first-serve
observation with second-serve results shares the second-serve topic; the separate
second-serve comparison therefore cannot repeat that advice. All exertion
variants share one topic, so HR and movement cannot occupy two rows.

## Exertion

Enabled only for the recorder (`focal == .me`) when `matchType == .singles`.
Doubles is suppressed: saved points identify the serving team, not which teammate
served. Opponent exports suppress these insights in both stat perspectives.

Use the preceding point's recorded HR to classify the next service point. For
steps, use the difference between the two preceding consecutive cumulative
samples, never match-total estimates. Exact score succession within the same
regular service game and set is required, with positive timestamp gaps of at most
90 seconds. Missing records, score resets, tiebreaks, negative/reset step deltas,
and pauses cannot join unrelated rallies. Never pre-filter out missing samples.

Split each sensor's eligible observations around its median. Require at least 10
observations on each side and average separation of 5 steps or 10 bpm. Candidates:
first-serve-in drop >=15 percentage points; double-fault rate rise >=10 points
with at least 3 high-effort double faults; service-point-win drop >=20 points.
Select at most one exertion insight. It describes an association and suggests a
between-point reset, not a diagnosis or a claim that rallies were too long.

Steps include between-point walking and logging delay. Recorded HR is the latest
available reading at point commit, not measured immediately before the next serve;
its sample age is not persisted. No exact rally duration, shot count, serve speed
or spin is measured. All thresholds and causal limitations remain explicit here.

## Integration and validation

- Core generator shared by iPhone, text/AI export and interactive HTML export.
- `MatchStatsSummary.recCoachInsights` retains its non-Health default for callers
  without a match type. Report callers invoke the generator on full records.
- Browser rules mirror Core; Pulse Coach remains a separate existing panel.
- No persisted schema or dependencies changed.
- Existing rule tests updated for intentionally changed wording, phase/score
  requirements and ranking. `RecCoachRedesignTests` adds coverage, ranking,
  perspective, set, exertion and export regressions.
- `COACHING_PARITY_OUTPUT=/tmp/coaching.json swift test ...` writes fictional
  native fixtures; the same environment variable on
  `node scripts/iphone-demo-coaching-qa.cjs` checks exact browser parity.

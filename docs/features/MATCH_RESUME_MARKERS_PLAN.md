---
title: Multi-session Matches — Completion Dates and Resume Markers
status: implemented_pending_hardware_validation
document_type: feature_design
created: 2026-07-14
last_updated: 2026-11-04
product: DeuceMate
platforms: [watchOS, iOS, interactive-html-export, browser-demo]
---

# Multi-session Matches — Completion Dates and Resume Markers

**Implementation status (2026-11-04):** Phases 1 and 2 are implemented; physical-Watch validation remains pending.
`MatchChronology` is the shared policy; Watch `AppState.matchCompletionTime` captures
normal completion and survives categorisation/restoration/undo/re-win. Live
checkpoints deliberately stay unfinished until finalization, preserving winning-
point undo under existing merge authority. No `MatchRecord` or wire fields were
added; existing archives are not rewritten. Histories/retention, Trends, comparisons,
roster activity dates and text/AI/HTML/browser reports use the policy. Export
filenames remain start-based. Phase 2 adds confirmed sessions, transactional resume/park,
workout accumulation, session-aware health analysis, graph/history markers and
all report variants. Phase 3 remains proposed. See the hardware checklist below.

## 1. Problem and intended experience

A match can start on one day, be parked, and finish a week later. It remains one
match, but its result belongs to the day it finished. Before Phase 1, Trends and match
history ordered it by its original start time, and the points graph does not
explain the interruption.

**Proposed behaviour:** date completed matches by completion in Trends, show the
most recently finished matches first in history, and mark confirmed resumptions
on the points graph. Preserve the original start date and the same match UUID.

Example (all times in the same local timezone):

| Match | Started | Finished | History position | Trends order |
|---|---|---|---|---|
| A, interrupted | 1 Nov | 8 Nov, 16:00 | First | Latest |
| C | 7 Nov | 7 Nov, 18:00 | Second | Middle |
| B | 4 Nov | 4 Nov, 11:00 | Third | Earliest |

A contributes **one** match to Trends, dated 8 Nov. Its row says `Finished 8 Nov`;
its detail also says `Started 1 Nov`. Its graph marks where play resumed on 8 Nov.
The week away does not occupy a week's width on the point-based graph.

This design is implemented through Phase 2, subject to the pending hardware
checks below. It expands and supersedes the July resume-marker proposal at this same path. In particular, it revises the
old assumption that time away from the app proves a break in play (§4).

## 2. Baseline before implementation and constraints

Historical baseline captured on 4 November 2026 before Phases 1–2:

| Area | Current behaviour / implementation |
|---|---|
| Match identity | `MatchRecord` retains `startTime`, optional `endTime`, and `isInProgress`. A completed draw has no winner; use `isInProgress`, never `iWon == nil` alone. |
| Trends | `MatchTrendSample` carries `startTime`; `PerformanceTrends.samples` sorts by it, and `series` uses it for each point's date. The chart axis is ordinal match index, not elapsed calendar time. |
| Phone history | `PhoneStatsStore` delegates sorting to `ArchiveBackupPolicy`; `PastMatchesView` sorts the combined archive/watch-only rows by start time. Row dates also use start time. |
| Watch history | `StatsStore.appendMatch` sorts by start time before applying the 25-match cap; `MatchHistoryView` displays start time. |
| Other ordering | `MatchMergePolicy.merge`, `WatchMirror`, `MatchComparison`, `PlayerRoster`, and `OpponentDirectory` also contain start-time chronology. |
| Explicit park/resume | Watch `End Match` parks an unfinished match; history's `Resume this match` calls `ScoreViewModel.resumeMatch`. The watch home's `Resume Match` can simply reopen the still-live match. These are different paths. |
| Timing | `matchElapsedSeconds` and `setElapsedSeconds` already accumulate across explicit history resumes. No persisted resume-event list or park timestamp exists. |
| Completion | `finalizeCurrentMatchToStore` stamps `Date()` when it writes a completed record. `endingAtCurrentScore(at:)` uses the explicit completion action's time. Capture of the actual final scoring time needs attention (§3). |
| Health | `HealthKitHRFetcher` queries from the original start to end/last point. `resumeMatch` starts a workout using the original match start, and finalization snapshots the current workout's activity. Multi-session health correctness needs explicit verification. |

Relevant existing designs: [Performance Trends](PERFORMANCE_TRENDS_PLAN.md),
[Health Trends](HEALTH_TRENDS_PLAN.md), [Match Tags](MATCH_TAGS_PLAN.md), and
[Interactive HTML Export](INTERACTIVE_HTML_EXPORT_PLAN.md). The current lifecycle
is documented in [match-lifecycle.md](../architecture/match-lifecycle.md).

### Pre-fix fitness-session audit during Phase 1 (4 November 2026)

The requested resume check found the following gaps before Phase 2. The
implementation below addresses these paths; sensor behavior still requires
physical-Watch verification:

- `ScoreViewModel.resumeMatch` restarts HealthKit with `matchStartTime`, the
  original match date, rather than the new session start. The resulting workout
  interval can span the parked break.
- Resume restores match/set elapsed timers, but does not restore saved steps,
  distance or calories into an accumulator. Finalization uses only
  `WorkoutManager.snapshotActivity()`. Earlier session totals are therefore not
  explicitly preserved or combined; builder behavior is not a safe substitute.
- Per-point steps come directly from the current builder, so their cumulative
  counter can restart across workouts. Session boundaries are required before
  movement/fatigue calculations can safely combine those points.
- `HealthKitHRFetcher` queries the original start-to-finish interval and buckets
  between point timestamps. The first point after resume can include unrelated
  heart-rate samples from the parked interval.
- Existing Watch test `parkAndResumeExcludesIdleTimeFromSetDuration` verifies
  retained set play time and a restarted clock. It does not verify HealthKit
  workout intervals or activity totals.

The Phase 2 implementation follows this requirement: persist explicit session boundaries and prior
activity, start each workout at resume, accumulate each session exactly once,
and scope HR buckets/graphs/coaching to sessions. Test repeated resumes, relaunch,
Health disabled on a later session, counter resets and delayed workout callbacks.
Real HealthKit collection and saved workout intervals also require physical-Watch
verification; simulator scoring tests cannot prove sensor behavior.

## 3. Date and ordering rules

### Shared date policy

Implement one pure Core policy for these meanings, reused across stores, views,
Trends, and exports. Suggested names below describe semantics, not a committed API.

| Meaning | Rule |
|---|---|
| Original start | Keep `startTime` unchanged. |
| Completed result date | `endTime`; for a legacy completed record without one, fall back to `startTime`. Label that fallback `Played`, not a falsely precise `Finished`. |
| In-progress activity date | Latest recorded play/resume/explicit park time; fall back to `startTime`. Never use sync receipt, import, metadata edits, or the current render time. |
| Archive recency | Completed result date for completed matches; activity date for unfinished ones. Sort descending, then UUID string ascending for deterministic ties. |
| Trends chronology | Result date for completed matches; activity date for opted-in in-progress matches. Sort ascending, then UUID string ascending, before applying the selected window. |

Keep the existing live-match section on iPhone. Retain a combined past-match list
for the first release: unfinished rows stay visibly `In progress` and use their
activity date. Among completed matches, newest completion always comes first.
A separate `Paused matches` section is an optional later layout change.

For schema-free phase 1, unfinished activity can use the last recorded point time
(or start time when there are no points). Phase 2 adds observed park/resume times.
Do not invent a last-played time for a tracking-disabled legacy record.

### Trends

- Update **both ordering and date labels**. Changing only the label leaves `Last
  10`, recent/previous blocks, delta arrows, and sparklines using the wrong matches.
- Keep one sample per match UUID, existing eligibility/coverage rules, filter-before-
  window semantics, and pooled numerator/denominator calculations.
- Add a distinct derived `date`/`resultDate` to `MatchTrendSample`; do not quietly
  change the meaning of its existing `startTime` property.
- Preserve the existing include-in-progress setting and its default. When enabled,
  label unfinished samples provisional. On completion, move/update the same sample;
  never append a second observation.
- Explain briefly: `Completed matches are ordered by finish date.` With unfinished
  matches enabled, also explain that they use last recorded activity.
- Keep ordinal spacing. A week-long interruption does not require a new time axis.

### Match history and related dates

Use the same policy on both devices, watch-only mirror rows, import/restore
results, archive backup previews, and the watch's retention ordering. Otherwise
an old-start/new-finish match can still fall out of the watch's 25-match history
immediately after finishing.

Update row labels alongside sorting. In details, show both start and finish when
they fall on different local calendar days; a compact same-day presentation is
sufficient otherwise. Format in the user's current locale/timezone; sort absolute
instants, not formatted dates. Export both timestamps for multi-day matches.

Apply completion chronology to `Compare with Previous Match`, baseline pickers,
head-to-head recent results, and opponent match lists. For an unfinished comparison,
use its activity date as the reference and clearly label it unfinished. Roster
`last played` uses actual recorded play/activity where available: administratively
closing an old match today should not pretend the opponents played today.

### Completion must be stable

Capture normal completion time when the final scoring action occurs, even when
point categorisation or closing the match screen happens later. Persist it in live
state; reuse it for checkpoints, finalization, and retries. Undo of the winning
point clears that provisional completion time; a new winning point gets a new one.
Do not derive it solely from `stats.last` because point tracking may be disabled.

For **End at Current Score**, use the time of that deliberate completion action.
For a match parked a week ago and closed today without more play, this means
`Finished today`, with last-played information available separately. This explicit
rule avoids silently guessing a historical finish date. Manual finish-date editing
is deferred because `endTime` also participates in sync conflict resolution.

Do not bulk rewrite old records. Existing `endTime` values are the best available
completion evidence. Date-policy changes must not change the merge winner rules or
use display recency as a substitute for record revision/authority.

## 4. What counts as a resume?

**Confirmed interruption:** an explicit park followed by an explicit resume of
that match. Record every such resume, including short breaks and multiple sessions.
The park/resume timestamps measure time between these app actions, not the exact
instant the ball stopped or restarted.

- History resume is confirmed even for a legacy/manual record without a known
  park time. Show `Resumed`; duration remains unknown.
- Backgrounding, lowering the wrist, dismissing the scoring sheet, or relaunching
  the app is **not sufficient evidence of stopped play**. The watch can continue
  recording, and iPhone scoring can remain available.
- Reopening a still-live match should not automatically create a confirmed marker.
  A long inactivity gap may support a future `Did you take a break?` affordance,
  but no prompt or automatic inference is required for the first release.
- If a dedicated `Pause match` action is added, it should use the same park/resume
  lifecycle. Consider renaming the current parking action `End Match` to `Pause
  match`, with `Finish at current score` remaining separate. This is a proposed
  UX follow-up, not a hidden change to existing button semantics.

The previous draft's five-minute background threshold measured app inactivity,
not necessarily an interruption. It is removed from the confirmed-break design.
Never infer historical breaks from long gaps between points or heart-rate changes.

## 5. Resume presentation

### Points graph

Draw a subtle dashed vertical line **between** the last pre-resume point and the
first post-resume point. Label it `Resumed · 8 Nov`; supplementary detail can say
`Break: 7 days` when measured. Distinguish it from set boundaries and the selected-
point rule using line style and text as well as colour.

```text
Points played →   •  •  •  •  │  •  •  •  •
                              ┆
                        Resumed · 8 Nov
                        Break: 7 days
```

- Keep point spacing, score progression, set boundaries, and momentum continuous.
  A resume does not reset the tennis score or create a new set.
- Show markers with all graph modes and with health overlays off, in both inline
  and expanded graphs through their shared `PointsChartCore`.
- Break health/movement connecting lines at confirmed session boundaries; never
  imply uninterrupted physiological measurement across the gap.
- Add a corresponding divider in point history. For `All / Set N`, a boundary
  belongs to the following point's set. Preserve full-history coordinates when
  filtering; changing outcome/serve filters must not move the boundary.
- Coalesce coincident visible rules (`Resumed twice`) but retain all events in
  details and exports. Avoid overlapping labels on narrow screens.
- With no post-resume points, retain a trailing event and show it in session details;
  do not assign it to a future set yet. With no points at all, show a session summary
  instead of manufacturing a chart point.
- VoiceOver should announce, for example, `Play resumed 8 November, before recorded
  point 43, after a seven-day break`. Large text must not obscure point selection.

### Match details, exports, and coaching

For interrupted matches add a compact `Play sessions` summary: original start,
resumptions, finish, and recorded play duration. Offer detailed timestamps without
making every match row taller. Do not call a week of wall-clock span play duration.

Text summary, full point report, AI prompt, interactive HTML, and static HTML must
carry the same interruption context. Events are perspective-neutral; recorder-only
health data remains subject to existing perspective and consent rules. Exports
without events need no empty interruption section.

Coaching should avoid attributing a post-resume HR change to continuous-match
fatigue or recovery. Session-aware comparisons may be offered only when coverage
is sufficient; the line itself does not establish why performance changed.

## 6. Persistence, sync, and derivation

Proposed additive fields:

| Model | Fields |
|---|---|
| `MatchResumeEvent` | Stable `id`, observed `resumedAt`, optional `pausedAt`, optional `precedingPointID`. |
| `MatchRecord` | `resumeEvents: [MatchResumeEvent] = []`, `parkedAt: Date? = nil`. |
| Watch live state | Same events/open park, plus the captured normal completion timestamp. |

A stable event ID allows duplicate delivery to be recognized. `precedingPointID`
anchors a boundary to existing recorded history despite equal timestamps or a
clock adjustment; it is not a mutable numeric index. Capture it before resumed
points are accepted. No new field is required on `PointStat`.

Core derives render boundaries once, in the `ResumeMarkers` helper. Prefer
the point-ID anchor. If unavailable, use the first recorded point at/after the
resume timestamp in stored play order, without reordering the score history.
An unresolvable or inconsistent anchor should yield an unplaced session event,
not a guessed line. Test equal timestamps, missing anchors, suffix-only history,
and manual records. Render JSON may contain a derived boundary index.

Negative park-to-resume intervals yield unknown duration, never a negative label.
Missing park times stay unknown. No previous resume is invented for old records.

Follow `CLAUDE.md` §4: defaulted initializer parameters and `decodeIfPresent` in
both record and live-state decoders. A cosmetic live-state version increment is
not a migration mechanism. Manual archive schema remains compatible (currently
version 1); additive record fields do not require rejecting old exports.

Carry fields through **every** checkpoint, finalization, park, resume, clear,
restore, and completion path, including phone `End at Current Score`. Prefer one
shared record builder to duplicated defaulted initializers. Clear the open park
on resume/completion; reset all session state when changing match identity.

Persist the event before acknowledging resume; a failed save must not remove the
only archived copy. Repeated save/sync or duplicate lifecycle callbacks must not
append events. Existing events survive undo; boundaries must still resolve after
undo/rescore. Resume without scoring, then park again, legitimately creates
multiple sessions at the same point boundary.

Events travel inside existing Codable match payloads, with no new wire key. The
watch remains authoritative for scoring. Preserve confirmed events when a winning
copy comes from an older app that omitted the new fields: reconcile immutable
events by ID independently of body choice; take `parkedAt` only from the winning
body and clear it for completed records. Pin deterministic resolution of duplicate
IDs in Core tests. Never union point histories or bypass tombstones. Metadata tags,
match-type revisions, and forgotten-player scrubbing retain their existing rules.
An older app that alone rewrites a record may still lose unknown fields; guarantee
full fidelity between updated peers and document this mixed-version limitation.

Resume events are session metadata, not HealthKit samples. Preserve them through
health stripping/sidecars, iCloud backup, manual archive transfer, and restoration.
Update the HTML render contract and both renderers together. The web schema is **14**, including resume rows, session summaries and health
series session IDs (up from 13 before Phase 2).

## 7. Additional aspects worth considering

| Priority | Aspect | Recommendation |
|---|---|---|
| Required with date changes | Watch retention | Sort by the shared recency policy before capping at 25, so newly finished long-running matches remain available. Protect existing pre-eviction sync behaviour. |
| Required with session support | Health query scope | Exclude known parked intervals from HR queries/buckets. If the park is unknown, avoid bridging across the boundary; use point snapshots where a continuous interval cannot be established. Never bucket a week's unrelated HR readings into one resumed point. |
| Required with session support | Workout identity and totals | Start each resumed workout at that session's start, retaining the original match start only as match metadata. Verify steps/distance/calories accumulate once across sessions and survive retries; handle reset cumulative counters at session boundaries. |
| Required with session support | Recorded duration | Exclude confirmed parked time from match/set timers. Keep `recorded play time` separate from start-to-finish span; app invisibility alone must not stop the play clock. Avoid claiming exact active time where legacy data cannot establish it. |
| Required consistency | Previous match / head-to-head | Use finish chronology for completed results and baseline selection; keep unfinished matches out of completed win/loss records. |
| Useful follow-up | Clearer actions | `Pause match`, `Resume match`, and `Finish at current score` better distinguish resumable and final states than today's `End Match`. |
| Useful follow-up | Session-aware coaching | Compare pre/post-resume results only with adequate samples. Fatigue and recovery calculations must not bridge session boundaries. |
| Later | Correcting historical dates | Offer explicit finish-date correction only with a separate revision/merge design; changing `endTime` currently affects conflict resolution. |
| Later | Per-session analysis | Optional session picker and session summaries; keep aggregate match results and Trends as one match. |

No reminders, automatic break detection, historical session reconstruction, new
scoring rules, or reopening of finalized matches are proposed for the first release.

## 8. Delivery plan and implementation map

**Phase 1 — completion chronology.** Deliver the shared date policy, stable final-
scoring timestamp, Trends ordering/labels/windows, history rows and retention,
comparison/head-to-head consistency, and browser-demo parity. Existing completed
archives improve immediately without a data rewrite. Add a short release note that
recent Trends windows may change because they now reflect finish order.

**Phase 2 — confirmed sessions.** Deliver persistence/lifecycle, graph and point-list
markers, detail summaries, all export variants, session-safe health handling, and
demo parity together. Health correctness is part of this phase, not something a
visual line alone solves.

**Phase 3 — optional UX.** Evaluate clearer pause/finish wording, unfinished-list
sections, and session comparisons separately.

| Surface | Main implementation sites |
|---|---|
| Dates and Trends | Core `Models/MatchRecord.swift`, shared `MatchChronology` helper, `Stats/MatchTrendSample.swift`, `Stats/PerformanceTrends.swift`; iOS `Views/Trends/` |
| Storage and lists | Core `Sync/{MatchMergePolicy,ArchiveBackupPolicy,WatchMirror}.swift`; watch `StatsStore.swift`, `MatchHistoryView.swift`; iOS `Persistence/PhoneStatsStore.swift`, `Views/PastMatchesView.swift` |
| Comparisons and opponents | Core `Stats/{MatchComparison,PlayerRoster,OpponentDirectory}.swift`; iOS `Views/MatchInfo/` |
| Session capture | Core resume-event/marker types; watch `ScoreViewModel.swift`, `HomeView.swift`, `MatchStatsView.swift`; phone completion path |
| Graph and health | iOS `Views/{PointsGraphView,MatchDetailView}.swift`, `HealthKitHRFetcher.swift`; watch `WorkoutManager.swift`; Core movement/coaching derivations |
| Sharing | iOS `Export/MatchExporter.swift`; Core `WebExport/` view model, interactive template, static fallback; export-cache inputs and filename policy audited explicitly |
| Demo | `docs/website/assets/` watch history, phone history/reports/trends/export/coaching mirrors; regenerate native export assets using the existing workflow |

Keep export filenames start-date-based for phase 1, as currently documented;
finish-date headers carry the new meaning. Renaming shared files can be considered
separately. Full-record equality already invalidates `TrendsSamples`; maintain it.

When implementing, update the user guide, lifecycle/health/sync architecture docs,
`CLAUDE.md`, and production file inventory where sources are added or changed.
The implemented component and lifecycle changes are recorded in the architecture documents.

## 9. Acceptance and verification

1. The A/B/C example orders A–C–B in both histories and B–C–A in Trends. `Last N`,
   filters, deltas, tooltips, and sparklines use that chronology; sync/import order
   does not affect it.
2. Single-session matches retain expected order. Equal completion instants have
   deterministic ties. Completed draws work; legacy completed records without an
   end time remain readable and use the documented fallback.
3. The winning point is scored before midnight and the screen closed after midnight:
   finish date remains the winning-point date. Undo/re-win updates it once. Delayed
   categorisation and app restoration do not change it.
4. Ending a parked match without more play uses the explicit action time. Phone/watch
   reconciliation keeps the authoritative score and preserves session metadata.
5. A provisional Trends sample becomes one completed sample with the same UUID.
   Metadata edits, health backfill, sync, and imports do not make a match newly played.
6. An old-start/new-finish match remains among the newest 25 watch records. Combined
   phone/watch-only rows and backup previews use the same date policy.
7. Explicit park → resume → play → finish survives a store read, relaunch, offline
   sync, archive export/import, and health-stripped backup with every event intact.
   Missing fields decode safely. Failed writes do not report successful transitions.
8. Multiple sessions, unknown park times, resume-without-scoring, no points, tracking
   disabled, clock changes, midnight/DST/travel, duplicate events, and undo/rescore
   have deterministic behaviour. Background/foreground alone creates no marker.
9. Inline, expanded, interactive HTML, static HTML, and demo graphs agree on boundaries
   under set/outcome filters. Point selection still works; VoiceOver and large text
   convey the interruption without relying on colour.
10. HR/steps lines and coaching do not bridge confirmed breaks. Resumed workouts use
    session dates; recorded duration excludes confirmed gaps; activity totals neither
    lose earlier sessions nor count them twice.
11. Text/AI/HTML exports agree on dates and interruptions, preserve health-sharing
    consent, and remain self-contained/offline. Existing script-safety tests pass.
12. Existing completion authority, tombstones, tags, match-type revisions, notes, and
    forgotten-player handling remain intact through all merge/restore paths.

Implementation verification: Core unit tests for chronology, Trends windows,
comparison, retention, coding, markers, merge and export contracts; Watch tests for
lifecycle persistence/timing/workouts; iPhone tests for history/graph/export updates;
existing browser parity checks and manual accessibility review. Use local Swift/
Xcode when available, following `CLAUDE.md`; do not trigger GitHub Actions.

## Phase 2 implementation and release validation

The session model is additive: `MatchResumeEvent`, default-empty resumeEvents and
optional parkedAt, with deterministic event union independent of score authority.
`ResumeMarkers` derives full-history coordinates; `MatchSessions` supplies shared
session descriptions and HR windows. Private backup-excluded AppState retains
fitness baselines and clocks. Graph/history/detail, physiological calculations,
text/AI reports, interactive/static HTML schema 14 and browser replicas carry the
same context. Unreadable/newer live-state files block writes/scoring; failed park
or resume retains durable data and shows an error. A resumed checkpoint leaves
history only after the live state is durable, protecting crashes during transition.
If the live file later becomes unreadable, the Watch has no stored copy until it can
be read again; the file is preserved and the phone keeps its last checkpoint.

For interrupted records, continuous Pulse/Steps insights are withheld, exertion
comparisons are confined to adequately covered individual sessions, and estimated
linear step timelines are suppressed. Unknown parks use saved HR snapshots where
continuous sample windows cannot be established. This does not infer breaks from
backgrounding or fabricate historical sessions. Updated peers preserve metadata;
an old app that rewrites a record alone may drop fields it does not understand.

### Retained workout completion behavior

Result dates and recorded play/set clocks stop at the winning point. HealthKit
collection retains the existing behavior of continuing until successful match
clear/finalization. Delayed final-point categorization or result-screen dismissal
can therefore extend the saved workout and its Health totals past the winning
point. Pending point sensor snapshots are also taken on commit. No confirmed
parked break is included. Ending a workout immediately at a provisional winning
point requires a separate completion/undo design so final-point measurements are
preserved and undo can restart collection without inventing a resume event.

### Pending physical-Watch checklist (required before release)

- [ ] Play, park, wait, resume and finish on the same day. Confirm separate saved
  Health workout intervals start/end at each play session and exclude the break.
- [ ] Repeat across different dates and multiple resumes, including resume without
  scoring. One match/result retains every explicit event and known/unknown break.
- [ ] Score a winning point, wait before categorizing/dismissing, then inspect
  workout end/totals. Confirm the retained collection-until-dismissal behavior
  and distinguish it from the frozen result date and recorded play clock.
- [ ] Compare steps, distance and calories before parking, after resuming and after
  finalizing. Earlier totals survive; each new workout contributes once.
- [ ] Disable/deny Health on a later session. Prior totals remain; missing new
  measurements do not become fabricated activity.
- [ ] Background/reopen/lower the wrist without parking: no resume event or invented
  break, and existing play/workout behavior remains usable.
- [ ] Relaunch during resumed play, retry saves, and start a new session while an
  older workout finishes. No duplicated totals or stale HR/calorie publications.
- [ ] Check HR overlays, smoothing and movement on both sides of a known break;
  unrelated break-time samples must not enter a resumed-point average. Check
  unknown prior parks use snapshots and graphs do not draw continuous health lines.
- [ ] Check VoiceOver and large text: markers announce the resume/date/break and
  point history/session details remain readable, including trailing events.
- [ ] Compare the native report and both HTML perspectives (with/without JavaScript),
  set filters and sharing disclosures on actual supported devices.

Automated results are reported separately; this checklist must not be inferred
complete from simulator or browser tests.

### Automated verification (4 November 2026)

- Core: 883 tests passed, including coding/merge/privacy/marker/window/HTML contracts.
- Watch: 111 tests passed, including injected resume/park/idle-write failures and
  fake-workout accumulation/relaunch/Health-unavailable cases.
- iPhone: 111 tests passed, including HR session/set windows and text/AI exports.
- Native/browser coaching parity: 240 scenarios passed, including interrupted play.
- Browser model/session and coaching suites passed; generated native export is current.
- Chromium and WebKit session probes passed: seven-day interruption, fixed inline
  and expanded markers, session IDs, interactive export and JavaScript-disabled
  static export. Expanded graph screenshot reviewed.
- Existing Chromium export/prompt/manual/rotation suite passed; diff whitespace clean.

These results do not complete the pending physical-Watch checklist above.

# Match Lifecycle — the journey of one tennis match

This is the end-to-end story of a single match, from the first swipe to an AI
coaching conversation, with the responsible files named at each stage (each is
described in the [file inventory](file-inventory.md)).

```mermaid
flowchart TD
    SETUP["1 · Setup on the watch<br/>singles/doubles, names, format,<br/>first server, court end"]
    SCORE["2 · Live scoring<br/>swipe up/down per point,<br/>swipe left to undo"]
    CAT["3 · Point categorisation (optional)<br/>winner / error / double fault<br/>+ ending shot, on watch or phone"]
    HEALTH["Workout runs throughout<br/>heart rate · calories · steps"]
    CHANGE["Changeovers<br/>prompt + compass check of court end"]
    PARKED["4a · In Progress (parked)<br/>workout closed, score remains resumable"]
    END1["4b · Completed normally<br/>configured format reached"]
    EARLY["4c · Ended early<br/>completed at current score"]
    SYNC["5 · Sync to iPhone<br/>record + manifest over the bridge"]
    ARCHIVE["6 · Permanent archive on iPhone<br/>(stripped main + local Health sidecar;<br/>iCloud backup in background)"]
    INSIGHT["7 · Stats, graphs & coaching<br/>serve/return/error stats, momentum chart,<br/>Rec Coach & Pulse Coach observations"]
    EXPORT["8 · Export & AI coaching<br/>text report, coaching prompt, or<br/>interactive HTML page · handed to<br/>ChatGPT, Claude, Gemini, ... or shared"]
    MANAGE["9 · Housekeeping<br/>free watch space (keep phone copy)<br/>or delete permanently (tombstoned)"]

    HOME["Idle home after restore/authorization"]
    OFFER["Optional first-use offer / Animated guide entry"]
    GUIDE["Nine automatic situations<br/>in-memory scoring + points only"]
    DISCARD["Done / dismissal: discard guide<br/>only two watch-local flags persist"]
    HOME --> SETUP
    HOME --> OFFER
    OFFER --> GUIDE
    GUIDE --> DISCARD
    DISCARD --> HOME

    SETUP --> SCORE
    SCORE --> CAT
    CAT --> SCORE
    SCORE -.-> CHANGE
    CHANGE -.-> SCORE
    HEALTH -.-> SCORE
    SCORE -- "End Match" --> PARKED
    PARKED -- "Resume this match" --> SCORE
    SCORE -- "final point reaches format" --> END1
    PARKED -- "End at Current Score<br/>(Watch or iPhone)" --> EARLY
    SCORE -- "live checkpoint after every point<br/>(scoreboard + spoken score on iPhone)" --> SYNC
    END1 --> SYNC
    PARKED --> SYNC
    EARLY --> SYNC
    SYNC --> ARCHIVE
    ARCHIVE --> INSIGHT
    INSIGHT --> EXPORT
    ARCHIVE --> MANAGE
```

## Match status lifecycle

This is the persisted state machine behind the journey above. **End Match** and
**End at Current Score** deliberately mean different things:

```mermaid
stateDiagram-v2
    state "Being Played" as BeingPlayed
    state "In Progress" as InProgress
    state "Completed Normally" as CompletedNormally
    state "Ended Early" as EndedEarly
    [*] --> New
    New --> BeingPlayed: Start Match
    BeingPlayed --> InProgress: End Match (park)
    InProgress --> BeingPlayed: Resume this match
    BeingPlayed --> CompletedNormally: Final point reaches the configured format
    InProgress --> EndedEarly: End at Current Score
    CompletedNormally --> [*]
    EndedEarly --> [*]
```

- **New** — setup exists, but scoring has not started.
- **Being Played** — the match is live on the Watch; point checkpoints are saved
  locally and mirrored to the iPhone.
- **In Progress** — play has been parked by **End Match**. It remains resumable
  and retains the same match identity, score, server, timing, and point history.
- **Completed Normally** — the configured match format reached its normal win
  condition on a final point.
- **Ended Early** — the player selected **End at Current Score** from the
  in-progress match detail on Watch or iPhone. The stored score is finalized;
  sets, then games, then current points decide the leader, and a level score is
  a completed draw. This state cannot be resumed.

Both completed routes persist the same completed `MatchRecord` shape. “Completed
Normally” and “Ended Early” describe how it got there; they are not separate
long-term archive statuses.

For a parked Watch record, completion reads, updates and saves the existing ID
on the archive's serial queue. An unreadable archive, missing/completed record,
or failed save reports failure: the detail sheet stays open with an error and
no history is synced. Only the successfully saved history snapshot is sent to
the phone. A stale sheet record is never used to recreate an absent match.

## Result and activity dates

`MatchChronology` keeps the original `startTime` intact. Completed results use
`endTime`; legacy completed records without it use the start, labelled **Played**.
Unfinished matches use their latest recorded point timestamp, falling back to the
start when there are no recorded points. History, Watch retention (25 matches),
restore/import results, backup previews, comparisons and head-to-head recent
results share this chronology. Equal dates sort by UUID ascending. Trends uses
ascending chronology before filtering/windowing, with a separate sample `date`;
its original `startTime` retains its meaning. Opted-in unfinished samples are
provisional and keep the same UUID after completion.

The Watch captures `matchCompletionTime` when the final scoring action happens,
including with outcome tracking off. It is an optional, backward-compatible
`AppState` field, reused at normal finalization after categorisation or relaunch.
Undo clears it; a new winning point captures a new instant. Live checkpoints
remain unfinished until finalization so undo remains authoritative. Explicit
**End at Current Score** uses the deliberate action time. Roster last-played uses
recorded activity, so administratively closing a parked match does not invent play.

Rows label the date's meaning; details and every report retain both start and
finish when their local calendar days differ. Export filenames still use the
original start. This requires no archive migration or rewrite and adds no match
record/wire fields in Phase 1. Phase 2 adds backward-compatible session metadata,
with the lifecycle below; elapsed span is never evidence of active play.

## Stage by stage

**1 · Setup (watch).** The player picks singles or doubles, names, the match
format (six supported, from best-of-3 to perpetual tiebreak — the rules are
data-driven in `ScoreTypes`), who serves first, and confirms the court end if the
compass feature is on. A HealthKit workout session starts automatically with the
match (given HealthKit permission).
*Files: `HomeView`, `ScoreViewModel`, `WorkoutManager`.*

**2 · Live scoring (watch).** Each swipe becomes "player X won a point" and is fed
through the shared tennis rulebook (`ScoringEngine`), which returns the new score
plus events: game won, set won, tiebreak started, changeover due. Undo rolls the
whole game state back. After every point the watch saves a checkpoint locally
(crash-safe: the match can be resumed) and sends it to the phone, which updates
the live scoreboard and — if enabled and on screen — speaks the score.
*Files: `ContentView`, `ScoreViewModel`, `ScoringEngine`, `StatsStore`,
`WatchMatchSyncService` → `PhoneMatchSyncService`, `LiveScoreboardView`,
`LiveAnnouncementService`.*

**3 · Point categorisation (optional, watch or phone).** With outcome tracking on,
a sheet asks how the point ended (winner, forced error, unforced error, double
fault) and on which shot. The same pending point is mirrored to the phone so a
spectator can tag it instead. Each tagged point also snapshots the player's heart
rate and step count — the raw material for all statistics and coaching.
*Files: `PointCategorySheet` (watch), `LivePointCategoryPanel` (phone),
`PointStat` (the data).*

**Throughout: workout & changeovers.** The workout session collects heart rate,
calories, steps and distance; at changeovers the watch prompts the players and can
use the compass to confirm they're heading to the correct end.
*Files: `WorkoutManager`, `ScoreViewModel`, `ContentView`.*

**4 · Stop or finish (watch).** A final point completes the configured format.
The live **End Match** action instead closes the workout and parks the current
score as an in-progress record, preserving the existing resume flow. From that
record's history detail, **End at Current Score** explicitly completes it: sets,
then games, then current game/tiebreak points determine the leader; a level score
is a completed draw. The watch keeps only its newest 25 matches — older ones roll
off (the phone keeps them; see stage 6). *Files: `HomeView`, `MatchStatsView`,
`ScoreViewModel`, `ScoringEngine`, `WorkoutManager`, `StatsStore`, `WatchHistoryCap`.*

**5 · Sync (watch → phone).** The finished record, an "active match over" signal
and the watch's manifest (which match IDs it still holds) go to the phone. The
merge rules (`MatchMergePolicy`) guarantee a finished match can never be
overwritten by stale data, and deleted matches stay deleted (tombstones). Details
in [sync-and-data-flow.md](sync-and-data-flow.md).
*Files: `WatchMatchSyncService`, `PhoneMatchSyncService`, `MatchMergePolicy`,
`MatchSyncTransport`.*

**6 · Archive (phone).** The match joins the permanent archive. Full records are
kept in memory, while disk persistence is split into a normally backed-up,
health-stripped match history and a backup-excluded sidecar containing only
heart rate, steps, distance, and calories. A background backup in the user's own
iCloud Drive (status shown as "Backed up to iCloud") also contains only the
stripped records. iCloud can restore during initial local archive setup; after
that it receives pushes from the phone and does not merge back. Sidecar rules
live in `HealthSidecarPolicy`; cloud rules live in `ArchiveBackupPolicy`.
The list shows where each match lives: both devices, phone only, or watch only.
*Files: `PastMatchesView`, `PhoneStatsStore`, `HealthSidecarPolicy`, `ArchiveBackupPolicy`,
`ICloudBackupCopy`, `MatchStorageLocation`, `WatchMirror`.*

**7 · Stats, graphs & coaching (phone).** The match page derives everything from
the tagged points: serve/return/break-point stats, error profile, pressure-point
performance (`MatchStatsSummary`); a momentum chart with optional heart-rate and
step overlays fetched from HealthKit; "Rec Coach" observations (from at least 20
tagged points) and "Pulse Coach" heart-rate observations (from at least 10
HR-tagged points). *Files: `MatchDetailView`, `PointsGraphView`,
`HealthKitHRFetcher`, `MatchStatsSummary`, `RecCoachInsights`/`RecCoachSection`,
`PulseCoachInsights`/`PulseCoachSection`.*

**7a · Match details, notes & comparison (phone, optional).** At any point after
the match reaches the phone archive — including while it is still **in progress**
— the user can open **Match Info** to record who they played (opponent, or partner
plus two opponents in doubles, picked from a roster derived from the archive) and
the competition type. This edits only the match's `tags`; it never changes the
score or completes the match, and the edit is pushed to the watch on its own
`matchTagsUpdate` key. A **private note** saves to an iPhone-only, backup-excluded
sidecar, separate from the record. **Compare with Previous Match** sets the match
beside the last one against the same opponent(s) — or the last of the same
singles/doubles type when it is untagged — with partial stats labelled and a
completed-only head-to-head. Settings → Players renames, merges or forgets a
player across every match. *Files: `MatchInfoSection`, `MatchInfoEditorView`,
`PlayerPickerView`, `MatchNotesEditorView`, `MatchComparisonView`,
`PlayersSettingsView`, `PhoneStatsStore`, `MatchNotesStore`; Core `MatchTags`,
`PlayerRoster`, `MatchComparison`, `MatchNotes`, `ForgottenPlayerLedger`. See
[MATCH_TAGS_PLAN.md](../features/MATCH_TAGS_PLAN.md).*

**8 · Export & AI coaching (phone).** The player can export a text summary, a full
point-by-point report, or an AI coaching prompt tuned to their skill level, and
hand it straight to an installed AI chat app (ChatGPT, Claude, Gemini, Perplexity,
Copilot, Poe, Grok) or the share sheet. They can also share a self-contained
interactive HTML page of the match — built off-thread and shared as a `.html` file —
with the momentum chart and set bands, a Stats/Points tab toggle, All/Set N filters, a
TV-style Me-vs-Opp comparison, a point-by-point list, and an optional AI Coach card.
The share menu offers it from **My Perspective** or **Opponent's Perspective**; each
file is framed for its reader, so the opponent's says they won when they did.
The page loads zero external resources; progressive enhancement
ships a static, no-JS report so even iOS Quick Look shows a readable preview.
Whenever an export would carry HealthKit data (heart rate, steps, calories,
distance), a per-export **"Share health data?"** disclosure names exactly what is
included and the user confirms before it leaves the device — the deliberate,
consented exception to "health never leaves the device unstripped." The disclosure
is skipped for a health-free match. See [health-data-flow.md](health-data-flow.md)
for the full strip / exclude / gate map.
*Files: consent gate — `HealthExportConsent` (Core), `MatchDetailView` (`beginShare`/`beginAICoach`);
text/AI export — `MatchExporter`, `AICoachSheet`, `AICoachLauncher`; HTML export —
`MatchDetailView` (share action) + Core `WebExport/` (`MatchWebViewModel`(+`Build`/`Comparison`/`AICoach`),
`MatchHTMLExporter`, `MatchWebTemplate`, `MatchWebStaticFallback`, `WebExportColors`);
see [INTERACTIVE_HTML_EXPORT_PLAN.md](../features/INTERACTIVE_HTML_EXPORT_PLAN.md).*

**9 · Housekeeping.** From the phone the user can free up watch space (delete from
the watch, keep the archive copy — the badge flips to "phone only") or delete a
match permanently (tombstoned so no future sync resurrects it; its private note is
deleted too). A watch-only match
can be pulled back into the phone archive at any time.
*Files: `PastMatchesView`, `PhoneStatsStore`, `PhoneMatchSyncService`.*

## Side journeys: phone-authored archive actions

Manual entry reconstructs a match from a paper scorecard or watch mishap. The
form saves it **directly into the phone archive** and sends a copy to the watch,
where it can be resumed and scored normally.

An in-progress iPhone archive detail also offers **End at Current Score**. The
phone completes its stored checkpoint and reliably sends that version to a
watch known to hold the match. If the same identity is currently live there,
the watch completes its newer live score and sends that authoritative record
back; if it is merely parked, the explicit completed version replaces it.
*Files: `ManualMatchEntryView` / `MatchDetailView` → `PhoneMatchSyncService` →
`WatchMatchSyncService` → `ScoreViewModel`.*


## Side journey: isolated animated watch guide

Home waits for restoration and launch presentation to finish. Successful reads,
empty history, no prior offer/completion and idle production state permit one
automatic offer. Guide retains its text reference and adds Animated guide;
entry is unavailable during live scoring, warmup, pending categorisation or setup.
Dismissal/Not now marks offer-seen; final Done records completion.

`WalkthroughViewModel` owns a disposable Core `WalkthroughSession`. Nine
situations automatically animate score gestures, category selections, stats
scrolling and changeover acknowledgement using existing reducer/reminder/stat
rules. Previous/Next replace the fixture at any beat; results wait for navigation.
There is no lesson/replay menu or required user gesture. Shared score/court/banner
and stats views take values only; category previews are read-only fixed examples.
Navigation/dismissal cancels tasks and rejects old generation callbacks; scene
inactivity pauses the script. No guide path reaches persistence, sync, export,
workout or heading. Production background and remote work stays in the normal app.

## Confirmed session lifecycle

Only explicit history resume creates a `MatchResumeEvent`: stable ID, resume time,
optional observed park time and optional preceding point ID. Park writes parkedAt;
resume/completion clears it. A same-identity reopen and scene changes create none.
A resume candidate must be durably saved to live state before navigation/workout
replacement. Only then is the archived checkpoint removed, so a failed write or
immediate crash cannot destroy the only saved copy; a copy left behind is removed
on the next launch. While live, the match is in live state and not in history.
Park/finalize
must durably append before clearing/replacing the live match; failures remain visible.
Unreadable/newer live states suspend writes and scoring, preserving original bytes.

Undo retains events. Marker derivation uses original point order and stable IDs;
missing/ambiguous anchors stay unplaced. Trailing/no-point events remain visible in
session summaries without inventing a point. Coincident markers coalesce visually.
The full-history boundary determines set membership before display filtering.

Workouts restart at the current session time. Prior aggregate activity survives
AppState save/relaunch and is added once to each fresh builder snapshot; repeated
saves do not advance the baseline. Match/set play clocks exclude explicit parked
time and stop at normal completion, including delayed categorization. No historical
breaks are inferred. See [health-data-flow.md](health-data-flow.md) for physiological
window and privacy rules, and the feature plan for pending hardware validation.

### Workout save completion

Parking or finalizing stops the current play session's workout independently of
whether the tennis match has a final result. `WorkoutFinalizer` retains the
session and builder until collection ends and HealthKit's save callback returns,
then ends the session. A newly resumed workout cannot be finalized by an older
callback. Failure is shown on the Watch Home/live screen without removing the
saved match score. A saved Health workout, rather than a DeuceMate archive row,
is what Fitness can display after device syncing. Physical-device save/sync
verification remains required.

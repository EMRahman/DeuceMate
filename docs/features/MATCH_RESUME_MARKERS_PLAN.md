---
title: Match Resume Markers and Export Context
status: proposed
document_type: implementation_plan
created: 2026-07-14
last_updated: 2026-07-14
product: DeuceMate
platforms:
  - watchOS
  - iOS
  - interactive-html-export
components:
  - match-persistence
  - watch-scoring
  - points-graph
  - text-export
  - ai-coaching-export
  - html-export
schema_changes:
  match_record: backward-compatible
  watch_app_state: backward-compatible
  manual_archive: no-change
  web_export: 6-to-7
decisions:
  resume_definition: measured-break-both-paths
  interruption_detail: marker-and-measured-duration
  graph_anchor: derived-in-core-from-timestamps
  export_scope: all-exports
  infer_legacy_breaks: false
---

# Match Resume Markers and Export Context

## Summary

Persist every match interruption that the app actually **measured** — a park with
a known wall-clock time, followed by a resume — and display it as a visible
session boundary on the graph and in every export.

Two user paths produce a measured break, and **both** count:

1. **Resume from history** — the match was ended-as-in-progress and later resumed
   from the History screen (`ScoreViewModel.resumeMatch(_:)`).
2. **Resume a live match after a gap** — the match sheet was dismissed, or the app
   was backgrounded, and the user returned to the still-live match after a break
   longer than `ResumeMarkers.minimumBreak`.

Path 2 is the common one and was nearly missed: the button labelled **"Resume
Match"** on the watch home screen (`HomeView.swift:337-348`) does *not* call
`resumeMatch(_:)` — it just reopens the modal on the still-live in-memory match.
An earlier draft of this plan scoped the feature to path 1 only, which would have
drawn no marker in exactly the rain-delay case the feature exists to explain.

In both paths the park and resume wall-clock times are **observed**, so the break
duration is measured, never inferred. Nothing is guessed from gaps between point
timestamps or from heart-rate data.

This makes a post-resume heart-rate change visually explainable and gives text,
HTML, and AI exports an explicit interruption signal instead of forcing a user or
a model to infer one from physiological data.

## Success criteria

- Every measured break is retained, including multiple breaks in one match, across
  both resume paths above.
- Returning to a live match after a trivial pause (a glance at the watch face)
  records **no** marker. Only breaks of at least `ResumeMarkers.minimumBreak` count.
- The iPhone points graph clearly marks each resume boundary whether or not its
  heart-rate overlay is enabled.
- A measured break duration is shown whenever the park was observed; legacy and
  manually entered matches use an honest unknown-duration state.
- Summary, full, AI, interactive HTML, and static HTML exports carry the same
  resume context.
- AI instructions distinguish an interruption-related HR discontinuity from
  uninterrupted fatigue or recovery.
- Existing archives and saved watch state continue to decode without migration
  failures.

## Implementation changes

### Persisted model

- Add a `MatchResumeEvent` value (see *Public interfaces* below) holding
  `resumedAt` and an optional `pausedAt`. **It stores no point index** — see
  *Graph anchor* for why.
- Add `resumeEvents: [MatchResumeEvent]` and `parkedAt: Date?` to `MatchRecord`.
  Follow the CLAUDE.md §4 recipe: memberwise-init parameters defaulting to `[]`
  and `nil`, and `decodeIfPresent(...) ?? default` in the custom `init(from:)`.
  Leave `CodingKeys`/`encode(to:)` synthesized.
- `parkedAt` is the **open** park timestamp: set when the match is parked, cleared
  when it is resumed. A completed record never carries one.
- Keep this data on `MatchRecord`, **never on `PointStat`**. `MatchRecord`'s
  `strippingHealthData()` / `fillingMissingHealthData(from:)`
  (`Models/MatchRecord.swift:180`, `:191`) do `var copy = self` and mutate, so new
  fields survive the iCloud backup round-trip automatically. `PointStat`'s
  equivalents (`Models/PointStat.swift:168`, `:178`) rebuild via a fully-defaulted
  memberwise init, so **any new `PointStat` field is silently dropped from every
  backup with no compiler error**. Resume markers are session metadata, not health
  measurements, so they are not stripped — and because they live on `MatchRecord`,
  nothing needs to change in either function.
- **Do not bump `ManualMatchArchiveBackup.supportedSchemaVersion`** (currently `1`).
  Its `validate(_:)` requires *exact* equality, so a bump would make every
  previously exported archive file un-importable. The archive encodes `MatchRecord`
  directly, and `MatchRecord.init(from:)` already tolerates missing keys, so an
  additive field needs no change there at all.
- WatchConnectivity needs no new wire key: resume events travel inside the
  Codable `MatchRecord` on the existing `MatchSyncKey.singleMatch` payload. They are
  **cumulative state, not deltas**, so a checkpoint dropped while the phone is
  unreachable (`MatchSyncTransport.sendRecord`) loses nothing — the next checkpoint
  or the final record carries the full list.

### Watch lifecycle

Two paths append an event. Both must record a *measured* park.

**Path 1 — resume from history.** `finalizeCurrentMatchToStore()` already writes an
unfinished match to the store when the user taps "End Match"; stamp `parkedAt = Date()`
there when the record is in progress. `resumeMatch(_:)` (`ScoreViewModel.swift:1516`)
then appends an event whose `pausedAt` is the record's stored `parkedAt`, and clears it.

**Path 2 — resume a live match after a gap.** Stamp `parkedAt` when a live match
leaves the screen, and check it when the user comes back:

- App backgrounded — `DeuceMateApp.swift:44-51` already switches on `scenePhase`;
  stamp on `.background` (alongside the existing `saveState()`) and check on `.active`.
- Match sheet dismissed — `HomeView.swift:396` presents `RootModal()` via
  `.sheet(isPresented: $showMatchView)` with no `onDismiss:`. Add one to stamp, and
  clear/check when the sheet is re-presented.
- On return: if `parkedAt` is set and `now - parkedAt >= ResumeMarkers.minimumBreak`,
  append an event and clear `parkedAt`; otherwise just clear it.

Put `minimumBreak` in Core as one named constant (**5 minutes**), following the
`WatchHistory.cap` precedent (`Sync/WatchHistoryCap.swift`) so the watch enforces and
the docs cite a single number.

Carrying the events through the rest of the lifecycle:

- Add `resumeEvents` and `parkedAt` to the watch `AppState` (`ScoreViewModel.swift:479-601`)
  with `decodeIfPresent ?? []` / `?? nil` in its `init(from:)`. **Do not rely on a
  version bump for migration**: `AppState.version` is written (`:1592`) but
  `loadState()` never reads it — back-compat comes purely from `decodeIfPresent` +
  defaults. Bumping the constant to `6` is cosmetic hygiene, not a mechanism.
- `resumeMatch(_:)` must load `record.resumeEvents` into the view model and reset
  `parkedAt`. Otherwise, on the "Replace current match?" flow (`MatchStatsView.swift:190`),
  match A's events leak into match B.
- `resetMatch()` (`:1415`) clears both.
- Automatic state restoration after a kill/relaunch restores existing events. It
  appends a new one only if the parked-at gap exceeds the threshold — that is path 2,
  not a special case.
- A manually entered or legacy in-progress record gets a marker on resume, but its
  `pausedAt` stays `nil` so its duration is never guessed.

> ⚠️ **Both record-construction sites must pass the new fields.**
> `MatchRecord` is built via its memberwise init in two places —
> `finalizeCurrentMatchToStore()` (`ScoreViewModel.swift:1373-1400`) and the live
> checkpoint inside `saveState()` (`:1638-1660`). Because every new parameter has a
> default, **omitting one at either site compiles cleanly and silently loses the
> data.** This has already happened once in this exact function: `finalizeCurrentMatchToStore`
> omits `recentPoints:` and `momentumEnabled:`, so every parked record is stored with
> `recentPoints: []`. Prefer extracting a single private `makeRecord(...)` used by both
> sites, so there is only one place to forget. At minimum, add the test in the
> *Watch behaviour* section that asserts events survive a park → resume → finalize
> round-trip **through `StatsStore`**, not just in memory.
> (The pre-existing `recentPoints` omission is a real bug, but a separate concern —
> file it, don't fold it into this feature's PR.)

### Graph anchor — derived, not persisted

`PointStat` already carries `timestamp: Date` (`Models/PointStat.swift:102`). Together
with `resumedAt`, that **already determines** where a marker sits. Persisting a point
index alongside it would freeze a derived value into an archive schema that must stay
compatible forever, and it would collapse to `0` for every resume when stats tracking
is off.

So: persist timestamps only, and derive the boundary once, in Core.

Add `Stats/ResumeMarkers.swift` (alongside the existing pure-derivation helpers such as
`Stats/SetActivitySplit.swift`) exposing `minimumBreak` and a function mapping
`(events, stats) -> [ResumeMarker]`, where a marker's boundary is the number of points
whose `timestamp <= resumedAt`. Points are chronological, so this handles the leading
edge (`0`), the trailing edge (`stats.count`), and the no-points case cleanly.

The SwiftUI chart, the JS viewer, and the static SVG all consume that one tested
function. The web JSON still **ships the derived index**, so the renderers keep just
painting — the denormalized index lives in the *render contract*, never in the *archive*.
This is the repo's standing rule: derivation stays in tested Swift; the JS only paints.

### Native iPhone graph

- Derive markers via `ResumeMarkers` alongside the existing point, set-band, HR, and
  steps series.
- Draw a distinct dashed vertical `RuleMark` inside `PointsChartCore`
  (`Views/PointsGraphView.swift:448`). It is the single shared chart body used by both
  the inline view (`:1264`) and the fullscreen view (`:1519`), so **one mark covers both
  surfaces**, and it remains visible when HR is off. The dashed selection `RuleMark` at
  `:539-543` is the pattern to copy; set bands (`:505-521`) show the `.annotation` label
  pattern.
- Label a known break `Resumed · <duration>` and an unknown one `Resumed`. Add an
  accessibility description carrying the boundary and duration.
- If multiple events land on one boundary, coalesce the visual rules to avoid overdraw
  while retaining every event in persistence and exports.
- **Points tab / set filters:** show a resume divider row in the point-by-point list, and
  specify its behaviour under an `All / Set N` filter — a boundary outside the selected
  set is not rendered; a boundary at a set edge belongs to the set that *follows* it.
  Leaving this unstated is how the Swift and JS renderers drift apart.

### Text and AI exports

- Add a `Match Interruptions` section listing each event in order with its point
  boundary, resume time, and measured duration or `duration unavailable`.
- Add it in `MatchExporter.dataSections` (`Export/MatchExporter.swift:60`) — the single
  funnel through which summary, full, **and** AI-prompt exports all flow, so one
  `sections.append` reaches all three. Slot it after `setBySetScores` (`:130`); both are
  match-timeline facts, and it lands before the raw point table.
- Interruptions are a property of the recording session, not of either player, so the
  section is perspective-neutral — unlike the HR/PulseCoach/Movement block, which is
  gated `focal == .me` (`:118-128`).
- Extend the coaching instructions to compare pre-resume and post-resume performance
  where enough data exists, and to treat an HR change at a resume boundary as an
  interruption effect rather than evidence of continuous-match fatigue or recovery.
- Emit nothing for matches with no resume events.

### Interactive and static HTML exports

- Add a top-level `interruptions` block to `MatchWebViewModel` carrying the
  Core-derived point boundary, ISO resume time, optional duration in seconds, and a
  Swift-derived display label. Bump `MatchWebViewModel.currentSchemaVersion` from **6**
  to **7** (`WebExport/MatchWebViewModel.swift:23`).
- Render the dashed rules and labels in the interactive SVG chart. Both renderers already
  compute identical `xAt(i)` / `step` geometry (`MatchWebStaticFallback.swift:286`,
  `MatchWebTemplate.swift:430`), and set bands already do the `± step/2` between-points
  math in both, so a rule between points *i* and *i+1* is `xAt(i) + step/2`. The JS
  already draws a dashed full-height selection line (`MatchWebTemplate.swift:501-505`) —
  copy it. The static fallback has no vertical-line precedent but already has `lineSVG`.
- Mirror the geometry in `MatchWebStaticFallback` so Quick Look and other no-JavaScript
  previews stay truthful and visually consistent.
- Preserve the offline/self-contained guarantee: resume rendering adds no external
  resources and no network calls.

### Documentation

- Update `CLAUDE.md` and `docs/architecture/file-inventory.md` for the new `MatchRecord`
  metadata, the new `Stats/ResumeMarkers.swift`, the web schema version, and current
  file sizes.
- Update `docs/features/INTERACTIVE_HTML_EXPORT_PLAN.md` to make resume-marker parity
  part of the interactive/static renderer contract.
- Update `docs/USER_GUIDE.md` to explain graph markers, measured-versus-unknown break
  duration, and how AI analysis treats interrupted sessions.

## Public interfaces and data contracts

```swift
public struct MatchResumeEvent: Codable, Equatable, Sendable {
    /// When play resumed. Always observed.
    public let resumedAt: Date
    /// When the match was parked. `nil` for legacy and manually entered records,
    /// whose park was never observed.
    public let pausedAt: Date?

    /// Measured break length. `nil` when the park was not observed. Never inferred.
    public var duration: TimeInterval? {
        guard let pausedAt else { return nil }
        let seconds = resumedAt.timeIntervalSince(pausedAt)
        return seconds >= 0 ? seconds : nil
    }
}

public struct MatchRecord: Codable, Identifiable, Equatable, Sendable {
    // Existing fields remain unchanged.
    public var resumeEvents: [MatchResumeEvent]
    /// Open park timestamp: set while parked, cleared on resume. Never set on a
    /// completed record.
    public var parkedAt: Date?
}
```

`duration` is defined **once, on the struct**, so the four renderers (iOS graph, text
export, interactive HTML, static HTML) cannot diverge on the rule.

Renderers must not infer a duration from point timestamps, heart-rate samples, or match
wall-clock time. They may, and do, use point timestamps to derive the *boundary* — that
is `ResumeMarkers`' job, and only its job.

The web-export JSON adds a top-level `interruptions` collection (carrying the derived
boundary index) and moves to schema version 7. Old persisted `MatchRecord` JSON stays
valid and decodes with no resume events.

## Test plan

### Core and persistence

- Round-trip one and multiple resume events, including an open `parkedAt`.
- Decode legacy `MatchRecord` JSON with neither new key; assert `[]` / `nil`.
- `MatchResumeEvent.duration`: known break, absent `pausedAt`, and a negative interval
  (clock skew) → `nil`.
- `ResumeMarkers` boundary derivation: leading edge, trailing edge, mid-match, empty
  stats, and two events sharing a boundary.
- Health stripping and backfilling preserve resume metadata (satisfied by construction —
  assert it anyway, so a future refactor of `strippingHealthData()` to a memberwise
  rebuild is caught).
- Manual-archive and WatchConnectivity record round trips retain events, and the manual
  archive's `schemaVersion` stays `1`.

### Watch behaviour

- Parking an unfinished match stores a park timestamp.
- **Path 1:** explicit resume from history appends an event and preserves the prior park
  timestamp.
- **Path 2:** backgrounding a live match and returning after more than `minimumBreak`
  appends an event with a measured duration; returning *under* the threshold appends
  none. Same for dismissing and re-presenting the match sheet.
- Multiple park/resume cycles remain ordered and survive finalization.
- Manual and legacy resumes record an event with unknown duration.
- Park → resume → finalize, then **read the record back from `StatsStore`** and assert the
  events survived. (This is the assertion that would have caught the `recentPoints` bug.)
- Live checkpoints contain completed events and no stale open park timestamp.
- Watch `AppState` round-trip preserves events; state saved by an older build defaults to
  an empty list.
- Replacing a different live match parks that match before resuming the selected one,
  without mixing their event histories.

### Exports and rendering

- Summary, full, and AI exports include ordered interruption details only for interrupted
  matches, and preserve correct focal-player physiology wording.
- AI output contains the pre/post-session and HR-discontinuity guidance.
- Web JSON schema 7 represents known and unknown durations correctly. **Bump the
  hard-coded assertion at `MatchWebExportTests.swift:189`** (`XCTAssertEqual(vm.schemaVersion, 6)`).
- Interactive and static HTML contain resume rules and labels, including leading/trailing
  boundaries and multiple events.
- Existing script-safety, no-external-resources, and offline HTML invariants still pass.
- Manually inspect the inline, fullscreen, browser-interactive, and Quick Look/static
  charts with HR enabled and with more than one resume.

> Note: `ArchiveBackupPolicyTests.swift:206` builds its point-level expectation by calling
> the function under test, so it would not catch a dropped `PointStat` field. Nothing here
> touches `PointStat`, but don't trust that test further than it goes.

### Verification commands

Run from the repository root. (The `cd` is scoped to the package command — do not let it
leak into the `xcodebuild -project` invocations, whose paths are root-relative.)

```bash
# Shared package — where the ResumeMarkers and coding tests belong.
cd DeuceMate/Packages/DeuceMateCore && \
  xcodebuild test -scheme DeuceMateCore \
  -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO

# Watch app tests
xcodebuild test -project DeuceMate/DeuceMate.xcodeproj \
  -scheme "DeuceMate Watch App" \
  -destination "platform=watchOS Simulator,name=Apple Watch Series 9 (45mm),OS=latest"

# iPhone unit + UI tests
xcodebuild test -project DeuceMate/DeuceMate.xcodeproj \
  -scheme "DeuceMate" \
  -destination "platform=iOS Simulator,name=iPhone 15,OS=latest"
```

## Assumptions and fixed decisions

- A resume is any return to play across a **measured** break: either an explicit resume
  from history, or a return to a live match after a gap of at least
  `ResumeMarkers.minimumBreak` (5 minutes). Both endpoints of the break are observed.
- The threshold exists only to suppress noise (a brief glance at the watch face). It is
  not an inference: the interval itself is measured, not guessed.
- Break duration is the park-to-resume interval. It is optional, and is never inferred for
  legacy or manually entered records.
- Every measured break is retained; no single-resume limitation is imposed.
- Existing matches remain unchanged and show no marker until interrupted after this ships.
- Resume markers are match/session metadata, not HealthKit measurements, so they remain in
  normal sync and archive payloads even where health data is stripped.

## Out of scope

- Inferring interruptions from long gaps between points or from heart-rate samples.
- Treating changeovers or medical timeouts as resumes.
- Recording a marker for an app relaunch or state restoration that happens **within** the
  threshold — a crash-and-relaunch mid-game is not a break.
- Retrofitting resume markers into historical completed matches.
- Changing scoring or HealthKit sampling.
- **Fixing `matchElapsedSeconds` on the live-resume path.** Today `sessionStartTime` is
  reset only on resume-from-history (`ScoreViewModel.swift:1555`), so put-the-watch-down
  idle time is still counted as *active play* when the user returns to a live match.
  Stamping `parkedAt` (path 2) finally makes that fixable — but it is a behaviour change to
  a long-standing number, and belongs in its own PR. Follow-up.

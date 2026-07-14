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
  watch_app_state: version-bump-required
  web_export: 6-to-7
decisions:
  resume_definition: explicit-user-resume-only
  interruption_detail: marker-and-measured-duration
  export_scope: all-exports
  infer_legacy_breaks: false
---

# Match Resume Markers and Export Context

## Summary

Persist every deliberate Resume-from-history event and display it as a visible
session boundary. Each event records where play resumed, when it resumed, and
the parked duration when known. Automatic watch-app relaunches do not create
resume events.

This makes a post-resume heart-rate change visually explainable and gives text,
HTML, and AI exports an explicit interruption signal instead of forcing a user
or model to infer one from gaps or physiological data.

## Success criteria

- Every explicit match resume is retained, including multiple resumes in one
  match.
- The iPhone points graph clearly marks each resume boundary whether or not its
  heart-rate overlay is enabled.
- A measured parked duration is shown when the watch recorded the prior park;
  legacy and manually entered matches use an honest unknown-duration state.
- Summary, full, AI, interactive HTML, and static HTML exports carry the same
  resume context.
- AI instructions distinguish an interruption-related HR discontinuity from
  uninterrupted fatigue or recovery.
- Existing archives and saved watch state continue to decode without migration
  failures.

## Implementation changes

### Persisted model and watch lifecycle

- Add a backward-compatible `MatchResumeEvent` value containing
  `afterPointCount`, `resumedAt`, and optional `pausedAt`.
- Add `resumeEvents: [MatchResumeEvent]` and `parkedAt: Date?` to `MatchRecord`.
  The memberwise initializer supplies `[]` and `nil` defaults, and the custom
  decoder uses `decodeIfPresent` with the same defaults.
- When an unfinished match is explicitly parked, store the park timestamp in
  `parkedAt`. Completed records do not carry an open park timestamp.
- In `resumeMatch`, append an event at `record.stats.count`, using the record's
  `parkedAt` when available, then clear the open park state in subsequent live
  checkpoints.
- Treat a manually entered or legacy in-progress record identically for the
  marker, but leave `pausedAt` nil so its duration is not guessed.
- Carry historical resume events through live checkpoints, final records, and
  reset/replace flows. Add them to the watch `AppState`, bump its version, and
  default older state to an empty list.
- Automatic state restoration after an app kill/relaunch restores existing
  events but never appends a new one.
- Rely on the existing `MatchRecord` Codable sync and archive paths so the new
  metadata travels through WatchConnectivity and manual backups. Confirm that
  health stripping/backfilling retains it unchanged.

### Native iPhone graph

- Derive resume markers alongside the existing point, set-band, HR, and steps
  series. A marker sits at the boundary after `afterPointCount` recorded points,
  rather than being attached ambiguously to the next point.
- Draw a distinct dashed vertical rule in the shared primary chart, so it is
  visible in both inline and expanded views and remains present when HR is off.
- Label a known break as `Resumed · <duration>` and an unknown break as
  `Resumed`. Add an accessibility description with the boundary and duration.
- If multiple events share a point boundary, coalesce their visual rules to
  avoid overdraw while retaining every event in persistence and exports.

### Text and AI exports

- Add a `Match Interruptions` section after the match overview whenever resume
  events exist. List each event in order with its point boundary, resume time,
  and measured duration or `duration unavailable`.
- Include this section in summary, full, and AI-prompt exports for both player
  perspectives.
- Extend the coaching instructions to compare pre-resume and post-resume
  performance where enough data exists and to treat an HR change at a resume
  boundary as an interruption effect, not evidence of continuous-match fatigue
  or recovery.
- Do not add an interruption section to matches with no explicit resume events.

### Interactive and static HTML exports

- Add a top-level resume-event view model containing the point boundary,
  ISO resume time, optional duration in seconds, and a Swift-derived display
  label. Bump `MatchWebViewModel.currentSchemaVersion` from 6 to 7.
- Render the same dashed rules and labels in the interactive SVG chart. Convert
  an after-point count into the geometric boundary between the surrounding
  points, with sensible leading/trailing-edge handling.
- Mirror the marker geometry in `MatchWebStaticFallback` so Quick Look and other
  no-JavaScript previews remain truthful and visually consistent.
- Preserve the export's offline/self-contained guarantees; resume rendering
  introduces no resources or network calls.

### Documentation

- Update `CLAUDE.md` and `docs/architecture/file-inventory.md` for the new
  `MatchRecord` metadata, web schema version, graph/export behavior, and current
  file sizes.
- Update `docs/features/INTERACTIVE_HTML_EXPORT_PLAN.md` to make resume-marker
  parity part of the interactive/static renderer contract.
- Update `docs/USER_GUIDE.md` to explain graph markers, measured-versus-unknown
  break duration, and how AI analysis treats interrupted sessions.

## Public interfaces and data contracts

```swift
public struct MatchResumeEvent: Codable, Equatable, Sendable {
    public let afterPointCount: Int
    public let resumedAt: Date
    public let pausedAt: Date?
}

public struct MatchRecord: Codable, Identifiable, Equatable, Sendable {
    // Existing fields remain unchanged.
    public var resumeEvents: [MatchResumeEvent]
    public var parkedAt: Date?
}
```

`MatchResumeEvent` duration is derived as `resumedAt - pausedAt` only when
`pausedAt` exists and the interval is non-negative. Renderers must not infer a
duration from point timestamps, heart-rate samples, or match wall-clock time.

The web-export JSON adds a top-level resume-event collection and changes its
schema version to 7. Old persisted `MatchRecord` JSON remains valid and decodes
with no resume events.

## Test plan

### Core and persistence

- Round-trip one and multiple resume events, including an open `parkedAt`.
- Decode legacy `MatchRecord` JSON without either new key and assert `[]`/`nil`.
- Verify health-data stripping and backfilling preserve resume metadata.
- Verify manual archive and WatchConnectivity record round trips retain events.

### Watch behavior

- Parking an unfinished match stores a park timestamp.
- Explicit resume appends the correct point boundary and preserves the prior
  park timestamp.
- Multiple park/resume cycles remain ordered and survive finalization.
- Manual and legacy resumes record an event with unknown duration.
- Live checkpoints contain completed events and no stale open park timestamp.
- Watch `AppState` round-trip preserves events; older versions default empty.
- Automatic state restoration adds no resume event.
- Replacing a different live match parks that match before resuming the selected
  one, without mixing their event histories.

### Exports and rendering

- Summary, full, and AI exports include ordered interruption details only for
  resumed matches and preserve correct focal-player physiology wording.
- AI output contains the pre/post-session and HR-discontinuity guidance.
- Web JSON schema 7 represents known and unknown durations correctly.
- Interactive and static HTML contain resume rules and labels, including
  leading/trailing boundaries and multiple events.
- Existing script-safety, no-external-resources, and offline HTML invariants
  continue to pass.
- Manually inspect inline, fullscreen, browser-interactive, and Quick Look/static
  charts with HR enabled and with more than one resume.

### Verification commands

```bash
cd DeuceMate/Packages/DeuceMateCore
swift test

xcodebuild test -project DeuceMate/DeuceMate.xcodeproj \
  -scheme "DeuceMate Watch App" \
  -destination "platform=watchOS Simulator,name=Apple Watch Series 9 (45mm),OS=latest"

xcodebuild test -project DeuceMate/DeuceMate.xcodeproj \
  -scheme "DeuceMate" \
  -destination "platform=iOS Simulator,name=iPhone 15,OS=latest"
```

## Assumptions and fixed decisions

- A resume means the user explicitly chooses to resume a match from history,
  including a manually entered in-progress match received by the watch.
- Watch app relaunches and automatic live-state restoration are out of scope as
  resume events.
- Break duration is the explicit park-to-resume interval. It is optional and is
  never inferred for old or manual records.
- Every explicit resume is retained; no single-resume limitation is imposed.
- Existing matches remain unchanged and show no marker until explicitly resumed
  after this feature ships.
- Resume markers are match/session metadata, not HealthKit measurements, so they
  remain in normal sync and archive payloads even where health data is stripped.

## Out of scope

- Inferring interruptions from long gaps between points or heart-rate samples.
- Treating changeovers, medical timeouts, or app relaunches as resumes without an
  explicit Resume action.
- Retrofitting reliable resume markers into historical completed matches.
- Changing scoring, elapsed-active-play calculations, or HealthKit sampling.

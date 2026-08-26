# File Inventory — every file, what it does, which feature it serves

This is the **complete list of production source files** in DeuceMate, in plain
English. It exists as a review guardrail:

- **A file not listed here should not exist.** If a pull request adds a file
  without adding it here (with a purpose you recognise), question it.
- **A file whose entry doesn't match what you asked for** is equally suspect.

> **Maintenance contract:** any PR that adds, removes, renames, or repurposes a
> source file must update this inventory in the same PR (see
> [README.md](README.md) and `CLAUDE.md`).

Line counts are approximate (rounded; they drift with normal edits and only matter
as a size signal — a "small helper" that is suddenly 800 lines deserves a look).

---

## 1. Apple Watch app — `DeuceMate/DeuceMate Watch App/` (14 files)

The scorer. Everything about running a live match happens here.

| File | ~Lines | What it does | Feature(s) |
|---|---:|---|---|
| `ScoreViewModel.swift` | 1,940 | The live-match brain. Holds the current score, serve rotation, undo, tiebreak and changeover state; applies the shared scoring rules; manages match start/end, saving, resuming after a crash; holds every synced setting; validates and applies score commands arriving from the phone; seeds/persists the remembered match setup (format + singles/doubles). The single most consequential file in the repo. | Live scoring, settings, sync, compass changeover, Pulse Coach settings, match setup |
| `ContentView.swift` | 940 | The live scoreboard screen: score display, swipe gestures (up/down = point, left = undo, right = stats), momentum strip, changeover prompts and compass indicator. | Live scoring, compass changeover |
| `HomeView.swift` | 959 | The start screen and pre-match setup flow: a pre-match card states the remembered Singles/Doubles + format setup (hidden mid-match) and taps through to a combined Match Setup sheet, so Start Match skips straight to who-serves-first; the same card shows the Points/Health/Pulse tracking strip; also handles player names, court-end confirmation for the compass feature, and Past Matches/Settings/Guide as an icon row. | Match setup, tracking status |
| `TrackingStatusStrip.swift` | ~140 | Paints Core's `MatchTrackingStatus`: the two-or-three-chip Points/Health/Pulse strip on the start screen (single-line icon + state per chip; taps to Settings; Pulse collapses out when Health is off) and the always-three full-width row form used inside Settings. `Live*` wrappers take only the view model — `ScoreViewModel` forwards `WorkoutManager.$healthAccess` (not its whole `objectWillChange`, which also ticks with live HR/calories) into its own, so no separate `@ObservedObject var workoutManager` is needed. | Tracking status |
| `MatchStatsView.swift` | 630 | On-watch statistics screen shown during/after a match: serve, return, break points, errors, rally depth, heart-rate zones; set and player filters. | Stats |
| `PointCategorySheet.swift` | 260 | The slide-up sheet after each point (when outcome tracking is on): pick how the point ended — winner, forced/unforced error, double fault — then the ending shot. | Point categorisation |
| `MatchHistoryView.swift` | 220 | The watch's recent-matches list (newest 25): open stats, resume an in-progress match, swipe to delete. | Match history |
| `AppTheme.swift` | 220 | The watch's five court-inspired colour themes; the chosen theme syncs to the phone. | Theming |
| `WorkoutManager.swift` | ~200 | Runs the HealthKit workout session during a match: live heart rate, calories, steps, distance per set. Also publishes `healthAccess` (the workout share permission, mapped onto Core's `HealthAccess`) so the start screen can say whether the next match will record health data; refreshed after authorization and on foreground. | Health/workout tracking, tracking status |
| `Sync/WatchMatchSyncService.swift` | 290 | The watch's end of the watch↔phone bridge: sends match checkpoints, full history, manifests and announcements; receives settings, score commands and delete commands from the phone. | Sync |
| `StatsStore.swift` | ~120 | Saves backup-excluded match history to a JSON file on the watch; trims to the newest 25 matches; thread-safe. Distinguishes a genuinely-empty archive from an unreadable/corrupt one and refuses to overwrite (or broadcast) the latter, so a transient read failure can't erase stored matches. | Match history (persistence) |
| `BackupExcludedFileWriter.swift` | ~30 | Shared watch helper for atomic Class B JSON writes that reapplies and verifies device-backup exclusion. Used by match history and transient live-match state. | Match history, live state, health/privacy |
| `DeuceMateApp.swift` | 58 | The watch app's entry point: wires up the scoring engine, workout manager and sync service; restores an in-progress match on launch; refreshes Health access on foreground. | App plumbing |
| `MatchStats.swift` | 50 | Small compatibility shim: re-exports shared types under old names, plus watch-only display labels and colours for match formats and point outcomes. | App plumbing, theming |

## 2. iPhone app — `DeuceMate/DeuceMate/` (24 files)

The viewer and the permanent archive. It displays, announces, analyses and exports
matches; it does not score them (except by sending validated commands to the watch).

| File | ~Lines | What it does | Feature(s) |
|---|---:|---|---|
| `Views/PointsGraphView.swift` | 1,870 | The interactive match chart: points momentum over time with counted Me/Opp filters for outcomes, serving categories and ending shots, plus optional heart-rate and steps overlays; pinch-zoom, fullscreen, touch-to-inspect. Its selection summary shows the same pre-point full match score, game score, serving side, and set-relative point number as the Points tab. | Stats & graphs |
| `Views/MatchDetailView.swift` | ~1,160 | One match's detail page: score summary, stats tabs, the graph, coaching sections, storage-location and iCloud badges, and the export / AI-coach actions — including "Share Interactive Web Page", a self-contained `.html` file (built off-thread, shared via the system share sheet) the opponent can open in any browser. Text/HTML share actions **and the AI Coach hand-off** route through one per-export HealthKit disclosure (`HealthExportConsent`, Blocker 4): a shared "Share health data?" alert (via `PendingHealthDisclosure`) when the match carries health data — Share → `UIActivityViewController` (`ShareSheet`), Continue → the AI Coach sheet; health-free matches proceed directly. Its Points tab rows show the full pre-point match score and serving side with a combined accessibility label. | Stats, AI export, web export, archive, health/privacy |
| `Views/PastMatchesView.swift` | ~751 | The archive list: all matches newest-first, live-match row, badges showing whether a match lives on the watch, the phone, or both; swipe-to-delete; pull a watch-only match to the phone; free up watch space. Set scores use Core's canonical formatter. Permanent deletion is confirmed by a single screen-level dialog rendered from a `PendingDelete` snapshot — never anchored inside a row, whose teardown when a swipe closes would dismiss it — and full-swipe stays reserved for the recoverable "Remove from Watch". Hosts the Trends section above Live Match / Past Matches (TECHNICAL_DEBT #13's "next substantial edit" — the file grew ~6 lines, all new content lives in `Views/Trends/`). | Archive, sync, Trends |
| `Views/Trends/TrendsSection.swift` | 135 | The "Trends" section on the archive screen: four headline sparklines (Double Faults, Unforced Errors, Winners, W:UE Ratio) wrapped in a single `NavigationLink` into the full screen — any tap on the card navigates, the system's chevron the only affordance — or a "needs N more tracked matches" line below `PerformanceTrends.minimumMatches` rather than hiding, a deliberate departure from the hide-when-empty idiom so a new user discovers the feature. Scopes the headline to completed matches only (`TrendFilter()`'s default), matching the full screen's own default, but the thin-data line stays a live `NavigationLink` (not just static text) when including the in-progress match would itself clear the minimum — otherwise the one control that could fix that (the full screen's "Include In-Progress Matches" toggle) would be unreachable. Reads `store.history` directly, not `PastMatchesView`'s `pastRecords`, since watch-mirror rows may carry no `stats`. | Trends |
| `Views/Trends/TrendsSamples.swift` | 40 | Caches the derivation of `MatchTrendSample`s from the archive so `MatchStatsSummary`'s ~30-filter-pass init runs once per match, not once per render; recomputes only when the full `[MatchRecord]` array actually differs by equality (not a hand-picked field subset, after a Codex-caught bug where an (id, endTime, iWon, count) fingerprint missed a Backup & Transfer import replacing a record's content in place). | Trends |
| `Views/Trends/TrendsView.swift` | 190 | The full Trends screen, pushed onto the archive's existing `NavigationStack`: window (Last 5/10/20/All) / Singles-Doubles / format filters, an "Include In-Progress Matches" toggle (off by default), and a Rate/Count toggle — four phone-local, unsynced `@AppStorage` keys (CLAUDE.md §0) — then one grouped `TrendChart` per `TrendMetricGroup` in a fixed display order (Errors, Serve & Return, Attack, Rally Depth, Pressure). Re-enforces `PerformanceTrends.minimumMatches` after filtering (not just on an empty result), and surfaces a caption naming how many matches in the current scoped window had `trackingCoverage` below 1.0 rather than silently averaging partial tracking in. Builds `dateByIndex` (index -> match date) from the full `scopedSamples` list, not from any one `TrendChart`'s own series, and passes it down — the source of truth every group's chart needs so an index with zero plottable data anywhere in that group still has a date for its axis label and selection readout. | Trends |
| `Views/Trends/TrendChart.swift` | 646 | One metric group's chart. Errors/Attack/Pressure share a multi-line `Chart` with a toggleable legend (`foregroundStyle(by:)` + `chartForegroundStyleScale(domain:range:)` — a literal per-mark colour merges every metric's points into one connected line with no series discriminator to split them); Serve & Return uses the same chart shape narrowed by a persisted Serves In/Serves Win/Returns Win filter to 2 of its 6 metrics at a time; Rally Depth gets a Mix/Win Rate toggle between a normalized stacked `AreaMark` and a win-rate line chart (normalized stacking reports its Y-axis already in percentage units, unlike every other chart here). Opponent-framed metrics (`doubleFaultsConceded`, `unforcedErrorsDrawn`, `forcedErrorsCaused`, `winnersConceded`) start hidden and render dashed on their paired metric's hue when shown. All three chart shapes here (`lineMarks(for:)`, shared by the standard groups and Rally Depth's win-rate chart; and `areaMarks(for:)`, Rally Depth's Mix chart) split each metric into runs of consecutive match indices, each run its own internal Chart discriminator — omitting a missing match's mark entirely (the prior approach) left Swift Charts connecting or stacking across it, implying a genuine coverage gap (a zero-UE match's W:UE, a legacy match's rally-depth data with no ending-shot record) as continuous data. All three charts also pin `.chartXScale(domain: chartXDomain)` to the full `0...sampleCount-1` window, since Swift Charts otherwise infers a chart's X-axis domain from whichever indices its marks actually cover — leaving a match at either EDGE with no data for any visible series (the newest match having no ending-shot data, say) shrinking the domain and stretching the nearest real match to that edge, same bug as the sparklines' `sampleCount`, recurring here because run-splitting alone only stops the CONNECTING, not the axis inference. Every chart also carries a tap/drag `.chartXSelection(value: $selectedIndex)` with a dashed `RuleMark` and a `selectionSummary(for:)` readout row (date + each visible metric's value at that match) below it — the axis-label-and-selection-readout design `PERFORMANCE_TRENDS_PLAN.md` §6.3 specified from the start but was never wired up until this fix; `dateByIndex` is passed in from `TrendsView`'s full scoped sample list (not derived from `series` here), so an index with zero plottable data across the WHOLE group — every Rally Depth share metric gapping the same ending-shot-less match, say — still has a date, and the selection binding clamps to `chartXDomain` (mirroring `PointsGraphView.applyXSelection`) so a drag past either plot edge can't leave `selectedIndex` stuck on an out-of-range value. | Trends |
| `Views/Trends/TrendSparkline.swift` | 217 | A compact per-metric row — label, pooled figure, tiny line chart, delta arrow/chip — used by `TrendsSection` and for `TrendChart`'s ratio-unit metrics (currently only W:UE, which can't share a percent-scaled axis with the rest of Attack). The delta arrow points by the metric's raw movement (`TrendDelta.change`'s sign), independent of the improving/declining colour, so a falling rate always points down regardless of whether falling is good or bad for that metric. `SparklineShape` positions each point by its real `TrendPoint.index` against the caller-supplied `sampleCount` (the full scoped window, not just the min/max index this one metric happens to have values for) and breaks its path at any non-consecutive pair, so a metric missing a match anywhere — including at either edge of the window — doesn't get silently re-spaced as if that match never existed. Hosts the shared `TrendMetric.format(_:)`/`.formatCount(_:)` display-string extensions every Trends view calls. | Trends |
| `Views/LiveScoreboardView.swift` | 490 | Full-screen landscape scoreboard for spectators, fed live from the watch. With "iPhone Input" on, swipes here send score commands to the watch. | Live scoreboard, iPhone input |
| `Views/SettingsView.swift` | 819 | Settings screen: Watch sync status/counts and fresh-Watch restore guidance, announcements, theme, outcome tracking, changeover compass, heart-rate settings, player name, skill level (NTRP), manual archive export/import, iCloud backup, About (version + tappable privacy-policy / support / contact links). | Settings, manual archive backup |
| `Views/ManualMatchEntryView.swift` | 440 | Form to reconstruct a match by hand (paper scorecard, watch mishap); the result is saved into the phone archive and a copy is sent to the watch so it can be resumed there. | Manual entry |
| `Views/PulseCoach/PulseCoachSection.swift` | 430 | "Pulse Coach" panel on the match page: heart-rate-based observations (performance by HR zone, pressure response, late-match fatigue). | Pulse Coach |
| `Views/LivePointCategoryPanel.swift` | 220 | Phone-side twin of the watch's point-categorisation sheet, shown under the live scoreboard so a spectator can tag the point. | Point categorisation, iPhone input |
| `Views/AICoachSheet.swift` | 200 | The export chooser: summary vs. full vs. AI coaching prompt, my/opponent perspective, copy to clipboard, hand off to an AI app. | AI export |
| `Views/AICoachLauncher.swift` | 120 | Detects which AI chat apps are installed (ChatGPT, Claude, Gemini, Perplexity, Copilot, Poe, Grok) and opens one with the coaching prompt; falls back to clipboard + share sheet. | AI export |
| `Views/Coaching/RecCoachSection.swift` | 60 | "Rec Coach" panel: up to three plain-English coaching observations derived from point stats (rules live in the shared package). | Rec Coach |
| `Export/MatchExporter.swift` | 640 | Builds the export text: match summary, full point-by-point report, or an AI coaching prompt tuned to the player's skill level. Set scores use Core's canonical formatter. | AI export |
| `Sync/PhoneMatchSyncService.swift` | 600 | The phone's end of the watch↔phone bridge: receives checkpoints/history/manifests, treats the manifest (including empty) as a full-sync acknowledgement, tracks live Watch installation/reachability, and sends settings and (when allowed) score and categorisation commands to the watch. | Sync, live scoreboard |
| `Persistence/PhoneStatsStore.swift` | ~830 | The permanent archive store. Full records are reconstructed in memory from a normally backed-up, health-stripped history plus a backup-excluded Health sidecar; tombstones remain separate. It migrates legacy full-fidelity history, degrades safely when the sidecar is unavailable, and keeps existing one-time iCloud restore/push behavior. | Archive, health/privacy, iCloud backup, manual archive backup |
| `AppTheme.swift` | 220 | The phone's copy of the five colour themes, kept in step with the watch via settings sync. | Theming |
| `Audio/LiveAnnouncementService.swift` | 130 | Speaks the score through the iPhone speaker (umpire-style), foreground-only by design — no background audio tricks. | Announcements |
| `HealthKitHRFetcher.swift` | 180 | Fetches heart-rate samples from HealthKit for a finished match and buckets them per point for the graph overlay. | Stats & graphs, health |
| `DeuceMateApp.swift` | 50 | The iPhone app's entry point: wires up the archive store, sync service and announcer; resumes initial restore or backup push whenever the app returns to the foreground. | App plumbing |
| `ContentView.swift` | 15 | The navigation root — essentially just opens the archive list. | App plumbing |

## 3. Shared package — `DeuceMate/Packages/DeuceMateCore/Sources/DeuceMateCore/` (47 files)

The rulebook both apps use. No screens; pure logic — which makes it the cheapest
place to test and the safest place to change.

| File | ~Lines | What it does | Feature(s) |
|---|---:|---|---|
| `Scoring/ScoringEngine.swift` | 567 | The tennis rules, as a pure function: given a state and "player X won the point", returns the new state plus events (game/set won, changeover due, announcement text). It also exposes the perspective-neutral regular-game completion predicate used by historical point-score reconciliation. No side effects — fully unit-testable. | Live scoring, stats |
| `Stats/MatchStatsSummary.swift` | 455 | The statistics math: serve/return percentages, break points, error counts, winner-to-error ratio (typed `RatioStat`, TECHNICAL_DEBT #7), pressure-point performance, rally depth, HR-zone splits, per-point step deltas + movement timeline, and categorized-only won/lost/service-point totals for cross-match trend metrics. Both apps display numbers computed here, so they can never disagree. | Stats |
| `Stats/MatchTrendSample.swift` | 223 | One eligible match reduced to the raw counters cross-match trends pool and window — a recorder-framed rename of a single `MatchStatsSummary(focal: .me)` (never a second, duplicated counting pass). A failable `init?(record:)` owns eligibility: an in-progress match is eligible once it clears the categorized-points threshold (its `isInProgress` flag tells it apart from a completed draw), formats with `disablesPointTracking` (Perpetual Points) are excluded, and matches need at least 20 categorized points. | Trends |
| `Stats/TrendMetric.swift` | 278 | The cross-match metric catalogue: double faults, unforced/forced errors (both directions), winners, W:UE ratio, rally-depth share/win-rate per `EndingShot`, serve/return percentages, and pressure conversions. `rawPair(in:)` (unguarded, for pooling) vs. `ratio(in:)` (denominator-guarded, for plotting a single dot) is the split that keeps a zero-UE match's winners from being discarded when pooled. | Trends |
| `Stats/PerformanceTrends.swift` | 236 | Windows, filters (type/format applied before the window, plus an opt-in `includeInProgress` axis — completed matches only by default), pools (Σnumerator/Σdenominator, not a mean of per-match rates), and diffs (`TrendDelta`, oriented by the metric's `betterDirection` so a falling double-fault rate is always `.improving`) a whole archive of `MatchTrendSample`s into per-metric `TrendSeries`. | Trends |
| `Stats/RecCoachInsights.swift` | 310 | The Rec Coach rule set: eight coaching rules (e.g. self-inflicted losses, double-fault leakage, pressure-point drop-off) that fire from point stats and rank the top observations. | Rec Coach |
| `Stats/PulseCoachInsights.swift` | 125 | The Pulse Coach rule set: three heart-rate rules (zone-vs-results delta, break-point HR spike, late-match decline). | Pulse Coach |
| `Stats/StepsCoachInsights.swift` | 95 | The steps movement/fatigue rule set: two rules (accumulated-step late-match decline, high-movement-point win rate) over the `MatchStatsSummary.StepPoint` timeline. Recorder-only; surfaced in the AI/stats export's Movement & Fatigue section. | Stats, health |
| `Stats/StepsSeries.swift` | 75 | Single source of truth for the steps **overlay** series shared by the iOS Points Graph and the HTML export: original 0-based point indices, base-normalized cumulative (starts at 0), per-point deltas, and the legacy `totalSteps` linear-estimate fallback. Distinct from `MatchStatsSummary`'s chronological insights timeline. | Stats, health |
| `Stats/SetActivitySplit.swift` | 115 | Per-set breakdowns (duration, points, games) used by the set filters in stats views. | Stats |
| `Stats/PointGamesScore.swift` | 115 | Internal building block for `PointMatchScore`: derives the running Me–Opponent games score within one set from `PointStat.gameScoreAtStart` resets, including safe reconciliation of a game won by the final tracked point. Reconciliation proves that point actually completed a regular game/tiebreak before crediting it, and suppresses suffix-only histories rather than mislabelling them. | Stats, Web export |
| `Stats/SetScoreLabel.swift` | 75 | Canonical recorder/opponent-oriented formatter for regular sets, in-set tiebreaks, and tiebreak-only sets; also owns the shared server-relative-snapshot → recorder-oriented `GameScoreLabel` used by iOS and web point displays. | Stats, archive, exports |
| `Stats/SetFilter.swift` | 50 | The "All / per-set" scope both stats screens and the web export slice a match by, including the label rule (a deciding super-tiebreak reads "TB") in long (`Set 2`) and watch-width short (`S2`) forms. | Stats, Web export |
| `Stats/MatchDurations.swift` | 55 | Canonical set/match duration resolution — the recorded value first, then the span between the set's first and last tracked point — plus the minute and live minute-second strings every surface renders. | Stats, exports |
| `Stats/StatFormatting.swift` | 60 | The count/ratio/percent strings the stats screens and both exports print (`76 (54%)`, `3/8 (38%)`), keeping the deliberate truncate-in-exports vs. round-in-headers distinction in one place; `RatioDisplay` resolves one comparison-row side into bar fraction, percent text and count label. | Stats, exports |
| `Stats/CompactScoreLine.swift` | 60 | The narrow hyphen-separated score line the watch renders where `SetScoreLabel`'s en-dashed form will not fit: completed sets, tiebreak parentheticals and the in-progress line with the live game score. | Stats (watch) |
| `Stats/PointMatchScore.swift` | 114 | Derives a typed full match-score snapshot immediately before every tracked point: authoritative prior sets plus the live games/tiebreak-points segment, with graceful omission for legacy or suffix-only histories. Shared by the iOS Points tab, graph selection summary, and HTML Points tab. | Stats, graphs, Web export |
| `Stats/HRZone.swift` | ~95 | Heart-rate zone maths: zones 1–5 from a max heart rate (age-derived or manually overridden). `isUsableBirthYear` exposes the same acceptance test `resolveMaxHR` uses internally, so the tracking-status UI can tell "calibrated" from "running on the 190 bpm default" without comparing against 190 (also a legitimate age-derived result, age 30). | Pulse Coach, health, tracking status |
| `Models/ScoreTypes.swift` | 185 | The shared vocabulary: players, singles/doubles, the six match formats and their rules (data-driven), set scores, doubles serve order. | Live scoring, match setup |
| `Models/MatchRecord.swift` | 175 | The saved match: scores, points, timing, fitness totals, resume state. Carefully written so that old saved matches always decode, forever. | Archive, match history |
| `Models/PointStat.swift` | 235 | One categorised point: who served, who won, how it ended (winner/error/double fault, ending shot), heart rate and steps at that moment; also defines the shared server-attributed categories and matching rules used by the iOS/HTML graph filters. The atom all statistics derive from. | Point categorisation, stats, graphs |
| `Sync/MatchSyncMessage.swift` | 155 | The sync dictionary: every key two devices may put on the wire (match data, settings, commands), in one place, with the sync-service contract. | Sync |
| `Sync/MatchSyncTransport.swift` | 255 | Delivery strategy: when to send instantly vs. queue for later vs. transfer as a file; what to drop when the other device is unreachable. | Sync |
| `Sync/SyncIncomingPayload.swift` | 230 | The decoder for everything arriving over the bridge: validates and routes incoming messages on both platforms. | Sync |
| `Sync/MatchSyncPayloadBuilder.swift` | 95 | The encoder counterpart: builds outgoing payloads in one place so the wire shape is testable and can't drift between apps. | Sync |
| `Sync/MatchMergePolicy.swift` | 75 | The merge rules when a match arrives on the phone: completed beats in-progress, newer completed wins, the watch is trusted for live matches, tombstoned (deleted) matches are skipped. | Sync, archive |
| `Sync/ArchiveBackupPolicy.swift` | ~115 | The one-way iCloud backup policy: creates outbound snapshots from the phone archive (stripping the five HealthKit-derived fields per App Store Review Guideline 5.1.3(ii)), handles the one-time initial restore, and defines `BackupPreview` (record count + newest date for the user-facing restore prompt). | Archive, iCloud backup |
| `Persistence/ManualMatchArchiveBackup.swift` | 193 | Versioned full-fidelity JSON codec and merge/replace policy for user-initiated manual archive export/import. Manual exports include HealthKit-derived match fields and are kept separate from iCloud backup policy. | Manual archive backup |
| `Persistence/HealthSidecarPolicy.swift` | 130 | Pure projection/reconstruction policy for exactly the five HealthKit-derived persisted fields. Produces the phone's stripped main archive and Health-only sidecar, then fills only missing values by match and point ID on load. | Archive, health/privacy |
| `Sync/WatchMirror.swift` | 70 | Phone-side bookkeeping of *which matches are currently on the watch* — so the phone can show watch-only matches (even ones deleted from the phone) and keep badges accurate. | Sync, archive |
| `Sync/MatchStorageLocation.swift` | ~85 | Derives each match's badge — on both devices / phone only / watch only — from the watch's reported list vs. the phone's archive. `reportedIDsSurvivingManifest(reported:manifest:activeMatchID:)` reconciles the phone's optimistic "the watch sent us this record" set against an authoritative manifest: the watch streams a checkpoint per point but only lists a match once it finishes, so a received record counts as proof of watch storage, while an id a manifest omits is retired unless it is the live match. | Archive (badges) |
| `Sync/WatchHistoryCap.swift` | 15 | One number: the watch keeps its newest **25** matches. Lives here so the watch (which enforces it) and the phone (which explains it) can't drift. | Match history |
| `Settings/SettingsCopy.swift` | 40 | The one-line description under every setting, written once so the watch and phone settings screens can't show different wording. | Settings |
| `Settings/MatchSetupDefaults.swift` | ~35 | The remembered "last used" match setup (format + singles/doubles) the watch start screen pre-applies. `resolve(formatRaw:typeRaw:)` is a total decode — an absent, empty, or retired raw value falls back to `.standard`/`.singles` rather than crashing. Watch-local only; no wire key (the phone never starts a live match). | Match setup |
| `Settings/MatchTrackingStatus.swift` | ~280 | The rule behind the pre-match "what will this match record?" indicators. Resolves point tracking (format-aware — suppressed to a `—` state when `MatchFormat.config.disablesPointTracking`, e.g. Perpetual Points), Health access, and Pulse Coach into `.on`/`.partial`/`.off` with a short state badge, an SF Symbol, and one line of fix-it copy; Pulse's uncalibrated copy says the fix is retroactive (zones are derived at display time). `HealthAccess` is the portable stand-in for the HealthKit permission (the watch maps `HKHealthStore` onto it, so the package stays HealthKit-free). `collapsingPulseWhenHealthOff(_:)` drops the Pulse status from a resolved list when Health is off — the pre-match strip's rule; the Settings rows use the uncollapsed three. | Tracking status, settings |
| `Settings/HealthAccessSettlePolicy.swift` | ~45 | The bounded schedule for re-reading HealthKit's share status after the authorization sheet closes. `requestAuthorization`'s completion is the only chance the watch gets to notice a fresh grant — the scene never leaves `.active` for a system sheet, and the start screen's `onAppear` already ran — so when that one read still answers `.notDetermined` the strip would show a yellow "Ask" until the next launch. `nextRetryDelay(attempt:access:)` returns the next gap, stopping on any conclusive state and once the delays run out. | Tracking status, health |
| `Settings/ICloudBackupCopy.swift` | ~95 | The iCloud backup status line and the rule for choosing it. Six cases: `backedUp`, `notBackedUp`, `unavailable`, `restoring`, `pendingRestore` (backup found, user prompt pending), `pendingUpload` (pushed but daemon upload not yet confirmed). `current(isEnabled:isAvailable:isRestoring:hasPendingRestore:isUploaded:)`. | iCloud backup |
| `Settings/HealthExportConsent.swift` | ~150 | The single source for the per-export HealthKit disclosure (Blocker 4). `presentFields(in:focal:includesRawPoints:)` reports which of the five health fields a rendered export (text/HTML/AI) would expose for that perspective and kind — totals gate on `> 0`, opponent HR / per-point-only steps need the raw-point table, zones are recorder-only, empty ⇒ skip the dialog. `archiveFields(in:)` is the union across a full-fidelity manual archive of raw records — heart rate, steps, calories, distance, but **never** derived zones; it counts **any non-nil** value (including a stored `0` total, which the archive serialises as-is), unlike the rendered `> 0` gating. `disclosure(fields:destination:)` builds the "Share health data?" copy naming exactly those fields plus the recipient (`archiveFile`, or `sharedReport` for text/HTML/AI-Coach — all reach the share sheet, so its clause names the broad recipient set). Does not strip — exports stay full-fidelity. | Health/privacy, exports |
| `Persistence/StatsStoring.swift` | 25 | The tiny storage contract (load/save/append/remove) that the watch's and phone's stores both implement. | Archive, match history |
| `WebExport/MatchWebViewModel.swift` | ~425 | The clean, `Encodable`, perspective-flattened JSON shape the self-contained HTML match export renders from: meta, both me/opponent stat perspectives with counted outcome/serving/ending-shot graph filters, a point list (with Points-tab display fields including full pre-point match score), set bands + labels, recorder-only HR/steps, per-set stat filters, and optional AI Coach prompts. `schemaVersion` 9. All derivation stays in tested Swift. | Web export |
| `WebExport/MatchWebViewModel+Build.swift` | ~525 | The pure builder behind `MatchWebViewModel.make` — mirrors `MatchExporter`'s section structure and recorder-only-HR rule but emits structured rows; also derives per-perspective outcome (Me/Opp), serving (Me/Opp), and ending-shot (Won/Lost) pill counts plus Points-tab display fields and canonical scores. | Web export |
| `WebExport/MatchWebViewModel+Comparison.swift` | ~225 | Builds the per-set `filters` (All + one per set, mirroring `availableSetFilters`): each recomputes `meSummary`/`oppSummary` over the filtered stats into the TV-style Me-vs-Opp `comparison` (a faithful mirror of `MatchDetailView`'s split-bar stats — same titles, order, gating, percent/count/ratio rows), the points-won header, and the duration/activity rows. | Web export |
| `WebExport/MatchWebViewModel+AICoach.swift` | ~40 | Builds the optional `aiCoach` block (mirrors the iOS `AICoachSheet`): attaches the explanatory copy + the static AI-app launch list (ChatGPT/Claude/Gemini/Perplexity/Copilot/Poe/Grok, with web URLs + tints) to the injected coaching prompt(s). Prompt TEXT comes from `MatchExporter.aiPromptExport` (passed in); `nil` when no prompt is supplied. | Web export |
| `WebExport/WebExportColors.swift` | ~120 | Single source of the export's colours/symbols (outcome, serving and ending-shot scatter; set bands; me/opponent lines; HR/steps), kept in step with `PointsGraphView` so the browser viewer never re-encodes the palette. | Web export |
| `WebExport/MatchWebTemplate.swift` | ~1,010 | The viewer itself as Swift raw-string constants (HTML skeleton + CSS + dependency-free SVG/JS), recorder-framed with **no perspective toggle**: momentum step lines, set bands, iOS-style counted scatter controls (Outcomes + Serving + Ending Shots), recorder-only HR/steps overlays, click/touch-drag point inspection, Stats/Points and set filters, the Me-vs-Opp stat comparison, point list, and AI Coach card. Loads no resources on open; AI links are user-clicked navigations. | Web export |
| `WebExport/MatchHTMLExporter.swift` | ~50 | Assembles ONE self-contained, offline HTML document for a match: encodes the view model and injects it (script-safely) into the template, with the static `#root` fallback from `MatchWebStaticFallback`. Optional `aiPromptMe`/`aiPromptOpponent` surface the AI Coach card. Pure and unit-testable. | Web export |
| `WebExport/MatchWebStaticFallback.swift` | ~405 | The no-JS view of the export (progressive enhancement): renders a styled static summary into `#root` — banner, header, **four server-rendered SVG momentum charts** (one per interactive preset: Points Won/Lost outcome scatter and Ending Shots All Won/Lost shot scatter), each with its scatter overlay + colour/label/count pills, and the **TV-style Me/Opp split-bar comparison for the whole match plus a per-set breakdown** (mirrors `MatchDetailView` and the viewer's bars) — so no-JS previews (iOS Quick Look, local-file opens) show a near-complete report instead of a blank page. `staticChartSVG(_:scatter:)` mirrors the JS `buildSVG`/`stepPath`/`symbol` geometry, and `pointsWonBar`/`comparisonCard`/`splitBar` mirror the JS comparison bars; the viewer JS clears `#root` and rebuilds on load. Reuses the viewer's CSS. | Web export |

Plus `Package.swift` (~35 lines) — the package manifest (name, platforms, library/executable
products, test target).

### Command-line tools — `DeuceMate/Packages/DeuceMateCore/Sources/` (2 files)

Reusable dev tooling, built via `swift run` from the package directory (not part of the
iOS/watchOS app targets). See `docs/screenshots/README.md` for usage.

| File | ~Lines | What it does | Feature(s) |
|---|---:|---|---|
| `DeuceMateArchiveTool/main.swift` | ~120 | CLI over `ManualMatchArchiveBackup`/`MatchHTMLExporter`: `list` inspects an archive JSON file (index, UUID, date, format, duration, set scores, stat count), `webexport` renders one match's interactive HTML export to disk, `seed` writes a decoded archive into a simulator app container's canonical `MatchArchive/` files (via `HealthSidecarPolicy`) for visual QA of the import feature without driving the file-picker UI. | Manual archive backup, Web export, tooling |
| `DeuceMateWebSnapshot/main.swift` | ~150 | macOS-only headless renderer: loads a local HTML file (or wraps a plain `.txt` file in a simple styled dark page) into an off-screen `WKWebView`, runs a sequence of steps — click a button by label (e.g. the web export's Stats/Points tab toggle) or `scroll:<0-100>` to a percentage of the page height — capturing a PNG via `WKWebView.takeSnapshot` after each step. No macOS Screen Recording permission needed since it's an in-process view snapshot, not a display capture. Generic; not DeuceMate-specific. | Web export, AI-coach prompt, tooling |

## 4. Tests (59 files)

Tests are the correctness record. The interesting ones all live against the shared
package (no simulator needed). Red flags in any PR: tests deleted, skipped, or
expected values rewritten to make a failure pass — that requires explicit approval.

**Package tests — `DeuceMate/Packages/DeuceMateCore/Tests/DeuceMateCoreTests/` (44 files):**

| File | Covers |
|---|---|
| `ScoringEngineTests.swift` | The tennis rules: deuce cycles, serve rotation, tiebreaks, changeovers, all match formats, match completion, and the perspective-neutral regular-game completion predicate shared with historical reconciliation. |
| `MatchStatsSummaryTests.swift` / `MatchStatsSummaryHRTests.swift` / `MatchStatsSummaryStepsTests.swift` | The statistics math, including heart-rate splits and per-point step deltas / timeline. |
| `MatchTrendSampleTests.swift` / `TrendMetricTests.swift` / `PerformanceTrendsTests.swift` | Cross-match trends: eligibility (in-progress, tracking-disabled formats, thin categorized data), the recorder-framed field mapping against `MatchStatsSummary`, nil-not-zero on empty denominators, filter-before-window ordering, pooling (including the zero-denominator-match regression), and delta orientation/thresholds. |
| `StepsSeriesTests.swift` | The shared steps overlay series: base-normalization, per-point deltas, sparse-sample indices, and the `totalSteps` linear-estimate fallback. |
| `RecCoachInsightsTests.swift` / `PulseCoachInsightsTests.swift` / `StepsCoachInsightsTests.swift` | Every coaching rule firing (and not firing) on fixture matches. |
| `MatchRecordCodingTests.swift` | Saved matches decode forever — round-trips plus old JSON without newer fields. |
| `MatchRecordFormattingTests.swift` | Score display notation. |
| `MatchMergePolicyTests.swift` | The watch-vs-phone merge matrix. |
| `ArchiveBackupPolicyTests.swift` | The one-way iCloud backup policy: outbound snapshots (health stripped), initial restore, tombstone propagation, stale in-progress backup protection, and health backfill from local checkpoints. |
| `HealthSidecarPolicyTests.swift` | Health sidecar split/merge identity, five-field stripping, empty projection omission, orphan handling, nil-only fill behavior, and backward-compatible decoding. |
| `ManualMatchArchiveBackupTests.swift` | Manual archive file format, full health-data round trip, merge/replace import behavior, and invalid file rejection. |
| `MatchSyncPayloadBuilderTests.swift` / `SyncIncomingPayloadTests.swift` / `MatchSyncRoundTripTests.swift` / `MatchSyncTransportTests.swift` | The wire format: encode → decode → merge round trips; queueing and reachability behaviour. |
| `MatchStorageLocationTests.swift` / `WatchMirrorTests.swift` | Storage badges and the phone's mirror of the watch's match set, including reconciling optimistically reported ids against a manifest — the live match survives an omission, a deleted one does not. |
| `MatchFormatConfigTests.swift` | The data-driven rules of each match format. |
| `MatchSetupDefaultsTests.swift` | The remembered match setup's total decode: absent/empty/unknown raw values fall back, and every format×type pair round-trips. |
| `HRZoneTests.swift` / `SetActivitySplitTests.swift` | HR zone boundaries; per-set splits. |
| `PointGamesScoreTests.swift` | The in-set games derivation: game boundaries, realistic completed 6–4 and 7–6 sets, final-point reconciliation, suffix suppression (including the mid-game one-game-offset guard), no-games formats, and legacy snapshots. |
| `SetScoreLabelTests.swift` | Canonical regular/tiebreak-only set labels across all six formats and both perspectives, plus recorder-oriented game scores (serve orientation, deuce, advantage, and tiebreak points). |
| `SetFilterTests.swift` / `MatchDurationsTests.swift` | The shared set-scope labels/indices, and duration resolution: recorded value wins, per-set point-span fallback, whole-match `matchElapsedSeconds` → start/end span, and the minute strings. |
| `StatFormattingTests.swift` / `CompactScoreLineTests.swift` | The shared percent/ratio strings (truncated for exports, rounded for headers, `—` with no denominator) and the watch's compact score line across regular sets, tiebreaks, tiebreak-only formats and in-progress matches. |
| `PointMatchScoreTests.swift` | Full pre-point match-score composition across all formats: prior sets, live games, regular-set breakers, deciding super-tiebreaks, suffix-only history, and legacy data. |
| `SettingsCopyTests.swift` / `ICloudBackupCopyTests.swift` | Settings blurbs and the iCloud status rule. |
| `MatchTrackingStatusTests.swift` | The pre-match tracking indicators: each facet's on/degraded/off resolution, format-suppressed point tracking (Perpetual Points → `—` regardless of the toggle), Health `notDetermined` vs. denied vs. unavailable, Pulse Coach calibration (including age 30 resolving to 190 without being mistaken for the default, and the retroactive-recompute copy), `collapsingPulseWhenHealthOff` keeping/dropping Pulse correctly, and chip copy/width invariants. |
| `HealthAccessSettlePolicyTests.swift` | The post-authorization re-read schedule: an undetermined status walks the delays in order and then stops, any conclusive status stops immediately, the window stays short and backs off, and the reported bug's shape — undetermined at the completion, authorized on a later read — settles rather than polling on. |
| `HealthExportConsentTests.swift` | The per-export health disclosure: present-fields per perspective (zones recorder-only, empty ⇒ skip), disclosure copy fidelity and recipient clauses, and agreement between `presentFields(.me)` and the recorder-framed HTML export's health blocks. |
| `PointStatTests.swift` | The point atom's own queries and identifiers: `isDoubleFault`, `wasServing`/`wasWonBy`, stable raw-value ids across `PointOutcome`/`EndingShot`/`ServingPointCategory`, `strippingHealthData` (tennis facts survive, only the five HealthKit-derived fields drop), `fillingMissingHealthData` never overwriting a non-nil value, and legacy `PendingPointInfo` JSON without `isBreakPoint`/`gameScoreAtStart`. |
| `ScoreTypesTests.swift` | The shared score vocabulary: `DoublesServer.team`/`displayName` for all four cases, `SetScore` defaults and round-trip identity, and the raw values pinned as persisted identifiers — the guard that makes deleting a case fail in Xcode rather than on a user's wrist (see `CLAUDE.md` §4 "Retire a case in a persisted enum"). |
| `StatsStoringCodecTests.swift` | The shared JSON codec both stores persist through — full-fidelity round trip, empty history, and rejection of corrupt or key-missing data. Drives the real `StatsStoring.encode/decode` rather than a local copy. |
| `SimulatedGameStatsTests.swift` | Simulates realistic whole matches to exercise stats end-to-end. |
| `MatchWebExportTests.swift` | The interactive HTML export: view-model shape, mirrored outcome/serving/ending-shot counts, serving-category rules and palette, full per-point match score + server rendering, realistic completed-set integration, recorder-only HR, pointer dragging, and self-contained output. |

**App-target tests (14 files):** `DeuceMate Watch AppTests/DeuceMate_Watch_AppTests.swift`
(~1,140 lines — watch-specific behaviour: tiebreak serve rotation, changeover events,
compass bearings), `DeuceMate Watch AppTests/StatsStoreTests.swift` (exercises the real
watch `StatsStore` against a temp file: absent-file vs. corrupt-file semantics, the
refuse-to-overwrite-on-unreadable guard, valid round-trips, and repeated backup exclusion),
`DeuceMate Watch AppTests/MatchSetupDefaultsWatchTests.swift` (the remembered-setup
hydration paths against a real `ScoreViewModel`: `loadState()` hydrates on both the
success-with-idle-state and catch exits but never touches a restored live match,
`resetMatch()` persists the remembered pair — not the hard-coded fallback — into the
saved `AppState`, and `init` never hydrates), `DeuceMate Watch AppTests/TrackingStatusWatchTests.swift`
(`ScoreViewModel.trackingStatuses` wires the live matchFormat/settings/`workoutManager.healthAccess`
into `MatchTrackingStatus.all(...)`, `WorkoutManager.$healthAccess` forwards into
the view model's own `objectWillChange` — the prior-art bug this feature's plan called out: a strip
observing only the workout manager looks load-bearing but silently never redraws
without this forward — and a negative case confirms the forward stays scoped to
`healthAccess`, not the manager's whole `objectWillChange` stream, which would
otherwise fire on every live-match heart-rate tick), `DeuceMateTests/PhoneStatsStoreTests.swift` (canonical migration, sidecar failure
degradation, import repair, unreadable-main suspension, and backup flags),
`DeuceMateTests/DeuceMateTests.swift` (iPhone WatchConnectivity activation fallbacks
and paired/unpaired Manual Entry copy), `DeuceMateTests/MatchExporterTests.swift`
(the plain-text / AI-prompt exporter's health content: recorder-only HR / zones /
movement, both-perspective step/calorie/distance totals only when > 0, per-point
HR/steps only via the raw-point table, the opponent-prompt disclaimer, and agreement
between `HealthExportConsent.presentFields` and what each export string actually
emits — the `MatchExporter` half of the disclosure↔export cross-check, which must
live in the iOS target because Core cannot import app-side code),
`DeuceMateTests/TrendsSamplesTests.swift` (the Trends screen's `@MainActor`
sample cache: a match completing with the same id it had while in-progress,
a still-in-progress match's points growing between refreshes, and — a
regression for a Codex-caught PR #121 finding — a record's content being
replaced in place (e.g. by a Backup & Transfer import) with the same id,
`endTime`, `iWon`, and point count are all picked up rather than staying
silently stale, alongside the no-op-when-unchanged and add-a-match cases),
`DeuceMateUITests/DeuceMateUITests.swift`
(Manual Entry -> history -> truthful detail empty states -> export, both the
negative skip-when-empty and the seed-gated positive "Share health data?" consent
gates, and the archive's swipe -> Delete permanent-delete confirmation staying up
until it is answered — the regression guarding the dialog against being re-anchored
inside a list row, where closing the swipe dismisses it), two remaining
UI-test placeholders (`DeuceMate Watch AppUITests/DeuceMate_Watch_AppUITests.swift`,
`DeuceMateUITests/DeuceMateUITestsLaunchTests.swift`), plus three screenshot-capture
suites (not regression tests — see `docs/screenshots/README.md`):
`DeuceMateTests/AIPromptExportCaptureTests.swift` (calls `MatchExporter.aiPromptExport`
directly against a real imported archive record and writes the real prompt text to a
host file — sidesteps `AICoachSheet` never rendering the prompt on-screen),
`DeuceMateUITests/ScreenshotTests.swift` (navigates a seeded match's detail view —
expanded Points Graph with HR/Steps overlays and Points Won/Lost filters, Pulse Coach,
Outcome Breakdown — capturing via `XCUIScreen.main.screenshot()`), and
`DeuceMate Watch AppUITests/LiveMatchScreenshotTests.swift` (drives a live match via
real swipe gestures, handling the first-launch HealthKit sheet, a leftover
in-progress match, and odd-game changeover prompts, for the watch scoreboard shot).

---

## 5. Feature → file matrix (the reverse index)

When reviewing a change to feature X, these are the files that may legitimately be
touched. A PR for feature X that edits files far outside its row deserves a question.

| Feature | Watch app | iPhone app | Shared package |
|---|---|---|---|
| **Live scoring & match formats** | `ScoreViewModel`, `ContentView`, `MatchStats` | — | `ScoringEngine`, `ScoreTypes` |
| **Match setup** | `HomeView`, `ScoreViewModel` | `ManualMatchEntryView` | `ScoreTypes`, `MatchSetupDefaults` |
| **Point categorisation** | `PointCategorySheet`, `ScoreViewModel` | `LivePointCategoryPanel` | `PointStat` |
| **Match history (watch)** | `MatchHistoryView`, `StatsStore`, `BackupExcludedFileWriter` | — | `WatchHistoryCap`, `StatsStoring`, `MatchRecord` |
| **Archive (phone)** | — | `PastMatchesView`, `PhoneStatsStore` | `MatchRecord`, `MatchMergePolicy`, `HealthSidecarPolicy`, `ArchiveBackupPolicy`, `MatchStorageLocation`, `WatchMirror` |
| **Watch ↔ phone sync** | `Sync/WatchMatchSyncService` | `Sync/PhoneMatchSyncService` | `MatchSyncMessage`, `MatchSyncTransport`, `MatchSyncPayloadBuilder`, `SyncIncomingPayload`, `MatchMergePolicy` |
| **Live scoreboard & iPhone input** | `ScoreViewModel` (command validation) | `LiveScoreboardView`, `LivePointCategoryPanel`, `PhoneMatchSyncService` | `MatchSyncMessage` |
| **Announcements (spoken score)** | `ScoreViewModel` (builds the text) | `Audio/LiveAnnouncementService` | `MatchSyncMessage` |
| **Stats & graphs** | `MatchStatsView` | `MatchDetailView`, `PointsGraphView`, `HealthKitHRFetcher` | `MatchStatsSummary`, `SetActivitySplit`, `PointMatchScore`, `PointGamesScore`, `SetScoreLabel`, `PointStat` |
| **Trends** | — | `PastMatchesView` (hosts the section), `TrendsSection`, `TrendsSamples`, `TrendsView`, `TrendChart`, `TrendSparkline` | `MatchTrendSample`, `TrendMetric`, `PerformanceTrends` |
| **Rec Coach insights** | — | `Views/Coaching/RecCoachSection` | `RecCoachInsights` |
| **Pulse Coach (heart-rate) insights** | `ScoreViewModel` (settings) | `Views/PulseCoach/PulseCoachSection` | `PulseCoachInsights`, `HRZone` |
| **AI coaching export** | — | `Export/MatchExporter`, `AICoachSheet`, `AICoachLauncher` | `MatchStatsSummary` |
| **Interactive web (HTML) export** | — | `MatchDetailView` (share action) | `WebExport/MatchHTMLExporter`, `MatchWebStaticFallback`, `MatchWebViewModel` (+`Build`, +`Comparison`, +`AICoach`), `MatchWebTemplate`, `WebExportColors`, `MatchStatsSummary`, `PointMatchScore`, `PointGamesScore`, `SetScoreLabel`, `MatchExporter` (AI prompt) |
| **Compass changeover** | `ScoreViewModel`, `ContentView`, `HomeView` | `SettingsView` (toggle) | — |
| **Health / workout tracking** | `WorkoutManager` | `HealthKitHRFetcher` | `HRZone` |
| **Tracking status (pre-match)** | `TrackingStatusStrip`, `HomeView`, `ScoreViewModel`, `WorkoutManager` | — | `MatchTrackingStatus`, `SettingsCopy`, `HRZone` |
| **Theming** | `AppTheme` | `AppTheme` | — |
| **Settings** | `ScoreViewModel` | `SettingsView` | `SettingsCopy`, `MatchSyncMessage` |
| **iCloud backup** | — | `PhoneStatsStore`, `SettingsView`, `DeuceMateApp` (foreground backup sync) | `ICloudBackupCopy`, `ArchiveBackupPolicy` |
| **Manual archive backup** | — | `SettingsView`, `PhoneStatsStore` | `ManualMatchArchiveBackup`, `MatchRecord`, `PointStat` |

## 6. Files that look speculative but are live (read before deleting anything)

- **`Sync/WatchMirror.swift`** — despite the name, this is *not* an unused mirror
  feature: it is what lets the phone display matches that exist only on the watch
  (including ones the user deleted from the phone). Used by `PhoneMatchSyncService`.
- **`Settings/ICloudBackupCopy.swift`** — live; it is the "Backed up to iCloud"
  status indicator logic used by the archive list and match detail pages.
- **`MatchStats.swift` (watch)** — mostly a naming shim from an old refactor plus
  some display colours; small, but removing it would break the watch build.

There are currently **no parked or orphaned production files**. If a future audit
finds a file not in this inventory, treat it as unreviewed until explained.

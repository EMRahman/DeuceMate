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

## 1. Apple Watch app — `DeuceMate/DeuceMate Watch App/` (12 files)

The scorer. Everything about running a live match happens here.

| File | ~Lines | What it does | Feature(s) |
|---|---:|---|---|
| `ScoreViewModel.swift` | 1,930 | The live-match brain. Holds the current score, serve rotation, undo, tiebreak and changeover state; applies the shared scoring rules; manages match start/end, saving, resuming after a crash; holds every synced setting; validates and applies score commands arriving from the phone. The single most consequential file in the repo. | Live scoring, settings, sync, compass changeover, Pulse Coach settings |
| `ContentView.swift` | 940 | The live scoreboard screen: score display, swipe gestures (up/down = point, left = undo, right = stats), momentum strip, changeover prompts and compass indicator. | Live scoring, compass changeover |
| `HomeView.swift` | 900 | The start screen and pre-match setup flow: singles/doubles, player names, who serves first, match format, court-end confirmation for the compass feature. | Match setup |
| `MatchStatsView.swift` | 630 | On-watch statistics screen shown during/after a match: serve, return, break points, errors, rally depth, heart-rate zones; set and player filters. | Stats |
| `PointCategorySheet.swift` | 260 | The slide-up sheet after each point (when outcome tracking is on): pick how the point ended — winner, forced/unforced error, double fault — then the ending shot. | Point categorisation |
| `MatchHistoryView.swift` | 220 | The watch's recent-matches list (newest 25): open stats, resume an in-progress match, swipe to delete. | Match history |
| `AppTheme.swift` | 220 | The watch's five court-inspired colour themes; the chosen theme syncs to the phone. | Theming |
| `WorkoutManager.swift` | 200 | Runs the HealthKit workout session during a match: live heart rate, calories, steps, distance per set. | Health/workout tracking |
| `Sync/WatchMatchSyncService.swift` | 290 | The watch's end of the watch↔phone bridge: sends match checkpoints, full history, manifests and announcements; receives settings, score commands and delete commands from the phone. | Sync |
| `StatsStore.swift` | 80 | Saves match history to a JSON file on the watch; trims to the newest 25 matches; thread-safe. | Match history (persistence) |
| `DeuceMateApp.swift` | 55 | The watch app's entry point: wires up the scoring engine, workout manager and sync service; restores an in-progress match on launch. | App plumbing |
| `MatchStats.swift` | 50 | Small compatibility shim: re-exports shared types under old names, plus watch-only display labels and colours for match formats and point outcomes. | App plumbing, theming |

## 2. iPhone app — `DeuceMate/DeuceMate/` (19 files)

The viewer and the permanent archive. It displays, announces, analyses and exports
matches; it does not score them (except by sending validated commands to the watch).

| File | ~Lines | What it does | Feature(s) |
|---|---:|---|---|
| `Views/PointsGraphView.swift` | 1,525 | The interactive match chart: points momentum over time with optional overlays for point outcomes, heart rate and steps; pinch-zoom, fullscreen, touch-to-inspect. | Stats & graphs |
| `Views/MatchDetailView.swift` | ~1,055 | One match's detail page: score summary, stats tabs, the graph, coaching sections, storage-location and iCloud badges, and the export / AI-coach actions — including "Share Interactive Web Page", a self-contained `.html` file (built off-thread, shared via the system share sheet) the opponent can open in any browser. | Stats, AI export, web export, archive |
| `Views/PastMatchesView.swift` | 705 | The archive list: all matches newest-first, live-match row, badges showing whether a match lives on the watch, the phone, or both; swipe-to-delete; pull a watch-only match to the phone; free up watch space. | Archive, sync |
| `Views/LiveScoreboardView.swift` | 490 | Full-screen landscape scoreboard for spectators, fed live from the watch. With "iPhone Input" on, swipes here send score commands to the watch. | Live scoreboard, iPhone input |
| `Views/SettingsView.swift` | 752 | Settings screen: watch pairing/sync status, announcements, theme, outcome tracking, changeover compass, heart-rate settings, player name, skill level (NTRP), manual archive export/import, iCloud backup, About (version + tappable privacy-policy / support / contact links). | Settings, manual archive backup |
| `Views/ManualMatchEntryView.swift` | 440 | Form to reconstruct a match by hand (paper scorecard, watch mishap); the result is saved into the phone archive and a copy is sent to the watch so it can be resumed there. | Manual entry |
| `Views/PulseCoach/PulseCoachSection.swift` | 430 | "Pulse Coach" panel on the match page: heart-rate-based observations (performance by HR zone, pressure response, late-match fatigue). | Pulse Coach |
| `Views/LivePointCategoryPanel.swift` | 220 | Phone-side twin of the watch's point-categorisation sheet, shown under the live scoreboard so a spectator can tag the point. | Point categorisation, iPhone input |
| `Views/AICoachSheet.swift` | 200 | The export chooser: summary vs. full vs. AI coaching prompt, my/opponent perspective, copy to clipboard, hand off to an AI app. | AI export |
| `Views/AICoachLauncher.swift` | 120 | Detects which AI chat apps are installed (ChatGPT, Claude, Gemini, Perplexity, Copilot, Poe, Grok) and opens one with the coaching prompt; falls back to clipboard + share sheet. | AI export |
| `Views/Coaching/RecCoachSection.swift` | 60 | "Rec Coach" panel: up to three plain-English coaching observations derived from point stats (rules live in the shared package). | Rec Coach |
| `Export/MatchExporter.swift` | 625 | Builds the export text: match summary, full point-by-point report, or an AI coaching prompt tuned to the player's skill level. | AI export |
| `Sync/PhoneMatchSyncService.swift` | 510 | The phone's end of the watch↔phone bridge: receives checkpoints/history/manifests, merges them into the archive, tracks watch reachability, sends settings and (when allowed) score and categorisation commands to the watch. | Sync, live scoreboard |
| `Persistence/PhoneStatsStore.swift` | ~700 | The permanent archive store. Canonical copy is a device-local JSON pair (Application Support, always readable at launch); iCloud Drive holds a background backup pushed after local saves, and read only during initial local archive setup. On a fresh install with a non-empty backup, publishes `pendingRestorePreview` and waits for the user to call `confirmRestore()` or `declineRestore()` before overwriting the cloud backup. Publishes `isBackupUploaded` (derived from `.ubiquitousItemIsUploaded` on both backup files after each push). | Archive, iCloud backup, manual archive backup |
| `AppTheme.swift` | 220 | The phone's copy of the five colour themes, kept in step with the watch via settings sync. | Theming |
| `Audio/LiveAnnouncementService.swift` | 130 | Speaks the score through the iPhone speaker (umpire-style), foreground-only by design — no background audio tricks. | Announcements |
| `HealthKitHRFetcher.swift` | 180 | Fetches heart-rate samples from HealthKit for a finished match and buckets them per point for the graph overlay. | Stats & graphs, health |
| `DeuceMateApp.swift` | 50 | The iPhone app's entry point: wires up the archive store, sync service and announcer; resumes initial restore or backup push whenever the app returns to the foreground. | App plumbing |
| `ContentView.swift` | 15 | The navigation root — essentially just opens the archive list. | App plumbing |

## 3. Shared package — `DeuceMate/Packages/DeuceMateCore/Sources/DeuceMateCore/` (27 files)

The rulebook both apps use. No screens; pure logic — which makes it the cheapest
place to test and the safest place to change.

| File | ~Lines | What it does | Feature(s) |
|---|---:|---|---|
| `Scoring/ScoringEngine.swift` | 555 | The tennis rules, as a pure function: given a state and "player X won the point", returns the new state plus events (game/set won, changeover due, announcement text). No side effects — fully unit-testable. | Live scoring |
| `Stats/MatchStatsSummary.swift` | 340 | The statistics math: serve/return percentages, break points, error counts, winner-to-error ratio, pressure-point performance, rally depth, HR-zone splits. Both apps display numbers computed here, so they can never disagree. | Stats |
| `Stats/RecCoachInsights.swift` | 310 | The Rec Coach rule set: eight coaching rules (e.g. self-inflicted losses, double-fault leakage, pressure-point drop-off) that fire from point stats and rank the top observations. | Rec Coach |
| `Stats/PulseCoachInsights.swift` | 125 | The Pulse Coach rule set: three heart-rate rules (zone-vs-results delta, break-point HR spike, late-match decline). | Pulse Coach |
| `Stats/SetActivitySplit.swift` | 115 | Per-set breakdowns (duration, points, games) used by the set filters in stats views. | Stats |
| `Stats/HRZone.swift` | 80 | Heart-rate zone maths: zones 1–5 from a max heart rate (age-derived or manually overridden). | Pulse Coach, health |
| `Models/ScoreTypes.swift` | 185 | The shared vocabulary: players, singles/doubles, the six match formats and their rules (data-driven), set scores, doubles serve order. | Live scoring, match setup |
| `Models/MatchRecord.swift` | 175 | The saved match: scores, points, timing, fitness totals, resume state. Carefully written so that old saved matches always decode, forever. | Archive, match history |
| `Models/PointStat.swift` | 165 | One categorised point: who served, who won, how it ended (winner/error/double fault, ending shot), heart rate and steps at that moment. The atom all statistics derive from. | Point categorisation, stats |
| `Sync/MatchSyncMessage.swift` | 155 | The sync dictionary: every key two devices may put on the wire (match data, settings, commands), in one place, with the sync-service contract. | Sync |
| `Sync/MatchSyncTransport.swift` | 255 | Delivery strategy: when to send instantly vs. queue for later vs. transfer as a file; what to drop when the other device is unreachable. | Sync |
| `Sync/SyncIncomingPayload.swift` | 230 | The decoder for everything arriving over the bridge: validates and routes incoming messages on both platforms. | Sync |
| `Sync/MatchSyncPayloadBuilder.swift` | 95 | The encoder counterpart: builds outgoing payloads in one place so the wire shape is testable and can't drift between apps. | Sync |
| `Sync/MatchMergePolicy.swift` | 75 | The merge rules when a match arrives on the phone: completed beats in-progress, newer completed wins, the watch is trusted for live matches, tombstoned (deleted) matches are skipped. | Sync, archive |
| `Sync/ArchiveBackupPolicy.swift` | ~115 | The one-way iCloud backup policy: creates outbound snapshots from the phone archive (stripping the five HealthKit-derived fields per App Store Review Guideline 5.1.3(ii)), handles the one-time initial restore, and defines `BackupPreview` (record count + newest date for the user-facing restore prompt). | Archive, iCloud backup |
| `Persistence/ManualMatchArchiveBackup.swift` | 193 | Versioned full-fidelity JSON codec and merge/replace policy for user-initiated manual archive export/import. Manual exports include HealthKit-derived match fields and are kept separate from iCloud backup policy. | Manual archive backup |
| `Sync/WatchMirror.swift` | 70 | Phone-side bookkeeping of *which matches are currently on the watch* — so the phone can show watch-only matches (even ones deleted from the phone) and keep badges accurate. | Sync, archive |
| `Sync/MatchStorageLocation.swift` | 50 | Derives each match's badge — on both devices / phone only / watch only — from the watch's reported list vs. the phone's archive. | Archive (badges) |
| `Sync/WatchHistoryCap.swift` | 15 | One number: the watch keeps its newest **25** matches. Lives here so the watch (which enforces it) and the phone (which explains it) can't drift. | Match history |
| `Settings/SettingsCopy.swift` | 40 | The one-line description under every setting, written once so the watch and phone settings screens can't show different wording. | Settings |
| `Settings/ICloudBackupCopy.swift` | ~95 | The iCloud backup status line and the rule for choosing it. Six cases: `backedUp`, `notBackedUp`, `unavailable`, `restoring`, `pendingRestore` (backup found, user prompt pending), `pendingUpload` (pushed but daemon upload not yet confirmed). `current(isEnabled:isAvailable:isRestoring:hasPendingRestore:isUploaded:)`. | iCloud backup |
| `Persistence/StatsStoring.swift` | 25 | The tiny storage contract (load/save/append/remove) that the watch's and phone's stores both implement. | Archive, match history |
| `WebExport/MatchWebViewModel.swift` | ~400 | The clean, `Encodable`, perspective-flattened JSON shape the self-contained HTML match export renders from: meta, both me/opponent stat perspectives, a point list (with Points-tab display fields), set bands + labels, the recorder-only HR/steps blocks, `filters` — per-set-filter (All / Set N) stat views, each carrying the TV-style Me-vs-Opp `comparison`, points-won header, and duration/activity rows — and an optional `aiCoach` block (prompt + launch links). `schemaVersion` 4. All derivation stays in tested Swift. | Web export |
| `WebExport/MatchWebViewModel+Build.swift` | ~530 | The pure builder behind `MatchWebViewModel.make` — mirrors `MatchExporter`'s section structure and recorder-only-HR rule but emits structured rows; also derives the per-perspective outcome (Me/Opp) and ending-shot (Won/Lost) pill counts, the Points-tab point-display fields (chip text/colour, outcome line, server-relative score), plus score/format/duration/game-score helpers. | Web export |
| `WebExport/MatchWebViewModel+Comparison.swift` | ~225 | Builds the per-set `filters` (All + one per set, mirroring `availableSetFilters`): each recomputes `meSummary`/`oppSummary` over the filtered stats into the TV-style Me-vs-Opp `comparison` (a faithful mirror of `MatchDetailView`'s split-bar stats — same titles, order, gating, percent/count/ratio rows), the points-won header, and the duration/activity rows. | Web export |
| `WebExport/MatchWebViewModel+AICoach.swift` | ~40 | Builds the optional `aiCoach` block (mirrors the iOS `AICoachSheet`): attaches the explanatory copy + the static AI-app launch list (ChatGPT/Claude/Gemini/Perplexity/Copilot/Poe/Grok, with web URLs + tints) to the injected coaching prompt(s). Prompt TEXT comes from `MatchExporter.aiPromptExport` (passed in); `nil` when no prompt is supplied. | Web export |
| `WebExport/WebExportColors.swift` | ~110 | Single source of the export's colours/symbols (outcome scatter, ending-shot scatter, set bands, me/opponent lines, HR/steps), kept in step with `PointsGraphView`'s palette so the browser viewer never re-encodes it. | Web export |
| `WebExport/MatchWebTemplate.swift` | ~865 | The viewer itself as Swift raw-string constants (HTML skeleton + CSS + dependency-free SVG/JS), recorder-framed with **no perspective toggle**: momentum step lines, set bands, iOS-`PointsGraphView`-style scatter controls (Outcomes + Ending Shots count pills), recorder-only HR/steps overlays, point selection, a **Stats/Points tab toggle** and **All/Set N set filter** (mirroring `MatchDetailView`), the set-filtered Me-vs-Opp split-bar comparison + points-won bar + Duration card + coaching/PulseCoach/HR-zone cards, a point-by-point list grouped by set, and an **AI Coach card** (mirrors `AICoachSheet`: My/Opponent prompt + clipboard copy + opt-in AI-app launch links). Loads no resources on open (CDN-free, network-free); the AI links are user-clicked navigations. | Web export |
| `WebExport/MatchHTMLExporter.swift` | ~50 | Assembles ONE self-contained, offline HTML document for a match: encodes the view model and injects it (script-safely) into the template, with the static `#root` fallback from `MatchWebStaticFallback`. Optional `aiPromptMe`/`aiPromptOpponent` surface the AI Coach card. Pure and unit-testable. | Web export |
| `WebExport/MatchWebStaticFallback.swift` | ~320 | The no-JS view of the export (progressive enhancement): renders a styled static summary into `#root` — banner, header, **four server-rendered SVG momentum charts** (one per interactive preset: Points Won/Lost outcome scatter and Ending Shots All Won/Lost shot scatter), each with its scatter overlay + colour/label/count pills, and the whole-match Me/Opp stat tables — so no-JS previews (iOS Quick Look, local-file opens) show a near-complete report instead of a blank page. `staticChartSVG(_:scatter:)` mirrors the JS `buildSVG`/`stepPath`/`symbol` geometry; the viewer JS clears `#root` and rebuilds on load. Reuses the viewer's CSS. | Web export |

Plus `Package.swift` (~25 lines) — the package manifest (name, platforms, test target). No logic.

## 4. Tests (28 files)

Tests are the correctness record. The interesting ones all live against the shared
package (no simulator needed). Red flags in any PR: tests deleted, skipped, or
expected values rewritten to make a failure pass — that requires explicit approval.

**Package tests — `DeuceMate/Packages/DeuceMateCore/Tests/DeuceMateCoreTests/` (23 files):**

| File | Covers |
|---|---|
| `ScoringEngineTests.swift` | The tennis rules: deuce cycles, serve rotation, tiebreaks, changeovers, all match formats, match completion. |
| `MatchStatsSummaryTests.swift` / `MatchStatsSummaryHRTests.swift` | The statistics math, including heart-rate splits. |
| `RecCoachInsightsTests.swift` / `PulseCoachInsightsTests.swift` | Every coaching rule firing (and not firing) on fixture matches. |
| `MatchRecordCodingTests.swift` | Saved matches decode forever — round-trips plus old JSON without newer fields. |
| `MatchRecordFormattingTests.swift` | Score display notation. |
| `MatchMergePolicyTests.swift` | The watch-vs-phone merge matrix. |
| `ArchiveBackupPolicyTests.swift` | The one-way iCloud backup policy: outbound snapshots (health stripped), initial restore, tombstone propagation, stale in-progress backup protection, and health backfill from local checkpoints. |
| `ManualMatchArchiveBackupTests.swift` | Manual archive file format, full health-data round trip, merge/replace import behavior, and invalid file rejection. |
| `MatchSyncPayloadBuilderTests.swift` / `SyncIncomingPayloadTests.swift` / `MatchSyncRoundTripTests.swift` / `MatchSyncTransportTests.swift` | The wire format: encode → decode → merge round trips; queueing and reachability behaviour. |
| `MatchStorageLocationTests.swift` / `WatchMirrorTests.swift` | Storage badges and the phone's mirror of the watch's match set. |
| `MatchFormatConfigTests.swift` | The data-driven rules of each match format. |
| `HRZoneTests.swift` / `SetActivitySplitTests.swift` | HR zone boundaries; per-set splits. |
| `SettingsCopyTests.swift` / `ICloudBackupCopyTests.swift` | Settings blurbs and the iCloud status rule. |
| `SimulatedGameStatsTests.swift` | Simulates realistic whole matches to exercise stats end-to-end. |
| `MatchWebExportTests.swift` | The interactive HTML export: view-model shape, both-perspective consistency, the recorder-only-HR rule, and that the produced HTML is self-contained (no external resource loads). |

**App-target tests (6 files):** `DeuceMate Watch AppTests/DeuceMate_Watch_AppTests.swift`
(~1,140 lines — watch-specific behaviour: tiebreak serve rotation, changeover events,
compass bearings), the near-empty `DeuceMateTests/DeuceMateTests.swift`, and four
UI-test placeholders: `DeuceMate Watch AppUITests/DeuceMate_Watch_AppUITests.swift`,
`DeuceMate Watch AppUITests/DeuceMate_Watch_AppUITestsLaunchTests.swift`,
`DeuceMateUITests/DeuceMateUITests.swift`,
`DeuceMateUITests/DeuceMateUITestsLaunchTests.swift`.

---

## 5. Feature → file matrix (the reverse index)

When reviewing a change to feature X, these are the files that may legitimately be
touched. A PR for feature X that edits files far outside its row deserves a question.

| Feature | Watch app | iPhone app | Shared package |
|---|---|---|---|
| **Live scoring & match formats** | `ScoreViewModel`, `ContentView`, `MatchStats` | — | `ScoringEngine`, `ScoreTypes` |
| **Match setup** | `HomeView`, `ScoreViewModel` | `ManualMatchEntryView` | `ScoreTypes` |
| **Point categorisation** | `PointCategorySheet`, `ScoreViewModel` | `LivePointCategoryPanel` | `PointStat` |
| **Match history (watch)** | `MatchHistoryView`, `StatsStore` | — | `WatchHistoryCap`, `StatsStoring`, `MatchRecord` |
| **Archive (phone)** | — | `PastMatchesView`, `PhoneStatsStore` | `MatchRecord`, `MatchMergePolicy`, `ArchiveBackupPolicy`, `MatchStorageLocation`, `WatchMirror` |
| **Watch ↔ phone sync** | `Sync/WatchMatchSyncService` | `Sync/PhoneMatchSyncService` | `MatchSyncMessage`, `MatchSyncTransport`, `MatchSyncPayloadBuilder`, `SyncIncomingPayload`, `MatchMergePolicy` |
| **Live scoreboard & iPhone input** | `ScoreViewModel` (command validation) | `LiveScoreboardView`, `LivePointCategoryPanel`, `PhoneMatchSyncService` | `MatchSyncMessage` |
| **Announcements (spoken score)** | `ScoreViewModel` (builds the text) | `Audio/LiveAnnouncementService` | `MatchSyncMessage` |
| **Stats & graphs** | `MatchStatsView` | `MatchDetailView`, `PointsGraphView`, `HealthKitHRFetcher` | `MatchStatsSummary`, `SetActivitySplit`, `PointStat` |
| **Rec Coach insights** | — | `Views/Coaching/RecCoachSection` | `RecCoachInsights` |
| **Pulse Coach (heart-rate) insights** | `ScoreViewModel` (settings) | `Views/PulseCoach/PulseCoachSection` | `PulseCoachInsights`, `HRZone` |
| **AI coaching export** | — | `Export/MatchExporter`, `AICoachSheet`, `AICoachLauncher` | `MatchStatsSummary` |
| **Interactive web (HTML) export** | — | `MatchDetailView` (share action) | `WebExport/MatchHTMLExporter`, `MatchWebStaticFallback`, `MatchWebViewModel` (+`Build`, +`Comparison`, +`AICoach`), `MatchWebTemplate`, `WebExportColors`, `MatchStatsSummary`, `MatchExporter` (AI prompt) |
| **Compass changeover** | `ScoreViewModel`, `ContentView`, `HomeView` | `SettingsView` (toggle) | — |
| **Health / workout tracking** | `WorkoutManager` | `HealthKitHRFetcher` | `HRZone` |
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

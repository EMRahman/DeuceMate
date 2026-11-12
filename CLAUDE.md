# CLAUDE.md — agent operating guide for DeuceMate

This file is for AI coding agents (Claude Code and others). It is the fast path
to being productive without re-deriving the architecture every session. Humans:
see `README.md` (product) and `CONTRIBUTING.md` (PR etiquette).

DeuceMate is a native **SwiftUI tennis-scoring app** for **Apple Watch** (the
primary scorer) with an **iPhone companion** (live viewing, announcements,
archive, stats) and a **shared Swift package** holding all portable logic.
~18k lines of production Swift, **zero third-party dependencies** (Apple
frameworks only — this is a hard rule, do not add packages).

---

## 0. Operational reality in this environment (READ FIRST)

- **Do not run or trigger GitHub Actions for verification.** The macOS test
  workflow was removed to eliminate runner costs, and nothing replaced it. Do
  not rely on GitHub CI as a feedback loop or safety net. Two ubuntu workflows
  do exist and neither builds or tests anything: `ci.yml` (a placeholder that
  echoes OK on every PR) and `pages.yml` (deploys the marketing site — see §2).
  Never add a Swift build or test step to either.
- **Local tests are welcome when the active environment is a Mac with the
  Swift/Xcode toolchain available.** Before building or testing, check for
  `xcodebuild` / `swift` (for example with `xcodebuild -version`). If they are
  present, run the relevant local commands in §3 and report results. If they are
  absent, do not keep retrying toolchain commands; verify statically and say
  what could not be run.
- **Before pushing, satisfy yourself statically that:**
  1. Every type you reference exists and is in scope (check imports — the Watch
     App test target needs `import DeuceMateCore` to use Core types directly).
  2. Every `switch` over an enum you touch is exhaustive.
  3. Any new `MatchRecord`/`PointStat` field follows the §4 backward-compat
     recipe (uses `decodeIfPresent` + default, never plain `decode`).
  4. New source files land in a globbed location: the Core package globs its
     sources, and the app + test targets are
     `PBXFileSystemSynchronizedRootGroup`s (objectVersion 77), so a new
     `.swift` file inside an existing target directory is picked up
     automatically with **no** `project.pbxproj` edit. pbxproj edits are only
     needed for new targets, build phases, or build settings — flag those
     explicitly rather than guessing.
- **Before pushing any change to a synced setting**, grep the key string across
  the whole repo and confirm it is consistent (§5 trap). Quick check:
  ```bash
  grep -rnE 'forKey:\s*"|@AppStorage\(' \
    "DeuceMate/DeuceMate Watch App/" "DeuceMate/DeuceMate/" \
    --include="*.swift" | grep -v "\.build"
  ```
  Every string literal shown should match a `MatchSyncKey` constant's raw value.
  Known exceptions: `phoneAnnouncementsEnabled` (watch) and `liveAnnouncementsEnabled`
  (phone) — the documented announcements aliases (TECHNICAL_DEBT #3); and
  `defaultMatchFormat` / `defaultMatchType` (watch-local, `MatchSetupDefaults` —
  the remembered match setup never syncs to the phone, see
  `docs/features/MATCH_START_UX_PLAN.md` §5.6); and `trendsWindow` /
  `trendsMatchType` / `trendsMatchFormat` / `trendsCompetitionType` / `trendsOpponentID` / `trendsIncludeInProgress`
  (phone-local, `TrendsView`) / `trendsServeReturnFilter` (phone-local,
  `TrendChart`) — the Trends screen's filters are UI state, not a match
  setting, so they never sync to the watch either, see
  `docs/features/PERFORMANCE_TRENDS_PLAN.md` §6.4).
  `swipeHapticsEnabled` is a synced setting (`MatchSyncKey.swipeHapticsEnabled`,
  bidirectional, last-write-wins) whose local key equals its wire key. It is not
  an exception: the watch reads it in `ScoreInputHaptics`, the iPhone's Settings
  toggle writes it, and incoming values are stored straight to `UserDefaults`.
  `matchInfoExpanded` is also phone-local: it remembers Match Info disclosure
  state across matches and launches and never syncs.
  The two walkthrough keys `walkthroughOfferSeenVersion` and
  `walkthroughCompletedVersion` are also watch-local exceptions: they never sync
  and never replace `hasCompletedFirstGame`.
  `reviewPromptLastRequestDate` and `reviewPromptLastRequestVersion`
  (`ReviewPromptCoordinator`) are phone-local too: they record App Store rating
  requests made on this iPhone and never sync.
  See `docs/features/TECHNICAL_DEBT.md` #10.
- **When you genuinely cannot verify**, say so clearly in the PR description
  rather than pushing speculatively.
- Edits to large files are fragile — `Edit` needs an exact unique match. Read
  only the `MARK:` section you need (see the file map) instead of the whole file.

---

## 1. Architecture at a glance

```
DeuceMate/
├── DeuceMate.xcodeproj
├── DeuceMate Watch App/   watchOS app — SOURCE OF TRUTH for live scoring
├── DeuceMate/             iOS companion — archive + live spectator
└── Packages/DeuceMateCore/  SPM package — portable models, stats, sync wire-format
```

Data-flow invariants — **internalise these before touching sync or persistence:**

- **The watch owns live scoring for every match it has touched.** The phone is
  normally a durable, read-only archive and matches flow watch → phone over
  `WatchConnectivity`. There are three narrow exceptions: the phone may issue
  score commands when "iPhone Input" is enabled (the watch validates/applies
  them); manual match entry may build a record and send it to the watch; and the
  user may explicitly complete an archived in-progress checkpoint with **End at
  Current Score**. If that identity is still live on the watch, the watch ends
  it using its newer live score and sends the authoritative completion back.
- **The phone archive is canonical on-device; iCloud is backup/restore only.**
  `PhoneStatsStore` renders the UI from full-fidelity records reconstructed from
  a health-stripped Application Support history plus a backup-excluded Health
  sidecar; tombstones live alongside them. The iCloud ubiquity container holds a background backup copy pushed
  after local saves. iCloud may be read only during initial local archive setup
  (fresh install / first canonical initialization), via Core's
  `ArchiveBackupPolicy`; once initialized, match data continues one way:
  watch → phone → iCloud. Tombstones back up too. Never gate the UI on iCloud,
  and never treat a failed read as an empty archive. **This "read failure ≠ empty
  archive" rule holds on _both_ stores:** the watch `StatsStore` also returns
  `nil` (not `[]`) from an unreadable/corrupt read via `loadHistoryOrNil()`, and
  its `appendMatch`/`removeMatch` and the sync manifest/full-history pushes bail
  rather than overwriting or broadcasting the emptiness.
- **Settings sync bidirectionally, last-write-wins.** Match data does not.
- **Persisted match JSON must stay backward-compatible forever** (see §4).

The watch's live-match brain is `ScoreViewModel` (an `ObservableObject`, MVVM).
It is large (~1.9k lines) and the most consequential app file in the repo: it
holds live game/set/tiebreak state, server rotation, undo, second-serve context,
break-point detection, changeover logic, HealthKit/workout wiring, and all the
synced settings. The pure scoring *rules* live in Core's `ScoringEngine`
(`pointWon(by:in:) -> ScoringResult`), to which `ScoreViewModel` delegates.

---

## 2. File map (where things live + how big)

Sizes flag the files that are expensive to load/edit. Jump to the named
`MARK:` anchors rather than reading top-to-bottom.

**Shared core — `Packages/DeuceMateCore/Sources/DeuceMateCore/`** (edit here for
anything portable; no `.pbxproj` change needed — the package globs its sources):

| File | What |
|------|------|
| `Models/ScoreTypes.swift` | `Player`, `MatchType`, `MatchFormat` + `MatchFormatConfig` (data-driven rules), `DoublesServer`, `SetScore`. **Add a match format here.** |
| `Models/MatchResumeEvent.swift`, `Stats/MatchSessions.swift` | Confirmed explicit resumes (`resumeEvents`, `parkedAt`), deterministic event union independent of scoring-body authority, point-ID anchored markers, session indices, conservative HR windows and shared session descriptions. `MatchActivityTotals` is used only in backup-excluded watch AppState; MatchRecord keeps its existing five Health-derived fields. Every record replacement/merge carries events forward; completion clears parkedAt. Pass events and full session points to health/stat builders, including when rendering a set subset. |
| `Models/MatchChronology.swift` | Pure display chronology: completed `endTime` (legacy fallback `startTime`, labelled Played), unfinished latest recorded point (fallback start), deterministic UUID ties, local-date captions and multi-day start/finish descriptions. Used by histories/retention, import/restore/backup previews, Trends and comparisons/exports. Activity-only dates keep administrative completion out of roster last-played. Never use this display policy to choose a sync body winner. |
| `Models/MatchRecord.swift` | The persisted match. Custom `init(from:)` for backward-compat decoding. **See §4 before adding fields.** Its optional `tags` and `matchTypeRevision` decode with `try?` so malformed values degrade to `nil` instead of failing the archive. |
| `Models/MatchTypeRevision.swift` | Post-completion `Doubles ↔ Singles` conversion (`MatchRecord.matchTypeRevision`): `MatchTypeRevision` (`matchType` + monotonic `updatedAt` + `revisionID` clock), commutative `merged`, `MatchRecord.convertingMatchType` / `mergingMatchTypeRevision` (completed matches only; clears resume-only doubles rotation fields and deterministically trims partner + >1 opponent tags when converted to `.singles`), `MatchTypeUpdate` (`matchTypeUpdate` wire body), and `pendingWatchUpdates`. |
| `Models/MatchTags.swift` | Match details (`MatchRecord.tags`): `TaggedPlayer` (stable id + sanitized ≤40-char name + optional free-text `playingNotes` (≤280 chars, edited in the player's Playing Style, deliberately kept OUT of `profileSummary`/AI Coach/exports and used only by the Game Plan pack's "Include playing style notes" toggle) + optional tennis playing profile stored as `handednessRaw`/`backhandRaw`/`playStyleRaw` for `PlayerHandedness`, `PlayerBackhand` and `PlayerPlayStyle` — deliberately not `Codable`, raw values pinned), `CompetitionType` (friendly/league/tournament/practice — raw values pinned; stored ONLY as `competitionTypeRaw`, deliberately not `Codable`, so a future case is "unknown" rather than an archive-killing decode error), and `MatchTags` with its own `updatedAt` + `revisionID` clock. **`tags == nil` means "no information", never "cleared"** — a clear is `MatchTags.cleared(after:)` (empty, newer). `MatchTags.merged` is commutative (equal clocks tie-break on `revisionID.uuidString`); every UI write goes through `revised(after:)` so the clock is strictly monotonic. `MatchRecord.mergingTags` applies a tag update without touching the body; `MatchTagsUpdate` is the `matchTagsUpdate` wire body; `pendingWatchUpdates(archive:watchCopies:newlyHeld:)` is the §6.1 resend rule (diff the manifest with `newlyHeldIDs` — never resend on every manifest). See `docs/features/MATCH_TAGS_PLAN.md`. |
| `Models/PointStat.swift` | `PointOutcome`, `EndingShot`, shared `ServingPointCategory` graph matching, `GameScoreSnapshot`, `PendingPointInfo`, `PointStat`. The atom from which all stats derive. |
| `Scoring/ScoringEngine.swift` | Pure scoring reducer — `pointWon(by:in:) -> ScoringResult` over value-type `ScoringState`; side-effects come back as typed `ScoringEvent`s. The watch `ScoreViewModel` delegates here. Its perspective-neutral `isRegularGameComplete` predicate is also shared by historical score reconciliation, and `leaderWhenStopped` resolves explicitly ended friendlies from sets, games, then points. **Change scoring rules here, with `ScoringEngineTests`.** |
| `Sync/MatchSyncMessage.swift` | `MatchSyncKey` (all wire keys), `MatchSyncService` protocol, codec helpers. |
| `Sync/MatchSyncPayloadBuilder.swift` | Pure construction of the `[String: Any]` WatchConnectivity payloads. **Build payloads here** (single source of the wire shape) rather than assembling dicts inline in the app/transport — keeps them round-trippable in package tests. |
| `Sync/SyncIncomingPayload.swift`, `MatchSyncTransport.swift`, `MatchMergePolicy.swift` | Decode/route incoming payloads, incl. the sanitized `.matchTagsUpdate(matchID:tags:)` event, which **both** apps route. Watch (`WatchMatchSyncService`): a stored match goes through metadata-only `StatsStore.updateTags` (never `appendMatch`/`.singleMatch`, never creates a record), and `onMatchTagsReceived` → `ScoreViewModel.applyIncomingMatchTags` merges it into `liveMatchTags` for the live match (which isn't in history); captions are read-only in `MatchHistoryView`/`MatchStatsView`. Phone (`PhoneMatchSyncService`, v1 watches never author tags): merges defensively via `PhoneStatsStore.applyIncomingTags` (tag clock + forgotten-player scrub, unknown ids ignored) and, when its own copy then supersedes what arrived — a stale echo or a scrub — answers with a `matchTagsUpdate` of the phone's tags; merge policy decides watch-vs-phone **body** winner, then merges `tags` by their own clock on every return path (the equal-`endTime` untagged-watch-copy hazard, MATCH_TAGS_PLAN.md §3) and `merge(…forgottenPlayers:)` scrubs forgotten players. Any new merge site must do the same. |
| `Sync/LiveScoreboardStatus.swift` | Pure rule for the iPhone live scoreboard and its browser mirror: LIVE or WAITING FOR WATCH, whether swipes and category actions run, and the matching copy. Reachability doesn't prove the score is current, so the copy only ever calls it the last score received. |
| `Sync/MatchStorageLocation.swift` | Pure derivation of where a match lives (`both` / `phoneOnly` / `watchOnly`) from the watch's reported id manifest vs the phone's store. Drives the iOS storage-location indicators. |
| `Sync/WatchMirror.swift`, `WatchHistoryCap.swift` | Pure merge/prune rules for the phone's mirror of the watch's rolling history; `WatchHistory.cap` (25) lives here so the watch (enforces) and phone (explains) cite one number, along with `recordsForPush`, which keeps an in-progress copy of the live match out of full-history pushes. |
| `Sync/ArchiveBackupPolicy.swift` | Pure one-way iCloud backup policy: builds outbound snapshots from the phone archive (stripping the five HealthKit-derived fields to comply with App Store Review Guideline 5.1.3(ii)), handles the one-time initial restore before the local archive is initialized (using `isInProgress`, so completed draws remain final), and defines `BackupPreview` (record count + newest date, used for the restore prompt). Used by `PhoneStatsStore`. |
| `Persistence/HealthSidecarPolicy.swift` | Pure split/merge policy for the phone's local archive: projects exactly the five HealthKit-derived fields into a backup-excluded sidecar and reconstructs full records in memory without overwriting existing non-nil Health values. |
| `Persistence/ManualMatchArchiveBackup.swift` | Versioned full-fidelity JSON codec + merge/replace policy for the iPhone Settings > Backup & Transfer manual archive export/import. Manual exports intentionally include HealthKit-derived fields and must stay separate from iCloud backup policy. Carries an optional `forgottenPlayers` ledger (additive within schema 1). |
| `Persistence/ForgottenPlayerLedger.swift`, `MatchNotes.swift` | "Forget player" deletion intent (player UUIDs only, never names): unioned on every merge/restore/import (`nil` can't erase it) and `scrubbed(_:now:)` from every inbound record regardless of timestamps, stamping a newer revision so the cleaned copy wins and is resent. `MatchNotes` is the pure codec/policy for the iPhone-only private notes sidecar (`MatchNote` keyed by match UUID, own revision clock, empty = clear, 4,000-char sanitizer, strict versioned codec that THROWS on corrupt/newer files — never treat as empty). Notes are never a `MatchRecord` field, so they can't reach sync, iCloud, HTML or AI implicitly. |
| `Stats/MatchExportDetails.swift` | What an export may carry from the match details: competition, names, non-PII tennis playing profiles (`opponentProfiles`/`partnerProfile`), quoted private note, head-to-head. **Names and the note are applied at construction** (a value built with names/notes off never holds them), so no text/AI/HTML builder can leak what was excluded — keep it that way; do not read `record.tags` or `MatchNotesStore` inside a builder. Builders default to `details: .none` (shares nothing). Also owns the AI `## Match Context` (names quoted, non-PII playing style included even when names are withheld, note labelled as data not instructions), reader-framed HTML side names, the opponent-side head-to-head flip and `MatchExportDisclosure` copy. `ManualMatchArchiveBackup.Archive.notes` is the optional, default-off archive notes section (omitted = no information). |
| `Stats/MatchStatsSummary.swift` | Derives serve/return/break/error/rally stats from `[PointStat]`. The reporting core. Winner/error ratios are typed `RatioStat` (`.formatted` for display), and it additively exposes categorized-only won/lost/service-point totals — the denominators the Trends metrics below divide by so an untracked point can't silently improve a rate. |
| `Stats/MatchTrendSample.swift`, `TrendMetric.swift`, `PerformanceTrends.swift` | Cross-match performance trends (the archive-screen Trends feature). `MatchTrendSample.init?(record:)` (also carrying `competitionTypeRaw` + `opponentIDs` for `TrendFilter`'s competition-type and opponent filters — raw string so an unknown future case never reads as untagged) reduces one eligible match to recorder-framed raw counters via a single `MatchStatsSummary(focal: .me)` — never a second counting pass, and never `opponentForcedErrors` read backwards as "forced errors I was forced into" (it means the reverse). `TrendMetric` is the data-driven metric catalogue, with `rawPair(in:)` (for pooling, unguarded) split from `ratio(in:)` (for plotting one dot, denominator-guarded) so a flawless zero-error match's winners aren't discarded when pooled. `PerformanceTrends` filters **before** windowing, pools as Σnum/Σden (never a mean of per-match rates), and orients every delta by the metric's `betterDirection` so a falling double-fault rate is always `.improving`. `TrendMetric.headline` — the archive card's four rows — reads as "what, among the things I control, is improving or slipping?", running from the points given away to the points taken (double faults, unforced errors, forced errors caused, winners); W:UE was cut from it and lives on in the Attack group. **`startsHidden` is therefore not a plain alias of `isOpponentFramed`**: `forcedErrorsCaused` stays opponent-framed (that is what earns it the dashed line paired with `forcedErrorsConceded`) but must not start hidden in the chart its own headline row taps through to — so changing `headline` changes what the Errors chart shows by default. The catalogue also carries 4 **fatigue** metrics (one group) plus 8 **per-serving-side rally-depth shares** in their own "Rally Depth — By Service" group, and the one non-percent `Unit` case they need (`.steps`) — a metric's unit **is** the axis it belongs on, which is what `TrendChart` buckets by. Their counters are projections of the SAME summary (`stepsTimeline`, `rallyDepthOnServe`/`OnReturn`, never a second pass); every one `rawPair`-gates to `nil` below its coverage threshold so a Health-free or pre-`endingShot` match leaves a gap, not a zero; the steps figures come from the sampled timeline and **never** `StepsSeries`' `totalSteps` fallback (which would make steps-per-point a constant by construction); and `MatchTrendSample.setSlices` carries one slice per COMPLETED set (a match that never reached a second set ⇒ empty — that bar counts the set in play too, so a live match in its second set still plots its finished first one; only the set in play is dropped, which is what makes the screen's include-in-progress toggle mean something here; each set's opening step delta dropped as non-comparable), flagging the decider `isDecidingTiebreak` when the FORMAT plays it as a super-tiebreak — `.standard`, the **default**, does — so it plots as its own series and colour rather than being pooled with true third sets, and gates at 10 points rather than 20. **The rally split is on `PointStat.server`, never `EndingShot.serve`** — that case is the *phase* a point ended in, so a point ending on the return shot is still a point you served. The catalogue was cut from 13 metrics over two passes; `HEALTH_TRENDS_PLAN.md` §3 records what went and why — read it before adding one back. See also `docs/features/PERFORMANCE_TRENDS_PLAN.md`. |
| `Stats/PlayerRoster.swift`, `OpponentDirectory.swift`, `MatchComparison.swift`, `MatchComparisonFormat.swift` | `MatchComparisonFormat` owns the comparison/head-to-head wording ("60% — 12/20", "Not recorded", "+5 pts", "3–2 in 5 matches · last 3: W W L") — the AI prompt must reuse `headToHeadSummary` so on-screen and AI scope match. Derived-from-archive roster (no roster store): `PlayerRoster.entries/suggestions/existingEntry`, `reconcilingEditorSlots` (keeps open Match Info drafts aligned across roster edits/merges/forgets without disturbing unsaved new players), and the rename/`updatingDetails`/merge/forget mutations (each returns `RosterMutation` with re-stamped tags + `affectedMatchIDs`; both rename and details edits preserve the player's latest resolved name + profile across every match), `OpponentDirectory` (opponents-only entries resolved from the full roster + unique doubles `Matchup`s), `Matchup` (singles: one opponent; doubles: unordered opponent pair + same partner — incomplete ⇒ `nil`, never a rematch), `MatchResult` (nil while in progress), completed-only `HeadToHead` (singles/doubles never pooled; partner ≠ opposition). `PreviousMatchBaseline.select` (rematch / noRematch / sameType / noHistory; current UUID excluded; (start, id) order) and `MatchComparison` read every rate through `TrendMetric` over an UNGATED `MatchTrendSample(record:summary:)` (internal) — same denominators and `betterDirection`, `nil` = "Not recorded", serve/return splits need some outcome tracking. |
| `Stats/PointGamesScore.swift`, `PointMatchScore.swift`, `SetScoreLabel.swift` | Derive the trustworthy full match score before each tracked point, plus reducer-derived scores after the rally for graph inspection, and format set/game scores once for iOS, text export, and HTML. `PointGamesScore` reconciles reset-derived games with stored scores and suppresses suffix-only histories; any final-point credit must first prove that the point completed its game. See `docs/features/POINT_MATCH_SCORE_PLAN.md`. |
| `Stats/RecCoachInsights.swift` + `RecCoachInsights+Exertion.swift`, `PulseCoachInsights.swift`, `SetActivitySplit.swift`, `HRZone.swift` | Coaching/heart-rate analytics. `HRZone.isUsableBirthYear` tells "calibrated" from "running on the 190 bpm default" without comparing the resolved value against 190 (also a legitimate age-derived result). |
| `WebExport/` (`MatchWebViewModel.swift` + `…+Build.swift` + `…+Comparison.swift` + `…+AICoach.swift` + `…+Promo.swift`, `MatchHTMLExporter.swift`, `MatchWebStaticFallback.swift`, `MatchWebTemplate.swift`, `WebExportColors.swift`) | Self-contained **interactive HTML match export** — a pure `Encodable` view-model (both me/opponent perspectives flattened, recorder-only HR/steps, + per-set `filters` (All / Set N) each with a reader-framed TV-style Me-vs-Opp `comparison`, points-won header, and duration rows, + an optional `aiCoach` block, mirroring `MatchDetailView`) + assembler + the viewer (HTML/CSS/dependency-free SVG-JS) kept as Swift **raw-string constants** (no resource bundle, no pbxproj edit). **Reader-framed, two files:** `make(from:maxHR:perspective:)` / `html(for:perspective:)` build the page for the recorder (`.me`, the default) or for their opponent (`.opponent`), and the share menu's "Interactive Web Page" submenu offers **My Perspective / Opponent's Perspective**. Every "me" field (result, scores, `PointVM.server`/`winner`/`cumulativeMe`, chips, score labels via the `focal:` parameter on `GameScoreLabel`/`PointMatchScore`, comparison, points-won) is the *reader's* side, so the static fallback and JS need no perspective logic and the no-JS preview and interactive rebuild can't disagree. The recorder's HR/steps stay in the opponent's file (labelled "Opp" by the viewer via the top-level `perspective`), but zone win rates and PulseCoach are recorder-file-only — `presentFields(.opponent, includesRawPoints: true)` is exactly that set. There is still **no perspective toggle** inside a page; it mirrors the iOS archive detail: `PointsGraphView`-style outcome, Serving, and ending-shot count pills drive the chart, regular/tiebreak bands share the iOS palette, pointer capture supports click/touch dragging across points, a **Stats/Points tab toggle** + **All/Set N set filter** switch the lower content, and the point-by-point list shows the full pre-point match score plus reader-relative 🎾 Serving / racquet Receiving status (`PointVM.matchScoreLabel` + `PointVM.isTiebreak`, schema v12; graph popups use separate after-point game/match labels). An **AI Coach card** (mirrors `AICoachSheet`) copies the prompt + offers opt-in AI-app launch links. Derivation stays in tested Swift; the JS only paints. **AI prompt text is injected** (`MatchHTMLExporter.html(for:perspective:aiPromptMe:aiPromptOpponent:)`; the opponent's file embeds only `aiPromptOpponent`) from `MatchExporter.aiPromptExport` by `MatchDetailView` — the only place outside Core's tested derivation. The page loads zero external resources on open; the AI links and the App Store / website links in the "Tracked with DeuceMate" strip that leads the page (`MatchWebViewModel+Promo` — the one place the export names those URLs) are user-clicked navigations (a refined `MatchWebExportTests` invariant — no `src=`/`<link>`/`@import`/CDN, and every `https://` pinned to an exact allowlist by `assertOnlyOptInLinks`), and a `default-src 'none'` Content-Security-Policy meta in `MatchWebTemplate.head` enforces that in the browser too (inline script/style only — keep it in step if the viewer ever needs a new source type). **Progressive enhancement:** `#root` ships pre-filled with a static report from `MatchWebStaticFallback` (header + four server-rendered SVG momentum charts — one per preset: Points Won/Lost + Ending Shots All Won/Lost, each with scatter + colour/label/count pills — + the TV-style Me/Opp split-bar comparison for the whole match plus a per-set breakdown) so no-JS previews (iOS Quick Look, local-file opens) aren't blank; the viewer JS does `root.innerHTML = ""` and rebuilds. `staticChartSVG` mirrors the JS `buildSVG`/`stepPath`/`symbol` geometry, and `pointsWonBar`/`comparisonCard`/`splitBar` mirror the JS comparison bars — keep them in step. HR is always the recorder's (mirrors `MatchExporter`). Bump `MatchWebViewModel.currentSchemaVersion` when the JSON shape changes (now **14**: session summaries, resume markers and per-point/session health series; schema 13 introduced `Meta.competitionTypeLabel`, reader-framed `readerSideNames`/`otherSideNames` — empty unless names were opted in — and `privateNote`, only after the notes opt-in; the JS only paints, the static fallback mirrors it, and `MatchHTMLExporter.esc` also entity-escapes U+2028/9). `MatchDetailView` builds both `.html` files (`…_opponent.html`) and shares the chosen one as a file. Keep `WebExportColors` in step with `PointsGraphView`'s palette. See `docs/features/INTERACTIVE_HTML_EXPORT_PLAN.md`. |
| `GamePlan/` (`GamePlanScope.swift`, `GamePlanEvidence.swift`, `GamePlanPackBuilder.swift`, `GamePlanText.swift`, `GamePlanTokenEstimator.swift`) | Opponent Game Plan (`docs/features/OPPONENT_GAME_PLAN_PROPOSAL.md`). `GamePlanEligibility` picks evidence by the opponent's UUID in **opposition** tags only (partner ≠ opposition; forgotten ⇒ none; doubles and, unless opted in, unfinished checkpoints are disclosed exclusions), `GamePlanSelection` resolves Last N / All / custom AFTER filters by `startTime` desc + UUID, and `GamePlanCompetition` keeps Unspecified apart from unrecognised raw values. `GamePlanEvidence` is the export boundary: it health-strips every record before deriving anything, holds names/notes only when opted in (notes also only for selected, non-omitted matches), reads rates through `TrendMetric` with `MatchComparison.requiresOutcomeTracking`'s categorized-only serve/return rule, and pools Σ/Σ. `GamePlanPackBuilder` only sees that projection — never a `MatchRecord` — and never truncates: Summary only is labelled, parts split at match boundaries or labelled point ranges. `GamePlanTokenEstimator` is pinned to reference tokenizer counts in `GamePlanTokenEstimatorTests`; re-measure with `scripts/game-plan-token-calibration.cjs` before changing it or the pack's table shape. |
| `Settings/SettingsCopy.swift` | Single source of truth for the one-line description shown under each setting on **both** apps. Add/edit a setting's blurb here so the watch and phone can't drift. |
| `Settings/MatchSetupDefaults.swift` | The remembered "last used" match setup (format + singles/doubles) the watch start screen pre-applies so Start Match doesn't re-ask what almost never changes. `resolve(formatRaw:typeRaw:)` is a total decode — absent/empty/retired raw values fall back to `.standard`/`.singles`. Watch-local `UserDefaults` keys only (`defaultMatchFormat`/`defaultMatchType`, §0 exception) — no wire key, no phone sync. See `docs/features/MATCH_START_UX_PLAN.md`. |
| `Settings/MatchTrackingStatus.swift` | The pre-match "what will this match record?" rule: point tracking (format-aware — `—` when `MatchFormat.config.disablesPointTracking`), Health access, and Pulse Coach resolved to `.on`/`.partial`/`.off` plus label, SF Symbol, and fix-it copy. `HealthAccess` is the portable mirror of the HealthKit permission (the watch maps `HKHealthStore` onto it — Core stays HealthKit-free). `collapsingPulseWhenHealthOff(_:)` drops the redundant Pulse chip when Health is off (the strip's rule; Settings always shows all three). Drives the watch start-screen tracking strip and its settings summary. |
| `Settings/ReviewPromptPolicy.swift` | When the iPhone may request an App Store rating, judged as a match report closes: a recently completed match with categorized points, 20s of foreground attention (`ReviewAttentionTimer`), 3+ completed matches, a win or 6+ matches, once per app version and 120+ days apart. Pure and StoreKit-free. Takes no opinion-of-the-app input on purpose: choosing a good moment is fine, routing people by sentiment is not. Also owns `writeReviewURL` for the Settings row, because `requestReview` must not be called from a button. |
| `Settings/ICloudBackupCopy.swift` | The global "backed up to iCloud?" indicator (label + SF Symbol + resolution rule) shown on the iPhone archive. Six cases: `backedUp`, `notBackedUp`, `unavailable`, `restoring`, `pendingRestore` (backup found, user prompt open), `pendingUpload` (pushed but daemon not yet confirmed upload). `current(isEnabled:isAvailable:isRestoring:hasPendingRestore:isUploaded:)`. |
| `Walkthrough/WalkthroughSession.swift`, `WalkthroughFixtures.swift` | Isolated nine-situation animated guide, deterministic singles fixtures, automatic scoring/category/stats beats and Previous/Next navigation. Calls the existing scoring reducer; never constructs a `MatchRecord` or reaches persistence, transport, settings or sensors. Advanced chapters remain deferred. |
| `Walkthrough/ScoreInputAction.swift`, `ScoringChangeoverCopy.swift` | Shared watch drag mapping (20-point scoring/undo threshold; >40 and >2:1 bias for stats) and unchanged changeover reason copy. Live callers retain their modal, match-complete and tracking guards. |
| `Persistence/StatsStoring.swift` | Persistence protocol + JSON codec; both apps implement it (file-backed JSON). |

**Watch app — `DeuceMate Watch App/`:**

| File | Lines | What |
|------|------:|------|
| `ScoreViewModel.swift` | ~2215 | Live match state + synced settings; delegates scoring rules to Core's `ScoringEngine` (see §1); `resetMatch` parks the live match as resumable while `endStoredMatchAtCurrentScore` completes a chosen history checkpoint and `completeCurrentMatchIfMatching` reconciles the phone ending that same live identity; seeds/persists the remembered match setup (`applyRememberedSetupIfIdle()`/`persistMatchSetupDefaults()`, called from `loadState()`/`resetMatch()` tails and `HomeView`'s `commitServerSelection()` — never from `init`, which runs before either restore path); `trackingStatuses` resolves Core's `MatchTrackingStatus.all(...)` and forwards `WorkoutManager.$healthAccess` (not its whole `objectWillChange` — that would also fire on every live-match HR/calorie tick) into its own `objectWillChange` in `init`, so views watching only the view model still redraw on Health-access changes without extra redraws during play. ⚠️ Almost no `MARK:` anchors yet — `Grep` for the symbol and read a bounded range. |
| `HomeView.swift` | ~1010 | Match setup / start screen: a pre-match card states the remembered Singles/Doubles + format setup (hidden mid-match) and taps through to a combined Match Setup sheet, so Start Match skips straight to who-serves-first; the same card carries the Points/Health/Pulse tracking strip, and the Settings sheet opens with the always-three row form. ⚠️ No `MARK:` anchors yet. |
| `ScoreInputHaptics.swift` | ~40 | Optional wrist tap confirming an applied swipe (off by default; `swipeHapticsEnabled` syncs both ways with the iPhone Settings > Apple Watch toggle, `storeIncoming` persists the phone's value without echoing it back). Called from `ContentView.performInput` after the score changes, so iPhone score commands don't buzz and a tap always means the input counted. |
| `TrackingStatusStrip.swift` | ~140 | Paints Core's `MatchTrackingStatus`: the pre-match strip (single-line icon+state chips, each tapping to its corresponding row under "What This Match Records" in Settings, which in turn carries shortcuts to the actual controls via Core's `MatchTrackingStatus.destination(access:)`; Health prompts only while undetermined; Pulse collapsed out when Health is off) and the full-width Settings rows (always all three). |
| `ContentView.swift` | ~953 | Live scoreboard + gesture handling. |
| `MatchStatsView.swift` | ~290 | Production live/history stats wrapper, including resume, End at Current Score, and tracking controls; failed completion keeps the sheet open with an error; delegates its stat rows to value-based `Scoring/MatchStatsContent.swift`. |
| `Scoring/ScoringScoreRow.swift`, `Scoring/MatchStatsContent.swift` | ~50 / ~350 | Shared row/point feedback and stats body; values and callbacks only, no live view model. The existing court, sticky banner and changeover overlay in `ContentView` are reused too. |
| `Walkthrough/WalkthroughView.swift`, `WalkthroughViewModel.swift`, `WalkthroughCoordinator.swift` | ~534 / ~21 / ~22 | Animated guide UI/adapter and two local flags. Guide entry and first-use offer live in `HomeView`; readiness follows successful state/history reads and completion of the launch authorization callback in `DeuceMateApp`. Adapter has no production dependencies. Navigation/dismissal cancels animation tasks; fixture generations and disposal reject stale beats. |
| `Sync/WatchMatchSyncService.swift` | ~300 | Watch side of `WatchConnectivity`, including completion reconciliation sent from the phone. |
| `WorkoutSession.swift`, `WorkoutUITestRoot.swift` | | Injectable HealthKit store/session adapters for the real workout manager, including recovered builders; DEBUG-only isolated warning UI fixture (`--workout-ui-test`), no real Health/sync services. |
| `PointCategorySheet.swift`, `WorkoutManager.swift`, `MatchHistoryView.swift`, `StatsStore.swift`, `BackupExcludedFileWriter.swift`, `AppTheme.swift` | | Categorisation UI, HealthKit workout (`WorkoutManager` also publishes `healthAccess`, refreshed on foreground and in `HomeView.onAppear`), backup-excluded history/live-state persistence, theming. |

Watch history completion uses `WatchStatsStoring.completeStoredMatch` (declared in
`StatsStore.swift`): read the latest existing checkpoint, complete it and save on
the same serial queue. Only its successfully saved snapshot may be synced or
reported as success to the sheet. Never fall back to the sheet's stale record,
recreate a missing ID, or use the legacy `appendMatch` (which hides write failures)
for this operation. `StatsStoreTests` covers unreadable/missing records, write
failures, preserved bytes, and success-only sync through the real store.

Watch tests: `DeuceMate Watch AppTests/` — includes `WalkthroughWatchTests`
for launch/restore eligibility, local flags, production isolation and stale callbacks. `DeuceMate_Watch_AppTests.swift` (~1.3k lines, 45 tests) holds the
high-level `ScoreViewModel` scenarios (each test owns its live-state file);
`WorkoutManagerTests`, `WorkoutFinalizerTests`, `MatchSessionsWatchTests` cover
production-manager save/recovery/error paths and session accumulation;
`WorkoutWarningUITests` uses `--workout-ui-test` for live/Home warnings. `StatsStoreTests`,
`MatchSetupDefaultsWatchTests`, `TrackingStatusWatchTests`, `MatchTagsWatchTests`,
`MatchTypeWatchTests` and `ScoreInputHapticsTests` cover the rest.
All need `import DeuceMateCore` (see §0).

**iPhone app — `DeuceMate/`:**

| File | Lines | What |
|------|------:|------|
| `Views/PointsGraphView.swift` | ~1.9k | Charts (points momentum + outcome/serving/ending-shot filters + HR/steps overlays), including set-relative point selection with the post-point score and serving side. Heavily `MARK:`-sectioned. |
| `Views/MatchDetailView.swift` | ~1350 | Per-match detail, stats tabs, End at Current Score for in-progress records, full-score/server point rows, share/export, and the Match Info section. The shown `record` is `@State`, re-resolved by id from `store.$history`, so edits/syncs/imports show at once; the prebuilt export snapshot is ONE `.task(id: currentExportInputs)` (record, max HR, NTRP, the names/notes toggles, note text, head-to-head) that clears every export string/URL first and drops a cancelled build — **add any new export input to `ExportInputs`**, or a stale file can be shared. Every staged file goes in that run's own `ExportStaging` generation directory (`<tmp>/MatchExports/<UUID>/<date-only filename>`), never a shared temp path: a superseded run that finishes last would otherwise overwrite the newer published file. The run deletes its generation when superseded, and after publishing parks in `ExportStaging.waitUntilCancelled()` so the files live exactly as long as they are current (held until an open share sheet using them closes). A new staged export file must use the same generation. |
| `Views/MatchInfo/` (`MatchInfoSection`, `MatchInfoEditorView`, `PlayerPickerView`, `MatchNotesEditorView`, `MatchComparisonView` + `BaselinePickerView`, `OpponentsSection` + `OpponentsView`, `PlayersSettingsView` + `PlayerRosterActions`, `MatchTagsCaption`) | | Match details UI (MATCH_TAGS_PLAN.md §5, §7.1). Edits go through `PhoneStatsStore.updateTags` (store stamps the draft — never pre-stamp in a view) then `PhoneMatchSyncService.pushTagUpdates(forMatchIDs:)`; roster mutations likewise via `PlayerRosterActions`, and forget also `rescrubMirror()`s. **User edits are all-or-nothing:** `updateTags`/`renamePlayer`/`mergePlayers`/`forgetPlayer` throw `TagEditError.notPersisted` and roll the in-memory archive + ledger back when the canonical write fails (or writes are suspended after an unreadable launch read) — the caller must not push, dismiss, or delete notes; it shows the error and stays open. Match Info starts collapsed and remembers the phone-local `matchInfoExpanded` preference. Competition Type uses a two-column choice grid (full-width rows at accessibility sizes) with a checkmark; tapping the selected choice clears it. Empty player slots preview four recent roster entries, excluding forgotten/occupied identities, before Search or add player opens the full picker; players can be managed directly from `PlayerPickerView` rows and `MatchInfoEditorView` slots (`PlayerManageView` for roster players, inline draft profile/name editing for unsaved players, reconciled via `PlayerRoster.reconcilingEditorSlots`). `OpponentsView` opens with a condensed, header-less Playing Style card (centred, display-only chips for handedness/backhand/play style — editing is via the gear; notes capped at 3 lines, tap to expand), then singles/doubles Head to Head, Prepare Game Plan, Pending Matches and Past Matches last; Rename or Manage Player is a persistent top-trailing gear (`opponent-manage-player`) navigation link. It omits `Pending Matches` and `Head to Head · Doubles` when empty. Selection changes only the draft until Save. `PlayerManageView` (a roster player, on every match) autosaves its profile when picked and its name when editing ends or on Back, with no save buttons; `DraftPlayerManageView` (not yet in the archive) stays on the Match Info draft until Save. `MatchNotesEditorView` fills the available height, keeps the character count directly under the input and Delete Note at the bottom above the keyboard, and opens its longer storage explanation from Privacy and storage. It autosaves after a pause in typing and on Done and backgrounding, blocks swipe-down while any text is unsaved, and has no Save or Cancel. The editor sheets are presented by `MatchDetailView` (bindings into `MatchInfoSection`): a `.sheet` attached inside the List did not present. The comparison resolves both records by UUID from `store.history` every render and formats via Core `MatchComparisonFormat`. Archive-row subtitle lives in `MatchTagsCaption`, not `PastMatchesView` (TECHNICAL_DEBT #13). **Exports (PR 4):** `MatchDetailView` keeps two share-menu switches — Include player names (ON) and Include private note (OFF, only enabled through `NotesExportReviewSheet`) — inside `ExportInputs` together with the note text and head-to-head, so any change clears and rebuilds every cached string and staged file; an included note joins the health alert (`MatchExportDisclosure.combinedMessage`). `AICoachSheet` has its own names/note switches (both OFF each open) and rebuilds from a pure closure. Filenames come from `ExportFilenames` (start time only). Settings' archive export is `ArchiveExportOptionsSheet` (notes default OFF, exact preview); import restores notes only into `MatchNotesStore.importNotes`. |
| `Export/MatchExporter.swift` | ~630 | Plain-text + AI-prompt export. `nonisolated static` builders by section. |
| `Export/ExportStaging.swift` | ~110 | Per-build staging directories (`<tmp>/MatchExports/<UUID>/`) for the files `MatchDetailView` shares; see its row above. Pure file policy, unit-tested in `ExportStagingTests`. |
| `Views/PastMatchesView.swift` | ~910 | iPhone archive list (phone-side analogue of the watch `MatchHistoryView`); shows storage-location + iCloud indicators; hosts the Trends section (below). Permanent-delete confirmation uses a non-publishing row-frame cache (geometry changes must not rebuild the List mid-swipe). Row and overlay measurements both use global coordinates; the List's named coordinate space would not reach an overlay outside that modifier. The popover presenter stays mounted, attaches to a one-point view **before** `.position` expands its layout bounds, and retains its captured origin through dismissal. The swipe's red Delete button must have **no destructive role**: it only requests confirmation, so UIKit must not optimistically remove the row. Only the confirmation performs deletion. Substantial Trends content remains in `Views/Trends/` per TECHNICAL_DEBT #13. |
| `Views/Trends/TrendsSection.swift`, `TrendsSamples.swift`, `TrendsView.swift`, `TrendChart.swift`, `TrendSparkline.swift` | | Cross-match performance trends UI: `TrendsSection` is the archive-screen headline — the whole card (4 sparklines) is one `NavigationLink` into the full Trends screen, the system's chevron the only affordance, with a `headlineAccessibilitySummary` collapsing the four rows into one VoiceOver announcement; below the minimum-matches threshold it's a "needs N more" line, deliberately not hidden; `TrendsView` is the full pushed screen (window/type/format filters, Rate/Count toggle, one `TrendChart` per group); `TrendChart` draws the grouped multi-line charts (`foregroundStyle(by:)` + `chartForegroundStyleScale(domain:range:)` — NOT a literal per-mark colour, which merges every metric into one connected line), the Rally Depth Mix/Win-Rate toggle, and Serve & Return's persisted Serves In/Serves Win/Returns Win filter (narrows 6 metrics to 2 at a time — no "All" option); `TrendSparkline`'s delta arrow points by `TrendDelta.change`'s raw sign (independent of the improving/declining colour), so a falling rate always points down regardless of whether falling is good or bad for that metric. `TrendChart` renders **one chart per `TrendMetric.Unit`** present in a group (percent, steps) — mixed units on one axis flatten the small-magnitude series, since Swift Charts infers a single domain; `.ratio` keeps its sparkline fallback. The **Rally Depth — By Service** group reuses Rally Depth's `stackedChart(for:)` behind an On Serve / On Returns picker, so its eight metrics cost one mode-switched chart. `TrendsView` lists it right after Rally Depth, and Fatigue after Pressure, skips any group whose every series is empty (`!groupSeries.isEmpty` is **not** the right test — a Health-free archive still returns a full series array), and captions Effort with its real step coverage. See `docs/features/PERFORMANCE_TRENDS_PLAN.md` and `docs/features/HEALTH_TRENDS_PLAN.md`. |
| `MaxHRSetting.swift` | ~33 | The phone's shared **reader** of the max-HR setting — owns the `userBirthYear`/`userMaxHROverride` `@AppStorage` literals (both also `MatchSyncKey` raw values, §5) and `HRZone.resolveMaxHR`. Read by `MatchDetailView`; `SettingsView` keeps its own declarations since it is the settings *editor* and needs write bindings. Declared non-`private` at each site: a private **stored** property (unlike a private property-wrapped one) makes a View's synthesized memberwise init private too. |
| `Views/SettingsView.swift` (~940), `ManualMatchEntryView.swift` (~449), `LiveScoreboardView.swift` (~506), `LivePointCategoryPanel.swift` (~222) | | Settings including Watch sync counts/fresh-Watch restore guidance, Match Details → Players, and Backup & Transfer archive export/import (a Replace states and then applies the private-notes `replacePlan`), manual entry, live spectator, phone-side point categorisation (mirrors the watch sheet when iPhone Input is on). |
| `Views/GamePlan/` (`GamePlanView`, `GamePlanUpcomingView`, `GamePlanEvidenceView`, `GamePlanContentsView`, `GamePlanAdvancedView`, `GamePlanBuild`, `GamePlanMatchPickerView`, `GamePlanNotesReviewView`, `GamePlanPreviewView`) | | Prepare Game Plan, pushed from `OpponentsView`'s opponent detail. The main screen is ready on arrival: one summary row each for Upcoming / Matches / Includes (each pushes its full controls), the Focus text, then the estimate and hand-off; Preview and Advanced (detail, delivery, size) last. Upcoming competition and format are pre-filled once per visit from `GamePlanCandidates.latestMatch` via Core's `GamePlanUpcomingMatch(prefilledFrom:)` (untagged/unknown competition stays unset, never guessed). An unfinished latest match sets `finishingMatchID`: that match is always evidence (`candidates(alwaysInclude:)` + `GamePlanSelection.resolve(_:pinning:)` — pin only while it is still unfinished), its own competition/format are stated, and the pack's brief (`GamePlanFinishing`: saved score, next server, recent points) and Coaching Request switch to finishing it. Unfinished matches are evidence by default on the iPhone (Core's `candidates` default stays opt-in). Session-local `@State` only (no store, no sync, no wire key). `GamePlanBuildInputs` is the build identity — selected records, roster entry, notes of selected matches, upcoming context, every inclusion choice — and one `.task(id:)` clears the old pack, debounces, builds off-main in its own `ExportStaging` generation and deletes it when superseded (held while a share sheet uses it). **Add any new pack input to `GamePlanBuildInputs`.** Names, playing style notes and private notes start ON; notes are left out per match through Choose Notes (`notesLeftOut`), and the Includes row states what the pack quotes. AI apps open via `AICoachLauncher.openWithoutPrefill` (never the 1,500-char URL pre-fill). Not yet mirrored in the browser demo. |
| `Views/ReviewPromptCoordinator.swift` | ~65 | Tracks the open match report and the two local request flags around Core's `ReviewPromptPolicy`. `PastMatchesView` calls `requestReview` from the report sheet's `onDismiss`, one second later, only if nothing else is presented. Flags count requests, not prompts: Apple never reports what it showed. Development builds always show the prompt and TestFlight never does, so the production show rate can't be tested. The prompt can take over 10s on a cold simulator. The browser demo mirrors the Settings rows but not this system prompt. |
| `Views/PulseCoach/PulseCoachSection.swift`, `Views/Coaching/RecCoachSection.swift`, `AICoachLauncher.swift`, `AICoachSheet.swift` | | HR coaching panel, recreational coaching insights, and routing a generated coaching prompt to third-party AI apps. |
| `Sync/PhoneMatchSyncService.swift` | ~735 | Phone side of `WatchConnectivity`; live score and category commands go through `sendLiveCommand`, never queued or retried (a failed send is ambiguous and could double-score), and anything undelivered increments `liveCommandFailureCount` for the scoreboard's message; a Watch manifest (including empty) acknowledges Sync Now, live install state refreshes through `sessionWatchStateDidChange`, and explicit record pushes made during activation are flushed once the session activates. Match tags: `pushTagUpdates(forMatchIDs:)` sends `matchTagsUpdate` only for `onWatchIDs`; §6.1 reconciliation runs after every `.history`/`.singleMatch` merge (`reconcileTags`) and on manifest arrival for `newlyHeldIDs` only (diff against the previous manifest — a manifest rides on every checkpoint); incoming `.matchTagsUpdate` is merged and answered when the phone's copy is newer; the watch mirror is scrubbed of forgotten players in `updateMirror`. |
| `Persistence/PhoneStatsStore.swift`, `Persistence/MatchNotesStore.swift`, `Audio/LiveAnnouncementService.swift`, `HealthKitHRFetcher.swift` | | Health-stripped archive plus backup-excluded sidecar, manual export/import, TTS announcements, HR backfill. `PhoneStatsStore` also owns tag edits (`updateTags` stamps a draft on its queue; `applyIncomingTags`; rename/merge/`forgetPlayer`), carries stored tags forward in `appendMatch`/`saveHistory`, and persists + backs up the forgotten-player ledger (`forgottenPlayers.json`, written BEFORE the archive and re-applied on load) which every inbound path unions and scrubs. Its `forgottenPlayers` is a main-queue mirror — read `forgottenPlayerLedger()` for a queue-consistent value. `MatchNotesStore` is the iPhone-only private-notes sidecar in its own `Application Support/MatchNotes/` directory: directory exclusion verified before every write, file exclusion reapplied after every atomic write, an unreadable/corrupt/newer file suspends ALL writes (never treat as empty), note text never logged, never on `MatchRecord`. Permanent match deletion (`PastMatchesView`) also removes the note. |

**Browser replicas (`docs/website/try.html`).** `docs/website/assets/watch-demo.js` (live match, a JS port of `ScoringEngine`), `watch-demo-app.js` (home / setup / settings / guide / warm-up shell), `watch-demo-history.js` (Past Matches) and `watch-demo-guide.js` (animated guide) mirror the watch views; sensors (heart rate, kcal, steps, compass) are invented. A change to `HomeView`, `ContentView`, `MatchHistoryView`, `MatchStatsView`, the Walkthrough, `SettingsCopy` or `MatchTrackingStatus` should be mirrored there — see `docs/features/INTERACTIVE_DEMO_PARITY_PLAN.md` (Phase 7).

The companion replica uses `phone-demo.js` (archive, shared live scorer, browser
persistence and simulated device services), `phone-demo-settings.js` (settings,
manual entry and demo archive transfer), `phone-demo-reports.js` (details, graphs,
coaching and report data), `phone-demo-export.js` (native report data adapter and
complete text/AI prompt builders), `phone-demo-native-export.js` (generated native
viewer, stylesheet and coaching instructions),
`phone-demo-trends.js` (native metric catalogue, coverage, pooling and UI),
`phone-demo-matchinfo.js` (Match Info: players with playing profiles, competition,
autosaved private note in its own storage key, previous-match comparison, head-to-head,
completed-match Singles↔Doubles conversion; the Watch replica's `watch-demo-history.js`
shows the same tags caption read-only and offers "Change to …"),
and `phone-demo-coaching.js` (pure Rec Coach and Pulse Coach rule ports).
Phone score commands go through the **existing watch instance**, gated by input,
reachability and match identity. Do not introduce a second live scoring engine.
The standalone report embeds the actual `MatchWebTemplate` viewer and CSS. Run
`node scripts/sync-iphone-demo-exports.cjs` after changing that template or the
native coaching instructions; `--check` detects drift. All AI copy/download/web
paths use the same full prompt builder, including every saved raw-point row.
Demo JSON archives are deliberately identified separately
from native match backups. Browser storage and sensor data are simulations;
AI launch buttons never contact external services. See
`docs/features/IPHONE_DEMO_PARITY_PLAN.md` for implementation and verification
status. Run `node scripts/iphone-demo-model-qa.cjs` and
`node scripts/iphone-demo-coaching-qa.cjs` for dependency-free model checks.
The home page's Try section (`assets/home-demo.js`) loads this same demo from
`try.html` only when a visitor asks for it: never duplicate the markup or asset
list in `index.html`, and never add `.reveal` or a transform around it, which
would break the phone's fixed-position layers. The demo's stylesheets load into
the home page, so an unscoped selector in them can restyle it (`.chip`, `.ic` and
`.sw` already did). `scripts/home-demo-qa.cjs` fails if opening the demo changes
anything outside the section (same `PLAYWRIGHT_MODULE`; it starts its own local
server, since the page reads `try.html` over HTTP).
Run `scripts/iphone-demo-qa.cjs`, `scripts/iphone-demo-extended-qa.cjs`,
`scripts/iphone-demo-state-qa.cjs`, `scripts/iphone-demo-visual-qa.cjs` and
`scripts/iphone-demo-popup-qa.cjs`, `scripts/iphone-demo-matchinfo-qa.cjs` and `scripts/iphone-demo-export-qa.cjs` with an externally installed Playwright
package (`PLAYWRIGHT_MODULE=/path/to/playwright`). Set `PLAYWRIGHT_BROWSER=webkit`
for Safari-engine checks; the default is Chromium. Extended QA saves screenshots
under `/tmp/deucemate-iphone-qa`. Browser launch may need sandbox escalation on
macOS. Syntax and model tests do **not** prove visual or interaction parity.
The inline phone graph stays clean; filters and overlays belong in its expanded
dialog. Static export SVGs must set essential appearance attributes themselves
because offline exports do not load the website stylesheet. Handled phone keys
must stop propagation: a render can detach the event target before the Watch's
document listener checks its ancestry, otherwise one key can score twice.
Gesture release listeners must also survive court replacement during a Watch
echo, and must reject a changed match identity or a closed scoreboard.

For visual parity use the current SwiftUI views and the saved iPhone captures
in `docs/website/screenshots/setup/`. The archive uses primary-color scores with
separate result pills, top-aligned date/status/storage badges, and native grouped
sections; detail uses a gray sheet surface, an in-header end action, and a clean
inline graph. Settings themes are a two-column card picker, not a select menu.
Trends and the report below the graph also have native capture references in
`docs/app-store-screenshots/iphone-6.9/03`–`07`. Trends uses segmented controls,
right-side chart axes and two-column legends; report comparisons use split bars
in separate grouped sections. The expanded graph is an in-phone full-screen
cover with a fixed chart and separately scrolling controls. Its inner surface
keeps the full phone height while the outer dialog clips to the visible viewport;
page scrolling must move the graph with the phone without resizing its chart.
Every phone popup uses the shared `showSheet` presenter
(sheet / menu / actions / popover / alert / cover),
bounded by the frame AND the visible viewport, with phone-local dimming. Never
use browser `alert`/`confirm` or viewport-centred modal sizing. Popups must follow
the frame on resize/scroll, including `visualViewport`, and release observers on
dismissal. Size observers must only reposition the popup: revealing the phone
again when its visible popup height changes makes webpage scrolling snap back.
A queued close event must not clear a newly opened presentation.
AI Coach mirrors `AICoachSheet`'s grouped app rows/perspective/Other sections;
its prompt hand-offs remain simulated. Archive replacement uses an in-phone
alert with the same destructive confirmation, never `window.confirm`.
The report share menu mirrors `MatchDetailView`: Interactive → Interactive Web
Page → My/Opponent's Perspective, then My Stats / Opponent's Stats with Share
Summary and (only with saved points) Share Summary + Raw Points. Its compact
material menu is undimmed and anchored to the toolbar. Extra formats and previews
live under Demo controls → Browser export tools. Sharing disclosure follows
`HealthExportConsent.presentFields`, including the opponent summary/raw-point
distinction, and uses the native Cancel / Share buttons.
Manual Entry mirrors the native grouped form: plus/minus steppers, date/time
pills, footer text outside cards, and a single Cancel in the leading toolbar.
Manual entry is the Matches toolbar pencil only; native Settings has no such row.
Rotation mirrors the native app, which is portrait-locked except the live
scoreboard: the external Rotate iPhone control is disabled on every other screen,
`setOrientation` refuses landscape off `live`, and leaving it returns to portrait.
On touch devices the real device orientation drives it (landscape enters on the
live screen, portrait leaves) and the portrait Rotate button is hidden; the frame
also has an in-frame Exit landscape pill and a click-away backdrop. The live
scoreboard mirrors `LiveScoreboardView` (LIVE or WAITING FOR WATCH badge, close, white ME/OPP names,
set/game columns, 8-slot momentum badge, format label, hint only with iPhone
Input and a reachable Watch); the non-native command buttons and status notes live in a visually
hidden, keyboard-reachable `.phone-live-extras`. Landscape must remain wider than
tall even in a portrait browser, fit both player rows, and retain Watch-owned
swipe/keyboard scoring. Navigation clears old transient notices so they cannot
obscure the live court. Popups follow the rotated device through the presenter.
Gesture capture belongs to the stable chart stage, not its replaceable SVG.
Only meaningful scorer/settings/history changes should redraw the phone — a
Watch timer refresh must not replace the court during a swipe. Report activity
scoping mirrors `SetActivitySplit`; keep the model QA cases in step.
Graph category symbols and filter-aware inspector badges mirror the native
scatter mappings. Inspectors show set-local point numbers, cumulative totals
including the selected rally, and after-point scores; sparse sampled steps use
the same `graphSteps` helper as the chart. Keep serialized offline helpers in
step. Archive swipes reveal confirmed Delete for every storage type; only the
recoverable Remove from Watch action may execute on a full swipe. Settings and
archive Sync Now share one handler so pending/failing sync cannot report success.
The phone follows system light/dark appearance, including open popups; dispose
the appearance listener with the presentation's other observers. End-at-score
uses the observed native undimmed material popover, cancelled outside or with
Escape. Permanent deletion uses the selected row's midpoint as its popover
anchor, with an explicit Cancel and destructive confirmation. Opt-in native
parity fixtures/tests and repeat commands are documented
in `docs/features/IPHONE_DEMO_PARITY_PLAN.md`; they seed only a disposable iOS
simulator through the normal importer and never add production launch hooks.
Scope every new demo section: the marketing site's global `section` padding is
64–88px and otherwise silently leaks into the phone layout. CSS-generated icon
text affects accessible names; prefer aria-hidden SVGs or explicit button labels.

Coaching Insights ranks candidates and suppresses overlapping topics before taking
three. Its input must be the full history, including unclassified points: filtering
first defeats coverage checks and can bridge missing rallies in exertion analysis.
Pass `matchType` only where recorder Health coaching is allowed; exertion is
singles/recorder-only because `PointStat.server` identifies a team in doubles.
Opponent HTML exports suppress recorder Health coaching in BOTH perspectives.
Mirror rules and ranking in `phone-demo-coaching.js`, and formatting in
`RecCoachSection`, `MatchWebTemplate` and `phone-demo-reports.js`; regenerate
`phone-demo-native-export.js` after template changes. The optional
`COACHING_PARITY_OUTPUT=/tmp/coaching.json` environment variable on `swift test`
writes fictional fixtures from `RecCoachRedesignTests`; pass that same variable to
`node scripts/iphone-demo-coaching-qa.cjs` to compare native/browser output.
See `docs/features/COACHING_INSIGHTS_PLAN.md` for thresholds and limitations.

Feature design docs live in `docs/features/*.md` — read the relevant plan before
extending sync, changeover, or the companion app. The prioritised improvement
backlog is `docs/features/TECHNICAL_DEBT.md` — **open items and their detail
come first, ranked; completed and parked work is archived at the bottom of that
file** with its original write-up intact. Item numbers are permanent and cited
from here (#3, #9, #13, #18), so they are never renumbered. Check it before
starting a refactor so you don't re-discover, or contradict, a documented
decision — including one already closed in the archive.

App Store working docs live in `docs/release/` — `APP_STORE_METADATA.md` (store
copy, App Review notes) and `SUBMISSION_REVIEW.md` (pre-flight review, blockers,
device evidence). Security reviews live in `docs/security/`. Marketing, SEO, and
GEO plans/trackers live in `docs/marketing/`.

⚠️ **`docs/website/` — and only `docs/website/` — is the published GitHub Pages
site.** It serves the App Store Marketing, Support, and Privacy URLs, so those
URLs must not move. `.github/workflows/pages.yml` uploads that one folder as the
Pages artifact; its `path:` **is** the publishing boundary. Everything else under
`docs/` (architecture, audits, features, marketing, release, security, USER_GUIDE,
the screenshot capture guide, app-store-screenshots) is unreachable by URL, with no
exclude list to maintain.

Practical consequences:
- A new internal doc anywhere under `docs/` is private by default. Put it in the
  subfolder that fits; nothing else is needed.
- A file added to `docs/website/` **is** published the moment it merges. That
  folder is the site, not a docs folder — keep guides, notes, and READMEs out.
- The site is plain static HTML: no front matter, no Liquid, no Jekyll. There is
  no `_config.yml` any more (the legacy `/docs` build and its exclude denylist
  were replaced by the artifact allowlist).
- The marketing screenshots live in `docs/website/screenshots/` because the site
  shows them; the capture guide that documents them stays at
  `docs/screenshots/README.md`, outside the published folder.
- The README gallery's images live in `docs/readme/`, outside the published
  folder, so they don't ship with the site. Their capture and build steps are in
  the same guide.

---

## 3. Build & test (run locally on macOS)

No CI builds or tests this project (the only workflows are a PR placeholder and
the Pages deploy — §0). Run tests locally from Xcode or from a Mac CLI
when `xcodebuild` is available. `swift test` also works for the Core package.
If the active environment lacks the Swift/Xcode toolchain, skip command
execution and verify statically instead (§0).

```bash
# Shared package (pure logic — where new tests usually belong).
# The package exposes a single auto-generated scheme, `DeuceMateCore`, whose
# test action runs DeuceMateCoreTests. `swift test` in the same directory works too.
cd DeuceMate/Packages/DeuceMateCore && \
  xcodebuild test -scheme DeuceMateCore \
  -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO

# Watch app tests
xcodebuild test -project DeuceMate/DeuceMate.xcodeproj \
  -scheme "DeuceMate Watch App" \
  -destination "platform=watchOS Simulator,name=Apple Watch Series 9 (45mm),OS=latest"

# iPhone app build
xcodebuild build -project DeuceMate/DeuceMate.xcodeproj \
  -scheme "DeuceMate" -destination "platform=iOS Simulator,name=iPhone 15,OS=latest"

# iPhone unit + UI tests (the shared DeuceMate scheme includes both targets).
xcodebuild test -project DeuceMate/DeuceMate.xcodeproj \
  -scheme "DeuceMate" -destination "platform=iOS Simulator,name=iPhone 15,OS=latest"
```

**Logic changes require tests** (`CONTRIBUTING.md` rule). Put them in
`Packages/DeuceMateCore/Tests/DeuceMateCoreTests/` — that target is the cheapest
to run and is pure logic. Mirror the existing one-file-per-subject naming
(`MatchStatsSummaryTests.swift`, `MatchMergePolicyTests.swift`,
`MatchSyncRoundTripTests.swift`, `MatchStorageLocationTests.swift`,
`SettingsCopyTests.swift`, …).

**Tests exist for Xcode, not GitHub.** Nothing runs them on push — but the test
suite is still the correctness record for the owner running Xcode locally. Keep it strong.
- ✅ **Add** tests / **strengthen** assertions — encouraged (and required for
  logic changes, above).
- ✅ **Update** a test for behaviour you changed *on purpose* — fine; say so in
  the PR.
- 🚩 **Delete, `XCTSkip`, loosen assertions, or rewrite expected values** so a
  failing test passes — **requires explicit human approval** and a stated reason
  in the PR. Fix the code, or surface the failure and ask.

---

## 4. Recipes for multi-site changes (easy to get partially wrong)

These are the changes where a partial edit compiles (or silently misbehaves) but
is wrong. Touch **every** listed site.

### Add a field to `MatchRecord` (or `PointStat` / `PendingPointInfo`)
Persisted JSON must decode old data forever. Update **all** of:
1. The stored `public var`/`let`.
2. The memberwise `init(...)` — add a parameter **with a default** + assignment.
3. The custom `init(from decoder:)` — add
   `x = try c.decodeIfPresent(T.self, forKey: .x) ?? <default>`.
   **Never** use plain `decode` for a newly added field, and **never** make an
   existing optional field non-optional — both break decoding of archived matches.
4. `encode(to:)` and `CodingKeys` are auto-synthesised from stored properties —
   do not hand-write them unless one already exists.
5. Add/extend a test in `MatchRecordCodingTests.swift` (round-trip + decode of
   old JSON without the new key).

### Retire a case in a persisted enum  ⚠️ never delete — the schema is additive-only
`MatchFormat`, `MatchType`, `Player`, `DoublesServer`, `PointOutcome` and
`EndingShot` all reach persisted JSON — `appState.json`, `matchHistory.json`, the
phone's canonical archive, its iCloud backup copy, and the WatchConnectivity wire
format. **Removing or renaming a case is a breaking schema change, not a
refactor.** None of them has an unknown-value fallback in its `Codable`
conformance, and `decodeIfPresent` does *not* protect you: it returns `nil` for a
*missing* key but **throws** for a key that is present with an unrecognised raw
value.

The blast radius is the whole file, not the one record: both archives decode
`[MatchRecord]` in a single `decode` call, so one point in one old match fails the
decode of every match. On the phone that quarantines `matchHistory.json` to
`.corrupt` and shows an empty archive; on the watch `loadHistoryOrNil()` returns
`nil`, which correctly refuses to overwrite but also silently stops appending new
matches.

**To retire a case, keep it decodable and hide it:**
1. Leave the `case` and its raw value in place, permanently. Mark it
   `@available(*, deprecated, message: "Retired <date>; kept for archive decoding")`
   if you want compiler pressure at *write* sites.
2. Remove it from the user-facing list, not from the type — the existing pattern
   is `PointOutcome.userSelectable`, a hand-written subset that keeps
   `.uncategorized` decodable while never offering it in the picker. `MatchFormat`
   is not `CaseIterable` and its picker is a hand-written list of
   `matchFormatOption(...)` calls in `HomeView.swift`, so hiding a format is a
   one-line deletion there.
3. Keep every exhaustive `switch` compiling with a sensible label ("Retired
   format" beats a wrong one — never fall back to `.standard`, which would
   re-render an old match's score in the wrong shape).
4. Pin the raw values in a test so a future deletion fails in Xcode rather than
   on a user's wrist. `ScoreTypesTests.test_doublesServer_rawValuesArePersistedIdentifiers`
   is the model to copy.

If a case genuinely must stop decoding, that is a schema migration: bump the
version, write the migration, and say so in the PR. See
`docs/features/TECHNICAL_DEBT.md` #18.

### Add a `MatchFormat`
1. Add the `case` to `MatchFormat` in `ScoreTypes.swift`.
2. Add its `MatchFormatConfig` in the `config` switch (rules are data-driven —
   you usually do **not** branch on the enum elsewhere; prefer adding a
   `MatchFormatConfig` flag over `if format == .x` scattered in views).
3. Grep for exhaustive `switch` on `MatchFormat` and update labels/UI.
4. Add a `SimulatedGameStatsTests`-style test exercising the new rules.

Adding a case is safe; **removing one is not** — see the retire recipe above.

### Add a synced setting / wire key  ⚠️ magic-string coupling
A setting name currently lives as a **literal string in 2–3 places that the
compiler does not connect** (see §5). To add one, keep them consistent:
1. `MatchSyncKey` constant in `MatchSyncMessage.swift` (the wire key).
2. Handle it in **both** `WatchMatchSyncService` and `PhoneMatchSyncService`
   (send + receive).
3. The local mirror, usually an `@Published` in `ScoreViewModel` (watch) and the
   phone settings store, persisted via `UserDefaults.standard.*(forKey:)`.
   **Use the same string** as the `MatchSyncKey` raw value to avoid drift.
   (Known legacy exception: announcements. The watch persists
   `"phoneAnnouncementsEnabled"`, the phone `"liveAnnouncementsEnabled"`, and
   the wire key is `announcementsEnabled`. Leave the local names alone unless
   you also add a one-time migration — renaming a `UserDefaults` key silently
   resets the user's stored choice. See `docs/features/TECHNICAL_DEBT.md` #3.)
4. If the setting is user-visible, add its one-line blurb to `SettingsCopy`
   (Core) and reference it from both apps' settings UI — don't hand-write the
   copy twice.
5. Build any new send payload via `MatchSyncPayloadBuilder` (not an inline dict)
   so it round-trips against `SyncIncomingPayload.decode` in tests.

### Add a point outcome / ending shot / derived stat
1. Extend `PointOutcome` / `EndingShot` in `PointStat.swift` (`displayLabel`,
   and `userSelectable` if user-pickable).
2. Derive it in `MatchStatsSummary.swift`.
3. Surface it in `PointCategorySheet` (watch) and the stats/graph/export views.
4. Add a `MatchStatsSummaryTests` case.

---

## 5. Known AI traps in this codebase

- **Stringly-typed `UserDefaults` keys duplicated as `MatchSyncKey` raw values
  (dozens of call sites across both apps).** Nothing connects the literal
  `"statsTrackingEnabled"` in `ScoreViewModel`, the same literal in
  `WatchMatchSyncService`, and `MatchSyncKey.statsTrackingEnabled` — change one
  and miss the others and you get a silent settings-sync bug with **no compiler
  error**. When editing any synced setting, grep the key string across the whole
  repo and update every occurrence — and do **not** assume local key == wire
  key: the announcements setting uses three different strings
  (`"phoneAnnouncementsEnabled"` watch-local, `"announcementsEnabled"` wire,
  `"liveAnnouncementsEnabled"` phone-local; see §4). (A typed `AppSettingKey`
  enum sharing the `MatchSyncKey` raw values is planned to remove this trap —
  `docs/features/TECHNICAL_DEBT.md` #3 and #10.)
- **Deleting a case from a persisted enum silently breaks every archive that
  contains it.** `MatchFormat`, `MatchType`, `Player`, `DoublesServer`,
  `PointOutcome` and `EndingShot` are all written to disk and to the wire, none
  has an unknown-value fallback, and `decodeIfPresent` throws (not `nil`) on a
  present-but-unrecognised value. Worse, both archives decode `[MatchRecord]`
  atomically, so one old point takes down the whole file. The schema is
  **additive-only** — retire a case by hiding it from the UI, never by removing
  it. See §4 "Retire a case in a persisted enum" and
  `docs/features/TECHNICAL_DEBT.md` #18. (`CompetitionType` is the exception by
  design: it is stored as a raw string and is not `Codable`.)
- **Rebuilding a `MatchRecord` field-by-field drops its `tags` (and `matchTypeRevision`).** The watch's
  `ScoreViewModel` constructs every live checkpoint/completion with the
  memberwise init, which has no tags or `matchTypeRevision`. That is safe on the *phone* (merges keep
  the newer metadata — `nil` is "no information"), but any store that **replaces**
  a record by id (watch `StatsStore.appendMatch`, phone `appendMatch` /
  `saveHistory`, any new phone mutation) must carry stored `tags` (`mergingTags`)
  and `matchTypeRevision` (`mergingMatchTypeRevision`) over or it silently erases them — both stores do, and any new
  replace path must too. Merge sites must also merge both clocks (`MatchTags.merged` then `MatchTypeRevision.merged`
  inside the body resolution). Any new phone inbound path must also scrub with
  the forgotten-player ledger.
  **Enforced on the watch (PR 2):** `StatsStore.appendMatch` merges the stored
  copy's tags forward; `ScoreViewModel.liveMatchTags` carries them across resume
  and into every checkpoint/finalize
  record and `appState.json`; `completeStoredMatch` copies the record so tags
  survive; `StatsStore.updateTags` (reached only from `.matchTagsUpdate`) is
  metadata-only and never creates a record. `MatchTagsWatchTests` pins all of it —
  a new watch write path needs a case there. A phone tag push for the **live**
  match can't reach the store (it isn't in history), so
  `onMatchTagsReceived` → `applyIncomingMatchTags` merges it into `liveMatchTags`.
- **Completion date versus live checkpoint authority.** `ScoreViewModel.matchCompletionTime`
  captures the final scoring action, persists additively in `AppState`, survives delayed
  categorisation/restoration, and clears on winning-point undo, resume and reset. Normal
  finalization reuses it; End at Current Score uses the deliberate action time. Live
  checkpoints stay unfinished (`endTime`/`iWon` nil) until finalization so a winning-point
  undo can still replace them on the phone. `MatchChronology` governs display ordering,
  never merge authority. Preserve start-date-based export filenames and full-record
  equality invalidation of Trends/export caches. Session markers and health redesign
  remain Phase 2 of `MATCH_RESUME_MARKERS_PLAN.md`.
- **Very large files** (`ScoreViewModel` ~2.0k, `PointsGraphView` ~1.9k,
  `MatchDetailView` ~1.3k, `ContentView`/`HomeView`/`PastMatchesView`
  ~0.7–1.0k). Don't load them whole. `PointsGraphView` and `MatchDetailView`
  are `MARK:`-sectioned; `ScoreViewModel` and `HomeView` currently have almost
  no anchors (adding them is TECHNICAL_DEBT #9) — for those, `Grep` for the
  symbol you need and read a bounded range around it. Splitting along `MARK:`
  boundaries into `extension` files is welcome and safe **everywhere**: the
  Core package globs its sources and the app/test targets are
  file-system-synchronized groups, so new files need no `project.pbxproj` edit
  (see §0).
- **No force-unwraps / no new dependencies / value types preferred** — these are
  enforced in review (`CONTRIBUTING.md`); match the surrounding style.
- **`MatchExporter` builders are `nonisolated static`** so they can run off the
  main actor; keep new builders `nonisolated` and pure.

---

## 6. Git / PR conventions

- Branch per change; never push to `main` directly.
- Commit subjects are short and **prefixed with the affected surface**, e.g.
  `[iOS] …`, `[Watch] …`, `[Core] …`, or `docs: …`. Explain the *why*.
- One concern per PR. Logic change ⇒ tests. Open PRs ready for review.
- **Production *source* file added / removed / renamed / repurposed ⇒ update
  `docs/architecture/file-inventory.md` in the same PR.** That inventory is the
  owner's no-code review guardrail; a source file missing from it is treated as
  unreviewed. Its scope is exactly what its own header says — "the complete list
  of production source files" — so `docs/**`, `.github/**`, and assets are **not**
  inventoried; no `docs/features/*_PLAN.md` has ever been listed there. Adding a
  design doc or a diagram does not require an inventory entry. Update the other `docs/architecture/` diagrams too when a change
  alters components, sync flows, or the match lifecycle (`docs/architecture/sync-and-data-flow.md`,
  `docs/architecture/match-lifecycle.md`, or the `docs/architecture/README.md` topology diagram as needed).
- **Keep `CLAUDE.md` and `AGENTS.md` current.** If you notice that a recipe is
  wrong, a file size is wildly off, a trap has been resolved, or a new
  multi-site coupling has appeared, fix it in the same PR. These files only work
  as a fast-path if they stay accurate — a stale entry is actively harmful.


### Isolated animated watch guide

The nine automatic situations live in Core’s and the watch’s `Walkthrough/`.
Never instantiate a second `ScoreViewModel` for the guide. Only
`WalkthroughCoordinator` writes the two local flags. Entry requires idle real
match/warmup/pending category/setup state; first-use offers additionally require
successful restoration/history reads, empty history and completed launch
presentation. Failed reads never establish first-use eligibility.

The guide accepts only Previous/Next/Done, runs gestures and selections for the
user and holds each result until navigation. No scoring gestures, lesson list,
replay menu or interactive category/stats modal belongs in the guide. Navigation
replaces fixture generations; view-scoped animation tasks cancel on replacement
or dismissal, and disposed adapters reject callbacks. Tasks pause with scene
inactivity. Reduce Motion uses static arrows and unanimated transitions. Shared
stats rows provide stable IDs so the guide can automatically reveal Errors.
The guide owns no production persistence/sync/sensor/background handlers and
never changes real settings or clears the active match.

UI tests use the DEBUG-only `--walkthrough-ui-test` harness; the additional
`--walkthrough-reduce-motion` flag sets the accessibility environment. Keep the
harness out of release builds. Watch integration tests cover entry and production
isolation; UI tests cover automatic responses, navigation and absence of old
practice menus. Physical-device VoiceOver and comprehension remain manual checks.

Serving graph filters on iOS and HTML require collected outcome data, following
the Outcomes pills. `ServingPointCategory.matches` excludes `.uncategorized`
points, whose default `isSecondServe == false` is not evidence of a first serve.
Keep the JavaScript `matchesServing` mirror and `controls()` availability in step
with Core and `PointsGraphScatterControls`; use saved match data, never the current
tracking preference. This applies equally to singles, doubles and mixed tracking.

Graph selection totals include the selected rally. Use `PointMatchScore.afterEachPoint`
for the inline/expanded graph inspector and HTML popup; never display the saved
`gameScoreAtStart` beside those totals. The Points history and exports retain their
before-point scores. After-point derivation runs only the pure scoring reducer,
keeps terminal tiebreak points visible, and suppresses unknown suffix-history games.

### Confirmed play sessions

Explicit history resume persists an additive AppState candidate before opening the
match, and only then removes the stored copy, so a crash leaves it in at least one
file. **A live match is not in history**: push, manifest, Past Matches and delete
paths all assume this. `ScoreViewModel.loadState` removes any in-progress copy left
by a crash or failed write (a completed copy stays). Failed writes can still leave
one until then, so `WatchMatchSyncService.sendFullHistory` also filters it through
`WatchHistory.recordsForPush`; the phone accepts any in-progress record, so a stale
copy would overwrite newer checkpoints. A push queued before a resume can still
arrive late (TECHNICAL_DEBT #2). Reopening the same live identity or
background/foreground creates no event. Park/finalize
uses `appendMatchDurably` and must succeed before clearing/replacing live state.
Unreadable/newer live state blocks writes and scoring rather than becoming empty.
Each fresh workout starts at its own start/resume/relaunch time. Launch and the
WatchKit recovery delegate share `restoreWorkoutAfterLaunch`: recover the existing
HealthKit session/builder before creating a fresh workout; a recovery error leaves
a visible warning and scoring available without automatically creating a competing
session. Backup-excluded AppState additionally stores the active workout start date
and its prior-activity baseline, so a matching recovered builder is counted once.
An unmatched/legacy recovered workout is saved separately; a missing workout starts
fresh for unfinished live play. Setup start requests made while recovery or a fresh
Health authorization grant is pending are coalesced and replayed after the recovered
identity is handled and permission becomes readable. `stopWorkout` cancels pending
intent; adopting a recovered session consumes it, and recovery errors discard it.
Health status uses the bounded settle policy, with no timeout while the system
permission sheet is open. Exhaustion/denial remains a visible recording failure.
Aggregate prior activity is combined with the
active builder without mutating the baseline on retries. These optional AppState
fields use `decodeIfPresent`; no new Health fields belong on MatchRecord.
`WorkoutFinalizer` retains each stopping session and builder through saving:
stop activity → `.stopped` → end collection → finish/save → end session. Recording
and save errors appear through `WorkoutStatusView`; HealthKit errors must never
be silently ignored. Stale callbacks cannot publish into the current session.
Preserve events on undo; unresolved anchors disable physiological continuity.
Graph health lines/smoothing and HR queries respect sessions; continuous Pulse/
Steps coaching is withheld for interrupted records. Exertion comparisons stay
within individual sessions. HTML schema 14 carries the same context in interactive
and static renderers; regenerate browser native exports after template changes.
Physical-Watch workout/collection checks remain a release requirement in
`docs/features/MATCH_RESUME_MARKERS_PLAN.md`.

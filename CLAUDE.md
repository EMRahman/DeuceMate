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

- **Do not run or trigger GitHub Actions for verification.** The workflow was
  removed to eliminate macOS runner costs. Do not rely on GitHub CI as a
  feedback loop or safety net.
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
  `docs/features/MATCH_START_UX_PLAN.md` §5.6).
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
├── DeuceMate/             iOS companion — read-only archive + live spectator
└── Packages/DeuceMateCore/  SPM package — portable models, stats, sync wire-format
```

Data-flow invariants — **internalise these before touching sync or persistence:**

- **The watch owns every match it has touched.** The phone is a *durable,
  read-only archive*; it never authors match results. Matches flow
  watch → phone over `WatchConnectivity`. (Two exceptions: the phone may *issue
  score commands* to the watch when "iPhone Input" is enabled — but the watch
  still validates and applies them; see `MatchSyncKey.scoreCommand*`. And
  manual match entry builds a record on the phone, saves it to the phone
  archive, and sends a copy to the watch, which then owns the live match.)
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
| `Models/MatchRecord.swift` | The persisted match. Custom `init(from:)` for backward-compat decoding. **See §4 before adding fields.** |
| `Models/PointStat.swift` | `PointOutcome`, `EndingShot`, shared `ServingPointCategory` graph matching, `GameScoreSnapshot`, `PendingPointInfo`, `PointStat`. The atom from which all stats derive. |
| `Scoring/ScoringEngine.swift` | Pure scoring reducer — `pointWon(by:in:) -> ScoringResult` over value-type `ScoringState`; side-effects come back as typed `ScoringEvent`s. The watch `ScoreViewModel` delegates here. Its perspective-neutral `isRegularGameComplete` predicate is also shared by historical score reconciliation. **Change scoring rules here, with `ScoringEngineTests`.** |
| `Sync/MatchSyncMessage.swift` | `MatchSyncKey` (all wire keys), `MatchSyncService` protocol, codec helpers. |
| `Sync/MatchSyncPayloadBuilder.swift` | Pure construction of the `[String: Any]` WatchConnectivity payloads. **Build payloads here** (single source of the wire shape) rather than assembling dicts inline in the app/transport — keeps them round-trippable in package tests. |
| `Sync/SyncIncomingPayload.swift`, `MatchSyncTransport.swift`, `MatchMergePolicy.swift` | Decode/route incoming payloads; merge policy decides watch-vs-phone winner. |
| `Sync/MatchStorageLocation.swift` | Pure derivation of where a match lives (`both` / `phoneOnly` / `watchOnly`) from the watch's reported id manifest vs the phone's store. Drives the iOS storage-location indicators. |
| `Sync/WatchMirror.swift`, `WatchHistoryCap.swift` | Pure merge/prune rules for the phone's mirror of the watch's rolling history; `WatchHistory.cap` (25) lives here so the watch (enforces) and phone (explains) cite one number. |
| `Sync/ArchiveBackupPolicy.swift` | Pure one-way iCloud backup policy: builds outbound snapshots from the phone archive (stripping the five HealthKit-derived fields to comply with App Store Review Guideline 5.1.3(ii)), handles the one-time initial restore before the local archive is initialized, and defines `BackupPreview` (record count + newest date, used for the restore prompt). Used by `PhoneStatsStore`. |
| `Persistence/HealthSidecarPolicy.swift` | Pure split/merge policy for the phone's local archive: projects exactly the five HealthKit-derived fields into a backup-excluded sidecar and reconstructs full records in memory without overwriting existing non-nil Health values. |
| `Persistence/ManualMatchArchiveBackup.swift` | Versioned full-fidelity JSON codec + merge/replace policy for the iPhone Settings > Backup & Transfer manual archive export/import. Manual exports intentionally include HealthKit-derived fields and must stay separate from iCloud backup policy. |
| `Stats/MatchStatsSummary.swift` | Derives serve/return/break/error/rally stats from `[PointStat]`. The reporting core. |
| `Stats/PointGamesScore.swift`, `PointMatchScore.swift`, `SetScoreLabel.swift` | Derive the trustworthy full match score immediately before each tracked point and format set/game scores once for iOS, text export, and HTML. `PointGamesScore` reconciles reset-derived games with stored scores and suppresses suffix-only histories; any final-point credit must first prove that the point completed its game. See `docs/features/POINT_MATCH_SCORE_PLAN.md`. |
| `Stats/RecCoachInsights.swift`, `PulseCoachInsights.swift`, `SetActivitySplit.swift`, `HRZone.swift` | Coaching/heart-rate analytics. `HRZone.isUsableBirthYear` tells "calibrated" from "running on the 190 bpm default" without comparing the resolved value against 190 (also a legitimate age-derived result). |
| `WebExport/` (`MatchWebViewModel.swift` + `…+Build.swift` + `…+Comparison.swift` + `…+AICoach.swift`, `MatchHTMLExporter.swift`, `MatchWebStaticFallback.swift`, `MatchWebTemplate.swift`, `WebExportColors.swift`) | Self-contained **interactive HTML match export** — a pure `Encodable` view-model (both me/opponent perspectives flattened, recorder-only HR/steps, + per-set `filters` (All / Set N) each with a recorder-framed TV-style Me-vs-Opp `comparison`, points-won header, and duration rows, + an optional `aiCoach` block, mirroring `MatchDetailView`) + assembler + the viewer (HTML/CSS/dependency-free SVG-JS) kept as Swift **raw-string constants** (no resource bundle, no pbxproj edit). The viewer is recorder-framed — **no perspective toggle** — and mirrors the iOS archive detail: `PointsGraphView`-style outcome, Serving, and ending-shot count pills drive the chart, regular/tiebreak bands share the iOS palette, pointer capture supports click/touch dragging across points, a **Stats/Points tab toggle** + **All/Set N set filter** switch the lower content, and the point-by-point list shows the full pre-point match score plus recorder-relative 🎾 Serving / racquet Receiving status (`PointVM.matchScoreLabel` + `PointVM.isTiebreak`, schema v9). An **AI Coach card** (mirrors `AICoachSheet`) copies the prompt + offers opt-in AI-app launch links. Derivation stays in tested Swift; the JS only paints. **AI prompt text is injected** (`MatchHTMLExporter.html(for:aiPromptMe:aiPromptOpponent:)`) from `MatchExporter.aiPromptExport` by `MatchDetailView` — the only place outside Core's tested derivation. The page loads zero external resources on open; the AI links are user-clicked navigations (a refined `MatchWebExportTests` invariant — no `src=`/`<link>`/`@import`/CDN), and a `default-src 'none'` Content-Security-Policy meta in `MatchWebTemplate.head` enforces that in the browser too (inline script/style only — keep it in step if the viewer ever needs a new source type). **Progressive enhancement:** `#root` ships pre-filled with a static report from `MatchWebStaticFallback` (header + four server-rendered SVG momentum charts — one per preset: Points Won/Lost + Ending Shots All Won/Lost, each with scatter + colour/label/count pills — + the TV-style Me/Opp split-bar comparison for the whole match plus a per-set breakdown) so no-JS previews (iOS Quick Look, local-file opens) aren't blank; the viewer JS does `root.innerHTML = ""` and rebuilds. `staticChartSVG` mirrors the JS `buildSVG`/`stepPath`/`symbol` geometry, and `pointsWonBar`/`comparisonCard`/`splitBar` mirror the JS comparison bars — keep them in step. HR is recorder-only (mirrors `MatchExporter`). Bump `MatchWebViewModel.currentSchemaVersion` when the JSON shape changes. `MatchDetailView` shares the produced `.html` as a file. Keep `WebExportColors` in step with `PointsGraphView`'s palette. See `docs/features/INTERACTIVE_HTML_EXPORT_PLAN.md`. |
| `Settings/SettingsCopy.swift` | Single source of truth for the one-line description shown under each setting on **both** apps. Add/edit a setting's blurb here so the watch and phone can't drift. |
| `Settings/MatchSetupDefaults.swift` | The remembered "last used" match setup (format + singles/doubles) the watch start screen pre-applies so Start Match doesn't re-ask what almost never changes. `resolve(formatRaw:typeRaw:)` is a total decode — absent/empty/retired raw values fall back to `.standard`/`.singles`. Watch-local `UserDefaults` keys only (`defaultMatchFormat`/`defaultMatchType`, §0 exception) — no wire key, no phone sync. See `docs/features/MATCH_START_UX_PLAN.md`. |
| `Settings/MatchTrackingStatus.swift` | The pre-match "what will this match record?" rule: point tracking (format-aware — `—` when `MatchFormat.config.disablesPointTracking`), Health access, and Pulse Coach resolved to `.on`/`.partial`/`.off` plus label, SF Symbol, and fix-it copy. `HealthAccess` is the portable mirror of the HealthKit permission (the watch maps `HKHealthStore` onto it — Core stays HealthKit-free). `collapsingPulseWhenHealthOff(_:)` drops the redundant Pulse chip when Health is off (the strip's rule; Settings always shows all three). Drives the watch start-screen tracking strip and its settings summary. |
| `Settings/ICloudBackupCopy.swift` | The global "backed up to iCloud?" indicator (label + SF Symbol + resolution rule) shown on the iPhone archive. Six cases: `backedUp`, `notBackedUp`, `unavailable`, `restoring`, `pendingRestore` (backup found, user prompt open), `pendingUpload` (pushed but daemon not yet confirmed upload). `current(isEnabled:isAvailable:isRestoring:hasPendingRestore:isUploaded:)`. |
| `Persistence/StatsStoring.swift` | Persistence protocol + JSON codec; both apps implement it (file-backed JSON). |

**Watch app — `DeuceMate Watch App/`:**

| File | Lines | What |
|------|------:|------|
| `ScoreViewModel.swift` | ~1947 | Live match state + synced settings; delegates scoring rules to Core's `ScoringEngine` (see §1); seeds/persists the remembered match setup (`applyRememberedSetupIfIdle()`/`persistMatchSetupDefaults()`, called from `loadState()`/`resetMatch()` tails and `HomeView`'s `commitServerSelection()` — never from `init`, which runs before either restore path); `trackingStatuses` resolves Core's `MatchTrackingStatus.all(...)` and forwards `WorkoutManager.$healthAccess` (not its whole `objectWillChange` — that would also fire on every live-match HR/calorie tick) into its own `objectWillChange` in `init`, so views watching only the view model still redraw on Health-access changes without extra redraws during play. ⚠️ Almost no `MARK:` anchors yet — `Grep` for the symbol and read a bounded range. |
| `HomeView.swift` | ~959 | Match setup / start screen: a pre-match card states the remembered Singles/Doubles + format setup (hidden mid-match) and taps through to a combined Match Setup sheet, so Start Match skips straight to who-serves-first; the same card carries the Points/Health/Pulse tracking strip, and the Settings sheet opens with the always-three row form. ⚠️ No `MARK:` anchors yet. |
| `TrackingStatusStrip.swift` | ~140 | Paints Core's `MatchTrackingStatus`: the pre-match strip (single-line icon+state chips, tap to Settings, Pulse collapsed out when Health is off) and the full-width Settings rows (always all three). |
| `ContentView.swift` | ~941 | Live scoreboard + gesture handling. |
| `MatchStatsView.swift` | ~630 | On-watch live stats. |
| `Sync/WatchMatchSyncService.swift` | ~289 | Watch side of `WatchConnectivity`. |
| `PointCategorySheet.swift`, `WorkoutManager.swift`, `MatchHistoryView.swift`, `StatsStore.swift`, `BackupExcludedFileWriter.swift`, `AppTheme.swift` | | Categorisation UI, HealthKit workout (`WorkoutManager` also publishes `healthAccess`, refreshed on foreground and in `HomeView.onAppear`), backup-excluded history/live-state persistence, theming. |

Watch tests: `DeuceMate Watch AppTests/DeuceMate_Watch_AppTests.swift` (~1.1k
lines, 36 Swift Testing `@Test` functions — high-level `ScoreViewModel`
scenarios; needs `import DeuceMateCore`, see §0).

**iPhone app — `DeuceMate/`:**

| File | Lines | What |
|------|------:|------|
| `Views/PointsGraphView.swift` | ~1.9k | Charts (points momentum + outcome/serving/ending-shot filters + HR/steps overlays), including set-relative point selection with the full pre-point score and serving side. Heavily `MARK:`-sectioned. |
| `Views/MatchDetailView.swift` | ~1100 | Per-match detail, stats tabs, full-score/server point rows, share/export. |
| `Export/MatchExporter.swift` | ~640 | Plain-text + AI-prompt export. `nonisolated static` builders by section. |
| `Views/PastMatchesView.swift` | ~705 | iPhone archive list (phone-side analogue of the watch `MatchHistoryView`); shows storage-location + iCloud indicators. Growing fast — see TECHNICAL_DEBT #13. |
| `Views/SettingsView.swift` (~820), `ManualMatchEntryView.swift` (~442), `LiveScoreboardView.swift` (~490), `LivePointCategoryPanel.swift` (~222) | | Settings including Watch sync counts/fresh-Watch restore guidance and Backup & Transfer archive export/import, manual entry, live spectator, phone-side point categorisation (mirrors the watch sheet when iPhone Input is on). |
| `Views/PulseCoach/PulseCoachSection.swift`, `Views/Coaching/RecCoachSection.swift`, `AICoachLauncher.swift`, `AICoachSheet.swift` | | HR coaching panel, recreational coaching insights, and routing a generated coaching prompt to third-party AI apps. |
| `Sync/PhoneMatchSyncService.swift` | ~600 | Phone side of `WatchConnectivity`; a Watch manifest (including empty) acknowledges Sync Now, and live install state refreshes through `sessionWatchStateDidChange`. |
| `Persistence/PhoneStatsStore.swift`, `Audio/LiveAnnouncementService.swift`, `HealthKitHRFetcher.swift` | | Health-stripped archive plus backup-excluded sidecar, manual export/import, TTS announcements, HR backfill. |

Feature design docs live in `docs/features/*.md` — read the relevant plan before
extending sync, changeover, or the companion app. The prioritised improvement
backlog is `docs/features/TECHNICAL_DEBT.md` (statuses verified against the
code at the most recent audit) — check it before starting a refactor so you don't
re-discover, or contradict, a documented decision.

---

## 3. Build & test (run locally on macOS)

There is no GitHub Actions CI. Run tests locally from Xcode or from a Mac CLI
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

**Tests exist for Xcode, not GitHub.** There is no CI — but the test suite is
still the correctness record for the owner running Xcode locally. Keep it strong.
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

### Add a `MatchFormat`
1. Add the `case` to `MatchFormat` in `ScoreTypes.swift`.
2. Add its `MatchFormatConfig` in the `config` switch (rules are data-driven —
   you usually do **not** branch on the enum elsewhere; prefer adding a
   `MatchFormatConfig` flag over `if format == .x` scattered in views).
3. Grep for exhaustive `switch` on `MatchFormat` and update labels/UI.
4. Add a `SimulatedGameStatsTests`-style test exercising the new rules.

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
- **Very large files** (`ScoreViewModel` ~1.9k, `PointsGraphView` ~1.9k,
  `MatchDetailView` ~1.1k, `ContentView`/`HomeView`/`PastMatchesView`
  ~0.7–0.9k). Don't load them whole. `PointsGraphView` and `MatchDetailView`
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

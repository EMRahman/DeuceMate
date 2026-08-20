# Technical Debt & Improvement Backlog

Captured from a Codex-assisted audit of the codebase, then re-verified
item-by-item against the code and extended with agent-operability
findings in a Claude-assisted re-audit. Each item has been
reviewed, contextualised against the actual runtime behaviour, and
prioritised. Items marked **Parked** have a documented reason why they are not
actively being worked on.

**How priorities are weighted.** DeuceMate is developed primarily by AI coding
agents working in cloud environments *without a Swift toolchain* (the owner
runs Xcode locally). Debt that degrades agent effectiveness — an inaccurate
claim in `CLAUDE.md`, a ~2k-line file with no `MARK:` anchors, an invariant
nothing can check without a compiler — therefore ranks above conventional
refactors of working code. An agent cannot compile its way back to safety;
accurate docs, navigable files, and text-level checks are its substitutes.

---

## Summary table

| # | Area | Item | Priority | Status |
|---|------|------|----------|--------|
| 1 | Architecture | Extract scoring engine into pure Core reducer | High | **Done** |
| 2 | Sync | Add `lastModified` to `MatchRecord` for merge policy | Medium | Backlog |
| 3 | Settings | Replace stringly-typed settings keys with typed keys | **High (next up)** | Backlog |
| 4a | Persistence | Silent save-failure handling (watch + phone) | Low | Backlog |
| 4b | Persistence | File-protection level on watch saves | Low | **Done** |
| 5 | UX | Simplify first-run and match-start flow | Medium | **Done** — [`MATCH_START_UX_PLAN.md`](MATCH_START_UX_PLAN.md) |
| 6 | Concurrency | `PhoneStatsStore` actor / `@MainActor` migration | Low | Backlog |
| 7 | Stats | Convert formatted string stats to typed `RatioStat` | Medium | Backlog |
| 8 | Agent docs | Fix `CLAUDE.md` drift (pbxproj claim, ghost files, stale sizes) | High | **Done — this re-audit** |
| 9 | Navigability | `MARK:` anchors for `ScoreViewModel` / `HomeView` / `ContentView` | High | Backlog |
| 10 | Tooling | Settings-key consistency check (grep in CLAUDE.md §0) | High | **Done** |
| 11 | Duplication | De-duplicate `AppTheme.swift` (byte-identical in both apps) into Core | Medium | Backlog |
| 12 | Duplication | Extract point-categorisation flow state machine into Core | Medium | Backlog |
| 13 | Architecture | Split `PastMatchesView` (705 lines, fastest-growing file) | Low | Backlog |
| 14 | Hygiene | Force-unwrap in `PointsGraphView`; placeholder test targets | Low | **14a done**; 14b backlog |
| 15 | i18n | Localization (all UI copy is hardcoded English) | — | **Parked (product, not code)** |
| 16 | Health/Privacy | Drop HealthKit date-of-birth read; user-entered birth year; remove dead computed max-HR path | High | **Done** |
| 17 | Duplication | De-duplicate set filters, durations, percent strings and the compact score line into Core | Medium | **Done** |
| 18 | Persistence | Persisted enums are additive-only; archives decode atomically | Medium | Rule documented; guards backlog |

---

## Detail

### 1 — Extract scoring engine (Done)

**What:** `ScoreViewModel` owned rules, settings, sync, HealthKit, haptics,
persistence, undo, and scoring in one ~2.3k-line file. The riskiest logic
(`winPoint`, `losePoint`, `completeSet`, `updateScore`) was untestable without
watchOS.

**Done:** `Scoring/ScoringEngine.swift` (~567 lines) added to Core as a pure
static reducer — `pointWon(by:in:) -> ScoringResult`. State is a value type
(`ScoringState`), side-effects are typed `ScoringEvent`s returned in the
result. `ScoreViewModel` now delegates to the engine
(`ScoreViewModel.swift:1010`) and reacts to events.

**Tests added:** 17 tests in `ScoringEngineTests` covering deuce
cycling, server rotation, break-point detection, snapshot correctness,
changeover event reasons, the shared perspective-neutral game-completion predicate,
all four non-standard formats, and endless formats. Test count across the Core package:
378 (re-counted after the point-match-score work, 29 test files).

**Remaining gap:** The `handleSideChangesAfterTiebreakSetEnd` 4-case switch
(players change × ball-holder changes; `ScoringEngine.swift:531–565`, called
from the set-completion path at `:317`) has no dedicated test. Low risk given
the logic is simple, but worth adding if the area is touched.

---

### 2 — Add `lastModified` to `MatchRecord` for merge policy

**What:** `MatchMergePolicy` Case 5 (both in-progress) currently does
"always accept incoming." This is safe for live `sendMessage` delivery
(in-order by WatchConnectivity contract) but would be unsafe if a stale
`transferUserInfo`-queued checkpoint ever arrived after a newer live one had
already been applied — the phone would silently roll back to the stale state.

The transport deliberately avoids this today by **dropping** all in-progress
checkpoints when unreachable (only announcements are queued). That removes the
stale-arrival path. The risk is therefore latent rather than active.

A previous attempt to use `stats.count` as a "newer" proxy broke undos
(an undo checkpoint has fewer stats, so the phone wrongly discarded it). The
comment in `MatchMergePolicy.swift` records this history.

**Proposed fix:** Add `lastModified: Date` to `MatchRecord`, set to `Date()`
on every watch-side state mutation. Update Case 5 to accept incoming only if
`incoming.lastModified >= existing.lastModified`. Undo checkpoints are written
*after* the undone state so their timestamp is always newer — the proxy is
correct. Decode with `decodeIfPresent` defaulting to `startTime` (§4
backward-compat recipe).

Secondary benefit: once `lastModified` exists the transport can safely queue
a bounded "latest live checkpoint" when unreachable, improving phone archive
freshness during BLE gaps. Currently the phone can lag the entire duration of
a gap.

**Why medium, not high:** The transport's intentional drop policy means there
is no live repro path today. The fix becomes important if the transport
strategy is ever changed.

**Key files:** `MatchRecord.swift`, `MatchMergePolicy.swift`,
`MatchSyncTransport.swift`, `MatchRecordCodingTests.swift`,
`MatchMergePolicyTests.swift`.

---

### 3 — Replace stringly-typed settings keys with typed keys

**What:** A setting's identity currently lives as a raw string in 2–3 places
the compiler does not connect: a `MatchSyncKey` constant, a `UserDefaults`
call in `ScoreViewModel`, and a matching call in `WatchMatchSyncService` /
`PhoneMatchSyncService` (plus `@AppStorage` literals in the iPhone
`SettingsView`). Changing one and missing another produces a silent
settings-sync bug. `ScoreViewModel` has 29 `UserDefaults.standard` call sites;
only 7 use `MatchSyncKey` directly.

**It is worse than simple duplication — one setting already uses three
different strings.** The announcements toggle is persisted on the watch as
`"phoneAnnouncementsEnabled"` (`ScoreViewModel.swift:87`), travels the wire as
`MatchSyncKey.announcementsEnabled` = `"announcementsEnabled"`
(`MatchSyncMessage.swift:55`), and is persisted on the phone as
`"liveAnnouncementsEnabled"` (`LiveAnnouncementService.swift:19`). So the §4
recipe's "local key == wire key" rule already has a legacy exception, and an
agent grepping only the wire key will miss both local stores. Do **not**
"fix" the local names casually: renaming a `UserDefaults` key silently resets
the user's stored preference unless a one-time migration reads the old key.

**Proposed fix:** A shared `AppSettingKey` enum in Core whose raw values equal
the `MatchSyncKey` raw values. Both apps look up `UserDefaults` via
`AppSettingKey`, so a drift between the two becomes a compile error. The
`SettingsCopy` registry already exists as a partial precedent for this pattern.
The design must model the announcements aliasing explicitly (either migrate
the stored keys once, or give the enum a `localStorageKey` override) rather
than assuming raw value == storage key everywhere.

**Why high:** The trap is live today. CLAUDE.md §5 flags it explicitly as an
AI trap. The fix is mechanical but large — touches both apps and every synced
setting. Scope one setting category at a time to keep PRs reviewable. Until
this lands, item 10's checker script is the only mechanical guard.

**Dead key to remove:** `MatchSyncKey.workoutSessionEnabled` and its decoded
event remain from an abandoned in-app workout toggle. No sender emits the key,
both platform receivers discard the event, and the accepted product behavior
uses the system-managed watchOS HealthKit authorization instead. Remove the
unused key and event during this cleanup; they are technical debt, not a
submission blocker.

**Key files:** `MatchSyncMessage.swift`, `ScoreViewModel.swift`,
`WatchMatchSyncService.swift`, `PhoneMatchSyncService.swift`,
`SettingsView.swift`, `LiveAnnouncementService.swift`.

---

### 4a — Silent save-failure handling

**What:** The watch's live-state save failure path is a `print` inside
`#if DEBUG` (`ScoreViewModel.swift:1625`) — completely invisible in a release
build. The two history stores do log failures through `os.Logger`
(`StatsStore.swift:74–76` on the watch, `PhoneStatsStore.swift:293` on the
phone), which reaches the unified log but is never surfaced in-app. For a
scoring app where a failed save means lost match data, failures should be
visible to the user (at minimum a brief in-app banner on the next active
interaction).

**Proposed fix:** Expose a `@Published var lastSaveError: Error?` (or similar)
on the view model; show a non-blocking warning in the UI if a save has failed
since the last successful one. Does not need to be intrusive — a small
indicator on the history or settings screen is enough.

**Why low:** Saves rarely fail in practice. This is a hardening measure rather
than a fix for an active bug.

---

### 4b — File-protection level on watch saves (Done)

**Original concern:** `.completeFileProtection` encrypts files and makes them
inaccessible when the device is locked. The suggestion was to switch to
`.completeFileProtectionUntilFirstUserAuthentication` so background writes
during screen-off periods succeed.

**Why it was parked (and why the park no longer holds).** The park assumed the
watch stays unlocked throughout use: "screen off" and "device locked" are distinct
states, a dimmed display between points does not lock the device, and an active
`HKWorkoutSession` keeps the device unlocked for the session's duration. That is
still true for **live scoring**. But the park named its own un-park trigger —
"watch-side background processing that runs after the watch has been taken off the
wrist" — and that path exists and is exercised by the companion flows: the phone
sends **"Sync to Watch"** / manual-entry records via `sendRecordReliable` and
**delete-from-watch** commands via `sendControl(queueOnFailure: true)`, both of
which fall back to `transferUserInfo` / `transferFile` when the watch is
unreachable (`MatchSyncTransport.swift`). Those are **background-queued** deliveries
("survives the peer being asleep") — WatchConnectivity can launch the watch app in
the background to receive them **while it is off-wrist and locked** (e.g. charging
on a nightstand), where it runs `StatsStore.appendMatch` / `removeMatch`. A Class A
write there fails silently, and a Class A *read* there returns nothing — which,
before the read-failure guard (item below), was mis-read as an empty archive and
could clobber stored matches.

**Resolved.** Switched both watch writers to
`.completeFileProtectionUntilFirstUserAuthentication` (Class B), matching
`PhoneStatsStore`:
- `StatsStore._writeUnsafe` (`StatsStore.swift`) — the writer actually reached by
  the off-wrist background deliveries above; this is the load-bearing change.
- `ScoreViewModel.saveState()` (`ScoreViewModel.swift`) — only reached during live
  scoring (device unlocked), so not strictly required; switched too for consistency
  across the three persistence writers and as defense-in-depth against any future
  off-wrist save path.

Self-migrating: both files are rewritten atomically on the next save, so existing
Class A files pick up Class B without a migration step. Shipped together with the
watch `StatsStore` read-failure guard (a failed/corrupt read now returns `nil`, and
`appendMatch` / `removeMatch` refuse to overwrite rather than persisting the
emptiness) as one watch-store-reliability change.

**Residual gap (accepted, documented).** For a watch that upgraded with an existing
`matchHistory.json` still written under Class A, the Class B benefit only lands after
the next *unlocked* save migrates that file. In the window before that — an off-wrist,
locked background delivery (Sync-to-Watch / manual-entry / delete via
`transferUserInfo`/`transferFile`) — the read still fails, so the read-failure guard
drops the delivery *without a retry path* rather than storing it. This is **not a
regression** (pre-guard, the subsequent Class A *write* failed too, so the delivery was
already lost), and it self-heals once any unlocked save migrates the file. Fully closing
it would need either an explicit unlocked protection-class migration on launch (only
narrows the window — a locked first-launch still can't migrate) or a
pending-operation retry queue for dropped background deliveries (larger). Deferred by
choice; recorded here so the tradeoff is visible.

---

### 5 — Simplify first-run and match-start UX (Done)

**Original concern:** The feature set is broad (scoring, HealthKit, compass,
announcements, iPhone input, manual recovery, AI prompts, graphs). The
suggestion was to narrow the first-run and match-start flow to: choose format,
choose server, start.

**Why it was parked:** This is a product design decision, not a software engineering
improvement. The code itself is not the problem. Should be addressed in a
product/UX conversation rather than a PR.

**Unparked, 3 August 2026.** That conversation has happened and is written up in
[`MATCH_START_UX_PLAN.md`](MATCH_START_UX_PLAN.md), prompted by the owner's report
that the start screen gives no way to tell whether point tracking, Health, or Pulse
Coach are on. The plan narrows the flow from 5 taps to 3 by remembering the last
match setup, and states the three irreversible tracking facets on the start screen.
Two implementation PRs are specified there (remembered defaults first — the tracking
strip is not *correct* without them, because `MatchFormat.perpetualPoints` suppresses
point tracking regardless of the user's setting).

**Done.** Both PRs landed: `[Watch] Remember the last match setup` (remembered
format + singles/doubles, `MatchSetupDefaults`) and `[Watch] State what the next
match will record` (the Points/Health/Pulse tracking strip, `MatchTrackingStatus`).
Taps from the start screen to the first point: 5 → 3.

---

### 6 — `PhoneStatsStore` concurrency model

**What:** `PhoneStatsStore` uses a `DispatchQueue` with `queue.sync` calls
from callers, then `DispatchQueue.main.async` to publish back. This works but
becomes harder to reason about as Swift concurrency strictness increases —
Swift 6 strict-concurrency mode will eventually force this migration anyway.
(The original deadlock surface — `queue.sync` from main hitting iCloud URL
resolution — was removed by the canonical/backup rewrite: mutations
now touch only local files; `url(forUbiquityContainerIdentifier:)` runs solely
inside async backup passes on the store's queue.)

The watch's `StatsStore` (78 lines) uses the same queue-confined pattern. If
the migration happens, do both stores together so the two sides keep
symmetrical concurrency semantics.

**Proposed fix:** Rewrite as an `actor` (or a `@MainActor`-isolated class
backed by an `async` storage helper). Callers `await` mutations; the actor
serialises access without blocking threads.

**Why low:** The current code works and the deadlock path requires a specific
calling pattern that doesn't exist today. The fix is worthwhile as a
maintenance improvement, especially before adding any new background sync paths.

**Key files:** `PhoneStatsStore.swift`, `StatsStore.swift`.

---

### 7 — Convert formatted string stats to typed values in `MatchStatsSummary`

**What:** Three fields in `MatchStatsSummary` store pre-formatted strings:

```swift
public let wueRatio: String        // e.g. "2.3 : 1" or "∞ : 1"
public let aggressionIndex: String // e.g. "35% (7/20)"
public let ownErrorsPct: String    // e.g. "60% (6/10)"
```

The underlying numerators and denominators are computed locally and then
discarded. Storing only the formatted string makes graphing impossible,
accessibility harder (VoiceOver reads the literal string), localization
harder, and AI-export formatting inconsistent.

**Proposed fix:** Replace with a small `RatioStat` struct in Core:

```swift
public struct RatioStat: Sendable {
    public let numerator: Int
    public let denominator: Int
    public var formatted: String { ... } // same logic as current pct()
}
```

Views and exporters call `.formatted` for display. The typed values are
available for graphing, accessibility labels, and structured AI export.

This is a Core-only change — no `project.pbxproj` edit needed. Both apps
consume `MatchStatsSummary` but read-only, so updating call sites to use
`.wueRatio.formatted` instead of `.wueRatio` is a mechanical find-and-replace.

**Why medium:** Clean, bounded change with clear benefits. No behaviour change
— only the type changes. The `pct(num:den:)` helper in `MatchStatsSummary` can
be retained as the formatting implementation.

**Key files:** `MatchStatsSummary.swift`, both apps' stats/export views,
`MatchStatsSummaryTests.swift`.

---

### 8 — Fix `CLAUDE.md` drift (Done — this re-audit)

**What:** In a repo developed by AI agents, `CLAUDE.md` is load-bearing
infrastructure: agents act on its claims without a compiler to catch them when
the claims are false. The latest re-audit found it had drifted from the
code in ways that actively changed agent behaviour:

- **Obsolete pbxproj warning.** The guide said adding a file to an app target
  requires a hand-edit of `project.pbxproj` and told agents to flag rather
  than attempt it. In reality the project is `objectVersion 77` with six
  `PBXFileSystemSynchronizedRootGroup`s covering both app targets and all
  four test targets — a new `.swift` file dropped into an existing target
  directory is picked up automatically. The warning made agents avoid a
  perfectly safe operation (notably file splits, see items 9 and 13).
- **Ghost / wrong paths in the file map.** `PulseCoachMonitor.swift` was
  listed but does not exist anywhere (watch-side Pulse Coach is just synced
  settings in `ScoreViewModel` + `WatchMatchSyncService`; the analytics live
  in Core's `PulseCoachInsights.swift`). `RecCoachSection.swift` was listed
  under `Coaching/` but lives at `Views/Coaching/`.
- **Stale line counts.** `ScoreViewModel` 1928 (claimed ~2322), `PastMatchesView`
  705 (claimed ~468 — it grew 51%), `WatchMatchSyncService` 289 (~321),
  `PhoneMatchSyncService` 508 (~455), `MatchDetailView` 1014 (~987),
  `HomeView` 900 (~987). Sizes matter to agents because they gate the
  read-whole-file vs. read-a-section decision.
- **Missing Core files.** The map omitted `Scoring/ScoringEngine.swift` — the
  most consequential Core file since item 1 landed — plus `WatchMirror.swift`,
  `WatchHistoryCap.swift`, and `ICloudBackupCopy.swift`.
- **No pointer to this document**, and no mention that the watch app target
  has real tests (`DeuceMate_Watch_AppTests.swift`, ~1.1k lines, 36 Swift
  Testing `@Test` functions).

**Done:** All of the above corrected in the same PR as this re-audit.

**Residual practice (cheap, do it opportunistically):** whenever a PR touches
a file named in the `CLAUDE.md` map, re-check its line count and existence
(`wc -l` is enough). Treat agent-doc drift as a bug, not housekeeping — a
false claim in `CLAUDE.md` misleads every future session.

---

### 9 — `MARK:` anchors for `ScoreViewModel`, `HomeView`, `ContentView`

**What:** `CLAUDE.md` instructs agents to "read only the `MARK:` section you
need" — but the prescribed navigation is impossible in exactly the files where
it matters most. Current anchor counts: `ScoreViewModel.swift` **1 MARK in
1928 lines**, `HomeView.swift` **0 in 903**, `ContentView.swift` **3 in 941**.
By contrast `PointsGraphView.swift` (9 MARKs / ~1700 lines) shows the target
state and is pleasant to work in. For an agent this is not cosmetic: without
anchors it must load the whole file (context cost) and its exact-match `Edit`s
get riskier because there are no nearby unique landmarks.

**Proposed fix:** Comment-only PR adding sections. Suggested cuts —
`ScoreViewModel`: synced-settings properties / match lifecycle / scoring
delegation (`ScoringEngine` call + event application) / undo / second-serve &
point-category context / changeover & compass / HealthKit & workout /
persistence / sync & announcements. `HomeView`: match-format setup / server &
side pickers / settings toggles / history & navigation. `ContentView`:
scoreboard layout / gesture handling / overlays & badges. Update the
`CLAUDE.md` file-map descriptions afterwards. Zero behaviour risk.

**Why high:** The cheapest change in this document with a compounding payoff
for every future agent session in the three most-touched watch files.

**Key files:** `ScoreViewModel.swift`, `HomeView.swift`, `ContentView.swift`.

---

### 10 — Settings-key consistency check ✅ Done

**What:** The silent-drift trap in item 3 (same string must appear in
`MatchSyncKey`, both sync services, and the `UserDefaults forKey:` call) is
not compiler-checked; a one-character difference produces no error anywhere.

**Done:** Added a copy-pasteable `grep` command to `CLAUDE.md` §0 as a
pre-push check. It surfaces every `UserDefaults forKey:` and `@AppStorage`
string literal in both app targets (string-literal `forKey:\s*"` only —
`CodingKey` enum accesses are excluded). An agent or the owner scans the
output and confirms each string matches a `MatchSyncKey` constant's raw
value; the two known aliases (`phoneAnnouncementsEnabled` / `liveAnnouncementsEnabled`)
are documented inline. No new files or toolchain needed. The long-term
solution remains item #3 (typed `AppSettingKey` enum, now "next up").

**Key files:** `CLAUDE.md`.

---

### 11 — De-duplicate `AppTheme.swift` into Core

**What:** `DeuceMate Watch App/AppTheme.swift` and `DeuceMate/AppTheme.swift`
are **byte-identical** (220 lines each; verified with `diff`). Nothing in
either file says the twin exists. This is the textbook agent trap: an agent
asked to tweak a theme colour edits one copy, the compiler is happy, and the
two apps drift visually with no error anywhere.

**Proposed fix:** Move the file to
`Packages/DeuceMateCore/Sources/DeuceMateCore/` (e.g. `Theme/AppTheme.swift`)
and delete both app copies. Core gaining `import SwiftUI` is fine — Apple
framework, and the package platforms (iOS 16 / watchOS 9 / macOS 13) all have
the APIs used. No `project.pbxproj` edit is needed for either the addition or
the deletions (package globs; app targets are file-system-synchronized).

**Why medium:** Low effort, removes 220 duplicated lines and a live drift
trap. Until it lands, item 10's checker can cheaply assert the copies remain
identical.

**Key files:** both `AppTheme.swift` copies → new Core file.

---

### 17 — De-duplicate stats scaffolding into Core (Done)

**What was duplicated:** four rules were each re-implemented per surface, with
nothing pointing at the twins:

- The `All / per-set` filter enum and its "a deciding super-tiebreak reads TB"
  label rule (iOS `MatchDetailView`, watch `MatchStatsView`, web export).
- Set/match duration resolution — recorded value first, else the span between
  the set's first and last tracked point (both stats screens, text export, web
  export).
- The `count (percent)` / `made/attempted (percent)` strings and the
  comparison-row fraction/percent/count triple (both stats screens, both
  exports).
- The watch's compact hyphen-separated score line, built twice (stats header
  and history rows) plus a third partial copy for in-progress matches.

**Fix:** `Stats/SetFilter.swift`, `Stats/MatchDurations.swift`,
`Stats/StatFormatting.swift` (incl. `RatioDisplay`) and
`Stats/CompactScoreLine.swift` in Core; every call site now delegates. The
deliberate difference between the exports (percentages truncated) and the
points-won headers (rounded) is preserved as two named functions rather than
two unexplained expressions, and the watch's narrow labels are a `LabelStyle`
on the shared enum.

**Key files:** the four new Core files; `MatchDetailView`, `MatchExporter`,
watch `MatchStatsView` / `MatchHistoryView`, `MatchWebViewModel+Build`,
`MatchWebViewModel+Comparison`.

---

### 12 — Extract the point-categorisation flow state machine into Core

**What:** `PointCategorySheet.swift` (watch, 261 lines) and
`LivePointCategoryPanel.swift` (phone, 222 lines) hand-mirror the same
two-step flow: pick a `PointOutcome`, then (when detailed shot tracking is on
and the outcome warrants it) pick an `EndingShot`. Both filter
`userSelectable` cases, both decide identically when step 2 applies, both
reset the same way. `CLAUDE.md` documents the phone panel as "mirrors the
watch sheet" — the mirroring is maintained by hand, and the §4 recipe for
adding an outcome requires touching both.

**Proposed fix:** Add a small value type in Core (e.g.
`PointCategorizationFlow`): exposes the selectable outcomes, whether an
ending-shot step applies for a given outcome + settings, and
`advance`/`reset` transitions. Both views render from it; the logic gets Core
tests. Adding an outcome then needs one logic change plus per-app cosmetics.

**Why medium:** Real logic duplication (not just similar UI), directly reduces
a documented multi-site recipe, and is testable in the cheap target.

**Key files:** `PointCategorySheet.swift`, `LivePointCategoryPanel.swift`,
new Core file + tests.

---

### 13 — Split `PastMatchesView`

**What:** 705 lines — up 51% from the ~468 recorded at the original audit, the
fastest-growing file in the repo (storage-location indicators, iCloud status
strip, filtering, deletion flows all accreted here). Not yet a problem, but it
is on the `ScoreViewModel` trajectory.

**Proposed fix:** Split along feature boundaries into extension files (row
view, storage/iCloud badges, toolbars/filters). Since the app targets use
file-system-synchronized groups (item 8), new files need no `project.pbxproj`
edit — the historical reason for avoiding app-target splits is gone. Add
`MARK:` anchors while there.

**Why low:** No correctness risk today. Do it opportunistically the next time
the file is touched, before it crosses ~1k lines.

**Key files:** `PastMatchesView.swift`.

---

### 14 — Hygiene: force-unwrap, placeholder test targets

**What (a):** `PointsGraphView.swift:325` uses `realSteps.first!.cumulative`.
It is guarded by a count check a few lines up (`:322`), so it cannot trap — but
`CONTRIBUTING.md` bans force-unwraps outright and review is supposed to
enforce that, so the one counterexample in the codebase weakens the rule
(especially for agents that learn style from surrounding code).

**What (b):** The iPhone unit-test target is a 12-line placeholder
(`DeuceMateTests/DeuceMateTests.swift`) and both UITest targets contain only
the Xcode template stubs (`testExample`, `testLaunchPerformance`). They add
scheme noise and imply coverage that doesn't exist. Meanwhile the watch test
target is real (36 Swift Testing tests) and Core has 378.

**Proposed fix / status:** (a) ✅ Done — replaced `realSteps.first!`
with `realSteps[0]`; the count guard at line 322 still applies, no behaviour
change. (b) Either write one minimal real phone-side test (e.g. `PhoneStatsStore`
save/load round-trip in a temp directory) or delete the placeholder files; per
`CLAUDE.md` §3 test-deletion rules, removing the stubs needs explicit owner
approval in the PR.

**Why low:** Minutes of work, no behaviour change; mostly about keeping the
stated rules true.

**Key files:** `PointsGraphView.swift`, `DeuceMateTests/`,
`DeuceMateUITests/`, `DeuceMate Watch AppUITests/`.

---

### 15 — Localization (Parked)

**What:** There is no localization infrastructure at all — zero
`NSLocalizedString` / String Catalog (`.xcstrings`) usage; every user-facing
string in both apps is hardcoded English (200+ literals), and stats labels are
formatted with English conventions.

**Why parked:** Single-market product decision, like item 5 — the code is not
wrong, the product simply isn't localized. If internationalization is ever
wanted: adopt Xcode String Catalogs, and note that Core's `SettingsCopy` /
`ICloudBackupCopy` pattern (centralised copy, unit-tested) is the right shape
to extend — item 7's `RatioStat` would also need to happen first for
locale-aware number formatting.

### 16 — Drop HealthKit date-of-birth read; user-entered birth year; remove dead computed max-HR path (Done, 15 July 2026)

**What changed:** Max HR (which defines the Pulse Coach heart-rate zones) is now
resolved as `manual override → 220 − age → 190` — see `HRZone.resolveMaxHR`.
Removed:
- The HealthKit `dateOfBirth` read: `WorkoutManager` no longer requests the
  characteristic, and `requestBirthYearAuthorization` / `fetchBirthYearFromHealth`
  are deleted. Birth year is now entered by the user in the Birth Year picker on
  either app.
- The `userBirthYearFromHealth` provenance flag (wire key, `SyncIncomingPayload`
  case, both sync services, and the "From Health record" UI on both apps).
- The dead computed-percentile path: `maxHRComputed` (phone `UserDefaults`, never
  written), the `pulseCoachMaxHR` wire key + watch `@Published` mirror, and the
  `historical99thPct` parameter of `resolveMaxHR`. The phone previously pushed a
  resolved max HR to the watch; the watch now computes the identical value locally
  from the synced birth year + override, so the push is gone.

**Why:** Three reasons. (1) Shrinks the HealthKit surface — one fewer read, a
shorter first-launch authorization prompt, and date of birth out of the
`NSHealthShareUsageDescription`, privacy policy, and App Review notes. (2) Removes
the only genuinely HealthKit-derived value that lived in `UserDefaults` (the
birth-year provenance flag), which mattered ahead of the device-backup exclusion
work — see `SUBMISSION_REVIEW.md` Blockers 3 & 4. A user-entered birth year is not
HealthKit data, so it can remain in `UserDefaults`. (3) The computed-percentile
branch was dead (`maxHRComputed` was never written), so `resolveMaxHR` carried a
permanently-nil parameter and a misleading doc comment. Zone math is otherwise
unchanged — no user's zones move.

**Coupling exercised:** This was a multi-site synced-setting removal (the trap in
items #3 and #10) — the same value lived as a raw string across `MatchSyncKey`,
`SyncIncomingPayload`, both sync services, and `@AppStorage`/`UserDefaults` in the
views. All sites were updated together; the CLAUDE.md §0 grep confirms no orphan
literals remain.

**Future direction:** iOS 27 / watchOS 27 expose the user's own system-calculated
or hand-edited heart-rate zones via `HKWorkout.zoneGroupsByType`
(`HKWorkoutZoneConfiguration`, `HKLiveWorkoutBuilderDelegate.didUpdateWorkoutZone`).
Since the app already creates an `HKWorkoutSession` per match, adopting that API
(gated by `#available`, post-1.0 on the iOS 26 SDK) would replace local max-HR
derivation entirely with Apple's own zones.

**Device-backup follow-up completed 15 July 2026:** The Health-derived match
values this cleanup prepared for now live in the phone's backup-excluded Health
sidecar rather than its normally backed-up canonical history. The watch history
and live-state files are also marked backup-excluded after every save. See
`HealthSidecarPolicy`, `PhoneStatsStore`, and `SUBMISSION_REVIEW.md` Blocker 4.

---

### 18 — Persisted enums are additive-only; archives decode atomically

**What:** Six enums reach persisted JSON — `MatchFormat`, `MatchType`, `Player`,
`DoublesServer`, `PointOutcome`, `EndingShot` — and none has an unknown-value
fallback in its `Codable` conformance. Removing or renaming a case makes every
file that contains the old raw value undecodable.

`decodeIfPresent` is not a defence: it returns `nil` for a *missing* key but
throws for a key that is present with an unrecognised value.

**Why it matters more than it looks — the decode is atomic.** Both archives
decode `[MatchRecord]` in a single call (`StatsStore._loadHistoryUnsafe`,
`PhoneStatsStore.readCanonicalFile`), so **one** point in **one** old match takes
down **every** match in the file. A format played twice a year ago costs the
whole archive. The cascade, worst first:

1. **Phone archive quarantined.** `readCanonicalFile` moves `matchHistory.json`
   aside to `.corrupt` and the store starts from an empty list.
2. **iCloud backup overwritten.** `pushBackupOnQueue` builds its snapshot
   straight from `records` with no emptiness floor, and `lastPushedSnapshot` is
   per-process — so the next push writes the now-empty archive over the backup.
   This is the only irreversible hop; everything else leaves a file on disk.
3. **Watch archive invisible and silently read-only.** `loadHistoryOrNil()`
   returns `nil`; the refuse-to-overwrite guard correctly protects the file, but
   `appendMatch` then bails, so every subsequently finished match is dropped
   without a word.
4. **Live match reset.** `loadState()`'s catch resets in-memory state and the
   next `saveState()` overwrites `appState.json`.

**Rule (documented):** `CLAUDE.md` §4 now carries a "Retire a case in a persisted
enum" recipe — keep the case decodable forever, hide it from the user-facing list
(`PointOutcome.userSelectable` is the existing pattern), and never fall back to a
wrong value such as `.standard`, which would re-render an old match's score in
the wrong shape.

**Guards still backlog, cheapest first:**

- **Pin the raw values in tests.** `ScoreTypesTests.test_doublesServer_rawValuesArePersistedIdentifiers`
  (added in #104) already does this for `DoublesServer` — extend the pattern to
  the other five. Deterministic, zero runtime cost, fails in Xcode before the
  code reaches a device. This is the real fix; the rest is defence in depth.
- **Floor the backup push — but qualify the floor by tombstones.**
  `pushBackupOnQueue` builds its snapshot straight from `records` with no floor,
  so a corrupt-load `[]` can overwrite a good backup. A naive "never push an
  empty or smaller snapshot" guard would be **wrong**: `deletePermanently`
  legitimately shrinks the record set — deleting the only match yields
  `records: []` — and that emptiness has to reach iCloud, or a fresh install
  restores matches the user deleted. The rule is whether the shrinkage is
  *explained*: every id that disappeared since the state being overwritten
  should appear in `snapshot.tombstones`. Unexplained shrinkage is the
  corrupt-archive case — withhold and report it. Two details that make this
  tractable: `backupSnapshot` already filters records by tombstones and carries
  the tombstone set, and `initialRestore` unions local with backup tombstones
  and filters backup records by the union — so the tombstone file is purely
  additive and should always be written, even when the record write is withheld.
  (`lastPushedSnapshot` is per-process, so a first push after launch has no
  in-memory baseline to diff against and must read the remote or skip the check.)
- **Decode the archive element-wise.** A `Lossy<T>` wrapper
  (`init(from:) { value = try? T(from: decoder) }`) over `[MatchRecord]` removes
  the amplifier — 24 of 25 matches survive instead of none. Count the drops and
  surface them rather than compacting silently.
- **Reconsider `.corrupt` vs `.unreadable` on the phone.** `CanonicalRead`
  already has a non-destructive hard stop (`.unreadable` suspends writes and
  leaves the file untouched). A well-formed file the app merely cannot map is
  arguably that case, not a quarantine.

**Not the answer:** a `fatalError` in the catch. `loadState()` runs on every
launch, so the bad value on disk produces a crash loop whose only user-side
remedy is deleting the app — which takes the sandbox, and the `.corrupt` file,
with it. `assertionFailure()` gives the same signal in Debug and compiles away in
Release.

**Key files:** `ScoreTypes.swift`, `PointStat.swift`, `StatsStore.swift`,
`PhoneStatsStore.swift` (`readCanonicalFile`, `pushBackupOnQueue`),
`ScoreViewModel.swift` (`AppState`, `loadState`).

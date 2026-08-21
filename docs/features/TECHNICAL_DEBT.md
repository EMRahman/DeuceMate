# Technical Debt & Improvement Backlog

Captured from a Codex-assisted audit of the codebase, then re-verified
item-by-item against the code and extended with agent-operability
findings in a Claude-assisted re-audit. Each item has been
reviewed, contextualised against the actual runtime behaviour, and
prioritised.

**How this file is organised.** Everything still needing attention is at the
top — the [open items](#open-items) table, ranked highest work-priority first,
then detail sections grouped by subject. Work that has landed (and the one item
parked on a product decision) is kept in full at the bottom under
[Archive](#archive--completed-and-parked-items); it is history worth reading
before re-opening the same ground, not a queue.

**Item numbers are permanent.** `CLAUDE.md`, `docs/release/SUBMISSION_REVIEW.md`,
`KNOWN_LIMITATIONS.md` and several feature plans cite items by number
("TECHNICAL_DEBT #18"). Numbers are never renumbered or reused when the
ordering changes, and a completed item keeps its number in the archive.

**How priorities are weighted.** The table deliberately separates two things
that the earlier version of this document conflated:

- **Application risk** is the severity and likelihood of harm to a user or
  their data. `Critical impact / low–medium likelihood` is different from a
  routine maintainability problem even when both deserve work.
- **Work priority** also accounts for exposure, prerequisites, effort, and
  engineering leverage. A comment-only navigation improvement can be a very
  good quick win without being a high application risk; a currently safe sync
  design can carry a mandatory trigger before its transport strategy changes.

DeuceMate is developed primarily by AI coding agents working in cloud
environments *without a Swift toolchain* (the owner runs Xcode locally). Agent
effectiveness therefore remains a real input: accurate docs, navigable files,
text-level checks, and recorded local verification substitute for a compiler in
many sessions. They no longer masquerade as runtime severity, however.

---

## Open items

Ranked. Application risk describes the app as it exists; the work band says
when the item should constrain future changes.

| # | Area | Item | Application risk | Work band / trigger | Effort |
|---|------|------|------------------|---------------------|--------|
| [18](#18--fail-closed-on-undecodable-archives-persisted-enums-are-additive-only) | Persistence | Fail closed on undecodable archives; add persisted-enum guards | **Critical impact; low–medium likelihood** | **Now** | Medium, staged |
| [4a-read](#4a-read--fail-closed-on-an-unreadable-live-state) | Persistence | Preserve and report an unreadable watch live state | **High** | **Now**, in the persistence-safety programme | Medium — PR #108 exists to re-read |
| [19](#19--version-the-persisted-json-formats-forward-compatibility) | Persistence | Version persisted JSON and wire formats | **High when schemas diverge** | **Before any persisted-model, enum, or wire-shape change** | Medium |
| [3](#3--replace-stringly-typed-settings-keys-with-typed-keys) | Settings | Replace stringly-typed settings keys with typed keys | Medium today; **high change risk** | Next engineering-risk cleanup after persistence containment | Large, splittable per setting category |
| [20](#20--make-health-derived-field-classification-mechanically-exhaustive) | Health/Privacy | Make Health-derived field classification mechanically exhaustive | No current bug; **high privacy risk on expansion** | Before adding any Health-derived field or export surface | Medium design; small first guards |
| [4a-write](#4a-write--surface-save-failures) | Persistence | Surface live-state and archive save failures | Medium impact; low likelihood | After, or alongside, read containment | Small–medium |
| [11](#11--de-duplicate-appthemeswift-into-core) | Duplication | De-duplicate `AppTheme.swift` (still byte-identical) | Medium change risk | Before the next theme edit | Small |
| [12](#12--extract-the-point-categorisation-flow-state-machine-into-core) | Duplication | Extract point-categorisation flow state machine into Core | Medium change risk | Before the next outcome / ending-shot change | Medium |
| [21](#21--record-an-executable-local-verification-gate) | Verification | Record an executable local verification gate | Medium regression/process risk | Establish now; require for scoring, persistence, and sync PRs | Small |
| [9](#9--mark-anchors-for-scoreviewmodel-homeview-contentview) | Navigability | `MARK:` anchors for `ScoreViewModel` / `HomeView` / `ContentView` | **None at runtime** | Independent quick win | Small — comment-only |
| [2](#2--add-a-monotonic-record-revision-before-queued-checkpoints) | Sync | Add a monotonic record revision for merge policy | Low today | **Mandatory before queueing live checkpoints** | Small |
| [6](#6--phonestatsstore-concurrency-model) | Concurrency | `PhoneStatsStore` actor / `@MainActor` migration | Low today | Before Swift 6 strict concurrency or new background mutation paths | Medium |
| [7](#7--convert-formatted-string-stats-to-typed-values-in-matchstatssummary) | Stats | Convert formatted string stats to typed `RatioStat` | Low | Before localization, structured stats export, or graphing | Small, mechanical, Core-only |
| [13](#13--split-pastmatchesview) | Architecture | Split `PastMatchesView` (745 lines, still the fastest-growing file) | None today | Opportunistically on the next substantial edit | Small |

**Read 18, 19 and 4a together.** They are one persistence-safety programme —
what happens when a persisted file cannot be decoded — and each fix constrains
the others'. #4a's PR was closed unmerged for exactly this reason. Sequence the
programme by safety rather than by cheapest patch:

1. **Fail closed at the origin.** A readable-but-undecodable canonical history
   or tombstone file must suspend canonical writes and iCloud pushes; an
   unreadable/undecodable live state must not be overwritten by the next point.
2. **Land the cheap guards immediately, without calling the programme done.**
   Pin all persisted-enum raw values and add the missing corrupt-main-file tests.
3. **Add version envelopes and refuse-to-overwrite-newer semantics** (#19),
   including an older-version policy for manual exports.
4. **Add the tombstone-qualified backup floor** (#18) as defence in depth.
5. **Offer explicit recovery.** Preserve the original bytes and make any lossy,
   element-wise salvage a reported recovery operation, never the default read.

---

## Archive

Completed, or parked with a recorded reason. Full write-ups are
[at the bottom of this file](#archive--completed-and-parked-items).

| # | Area | Item | Outcome |
|---|------|------|---------|
| [1](#1--extract-scoring-engine-done) | Architecture | Extract scoring engine into pure Core reducer | **Done** — `Scoring/ScoringEngine.swift` |
| [4b](#4b--file-protection-level-on-watch-saves-done) | Persistence | File-protection level on watch saves | **Done** — Class B on both watch writers; residual gap recorded |
| [5](#5--simplify-first-run-and-match-start-ux-done) | UX | Simplify first-run and match-start flow | **Done** — [`MATCH_START_UX_PLAN.md`](MATCH_START_UX_PLAN.md); 5 taps → 3 |
| [8](#8--fix-claudemd-drift-done) | Agent docs | Fix `CLAUDE.md` drift (pbxproj claim, ghost files, stale sizes) | **Done** — plus a standing re-check practice |
| [10](#10--settings-key-consistency-check-done) | Tooling | Settings-key consistency check | **Done** — grep in `CLAUDE.md` §0; #3 is the real fix |
| [14](#14--hygiene-force-unwrap-placeholder-test-targets-done) | Hygiene | Force-unwrap; placeholder test targets | **Done** — force-unwrap removed; the phone test targets are real now |
| [16](#16--drop-healthkit-date-of-birth-read-user-entered-birth-year-remove-dead-computed-max-hr-path-done-15-july-2026) | Health/Privacy | Drop HealthKit date-of-birth read; user-entered birth year | **Done** — 15 July 2026 |
| [17](#17--de-duplicate-stats-scaffolding-into-core-done) | Stats | De-duplicate set filters, durations, percent strings, compact score | **Done** — four new Core files |
| [15](#15--localization-parked) | i18n | Localization (all UI copy is hardcoded English) | **Parked** — product decision, not code |

---

## Open items — detail

### 3 — Replace stringly-typed settings keys with typed keys

**What:** A setting's identity currently lives as a raw string in 2–3 places
the compiler does not connect: a `MatchSyncKey` constant, a `UserDefaults`
call in `ScoreViewModel`, and a matching call in `WatchMatchSyncService` /
`PhoneMatchSyncService` (plus `@AppStorage` literals in the iPhone
`SettingsView`). Changing one and missing another produces a silent
settings-sync bug. `ScoreViewModel` has 23 executable `UserDefaults.standard`
call sites (re-counted 21 August 2026; a 24th grep match is a doc comment);
only 7 use `MatchSyncKey` directly.

**It is worse than simple duplication — one setting already uses three
different strings.** The announcements toggle is persisted on the watch as
`"phoneAnnouncementsEnabled"` (`ScoreViewModel.swift:89`), travels the wire as
`MatchSyncKey.announcementsEnabled` = `"announcementsEnabled"`
(`MatchSyncMessage.swift:49`), and is persisted on the phone as
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

**Risk and work priority:** The current keys were re-checked and are consistent,
so this is not a known runtime bug. It is a **medium application risk today but
a high change risk**: the next setting edit can create a silent sync/reset bug
with no compiler signal. CLAUDE.md §5 flags it explicitly as an AI trap. Do it
after the persistence containment work, scoped one setting category at a time
to keep the large mechanical change reviewable. Until it lands, item 10's grep
is the only guard.

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

### 9 — `MARK:` anchors for `ScoreViewModel`, `HomeView`, `ContentView`

**What:** `CLAUDE.md` instructs agents to "read only the `MARK:` section you
need" — but the prescribed navigation is impossible in exactly the files where
it matters most. Current anchor counts (re-counted 21 August 2026, and all
three files have grown since the last audit): `ScoreViewModel.swift` **1 MARK in
1974 lines**, `HomeView.swift` **0 in 959**, `ContentView.swift` **4 in 989**.
By contrast `PointsGraphView.swift` (9 MARKs / ~1870 lines) shows the target
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

**Risk and work priority:** **No runtime risk.** This remains the cheapest
independent change in the document with a compounding payoff for every future
agent session in the three most-touched watch files. Treat it as a quick win,
not as evidence that it outranks user-data containment.

**Key files:** `ScoreViewModel.swift`, `HomeView.swift`, `ContentView.swift`.

---

### 18 — Fail closed on undecodable archives; persisted enums are additive-only

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

**The same break runs in both directions.** *Adding* a case is safe for a new app
reading old data, but an **old** app reading data a newer one wrote hits the
identical `DecodingError` — `init(rawValue:)` returns `nil` for a case it does
not have. So "additive-only" protects new-reads-old; nothing here protects
old-reads-new. See #19.

**Rule (documented):** `CLAUDE.md` §4 now carries a "Retire a case in a persisted
enum" recipe — keep the case decodable forever, hide it from the user-facing list
(`PointOutcome.userSelectable` is the existing pattern), and never fall back to a
wrong value such as `.standard`, which would re-render an old match's score in
the wrong shape.

**Application risk: critical impact, low–medium likelihood.** Corruption and
schema divergence are uncommon, but the failure amplifier spans the whole
archive and the iCloud overwrite is irreversible. This is the first runtime
risk to contain.

**Safest implementation sequence:**

- **Fail closed on score-bearing canonical data first.** A readable file that
  cannot be decoded is not an empty archive. A decode failure in either the
  canonical match history or its tombstones must preserve/quarantine the bytes,
  suspend canonical writes, and suppress iCloud pushes for the process — the
  same hard stop `.unreadable` already provides. The Health sidecar is different:
  it is a reconstructable projection and may continue to degrade independently
  without blocking score persistence.
- **Pin the raw values in tests immediately, but state the limit accurately.**
  `ScoreTypesTests.test_doublesServer_rawValuesArePersistedIdentifiers` (added
  in #104) already does this for `DoublesServer`; extend the pattern to the other
  five. This cheaply catches deletion, renaming, and raw-value drift. It does
  **not** protect an old client from a newly added case, arbitrary corrupt JSON,
  a missing required field, or an unbumped schema version, so it is a guard —
  not the complete fix.
- **Add the version/refuse-to-overwrite shape in #19.** Decode failure and
  unsupported-newer-format are different diagnoses even though both must block
  automatic writes.
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
- **Make element-wise decode an explicit recovery tool, not the normal read.**
  A `Lossy<T>` wrapper can recover 24 of 25 records, but if the app then saves
  that partial result it silently makes the rejected record's loss permanent.
  Keep the original file, report the number and ids of dropped records where
  possible, require a deliberate recovery action, and do not resume automatic
  backup until the recovered state is accepted.

**Tests required by the first containment PR:** a readable-but-undecodable main
history suspends writes; a corrupt tombstone file does the same; neither state
pushes an empty backup; and a legitimate tombstoned deletion — including
deleting the only match — can still push a smaller or empty archive.

**Not the answer:** a `fatalError` in the catch. `loadState()` runs on every
launch, so the bad value on disk produces a crash loop whose only user-side
remedy is deleting the app — which takes the sandbox, and the `.corrupt` file,
with it. `assertionFailure()` gives the same signal in Debug and compiles away in
Release.

**Key files:** `ScoreTypes.swift`, `PointStat.swift`, `StatsStore.swift`,
`PhoneStatsStore.swift` (`readCanonicalFile`, `pushBackupOnQueue`),
`ScoreViewModel.swift` (`AppState`, `loadState`).

---

### 19 — Version the persisted JSON formats (forward compatibility)

**What:** Backward compatibility — a *new* app reading *old* data — is well
covered: the §4 `decodeIfPresent` recipe, enforced in review and pinned by
`MatchRecordCodingTests`. The opposite direction has no defence and, more
importantly, **no way to detect that it is happening**.

Current state of the four persisted formats:

| Format | Version field | Behaviour on data from a newer app |
|---|---|---|
| `appState.json` (watch live state) | `version: Int` — **present, required, and never read** (decoded at `ScoreViewModel.swift:528`, branched on nowhere) | none |
| `matchHistory.json` (watch + phone canonical archive) | none — a bare `[MatchRecord]` array | none |
| WatchConnectivity wire format | none | none |
| Manual archive export/import | `schemaVersion`, rejected via `ArchiveError.unsupportedSchemaVersion` | detected and refused legibly — but see the equality-gate caveat below |

**Why this repo is exposed, specifically.** The generic version of this risk is
about staggered updates across devices. Here the real path is closer to home:
the **watch app and the iPhone app are separate installs that can sit on
different versions**, and they exchange `MatchRecord` JSON continuously. An App
Store downgrade never happens; a mixed-version pair happens routinely.

What that looks like today, if a newer watch sends a case an older phone lacks:

- **Live payloads degrade correctly.** `SyncIncomingPayload.decode` wraps each
  key in its own `do`/`catch` and emits `.decodeError(key:error:)`; the phone
  logs it and drops that one event, keeping the rest.
- **History pushes fail wholesale.** `MatchSyncMessage.decodeArray` decodes
  `[MatchRecord]` in a single call, so one unknown value kills the entire
  transfer. Nothing crashes and nothing is reported — the sync simply
  accomplishes nothing until both sides update. Same atomic-array amplifier as
  #18.

**Application risk: high when schemas diverge.** There is no known version-2
payload today, but the watch and phone routinely run different app versions.
This item is therefore a hard prerequisite for any persisted enum/model or
wire-shape change, not general cleanup to schedule afterwards.

**Proposed compatibility rollout:**

1. **Read the version that already exists.** `AppState.version` is stored and
   required but inert. A `guard` against a version higher than the build
   understands costs almost nothing and is already wired through the codec.
2. **Give the archive and the wire format a top-level version.** Copy
   `ManualMatchArchiveBackup`'s *envelope and its user-facing error* — it is the
   one format that fails legibly rather than mysteriously — but **not** its
   comparison. `validate` gates on `schemaVersion == supportedSchemaVersion`
   (strict equality), which is indistinguishable from `<=` only because 1 is the
   only version that has ever existed. A persistent store needs three branches,
   not one:
   - `version > supported` → refuse to read **and** refuse to write over it
   - `version < supported` → migrate, or decode via the older shape
   - `version == supported` → normal path
3. **Make the gate a refusal to _write_, not just to read.** This is the half
   that actually prevents data loss: an old client that encounters a newer
   version must leave the file alone rather than resetting and saving over it.
   A read-only refusal still loses the data on the next save.
4. **Ship the version-1 envelope and gate before using version 2.** Forward
   refusal only protects clients that already know how to inspect the version.
   First release readers that accept the legacy bare array and the version-1
   envelope; only a later release should emit a genuinely incompatible shape.
   Old clients predating the gate will still drop an unfamiliar sync payload,
   but the new envelope must never make them overwrite local storage.

Two caveats on (2). First, a version gate only fires if someone remembers to
bump the number: adding an enum case does not bump `supportedSchemaVersion`
automatically, so an export from a newer app would still claim version 1, sail
past the check, and throw a raw `DecodingError` instead of the clean message.
Worth a comment next to that constant.

Second — and this is a latent bug in `ManualMatchArchiveBackup` itself, not just
a bad pattern to copy — **the first bump breaks every existing export.** The
moment `supportedSchemaVersion` becomes 2, the equality check rejects every
version-1 archive a user has already saved, with "this archive was created by a
different version of DeuceMate". Their own backup file becomes unimportable by
the newer app, which is the opposite of what a backup format is for. Replace
the equality gate with an explicit set/range of versions for which a decoder or
migration actually exists. Do not blindly accept every `<=` value — version 0
or an otherwise unknown old shape is not safe merely because its number is
smaller. Establish the version-1 branch *before* the first bump, not as part of
it.

**External guidance reviewed, and what applies here.** This is a recognised
class of bug (decode failure → treat as empty → write the empty state back →
the empty file becomes the truth). Assessed against this codebase:

*Applies:*

- Decode-failure-then-write-empty is the phone's exact path today
  (`readCanonicalFile` → `.corrupt` → `loadedRecords = []` →
  `pushBackupOnQueue` with no floor). Tracked in #18.
- "Never silently replace on failure; move the original aside." Partially done:
  the watch `StatsStore` read guard (#4b) and the phone's `.corrupt` quarantine
  both do it; `appState.json` does not.
- Version plus refuse-to-overwrite-newer. Missing everywhere. The manual archive
  has the version and detects a mismatch, but refuses symmetrically rather than
  only refusing *newer*, and it never writes back over the imported file, so it
  does not demonstrate the overwrite half either.

*Does not apply — recorded so it is not re-litigated:*

- **`Codable` blobs in `UserDefaults`/`@AppStorage`.** DeuceMate stores only
  scalars there (`Bool`, `Int`, `String`, `Double`), so the "decode fails →
  default returned → default saved over the data" variant has no foothold.
- **`NSUbiquitousKeyValueStore` overwrite limits.** Not used.
- **Multi-device last-writer-wins propagation.** The iCloud copy is a one-way
  backup: it is read only during initial local archive setup, gated by
  `archiveInitialized.json`. The exposure is "an empty local archive overwrites
  the backup", not "device A wipes device B".
- **Core Data / SwiftData + CloudKit.** Genuinely more robust for schema
  evolution, and the reason CloudKit locks production schemas to additive
  changes — but adopting it is a re-architecture of the whole persistence layer.
  Noted for completeness, not proposed.

*One correction to the general advice:* the usual compatibility table says
"field removed → usually fine". That holds for **fields** — `JSONDecoder`
ignores unknown keys, pinned by `MatchRecordCodingTests`. It does **not** hold
for **enum cases**, where both adding and removing break the reader. That is
this repo's actual exposure, and it is why #18 exists as a separate item.

**Key files:** `ScoreViewModel.swift` (`AppState.version`),
`Persistence/StatsStoring.swift` (the unversioned archive codec),
`Sync/MatchSyncMessage.swift` (`decodeArray`), `Sync/SyncIncomingPayload.swift`,
`Persistence/ManualMatchArchiveBackup.swift` (envelope and error copy worth
reusing; its equality gate is not).

---

### 4a — Persistence health: unreadable live state and save failures

The old item combined a high-impact read path with a low-likelihood save path
and then gave the pair one ambiguous priority. Keep the permanent #4a reference,
but treat its two deliverables separately.

#### 4a-read — Fail closed on an unreadable live state

**What:** `loadState()` catches a missing file, an I/O failure, corrupt JSON,
and a future-schema decode failure identically. It resets roughly 20 fields to
a fresh match. `saveState()` runs on the next point and can then overwrite the
checkpoint it merely failed to read. A transient protection/I/O problem or one
unknown persisted enum can therefore erase the live match within one point.

**Application risk: high.** The probability is low, but a live tennis score is
time-sensitive and often cannot be reconstructed after play continues. The
watch archive already understands “read failure ≠ empty”; live state does not.

**Proposed fix:** Distinguish “file genuinely absent” (normal first launch) from
“file exists but could not be read/decoded”. Preserve or quarantine the latter,
publish a critical persistence state, and block automatic state overwrite until
the user explicitly abandons/resets or a recovery succeeds. Pair it with #19's
`version > supported` diagnosis so “newer format” is reported accurately rather
than called corruption. User-facing copy must say only what the app can really
do; retaining bytes is not the same as offering a recovery path.

**Attempted and closed: PR #108.** It reported failures through a shared
`PersistenceHealth` model in Core, moved the unreadable file aside before the
reset, promoted a failed restore to `.critical`, and added a scoreboard chip so
a mid-match failure is visible where it happens. Verified green locally (Core,
watch and iOS suites). Closed unmerged pending the wider persistence programme,
not because the work was wrong. Re-read it before re-attempting. Findings to
resolve: stale inventory counts, copy promising unavailable recovery, no cleanup
policy for quarantined files, and `persistenceHealth` not clearing on an
intentional `resetMatch()`.

#### 4a-write — Surface save failures

**What:** The watch live-state writer reports failure only through a `print`
inside `#if DEBUG`; release builds emit nothing. The two history stores use
`os.Logger`, which reaches the unified log but not the person continuing to
score. Failed phone canonical writes also publish the new in-memory archive even
though it may disappear on process termination.

**Application risk: medium impact, low likelihood.** Class-B protection and
atomic writes make failure uncommon, but storage/I/O failures still mean the
latest score or archive mutation is not durable.

**Proposed fix:** Reuse the persistence-health model established by 4a-read.
Show a small but visible warning on the live scoreboard for live-state failure,
and on history/settings for archive failure. Clear it only after a successful
write or a deliberate reset that the model defines as resolving the condition;
do not clear it merely because the view disappeared.

---

### 2 — Add a monotonic record revision before queued checkpoints

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

**Proposed fix:** Add a monotonic `revision: UInt64` to `MatchRecord`, incremented
by the source watch on every state mutation, including undo. Update Case 5 to
accept an incoming in-progress record only when its revision is greater than or
equal to the existing revision. Decode old records with
`decodeIfPresent(UInt64.self, forKey: .revision) ?? 0` under the §4
compatibility recipe: two legacy revision-0 checkpoints retain today's “latest
arrival wins” behaviour, while a legacy checkpoint cannot roll back an already
revisioned one.

Use the revision — not a wall-clock `lastModified` date — as the ordering
primitive. Device time can move backwards and two rapid mutations need not have
distinct timestamps. A `lastModified` date may still be useful for display or
diagnostics, but it should not decide which queued checkpoint wins.

Once revision ordering exists, the transport can safely queue a bounded
“latest live checkpoint” when unreachable, improving phone archive freshness
during BLE gaps. Currently the phone can lag for the whole gap.

**Risk and trigger:** **Low today.** The transport intentionally drops
unreachable in-progress checkpoints, so the stale queued-arrival path does not
exist. Make this a mandatory prerequisite — in the same PR or an immediately
preceding one — before any transport change starts queueing them.

**Key files:** `MatchRecord.swift`, `MatchMergePolicy.swift`,
`MatchSyncTransport.swift`, `MatchRecordCodingTests.swift`,
`MatchMergePolicyTests.swift`.

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

**Risk and trigger:** **Low today.** This is a clean, bounded change with useful
future benefits but no current correctness failure. Do it before localization,
structured stats export, or graphing needs the discarded values (or elevate it
sooner if the current VoiceOver rendering becomes a release requirement). The
`pct(num:den:)` helper in `MatchStatsSummary` can remain the formatter.

**Key files:** `MatchStatsSummary.swift`, both apps' stats/export views,
`MatchStatsSummaryTests.swift`.

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

**Risk and trigger:** **Medium change risk, no known drift today.** Low effort
removes 220 duplicated lines and a silent cross-platform drift trap. Land it
before the next theme edit. Until then, a direct `cmp`/`diff` of the two files —
not item 10's settings-key grep — is the appropriate pre-push guard.

**Key files:** both `AppTheme.swift` copies → new Core file.

---

### 12 — Extract the point-categorisation flow state machine into Core

**What:** `PointCategorySheet.swift` (watch, 336 lines) and
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

**Risk and trigger:** **Medium change risk.** This is real logic duplication,
not just similar UI, but both copies agree today. Make it a prerequisite for
the next `PointOutcome` / `EndingShot` or categorisation-flow change; it need not
displace persistence containment before then.

**Key files:** `PointCategorySheet.swift`, `LivePointCategoryPanel.swift`,
new Core file + tests.

---

### 20 — Make Health-derived field classification mechanically exhaustive

**What:** Five HealthKit-derived values currently travel as ordinary
`MatchRecord` / `PointStat` properties, while three separate policies must agree
that they are Health data:

1. `MatchRecord.strippingHealthData()` removes them from the phone canonical
   archive and iCloud snapshot.
2. `HealthSidecarPolicy` projects and reconstructs them in the backup-excluded
   local sidecar.
3. `HealthExportConsent` identifies them before a user export or AI hand-off.

`docs/architecture/health-data-flow.md` documents the manual recipe, but the
compiler does not connect these lists. A sixth field added to the model but
missed by the stripper can enter iCloud in violation of the app's privacy
posture; one missed by consent can be shared without the promised disclosure.
The existing JSON key-absence tests protect the five names they know, not a new
field nobody added to the fixture or denylist.

**Application risk:** No current leak was found and the five existing fields
are covered. The risk becomes **high immediately when Health-derived storage or
an export surface expands**, so this is a trigger item rather than a reason to
rewrite stable code today.

**Proposed fix:** Make one Core-owned projection/classification the source for
stripping, sidecar split/merge, and consent-field enumeration. Preserve the
existing flat persisted keys through compatible custom coding if the internal
shape changes; do not trade the privacy fix for a schema break. Until that
design lands, strengthen the contract tests around one full-fidelity sentinel
record and keep the architecture checklist mandatory.

**Cheap first guard:** add the missing dedicated assertion that the watch
`appState.json` file is backup-excluded. It does not solve field exhaustiveness,
but closes the explicit test gap recorded in `health-data-flow.md`.

**Key files:** `MatchRecord.swift`, `PointStat.swift`,
`HealthSidecarPolicy.swift`, `ArchiveBackupPolicy.swift`,
`HealthExportConsent.swift`, and their policy/export tests.

---

### 21 — Record an executable local verification gate

**What:** No GitHub workflow compiles or tests the app. `ci.yml` is a deliberate
Ubuntu placeholder that only echoes `OK`, and many coding-agent environments
have no Swift toolchain. `CLAUDE.md` §3 documents the individual local commands,
but there is no executable all-relevant-suites entry point or required PR
evidence field. The test suites are strong; a green pull-request check is still
not evidence that a Swift change compiled or that any test ran.

**Application risk:** **Medium regression/process risk.** This is not a runtime
bug by itself, but it increases the chance that scoring, persistence, or sync
regressions reach a build precisely where static review is weakest.

**Proposed fix:** Keep the no-paid-macOS-CI decision in `CLAUDE.md`; do not add
Swift work to the Ubuntu placeholder. Instead:

- turn the existing commands into one repository-local verification entry point,
  or explicitly designate the documented sequence as the gate and keep its
  destinations current;
- require PRs touching scoring, persistence, or sync to record the exact local
  command, destination/toolchain, and result supplied by the owner;
- make release-candidate evidence distinguish “statically reviewed” from
  “compiled and tested”; and
- rename or describe the placeholder check clearly enough that nobody reads
  its `OK` as build verification.

This is an evidence gate, not a demand that toolchain-less agents pretend they
ran Xcode. When verification cannot run, the PR should remain explicit about
that gap until the owner supplies it.

**Key files:** `CLAUDE.md`, `CONTRIBUTING.md`, `.github/workflows/ci.yml`, and
the chosen local verification script/documentation.

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

The watch's `StatsStore` (127 lines — grown by the #4b read-failure guard)
uses the same queue-confined pattern. If
the migration happens, do both stores together so the two sides keep
symmetrical concurrency semantics.

**Proposed fix:** Rewrite as an `actor` (or a `@MainActor`-isolated class
backed by an `async` storage helper). Callers `await` mutations; the actor
serialises access without blocking threads.

**Risk and trigger:** **Low today.** The app targets still compile in Swift 5
language mode, the current queue confinement works, and the former iCloud
deadlock path is gone. Promote this to a prerequisite before enabling Swift 6
strict concurrency or adding a new background mutation path; either change
invalidates the assumptions behind the low rating.

**Key files:** `PhoneStatsStore.swift`, `StatsStore.swift`.

---

### 13 — Split `PastMatchesView`

**What:** 745 lines — up 59% from the ~468 recorded at the original audit, and
still the fastest-growing file in the repo (storage-location indicators, iCloud status
strip, filtering, deletion flows all accreted here). Not yet a problem, but it
is on the `ScoreViewModel` trajectory.

**Proposed fix:** Split along feature boundaries into extension files (row
view, storage/iCloud badges, toolbars/filters). Since the app targets use
file-system-synchronized groups (item 8), new files need no `project.pbxproj`
edit — the historical reason for avoiding app-target splits is gone. The file
has picked up 6 `MARK:` anchors since the original audit, so it is navigable —
this is now purely about size.

**Risk and trigger:** **No correctness risk today.** Do it opportunistically on
the next substantial edit, before the file crosses ~1k lines.

**Key files:** `PastMatchesView.swift`.

---

## Archive — completed and parked items

Kept in full: each entry records what the problem was, what was done,
and any residual gap that was accepted rather than fixed.

### 1 — Extract scoring engine (Done)

**What:** `ScoreViewModel` owned rules, settings, sync, HealthKit, haptics,
persistence, undo, and scoring in one ~2.3k-line file. The riskiest logic
(`winPoint`, `losePoint`, `completeSet`, `updateScore`) was untestable without
watchOS.

**Done:** `Scoring/ScoringEngine.swift` (~567 lines) added to Core as a pure
static reducer — `pointWon(by:in:) -> ScoringResult`. State is a value type
(`ScoringState`), side-effects are typed `ScoringEvent`s returned in the
result. `ScoreViewModel` now delegates to the engine
(`ScoreViewModel.swift:1024`) and reacts to events.

**Tests added:** 17 tests in `ScoringEngineTests` covering deuce
cycling, server rotation, break-point detection, snapshot correctness,
changeover event reasons, the shared perspective-neutral game-completion predicate,
all four non-standard formats, and endless formats. Core package test count when
this landed: 378 across 29 test files (41 test files as of 21 August 2026).

**Remaining gap:** The `handleSideChangesAfterTiebreakSetEnd` 4-case switch
(players change × ball-holder changes; `ScoringEngine.swift:551–585`, called
from the set-completion path at `:337`) has no dedicated test. Low risk given
the logic is simple, but worth adding if the area is touched.

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

### 8 — Fix `CLAUDE.md` drift (Done)

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

### 10 — Settings-key consistency check (Done)

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

### 14 — Hygiene: force-unwrap, placeholder test targets (Done)

**What (a):** `PointsGraphView` used `realSteps.first!.cumulative`. It was
guarded by a count check a few lines above, so it could not trap — but
`CONTRIBUTING.md` bans force-unwraps outright and review is supposed to
enforce that, so the one counterexample in the codebase weakened the rule
(especially for agents that learn style from surrounding code).

**What (b):** The iPhone unit-test target was a 12-line placeholder
(`DeuceMateTests/DeuceMateTests.swift`) and both UITest targets contained only
the Xcode template stubs (`testExample`, `testLaunchPerformance`). They added
scheme noise and implied coverage that didn't exist.

**Done (a):** replaced `realSteps.first!` with `realSteps[0]`; the count guard a
few lines above still applies, no behaviour change.

**Done (b), by accretion rather than by this item:** the iPhone unit-test target
is now real — `DeuceMateTests` holds four files (~840 lines): sync-service
behaviour, `MatchExporter`, the AI-prompt capture, and exactly the
`PhoneStatsStore` save/load round-trip this item proposed. `DeuceMateUITests`
gained real flows plus `ScreenshotTests`, and `DeuceMate Watch AppUITests`
gained `LiveMatchScreenshotTests`. Counts as of 21 August 2026: Core 41 test
files, the watch unit target 4 files / 59 `@Test` functions.

**Residual (trivial, needs owner sign-off):** two template stubs still ship —
`testExample` + `testLaunchPerformance` in
`DeuceMate Watch AppUITests/DeuceMate_Watch_AppUITests.swift`, and a leftover
`testLaunchPerformance` in `DeuceMateUITests.swift`. Deleting them is test
deletion under `CLAUDE.md` §3, so it needs explicit approval in whichever PR
does it. They are noise, not a coverage claim, so this is not tracked as open.

**Key files:** `PointsGraphView.swift`, `DeuceMateTests/`,
`DeuceMateUITests/`, `DeuceMate Watch AppUITests/`.

---

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
work — see `docs/release/SUBMISSION_REVIEW.md` Blockers 3 & 4. A user-entered birth year is not
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
`HealthSidecarPolicy`, `PhoneStatsStore`, and `docs/release/SUBMISSION_REVIEW.md`
Blocker 4.

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

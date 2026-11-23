<!--
machine-readable summary (parse this block first)

status: proposal — design only, nothing implemented. No phase starts until the owner signs off on §9.
author: Claude, from an owner request
date: 2026-11-23
feature: "Remind the iPhone user, roughly every 10 matches, to export a full-fidelity match archive file, because it is the only copy that carries Health data and (optionally) private notes to a new iPhone. Never remind again once they choose Don't Remind Me Again."
surfaces: "[Core] pure policy + tests; [iOS] Matches-screen card, Settings toggle and last-export line, shared export flow; browser demo parity. No Watch change, no sync key."
rules:
  - "The reminder only opens the existing export flow. It never exports by itself, never pre-enables private notes, and never changes what the file contains."
  - "Only a successful file export (or a Later tap) resets the count. A cancelled export does not."
  - "Don't Remind Me Again is permanent until the user turns the Settings toggle back on."
  - "No modal, no alert, no local notification: one non-blocking card on the Matches screen."
new_keys: "phone-local only: archiveExportReminderEnabled, archiveExportReminderBaseline, archiveLastExportDate (add to CLAUDE.md §0 exceptions)"
decisions_open: [E1, E2, E3, E4, E5, E6]
-->

# Plan: Remind the user to export a full-fidelity match archive

**Status: proposal. Nothing here is implemented.**

**Read with:** [`ICLOUD_BACKUP_HARDENING_PLAN.md`](ICLOUD_BACKUP_HARDENING_PLAN.md)
(why the iCloud copy has no Health data), [`MATCH_TAGS_PLAN.md`](MATCH_TAGS_PLAN.md)
§4.1 (private notes never leave the phone unless the user opts in),
[`HEALTH_EXPORT_CONSENT_PLAN.md`](HEALTH_EXPORT_CONSENT_PLAN.md) (the export
disclosure), and [`ARCHIVE_SAFETY_PLAN.md`](ARCHIVE_SAFETY_PLAN.md) (which this
plan does not change, §8).

---

## 1. Why

Settings › Backup & Transfer › **Export Match Archive** writes the only copy of a
player's matches that is complete. Every other copy loses something:

| Data | iCloud backup (automatic) | iPhone device backup / restore | Apple Watch | Manual archive file |
|---|---|---|---|---|
| Scores, points, stats, match details (players, competition) | ✅ | ✅ | Newest 25 only | ✅ |
| Heart rate, steps, distance, calories (the five Health fields) | ❌ stripped (Guideline 5.1.3(ii)) | ❌ sidecar is backup-excluded | Newest 25 only | ✅ |
| Private match notes | ❌ never | ❌ notes directory is backup-excluded | ❌ never | ✅ only if the user includes them on export |

The Settings footer already says this ("Before moving to a new iPhone, Export
Match Archive here, then Import it on the new phone"). But that footer is only
read by someone who is already in Settings, and the moment it matters — a lost,
broken or replaced phone — is usually the moment it's too late to export.

A player who records Health data with every match and writes notes after them
builds up exactly the detail the app can't otherwise recover. A light, periodic
nudge, tied to how much new unprotected detail has built up, turns the
existing export into a habit without adding a new backup system.

> **Nuance to keep the copy honest:** on a new iPhone with Apple Health synced
> through iCloud, the match report's *Per-point avg* heart-rate chart may still
> be rebuilt from HealthKit (`HealthKitHRFetcher`). The match's own stored
> values — per-point heart rate and steps, totals for steps, distance and
> calories — are not. Copy must not claim Health data is "gone forever" or
> "always recoverable".

---

## 2. What the user sees

### 2.1 The card

When the reminder is due (§3), the Matches screen (`PastMatchesView`) shows one
card as its first section, above Trends:

> **Keep a full copy of your matches**
>
> You've recorded 10 matches since your last export. Your iCloud backup keeps
> scores and stats, but not heart rate, steps, distance, calories or private
> notes. An archive file keeps everything. Import it if you move to a new
> iPhone.
>
> **[Export Archive]**  **[Later]**
>
> [Don't Remind Me Again]

- The count is real ("10", "14"). It names only the categories this archive
  actually holds: if no match has Health data, the Health clause is dropped;
  if there are no private notes, "or private notes" is dropped (§3.2 decides
  which matches count at all).
- When iCloud backup is off or unavailable, the second sentence becomes "Your
  matches aren't backed up anywhere else." (`ICloudBackupCopy.current` already
  resolves this state.)
- It is a plain `Section`, not an alert, sheet, banner overlay or local
  notification. Scrolling past it is a valid way to ignore it.
- It is hidden while a live match section is showing, so the live row stays
  first, and returns when the live match ends.

### 2.2 The three buttons

| Button | What happens | Counter |
|---|---|---|
| **Export Archive** | Opens the **existing** `ArchiveExportOptionsSheet` → `fileExporter` flow, unchanged (§5.2). | Reset only if the file export reports success. Cancel at either step leaves the card showing. |
| **Later** | Hides the card. | Reset: the next card needs another 10 matches. |
| **Don't Remind Me Again** | Hides the card for good. No confirmation dialog: the Settings toggle (§2.3) is the undo, and the button's accessibility hint says so. | Reminders off. |

### 2.3 Settings › Backup & Transfer

Two additions to the existing section:

1. A line under the two buttons: **"Last exported 12 Nov 2026"** or **"Never
   exported"**. Shown whether or not reminders are on — it's useful on its own,
   and it is what a player checks before trading in a phone.
2. A toggle: **Remind Me to Export** (on by default). Turning it off is the same
   as Don't Remind Me Again; turning it back on re-enables the card. Its
   one-line blurb lives in `SettingsCopy` like every other setting, even though
   it exists only on the iPhone.

An export made from Settings resets the counter exactly as one made from the
card does: there is one export flow and one place that records success.

### 2.4 After a successful export

The card disappears, and the existing green "Archive exported" status shows where
the export started. Nothing else changes.

---

## 3. When the reminder is due

### 3.1 The rule

The card shows when **all** of these hold:

1. Reminders are enabled (default yes).
2. The archive opened normally (`PhoneStatsStore` isn't in its unreadable-file
   state, and there is no pending iCloud restore prompt). Never nudge someone
   to export an archive the app isn't sure it has fully loaded: exporting a
   partial archive would hand them a false sense of safety.
3. At least **10** *countable* matches (§3.2) have a completion date
   (`endTime`) later than the **baseline** (§3.3).

That's all. No time-based rule, no app-version gating, no attention timer. A
player who records 10 matches in one weekend tournament sees it after the
weekend; one who plays monthly sees it once or twice a year. Both are right:
the risk is proportional to unprotected matches, not to time.

### 3.2 Which matches count

A match counts when it is **completed** (`!isInProgress`) and holds something
the automatic backup doesn't:

- **any** of the five Health fields is non-nil (reuse
  `HealthExportConsent`'s per-record raw-field check — it already treats a
  stored `0` as present), **or**
- it has a non-empty private note (the iPhone passes Core a `Set<UUID>` of
  matches with notes; Core never sees note text).

When iCloud backup is off or unavailable, **every** completed match counts,
because nothing else protects it.

In-progress checkpoints never count: they change with every point and the
watch still holds them.

> **E1 (owner):** count only "at-risk" matches as above, or every completed
> match? *Recommendation: at-risk only.* A player with Health off and no notes
> whose iCloud backup works already has every byte of their archive backed up;
> reminding them is noise that teaches them to tap Don't Remind Me Again.

### 3.3 The baseline

One stored date, `archiveExportReminderBaseline`. It moves forward on:

| Event | New baseline |
|---|---|
| A successful archive export (card or Settings) | now |
| **Later** | now |
| A successful archive **import** (Merge or Replace) | `max(baseline, archive.exportedAt)` — the matches in that file are already in a file the user holds, so restoring onto a new phone doesn't trigger an instant reminder |
| Turning reminders back on in Settings | unchanged (if 10+ are already unexported, the card shows straight away — which is what someone turning it on wants) |

No baseline yet (`nil`) means "never exported": every countable match counts.
An existing player who updates with 40 Health-tracked matches therefore sees the
card once on first launch. That is intended — they have never been told this.

A separate `archiveLastExportDate` records only real exports, for the Settings
line. **Later** must not move it.

### 3.4 Known imprecision (accepted)

The count is "completed after the baseline", not "absent from the last file".
The differences, all of which err towards reminding *later*, never towards
losing the reminder for good:

- A match completed on the Watch before an export but synced to the iPhone
  after it isn't in the file and isn't counted. It is counted only if it has
  company: the next 10 bring the card back, and that export includes it.
- A note or Health backfill added to an *older* match after an export isn't
  counted.
- A clock change can shift a match either side of the baseline.

> **E2 (owner):** accept these, or track the exact match IDs in the last export
> (a small Application Support file, unioned on import)? *Recommendation:
> accept.* "Every 10 matches or so" is the brief; an ID ledger is a new
> persisted file with its own failure modes, for an off-by-one in a nudge.

---

## 4. What the reminder must never do

- **Never export by itself**, or schedule, upload, or write anything. The user
  always chooses where the file goes through the system `fileExporter`.
- **Never pre-enable private notes.** The export sheet opens exactly as it does
  from Settings, with Include private notes **off** and the exact-text review
  (`ExportInclusionDefaults.includePrivateNotes`, never remembered). The card
  says an archive file *can* hold notes; it must not imply they're included
  automatically.
- **Never skip or shorten the Health disclosure.** `HealthExportConsent`'s
  message is shown unchanged.
- **Never steer the destination to iCloud.** Copy says "somewhere other than
  this iPhone" at most. The app suggesting iCloud Drive for Health data would
  sit badly next to the iCloud copy we strip for Guideline 5.1.3(ii); the
  user's own choice of destination is already covered by the existing
  disclosure.
- **Never use a notification.** No permission prompt, no badge, no background
  work.
- **Never show over another presentation**, and never on the same close as the
  App Store review prompt (§5.4).

---

## 5. Design

### 5.1 Core — `Settings/ArchiveExportReminderPolicy.swift` (new, pure)

Mirrors `ReviewPromptPolicy`: the app supplies facts, Core decides.

- Constants: `threshold = 10`, and the three phone-local key strings (pinned in
  tests, like `ExportInclusionDefaults`).
- `countableMatchCount(records:matchIDsWithNotes:backupProtectsNonHealthData:since:) -> Int`
- `state(...) -> Reminder` where `Reminder` is `.hidden` or
  `.due(count:, missing: Set<MissingCategory>)`. `MissingCategory` is
  `.health` / `.notes` / `.everything` and drives which clauses of the card
  copy appear.
- `baselineAfterImport(current:archiveExportedAt:) -> Date`.
- The card's strings live here too (`ArchiveExportReminderCopy`), so the
  iPhone and the browser demo can't drift, and the "don't overclaim" rule in
  §1 is pinned by a test.

No `MatchRecord` field, no `MatchSyncKey`, no wire change.

### 5.2 iPhone — one shared export flow

Today the export sheet, `fileExporter`, its `MatchArchiveDocument` and the
"Archive exported" status are private `@State` in `SettingsView`. The card
needs the same flow, and duplicating it would give two places that can record
success — or forget to.

Extract it into one reusable view modifier, `ArchiveExportFlow`
(`Views/Backup/`), that owns: presenting `ArchiveExportOptionsSheet`, building
the data off-main via `PhoneStatsStore.exportManualArchiveData(notes:)`,
presenting `fileExporter`, and reporting `.exported` / `.failed` / `.cancelled`.
On `.exported` it calls the coordinator's `recordExport(now:)`. Both
`SettingsView` and `PastMatchesView` attach it. This is a pure move of existing
code plus one callback; the sheet itself is unchanged.

`ArchiveExportReminderCoordinator` (`Views/Backup/`, like
`ReviewPromptCoordinator`) owns the three `UserDefaults` keys with an injectable
`UserDefaults`, and exposes `reminder(for:notes:icloud:)`, `recordExport`,
`snooze`, `disable`, `setEnabled`, `recordImport(exportedAt:)`. Settings calls
`recordImport` from the existing successful-import path.

The card view, `ArchiveExportReminderCard`, takes the `.due` value and three
closures. Accessibility identifiers: `export-reminder-card`,
`export-reminder-export`, `export-reminder-later`, `export-reminder-never`.

### 5.3 Keys (phone-local, never synced)

| Key | Type | Default | Meaning |
|---|---|---|---|
| `archiveExportReminderEnabled` | Bool | `true` (absent = true) | Settings toggle / Don't Remind Me Again |
| `archiveExportReminderBaseline` | Date | absent | §3.3 |
| `archiveLastExportDate` | Date | absent | Settings "Last exported" line only |

These join the phone-local exceptions listed in CLAUDE.md §0 (and AGENTS.md)
in the same PR, so the synced-settings grep check stays explainable.

The reminder state deliberately is **not** in the match archive or the iCloud
backup. After a new-phone restore from iCloud, the baseline is absent, so a
player who restored from iCloud (and so lost Health data and notes) is told
about the archive file as soon as they have 10 new at-risk matches — or, if the
restore brought Health-free matches only, not until there is something worth
protecting.

### 5.4 Interplay with the review prompt

The card is inline and non-modal, so it can't collide with StoreKit's sheet.
Two small rules keep the screen calm anyway:

- The card never appears *on* the dismissal that requests a review: if
  `requestReviewIfEarned` made a request, the card waits until the next time
  the Matches screen appears.
- Only one card-style prompt at a time on the Matches screen. The iCloud
  restore prompt and the archive-safety notices (`ARCHIVE_SAFETY_PLAN.md`
  §5.9, if built) take precedence; the export card hides while either shows.

### 5.5 Watch

No change. The Watch keeps 25 matches and is not where archives are exported.

### 5.6 Browser demo

`phone-demo.js` (archive) and `phone-demo-settings.js` (Backup & Transfer)
mirror the card, the toggle and the last-export line, reading the same copy.
The demo's archive file is already a separate format, and its "export" stays a
local download. Its threshold may be lowered by a Demo control so a visitor can
see the card without recording 10 matches.

---

## 6. Every situation, and what happens

This table is also the test list (§7).

| # | Situation | Result |
|---|---|---|
| 1 | Fresh install, 9 at-risk matches | No card |
| 2 | 10th at-risk match completes | Card shows, "10 matches" |
| 3 | Export Archive → file saved | Card gone; Settings shows today's date; next card after 10 more |
| 4 | Export Archive → Cancel on the sheet, or Cancel in Files | Card stays; nothing recorded |
| 5 | Export fails (disk full, write error) | Card stays; existing red "Export failed" status |
| 6 | Later | Card gone until 10 more; "Last exported" unchanged |
| 7 | Don't Remind Me Again | Card never shows; toggle off in Settings; Settings export still records "Last exported" |
| 8 | Toggle turned back on with 15 unexported | Card shows at once with "15" |
| 9 | Export from Settings while the card is showing | Card gone |
| 10 | Matches without Health data or notes, iCloud backup working | Not counted (E1) |
| 11 | Same, iCloud backup off or unavailable | Counted; copy says nothing else backs them up |
| 12 | In-progress checkpoints | Never counted |
| 13 | User deletes matches and drops below 10 | Card hides (derived state, nothing stored) |
| 14 | New phone: Import a manual archive | Baseline = file's `exportedAt`; no instant card |
| 15 | New phone: restored from iCloud | Baseline absent; card after 10 at-risk matches |
| 16 | Archive unreadable this launch, or restore prompt pending | No card |
| 17 | Live match in progress | Card hidden until it ends |
| 18 | Review prompt requested on this report close | Card waits for the next appearance |
| 19 | Archive with Health data but no notes | Copy names Health only |
| 20 | Notes but no Health data | Copy names notes only, and says they're included only if chosen |

---

## 7. Tests

- **Core** (`ArchiveExportReminderPolicyTests`): every row of §6 Core can
  express — threshold at 9/10/11, at-risk vs plain matches, iCloud off,
  in-progress excluded, a stored Health `0` counts, nil vs set baseline,
  `baselineAfterImport` never moving backwards, copy variants per
  `MissingCategory`, and the copy never containing "lost forever"-style
  overclaims. Pin the three key strings.
- **iPhone unit** (`ArchiveExportReminderCoordinatorTests`, injected
  `UserDefaults`): export/snooze/disable/import transitions; Later never moves
  `archiveLastExportDate`; cancel/failure record nothing.
- **iPhone UI**: seed 10 Health-tracked matches through the existing importer
  (as the demo-parity fixtures do), check the card appears, Later hides it,
  Don't Remind Me Again turns the Settings toggle off, and Export Archive
  presents the same sheet with Include private notes off.
- **Demo**: extend `iphone-demo-qa.cjs` for the card and toggle.

---

## 8. What stays the same

- The export file format, schema version, disclosure and notes opt-in.
- Import, Merge and Replace.
- The iCloud backup and its Health stripping.
- `ARCHIVE_SAFETY_PLAN.md`: this plan neither depends on it nor changes it.
  If that plan ships restore points, they protect against bad data on *this*
  phone; this reminder protects against losing the phone. Both remain needed.

---

## 9. Decisions for the owner

| # | Decision | Recommendation |
|---|---|---|
| E1 | Count only matches with Health data or notes (plus everything when iCloud is off) | Yes (§3.2) |
| E2 | Date baseline rather than an exact ledger of exported match IDs | Yes (§3.4) |
| E3 | Threshold 10, the same after Later | Yes; revisit with real usage |
| E4 | Inline card on the Matches screen, not an alert or notification | Yes (§2.1, §4) |
| E5 | Settings gets a Remind Me to Export toggle and a Last exported line | Yes (§2.3) — the toggle is the only undo for Don't Remind Me Again |
| E6 | Don't Remind Me Again without a confirmation dialog | Yes; the toggle makes it reversible |

---

## 10. Phases (not started)

| Phase | Surface | What |
|---|---|---|
| 1 | `[Core]` | `ArchiveExportReminderPolicy` + copy + tests. No app change. |
| 2 | `[iOS]` | Extract `ArchiveExportFlow` from `SettingsView` with no behaviour change (export still works identically from Settings). |
| 3 | `[iOS]` | Coordinator, card, Settings toggle and last-export line, import baseline; CLAUDE.md §0 key exceptions; file inventory entries for the new source files. |
| 4 | `[Web]` | Browser demo parity (§5.6). |

`APP_STORE_METADATA.md` needs no new review note: the feature adds no data
flow, only a pointer to an existing one.

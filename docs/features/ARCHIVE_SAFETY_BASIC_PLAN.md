<!--
machine-readable summary (parse this block first)

status: proposal — design only, nothing implemented. Waiting for the owner's sign-off on §3–§9.
author: Claude, from the owner's "smaller change" proposal and review, 2026-11-23
date: 2026-11-23
defers: "ARCHIVE_SAFETY_PLAN.md (the full redesign). It stays as a reference and is not scheduled."
fixes: "TECHNICAL_DEBT #18 on the iPhone: an undecodable archive no longer starts empty and no longer overwrites the iCloud backup."
approach: "Fail closed. Leave every file untouched, stop all writes and iCloud pushes, show one blocking screen, and hand the problem to support with a diagnostic report."
rules:
  - "B1 Opening the archive never changes a file it couldn't open, or the iCloud backup."
  - "B2 While the archive is blocked, nothing changes it: no saves, no Watch merges, no iCloud pushes."
  - "B3 'Not unlocked yet' is waiting, not failing, and retries on its own."
  - "B4 The user can always send support everything needed to diagnose it, after seeing what is sent."
  - "B5 Health data and private notes are never sent to support."
states: "Loading | Open | Blocked(problem) — closed list, §4.2"
phases: "(1) fail closed + blocking screen + retry + Send to Support; (2) Open a File from Support. Neither started."
decisions_open: [S1, S2, S3, S4, S5, S6]
-->

# Plan: Archive safety, the basic version (fail closed, support-assisted)

**Status: proposal. Nothing here is implemented.** No code until the owner signs
off on §3–§9.

**Relationship to [`ARCHIVE_SAFETY_PLAN.md`](ARCHIVE_SAFETY_PLAN.md):** this plan
replaces it as the next step for TECHNICAL_DEBT #18. The full plan is **deferred**:
it stays as a reference for the problems this plan leaves open (§7). This plan
deliberately reverses the full plan's §9 position against pausing saves. It pauses
everything, but behind a screen that leaves nothing half-working, which is what
made the #228–#234 approach fail to converge.

**Read with:** [`TECHNICAL_DEBT.md`](TECHNICAL_DEBT.md) #18 (the diagnosis) and
#19 (versioned files).

---

## 1. The problem, in one paragraph

In 1.4.0, when `PhoneStatsStore` can read `matchHistory.json` but can't decode it,
`readCanonicalFile` moves the file aside to `.corrupt`, the archive starts
empty, and the same launch's iCloud push writes that empty archive over the only
iCloud backup. One unknown value in one point of one old match is enough. The
moved-aside file survives on the phone. The backup does not. The same happens,
more quietly, to `deletedMatchIDs.json` (deleted matches can come back) and
`forgottenPlayers.json` (forgotten players can come back).

## 2. The decision

Don't try to keep working with a bad archive. **Stop, keep everything as it is,
and let support look at it.**

Why this is proportionate:
- Saves are atomic, and the iPhone only reads files it wrote itself. A bad
  file realistically means one of these:
  - a developer mistake, such as a persisted enum case deleted against
    CLAUDE.md §4;
  - a TestFlight downgrade;
  - a restore from a newer phone onto an older app.

  In each case the real fix is an app update. Because nothing was touched, that
  update reopens everything.
- Genuine byte corruption is very rare, and a human looking at the file is the
  most reliable repair.
- One blocking screen has exactly one state to reason about. #228–#234 kept the
  app half-working around a pause, and every review found a new combination.

## 3. Rules

These are the acceptance criteria for the PRs below, and the only basis for
blocking one.

1. **B1. Opening never changes what it couldn't open.** A file that fails to read
   or decode stays in place, byte for byte. The iCloud backup is not written.
2. **B2. While blocked, nothing changes the archive.** No local saves, no Watch
   merges into the store, no iCloud pushes, no Settings mutations, no exports.
   This is enforced **in the store**, not only by the UI.
3. **B3. Not unlocked yet means waiting.** Before the first unlock after a
   restart, iOS blocks protected files. The app shows *Loading* and retries by
   itself. It never shows the error screen for this.
4. **B4. The user can always send support what is needed.** That means the
   diagnostic report and the archive files, after a preview of exactly what is
   included.
5. **B5. Support never gets Health data or private notes without the user being
   told.** The Health sidecar and the `MatchNotes/` store are never attached. A
   damaged main file from before the Health sidecar existed may still hold
   Health fields. It is attached only when the preview names that (S5), under
   the consent-gated export rule in
   [`health-data-flow.md`](../architecture/health-data-flow.md).

## 4. The change

### 4.1 Reading the three canonical files

Today `loadCanonicalOnQueue` reads `deletedMatchIDs.json`,
`forgottenPlayers.json` and `matchHistory.json` through `readCanonicalFile`.

Changes:
- **Never move a file aside.** Delete the `.corrupt` move (and the
  `removeItem(at: aside)` that destroys an earlier `.corrupt` copy).
- **Decode `matchHistory.json` and `deletedMatchIDs.json` through
  `PersistedArchiveCodec.decode`** (#229), so an envelope with a newer
  `schemaVersion` is reported as `newerSchemaVersion`. Note the limit: 1.4.0
  still *writes* bare arrays, so an unknown enum value inside a bare array comes
  back as an ordinary `DecodingError`. The app **cannot** tell "needs a newer
  version" from "damaged" in that case, and the copy (§4.5) must not pretend it can.
- **Don't use that codec for `forgottenPlayers.json`.** The ledger is a plain
  JSON object (`{"schemaVersion": 1, "playerIDs": [...]}`), not an array or an
  envelope. `PersistedArchiveCodec.decode` treats every object as an envelope
  and requires a `format` header, so it would block every healthy archive. The
  ledger's own `init(from:)` is no good either: it uses `try?` per field, so a
  newer `schemaVersion` or a damaged `playerIDs` silently reads as version 1 with
  no players. That would quietly undo every Forget Player.

  Add a **strict canonical decoder** in Core,
  `ForgottenPlayerLedger.decodeCanonical(_ data: Data) throws`, used only for
  the canonical `forgottenPlayers.json`:
  - The data must be a JSON object, or it is `.undecodable`.
  - An object with a `format` key is a future envelope. It goes through
    `PersistedArchiveCodec.decode` (format `forgottenPlayers`), so a newer
    version reads as `.newerVersion`.
  - Otherwise it is the existing `{"schemaVersion", "playerIDs"}` shape:
    - A missing `schemaVersion` means 1, as today. A value above
      `currentSchemaVersion` is `.newerVersion`, and one below 1 is
      `.undecodable`.
    - `playerIDs` must be present and be an array of strings, each a valid UUID.
      Anything else is `.undecodable`, never an empty ledger.

  The lenient `init(from:)` is unchanged for the manual archive, the iCloud
  backup and sync paths. Hardening those is out of scope.
- **Classify the failure** into one `ArchiveOpenProblem` (pure, in Core):

  | Case | Cause | Result |
  |---|---|---|
  | `.notYetUnlocked` | `CocoaError.fileReadNoPermission` / `EPERM`, while `UIApplication.isProtectedDataAvailable == false` | *Loading* (§4.4) |
  | `.unreadable` | Any other read error | *Blocked* |
  | `.undecodable` | Bytes read, decode failed (`DecodingError`, invalid JSON, `wrongFormat`, `emptyData`) | *Blocked* |
  | `.newerVersion` | `PersistedArchiveCodec.CodecError.newerSchemaVersion` / `unsupportedSchemaVersion` | *Blocked*, with Update wording |
  | `.missing` | `matchHistory.json` is absent but the archive is already initialized (`canonicalInitializedURL` exists) | *Blocked*. An initialized archive always has this file, because the marker is only written after a successful canonical write, so its absence is loss, not "empty". The deleted-ids and forgotten-players files may legitimately be absent (older builds) and keep 1.4.0's "missing means none" |
  | `.repairIncomplete` | A phase 2 `repair-in-progress` marker exists (§4.7) | *Blocked*. Roll back from `Damaged/` first, and never read the canonical files as an archive |

- **Any one of the three files failing blocks the whole archive.** This is a
  behaviour change for the deleted-ids and forgotten-players files, which today
  are silently dropped. Dropping them can resurrect a deleted match or a
  forgotten player's name, so blocking is the correct answer.
- **The Health sidecar keeps its 1.4.0 behaviour** (moved aside, Health detail
  starts empty). It is a re-fetchable copy of HealthKit data and must not block
  the archive. The PR states this explicitly.
- The problem records **which file** failed and the error details for the report
  (§4.6).

### 4.2 States (closed list)

`PhoneStatsStore` publishes one `archiveState`:

| State | Meaning | Ends when |
|---|---|---|
| `loading` | Not read yet, or `.notYetUnlocked` | A read succeeds or fails for another reason |
| `open` | Normal 1.4.0 behaviour | — |
| `blocked(ArchiveOpenProblem)` | A file couldn't be opened | A Try Again succeeds, an app update reads it, or (phase 2) a file from support is opened |

`canonicalWritesSuspended` becomes `archiveState != .open`. **A fix that needs
another state changes this plan first, with the owner's OK.**

### 4.3 Store guards (B2)

The guard lives at the one funnel every mutation passes through:
- `adoptOnQueue`: when not `open`, return `false` **before** touching `records`,
  `tombstones` or `forgotten`, and don't publish. Today it assigns the new state
  first and publishes even when the write is refused. That is how a blocked store
  could still show and reconcile Watch merges.
- This covers `mergeIncoming`, `appendMatch`, `syncToPhone`, `saveHistory`,
  `removeMatch`, imports and the roster mutations.
- `commitUserEditOnQueue` already throws `TagEditError.notPersisted` when writes are
  suspended. Keep it.
- `syncICloudBackupOnQueue` and `markArchiveInitializedOnQueue` already bail when
  suspended. Keep them.
- `PhoneMatchSyncService` needs no new logic: merges return the unchanged (empty)
  archive, so tag reconciliation finds nothing to send. Add one test that pins
  this.

Paths that don't pass through `adoptOnQueue` get their own guard:
- **`exportManualArchiveData`** throws when not `open`. Today it encodes the
  current `records`, so a blocked store would hand Backup & Transfer an empty,
  zero-match archive file that looks valid.
- **`performRestoreOnQueue`** returns at the top when not `open`, before
  replacing `records`. The confirmed-restore entry point that calls it does the
  same.
- **`migrateLegacyDocumentsArchiveIfNeeded`** (run in `init` before
  `loadCanonicalOnQueue`) runs only when protected data is available **and** the
  archive isn't initialized yet. Otherwise a legacy file could be written into
  a `.missing` canonical path and bypass the block. It already never deletes the
  legacy files unless the canonical write succeeds; keep that.

While blocked, the store publishes an empty `history` and the UI never shows it,
because the blocking screen covers the app.

### 4.4 Retry (B3)

- Retry the load when `UIApplication.protectedDataDidBecomeAvailableNotification`
  fires, and when the scene becomes `.active`, but only from `loading` or
  `blocked(.unreadable)`. A decode failure gives the same answer every time, so it
  isn't retried automatically. **Try Again** still re-reads it on request.
- A retry **replaces** the in-memory state wholesale from disk. Nothing was merged
  while blocked (§4.3), so nothing is lost. On success:
  1. publish;
  2. call `PhoneMatchSyncService.requestFullHistorySync()` so the Watch resends
     what it delivered meanwhile;
  3. call `syncICloudBackup()` as at a normal launch.
- The files use `completeFileProtectionUntilFirstUserAuthentication`, so once the
  phone has been unlocked once, reads keep working while it is locked again. One
  retry after unlock is enough.
- **Threading.** `UIApplication.shared.isProtectedDataAvailable` is main-actor
  isolated, and `loadCanonicalOnQueue` runs on the store's queue inside a
  `queue.sync` that `init` calls from main. Calling back to main from there would
  deadlock. So the caller captures the flag on main **before** entering the
  queue and passes it in. It comes through a `StorageConfiguration` closure
  (`isProtectedDataAvailable: @MainActor () -> Bool`), which tests replace.
  Notification and scene-phase retries capture it the same way. They arrive on
  main.
- **No missed unlock.** Register the `protectedDataDidBecomeAvailableNotification`
  observer **before** the initial load. After the load, if the state is still
  `loading` and the flag now reads `true`, retry once at once. An unlock that
  happens between the read and the observer registration is then never missed.

### 4.5 The blocking screen

A full-screen view at the root of the iPhone app, shown whenever `archiveState` is
`blocked`. It covers everything, including the live scoreboard. Watch scoring is
unaffected, and the screen says so. *Loading* shows a plain progress view, never
this screen.

Copy (final wording to the owner, S1):

> **DeuceMate can't open your match archive**
>
> Nothing has been changed or deleted. Your matches on this iPhone and your iCloud
> backup are exactly as they were.
>
> Your Apple Watch keeps scoring, and keeps your newest 25 matches until this is
> fixed.
>
> Please check the App Store for an update. If there isn't one, send a report to
> DeuceMate support and we'll help you get your matches back.

For `.newerVersion`, the first line of the last paragraph becomes "This archive was
saved by a newer version of DeuceMate. Update the app to open it."

Actions:
1. **Try Again.** Re-runs the load (§4.4).
2. **Send Report to Support.** See §4.6.
3. **Check for Updates.** Opens the App Store product page. Reuse Core's
   `MatchWebViewModel.appStoreURL`, which `ReviewPromptPolicy.writeReviewURL`
   already builds on. It is `internal` today, so expose it as `public`, or add
   a public `ReviewPromptPolicy.appStoreURL` alias, rather than repeating the
   literal.
4. *(phase 2)* **Open a File from Support.** A secondary text button. See §4.7.

No reinstall advice appears anywhere in the app. A reinstall deletes:
- the untouched file;
- all private notes (stored only on this iPhone and excluded from backup);
- the local Health detail.

For the likely cause, it doesn't even work: the iCloud backup holds the same bad
value. The initial restore then gives up with "backup data is corrupt"
(`restoreInitialBackupOnQueue`), the user sees an empty archive with no
explanation, and backup pushes stay paused because the archive is never marked
initialized. Support may still suggest a reinstall in the rare case where they
have confirmed that it is safe.

### 4.6 Send Report to Support

**What a "stack trace" means here.** A decode failure doesn't crash, so there is
no crash log. The useful equivalent is the decoding error's coding path. It
points at the exact match, point and field, for example
`[12].points[204].endingShot: Cannot initialize EndingShot from invalid String
value "dropShot"`. That is the core of the report, together with this launch's
persistence log lines.

**The report** (`ArchiveSupportReport`, a pure, tested Core builder that produces
plain text, and the email body):
- app version and build, iOS version, device model (no device identifiers);
- the date and time of the failure, and whether the app was launched in the
  background;
- for each of the three files: present or absent, size, modification date,
  SHA-256 (CryptoKit), and read result (`ok`, or the `ArchiveOpenProblem` case);
- for a decode failure: the error type, the full coding path, the debug
  description, and for an envelope its `format` and `schemaVersion`;
- for a read failure: the error domain, code and underlying POSIX error;
- whether the Health sidecar and the notes store exist (yes or no only; never
  their contents);
- this launch's `PhoneStatsStore` log lines from `OSLogStore` (current process,
  the store's subsystem and category only; S4). The store logs error
  descriptions, never note text. Collecting them is **best-effort**: capped at
  the newest 500 lines and 64 KB. If `OSLogStore` throws, the report says "Logs
  unavailable" and sending continues.

**Attachments.** Copies of `matchHistory.json`, `deletedMatchIDs.json` and
`forgottenPlayers.json`, staged in an `ExportStaging` generation directory, never
shared from their live paths. Never the Health sidecar or `MatchNotes/` (B5).
- Only files that exist and can be read are attached. For an absent file
  (`.missing`) or an unreadable one (`.unreadable`), the report says so in its
  per-file section, and Send Report still works with whatever remains, even with
  no attachments at all.
- The generation is ended (`ExportStaging.endGeneration`) when the Mail
  composer or the share sheet is dismissed, whether the user sent or cancelled.
  The existing `sweepInactive()` at launch catches anything left behind by a
  crash.

**Preview before sending.** One sheet lists the report text in full and the
attached files with their sizes. Above them:

> This sends your match archive to DeuceMate support. It includes scores, player
> names and playing style notes. It doesn't include Health data or your private
> match notes. Support uses it only to fix this problem and deletes it when the
> case is closed.

The last sentence depends on S3. A damaged file can't be checked, so the copy
says what the app *attaches*, not what the file is guaranteed to contain. A
file from before the Health sidecar existed may still hold Health fields, so
the PR should either check for the five Health keys textually and mention them,
or soften "doesn't include" to "doesn't attach your Health data file" (S5).

**Sending.** Use `MFMailComposeViewController` (MessageUI, an Apple framework, no
dependency) with the existing support address (`SettingsView.supportEmailURL`'s
address, moved to one shared constant), subject "DeuceMate archive problem
(<version>)", the report as the body and the files attached. If
`canSendMail()` is false, fall back to the share sheet with the report as a
`.txt` plus the three files. The user then picks Mail, Messages, AirDrop or
Files.

### 4.7 Phase 2: Open a File from Support

Support's way to give the user their matches back without a reinstall:
- Support repairs the archive and sends back a **manual export file**
  (`ManualMatchArchiveBackup`, the same format Backup & Transfer uses), first
  tested in a simulator through the normal importer.
- The blocking screen's **Open a File from Support** opens a file picker and
  validates the file fully (format, schema version, every record). It then shows
  the existing `BackupPreview` (match count and newest date) with a confirmation.
- On confirm, on the store queue. The originals stay at their canonical paths
  until the repaired archive is fully written, and are only ever *copied*:
  1. **Snapshot** the three canonical paths into `MatchArchive/Damaged/<ISO-date>/`.
     The snapshot has a `manifest.json` that records each path as either
     **present** (with its size and SHA-256) or **absent**. Every present file
     is copied and verified against the manifest. An absent file is legitimate:
     `matchHistory.json` in the `.missing` case, or a deleted-ids or
     forgotten-players file an older build never wrote. Snapshots are never
     deleted automatically, and support can ask for them again. If a copy, its
     verification or the manifest write fails, stop: nothing has changed.
  2. Write a `repair-in-progress` marker naming that snapshot folder. If the
     marker can't be written, stop: nothing has changed.
  3. Build the repaired archive in memory:
     - **Records:** the file's records.
     - **Deleted ids:** the readable local tombstones, unioned with the file's
       `deletedMatchIDs` (below). Any record whose id is in that union is
       dropped. Deletion wins, as in the normal Watch merge, so a deleted match
       can't return through the file or the Watch resend in step 6.
     - **Forgotten players:** the file's ledger, unioned with the local one if
       that file was readable. Then every record is scrubbed with the union.
     - **Health:** merged back from the existing sidecar
       (`HealthSidecarPolicy.merge`), in memory only.

     **How deleted ids travel.** `ManualMatchArchiveBackup.Archive` carries
     records, forgotten players and notes, but no deleted ids: an ordinary import
     takes tombstones from the local store. Add one optional field,
     `deletedMatchIDs: [UUID]?`, following CLAUDE.md §4's backward-compatibility
     recipe (`decodeIfPresent`, nil = no information, still schema 1, pinned in
     `ManualMatchArchiveBackupTests`):
     - Ordinary exports don't write it, and ordinary Backup & Transfer imports
       ignore it, so their behaviour is unchanged. Only Open a File from
       Support reads it.
     - Support fills it from the repaired `deletedMatchIDs.json` whenever that
       file was the damaged one, or was unreadable. When the local file is
       readable, its ids are kept anyway, so the field may be omitted.
     - If the local tombstone file was damaged and the support file has no
       `deletedMatchIDs`, refuse the file ("This file is missing deleted-match
       information. Please contact support."). Otherwise a deleted match could
       come back from the Watch.
  4. Replace the three canonical files, each with an atomic write of its
     Health-stripped content. The Health sidecar is **not** rewritten: it is
     keyed by match id and still applies to the repaired records.
  5. Mark the archive initialized, then delete the marker.
  6. Only after step 5 succeeds: set `open`, publish, ask the Watch to resend,
     and push to iCloud. This push replaces the iCloud backup with the repaired
     archive, which the user confirmed.
- **If any of steps 4–5 fails**, roll back to the manifest. Write each
  **present** file back from its verified copy. **Remove** any file now at an
  **absent** path, because it was created by the failed repair. Check the result
  against the manifest, then delete the marker. The archive stays
  `blocked` with its original problem, and the screen says "Couldn't save.
  Nothing has been changed."
- **If the rollback fails too** (for example, the disk is still full), the
  marker stays. While the marker exists, every load — Try Again, the next
  launch, a retry on unlock — stays `blocked(.repairIncomplete)` and first tries
  the rollback again. It never reads the canonical files as an archive, so a
  partly replaced set can never open, and it never pushes to iCloud. The screen
  says "DeuceMate couldn't finish restoring the file from support. Your
  original files are kept safely. Free up some space on your iPhone, then tap
  Try Again."
- **Leaving `.repairIncomplete`.** When a rollback retry succeeds and its result
  matches the manifest, the marker is deleted and the normal load runs again
  from the top. That returns the archive to the original blocked problem (or
  `open`, if an app update can now read it), as §10 tests.
- **`Damaged/` is excluded from device backups.** Set
  `isExcludedFromBackup = true` on `MatchArchive/Damaged/` and verify it before
  each snapshot, with the same verify-then-write pattern as the notes store. A
  damaged `matchHistory.json` from before the Health sidecar can hold Health
  fields, and Guideline 5.1.3(ii) keeps those out of iCloud, including device
  backups. It also stops damaged copies bloating backups.
- Private notes are untouched. They live in their own store and are never part
  of the exchange.

### 4.8 Support runbook (goes in `docs/release/` with phase 1)

1. Read the report's read result for each file.
2. **Unknown enum value or `newerVersion`.** This is an app bug or a version
   mismatch. Ask the user to update. If no released build can read it, ship a
   hotfix that restores the case under CLAUDE.md §4's retire recipe, then confirm
   with the user that Try Again or the update opened it.
3. **`unreadable` (not a lock).** Ask the user to restart and unlock the phone,
   then Try Again. If it persists, the file needs repair (step 4) from a copy
   support already holds.
4. **Genuinely damaged.** Repair by hand using the coding path. Validate it with
   `swift test`, or a disposable simulator import, through `ManualMatchArchiveBackup`.
   Always carry the deletion history: copy the ids from the attached
   `deletedMatchIDs.json` (repaired if it was the damaged file) into the
   support file's `deletedMatchIDs`. Leave every match with one of those ids out
   of `records`, and copy the forgotten-players ledger into `forgottenPlayers`.
   Send it back for **Open a File from Support** (phase 2). Before phase 2 ships,
   the only options are waiting for phase 2 or, if support has confirmed the iCloud
   backup is good, a reinstall.
5. Delete the received files when the case closes, under S3's retention period.

## 5. Every situation, and what happens

| # | Situation | What happens |
|---|---|---|
| 1 | Unknown value in one match in a bare-array file | Blocked; the copy says to check for updates and offers Send Report. Nothing is written; iCloud is untouched |
| 2 | Newer envelope `schemaVersion` | Blocked with Update wording |
| 3 | Invalid JSON or empty file | Blocked, as row 1 |
| 4 | `deletedMatchIDs.json` or `forgottenPlayers.json` undecodable | Blocked, as row 1. This changes 1.4.0, which dropped them silently |
| 5 | Watch wakes the app before the first unlock | *Loading*; nothing written; retries on unlock or foreground; Watch resends |
| 6 | Any other read error | Blocked; retried automatically on unlock or foreground, and on Try Again |
| 7 | Watch delivers a match while blocked | The store refuses it; the Watch keeps it and resends after the archive opens |
| 8 | User updates to a build that can read the file | The archive opens normally at launch; nothing was lost |
| 9 | Support sends a repaired file (phase 2) | The bad files are copied to `Damaged/` and verified, the repaired archive replaces them, then it is shown, synced and backed up |
| 10 | Health sidecar undecodable | 1.4.0 behaviour: moved aside, archive opens, Health detail empty |
| 11 | A 1.4.0 `.corrupt` file already exists | Left alone. Support can ask for it |
| 12 | Fresh install, no local files | Unchanged 1.4.0 first-launch restore offer |
| 13 | `matchHistory.json` missing on an initialized archive | Blocked (`.missing`). Never opened as empty, so iCloud is never overwritten |
| 14 | Saving the support file fails, for example with a full disk (phase 2) | The canonical paths are rolled back to the snapshot manifest (present files restored, absent paths removed); still blocked with the original problem; iCloud untouched |
| 15 | The rollback fails too, or the app is killed mid-repair (phase 2) | The marker keeps it `blocked(.repairIncomplete)`; every load retries the rollback first, and nothing opens or pushes until it succeeds |

## 6. Accepted costs

- **New matches stop saving on the iPhone while blocked.** The Watch keeps only
  its newest 25 (`StatsStore.historyCap`), regardless of what the phone has
  received. At a few matches a week that is weeks of headroom, not forever. A
  hotfix or a support repair has to land within it, or the oldest matches from
  that period exist only as Watch history that has already rolled off.
- **The whole iPhone app is unusable while blocked**, including the live
  scoreboard and Settings. Watch scoring is unaffected.
- **Support needs a human.** Resolution time is support's response time.
- **The user sends personal data (names, playing style notes) to support.** They
  see exactly what is sent, and choose to send it.
- **The app can't tell "newer version" from "damaged"** for bare-array files
  (§4.1) until TECHNICAL_DEBT #19's versioned writers ship.
- **Phase 2's `Damaged/` snapshots are kept permanently and aren't cleaned.** A
  later Delete Permanently or Forget Player doesn't rewrite them. They stay on
  this iPhone only (excluded from backups), and support can ask for them. A
  Settings row to delete them is out of scope (full plan D6).
- **No new persisted enum case may ship under this plan** until the six
  persisted enums are unknown-safe (TECHNICAL_DEBT #18 "Still open"). Without
  the full plan's match-by-match reading, an older iPhone that meets a new case
  blocks the whole archive.

## 7. What this plan doesn't fix (deferred to `ARCHIVE_SAFETY_PLAN.md`)

1.4.0 has none of these either, so none of them blocks this fix:
- Valid but wrong data, such as a Replace import of the wrong file (full plan §2
  D). There are still no restore points.
- Changes that appear on screen but are gone after a restart when a save fails
  (#4a). Match-detail edits already roll back.
- Crash-safe saves across the four files (full plan §5.1).
- Keeping a single unreadable match while the rest open (full plan §5.2), and
  newer-Watch-to-older-iPhone deliveries (D9).
- The single iCloud copy is still overwritten on every save. This plan only stops
  it being overwritten *by a blocked archive*.

## 8. Decisions for the owner

| # | Decision | Recommendation |
|---|---|---|
| S1 | The blocking screen's wording (§4.5) | As drafted; review on device |
| S2 | Send by Mail with attachments, falling back to the share sheet | Yes |
| S3 | Support's retention of received archives, stated in the privacy policy | 30 days after the case closes. Add a privacy policy paragraph. Confirm the App Store privacy label: Apple treats optional, user-initiated customer-service submissions as optional to disclose when infrequent and clearly disclosed, but the owner should check this against the current guidance |
| S4 | Include this launch's store log lines from `OSLogStore` | Yes, filtered to the store's subsystem and category |
| S5 | Health wording for a damaged file that may predate the Health sidecar | Textually check for the five Health keys and say so if present |
| S6 | Ship phase 2 (Open a File from Support) | Yes, as a separate PR soon after phase 1, so support has a return path without reinstalling |

## 9. Phases and scope

| Phase | Surface | What | Rough size |
|---|---|---|---|
| 1 | `[Core]` + `[iOS]` | `ArchiveOpenProblem` classification and `ArchiveSupportReport` builder (Core). `PhoneStatsStore`: no move-aside, codec decode, `archiveState`, guard at the top of `adoptOnQueue`, retry on unlock and foreground, resend request on success. Blocking view, report preview, mail and share sending. Support runbook | ~150 store + ~120 Core + ~200 UI, plus tests |
| 2 | `[Core]` + `[iOS]` | Open a File from Support (§4.7): verified `Damaged/` copies, the `repair-in-progress` marker and rollback, and the optional `deletedMatchIDs` field on `ManualMatchArchiveBackup.Archive` | ~230 plus tests |

The same PRs also update (CLAUDE.md §6):
- **CLAUDE.md §1** read-failure paragraph and the `PhoneStatsStore` row. The
  "known gap" becomes "fails closed; see ARCHIVE_SAFETY_BASIC_PLAN.md".
- **TECHNICAL_DEBT #18** cascade item 1–2 notes, and the full plan's status
  line ("deferred").
- **`docs/architecture/file-inventory.md`** for the new view, Core files and mail
  helper.
- **The privacy policy page** (`docs/website/privacy.html`) for S3, and the App
  Review notes if the reviewer should know about the screen.

## 10. Tests

**Core** (`DeuceMateCoreTests`):
- `ArchiveOpenProblem` classification for every row of §4.1, including the
  `newerSchemaVersion` envelope and an unknown enum value in a bare array
  (`.undecodable`).
- `ArchiveSupportReport` contains the coding path, sizes and hashes, and never
  contains note text or Health values, even when given them. It handles absent,
  unreadable and log-unavailable inputs, and stays within the log cap.
- `ForgottenPlayerLedger.decodeCanonical`:
  - accepts the shape `writeCanonicalOnQueue` writes today;
  - accepts a missing `schemaVersion` (version 1);
  - gives `.newerVersion` for a higher `schemaVersion`, and for a newer
    envelope;
  - throws, never returning an empty ledger, for a non-array `playerIDs`, a
    missing `playerIDs`, a non-string element or an invalid UUID string.
- Core's App Store URL is public, and `writeReviewURL` is still built from it.

**iPhone** (`PhoneStatsStoreTests`, real files in a temporary directory):
- An undecodable file for each of the three canonical files gives `blocked`. The
  file is byte-identical afterwards, no `.corrupt` file exists, and nothing is
  written to the fake ubiquity container.
- While blocked, `mergeIncoming`, `appendMatch`, `syncToPhone`, `removeMatch` and
  imports change nothing and publish nothing. `updateTags` throws `notPersisted`.
  `exportManualArchiveData` throws, and `performRestoreOnQueue` changes nothing.
- Legacy Documents migration doesn't run while protected data is unavailable,
  or on an initialized archive with a missing `matchHistory.json`.
- With the injected protected-data flag `false`, a read failure gives `loading`,
  never `blocked`. Flipping it to `true` and posting the notification opens the
  archive. A flag that becomes `true` during the initial load triggers the
  immediate retry.
- Send Report stages only the files that exist and can be read, and the
  generation directory is gone after dismissal.
- A read error, then a retry after the fault is removed, gives `open` with the
  disk contents and requests a Watch resend.
- A Health sidecar that can't be decoded still opens the archive (row 10).
- The report's attachments are staged copies of exactly the three files, never
  the sidecar or the notes store.
- A missing `matchHistory.json` with the initialized marker present gives
  `blocked(.missing)`, and nothing is pushed.
- A healthy archive written by `writeCanonicalOnQueue` opens: an existing
  `forgottenPlayers.json` object (no `format` header) is read as a ledger, not
  rejected as an envelope. A ledger with a `schemaVersion` above the current one
  gives `.newerVersion`, and invalid JSON gives `.undecodable`.
- Phase 2:
  - A valid support file copies the old files to `Damaged/` (verified), writes
    the canonical files, opens, and pushes.
  - Repair works when files are absent: `.missing` (no `matchHistory.json`),
    and no deleted-ids or forgotten-players file. The manifest records them as
    absent. A rollback after a write failure removes whatever the failed repair
    created at those paths, leaving them absent again.
  - An invalid file, or a failed copy or marker write, changes nothing.
  - A write failure at each of the three canonical files (injected through the
    store's storage configuration) rolls back to byte-identical originals,
    stays blocked, and pushes nothing.
  - A failed rollback leaves the marker. The next load stays
    `blocked(.repairIncomplete)`, retries the rollback, and only then reports
    the original problem.
  - The Health sidecar is byte-identical after a repair.
  - `Damaged/` has `isExcludedFromBackup` set before the first snapshot file is
    written. A failure to set it stops the repair, with nothing changed.
  - After a successful rollback retry, the marker is gone and the load returns
    the original problem.
  - Deleted ids: readable local tombstones survive a repair whose file omits
    `deletedMatchIDs`. The file's `deletedMatchIDs` are unioned in. A record
    with a tombstoned id is dropped. After the Watch resends a tombstoned match,
    it is still absent. A damaged local tombstone file plus a support file
    without `deletedMatchIDs` is refused and changes nothing.
  - Core: `ManualMatchArchiveBackup` decodes an export without
    `deletedMatchIDs` as nil, round-trips one with it, and the ordinary
    importer ignores it.

**On a device, by hand:**
- *Loading* after a restart with the Watch waking the app.
- The blocking screen with VoiceOver and Dynamic Type.
- Mail with attachments, and the share sheet fallback with no mail account.

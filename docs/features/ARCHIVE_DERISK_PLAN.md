<!--
machine-readable summary (parse this block first)

status: decisions signed off by the owner on 2026-11-23 (§9). Nothing implemented yet; PR A comes first.
author: Claude, from the owner's direction after closing #240
date: 2026-11-23
fixes: "TECHNICAL_DEBT #18's one irreversible step: an iPhone archive that can't be decoded no longer overwrites the iCloud backup."
stance: "Rare and self-inflicted. Prevent it, destroy nothing, and write recovery code only if it ever happens, inside the hotfix that fixes the cause."
budget: "PR A ≤ 75 production lines; PR B ≤ 340 production lines (raised from 300 for the file list, §5.3). A finding that breaks the budget needs the owner's OK (§8)."
parts: "1 prevent (golden-file test); 2 destroy nothing (keep every copy, pause iCloud); 3 export reminder (ARCHIVE_EXPORT_REMINDER_PLAN.md, unchanged); 4 Archive Diagnostics (a report for support or a coding agent)"
defers: "ARCHIVE_SAFETY_PLAN.md (full redesign). Its status is deferred, as a reference only."
decisions_open: []
decided: "D1: no Resume iCloud Backup button. Only a fixing build ends the pause, after it recovers the dated copies (§3.2). D2: offer the report and, separately, the report with damaged files. D3: no hosted page for now. D4: PR A ships before PR B. D5: Archive Diagnostics is always in Settings, with its details collapsed until the user opens them (§5.1)."
hotfix_rule: "Any fix for a decode failure must recover the dated copies into the archive and then delete them. Otherwise iCloud stays paused for good (§10)."
-->

# Plan: De-risk the undecodable archive (#18), proportionately

**Status: decisions signed off (2026-11-23). Nothing here is implemented yet.**

**Read with:** [`TECHNICAL_DEBT.md`](TECHNICAL_DEBT.md) #18 (the cascade) and
[`ARCHIVE_EXPORT_REMINDER_PLAN.md`](ARCHIVE_EXPORT_REMINDER_PLAN.md) (part 3).
[`ARCHIVE_SAFETY_PLAN.md`](ARCHIVE_SAFETY_PLAN.md) is **deferred**. It stays as a
reference for the problems this plan deliberately leaves open (§7).

**Why a new plan.** #228–#234 and then #240 each tried to make a bad archive
recoverable inside the app. Each review round added an edge case and a mechanism
to handle it. #240's "basic" plan grew from 402 to 594 lines, and implementing
it would have taken roughly 3,000–4,000 lines. That is out of proportion to a
failure that is very rare and almost always caused by our own mistake. This
plan does three cheap things and stops.

---

## 1. The risk

In 1.4.0, when `PhoneStatsStore` can read `matchHistory.json` but can't decode
it, `readCanonicalFile` moves the file aside to `.corrupt`. The archive then
starts empty, and the same launch's iCloud push writes that empty archive over
the backup. The same happens to `deletedMatchIDs.json` and
`forgottenPlayers.json`.

**The realistic cause is us.** Saves are atomic, and the iPhone only reads files
it wrote itself. A bad file almost always means one of these:
- a persisted enum case deleted or **renamed**. None of the six persisted enums
  declares its raw values, so an Xcode Rename of `quick4Games` changes the
  stored string;
- a TestFlight downgrade;
- a restore onto an older app.

In every one of these cases, **every copy holds the same value**: the iPhone,
iCloud, any manual export and the Watch. No backup helps until an update ships
that can read the value again. So the job now is:
1. make the mistake unlikely;
2. make sure nothing is destroyed, so that update can recover everything.

**One step is irreversible: the iCloud overwrite.** Today the moved-aside file
survives on the phone, unless a second failure deletes it (§3.1). Everything
else is recoverable.

## 2. Part 1: Prevent it (tests only)

The six persisted enums (`Player`, `PointOutcome`, `EndingShot`, `MatchFormat`,
`MatchType`, `DoublesServer`) already have pinned raw-value tests in
`ScoreTypesTests` and `PointStatTests`. Add one **golden-file test**:

- `ArchiveGoldenFileTests` in `DeuceMateCoreTests` holds a compact JSON archive
  as a Swift raw-string constant. That's the house style: no resource bundle,
  no `Package.swift` change.
- The archive has fictional matches that together use **every case of every
  persisted enum**: every format, singles and doubles, every doubles server,
  every outcome and ending shot. It also includes `tags`, `matchTypeRevision`,
  `resumeEvents` and the Health fields.
- The test decodes it as `[MatchRecord]` and as a `ManualMatchArchiveBackup`
  file (wrapped in the envelope), and asserts the count and a few values per
  enum.
- **The fixture is append-only.** It was encoded once and committed as text.
  Never regenerate it from the current encoder, because then it would test
  nothing. A new field or case adds a new match to it, and existing JSON is
  never edited. The file header says so.

It catches a deleted case, a renamed case, a property rename and a new required
field. Like all tests here, it only helps when someone runs it, because there is
no CI.

**Size:** 0 production lines, about 150 test lines (mostly the fixture).

## 3. Part 2: Destroy nothing (PR A)

### 3.1 Keep every damaged copy

In `readCanonicalFile`:
- Move the file aside to a **dated** name, `<file>.corrupt-<yyyyMMdd'T'HHmmss>`
  (for example `matchHistory.json.corrupt-20261123T101500`). Delete the
  `removeItem(at: aside)` that today destroys an earlier copy.
- Apply backup exclusion to the moved copy, best-effort, through the existing
  `storageConfiguration.backupExcluder`. A copy of a main file from before the
  Health sidecar existed can still hold Health fields, which must stay out of
  device backups (Guideline 5.1.3(ii)).
- Nothing else changes. The archive still starts empty, so new matches still
  save, and the app stays fully usable.

### 3.2 Pause iCloud while a damaged copy exists

- `syncICloudBackupOnQueue` returns at the top while a **dated** damaged copy
  of any of the three canonical files sits in `MatchArchive/`. That blocks both
  the push and the initial restore, so the iCloud copy stays exactly as it was.
- It is a file-existence check, not a flag, so it **persists across launches**.
  Without that, the next launch would open the new, near-empty file normally
  and push it, which is the original bug.
- **Legacy `.corrupt` files (no date) don't pause iCloud.** 1.4.0 may already
  have left them on some phones, possibly long ago. Pausing on upgrade would
  silently stop backups for users with no current problem. They still appear
  in Archive Diagnostics (§5).
- A damaged Health sidecar (`healthData.json`) doesn't pause anything. iCloud
  never holds Health data, and the sidecar is a re-fetchable copy.
- While paused, deletions and forgets don't reach iCloud either. That's
  intended: the iCloud copy is frozen as it was.

**How the pause ends.** Only when the dated copies are gone, and only a fixing
build removes them, after it has recovered their contents (§6). There is no
button to end it (D1, decided No). A Resume button would push the reduced
archive over the good backup, which is the one irreversible step this part
exists to prevent. It would also need its own follow-ups: somewhere to keep the
moved copies, code in the hotfix to recover from there, and a way to clean them
up. A hotfix that doesn't handle the copies leaves iCloud paused, which is the
safe way to fail. Until then, new matches still save on the iPhone, the Watch
keeps its last 25, and manual export (Part 3) still works.

### 3.3 Tell the user

Add one case to Core's `ICloudBackupCopy`:
- `.pausedDamagedArchive`: "iCloud backup paused — your iCloud copy is
  unchanged", with an `exclamationmark.icloud` symbol in orange.
- It wins over every other case except "toggle off". It's resolved from a new
  `isPausedForDamagedArchive` input that the store publishes.

The Matches screen's existing indicator shows it. In PR A it's a plain label.
PR B makes it a button that opens Archive Diagnostics. No alert, no blocking
screen, and nothing else in the UI changes.

**Size:** about 50 production lines (store about 30, Core about 12, views about
8). About 80 test lines:
- a decode failure keeps a dated copy and leaves an older copy in place;
- iCloud isn't written while a dated copy exists, and still isn't on the next
  launch;
- a legacy `.corrupt` file doesn't pause;
- a damaged sidecar doesn't pause;
- the `ICloudBackupCopy` resolution order.

## 4. Part 3: Encourage exports

This is [`ARCHIVE_EXPORT_REMINDER_PLAN.md`](ARCHIVE_EXPORT_REMINDER_PLAN.md),
unchanged and shipped on its own schedule. It doesn't depend on this plan.

A manual export protects against genuine damage straight away. For the
self-inflicted case it protects once the fixing update ships: the update can
import the user's own export again, even if the iPhone archive never recovers.

## 5. Part 4: Archive Diagnostics (PR B)

A screen that turns a damaged copy into a report a person or a coding agent can
act on. It is the "application debugging stats" the owner asked for. It also
lists every archive file on the iPhone and in iCloud, so support can see the
state of both without a Mac.

### 5.1 Where it appears

- **Settings › Backup & Transfer › Archive Diagnostics, always** (D5). It's the
  last row in that section: a plain navigation row with no badge or count, so
  it stays out of the way unless someone looks for it. While a damaged copy
  exists, the row also shows a small orange "Needs attention" detail.
- Tapping the paused iCloud indicator (§3.3) opens the same screen.

**Collapsed by default.** The screen opens on a short status and the share
actions. Everything detailed (the damaged copies and the two file groups) sits
in collapsed sections that the user expands only if they want to look. The
report always contains every detail, whether or not a section was expanded.

### 5.2 What the screen shows

The status at the top depends on which copies exist. With **no damaged copy**,
which is almost every user:

> **No problems found**
>
> Your match archive opened normally. If support asks for diagnostics, share
> the report below.

With a **dated** copy (iCloud paused):

> **Some match data couldn't be opened**
>
> DeuceMate kept a copy of the file it couldn't read. Nothing has been deleted.
> Your iCloud backup is paused, so it still holds your matches as they were.
> It resumes by itself once an app update recovers the copy.
>
> This usually means an app update is needed. Check the App Store. If there
> isn't one, share the report below with DeuceMate support, or give it to a
> coding agent to look at.

With only **legacy** (undated) copies, iCloud was never paused, and the 1.4.0
launch that kept the copy probably replaced the backup. So the screen says so:

> **An earlier version couldn't open some match data**
>
> DeuceMate kept a copy of the file. Your iCloud backup wasn't paused at the
> time and may have been replaced, so this copy may be the only one of those
> matches. Keep it, and share the report below with DeuceMate support.

Below the status, one line for the iCloud backup state (on, off, paused or
unavailable), then three **collapsed** sections, each a standard disclosure
row showing only its title and a count until expanded:
- **Damaged copies** (only while one exists): original file name, the date it
  was moved aside, and its size.
- **Files on this iPhone:** every file in `MatchArchive/`, with its size and
  modified date. Damaged copies are marked. Any archive file an older build
  left in `Documents/` is listed too.
- **Files in iCloud:** every file in the backup, with its size, modified date
  and upload status. Or one line saying iCloud is unavailable.

These are the same rows as §5.3's file list. Expanding a section doesn't
change any file.

Then the actions, always visible:
1. **Share Report.** Opens the share sheet with
   `DeuceMate-archive-report-<date>.md`. It contains no match data (§5.3), so
   it is safe to send anywhere.
2. **Share Report and Damaged Files** (only while a damaged copy exists). The
   same report plus the damaged copies
   of `matchHistory.json`, `deletedMatchIDs.json` and `forgottenPlayers.json`,
   after this disclosure:
   > These files contain your scores, player names and playing style notes.
   > Files from older versions may also contain heart rate, steps, distance and
   > calories. Private match notes are never included. Only share them with
   > DeuceMate support or a tool you trust. Never post them publicly.

A damaged copy of the Health sidecar (`healthData.json`) is listed and
reported, but never attached: it holds only Health data, which DeuceMate can
fetch again from Apple Health. There is no Resume iCloud Backup action (D1,
§3.2).

Sharing uses the existing share-sheet pattern (`GamePlanShareSheet`) and an
`ExportStaging` generation, ended when the sheet closes. The report is a plain
`.md` file, so the user can send it by Mail or Messages, AirDrop it, or save it
with Files, for example to get it to a computer with a coding agent. There's no
Mail composer and no new framework.

### 5.3 The report

`ArchiveDiagnosticsReport` is a pure Core builder that produces Markdown:
readable by a person, and parseable by a coding agent without a hosted page.

1. **What happened**, in two sentences, plus the support address. With no
   damaged copy it says "No damaged copies", and sections 4 and 6 are left
   out.
2. **Environment:** app version and build, iOS version, the report date. No
   device identifiers.
3. **Files** (what the screen's Files section shows, as two Markdown tables):
   - **On this iPhone:** every entry in `Application Support/MatchArchive/`
     (not recursive) plus any `matchHistory.json` or `deletedMatchIDs.json`
     left in `Documents/` by an older build. Per file: name, size in bytes,
     modified date, and whether it is a damaged copy.
   - **In iCloud:** the iCloud backup state (on, off, paused or unavailable),
     then every entry at the top level of the iCloud container. Per file: name,
     size, modified date, **upload status** (Uploaded, Uploading, Waiting to
     upload, or Upload failed with the error's domain and code) and whether
     it's downloaded to this iPhone. A placeholder for a file that isn't
     downloaded (`.<name>.icloud` on older iOS) is shown under the file's real
     name. A value iCloud doesn't report is shown as "unknown".
   - All of it comes from `URL.resourceValues` and directory listings, on the
     store's queue. It **never reads a file's contents, never starts a
     download, and never writes**, so building the report can't change iCloud
     or disturb the pause. File names are fixed by the app, so the list holds
     no personal data.
4. **For each damaged copy:**
   - name, original file, the date it was moved aside, size, and SHA-256
     (CryptoKit);
   - **the result of decoding it again now**, with this build. For a failure
     that means the error type, the coding path in readable form (for example
     `[12].points[204].endingShot`) and the debug description, which names the
     bad value (for example `Cannot initialize EndingShot from invalid String
     value "dropShot"`).
   - If this build **can** read the file, the report says so. That is what a
     user who has installed the fixing update would see.

   Decoding again on demand means nothing has to be stored at failure time,
   and the report always reflects the installed build.
5. **Stored values this build accepts:** every raw value of the six persisted
   enums, from `allCases`. `Player`, `MatchType` and `MatchFormat` gain
   `CaseIterable`, which changes nothing that is stored. An agent can compare
   the bad value against this list.
6. **Instructions for a coding agent**, fixed text:
   - Never change or delete the original file. Work on a copy.
   - **Change values, never drop records.** If the bad value looks like one
     DeuceMate used to accept (for example an old format name), stop. It's an
     app bug, and an update will read it unchanged. Tell the user to contact
     support.
   - To return a repaired archive, wrap the repaired `matchHistory.json` array
     in a manual archive file:
     `{"format": "deucemate.matchArchive", "schemaVersion": 1,
     "exportedAt": <seconds since 2001-01-01, or an ISO-8601 string>,
     "includesHealthData": <true if any record has Health fields>,
     "records": [...]}`.
     Dates in the records are already in the right encoding, so copy them as
     they are.
   - If `forgottenPlayers.json` was attached, copy its object into a
     `forgottenPlayers` key.
   - Then the user imports it with Settings › Backup & Transfer › Import Match
     Archive › **Merge**.
   - The report doesn't contain the file. Ask the user for the damaged files if
     they weren't attached.

**Privacy:** the report never contains a match, a name or a note. A decoding
error names a field and a value, never a player. The builder's tests pin this.

**Size:** about 330 production lines:
- Core about 145: the report builder with its fixed text and the Files tables,
  the coding-path formatter, and `CaseIterable`;
- store about 65: list local and iCloud files with their resource values;
  hash and decode result for damaged copies; stage copies;
- views about 120: the screen with its three wordings and collapsed sections,
  the always-present Settings row with its "Needs attention" detail, and the
  indicator tap.

About 200 test lines:
- the report holds the coding path, hash and enum list, and never holds a name
  or note even when the damaged file does;
- the readable-now wording;
- staging and cleanup;
- a phone with no damaged copy gets the "No problems found" wording and a
  report without the damaged-copy and repair sections;
- a legacy-only phone gets the legacy wording and the "Needs attention"
  detail, and isn't paused;
- the Files tables: every local entry listed, a `Documents/` leftover listed,
  iCloud upload states and "unknown" values formatted, iCloud unavailable;
- the Health sidecar copy is reported but never attached.

## 6. Example: `quick4Games` deleted by mistake

1. The update ships, and a user with one Quick 4 match opens the app.
   `matchHistory.json` fails to decode. It's moved to
   `matchHistory.json.corrupt-…`, the archive starts empty, and **iCloud is
   paused**, so the backup still holds every match.
2. The Matches screen says "iCloud backup paused — your iCloud copy is
   unchanged". New matches still save on the iPhone.
3. The user taps it and shares the report. It reads
   `[3].matchFormat: Cannot initialize MatchFormat from invalid String value
   "quick4Games"`, and the enum list shows the value is missing. Support, or an
   agent following the instructions, sees an app bug.
4. A hotfix restores the case under CLAUDE.md §4's retire recipe. Recovery is
   decided **then**, with the exact failure known. For example, the hotfix
   merges the dated copy back into the archive and then deletes it, which ends
   the pause, and the next push brings iCloud up to date. That code is written
   only if this ever happens.

## 7. Not doing (non-goals)

- A blocking screen, a global pause of saves, a Loading state, or retry
  machinery.
- Reading a damaged copy back into the archive automatically, a "Restore from
  iCloud" action, or any repair inside the app.
- Any way to end the iCloud pause inside the app, such as a Resume button (D1).
- A file explorer for damaged files. Diagnostics lists files and their
  metadata; it never opens the iCloud files or shows any file's contents.
- A hosted recovery page. The report carries the agent instructions itself
  (D3).
- The Mail composer, `OSLogStore`, crash logs or analytics.
- Watch changes. The Watch already fails closed (`loadHistoryOrNil`).
- Strict decoding of `forgottenPlayers.json`, unknown-safe enums, versioned
  files (#19), restore points, dated iCloud copies. These are all in the
  deferred `ARCHIVE_SAFETY_PLAN.md`.

## 8. Scope rules for reviewing this plan and its PRs

These exist because #228–#240 grew with every review.
- Every finding is labelled **blocks the fix** (it breaks §3's guarantee that
  nothing is destroyed, or leaks data) or **follow-up**. Follow-ups go to
  TECHNICAL_DEBT, not into the PR.
- A finding that adds a mechanism to handle the failure of another mechanism is
  a follow-up by default.
- Weigh likelihood: this plan accepts rare-on-rare cases (§7).
- Re-state the line count after each round. Breaking the budget needs the
  owner's OK.

## 9. Decisions (signed off 2026-11-23)

| # | Decision | Outcome |
|---|---|---|
| D1 | Offer **Resume iCloud Backup**? | **Decided: No** (2026-11-23). Resuming would overwrite the good iCloud backup and need its own follow-ups (§3.2). The pause ends only when a fixing build recovers the copies |
| D2 | Should Share Report and Damaged Files exist, or the report only? | **Decided: Both.** The report alone diagnoses the cause, and the files are needed to repair genuine damage |
| D3 | Also publish the agent instructions as a web page? | **Decided: Not now.** Do it only if support starts receiving these reports |
| D4 | Ship PR A before PR B? | **Decided: Yes.** PR A closes the irreversible step on its own, and PR B can follow |
| D5 | Show Archive Diagnostics **always**, not only while a damaged copy exists? | **Decided: Yes** (2026-11-23), as a plain last row in Backup & Transfer with its details collapsed until the user opens them (§5.1). The file list then helps with any backup question, and the user can export the report from there |

## 10. Phases

| PR | Surface | What | Production | Tests |
|---|---|---|---|---|
| A | `[Core]` + `[iOS]` | Golden-file test, dated copies, iCloud pause, `.pausedDamagedArchive` indicator | ≤ 75 | ~230 |
| B | `[Core]` + `[iOS]` | Archive Diagnostics: report builder, file list (iPhone and iCloud), screen, Settings row, share | ≤ 340 | ~230 |

Each PR also updates:
- CLAUDE.md §1 and the `PhoneStatsStore` row. PR A also adds the **hotfix
  rule** to CLAUDE.md §4 ("Retire a case in a persisted enum") and §5:
  > Any fix for a decode failure must recover the dated
  > `.corrupt-<date>` copies into the archive and then delete them. Restoring
  > the enum case alone isn't enough: while a dated copy exists, iCloud stays
  > paused, so the user's matches stay stuck on the phone.

  The fixing update must include a test that a dated copy is merged back and
  removed, and that iCloud then resumes;
- TECHNICAL_DEBT #18;
- `docs/architecture/sync-and-data-flow.md`;
- `docs/architecture/file-inventory.md` (PR B: the new view and Core file).

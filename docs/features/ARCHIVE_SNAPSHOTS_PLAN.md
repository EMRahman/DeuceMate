<!--
machine-readable summary (parse this block first)

status: proposal — plan only, nothing implemented
author: Claude, from the owner's review of #228–#231 recovery flows
date: 2026-11-22
feature: "Keep a few point-in-time snapshots of the iPhone match archive so the user can go back to an earlier version after a failure the push guard cannot anticipate (valid-but-wrong data, a bad merge, a wrong Replace)."
recommendation: "Local snapshots first (MatchArchive/Snapshots/, health-stripped, backup-excluded): at most one automatic snapshot a day plus a mandatory one before each destructive recovery action, pruned by a pure Core rule (3 daily + 2 weekly + the last 3 pre-action). Tombstones and the forgotten-player ledger are NEVER restored from a snapshot — the live ones always apply — and a Delete Permanently / Forget Player scrubs existing snapshots at once. Restore is a confirmed Replace that snapshots first. iCloud generations are a later, optional phase."
hard_findings:
  - "Rotating a fixed set of N snapshots on every push would lose the good ones within N syncs: the debounced push fires on every save, so a bad state (a wrong Replace) is the newest N snapshots almost immediately."
  - "A snapshot taken before Delete Permanently or Forget Player still holds that data. The repo treats forgetting as a privacy action, so snapshots must not become a place deleted matches live on."
  - "MatchArchive/Recovered/ (written by every recovery action since #228) already has the same property: it holds raw copies, including matches the user may later delete or forget. Whatever rule snapshots get, Recovered/ needs it too."
  - "A snapshot may only come from an archive that LOADED cleanly. Snapshotting a suspended or half-read archive would present unreadable state as a good restore point (the 'read failure != empty archive' rule)."
scope:
  in_scope:
    - "Core: ArchiveSnapshotRetention + ArchiveSnapshotManifest (pure), tests"
    - "iOS: PhoneStatsStore snapshot writer/reader, pre-action snapshots, scrub on delete/forget, Restore earlier version screen"
  out_of_scope_v1:
    - "iCloud-hosted snapshot generations (phase 5, optional)"
    - "Watch archive snapshots (the Watch keeps a rolling 25 and the phone is the archive)"
    - "Snapshots of private notes or Health data"
    - "Per-match history / undo of single edits"
decisions: []
-->

# Plan: Archive Snapshots — go back to an earlier version of the archive

Read alongside [`TECHNICAL_DEBT.md`](TECHNICAL_DEBT.md) #18 (fail-closed archive,
push floor, recovery) and [`ICLOUD_BACKUP_HARDENING_PLAN.md`](ICLOUD_BACKUP_HARDENING_PLAN.md).

## 1. Why

#228 stops the failures it can name: an unreadable or undecodable file keeps
its bytes and pauses writes, `BackupPushGuard` withholds a push that would drop
matches with no tombstone or confirmed Replace to explain it, and an iCloud
account switch inspects the new account's backup instead of trusting the old
manifest. Every one of those is a **recognisable shape**.

What it cannot catch is data that is *valid but wrong*:

- a confirmed Replace with the wrong file (the push guard is told, by design,
  that dropping matches is intended);
- a bad merge or a bug that rewrites many records plausibly;
- a restore that picked the wrong side of a conflict.

Recovery from those today depends on whichever copy happens to exist: the
iCloud backup is overwritten by the next push, and `Recovered/` only exists if
the recovery action that caused the loss remembered to write it. The recovery
review that prompted this plan found exactly that for Replace (fixed in the same
review: Replace now keeps a copy of the iCloud history first). That fix is
point-by-point; snapshots are the general answer.

Archives are small relative to a phone's storage, so a handful of generations
is cheap — **to be measured, not assumed** (§5.3).

## 2. What a snapshot is

A snapshot is a full, health-stripped copy of the **match list** at a moment,
plus a small manifest. It is not a second source of truth and nothing reads it
during normal operation.

| Part | In a snapshot? | Why |
|---|---|---|
| `[MatchRecord]` (tags included) | Yes, health-stripped | The thing being protected. |
| Health fields (the five HealthKit-derived ones) | **No** | Snapshots reuse `HealthSidecarPolicy.split`; the live backup-excluded sidecar is merged back on restore (`HealthSidecarPolicy.merge`), exactly as Restore from iCloud does. Keeps the later iCloud phase inside Guideline 5.1.3(ii) with no new rule. |
| Tombstones (`deletedMatchIDs`) | **No** | Always the live set. A snapshot can never resurrect a deleted match. |
| Forgotten-player ledger | **No** | Always the live ledger; restore scrubs with it. |
| Private notes | **No** | iPhone-only sidecar, keyed by match UUID. Restored matches re-attach to notes that still exist; notes are never copied anywhere they weren't. |
| Manifest | Yes | `schemaVersion`, `takenAt`, `reason` (daily / pre-Replace / pre-restore / pre-remove / pre-bring-back), record count, newest match date, newer-format count, `identityKey` of the iCloud account at the time (nil if none), app version. |

Records are written with `PersistedArchiveCodec`'s **versioned envelope**
(`format` + `schemaVersion` + `items`), not a bare array — these are new files
so there is no old reader to stay compatible with, and a newer build's
snapshot then fails closed cleanly on an older build (#19). The manifest is its
own versioned file. No field is added to `MatchRecord`, so CLAUDE.md §4 is not
triggered; if a later phase does add one, follow the §4 recipe.

## 3. When snapshots are taken, and kept

### 3.1 Not on every push

The debounced backup push fires on every save. Rotating "the last five" on
each one means a bad state evicts every good snapshot within five syncs.
Snapshots therefore follow time and intent, not traffic.

**Triggers**

1. **Automatic, at most once per 24 hours**, taken after a successful canonical
   write while the app is active, from the already-loaded in-memory archive.
2. **Mandatory, immediately before each destructive recovery action:** confirmed
   Replace import, Restore from iCloud, Remove from Backup and Bring Them Back.
   (Restore earlier version itself, §6, also snapshots first.) If this snapshot
   cannot be written, **the action is refused** with "nothing has been changed" —
   the same rule `Recovered/` already follows (a failed copy aborts recovery).
3. Not on Delete Permanently or Forget Player: those are deliberate, and §4
   explains why snapshotting them would work against the user.

### 3.2 Retention rule (pure Core type)

`ArchiveSnapshotRetention` — no file I/O, injected `now` and `Calendar`:

- `shouldTakeAutomatic(existing:now:)` — true when no automatic snapshot is
  within 24 hours, and **false when the archive is empty but a non-empty
  snapshot exists** (an empty archive must never become a restore point that
  pushes out real ones; the user sees the "archive is empty" state elsewhere).
- `prune(_:now:) -> [SnapshotID]` — the ids to delete. Recommendation:
  - **3 daily**: the newest automatic snapshot of each of the last 3 days that
    have one;
  - **2 weekly**: the newest automatic snapshot of each of the 2 calendar weeks
    before that;
  - **last 3 pre-action** snapshots, whatever their age, dropped after 30 days;
  - never prune the only snapshot that has the highest record count unless a
    newer one has at least as many (a guard against a shrinking archive
    gradually evicting the large one — see open question 3).
  - Worst case ≈ 8 snapshots. Pre-action snapshots are kept apart so a busy
    recovery session cannot push out the daily ones, and a dull week cannot
    push out the undo for a Replace made yesterday.

Tests pin every boundary (exactly 24 h, DST, week edges, empty archive, ties
broken by id, clock going backwards).

## 4. Deletion intent and privacy

A snapshot taken before Delete Permanently or Forget Player still contains that
data. The repo treats forgetting as a privacy action, so restoring or even
retaining it must not undo or undermine the user's choice.

Options evaluated:

| Option | Verdict |
|---|---|
| **A. Scrub on restore** (tombstones + `ForgottenPlayerLedger.scrubbed`, the same merge path Restore from iCloud uses) | Needed regardless — it is what makes a restore correct. But on its own the data still sits on disk until the snapshot ages out (up to ~3 weeks). |
| **B. Expire snapshots quickly** | Shortens the window but also shortens the protection (a problem noticed after a week is the common case), and still leaves data on disk for days. Rejected as the primary mechanism. |
| **C. Scrub snapshots at deletion time** | Delete Permanently / Forget Player rewrite each existing snapshot without that match / player, best effort; a snapshot that can't be rewritten is **deleted**. At most ~8 small files. Deletion then means deletion. |

**Recommendation: A + C.** A is the correctness rule on every restore; C makes the
privacy promise true on disk. Neither depends on a snapshot being short-lived.
The cost of C is that a snapshot is not an "undo delete" — which matches how
tombstones already behave.

**`Recovered/` has the same property** and today keeps raw copies indefinitely.
It should get the same treatment (C, or expiry after 30 days): phase 4, and a
line in `docs/website/privacy.html` once decided. Flagged here rather than
silently widened.

Private notes are not in snapshots (§2). The match-deletion path already removes
a note only after the deletion commits; snapshots add no note state to keep in
step.

## 5. Storage

### 5.1 Local first

```
Application Support/MatchArchive/Snapshots/
  <ISO8601>-<reason>-<id8>/
    snapshot.json        manifest (versioned)
    matchHistory.json    health-stripped, versioned envelope
```

- Same backup-exclusion rule as the canonical store: directory exclusion
  verified before every write, file exclusion reapplied after (as
  `MatchNotesStore` does). A snapshot must not ride into an iOS device backup
  that the canonical archive is excluded from.
- Written atomically to a temporary name inside `Snapshots/`, then renamed, so a
  crash leaves an incomplete directory (ignored and swept) and never a
  half-snapshot that looks complete.
- Protects against: **app bugs and user mistakes** (a wrong Replace, a bad
  merge, a bug in a later build). It does **not** protect against losing or
  corrupting the phone itself.

### 5.2 iCloud generations (phase 5, optional)

Same files in the ubiquity container (`Snapshots/`), identity-scoped like
`BackupManifest`: the snapshot manifest carries the account's `identityKey`, and
Restore only offers snapshots whose key matches the active account; after an
account switch the new account's container is inspected directly, never
trusting the cached listing. Health stays stripped (already true). Protects
against **losing the phone**, which local snapshots cannot. Costs the user's
iCloud quota and adds another pushed surface that must fail closed on an
unreadable remote. Worth doing only if phase 1–3 prove useful; the existing
one-way "watch → phone → iCloud" flow stays intact (snapshots are written by the
phone, never read back during normal operation).

### 5.3 Size — measure before committing

I have no measured numbers for a heavily used archive. Phase 0 measures
`matchHistory.json` size on a realistic fixture (hundreds of matches with full
point tracking). If 8 generations is too large, the mitigations, in order:
compress (`NSData.compressed(using: .lzfse)` — Foundation, no dependency),
drop to 2 daily + 1 weekly, or store daily snapshots as a diff against the
newest weekly. Decide on the measurement, not on "archives are small".

## 6. Restore: "Restore Earlier Version"

- **Entry points:** the archive problem notice (a suspended archive can still
  list snapshots, since they are independent files), the iCloud Backup Paused
  notice, and Settings › Backup & Transfer.
- **List:** date taken, why (automatic / before Replace / …), match count, newest
  match date, and "N need a newer version of DeuceMate" when the lenient read
  skipped some.
- **Read:** `LenientRecordList`, so one newer-format record cannot hide the
  rest, and the newer-format count is shown rather than hidden.
- **Apply:** snapshot records → `HealthSidecarPolicy.merge` with the live
  sidecar → drop live tombstones → `ForgottenPlayerLedger.scrubbed` → adopt. In
  push-floor terms this is a **confirmed Replace**, so it reuses the Replace
  machinery (`pendingReplaceManifest`: the iCloud history is copied to
  `Recovered/` before the push that may drop iCloud-only matches).
- **Before applying:** a pre-restore snapshot of the current archive (refuse on
  failure), so the restore itself can be undone.
- **Confirmation copy** states plainly: *"This replaces your current N matches
  with the M matches from <date>. Matches added since then will no longer be on
  this iPhone (your Apple Watch may send recent ones again). DeuceMate keeps a
  copy of your current archive first."* — destructive-styled primary action, a
  non-`.cancel` safe choice (iOS 26+ hides cancel-role buttons in popover
  dialogs, per CLAUDE.md).
- Failure after adoption reports what changed (the lesson of "Nothing has been
  changed" being wrong in Bring Them Back, fixed alongside this plan).

## 7. Fail-closed interplay

- **Only from a clean load.** The writer runs on the store queue and refuses
  while `canonicalSuspension != nil` or writes are suspended. Snapshots come from
  the in-memory archive that was read successfully, never from re-reading files
  that may be half-written.
- **Never blocks the user.** Automatic snapshots run after the user's own write
  has committed, are best effort and log-and-skip on failure (no alert). Only the
  *pre-action* snapshot can refuse something, and only the destructive recovery
  action it guards — never a save, a Watch delivery, a delete or a tag edit.
- **No effect on the push guard.** Snapshots are not an input to
  `BackupPushGuard` and do not satisfy it: a snapshot existing never makes
  dropping a match from iCloud "explained".
- **A read failure of a snapshot is not an empty snapshot.** An unreadable or
  newer-version snapshot is listed as such and left in place, never silently
  pruned as "bad".

## 8. Phases (small PRs)

| Phase | Surface | What |
|---|---|---|
| 0 | docs / measure | Size a realistic archive; confirm 8 generations (or choose compression). Decide open questions 1–3. |
| 1 | `[Core]` | `ArchiveSnapshotManifest` (versioned), `ArchiveSnapshotRetention`, copy strings; full test matrix. No app change. |
| 2 | `[iOS]` | `PhoneStatsStore` snapshot writer/reader (local only), automatic daily, pre-action snapshots on the four destructive actions, scrub on Delete Permanently / Forget Player. |
| 3 | `[iOS]` | Restore Earlier Version screen + flow (lenient read, scrub, pre-restore snapshot, confirmed-Replace push). |
| 4 | `[iOS]` | Apply the §4 rule to `Recovered/`; update `privacy.html` / App Review notes if retention text changes. |
| 5 | optional | iCloud generations (§5.2). |
| docs | `docs:` | CLAUDE.md file map, `docs/architecture/file-inventory.md` for new source files, TECHNICAL_DEBT #18 text, browser-demo note (the phone demo simulates storage; mirror the screen only if worthwhile). |

## 9. Test plan

- **Core:** retention boundaries (§3.2), manifest round-trip, newer
  `schemaVersion` fails closed, unknown reason decodes (stored as raw string, like
  `CompetitionType`), empty archive never evicts, deterministic tie-breaks.
- **`PhoneStatsStoreTests`** (real files, as the recovery tests): no snapshot while
  suspended; daily at most once; failed automatic snapshot never fails a save;
  failed pre-action snapshot refuses each of the four actions and changes
  nothing; snapshot excludes tombstones / ledger / Health / notes; backup
  exclusion on directory and files; Delete Permanently and Forget Player remove
  the data from every snapshot (and delete one that can't be rewritten);
  restore applies scrub + tombstones, merges the live Health sidecar, takes a
  pre-restore snapshot, withholds nothing it shouldn't from iCloud and copies
  the iCloud history first; a snapshot with one unknown enum value lists
  readable matches and the newer count; a corrupt snapshot is listed unreadable
  and left in place.
- **Manual:** the confirmation wording on a device; restore after a deliberate wrong
  Replace; Dynamic Type; VoiceOver on the list.

## 10. Open questions

1. **Replace vs merge on restore.** The proposal is a true "go back" (Replace). Should
   the screen also offer "Add missing matches only" for the common case where the
   user just wants a lost match back and not to discard newer ones?
2. **Recovered/ retention** (§4): scrub-on-delete, or expire after 30 days, or both?
3. **Shrinking archives.** The "keep the largest" guard in §3.2 prevents slow
   erosion but keeps a possibly-stale large snapshot forever. Is a cap (e.g. 90
   days) acceptable?
4. **Automatic cadence.** 24 h assumes daily use; should it also snapshot before
   an app-update's first launch (a new build is the likeliest source of a bad
   merge)?
5. **iCloud generations** (§5.2): worth the quota and the extra fail-closed
   surface, or is local-only enough given the existing one-way backup?

See [`TECHNICAL_DEBT.md`](TECHNICAL_DEBT.md) #18 for the failure model this
extends.

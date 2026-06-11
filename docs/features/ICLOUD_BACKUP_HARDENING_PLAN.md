# Plan: iCloud Backup Hardening — health-data stripping & reconcile-once initialization

Produced from a Claude-assisted review of the watch → phone → iCloud backup
workflow, produced immediately after the manual archive export/import
landed. Read alongside
[`docs/architecture/sync-and-data-flow.md`](../architecture/sync-and-data-flow.md)
and the storage-model notes at the top of `PhoneStatsStore.swift`.

## Context

The iPhone archive is canonical on-device; iCloud Drive holds a one-way
background backup used for fresh-install restore (`ArchiveBackupPolicy`,
`PhoneStatsStore`). The review found the core design sound — tombstone
propagation, read-failure discrimination, and the merge rules all check out —
but identified three problems this plan fixes:

1. **Compliance: HealthKit-derived data is pushed into iCloud.** App Store
   Review Guideline 5.1.3(ii): *“Apps must not write false or inaccurate data
   into HealthKit or any other medical research or health management apps,
   **and may not store personal health information in iCloud**.”* The backup
   currently contains per-point heart rate and steps plus per-match activity
   totals — all sourced from the HealthKit workout session.
2. **Fresh-install restore race.** Any first local write (most commonly the
   watch’s unsolicited full-history push on session activation, or a manual
   import) calls `adoptOnQueue`, which writes the
   `archiveInitialized.json` marker and schedules a backup push that *cancels*
   a pending restore retry. The push then overwrites the iCloud backup with
   only what the phone holds (≤ the watch’s 25), permanently destroying every
   match that existed only in the backup — precisely the matches the backup
   exists to protect.
3. **Sign-in-later overwrite.** When the ubiquity container is unavailable,
   `syncICloudBackupOnQueue` marks the archive initialized as soon as any
   local data exists. A user who sets up a phone without iCloud and signs in
   later never gets a restore; the first push overwrites their old backup.
   Deterministic, not a race.

**Relationship to the manual archive.** `ManualMatchArchiveBackup`
is the deliberate full-fidelity escape hatch: a *user-initiated* export may
include health data (the guideline restricts the app storing health data in
iCloud, not users taking their own data wherever they choose), and its
merge-mode import already backfills missing health fields per point id
(`mergeMissingHealthData`). This plan leans on that: the iCloud backup gets
*stripped*, and the manual archive is the documented recovery path for health
data. The two policies must stay separate — do not “unify” them.

## The health-field set

Exactly five stored fields are HealthKit-derived and must never reach the
ubiquity container:

| Type | Fields |
|------|--------|
| `MatchRecord` | `totalSteps`, `totalDistanceMeters`, `totalCaloriesKcal` |
| `PointStat` | `heartRateBPM`, `stepsCumulative` |

All five are already `Optional` and decoded with `decodeIfPresent`, so a
stripped record is a valid `MatchRecord` on every build — no schema version,
no migration. Every consumer degrades gracefully when they are `nil`
(`MatchStatsSummary` HR section, `PulseCoachInsights`, `SetActivitySplit`,
detail/export views). `matchElapsedSeconds` / `setElapsedSeconds` come from
app timers, not HealthKit — they stay.

Stripping never touches ids, so the two healing paths keep working:

- **Watch heal (automatic, newest ≤ 25):** the watch’s next full-history push
  carries complete records; `MatchMergePolicy` resolves completed-vs-completed
  with `incomingEnd >= existingEnd`, so the full watch copy replaces the
  stripped restored copy.
- **Manual-import heal (user-initiated, any age):** merge-mode import
  backfills `nil` health fields by match/point id from a previously exported
  archive.
- **Display-time heal:** `HealthKitHRFetcher` re-derives the HR chart from raw
  HealthKit samples, which Apple’s own Health sync carries to a new phone.

## Step 0 — before shipping anything (owner, on-device)

Export a manual archive (Settings → Backup & Transfer) and park a copy off-device.
That is the full-fidelity safety net for all testing below.

## PR A — `[Core]` Strip health-derived data from the iCloud backup ✅ Done

Single choke point: `ArchiveBackupPolicy.backupSnapshot` is the only producer
of outbound backup content, and every mutation source (watch sync, delete,
manual import) funnels through `adoptOnQueue` → `pushBackupOnQueue` →
`backupSnapshot`. Stripping there covers everything, including freshly
imported full-fidelity records.

| File | Change |
|------|--------|
| `Packages/…/Models/MatchRecord.swift` (or a small extension file) | Promote the manual archive’s `private mergeMissingHealthData` into a shared pure helper, e.g. `fillingMissingHealthData(from:)` on `MatchRecord` + the `PointStat` twin, and add the inverse `strippingHealthData()` nil-ing the five fields. |
| `Packages/…/Persistence/ManualMatchArchiveBackup.swift` | Replace its private helpers with calls to the shared ones. **No change to `encode`** — manual exports stay full-fidelity by design (`includesHealthData: true`). |
| `Packages/…/Sync/ArchiveBackupPolicy.swift` | `backupSnapshot` maps records through `strippingHealthData()`. In `resolveBackup`, when a (now health-less) completed backup body replaces a local in-progress checkpoint, backfill the loser’s health fields into the winner via the shared helper instead of discarding them. |
| `PRIVACY_POLICY.md`, `docs/privacy.html` | State that the iCloud copy excludes health measurements; manual exports include them. (Also fold in the PR C corrections for these files if convenient — see below.) |
| `CLAUDE.md`, `docs/architecture/file-inventory.md` | Refresh the `ArchiveBackupPolicy` blurbs to mention stripping. |

Tests (`DeuceMateCoreTests`, all pure):

1. `backupSnapshot` output, encoded with `JSONEncoder`, contains **none of the
   five key names anywhere in the JSON tree** — the strongest guard, and the
   regression test for future fields being added to the wrong side.
2. A stripped record round-trips and equals the original minus the five fields.
3. Watch heal: full completed record vs stripped restored copy through
   `MatchMergePolicy.resolve` → full copy wins.
4. The end-to-end disaster drill: full archive → `backupSnapshot` →
   `initialRestore` into empty local (assert health `nil`, tennis data intact)
   → `ManualMatchArchiveBackup.importSnapshot(.merge)` with the original
   export → assert health fully restored.
5. `resolveBackup` backfill: completed stripped backup over a local checkpoint
   with HR snapshots → winner keeps the checkpoint’s health fields where ids
   match.

Remediation of existing backups is automatic: the push rewrites both container
files wholesale, so the first push after this ships replaces full-data backups
with stripped ones.

## PR B — `[iOS]` Redefine “initialized” as “reconciled with iCloud once” ✅ Done

The marker file’s meaning changes from “the canonical store has been written”
to “the local archive and the iCloud backup have been merged at least once”.
That single change removes both loss scenarios: a local write can no longer
foreclose the restore, and a later sign-in reconciles before the first push.

| File | Change |
|------|--------|
| `DeuceMate/Persistence/PhoneStatsStore.swift` | `adoptOnQueue` stops calling `markArchiveInitializedOnQueue`; it always schedules a backup pass and lets the pass decide. The pass owns the marker per the matrix below. Optional rider: skip the push when `ArchiveBackupPolicy.sameContents` says the last-pushed content is unchanged (the helper exists, tested, currently unused). |

Behaviour matrix for `syncICloudBackupOnQueue`:

| Marker | Container | Today | After PR B |
|--------|-----------|-------|------------|
| absent | available, files settled/missing | restore → mark → push — *unless a local write already marked, which silently skips restore* | always `initialRestore` (it merges correctly with non-empty local) → mark → push |
| absent | available, files downloading | retry ×4 then defer; a concurrent local write forecloses restore | same retry/defer, but local writes no longer foreclose — a later pass still restores |
| absent | nil | mark initialized if local data exists | leave unmarked, no-op; the sign-in’s `NSUbiquityIdentityDidChange` / next foreground reconciles first |
| present | available | push | push (optionally `sameContents`-gated) |

Notes:

- `isRestoringFromICloud` semantics are unchanged (set on init when
  uninitialized + empty + available; cleared by `finishRestoreIndicator`).
- Write-failure handling in the restore path (revert and bail without marking)
  stays as-is.
- Backward compatibility: existing installs already carry the marker and see
  no behaviour change. Installs that were *already* victimised by the
  sign-in-later path also carry the marker; their remediation is the manual
  import, not retroactive logic — explicitly out of scope.
- Honest testability note: the policy halves are pure-tested in Core; the
  store orchestration is `FileManager`/ubiquity-bound and is verified
  on-device (drill below). A seam for store-level tests is the actor rewrite
  already tracked as TECHNICAL_DEBT #6 — do not block this fix on it.

On-device test drill (after A + B, with the Step 0 archive banked). ⚠️ Steps
3–4 are destructive on pre-B builds — step 4 deterministically overwrites the
real backup with only the watch’s matches. Never run them before PR B ships:

1. Delete + reinstall with the watch unavailable (airplane mode) → expect the
   full match list restored from iCloud, health fields absent.
2. Manual import (Merge) of the Step 0 archive → expect Pulse Coach, set
   splits, totals, and HR snapshots back.
3. Delete + reinstall with the watch live → expect archive = backup ∪ watch
   history; nothing overwritten (the pre-B code loses backup-only matches
   here).
4. Sign out of iCloud, reinstall, sync watch, sign back in → expect a
   reconcile (union), not an overwrite.

## PR C — `docs:` corrections (no behaviour change) ✅ Done

Carried over from the review; independent of A/B except where A already
touches the privacy texts:

- `docs/index.html` FAQ: “Is my match data synced to the cloud? **No** … no
  iCloud” contradicts the app (and `docs/privacy.html` on the same site).
- `PRIVACY_POLICY.md`: “**Is never transmitted off your devices by the App**”
  contradicts its own iCloud Sync section; “stored in your personal iCloud
  Drive container **rather than** the device’s local Documents folder”
  describes the pre-rewrite, iCloud-primary model.
- `MatchMergePolicy.resolve` docstring rule 5 still says “keep the one with
  more points” — stale; the implementation always accepts the incoming
  in-progress record (deliberately, for undo).
- `PhoneMatchSyncService` comments say “10-match cap” twice; `WatchHistory.cap`
  is 25.

## PR D — `[iOS]` Ask-before-restore prompt (owner-requested; depends on PR B) ✅ Done

Owner feedback after a successful same-device reinstall test: the
silent auto-restore worked, but it would be better if a fresh install
**detected the iCloud backup first and asked** before importing — for
visibility, control, and so the manual-import path can be exercised
deliberately. This is a UX layer on top of PR B, not a replacement: PR B’s
merge-on-reconcile is exactly what makes “restore whenever the user answers”
safe at any time.

Mechanics, on top of the PR B behaviour matrix:

- When a pass finds *marker absent + container available + both files settled
  **and non-empty***, it does **not** auto-reconcile. It publishes a pending
  preview — record count and newest match date, derived from the raw backup
  arrays themselves (no container file-format change) — and the UI prompts:
  *“Found an iCloud backup with N matches (latest: <date>). Restore?”*
- **Restore** → `initialRestore` merge → mark reconciled → push. Identical to
  PR B’s path, just user-triggered.
- **Not now** → stay unreconciled. The archive keeps working locally and
  watch merges keep landing, but backup pushes stay paused (marker absent), so
  the old backup is never overwritten while the question is open. The status
  line must say so (new `ICloudBackupCopy` state — “iCloud backup found,
  restore pending” — alongside the existing `.restoring`).
- **There is deliberately no “never restore, start pushing” button.** Pushing
  without reconciling overwrites the declined backup — the exact loss PR B
  exists to prevent. If such an escape hatch is ever wanted, it needs a
  destructive-action confirmation and should overwrite tombstone-style, not
  silently.
- Genuinely new users (no backup files, or empty ones) never see the prompt:
  that pass reconciles against nothing, marks, and pushes silently, as in
  PR B.
- Drill adjustment: with PR D, drill steps 1 and 3 begin with the prompt
  appearing and choosing **Restore**; step 4’s sign-in ends with the prompt
  rather than a silent merge.

## PR E — `[iOS]`/`[Core]` Evidence-based backup status (owner-reported; independent of A–D) ✅ Done

Owner-observed false positive: after a manual import **with no
internet connection**, the archive showed “Backed up to iCloud”. Mechanism:
`isICloudAvailable` only checks `ubiquityIdentityToken != nil` (signed-in
account state, cached offline — not connectivity), and the backup push
“succeeds” offline because it writes to the ubiquity container’s **local
replica**; the daemon uploads later. `ICloudBackupCopy`’s docstring already
concedes the status is “not an upload-progress reading” — this PR removes that
shortcut and derives the label from evidence.

Design — ask iCloud for a receipt instead of assuming:

- After each push, and at the existing triggers (foreground sync, ubiquity
  change), read `URLResourceValues` for
  `.ubiquitousItemIsUploadedKey` / `.ubiquitousItemIsUploadingKey` on both
  backup files (cheap, on the store queue) and publish the result, e.g.
  `@Published isBackupUploaded: Bool?` (`nil` = unknown/never pushed).
  Polling at those trigger points is sufficient — the status line is only
  visible while the app is foregrounded; an `NSMetadataQuery` live feed is an
  upgrade, not a requirement.
- `ICloudBackupCopy` gains a state between “backed up” and “unavailable”:
  `pendingUpload` — *“Waiting to upload to iCloud”* — shown when the account
  is available but the current file versions are not yet uploaded.
  `.backedUp` is shown only when both files report uploaded. Resolution rule
  + copy stay in Core with `ICloudBackupCopyTests` coverage (truth table over
  enabled/available/restoring/uploaded).
- This also fixes the adjacent false positive found in review: a deferred
  initial restore currently shows `.backedUp` while nothing has ever been
  pushed (`isBackupUploaded == nil` → don’t claim backed up).

| File | Change |
|------|--------|
| `Packages/…/Settings/ICloudBackupCopy.swift` | New `pendingUpload` case + label/symbol; `current(...)` takes the uploaded signal; docstring drops the “not an upload-progress reading” carve-out. |
| `DeuceMate/Persistence/PhoneStatsStore.swift` | Read the two files’ upload resource values after pushes / on sync triggers; publish for the views. |
| `Views/PastMatchesView.swift`, `Views/MatchDetailView.swift` | Pass the new signal through. |

## Interplay notes & invariants

- Merge-mode import deliberately un-tombstones imported ids
  (`tombstones.subtracting(incomingIDs)`) — correct for an explicit restore;
  the next (stripped) push propagates the reduced tombstone set consistently.
- Until PR B lands, a manual import on a fresh install can foreclose the
  initial restore exactly like a watch sync — land A and B before reinstall
  testing.
- Invariants that must survive this work: the phone archive stays canonical
  on-device and is never gated on iCloud; iCloud stays one-way after
  reconciliation; tombstones keep backing up; a failed read is never treated
  as an empty archive; **new** — the ubiquity container never contains the
  five health fields; manual exports remain full-fidelity.

## Considered and rejected

- **A user-facing iCloud toggle** (the dormant `ICloudBackupCopy.notBackedUp` /
  `SettingsCopy.iCloudSync` plumbing): a privacy-UX question, not a compliance
  fix — 5.1.3(ii)’s iCloud clause is unconditional, so the backup must be
  health-free whenever it runs. Decide the toggle separately.
- **Sidecar split** (health data in a separate never-synced file, optionally
  `isExcludedFromBackup`): stronger by construction, but heavier (store
  split/join, migration). Revisit if more health fields accumulate; the
  JSON-keys test in PR A is the cheap guard until then.
- **Re-deriving health data on demand instead of persisting it**: too
  invasive; the watch needs live snapshots at point-commit time and stats
  views would become async and permission-dependent.
- **Dropping the app-managed iCloud backup** in favour of OS device backup
  alone: loses fresh-install restore, which this feature exists to provide.
  (The OS-managed device backup containing app files is not what 5.1.3(ii)
  polices; the app-pushed ubiquity container is.)

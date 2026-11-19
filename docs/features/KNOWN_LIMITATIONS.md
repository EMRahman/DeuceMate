# Known Limitations

Design-bound limitations that are understood, bounded, and deliberately *not*
scheduled — as opposed to bugs (fix now) or the improvement backlog
(`TECHNICAL_DEBT.md`, things worth doing when we get to them). Each entry records
what the limit is, why it exists, why it is safe to live with for now, and the
candidate fixes we have already reasoned about — so a future agent can pick one up
with full context instead of re-deriving it. Captured from a Claude-assisted audit
of the sync/persistence paths.

---

## Summary table

| # | Area | Limitation | Severity | Status |
|---|------|------------|----------|--------|
| 1 | Sync | Large per-point records can delay archive stats | Low for upgraded pairs | Full-record refresh and finalized transfers catch up |
| 2 | Health/Privacy | Pre-match "Health: On" tracking chip can't detect a share-only grant (workout writes allowed, heart-rate reads denied) | Low (uncommon permission combination; strictly better than showing nothing) | Documented, not scheduled |

---

## Detail

### 1 — Long matches can outgrow the per-point archive message

**Remaining limitation.** A long match can exceed the per-message limit for a full
`MatchRecord`. Routine per-point full records are best-effort, so the iPhone's
archive and point detail can lag while the Watch keeps scoring.

The compact live scoreboard travels separately. A refresh or reconnect sends
the full checkpoint reliably, with a file fallback for oversized records. Finalized
matches also fall back to a queued dictionary or file. On an updated pair,
`checkpointRevision` keeps an older unfinished transfer from replacing a newer
score or undo. The compact stats-free record must stay out of archive merging.

See [Live Watch sync](LIVE_WATCH_SYNC_PROPOSAL.md) for the paired-device acceptance
checks and [checkpoint ordering](TECHNICAL_DEBT.md#2--add-a-monotonic-record-revision-before-queued-checkpoints)
for mixed-version behavior.

**Options for the per-point archive feed**
- **Strip stats + receive-side graft (leading option).** When a checkpoint exceeds
  the limit, re-encode it with `stats = []` (the tiny scoreboard fields always fit)
  and mark the payload stats-omitted via a new `MatchSyncKey`. On the phone, graft
  the already-stored stats onto the incoming record before merging. Keeps the live
  feed flowing; accepts a small, self-correcting skew (a late-match undo can leave
  the phone's stats one point ahead until the final record reconciles).
- **`transferFile` per oversized checkpoint.** Fully lossless live stats, but queues
  one file transfer per point for the rest of the match — more WatchConnectivity
  queue pressure and delivery latency on the live path.

### 2 — Pre-match "Health: On" can't detect a share-only HealthKit grant

**What:** The pre-match tracking strip (`MatchTrackingStatus.healthTracking`,
`docs/features/MATCH_START_UX_PLAN.md`) reports Health readiness from
`WorkoutManager.healthAccess`, which is read via
`HKHealthStore.authorizationStatus(for: HKQuantityType.workoutType())` — the
**share** authorization for the workout type. HealthKit deliberately does not expose
**read** authorization for any type, so an app can never ask "will I actually receive
heart-rate samples?" — only "am I allowed to write a workout?".

**Symptom:** A user who grants workout **write** access but denies **heart-rate
read** access sees the Health chip say **"On"**, and the match does get a saved
`HKWorkoutSession` — but per-point heart rate and HR-derived Pulse Coach zones never
arrive, because the *read* grant that would fetch them was declined. The chip is
telling the truth about the only thing it can observe (whether a workout will be
recorded) and cannot see the narrower reason HR specifically will be thin.

**Why it's bounded:** the combination is uncommon — the two permissions are granted
from the same iOS Health-access sheet, and users who bother to grant one typically
grant the other. When it does happen, the strip is still strictly better than showing
nothing: "On" is accurate for the workout/steps/calories that *will* record, just not
maximally precise about heart rate specifically. There is no read-side signal to fall
back to pre-match; the only honest per-match confirmation would be checking after the
first HR sample arrives, which is a live-match affordance, not a pre-match one.

**Candidate fixes (already reasoned about):**
- **Leave as-is (current choice).** The workout-share proxy is the only pre-match
  signal HealthKit exposes. Document the gap rather than build UI around a
  permission state the platform won't report.
- **Live-match fallback indicator.** If no HR sample has arrived N seconds into a
  match with Health "On", surface a one-time in-match notice. Deferred: adds live-UI
  surface for a rare permission combination; revisit if support reports suggest users
  are actually hitting it.

**Status:** Documented, not scheduled. Revisit only if real-world reports show the
share-write/read-deny combination is common enough to justify a live-match indicator.

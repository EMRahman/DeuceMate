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
| 1 | Sync | Live per-point checkpoint has no payload-size guard; long matches freeze the phone's *live* view | Low (live-only; no data loss) | Documented, not scheduled |
| 2 | Health/Privacy | Pre-match "Health: On" tracking chip can't detect a share-only grant (workout writes allowed, heart-rate reads denied) | Low (uncommon permission combination; strictly better than showing nothing) | Documented, not scheduled |

---

## Detail

### 1 — Live checkpoint payload has no size guard (long matches freeze the phone's live view)

**What:** During a match the watch sends a per-point "checkpoint" to the phone so
the phone's live scoreboard, spoken announcements, and iPhone-Input mirror stay
current. On the reachable path this goes over `WCSession.sendMessage`
(`MatchSyncTransport.sendRecord`, `MatchSyncTransport.swift:70-97`). The checkpoint
embeds the whole `MatchRecord`, including its `stats` array — one `PointStat` per
point — so the payload **grows every point**.

**Symptom:** `sendMessage` fails once the message exceeds its ~64 KB ceiling. A
long match (~190–260+ points, i.e. a full three-setter) crosses it, and from that
point on **every** checkpoint fails. The failure handler only logs
(`MatchSyncTransport.swift:90-93`) — there is no fallback — so the phone's live
scoreboard, live announcements, and iPhone-Input mirror all freeze mid-match. It
hits exactly the long, competitive matches people care most about.

**Root cause:** `sendRecord` (the live checkpoint path) has no `data.count` guard,
unlike `sendRecordReliable` (`:102-121`) and `sendHistory` (`:133-147`), which both
check `matchSyncUserInfoSizeLimit` and fall back to `transferFile` for oversized
payloads. Only the live path was never given that guard.

**Why it's bounded (no permanent data loss):** the impact is confined to the
**watch → phone *live* channel**. The watch is the source of truth and is unaffected
— the scorer sees nothing wrong. And **no data is permanently lost**, though with one
subtlety worth stating precisely: the end-of-match send is *not* itself protected.
Finalizing routes through `sendMatch` → `sendRecord` — the same no-fallback
`sendMessage` path as the checkpoints — so an oversized *final* record can also fail
to deliver at match-end. What guarantees the archive still converges is the watch's
**full-history sync** (`sendHistory`, which *does* fall back to `transferFile` above
the size limit): it runs on the next activation / reachability change and carries the
completed match with full stats. So the phone's durable archive catches up on the
**next sync** rather than necessarily at the instant the match ends. This is a
real-time convergence delay, not a stored-data bug — hence "known limitation" rather
than a P0/P1 fix.

**Candidate fixes (already reasoned about):**
- **Strip stats + receive-side graft (leading option).** When a checkpoint exceeds
  the limit, re-encode it with `stats = []` (the tiny scoreboard fields always fit)
  and mark the payload stats-omitted via a new `MatchSyncKey`. On the phone, graft
  the already-stored stats onto the incoming record before merging. Keeps the live
  feed flowing; accepts a small, self-correcting skew (a late-match undo can leave
  the phone's stats one point ahead until the final record reconciles).
- **`transferFile` per oversized checkpoint.** Fully lossless live stats, but queues
  one file transfer per point for the rest of the match — more WatchConnectivity
  queue pressure and delivery latency on the live path.

**Receive-side constraint (mandatory for either fix):** `MatchMergePolicy.resolve`
Case 5 *always accepts* an incoming in-progress record (`MatchMergePolicy.swift:40-45`,
deliberately, for undo checkpoints). So a stats-stripped checkpoint that reached the
merge unflagged would overwrite the phone's stored stats with `[]`. Any fix must
flag the omission on the wire *and* graft on receive, and therefore ship send + receive
in one change. This is closely related to `TECHNICAL_DEBT.md` item 2 (add
`lastModified` to `MatchRecord` — same Case-5 "always accept incoming" area, but for
staleness rather than payload size); revisit them together.

**Status:** Documented, not scheduled. The owner has prioritised persistence/sync
*reliability* work over this live-view *performance/robustness* gap. Pick up via one
of the candidate fixes above when live-view robustness in marathon matches becomes a
priority.

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

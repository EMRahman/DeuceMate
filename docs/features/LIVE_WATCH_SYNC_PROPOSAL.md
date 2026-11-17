# Live Watch sync and courtside iPhone scoring

**Status:** Implemented in the working branch, 16 November 2026; paired-device
validation pending. The owner approved the smaller scope after reviewing the
original proposal. The original durable-receipt/heartbeat design is deferred.

## Product boundary

The player's Watch is the sole live scorer. Another person can use that player's
**paired iPhone** as a courtside remote. Every phone action is applied through the
Watch's existing scoring, categorisation and persistence paths. The iPhone displays
Watch state and keeps no independent scoring engine or offline command queue.
Independent iPhone scoring and another person's phone remain future product work.
Existing manual entry, Sync to Watch, metadata and End at Current Score archive
actions retain their separate semantics.

## Device finding and cause

During [PR #175](https://github.com/EMRahman/DeuceMate/pull/175) testing, the owner
disabled Bluetooth, incremented the score and restored Bluetooth. The phone
reported reachability but did not catch up. The tested build/devices and whether
a subsequent point recovered were not recorded; this does not establish a
regression introduced by #175.

Previously, offline live checkpoints were dropped and reconnect requested only
stored history. The live match intentionally lives outside that history. The
phone nevertheless enabled input as soon as reachability returned. The original
#175 reconnect test scored nothing during the gap, so it missed this case.

## Implemented flow

1. Activation, reconnect, iPhone foreground, opening the live board and Sync Now
   request the Watch's **current live state**. Overlapping requests coalesce.
2. The existing main-thread `ScoreViewModel` answers after restoration. Its pure
   record builder does not save, score, resume, start a workout or announce.
   Unreadable state produces an error; an explicit idle snapshot clears the live
   identity and pending category together.
3. A versioned `liveRequest`/`liveReply` exchange carries a compact scoreboard
   record, pending point/phase, input permission and Watch blockers. Its record
   contains no stats, Health or match metadata and **never enters archive merging**.
   An explicit read also sends the full live record using the reliable/file path,
   so large matches can catch up their archive separately.
4. Normal Watch mutations publish the same compact state. An in-memory Watch
   session UUID and send sequence prevent an older response/push replacing a newer
   live state. They are transport-lifetime ordering, not persisted match revisions.
   Delayed archive records and legacy clear/pending messages do not overwrite a
   scoreboard already following this protocol.
5. The phone shows WAITING FOR WATCH while unreachable, SYNCING WITH WATCH while
   fetching state and SENDING TO WATCH while a confirmed-state command awaits its
   response. Input requires a current-session response, permission and no blocker.
   A push can update the display but cannot complete an outstanding request.
6. A gesture sends a request with the displayed match ID. Categorisation also
   carries the pending context and phase the helper saw. The Watch validates,
   applies through its existing methods, saves and replies with current state or
   a rejection reason. Phase-only categorisation is saved by the shared selection
   and Back methods for both Watch and phone input; optional AppState
   `pendingOutcome` defaults to nil in old files. The phone handler does not
   repeat the save or mask a failed write.
7. Only one phone request is in flight. A ten-second timeout or transport error
   never replays the action: it invalidates that request and makes one read-only
   refresh. Late callbacks cannot unlock input. If refresh fails, input stays
   disabled and Refresh/reopening the board can try again. Backgrounding or
   losing reachability invalidates readiness.

No optimistic score change occurs on the iPhone. Gesture previews/haptics still
mean the gesture was recognised, not that the Watch saved it. Save failures return
an error and block further phone input while the Watch reports the problem.
The browser demo uses the existing Watch engine with simulated request/reply
latency and retains its last received state while disconnected.

Changeover acknowledgement saves and publishes the cleared blocker immediately,
so the phone can resume scoring without another point or refresh. A pending point
can still be categorized or undone while a doubles server decision is waiting;
the existing Watch and phone swipe guards reject new scoring until the pending
point is resolved and the Watch-only decision is complete. Persistence failures
continue to block every remote action, including categorization.

### Watch prompts on the iPhone (17 November 2026)

The Watch screens that pause play — the changeover reminder ("Even games – balls
change ends") and doubles' "Who serves next?" — previously left the phone saying
"Continue on the Watch before scoring." They now travel as a structured
`LiveMatchState.prompt` (`LiveWatchPrompt`), and the phone shows the same card:

- **Same order as the Watch.** The doubles decision is drawn over a changeover
  raised at the same game, so it is offered first on both devices. No prompt is
  sent while a point awaits its category, or during the 0.4 s before a deferred
  changeover appears; when it appears the Watch publishes via
  `liveStateDidChange()` rather than waiting for the next point.
- **Answered through the Watch.** The phone sends `acknowledgeChangeover` or
  `chooseDoublesServer` with the prompt it displayed. The Watch rejects the answer
  unless that same prompt is still open (late tap, other device answered first,
  different match), then calls the same `acknowledgeChangeover()` /
  `resolveDoublesTeamServer(_:)` as its own buttons. Both overlays are bound to
  that state, so they clear together; the save publishes the result.
- **Same gates as scoring.** iPhone Input on, Watch reachable, current state
  confirmed, one request at a time. A prompt answer is the one request allowed
  while the prompt blocks scoring. Spectators see the card without buttons.
- **Mixed versions.** `blockingReason` is still sent, so an older phone shows
  the text. An older Watch sends no prompt, so a newer phone shows the text. A
  prompt kind the phone does not know is shown as text, never answered.

## Deliberately deferred

- **Durable command receipts/deduplication:** a lost response is reconciled by
  fetching state and having the helper check the score. A refreshed score cannot
  always identify which person's action produced it. No exactly-once guarantee,
  automatic resend or restoration of pending phone scoring intent is claimed.
- **Expected scoring revisions/exclusive input:** two distinct valid gestures
  from Watch and phone can both count. One Watch writer serializes them but cannot
  infer that both people meant the same rally. Pending context comparison is not
  a durable point ID.
- **Heartbeat and last-confirmed age:** no polling, expiry timer or time-based
  freshness UI. Reachability loss and lifecycle/read/command responses drive
  recovery. A silently lost update with reachability unchanged can remain stale
  until the next update or explicit/lifecycle refresh.
- **Archive revision counters (#2):** separate existing debt. A queued older
  unfinished record can still revert the phone archive; the dedicated compact
  live board does not read its scoring body from that archive. Tags, type clocks,
  completion precedence, tombstones and Health merge boundaries are unchanged.
- **Mixed versions:** an older Watch's blank reply does not establish readiness.
  New phone remote scoring requires both apps to support this protocol; legacy
  Watch-to-phone archive messages still decode.

## Verification and device acceptance

Core tests cover bounded payloads, wire round trips, unavailable versus idle,
unsupported versions, readiness gates and transport failure without replay.
iPhone tests exercise one request at a time, no optimistic mutation, timeouts,
late callbacks, reconnect/idle, Watch rejection and delayed history. Watch tests
exercise real scoring/saves, phase restoration, unreadable state and failed writes.
Prompt tests cover phone OK/server choice clearing the Watch state, stale and
mismatched answers, input-off refusal, the doubles-before-changeover order, and
publication of the deferred changeover (`LiveMatchWatchTests`,
`LiveCommandDeliveryTests`, `LiveScoreboardStatusTests`, `LiveMatchStateTests`;
browser: `iphone-demo-state-qa.cjs`).
Regression tests also cover changeover acknowledgement publication/persistence,
phone input resuming from that push, and first-game doubles categorization/back/
commit/undo while the next-server decision waits.
Phase persistence regressions cover a phone or Watch selection followed by
Watch-side Back/reselection and relaunch, plus failed phase saves that must not
be acknowledged as successful phone commands.
The browser state suite adds offline Watch scoring followed by reconnect without
another point, and a second gesture while confirmation is pending.

Before release, use a physical paired Watch/iPhone and record build, devices/OS,
latency and results:

- Disconnect, score several points on Watch, reconnect and **score nothing else**.
  The phone must catch up and permit input only after current-state confirmation.
- Repeat with undo, tracking off, perpetual points, pending categorisation and
  park/finish/switching matches during the gap. Verify stale panels clear.
- Score from iPhone: each gesture produces one Watch result. Disconnect during a
  request; it must refresh without replaying. Check rejection guidance when the
  Watch requires a changeover/server decision.
- Dismiss a changeover on the Watch and verify phone input resumes without a
  refresh or another point. With tracking on and opponents serving first in
  doubles, categorize or undo game one's final point from the phone; scoring the
  next point must still wait for the Watch's server choice and any changeover.
- Relaunch/foreground each device and test a long record above the message budget.
  The board must remain current while full archive stats arrive separately.

Native type checking and model tests do not establish real WatchConnectivity
reconnect timing or visual/browser interaction parity. See the release checklist
for the recorded verification and remaining sandbox/device checks.

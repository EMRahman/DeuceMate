# Watch battery review: what drains power during a live match

**Date:** 2026-11-06 · **Scope:** `DeuceMate Watch App/` plus the Core sync transport it calls · **Baseline:** `main` @ `495685a`
**Method:** static code review, plus a scratch benchmark that encodes real `DeuceMateCore` types (`MatchRecord`, `PointStat`, `SetScore`) to measure payload sizes. No on-device Energy Log or Instruments trace was captured, so the energy ranking is an engineering estimate and needs confirming on a physical Watch (see §6).

---

## 1. Summary

During a match, most of the energy goes to the **HealthKit workout session**: the heart-rate sensor runs continuously and the app stays frontmost behind Always-On. That cost is deliberate, because it's what produces the HR, steps and calories data. The workout already uses `locationType = .indoor`, so there is no GPS cost.

The avoidable costs, from largest to smallest:

| # | Finding | Where | Est. impact | Fix effort |
|---|---------|-------|-------------|------------|
| 1 | **The workout session has no end condition.** It keeps running after the match is won, after the match sheet is swiped away mid-match, and restarts on every app launch while an unfinished match exists. | `ScoreViewModel.swift:704-714, 1553`, `HomeView.swift:130-135`, `DeuceMateApp.swift:33-36` | **Very high when it happens.** It keeps the costliest component running for hours after play has stopped. | S–M |
| 2 | **Every save sends the whole match over WatchConnectivity.** `saveState()` runs 2–3 times per point and each run `sendMessage`s the full, growing `MatchRecord`. A categorized point also sends 2–3 pending-point control messages. | `ScoreViewModel.swift:1795-1833`, `MatchSyncTransport.swift:70-97`, `ScoreViewModel.swift:274-303` | **High.** About **7 MB over Bluetooth** for a 150-point match. Each send can wake the iPhone app. Past about 200 points the payload is too big for `sendMessage`, so every later send is wasted (§3.2). | M |
| 3 | **Every save writes the whole match to disk on the main thread.** The full `AppState` is re-encoded and written atomically, then backup exclusion is set and read back, on every `saveState()`. | `ScoreViewModel.swift:1735-1791`, `BackupExcludedFileWriter.swift:16-33` | **Medium–high.** Cost grows with match length (O(n) per save, O(n²) per match). About **16 MB written** for a 150-point match, all on the main thread. | M |
| 4 | **Compass heading runs longer and more often than it needs to.** It restarts on every wrist raise even mid-game, keeps running in Always-On, loses its relaxed filter after each restart, and each heading update re-renders every view observing the view model. | `DeuceMateApp.swift:71-77`, `ScoreViewModel.swift:1599-1646, 2088-2157` | **Medium**, but only when "Check changeover" is on (it's off by default). | S |
| 5 | **No Always-On (luminance-reduced) variant.** No view reads `isLuminanceReduced`. The full-colour scoreboard and a 1 Hz seconds clock are what the wrist shows for most of the match. | `ContentView.swift:279-292, 545-556` (entire scoreboard) | **Medium.** The workout keeps the app on the AOD face for nearly the whole match. | S–M |
| 6 | **Each reachability change re-sends the whole history.** Every time the phone becomes reachable, the watch decodes all of history (up to 25 matches, about 1.1 MB) and re-sends it as a file. There is no debounce. | `WatchMatchSyncService.swift:132-138, 221-224, 85-92` | **Low–medium.** Depends on how often reachability flaps during play. | S |
| 7 | **Swipe vibration plays a multi-pulse haptic and a tone on every point.** Reported by the owner. The code is one call per input with no loop, so this should be small. Measure it (§3.7). | `ScoreInputHaptics.swift:29-47`, `ContentView.swift:107-127` | **Low by code inspection.** Not yet measured. | XS |

**Bottom line:** the biggest leak is #1 (a workout session nobody ends). The biggest steady per-point cost is #2 combined with #3: every point re-encodes, rewrites and re-transmits the entire match, so the cost per point keeps rising as the match goes on.

---

## 2. Baseline: what a match costs by design

| Component | Behaviour | Verdict |
|-----------|-----------|---------|
| `HKWorkoutSession` (`.tennis`, `.indoor`) | Continuous optical HR, motion, energy and steps. Keeps the app running and frontmost, so it is the AOD face. | Intended. `.indoor` avoids GPS, which is the right call (`WorkoutManager.swift:94`). |
| `HKLiveWorkoutBuilder` delegate | HR is published to the UI at most every 2 s and kcal at most every 5 s (`WorkoutManager.swift:22-23`). | Good. Throttled. |
| `HeartRateBadgeView` | Observes `WorkoutManager` directly, so HR ticks do not invalidate the large view model (`ContentView.swift:637-643`). The view model only forwards `$healthAccess` (`ScoreViewModel.swift:680-691`). | Good. Isolated. |
| Animations | Short, one-shot point flash and transitions. No `repeatForever`, no `Timer`s. The walkthrough tasks pause when the app is inactive. | Fine. |
| `PointCategorySheetPrewarm` | A 0×0, invisible static view. | Negligible. |

---

## 3. Findings in detail

### 3.1 The workout session has no end condition (biggest leak)

The workout starts at "Warm Up Complete" (`HomeView.swift:79`), or immediately for tiebreak-only formats (`HomeView.swift:127`). It stops in only two places:

- `clearMatch` → `workoutManager.stopWorkout()` (`ScoreViewModel.swift:1553`), which runs only when the user taps **End Match** or parks/resets the match.
- `RootModal.onDisappear`, only when **no server was ever chosen** (`HomeView.swift:130-135`).

So:

1. **After the winning point the workout keeps running.** `ContentView` shows "You Won! / End Match", but nothing ends or pauses the session (`ContentView.swift:237-275`). If the user drops their arm and walks off, the HR sensor and the frontmost AOD scoreboard keep running until they come back and tap End Match.
2. **Swiping away the match sheet mid-match keeps the workout running** (`currentServer != nil`, so `onDisappear` doesn't stop it). The workout session also keeps the app alive in the background, so nothing reclaims it.
3. **Every launch restarts the workout while an unfinished match exists.** `resumeWorkoutIfMatchInProgress()` (`ScoreViewModel.swift:711-714`) runs after the HealthKit authorization callback on **every** launch (`DeuceMateApp.swift:33-36`). It is guarded only by `sessionStartTime != nil && !isMatchComplete()`. If someone opens the app days later just to check history, a new workout starts and runs until they end that old match.

In each case the most expensive component runs for open-ended stretches when nobody is playing, which costs far more than any per-point inefficiency.

**Recommendations**

- On match completion, `pause()` the `HKWorkoutSession` instead of ending it, so an undo of the winning point can `resume()` it. Then end it automatically after a grace period (for example 10 minutes), or on End Match, whichever comes first. The completion time is already captured in `matchCompletionTime`. This change needs a Watch test, and must respect the "park/finalize must succeed first" rule in CLAUDE.md §6.
- Add an inactivity guard: if no point has been scored for N minutes (for example 20), pause the workout. If that lasts longer (for example 45 minutes), offer to park the match. Resume on the next score.
- In `resumeWorkoutIfMatchInProgress`, only resume automatically if the last saved checkpoint (`AppState.clockSavedAt`) is recent, for example under 30 minutes old. Otherwise wait until the user opens the match.
- Optional: stop the workout in `RootModal.onDisappear` when the match is unfinished and the app goes to the background. Doing this unconditionally would break the deliberate "keep scoring while the screen is off" behaviour, so treat it as a product decision.

### 3.2 Each save sends the full match record over WatchConnectivity

`saveState()` builds a full `MatchRecord` checkpoint, including **every `PointStat` so far**, and calls `sync.sendMatch` (`ScoreViewModel.swift:1795-1833`). When the phone is reachable, `MatchSyncTransport.sendRecord` encodes it and calls `sendMessage` (`MatchSyncTransport.swift:70-97`).

`saveState()` runs on:

| Trigger | Line |
|---------|------|
| `winPoint` / `losePoint` | `ScoreViewModel.swift:1010`, `1070` |
| `commitPointStat` (each categorized point, a **second** save for the same point) | `1295` |
| `toggleSecondServe` (double-tap) | `1312` |
| `undo` | `2047` |
| scene → background | `DeuceMateApp.swift:73` |

Point categorization also sends control messages from the `didSet` observers on `pendingStatPoint` and `pendingOutcome` (`ScoreViewModel.swift:274-303` → `WatchMatchSyncService.swift:179-195`). That's 2 messages per point (set, then clear), or 3 with ending-shot tracking. Each one JSON-encodes a `PendingPointInfo` and calls `sendMessage`.

**Measured payload sizes** (scratch benchmark using the real Core types, with each point carrying HR, steps, score snapshot and ending shot; encoded with `JSONEncoder` on an Apple Silicon Mac):

| Points | Checkpoint `MatchRecord` | `AppState` on disk (≈) | Encode time per save (record + state), Mac |
|-------:|-------------------------:|------------------:|------------------------------------:|
| 50 | 16 KB | 35 KB | 1.2 ms |
| 100 | 31 KB | 74 KB | 2.3 ms |
| 150 | 46 KB | 117 KB | 3.6 ms |
| 200 | **61 KB** | 165 KB | 5.0 ms |
| 250 | **76 KB** | 213 KB | 6.3 ms |

- In a 150-point categorized match (about 2 saves per point), the watch sends **about 7 MB** of checkpoint data over Bluetooth, and the cost per point grows linearly as the match goes on.
- Each `sendMessage` from the Watch can **wake the iPhone app in the background**, so the phone pays a cost too.
- **There's also a correctness bug.** `sendMessage` rejects payloads above about 64 KB (`WCErrorCodePayloadTooLarge`). Around 200 points, the record plus its envelope crosses that limit. **From then on every checkpoint fails**: the watch still encodes it and attempts the send, but the error handler only logs and re-queues the announcement (`MatchSyncTransport.swift:90-93`). In long three-set matches, the phone's live view and archive checkpoint quietly stop updating until the match is finalized. Verify the exact threshold on a device.
- Per the owner's memory notes, the live mirror and announcements aren't actually used. Most of this traffic exists to support them.

**Recommendations**

- **Split the fast live-score update from the durable checkpoint.** Per point, send a small live delta: score, server, last point and match ID. That's under 1 KB. Send the full `MatchRecord` only at game end, every N points, on scene → background, and at finalize. Use `MatchSyncPayloadBuilder` for the new payload (CLAUDE.md §4).
- Or, for checkpoint state where only the latest value matters, use `updateApplicationContext`. The system merges pending updates and delivers when convenient instead of waking the phone for each one.
- Skip the per-point send entirely when nothing on the phone uses it. For example, the phone can tell the watch when the live scoreboard is open, or the watch can stop sending when both iPhone Input and announcements are off.
- Coalesce the 2–3 pending-point messages per point. They aren't queued anyway, so dropping intermediate ones is harmless.
- Guard against the size limit: if the encoded record is larger than about 60 KB, don't call `sendMessage`. Send the delta instead and leave the full record to the queued or file path.

**Make per-point traffic automatic rather than a new setting (decision note, 2026-11-06).** Who consumes per-point traffic, and whether the Watch already knows they're in use:

| Consumer | Needs per-point updates? | Watch already knows? |
|----------|-------------------------|----------------------|
| iPhone live scoreboard | Yes | **No** |
| iPhone Input | Yes, plus pending-point messages | Yes (`iPhoneInputEnabled`, default off) |
| Spoken announcements | Yes | Yes (`phoneAnnouncementsEnabled`, default off) |
| Phone's checkpoint of the match in progress | No. Game or set boundaries are enough; finalize and the reconnect history push still deliver the full match. | n/a |

Recommended design: **send per point only when iPhone Input or announcements are on, or a live viewer is active.** Otherwise send a checkpoint at game and set boundaries, on background, and at finalize.

- The phone sends a "live viewer active" control message when `LiveScoreboardView` appears and again when it disappears. The message should expire on its own after a few minutes and be renewed while the view stays open, so a crashed phone app can't leave it on. When the Watch receives it, it replies at once with the current full checkpoint.
- **A user-facing "Live updates to iPhone" toggle was considered and rejected**:
  - Users can't judge when to turn it off.
  - With it off, the live scoreboard silently looks frozen.
  - It would add another magic-string synced setting (CLAUDE.md §5) with copy on both apps plus browser-demo parity.
- In the owner's usual setup (no live view, no announcements), a 150-point match drops from about 300 full-record sends to about 25.
- This only helps when the phone is in range: when it isn't, in-progress checkpoints are already dropped. It doesn't affect the per-save disk cost (#3).

### 3.3 Each save re-encodes and rewrites the whole state on the main thread

The same 2–3 saves per point each do the following, synchronously on the **main thread** (`ScoreViewModel.swift:1735-1791`):

1. Build `AppState`, which includes `history: [HistoryEntry]`. **Each `HistoryEntry` stores its own copy of the whole `sets` array** (`ScoreViewModel.swift:374-398`). It also includes `currentMatchStats`, which repeats the data in the checkpoint record.
2. `JSONEncoder().encode` the full state.
3. `Data.write(.atomic, .completeFileProtectionUntilFirstUserAuthentication)`, which writes a temp file and renames it, rewriting the entire file.
4. Call `setResourceValues(isExcludedFromBackup)` and then **read it back** (`BackupExcludedFileWriter.swift:16-33`). That's two more filesystem metadata calls per save.
5. Then encode the checkpoint `MatchRecord` again for the sync send (§3.2).

The state is about 117 KB at 150 points, so a 150-point match writes **about 16 MB** of flash. On a Mac each save takes about 3.6 ms of encoding. A Watch is several times slower (a reasonable guess is 5–10×, which needs confirming on a device), so late in a match the main thread could be busy for tens of milliseconds on every swipe. That costs CPU energy and can cause dropped frames right when the point flash animates.

**Recommendations** (in-progress checkpoints only; never weaken the durable park/finalize path)

- **Coalesce the saves within a point.** `winPoint` followed by `commitPointStat` happens within a few seconds. Debounce in-progress `saveState()` writes by about 0.5–1 s, and flush immediately on scene → inactive/background, on finalize/park, and on undo of a winning point. Tradeoff: a crash within that window loses the last point. Decide explicitly whether that's acceptable.
- **Do the encode and write off the main thread.** Snapshot the value-type `AppState` on main, then encode and write it on a serial utility queue. `StatsStore` already uses a serial queue.
- **Exclude the directory from backup once, rather than the file on every write.** Or check the flag only after the file is first created. That removes two syscalls per save. Keep a test that proves the exclusion still holds.
- **Shrink `HistoryEntry`**: store `sets` only when it changes (at game boundaries), or store just the per-point delta. `HistoryEntry` is only used for undo. This needs the §4 backward-compat recipe for `AppState` decoding.

### 3.4 Compass heading runs longer and more often than needed (only with "Check changeover" on)

Heading monitoring is meant to run only at the start of a game (`syncHeadingMonitoring`, `ScoreViewModel.swift:1632-1646`). That window already includes the whole 90-second changeover and every gap between games. Four problems make it worse:

1. **It restarts on every wrist raise, mid-game too.** `DeuceMateApp.swift:75-76` calls `startHeadingMonitoring()` on every transition to `.active`. That includes inactive → active, which happens on each wrist raise while the workout keeps the app frontmost, and it doesn't check `isAtGameStart`. The magnetometer then runs until the next point is scored.
2. **It isn't paused in Always-On.** Only `.background` pauses it (`DeuceMateApp.swift:72-74`). With the wrist down at a changeover, heading keeps streaming to a dimmed screen where nobody reads the compass.
3. **Each restart loses the locked state.** `pauseHeadingMonitoring()` sets `headingManager = nil` (`ScoreViewModel.swift:1624-1627`), and the next `startHeadingMonitoring()` creates a fresh `HeadingManager` with `isLocked = false` (`ScoreViewModel.swift:2093`). So after the first game, every restart uses the **10° precise filter** instead of 20° (about twice the update rate) and allows the **calibration popup** again, even though the comment above `ScoreViewModel.swift:2154` says it should be suppressed once the bearing is locked. This is also a UX bug.
4. **Every heading update invalidates the whole view tree.** `currentDeviceHeading` and `currentHeadingAccuracy` are `@Published` on the roughly 2,000-line `ScoreViewModel` (`ScoreViewModel.swift:271-272`). So every update re-renders `RootView`, `HomeView`, `RootModal`, `ContentView` and any `TrackingStatusStrip`. Wrist movement easily causes several 10° changes per second.

**Recommendations**

- Replace the unconditional `startHeadingMonitoring()` on `.active` with `syncHeadingMonitoring()`. Pause on `.inactive` as well as `.background`.
- Keep a single `HeadingManager` for the match and call `stop()`/`start()` on it, or carry `isLocked` across restarts once `courtInitialHeading != nil`.
- Move the heading values into a small dedicated `ObservableObject` (like `HeartRateBadgeView` does for HR), so only `CompassBadgeView` redraws. Also consider snapping to 15° before publishing. The badge only needs green, orange or red.

### 3.5 No Always-On (luminance-reduced) rendering

A search for `isLuminanceReduced` in the watch target finds nothing. Because the workout keeps DeuceMate frontmost, **the scoreboard is what Always-On shows for almost the whole match**: the wrist is down between nearly every point. Right now that means:

- Full-colour row fills and strokes (`palette.meRow` / `opponentRow`), the court graphic, the momentum strip and the server glow `.shadow`, all dimmed by the system but still lit OLED pixels.
- A `TimelineView(.periodic(by: 1))` footer showing **seconds** (`ContentView.swift:279-292`, `formatDuration` at `545-556`). watchOS throttles AOD refreshes, so a seconds counter can't show accurate values there anyway. It only creates redraw work and an incorrect display.

**Recommendations**

- Read `@Environment(\.isLuminanceReduced)` in `ContentView`. When it's true, drop the row fills, strokes and shadows, keep the score digits and a dim server marker, and hide the HR/kcal/compass badges.
- Switch the footer to `.everyMinute` and a format without seconds when luminance is reduced, as Apple's Workout app does.
- This is view-only and safe. Mirror it in the browser demo per the Phase 7 parity rule (CLAUDE.md §2) only if the demo simulates AOD, which it currently doesn't.

### 3.6 Full-history push on every reachability change

`sessionReachabilityDidChange` calls `pushFullHistory()` whenever the phone becomes reachable (`WatchMatchSyncService.swift:221-224`). That one call:

- decodes the whole `matchHistory.json` (up to `WatchHistory.cap` = 25 matches; 25 matches of 150 points is about **1.1 MB** of JSON),
- re-encodes it and, because it's over 64 KB, writes a temp file and calls `transferFile` (`MatchSyncTransport.swift:133-150`),
- then `sendManifest()` decodes the whole history file **again** just to read the IDs (`WatchMatchSyncService.swift:85-92`).

Reachability can flap during play: a phone in a bag at the edge of Bluetooth range, a Wi-Fi handoff, or the iPhone app being woken and suspended. Each flap repeats all of this, and the phone already has every completed match unless something changed.

**Recommendations**

- Debounce reachability-triggered pushes (for example at most once per 10 minutes), and skip them while a match is live. The phone's manifest/request path can ask when it actually needs a refresh.
- Keep an in-memory ID manifest so `sendManifest()` doesn't decode the whole file each time.
- Better still, push only the records the phone's last manifest doesn't already have.

### 3.7 Swipe vibration ("Vibrate on swipe") — reported by the owner, follow-up 2026-11-06

**Observation:** the owner noticed more battery drain with the swipe-vibration option on, and that it also plays a sound.

**What the code does** (`ScoreInputHaptics.swift`, called from `ContentView.performInput`, `ContentView.swift:107-127`):

- It plays one `WKInterfaceDevice.current().play(_:)` **per applied on-watch input**: `.directionUp` for a won point, `.directionDown` for a lost point, `.click` for undo. Nothing plays for the stats swipe, for iPhone score commands, or for categorization taps.
- There is no loop, timer, retry or repeat. The haptic doesn't touch persistence or sync. The setting itself syncs only when the toggle changes (`HomeView.swift:602-604`), never per point.
- **The sound comes from the same call.** `WKHapticType` patterns are a vibration plus a matching system tone, and the tone is muted only when the Watch is in Silent Mode. The app has no separate sound option, and `WKInterfaceDevice` can't play the vibration without the tone. That's why the "vibration" option is heard as "vibration and sound".
- `.directionUp` and `.directionDown` are among the longer patterns (several pulses plus a rising or falling tone). `.click` is the lightest.

**How big can it be?** A match has roughly 120–250 inputs, so the Taptic Engine and speaker amp are active for perhaps one to three minutes in total, spread across the match. Compare that with 60–120 minutes of continuous heart-rate sensing and an always-frontmost screen. Based on the code, this setting should be a **small, roughly linear-per-point cost**, well below findings #1–#3. Nothing in the code would make it grow over time or keep anything running between points.

So the code doesn't explain a large drain. If the difference is clearly bigger than a few percent per hour, the likely explanations are:

1. **Confounding between test sessions.** Match length, the phone being in range (finding #2), the compass setting (#4), and a forgotten workout (#1) all change between sessions and matter more.
2. **The audio path costs more than expected.** Powering the speaker amp up and down for every point may cost more than the vibration itself. Silent Mode separates the two (see the test below).
3. **Something specific to the device** that only a measurement can show.

**Recommendations**

- **Measure before changing anything.** Run the same scripted match length with the phone in the same state and the compass off, in four combinations: haptics off; haptics on with Silent Mode on (vibration only); haptics on with Silent Mode off (vibration and tone). Record the battery percentage before and after each, or use Energy Impact in Xcode.
- **Cheap reduction whatever the result:** use `.click` (a single tap with a short tick) for both win and lose, or a different short pattern for each direction, instead of the multi-pulse `.directionUp`/`.directionDown`. You'd lose the "up versus down" feel, so it's a UX tradeoff. Update `ScoreInputHapticsTests` if the mapping changes; it pins the current patterns.
- **Say that it makes a sound.** The toggle's blurb, `SettingsCopy.swipeVibration`, currently reads "Taps your wrist when a swipe scores or undoes a point." Update it on both apps to mention that it also plays a tone unless the Watch is in Silent Mode, so users aren't surprised.

---

## 4. Suggested order of work

1. **#1 workout lifetime.** Pause on completion with an auto-end grace period, an inactivity guard, and a stale-checkpoint check before auto-resuming on launch. This has the biggest real-world effect.
2. **#4 heading fixes.** These are small, contained edits (and fix the calibration-popup UX bug).
3. **#5 AOD variant.** View-only and low risk.
4. **#2 + #3 together.** Introduce a small live delta for per-point sync and send the full checkpoint only at game end, debounce and move the state write off the main thread, and fix the over-64 KB `sendMessage` failure. These touch sync and persistence invariants, so they need tests in `DeuceMateCoreTests` (payload builder round-trip) and Watch tests (save coalescing and flush on scene change).
5. **#6** reachability debounce and manifest cache.

Each item that changes logic needs tests (CONTRIBUTING.md), and #2/#3 should be checked against `docs/architecture/sync-and-data-flow.md` and `match-lifecycle.md`.

---

## 5. Checked and found fine

- No GPS: `locationType = .indoor`.
- No `Timer`, `CADisplayLink` or repeating animations in the live UI.
- HR and kcal publishing are throttled (2 s and 5 s); the HR badge observes `WorkoutManager` on its own.
- The view model forwards only `healthAccess` from `WorkoutManager`, not every HR tick.
- `HealthAccessSettlePolicy` retries are bounded.
- Walkthrough animation tasks are cancelled or paused when the app is inactive.
- History writes (`StatsStore`) happen only at park and finalize, not per point.

---

## 6. How to confirm on a device

1. **Xcode → Debug Navigator → Energy Impact** on a paired Watch during a scripted 150-point match: compare CPU and "Overhead" before and after #2/#3.
2. **Instruments → Activity Monitor / Time Profiler** on the Watch. Look for `JSONEncoder` and `BackupExcludedFileWriter.write` under `saveState` on the main thread late in the match.
3. **Instruments → Network / os_signpost** around `sendRecord`. Count `sendRecord failed` log lines (subsystem `com.deucemate.sync`) after about 200 points to confirm the oversized-payload failure.
4. **Battery A/B test:** two 60-minute sessions on the same Watch at the same starting charge, with "Check changeover" on and off, and with the phone reachable and unreachable (Airplane Mode on the phone).
5. **Forgotten-session test:** win a match and leave the Watch for 30 minutes without tapping End Match. Confirm in Fitness that the workout is still recording, then repeat after fix #1.

### Benchmark reproduction

The measurements in §3.2 came from a throwaway SwiftPM executable that depended on `Packages/DeuceMateCore` by path and encoded `MatchRecord`s with N `PointStat`s. Each point had outcome, ending shot, `GameScoreSnapshot`, HR and steps, plus a local mirror of the watch's `HistoryEntry`. It wasn't committed. Rebuild it in a temporary directory if you need fresh numbers. Sizes depend on the field set, not the hardware, but encode times are Mac numbers and only show the trend.

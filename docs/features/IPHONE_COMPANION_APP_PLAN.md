# Plan: iPhone Companion App (Sync + Past Matches)

## Context

Today DeuceMate is a standalone watchOS app (`ehsan.DeuceMate.watchkitapp`).
Match history is persisted as JSON in the watch's Documents directory by
`StatsStore` and surfaced via `MatchHistoryView` / `MatchStatsView`. There is
no iPhone target.

This plan introduces a **read-only iPhone companion app** whose v1 purpose is:

1. **Sync** completed and in-progress match records from the paired Apple
   Watch.
2. **Save** those records on the phone so they outlive the watch's
   `StatsStore.historyCap` (currently 25).
3. **Display** match history and per-match statistics with **parity** to the
   watch's `MatchStatsView`.

Explicit non-goals for v1:

- **No live match tracking on the phone.** No point entry, no point-outcome
  categorization, no score editing, no resume/score-from-iPhone. The watch
  remains the only place a match is scored. The phone never writes to a match's
  point stream.
- No CloudKit / multi-device sync (watch ↔ phone only via WatchConnectivity).
- No new statistics beyond what `MatchStatsView` already computes.

A larger phone-side stats surface ("more statistics … in time") is anticipated
but explicitly deferred — see *Future work*.

---

## High-level architecture

```
┌────────────────────┐     WCSession      ┌────────────────────┐
│  Apple Watch       │ ◀────────────────▶ │  iPhone companion  │
│  (existing)        │   transferUserInfo │  (new)             │
│                    │   transferFile     │                    │
│  StatsStore.json   │                    │  StatsStore.json   │
│  (cap = 25)        │                    │  (cap = ∞ / large) │
└────────────────────┘                    └────────────────────┘
       │                                          │
       └─────────── shared Swift code ────────────┘
                    (DeuceMateCore package)
```

Watch is the **source of truth** for any match it has touched: outcomes are
only ever entered there. The phone is a durable archive + larger-screen
viewer. Conflicts on a given `MatchRecord.id` resolve by **most-recent wins,
watch-as-tiebreaker**: if the watch has a record with the same id and a later
`endTime` (or any change while the watch has it in-progress), the watch
version replaces the phone's.

---

## Project / target changes

### 1. New iOS app target

Add to `DeuceMate.xcodeproj`:

| Item | Value |
|------|-------|
| Target name | `DeuceMate` (iOS app) |
| Bundle ID | `ehsan.DeuceMate` |
| Platform | iOS 16.0+ (matches SwiftUI features used on watch; no need to push lower) |
| Capabilities | none required for v1 (no HealthKit, no push, no iCloud) |
| Embedded Watch App | the existing watch app target is embedded so the pair installs together |

The existing watch target stays an *independent* watch app (it must still
work standalone for users without the phone app installed yet). After embed,
its `WKCompanionAppBundleIdentifier` should be set to `ehsan.DeuceMate`.

### 2. New shared Swift Package: `DeuceMateCore`

Extract the types currently defined in the watch target that the phone also
needs:

- `MatchRecord`
- `PointStat`, `PointOutcome`, `EndingShot`, `GameScoreSnapshot`, `PendingPointInfo`
- `ScoreViewModel.Player`, `.SetScore`, `.MatchType`, `.MatchFormat`,
  `.DoublesServer` — these are referenced by `MatchRecord` so they must move
  too. Either:
  - **(preferred)** lift the nested types out of `ScoreViewModel` into top-level
    types in the package (e.g. `enum Player`, `struct SetScore`), and add
    typealiases inside `ScoreViewModel` so existing watch code compiles
    unchanged, **or**
  - move `ScoreViewModel` itself into the package. Rejected: it pulls in
    `WorkoutManager`, haptics, and watch-only state that the phone has no use
    for.
- `StatsStoring` protocol + the `StatsStore` JSON format. The store
  *implementation* can stay per-target (the file lives in each device's own
  Documents dir), but the encoding/decoding code is shared.

The shared package keeps zero UIKit / WatchKit / SwiftUI dependencies so it
can compile against both `iOS` and `watchOS`.

### 3. Stats view sharing

`MatchStatsView` is SwiftUI and largely platform-neutral, but uses
`watchOS`-sized fonts (size 9–13), no segmented controls, etc. The plan is:

- Move the **derivation logic** out of the view into a pure
  `MatchStatsSummary` value type in `DeuceMateCore` (one initializer:
  `init(stats: [PointStat], focal: Player)` returning all the percent/count
  fields the view currently computes inline).
- The watch view consumes that summary unchanged visually.
- The phone target writes a fresh `MatchStatsView` (iOS) that consumes the
  same summary, with iOS-appropriate typography, a real `Picker` for
  set/player toggles, and `.list` styling. v1 displays **the same fields, in
  the same order**, with no additional metrics.

This guarantees parity-by-construction: a new metric added to the summary
appears on both platforms with one change.

---

## Sync transport: WatchConnectivity

### Why WCSession (not iCloud / shared container)

- Watch and phone live in separate sandboxes — App Groups don't bridge them.
- CloudKit is overkill for v1, requires account state, and is a privacy
  regression (current README/PRIVACY_POLICY emphasize zero data leaves the
  device).
- WCSession is local, requires no account, works offline, and matches the
  privacy posture.

### Session setup

Both apps adopt `WCSessionDelegate` via a small `MatchSyncService` in each
target:

```swift
// In DeuceMateCore
public protocol MatchSyncService {
    func start()
    func sendMatch(_ record: MatchRecord)              // single record
    func sendFullHistory(_ records: [MatchRecord])     // bulk / reconcile
    var lastSyncDate: Date? { get }
}
```

### When the watch sends

The watch pushes on three triggers:

1. **Match completes** (`iWon` becomes non-nil in `ScoreViewModel`) →
   `sendMatch` for that record via `transferUserInfo` (queued; survives the
   watch app being killed; delivered when phone wakes the iOS app in the
   background).
2. **Match parked / state checkpoint** (existing `saveState` flow) → also
   `transferUserInfo` for that one record. Throttle: at most one in-flight
   transfer per match id; coalesce by replacing pending transfer for the same
   id.
3. **History eviction risk** — when a new match would push history over
   `historyCap`, push a `sendFullHistory` *before* the trim happens, so the
   phone receives the about-to-be-evicted record even if it had never been
   delivered. Belt-and-braces; the per-match push above usually covers it.

`transferUserInfo` is preferred over `sendMessage` because it survives both
apps being suspended. Records are encoded as JSON `Data` in the userInfo dict
under a single key (`"match"` for one record, `"matchHistory"` for full).

### When the phone sends

Phone is read-only for match data, so it never pushes records. It does send:

- A **sync handshake** on launch: requests the watch's full history via
  `sendMessage` *if reachable*, falls back to waiting for the next watch
  push otherwise.
- A **"sync now"** user-initiated request from the phone's settings screen,
  same handshake behavior.

### Bulk reconcile via `transferFile`

If full-history payload exceeds the userInfo size limit (~64KB), fall back to `transferFile`. Given the metadata in `PointStat`, this fallback will likely be the primary path for full history syncs, rather than a rare occurrence.

### Reachability + first-launch states

| Watch state | Phone state | Behavior |
|-------------|-------------|----------|
| Reachable | Foreground | Live sync via sendMessage if user taps "Sync now" |
| Not reachable / paired but asleep | Any | Watch queues transferUserInfo; iOS launches in background to receive |
| Phone app never opened | — | Watch queues; nothing delivers until first phone launch, which is fine |
| Watch app never opened since pair | App opens | Phone shows "No matches synced yet" |

---

## Data model: persistence on iPhone

Reuse the JSON file scheme used on the watch to keep the formats identical.
On iOS:

- File: `<Documents>/matchHistory.json`
- Encoding: `JSONEncoder` (default, same as watch)
- File protection: `.completeFileProtection` (same as watch)
- Concurrency: same serial-queue pattern as watch's `StatsStore`

**No `historyCap` on the phone in v1.** Phone keeps everything it ever
received. (When this list grows large enough that pagination matters, that's
a v2 problem.)

### Merge / dedupe rules

When the phone receives a record:

1. Look up existing record by `id`.
2. If absent → insert.
3. If present:
   - If incoming has `iWon != nil` and existing has `iWon == nil` → replace
     (in-progress → completed transition).
   - If both have `iWon != nil` → keep newer `endTime`.
   - If both are in-progress → keep the one with more points
     (`stats.count` greater) as a heuristic; tiebreak on `startTime` newer.
4. Sort by `startTime` descending, persist.

A unit test matrix in `DeuceMateCore` covers each case; this logic is the
likeliest place for subtle bugs.

---

## iPhone UI (v1)

### Information architecture

Tab-less single root for v1; `NavigationStack` with three screens:

1. **Past Matches** (root) — equivalent to watch's `MatchHistoryView`.
   - List of `MatchRecord`s newest first.
   - Row content (parity with watch): date, result label (`Won 6-3, 6-4` /
     `In Progress` / etc.), badge for `Match Stats` vs `Score Only`.
   - Swipe-to-delete on iOS; deletes locally only. The phone should maintain a "tombstone" list of deleted match IDs to prevent them from being re-imported during bulk syncs.
   - Pull-to-refresh triggers a sync handshake with the watch.
2. **Match Detail** — push from a row.
   - Header: same title logic as watch (`title(for:)`), plus full date.
   - Score line, set duration rows, Me/Opp toggle, Set filter — **same
     fields, same order** as `MatchStatsView`.
   - **No "Resume this match" button on the phone.** Resume is a watch-only
     concept in v1; we never want the phone to look like it can score.
3. **Settings** — sheet from a toolbar gear.
   - Sync status: "Last synced X ago", phone↔watch reachability indicator.
   - "Sync now" button.
   - "About" / version.
   - **Nothing scoring-related.**

### Visual parity vs platform-appropriate

Parity = same metrics, same labels, same numerical formatting. Not pixel
parity — the iPhone gets:

- Native `List` styling (`.insetGrouped`).
- `Picker(.segmented)` for Me/Opp and set filters.
- iOS-typical font sizes (the watch's 9–13pt is illegible on iPhone).
- Larger color swatches for outcome categories.

### Empty / error states

- No matches synced yet → friendly empty state with watch icon and "Open
  DeuceMate on your watch and play a match — it'll show up here."
- Watch not paired → "No paired Apple Watch detected. Pair an Apple Watch
  with DeuceMate installed."
- Sync failed (transferUserInfo never arrived) → still show whatever's
  cached locally; surface "Last sync X ago" in Settings.

---

## Files to add / modify

### New (iPhone target: `DeuceMate/`)

| File | Purpose |
|------|---------|
| `DeuceMateApp.swift` | `@main` entry, sets up `MatchSyncService` |
| `Views/PastMatchesView.swift` | Phone equivalent of `MatchHistoryView` |
| `Views/MatchDetailView.swift` | Phone equivalent of `MatchStatsView` |
| `Views/SettingsView.swift` | Sync status + "Sync now" |
| `Sync/PhoneMatchSyncService.swift` | `WCSessionDelegate` for iOS |
| `Persistence/PhoneStatsStore.swift` | `StatsStoring` impl on iOS (no cap) |
| `Info.plist` | minimal; no special keys for v1 |
| `DeuceMate.entitlements` | empty in v1 |

### New (shared package: `Packages/DeuceMateCore/Sources/DeuceMateCore/`)

| File | Purpose |
|------|---------|
| `Models/MatchRecord.swift` | Moved from watch target |
| `Models/PointStat.swift` | Moved from watch target |
| `Models/ScoreTypes.swift` | Lifted nested types from `ScoreViewModel` |
| `Stats/MatchStatsSummary.swift` | Pure derivation extracted from `MatchStatsView` |
| `Sync/MatchSyncMessage.swift` | Wire format constants + `Codable` envelope |
| `Sync/MatchMergePolicy.swift` | Dedupe / merge rules |
| `Persistence/StatsStoring.swift` | Protocol + JSON helpers |

### Modified

| File | Change |
|------|--------|
| `DeuceMate Watch App/MatchStats.swift` | Replace nested-type definitions with `import DeuceMateCore` and typealiases on `ScoreViewModel`; or keep the typealiases inside `ScoreViewModel` and let the underlying types live in the package |
| `DeuceMate Watch App/StatsStore.swift` | Adopt the package's `StatsStoring` protocol; implementation stays watch-side for the file location |
| `DeuceMate Watch App/MatchStatsView.swift` | Replace inline derivations with `MatchStatsSummary` calls; visuals unchanged |
| `DeuceMate Watch App/ScoreViewModel.swift` | Hook a new `WatchMatchSyncService.send(record:)` call into the existing match-completion and `saveState` paths |
| `DeuceMate.xcodeproj/project.pbxproj` | Add iOS app target, add Swift Package, add `WCSession` capability, embed watch app inside iOS app |
| `PRIVACY_POLICY.md` | Add: "Match data may be transmitted between your iPhone and Apple Watch via Apple's WatchConnectivity framework. No data leaves your devices or is sent to any server." |
| `APP_STORE_METADATA.md` | Update product description: "Now with iPhone companion to keep your match history forever." |
| `README.md` | Update platform badge + features section |

---

## Test plan

### Unit tests (in `DeuceMateCore` test target — runs on macOS, no watch needed)

1. **`MatchStatsSummary` parity**: snapshot a representative `MatchRecord`
   (singles, doubles, super-tiebreak, score-only-no-stats) and assert every
   field the current `MatchStatsView` displays equals the summary's
   computed value. This locks parity before any UI is forked.
2. **`MatchMergePolicy`** matrix:
   - new id → insert
   - existing in-progress + incoming completed → replace
   - existing completed + incoming completed-newer → replace
   - existing completed + incoming completed-older → keep
   - both in-progress, more points wins
   - both in-progress, same points, newer startTime wins
3. **JSON round-trip**: `MatchRecord` written by current watch code is
   decoded losslessly by the new package decoder (catches accidental
   coding-key changes during the move).

### Watch tests (existing target)

- Existing `ScoreViewModel` tests must pass unchanged. The type aliasing in
  the move-to-package step is the risky part; a green test suite is the
  signal it landed cleanly.

### iOS tests (new target)

- `PhoneStatsStore` round-trips through the same `matchHistory.json` format.
- `PhoneMatchSyncService` consumes a fixture userInfo dict and produces the
  expected merged history.

### End-to-end manual checklist

1. Install both apps on a paired watch + phone.
2. With phone app **closed**, play a match on the watch to completion.
3. Open phone app → match appears within seconds (transferUserInfo wakes
   iOS in the background; on first launch it'll arrive on launch).
4. Play a second match while phone app is **foregrounded** → match appears
   live without needing pull-to-refresh.
5. Park a match (start a new one without finishing) → in-progress record
   appears on phone with "In Progress" label and **no resume button**.
6. Resume that match on the watch and finish it → phone's row updates to
   the completed score (same `id`, merge policy upgrades it).
7. Play 26 matches on the watch; the watch evicts the oldest (cap = 25);
   confirm the phone still shows all 26.
8. Delete a row on the phone; play a new match on the watch; the deleted
   record does **not** come back (deletion is local-only, but the watch
   never re-pushes a record it didn't change).
9. Toggle airplane mode on phone, finish a match, re-enable airplane mode
   off → match arrives on phone (queued transferUserInfo).
10. Open Settings → "Sync now" forces a full reconcile; "Last synced" stamp
    updates.
11. Open phone app with no paired watch → empty state explains the
    requirement; no crashes.
12. Verify privacy policy text is reachable from the phone Settings screen
    and accurately describes WatchConnectivity usage.

---

## Rollout

1. **PR 1 — Extract `DeuceMateCore` package.** Watch target imports it.
   Watch tests + UI unchanged. No iOS target yet. Lowest risk; highest
   leverage. Ship and verify the watch app is still byte-identical from a
   user perspective.
2. **PR 2 — Add iOS target, no sync.** Phone reads from an empty
   `matchHistory.json` and shows the empty state. Past Matches and Match
   Detail views render against fixture data behind a debug menu so design
   iteration doesn't depend on sync working.
3. **PR 3 — Watch → phone sync.** Wire `WCSession` both sides. Manual
   end-to-end checklist above is the gate.
4. **PR 4 — Settings + "Sync now" + privacy policy update.** Polish.
5. **PR 5 — App Store submission.** Update screenshots, metadata, support
   page; phone app ships as a free companion bundled with the watch app.

Each PR is independently revertible without breaking the watch app on
production.

---

## Future work (explicitly deferred)

These are *not* in v1 but the architecture above leaves room for them:

- **Phone-only stats** — career-level rollups across matches: serve % over
  time, W:UE trend lines, opponent-specific records. Add fields to
  `MatchStatsSummary` or a new `CareerStatsSummary` and surface a third
  screen on iOS.
- **CSV / share-sheet export** of a single match or full history.
- **iCloud backup** so users can restore on a new phone without replaying
  the watch sync. Optional; off by default to preserve the privacy posture.
- **Match notes** entered on the phone (post-match reflection text). Would
  require relaxing "phone is read-only," but only on a new field that the
  watch never owns, so it's safe.
- **Larger watch cap** once the phone reliably archives — e.g. drop the
  watch's `historyCap` (currently 25) to a smaller number to save watch
  storage, since the phone is now the long-term archive.
- **Live match mirroring** — phone shows current score in real time during
  a match. Read-only; no input. Deliberately deferred because it changes
  the framing of the phone app from "archive" to "second screen" and
  deserves its own design pass.

---

## Open questions

1. **Bundle ID change for the watch app.** Today the watch target's bundle
   ID is `ehsan.DeuceMate.watchkitapp`, which is fine for an embedded watch
   app. Confirm whether the existing App Store listing was submitted as
   independent or embedded; if independent, embedding it inside an iOS app
   may require a new App Store record. Investigate before PR 1.
2. **Minimum iOS version.** Proposed iOS 16. Confirm against watch's
   minimum (watchOS 9) — both shipped together, so iOS 16 is the natural
   pair. No reason to push lower for v1.
3. **Privacy policy wording.** Apple's review may want explicit mention
   that WatchConnectivity is on-device peer-to-peer and not a network
   transmission. Draft language with reviewer in mind in PR 4.

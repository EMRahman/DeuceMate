# Principal-Engineer Audit — DeuceMate (2026-07-04)

Single-pass audit. Scope: persistence, sync, live-match hot paths on both targets +
Core. Static analysis only (no Swift toolchain in this environment — nothing was
built or run). Each item was written to be independently shippable as its own PR per
`CONTRIBUTING.md` (one concern per PR, logic change ⇒ Core tests).

> **Disposition (as of 2026-07).** Most of this audit has since been actioned; it is
> kept here as the historical record of the review. The findings below are preserved
> verbatim as originally written.
> - **P0 #1 (watch `StatsStore` treats a failed read as empty)** — **Done.** The
>   loader now distinguishes absent (`[]`) from unreadable/corrupt (`nil`), and the
>   write/broadcast paths bail on `nil`. Covered by `StatsStoreTests`.
> - **P0 #2 (Class A file protection on watch stores)** — **Done.** Both watch
>   writers moved to `.completeFileProtectionUntilFirstUserAuthentication`, which
>   un-parked `docs/features/TECHNICAL_DEBT.md` #4b (see its "Residual gap" note).
> - **P1 #3 (live-checkpoint payload size guard)** — **Deferred, documented** as a
>   design-bound limitation in `docs/features/KNOWN_LIMITATIONS.md` #1 (not fixed —
>   reliability was prioritised over the live-view robustness gap).
> - **P2 #4 & #5 (performance: synchronous disk I/O, duplicate history syncs)** —
>   **Not done, deferred by choice** (reliability over performance).
> - **P3 hygiene** — the history-cap doc-rot is **fixed** (comments now cite
>   `WatchHistory.cap`); the settings-key and `MatchRecord`/`PointStat` decoding
>   audits confirmed no action needed.

---

## P0 — data loss

### 1. Watch `StatsStore` treats a failed read as an empty archive, then persists the emptiness
- **Where:** `DeuceMate/DeuceMate Watch App/StatsStore.swift:60-67` (`_loadHistoryUnsafe` returns `[]` on read *or* decode failure), consumed destructively by `appendMatch` (:37) and `removeMatch` (:50).
- **Failure chain:** one transient read/decode failure → `appendMatch` rewrites `matchHistory.json` with a single record → up to 24 matches silently gone from the watch; `WatchMatchSyncService.sendManifest()` (`Sync/WatchMatchSyncService.swift:72-76`) then broadcasts the near-empty manifest → phone caches it and prunes its watch mirror (`PhoneMatchSyncService.swift:361-366`) → storage badges and watch-only rows corrupted on the phone too.
- **Note:** this violates the repo's own invariant ("a read failure is never treated as an empty archive", `PhoneStatsStore.swift:16-19`). The phone store got the careful `missing / corrupt / unreadable` treatment; the watch store never did.
- [ ] Make `_loadHistoryUnsafe` return `[MatchRecord]?` (nil = unreadable/corrupt; `[]` only when the file is genuinely absent).
- [ ] `appendMatch` / `removeMatch`: bail (log) instead of rewriting when the load returns nil.
- [ ] Add `loadHistoryOrNil()` and use it in `WatchMatchSyncService.sendManifest()` + the activation/reachability full-history pushes so a failed read never sends an empty manifest.
- [ ] Tests: none exist for `StatsStore` (watch target). Add a Core-level test if the load/guard logic is extracted, else a watch-target test with a corrupt fixture file.

**Diff (changed lines only):**
```diff
 // StatsStore.swift
-    func loadHistory() -> [MatchRecord] {
-        queue.sync { _loadHistoryUnsafe() }
-    }
+    func loadHistory() -> [MatchRecord] {
+        queue.sync { _loadHistoryUnsafe() ?? [] }
+    }
+
+    /// nil when the file exists but could not be read or decoded — callers must
+    /// never treat that as an empty history (see PhoneStatsStore's invariant).
+    func loadHistoryOrNil() -> [MatchRecord]? {
+        queue.sync { _loadHistoryUnsafe() }
+    }

     func appendMatch(_ record: MatchRecord) {
         queue.sync {
-            var records = _loadHistoryUnsafe()
+            guard var records = _loadHistoryUnsafe() else {
+                statsStoreLogger.error("appendMatch skipped: history unreadable; refusing to overwrite")
+                return
+            }

     func removeMatch(id: UUID) {
         queue.sync {
-            var records = _loadHistoryUnsafe()
+            guard var records = _loadHistoryUnsafe() else {
+                statsStoreLogger.error("removeMatch skipped: history unreadable; refusing to overwrite")
+                return
+            }

-    private func _loadHistoryUnsafe() -> [MatchRecord] {
-        guard let data = try? Data(contentsOf: fileURL) else { return [] }
+    private func _loadHistoryUnsafe() -> [MatchRecord]? {
+        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
+        guard let data = try? Data(contentsOf: fileURL) else { return nil }
         do {
             return try JSONDecoder().decode([MatchRecord].self, from: data)
         } catch {
             statsStoreLogger.error("Failed to decode match history: \(error.localizedDescription, privacy: .public)")
-            return []
+            return nil
         }
     }
```
```diff
 // WatchMatchSyncService.swift — sendManifest()
-        let ids = StatsStore.shared.loadHistory().map(\.id)
+        guard let history = StatsStore.shared.loadHistoryOrNil() else { return }
+        let ids = history.map(\.id)
```

### 2. Class A file protection on watch stores breaks background WatchConnectivity handling (and feeds #1)
- **Where:** `StatsStore.swift:73` and `ScoreViewModel.swift:1622` write with `.completeFileProtection`; incoming background deliveries (`deleteMatchOnWatch`, `singleMatch` "Sync to Watch") call `StatsStore.appendMatch/removeMatch` from the WC delegate (`WatchMatchSyncService.swift:264-280`), which can fire while the watch is locked (off-wrist).
- **Cost of ignoring:** while locked, reads fail → #1's empty-read path; writes fail → queued phone→watch commands are silently lost; a locked-state `sendManifest` reports an empty watch.
- **Note:** the phone codebase already documents exactly this hazard and uses until-first-unlock for the same reason (`PhoneStatsStore.swift:358-362`, `PhoneMatchSyncService.swift:488-495`). The watch files contradict it.
- [ ] Switch both writes to `.completeFileProtectionUntilFirstUserAuthentication`.
- [ ] Note in the PR: existing files keep Class A until next rewrite; both files are rewritten atomically on next save, so migration is automatic.

**Diff:**
```diff
 // StatsStore.swift — _writeUnsafe
-            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
+            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
```
```diff
 // ScoreViewModel.swift — saveState()
-            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
+            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
```

---

## P1 — correctness of the flagship live feature

### 3. Per-point live checkpoints have no payload-size guard — live scoreboard silently freezes in long matches
- **Where:** `Packages/DeuceMateCore/Sources/DeuceMateCore/Sync/MatchSyncTransport.swift:83-93` (`sendRecord` reachable path). `WCSession.sendMessage` hard-fails above 65,536 bytes; the checkpoint embeds the full `stats` array, which grows every point (~250–350 B/point with `gameScoreAtStart` + HR + steps → limit crossed around 190–260 points, i.e. a long 3-setter).
- **Cost of ignoring:** every subsequent per-point update errors (log-only, no fallback — unlike `sendRecordReliable`/`sendHistory` which detect >64 KB); the spectator scoreboard, announcements, and iPhone-input state stop updating exactly in the matches people care most about.
- ⚠️ **Receive-side change is mandatory, not optional** (caught in PR review): `MatchMergePolicy.resolve` case 5 always accepts the incoming in-progress record (`MatchMergePolicy.swift:40-45`, deliberately — undo checkpoints), so a bare stats-stripped checkpoint would replace the phone's stored active match with `stats = []`, blanking live stats and — if the match is abandoned and never finalized — leaving the archive copy statless until the next full-history push. The strip must be *flagged on the wire* and *grafted on receive*. Send + receive land in the same PR.
- [ ] Add `MatchSyncKey.checkpointStatsOmitted` (Bool) to `MatchSyncMessage.swift`; set it in `MatchSyncPayloadBuilder.checkpointPayload` when the transport strips stats; surface it from `SyncIncomingPayload.decode`.
- [ ] In `sendRecord`, when `data.count > matchSyncUserInfoSizeLimit`, re-encode the checkpoint with `stats = []` (scoreboard fields intact) and mark the payload stats-omitted; the finalized record / full-history path (which already falls back to `transferFile`) carries the complete stats.
- [ ] On the phone, graft before merging: when a checkpoint is flagged stats-omitted and the store holds a same-id record, copy the stored `stats` onto the incoming record, then run the normal merge. (Known, accepted skew: a late-match undo in slim mode leaves the phone's stats one point ahead until the final record — score display stays correct.)
- [ ] Tests: `MatchSyncTransportTests` — oversized in-progress record still sends, decodes to the same score, empty stats, flag set; `MatchMergePolicyTests` (or a new graft test) — flagged slim checkpoint into a store with stats preserves them.
- **Open decision (see “Decisions needed”):** strip-stats-with-graft vs. queuing the oversized checkpoint via `transferFile` (fully lossless but floods the transfer queue at one file per point).

**Diff (strip-stats option, send side):**
```diff
 // MatchSyncTransport.swift — sendRecord(_:completedClearsActive:announcement:)
         if session.isReachable {
+            var messageData = data
+            var statsOmitted = false
+            if data.count > matchSyncUserInfoSizeLimit {
+                // sendMessage hard-fails ≥ ~65 KB. Keep the live scoreboard
+                // updating in long matches by dropping the stats array from the
+                // live checkpoint; the finalized record / full-history sync
+                // (transferFile path) delivers the complete stats. The flag lets
+                // the phone graft its stored stats instead of accepting [].
+                var slim = record
+                slim.stats = []
+                if let slimData = try? MatchSyncMessage.encode(slim) {
+                    messageData = slimData
+                    statsOmitted = true
+                }
+            }
             let msg = MatchSyncPayloadBuilder.checkpointPayload(
-                recordData: data,
+                recordData: messageData,
+                statsOmitted: statsOmitted,
```
(Requires `MatchRecord.stats` to be `var` — it already is.)

**Diff (receive side, phone):**
```diff
 // PhoneMatchSyncService.swift — handle(_:), checkpoint/singleMatch event
+            // Slim checkpoint: the watch omitted stats to fit sendMessage's
+            // size limit. Graft the stored stats so the merge (which always
+            // accepts an incoming in-progress record) can't blank them.
+            var record = record
+            if statsOmitted, record.iWon == nil, record.stats.isEmpty,
+               let existing = store?.loadHistory().first(where: { $0.id == record.id }) {
+                record.stats = existing.stats
+            }
             store?.mergeIncoming(record)
```

---

## P2 — performance

### 4. Synchronous full-state disk writes on the watch main actor, every point
- **Where:** `ScoreViewModel.saveState()` (`ScoreViewModel.swift:1584-1622`) JSON-encodes the whole `AppState` (including all `currentMatchStats`) and writes atomically, called on every scoring action (call sites :684, :704, :746, :934, :993, :1233, :1249, :1452, :1563, :1819).
- **Cost of ignoring:** per-point input latency grows linearly with match length on watch hardware; late in a long match every tap pays an O(n) encode + fsync on the UI thread.
- [ ] Encode on the main actor (state is main-confined), move the `write` onto a serial utility queue.
- [ ] Same pattern phone-side: `PhoneStatsStore` mutators (`saveHistory`/`appendMatch`/`syncToPhone`/`deletePermanently`/`mergeIncoming`, `PhoneStatsStore.swift:149-248`) are `queue.sync` from the caller, so UI actions block on a full-archive encode + write (`adoptOnQueue`, :254-271). Switch the void-returning mutators to `queue.async` (FIFO on the serial queue keeps read-after-write consistent).
- [ ] Launch time: `PhoneStatsStore.init` (:115-135) decodes the entire archive under `queue.sync`, and `PhoneMatchSyncService.loadCachedMirror()` (:37, :478-483) decodes the mirror — both on first touch of `.shared`, typically main thread at launch. Load async and publish when ready (keep `isRestoringFromICloud`-style "loading" state so an empty list reads as in-progress).

**Diff (watch write, minimal):**
```diff
 // ScoreViewModel.swift — saveState()
-            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
+            let url = fileURL
+            Self.stateIOQueue.async {
+                do {
+                    try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
+                } catch {
+                    // log via existing logger
+                }
+            }
+// new, near other stored properties:
+    private static let stateIOQueue = DispatchQueue(label: "com.deucemate.watch.state", qos: .utility)
```
```diff
 // PhoneStatsStore.swift — e.g. mergeIncoming / deletePermanently / appendMatch / saveHistory / syncToPhone
-        queue.sync {
+        queue.async {
```
(Leave `loadHistory`, `exportManualArchiveData`, `importManualArchive` as `sync` — they return values.)

### 5. Duplicate full-history syncs on every reachability flip, from both sides
- **Where:** watch pushes full history on activation *and* every reachability gain (`WatchMatchSyncService.swift:169-184`); the phone *also* requests full history on activation and every reachability gain (`PhoneMatchSyncService.swift:279-281, :295-297`), which the watch answers with another full push (`WatchMatchSyncService.swift:210-211`). Reachability flips constantly on watchOS (wrist-down, app background).
- **Cost of ignoring:** two full-archive encodes + transfers (25 records × full stats; >64 KB becomes repeated `transferFile`s) per flip — battery, WC queue backlog, and constant `mergeIncoming` churn through the phone store's write funnel (which also re-triggers debounced iCloud pushes).
- [ ] Dedupe the watch's *proactive* pushes: remember a cheap signature (`id + endTime + stats.count` per record) of the last successful push and skip when unchanged. Always honor an explicit `requestFullHistory` (the phone may have lost data).
- [ ] Confine the signature to a serial queue (caught in PR review): `WCSessionDelegate` callbacks arrive on background queues, so an unsynchronized `lastPushedHistorySignature` is a data race. Don't hop to main for this — `loadHistoryOrNil()` is blocking disk I/O (see item 4); a private serial queue gives safety *and* keeps the work off the main thread.
- [ ] Reset the signature after a local mutation that must re-sync (e.g. `removeMatch` via `deleteMatchOnWatch`) — routing the reset through the same queue keeps it race-free.
- [ ] Then drop the phone's `requestFullHistorySync()` on reachability gain (keep the activation one) — the watch's push already covers it.

**Diff (watch dedupe, queue-confined):**
```diff
 // WatchMatchSyncService.swift
+    /// Serializes proactive history pushes and the dedupe signature —
+    /// WCSessionDelegate callbacks arrive on background queues, and the
+    /// history load is blocking I/O that must stay off the main thread.
+    private let pushQueue = DispatchQueue(label: "com.deucemate.sync.historyPush", qos: .utility)
+    /// Signature of the last proactively pushed history; explicit phone
+    /// requests bypass this (the phone may have lost data). Access only
+    /// on `pushQueue`.
+    private var lastPushedHistorySignature: String?
+
+    private func pushFullHistoryIfChanged() {
+        pushQueue.async { [weak self] in
+            guard let self, let history = StatsStore.shared.loadHistoryOrNil() else { return }
+            let signature = history
+                .map { "\($0.id):\($0.endTime?.timeIntervalSince1970 ?? -1):\($0.stats.count)" }
+                .joined(separator: "|")
+            guard signature != self.lastPushedHistorySignature else { return }
+            self.lastPushedHistorySignature = signature
+            self.sendFullHistory(history)
+        }
+    }

     // activationDidCompleteWith / sessionReachabilityDidChange
-        sendFullHistory(StatsStore.shared.loadHistory())
+        pushFullHistoryIfChanged()
```
```diff
 // PhoneMatchSyncService.swift — sessionReachabilityDidChange
-        if session.isReachable {
-            requestFullHistorySync()
-        }
+        // Activation still requests once; the watch pushes proactively on
+        // reachability gain, so a second per-flip request is redundant.
```

---

## P3 — hygiene (fix opportunistically, same-PR where touched)

- [ ] **Doc rot:** `MatchSyncMessage.swift:19` and `:28` say the watch caps history at 10; `WatchHistory.cap` is 25. Fix the comments (they exist precisely so agents don't guess).
- [ ] **`isBackupUploaded` false-negative:** `readUploadStatusOnQueue` (`PhoneStatsStore.swift:619-620`) maps a resource-value read *error* to `false` (“uploading”) — indistinguishable from a real in-progress upload; benign but consider logging.
- [ ] **Settings-key audit result (for the record):** all `UserDefaults`/`@AppStorage` literals match `MatchSyncKey` raw values; the only intentional exceptions remain the documented announcements aliases and phone-local `maxHRComputed` / `courtInitialHeading` / `hasCompletedFirstGame` / `watchManifestIDs`. No drift found — no action.
- [ ] **`MatchRecord`/`PointStat` decoding:** verified compliant with the §4 recipe (`decodeIfPresent` + defaults on all post-v1 fields). No action.
- [ ] After #1/#2 land, update `docs/architecture/sync-and-data-flow.md` if it documents the watch store's failure semantics, and keep `CLAUDE.md` §0's invariant wording pointing at both stores.

---

## Decisions needed before executing

1. **Item 3 fallback strategy:** strip `stats` from oversized live checkpoints *with the flagged-payload + receive-side graft* (proposed — cheap, scoreboard-correct, phone archive keeps its stats, final record reconciles) vs. `transferFile` per oversized checkpoint (fully lossless live stats, but queues one file per point for the rest of the match). Proposed default: strip + graft, both sides in one PR.
2. **Item 5 scope:** dedupe-only (watch side, lowest risk) vs. also removing the phone's per-reachability `requestFullHistorySync()`. Proposed default: both, in one PR, since the request path is what doubles the traffic.

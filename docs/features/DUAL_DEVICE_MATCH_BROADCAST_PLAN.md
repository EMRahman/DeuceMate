# Plan: Dual-Device Match Broadcast & Archive (co-scoring, gated, default-OFF)

## Status
**Design — not yet implemented.** Singles only for the first iteration. Doubles is
explicitly deferred (see "Why doubles is deferred" below).

## Context
DeuceMate is single-perspective today: one player scores on their Apple Watch (the
sole source of truth), the score syncs to that player's iPhone over WatchConnectivity,
and the iPhone archives the completed match. Two pain points motivate this feature:

1. Players sometimes disagree on the score mid-match — there is no shared, live view.
2. Only one player ends up with a record of the match in their history.

This feature lets a **second player's iPhone (and their Apple Watch) follow the same
live match** so both players see one shared score, and the **second iPhone records the
match into its own history exactly the way the primary iPhone does today**.

This is the lowest-risk **broadcast** model: one scorer remains the single source of
truth; the second device is a follower/archiver. There is **no concurrent scoring and
no merge engine**. Per-point acknowledgement and fully independent dual-scoring are
**out of scope** for this iteration.

### Hard gating requirement
Every line of new behavior sits behind a single feature toggle that **defaults to OFF**.
When OFF, the app's existing flow is byte-for-byte unchanged — no MultipeerConnectivity
advertising/browsing, no new UI surfaces active, no new code paths reached in the
existing sync / scoring / archive flow, and no new permission prompts. This is the most
important constraint of the whole feature.

## Comms decision: MultipeerConnectivity (Bluetooth / peer-to-peer Wi-Fi)
Both players are on the same court, so we use **MultipeerConnectivity (MPC)** —
serverless, accountless, works with no Wi-Fi/cell, and consistent with the app's
offline / zero-backend ethos. Alternatives considered and rejected:

- **Internet relay / CloudKit:** needs accounts + signal, breaks the no-cloud promise,
  adds backend cost and privacy surface. Rejected.
- **Direct watch-to-watch:** watchOS cannot run MPC, and cross-user watch connectivity
  is not a supported path. Rejected.

Because watchOS cannot run MPC, the topology relays through each player's phone:

```
Host watch (scorer) ─WCSession→ Host iPhone ─MPC/Bluetooth→ Guest iPhone ─WCSession→ Guest watch (display)
```

The host iPhone is already a passive receiver of its watch's live checkpoints; it simply
re-broadcasts them. The guest iPhone receives, mirrors to its own perspective, displays,
relays to its watch, and archives on completion.

## Design

### The feature toggle
- New iPhone-side `UserDefaults` flag `coScoreEnabled`, default `false`, surfaced in
  `DeuceMate/Views/SettingsView.swift` alongside the existing toggles (follow the
  `iPhoneInputEnabled` pattern).
- It is **phone-local** (not synced to the watch) for this iteration.
- `PhoneCoScoreService` only activates MPC advertising/browsing while the flag is ON.
  Guards everywhere: when OFF, `PhoneMatchSyncService` never calls into the co-score
  service, the pairing UI entry point is hidden, and no MPC objects are instantiated.

### Roles & pairing (QR)
- A **`CoScoreSession`** (new model) holds: a negotiated shared session `UUID`, the
  host's `playerName`, `matchFormat` / `matchType`, who serves first, and the local
  device's role (host vs guest).
- **Host** taps "Share this match" → its phone advertises over MPC and shows a **QR
  code** encoding the session payload. **Guest** scans the QR, connects over MPC, and a
  handshake confirms format/role.
- QR (rather than open MPC discovery) binds the *correct* peer — open discovery alone
  would surface strangers' devices at a busy club.
- Pairing should happen before / at match start; mid-match join does a one-time "adopt
  host's current record" on connect.

### Data flow
- **Host →** `PhoneCoScoreService` observes the live checkpoint the host phone already
  receives (the `.singleMatch` case in `PhoneMatchSyncService.handle`) and, when paired,
  forwards the encoded `MatchRecord` over MPC tagged with the session UUID. No change to
  scoring; reuses `MatchSyncMessage.encode`.
- **Guest ←** receives the record over MPC, runs `MatchRecord.mirrored()` so it reads
  from the guest's perspective (guest = `.me`), then:
  1. publishes it for the **live scoreboard** (reuse
     `DeuceMate/Views/LiveScoreboardView.swift`, read-only),
  2. **relays the live score to the guest's own watch** over WCSession for a read-only
     watch display,
  3. on completion (`iWon != nil`) **archives** it via `PhoneStatsStore.mergeIncoming`
     — the same path the primary uses, so it lands in the guest's history naturally.

### Perspective mirroring (`MatchRecord.mirrored()`)
A pure transform in `DeuceMateCore` that swaps every perspective-relative field:

- `currentPointsMe` ↔ `currentPointsOpponent`
- `iWon` negated (when non-nil)
- `currentServer` / `tiebreakStartServer` / `tiebreakFirstPointReceiver` /
  `lastTiebreakPointServer` flipped
- each entry in `recentPoints` flipped
- each `SetScore`'s `gamesMe` / `gamesOpponent` and `tieBreakPointsMe` /
  `tieBreakPointsOpponent` swapped

`stats[]` are perspective-relative with per-device IDs; for broadcast we mirror the
server/winner fields but keep them **archive-only** (no cross-device stat
reconciliation). The transform must be **exhaustively unit-tested** across deuce,
tiebreak rotation, and set completion — otherwise the guest's display will be wrong.

**Strip the host's health/fitness metrics.** These fields describe the *host's* body,
not the guest's, so `mirrored()` must set them to `nil` before the guest displays or
archives the record — otherwise they corrupt the guest's personal stats and health
history. Specifically:
- on `MatchRecord`: `totalSteps`, `totalDistanceMeters`, `totalCaloriesKcal`
- on each `PointStat`: `heartRateBPM`, `stepsCumulative`

The guest's archived record therefore carries the shared *score* but none of the host's
activity/biometric data. This is both a correctness and a privacy requirement, and
should have its own unit-test assertions (mirrored record's health fields are all
`nil`).

## Files

### New (DeuceMateCore, iOS-only via `#if canImport(MultipeerConnectivity)` where needed)
- `Sync/PeerMatchTransport.swift` — MPC wrapper
  (`MCSession` / `MCNearbyServiceAdvertiser` / `MCNearbyServiceBrowser`); intent-based
  API mirroring the shape of the existing `Sync/MatchSyncTransport.swift`
  (sendCheckpoint / sendHandshake).
- `Models/CoScoreSession.swift` — session UUID, names, format, first server, role,
  connection state.
- `Sync/MatchPerspective.swift` — `MatchRecord.mirrored()` + the QR payload `Codable`
  struct.
- Extend `Sync/MatchSyncMessage.swift` / `MatchSyncKey` with co-score keys
  (`coScoreSessionID`, `coScoreCheckpoint`, `coScoreHandshake`).

### New (iPhone target)
- `CoScore/PhoneCoScoreService.swift` — owns `PeerMatchTransport`; host-forward +
  guest-receive / mirror / relay / archive; only live while `coScoreEnabled`.
- `Views/CoScorePairingView.swift` — host QR generation + guest QR scan (AVFoundation),
  handshake status.

### New (watch target)
- `RemoteLiveScoreView.swift` — read-only live score display fed by the guest phone;
  surfaced by a new branch in `Sync/WatchMatchSyncService.swift` when a
  remote-live-score payload arrives.

### Changed
- `DeuceMate/Views/SettingsView.swift` — add the default-OFF `coScoreEnabled` toggle +
  a gated "Share / Follow match" entry to `CoScorePairingView`.
- `DeuceMate/Sync/PhoneMatchSyncService.swift` — in `handle(...)`, when
  `coScoreEnabled`, forward `.singleMatch` / `activeMatchID` / `clearActiveMatch` to
  `PhoneCoScoreService` (host side); inbound MPC mirrored records routed to
  `PhoneStatsStore.mergeIncoming` (guest side). All additive and flag-guarded.
- iPhone `Info.plist` — `NSLocalNetworkUsageDescription` + `NSBonjourServices`
  (MPC service type) + `NSCameraUsageDescription` (the guest QR scanner opens the
  camera via AVFoundation; without this key iOS terminates the app the moment the scan
  view tries to access the camera). Inert until the feature is used. The MPC service
  type must obey
  iOS Bonjour rules or advertising/browsing crashes at runtime: **≤ 15 characters,
  lowercase letters / digits / hyphens only, no leading/trailing/double hyphen**, and it
  must be declared for **both** transports — `_<service>._tcp` and `_<service>._udp` —
  with the same `<service>` string passed to `MCNearbyServiceAdvertiser` /
  `MCNearbyServiceBrowser`. Proposed value: `deucematch` (e.g. `_deucematch._tcp` /
  `_deucematch._udp`).

### Reused as-is
`MatchSyncMessage.encode/decode`, `PhoneStatsStore.mergeIncoming`
(+ `MatchMergePolicy` dedupe by id / tombstones), `LiveScoreboardView`, and the existing
phone↔watch WCSession transport for the guest-watch relay.

## Edge cases
- **Doubles:** feature unavailable (mirroring is asymmetric — see below). Pairing
  rejects non-singles.
- **Guest already has an active match when pairing:** if the guest has a live match in
  progress on their own iPhone or Apple Watch, the pairing flow must detect this and
  **not** silently overwrite it. Block pairing with a prompt to finish, save, or discard
  the in-progress match first, then allow joining. Following a host's match must never
  clobber the guest's own unsaved match state.
- **Guest joins mid-match:** one-time adopt-host's-current-record on connect, then
  live-follow.
- **Peer disconnect / app backgrounded:** host keeps scoring normally; guest shows
  "disconnected — following paused"; on reconnect, host resends current checkpoint and
  guest resyncs. Local behavior never blocks on the peer.
- **Undo on host:** propagates as the next checkpoint (a record with fewer points) —
  guest just reflects it; `MatchMergePolicy` already accepts in-progress checkpoints in
  order, including undos.
- **Completion:** host sends the finalized record (`iWon != nil`); guest mirrors →
  archives once.

## Why doubles is deferred
Singles mirroring is a clean bijection: `Player { case me, opponent }`, so flipping
perspective is just `me ↔ opponent`.

Doubles uses `DoublesServer { case me, partner, opponentS1, opponentS2 }`, and the two
sides are **not stored symmetrically**:

- **Your own team is named; the opponents are anonymized slots.** From the host's
  vantage point its side is two identified individuals (`me`, `partner`), but the
  opposing side is only "server 1" / "server 2" — positional slots with no identity
  attached to which physical human is which.
- **Mirroring therefore loses information.** When the guest (on the other team)
  receives the host's record, the guest's `me` / `partner` must map onto the host's
  `opponentS1` / `opponentS2`, but the host never recorded which slot is the guest vs
  the guest's partner. That disambiguation simply isn't in the record.
- **Service rotation compounds it.** Doubles carries `doublesServiceOrder` (a 4-element
  rotation), `doublesServiceIndex`, and `tiebreakStartDoublesIndex`. Mirroring must
  remap all four roles *and* preserve rotation/index semantics from the opposite side,
  which the named-vs-slotted mismatch prevents.

Supporting doubles would require capturing a **shared four-player identity mapping at
pairing time** (each human mapped to an agreed slot on both devices) — a meaningfully
larger pairing handshake and model change. Deferred as a follow-up, not abandoned.

## Verification
1. **Gating first:** with `coScoreEnabled` OFF, confirm the app is unchanged — no MPC
   permission prompt, no new UI, existing watch↔phone scoring/archive flow identical.
   This is the most important check given the hard gating requirement.
2. **On-court reliability (the real-world risk):** enable the toggle on two iPhones,
   take them to an actual court (no Wi-Fi); verify QR pairing binds the right peer, the
   local-network permission flows, the live score mirrors within ~1s, it survives a
   backgrounding/reconnect, and battery cost is acceptable over a full match.
3. **Guest archive parity:** play a full singles match; confirm the completed match
   appears in the guest's history from the guest's perspective (correct winner, scores
   not inverted), matching how the host's own history shows it (inverted me/opponent).
4. **Guest watch display:** confirm the live score shows read-only on the guest's Apple
   Watch and updates with the host's points.
5. **Unit tests:** exhaustive `MatchRecord.mirrored()` tests (deuce, tiebreak server
   rotation, set completion, `iWon` negation) in `DeuceMateTests` / `DeuceMateCore`
   tests — these guard against inverted-display bugs.
6. Build all targets (iPhone, watch, `DeuceMateCore`) and run the existing test suites
   to confirm no regression.

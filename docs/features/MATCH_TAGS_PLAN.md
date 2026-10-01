<!--
machine-readable summary (parse this block first)

status: approved (owner decisions recorded in §11, 2026-10-01)
author: Claude, design session with the owner
date: 2026-10-01
feature: "Tag a finished match with who was played (selectable roster) and its competition type (Friendly / League / Tournament / Practice); show the tags on the watch; feed them into the AI Coach prompt and the shared reports."
recommendation: "One optional `tags: MatchTags?` field on MatchRecord, edited on iOS, read-only on the watch in v1. The roster of players is DERIVED from the archive (no second persisted store). Tags merge independently of the record body by their own last-write-wins clock, because today's merge rules would silently wipe them. Names are withheld from the AI prompt by default and never put in filenames or spoken announcements."
hard_findings:
  - "MatchMergePolicy.resolve case 4 (both completed) keeps `incomingEnd >= existingEnd ? incoming : existing` (MatchMergePolicy.swift:42). The watch's copy of a finished match has the SAME endTime as the phone's, so the next full-history push (Sync Now, requestFullHistory, ping) replaces the phone's tagged record with the watch's untagged one. `fillingMissingHealthData` backfills only health. Tags MUST merge separately — PR 1 lands before any UI can write a tag."
  - "Three other merge sites have the same shape: ArchiveBackupPolicy.resolveBackup (initial iCloud restore), ManualMatchArchiveBackup.importSnapshot(.merge) (via resolve) and the watch's `.singleMatch` handler (via resolve). WatchMirror.merged replaces by id but is a display mirror of the watch's own copy."
  - "Mixed versions are routine (watch and phone update separately). MatchRecord's custom init(from:) ignores unknown keys, so an old build decodes a tagged record — but re-encodes it WITHOUT tags. So `tags == nil` must mean 'no information', never 'cleared'. Clearing is an empty MatchTags with a newer updatedAt."
  - "`MatchType` already exists and means singles/doubles (ScoreTypes.swift:11, rendered as `matchTypeLabel` in the HTML export). Friendly/League/Tournament needs a different name: `MatchCompetition`."
  - "A new persisted enum is additive-only forever (CLAUDE.md §4, TECHNICAL_DEBT #18) and a value an older build doesn't know fails the WHOLE [MatchRecord] decode (#19). MatchCompetition is stored as a raw string and exposed as an optional typed value, so a future case degrades to 'unknown' instead of blanking an archive."
  - "Sending a full record to the watch to update tags would go through the `.singleMatch` handler, which calls `onCompletedMatchReceived` → `completeCurrentMatchIfMatching` (DeuceMateApp.swift:60). A dedicated `matchTagsUpdate` wire key avoids that side effect, is tiny, and older watch builds already ignore unknown keys."
scope:
  in_scope:
    - "Core: Models/MatchTags.swift (new), MatchRecord.tags, MatchMergePolicy + ArchiveBackupPolicy tag merge, Stats/PlayerRoster.swift + HeadToHead (new, derived), MatchSyncKey.matchTagsUpdate + payload builder + SyncIncomingPayload event"
    - "iOS: tag editor + player picker on MatchDetailView, archive-row subtitle, PhoneStatsStore.updateTags, rename/forget player, push tags to the watch with manifest/history reconciliation (§6.1)"
    - "Watch: persist incoming tags (StatsStore, same serial queue), show them in MatchHistoryView / MatchStatsView"
    - "Exports: AI prompt 'Match Context' section + head-to-head, text export overview lines, HTML meta (schema 13) + static fallback"
    - "docs/website/privacy.html, docs/release/APP_STORE_METADATA.md, docs/architecture/* — in the PRs that ship the behaviour, not in this plan PR"
  out_of_scope_v1:
    - "Tagging on the watch (quick pick after a match) — v2, see §9"
    - "Trends filter by competition / opponent, head-to-head card on iOS — v2"
    - "Free-text event / club / venue names — not asked for, adds location-like data"
    - "Contacts framework integration — a permission and a privacy surface for no real gain"
    - "Tagging in-progress matches — v1 tags completed records only (the merge rule copes either way)"
    - "Tag fields in ManualMatchEntryView — it only ever builds an in-progress record (endTime: nil, iWon: nil), so tags there would contradict the completed-only rule. A manually entered match is tagged from MatchDetailView once it is completed (on the watch, or via End at Current Score)."
decisions: [OQ-1 UI label is 'Competition Type', OQ-2 names in shared reports ON by default with a toggle, OQ-3 iPhone-only editing in v1 (watch read-only), OQ-4 'Practice' included as a fourth case; the six defaults in §11.1 confirmed]
-->

# Plan: Match Tags — Opponent / Partner Names and Competition

## 1. The ask

> Tag a finished match with the name of a player, and a match type of
> friendly / league / tournament. Names, once added, should be selectable
> later. Tagging can happen on the watch or iOS, most likely iOS, with
> visibility on the watch. Use the tags in the AI generation prompt and in
> shared reports. Review whether there is sensitive data to think about.

### 1.1 The proposal at a glance

| Decision | Choice | Why |
|---|---|---|
| Where tags live | One optional `tags: MatchTags?` on `MatchRecord` | Travels with the match through every existing path (sync, iCloud backup, manual archive) with no new store to back up, tombstone or restore. |
| Where you edit | **iOS** match detail, completed matches only. Watch is read-only in v1. | Typing names on a 45 mm screen is slow; the phone is where the archive is reviewed. |
| "Selectable later" | A **roster derived from the archive** — every distinct tagged player, most recent first. | Nothing extra to persist or sync; deleting a player's last match removes them naturally; rename/forget are bulk edits over records. |
| Identity | Each player is `{id: UUID, name}`; the id is minted once and reused when picked from the roster. | Two different "Alex"es stay separate; a rename updates every match. |
| Competition Type | `MatchCompetition`: `friendly`, `league`, `tournament`, `practice`; shown in the UI as **"Competition Type"** | Not `MatchType` — that name is taken by singles/doubles. |
| Sync | Tags merge by their own `updatedAt` clock, independent of the record body; edits go to the watch on a new `matchTagsUpdate` key. | Today's merge would silently delete tags (§3). |
| AI prompt | Competition + head-to-head record **always**; real names **only if the user opts in**, default off. | Names add nothing to coaching quality and are third-party personal data going to an AI service. |
| Shared reports | Names + competition in the header; filenames never contain names. | The recipient is often the opponent — the name is the point. |

## 2. What exists today

- `MatchRecord` has `matchType: MatchType` (singles / doubles) and
  `matchFormat`, nothing about who was played or why.
- `playerName` is a **synced setting** (`MatchSyncKey.playerName`, capped at
  128 chars in `SyncIncomingPayload`) holding the *user's own* name for spoken
  announcements. It is not a tag and is not touched by this plan, except that
  exports can use it for the "me" side when names are included.
- The phone can push a whole record to the watch ("Sync to Watch",
  `PhoneMatchSyncService.sendMatchToWatch`), the watch holds at most
  `WatchHistory.cap` (25) records and reports which via `watchManifest`.
- Doubles already models four positions (`DoublesServer`: me, partner,
  opponentS1, opponentS2) for serve rotation; tags do not need to map onto
  those slots.

## 3. The merge hazard (why Core lands first)

`MatchMergePolicy.resolve`, case 4 — both records completed:

```swift
return incomingEnd >= existingEnd ? incoming : existing   // MatchMergePolicy.swift:42
```

A finished match on the phone and the watch has the **same** `endTime`. The
watch re-sends its whole history on Sync Now, `requestFullHistory` and every
`ping`, so the sequence

1. user tags the match on the phone,
2. watch pushes its history (untagged copy, equal `endTime`),
3. `>=` picks `incoming`,

ends with the tag gone, silently. `fillingMissingHealthData(from:)` only
backfills the five health fields. The same body-wins shape exists in:

| Site | Path |
|---|---|
| `MatchMergePolicy.resolve` | phone ← watch sync; manual archive import (`.merge`); watch ← phone `.singleMatch` |
| `ArchiveBackupPolicy.resolveBackup` | one-time initial iCloud restore |
| `WatchMirror.merged` | phone's display mirror of watch-only rows (replace by id) |

**Rule:** resolve the body exactly as today, then set
`result.tags = MatchTags.merged(existing?.tags, incoming.tags)`:

- one side `nil` → the other (nil = "this copy never heard of tags", e.g. an
  older build re-encoded it);
- both present → the later `updatedAt`; on a tie keep `existing` (stable, no
  flip-flop between devices).

Clearing all tags writes an **empty** `MatchTags` with a fresh `updatedAt`, so
it beats an older non-empty copy instead of looking like "no information".

Put the call inside `resolve` and `resolveBackup` so every current caller gets
it. `WatchMirror` needs no change in v1: tags can only be edited on archive
rows, and a watch-only row shows the watch's own copy.

## 4. Data model (Core)

New file `Models/MatchTags.swift`:

```swift
public struct TaggedPlayer: Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public var name: String            // sanitized display snapshot
}

public enum MatchCompetition: String, CaseIterable, Sendable {
    case friendly, league, tournament, practice
    public var displayLabel: String { … }
}

public struct MatchTags: Codable, Equatable, Sendable {
    public var opponents: [TaggedPlayer]   // 0…1 singles, 0…2 doubles
    public var partner: TaggedPlayer?      // doubles only
    /// Raw storage so an unknown future case round-trips instead of failing
    /// the whole archive decode on an older build (TECHNICAL_DEBT #18/#19).
    public var competitionRaw: String?
    public var competition: MatchCompetition? {
        get { competitionRaw.flatMap(MatchCompetition.init(rawValue:)) }
        set { competitionRaw = newValue?.rawValue }
    }
    public var updatedAt: Date             // tag-only last-write-wins clock
    public var isEmpty: Bool { … }
    public static func merged(_ existing: MatchTags?, _ incoming: MatchTags?) -> MatchTags?
    public func sanitized() -> MatchTags   // see below
}
```

`MatchCompetition` deliberately is **not** `Codable` itself: nothing persists
the enum, only its raw string. That makes it the first persisted value in the
repo that is forward-compatible by construction rather than by review.

`MatchTags` gets a custom `init(from:)` that uses `decodeIfPresent` with
defaults for every field from day one, so later additions follow §4 of
`CLAUDE.md` without a special case.

`MatchRecord` change — the standard §4 recipe, one field:

1. `public var tags: MatchTags?`
2. memberwise `init(…, tags: MatchTags? = nil)`
3. `tags = try c.decodeIfPresent(MatchTags.self, forKey: .tags)`
4. `MatchRecordCodingTests`: round-trip, old JSON without `tags`, a record
   whose `competitionRaw` is `"practice"` (unknown) decoding with
   `competition == nil` and re-encoding the raw value unchanged.

`strippingHealthData()` leaves tags alone (not HealthKit-derived), so they are
in the iCloud backup copy; `HealthSidecarPolicy` is unaffected.

**Sanitizing** (applied on every input path — UI, wire decode, archive import):
trim, collapse internal whitespace, drop control and newline characters, cap
at 40 characters, drop empty names, de-duplicate by id, cap opponents at 2.
The match-type rule (singles ⇒ ≤1 opponent, no partner) is enforced by the
editor, not by decode — decode must never destroy data an editor wrote.

## 5. The roster — "selectable in the future"

New `Stats/PlayerRoster.swift`, pure and derived:

```swift
public struct RosterEntry: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String          // from the most recently updated tag
    public let matchCount: Int
    public let lastPlayed: Date
}
public enum PlayerRoster {
    public static func entries(from records: [MatchRecord]) -> [RosterEntry]   // most recent first
    public static func suggestions(_ query: String, in entries: [RosterEntry]) -> [RosterEntry]
}
public enum HeadToHead {
    /// Wins / losses / draws vs a player across completed matches, excluding `excluding`.
    public static func record(vs playerID: UUID, in records: [MatchRecord], excluding: UUID?) -> HeadToHeadRecord
}
```

Why derived rather than a separate roster file:

- the phone archive already has local + iCloud + manual-archive + tombstone
  handling; a second store would need all four, plus its own sync;
- "forget this person" is simply "remove them from every match";
- a player who appears in no match is not someone you need to pick.

Cost: a player added but never saved to a match is not remembered — fine.

**Picker UX (iOS):** a search field over `suggestions`, recent players below it,
and "Add “<typed text>” as new player". When the typed name case-insensitively
matches an existing entry, the existing one is the first suggestion so you
don't mint a duplicate Alex by accident. Same person can be partner in one
match and opponent in another — one id, one roster row.

**Roster management** (Settings → Players): rename (rewrites the name in every
record carrying that id, bumping each `updatedAt`), merge two duplicates
(rewrite id B → A), and **Forget player** (remove from every record). Each is
a single `PhoneStatsStore` mutation through `adoptOnQueue`, followed by tag
pushes for every affected id the watch holds (§6.1).

## 6. Sync

New wire key in `MatchSyncKey`:

```swift
/// JSON-encoded `MatchTagsUpdate { matchID: UUID, tags: MatchTags }`. Bidirectional.
/// Applied only to a record the receiver already holds; merged by `updatedAt`.
public static let matchTagsUpdate = "matchTagsUpdate"
```

- Built in `MatchSyncPayloadBuilder`, decoded in `SyncIncomingPayload` into
  `.matchTagsUpdate(UUID, MatchTags)` (sanitized at decode), round-trip test in
  `MatchSyncRoundTripTests`.
- Sent with `queueOnFailure: true` (`transferUserInfo`) — it is small and
  must survive the watch being away.
- Phone sends it at edit time when `PhoneMatchSyncService.onWatchIDs`
  contains the id (that set includes optimistic ids from records just
  received, not only the last manifest, which can lag). An edit-time send is
  best-effort; §6.1 is what guarantees delivery. "Sync to Watch" of a tagged
  record needs nothing new: the record carries its tags.
- **Watch:** new `StatsStore.updateTags(id:tags:) -> Bool` that reads, merges
  and writes on the store's serial queue and bails when history is unreadable
  (the CLAUDE.md "read failure ≠ empty archive" rule). Do **not** route it
  through `appendMatch` (hides write failures) or `.singleMatch` (fires
  `completeCurrentMatchIfMatching`).
- **Phone:** the same key is handled (watch → phone) so v2 watch editing needs
  no wire change; it applies through `PhoneStatsStore.updateTags`.
- It is not a setting: no `UserDefaults`, so the §0 settings-key grep is
  unaffected.

### 6.1 Reconciliation — eventual delivery to the watch

An edit-time send alone can be skipped for good: the edit can land while the
manifest still lags a record the watch already holds, or the watch can be an
older build that ignores `matchTagsUpdate` and is upgraded later. Nothing would
ever resend. So the phone also reconciles, triggered by the two signals that
say what the watch actually holds:

1. **Watch record bodies** (`.history`, `.singleMatch`). Each carries the
   watch's own copy of the tags. After the merge, any id whose archive tags
   are newer than the incoming copy's (`nil` counts as oldest) gets a
   `matchTagsUpdate`. This is the precise "watch is behind" signal, and it is
   what heals an upgraded watch: its first history push after the upgrade
   still has no tags.
2. **Manifest arrival.** For ids that are in the new manifest but were not in
   the previous one, send the archive's tags if they are non-empty. This
   covers an edit made during the manifest lag.

Both checks are a pure Core function,
`MatchTags.pendingWatchUpdates(archive:watchCopies:newlyHeld:) -> [MatchTagsUpdate]`,
tested in `MatchTagsTests`. Resends are idempotent (the watch merges by
`updatedAt`). Diffing the manifest rather than re-sending on every arrival
matters: the watch sends a manifest with every live checkpoint, so a naive
"resend all held tags" would add up to 25 payloads per point during play.

Mixed-version behaviour, checked:

| Phone | Watch | Result |
|---|---|---|
| new | old | watch ignores the unknown key; its history pushes carry no `tags` → merge keeps the phone's. After the watch upgrades, its next history push still has no tags → §6.1 rule 1 resends them. |
| old | new | phone never sends tags; nothing to show. |
| new | new | full behaviour. |

## 7. Surfaces

### 7.1 iOS

- **MatchDetailView:** a "Match Info" row under the header —
  `vs Alex · League` or `With Sam vs Alex & Jo · Tournament`, "Add opponent &
  type" when empty. Tapping opens a sheet: Competition Type segmented control (Friendly / League / Tournament / Practice), then
  Opponent(s) (+ Partner for doubles) using the picker. Completed records only.
- **PastMatchesView:** the same one-line subtitle in each row (cheap, already a
  `MatchRecord`-driven row; respects the TECHNICAL_DEBT #13 note — put the
  subtitle helper in Core or a small view file, not in `PastMatchesView`).
- **ManualMatchEntryView:** no tag fields — it only creates in-progress
  records. A manually entered match is tagged from its detail view once it is
  completed.
- **Settings → Players:** roster management (§5).

### 7.2 Watch (read-only in v1)

- `MatchHistoryView` row: one caption line `vs Alex · League` (truncated).
- `MatchStatsView` header: the same line.
- Nothing during live play.

### 7.3 Exports

| Export | Adds | Names |
|---|---|---|
| AI Coach prompt (`MatchExporter.aiPromptExport`) | `## Match Context`: competition, singles/doubles, head-to-head ("vs this opponent: 3–2 in 5 matches; last 3: W W L") | **Off by default.** "Include player names" toggle on `AICoachSheet`; off ⇒ "Opponent", "Partner". |
| Text summary / full export | Overview lines: Competition, Opponent(s), Partner | On by default (OQ-2, decided). |
| Interactive HTML | `Meta.competitionLabel`, `Meta.readerSideNames`, `Meta.otherSideNames` — **reader-framed in Swift** like every other field, so the JS only paints; schema 12 → 13; same lines in `MatchWebStaticFallback` | On by default (OQ-2, decided). |
| Filenames (`deuce_mate_<date>[_opponent].html`) | unchanged | **Never.** |
| Spoken announcements | unchanged | **Never** (v1). |

Coaching prompt wording: the competition is a useful steer ("this was a league
match — weight the pressure-point and break-point sections"), the head-to-head
tells the model whether this was a familiar opponent. Neither needs a name.

All name strings reach HTML only through the existing escaping —
`MatchHTMLExporter.scriptSafe` for the inlined JSON and the static fallback's
`&lt;` escaping. Add `MatchWebExportTests` cases with hostile names
(`</script><script>alert(1)</script>`, `<!--`, U+2028) asserting the page
contains no executable injection and still passes `assertOnlyOptInLinks`.

## 8. Sensitive data review

Tags introduce the app's first **third-party personal data**: names of people
who are not the user and never agreed to be recorded. Nothing here reaches the
developer, but every place a name can travel needs a deliberate answer.

| # | Concern | Risk | Decision |
|---|---|---|---|
| S1 | **Names of other people stored on device and in the user's iCloud backup** | Low. Personal/household use; the user's own iCloud container. | Allowed. Disclose in the privacy policy (S9). Tags are *not* health data, so they stay in the iCloud copy. |
| S2 | **Names sent to third-party AI services** via the AI Coach hand-off | Medium. Another person's name plus their performance data goes to a service under its own terms; adds nothing to coaching. | **Withheld by default**; per-export opt-in toggle; the existing disclosure line names "player names" when included. |
| S3 | **Names in shared reports** (text, HTML, manual archive) | Low–medium. Shared on purpose, often *with* that opponent — but a report can be forwarded. | Included by default for reports (OQ-2, decided), behind a visible "Include player names" toggle in the share menu. Manual archive (a personal backup) always full-fidelity, and its disclosure mentions names. |
| S4 | **Names in filenames** | Medium, easy to miss. Filenames show in Files, AirDrop previews, iCloud Drive listings, email attachments — outside the report's own context. | Never. Filenames stay date-based. |
| S5 | **HTML / script injection** through a typed name in the exported page | Medium if unescaped — CSP allows inline script. | Route through existing `scriptSafe` / HTML escaping; hostile-name tests (§7.3). |
| S6 | **Prompt injection** through a name ("ignore previous instructions…") | Low (names off by default; user typed it themselves). | 40-char cap, no newlines/control chars, names quoted in the prompt. |
| S7 | **Names spoken aloud** by iPhone announcements in public | Medium if added. | Not in v1; any future addition needs its own toggle. |
| S8 | **Logging** | Low but permanent in sysdiagnoses. | Never log names or tags with `privacy: .public`; log ids and counts only. |
| S9 | **Privacy policy wording** — it currently says the app does NOT collect "Personal identification information (name, …)" | Low legal risk (still true of the *developer*), but reads as contradictory once the app stores names. | In the shipping PR, add to "Local Data Storage": *"Names you choose to enter for opponents or partners, and a match's competition type."* and to "Sharing": names are included in exports only as described. Update `Last Updated`. Not in this plan PR — the site is published on merge and must not describe a feature that doesn't exist yet. |
| S10 | **App Store privacy label** | None expected. | Stays **"Data Not Collected"**: nothing is transmitted to the developer or a third party except by user-initiated share. Re-confirm in `APP_STORE_METADATA.md` when shipping. |
| S11 | **Minors** — junior tennis means some names are children's | Low (household use, not published by the app). | Picker placeholder suggests first names or nicknames ("e.g. Alex"); no surnames required. |
| S12 | **Right to erasure** | Low. | "Forget player" removes a person from every match on the phone, propagates to the watch, and the next iCloud push overwrites the backup copy. Reports already shared are out of reach — say so in the confirmation. |
| S13 | **Contacts / photos / location** | Would be high. | Not used. Names are typed; no Contacts permission, no venue or GPS. |
| S14 | **Screenshots and App Review demo data** | Low. | Fictional names only in marketing screenshots and demo matches. |

Health interaction: tags do not change what `HealthExportConsent` reports; a
health-free export with names still needs no health dialog — the names toggle
is its own control, not a second consent dialog.

## 9. Watch tagging (v2 — OQ-3 decided: iPhone-only editing in v1)

The natural moment to tag is right after match point, on the wrist. Sketch for
later: after a completed match, an optional "Who did you play?" list showing
the 5 most recent roster names (derived from the watch's own 25 records, plus
a small roster snapshot the phone sends in its application context), a
Competition Type row, and Skip. The wire key is already
bidirectional (§6), so v2 is UI plus one roster payload. Dictation for a new
name is possible but slow — new names stay a phone job.

## 10. Implementation plan

Order is load-bearing: **PR 1 must merge before any PR that can write a tag**,
otherwise the first watch sync deletes it (§3).

### PR 1 — `[Core] Match tags model, tag-preserving merge, roster`
- `Models/MatchTags.swift`, `MatchRecord.tags`, sanitizer.
- Tag merge inside `MatchMergePolicy.resolve` and `ArchiveBackupPolicy.resolveBackup`.
- `Stats/PlayerRoster.swift` (`PlayerRoster`, `HeadToHead`).
- `MatchTags.pendingWatchUpdates` (§6.1).
- `MatchSyncKey.matchTagsUpdate`, payload builder, `SyncIncomingPayload` event
  (+ `==` case, which keeps every exhaustive switch compiling).
- Tests: `MatchTagsTests` (merge table incl. nil/empty/tie, sanitizer,
  unknown competition, raw values `friendly`/`league`/`tournament`/`practice`
  pinned), `MatchRecordCodingTests`, `MatchMergePolicyTests`
  (equal-endTime untagged incoming keeps tags — the §3 regression),
  reconciliation cases (watch copy older/nil, id newly in manifest, no resend
  for an unchanged manifest),
  `ArchiveBackupPolicyTests`, `PlayerRosterTests`, `MatchSyncRoundTripTests`.

### PR 2 — `[Watch] Persist and show match tags`
- Handle `.matchTagsUpdate` in `WatchMatchSyncService`; `StatsStore.updateTags`
  with `StatsStoreTests` for unreadable history / missing id / write failure.
- Caption in `MatchHistoryView` and `MatchStatsView`.
- Ships before PR 3 so a watch that can display tags exists when the phone
  starts writing them (not required for safety — PR 1 covers that).

### PR 3 — `[iOS] Tag matches with opponents and competition`
- `PhoneStatsStore.updateTags(id:tags:)`; edit-time push via `onWatchIDs`
  plus §6.1 reconciliation on history and manifest arrival.
- Editor sheet + picker, detail row, archive subtitle,
  Settings → Players (rename / merge / forget).
- `docs/architecture/file-inventory.md` for new source files.

### PR 4 — `[Core][iOS] Use tags in AI Coach and shared reports`
- AI `## Match Context` + head-to-head; names toggle (default off).
- Text export lines; HTML `Meta` fields, schema 13, static fallback; hostile-name tests.
- Share-menu names toggle.
- `privacy.html` (S9), `APP_STORE_METADATA.md` (S10), `INTERACTIVE_HTML_EXPORT_PLAN.md`.

### Later (v2)
Watch quick-tag (§9); Trends filters by competition and by opponent (new
phone-local `@AppStorage` keys go on the CLAUDE.md §0 exception list); an iOS
head-to-head card per player.

## 11. Decisions (owner, 2026-10-01)

- **OQ-1 — UI label: "Competition Type"** (Friendly / League / Tournament /
  Practice). "Match Type" stays singles/doubles. The Core type remains
  `MatchCompetition`; the HTML field is `Meta.competitionLabel`, rendered under a
  "Competition Type" heading.
- **OQ-2 — names in shared reports: on by default**, with an "Include player
  names" toggle in the share menu. The AI prompt stays off by default regardless.
- **OQ-3 — iPhone-only editing in v1.** The watch shows tags read-only; watch
  quick-tag stays v2 (§9).
- **OQ-4 — "Practice" is in v1** as the fourth `MatchCompetition` case. It goes
  into the raw-value pin test from day one like the other three.

### 11.1 Defaults confirmed as proposed

1. Player names are withheld from the AI prompt by default (opt-in toggle);
   competition type and head-to-head are always included.
2. The roster is derived from the archive — a player is remembered while at
   least one match carries them.
3. Tags apply to completed matches only (not live, not manual entry).
4. Doubles tags partner plus both opponents.
5. Settings → Players ships with Rename, Merge duplicates and Forget player.
6. Names are capped at 40 characters; the input hint suggests first names or
   nicknames.

## 12. Verification

No CI builds or tests this project. Each PR runs the Core package tests
(`swift test` / `xcodebuild test -scheme DeuceMateCore`), and PR 2/3 the watch
and iPhone schemes, on a Mac. Manual pass on a paired device: tag on the phone →
Sync Now on the watch → tag survives on the phone and appears on the watch;
clear the tag → it clears on both; forget a player → gone from every match on
both devices; AI prompt with names off contains no typed name.

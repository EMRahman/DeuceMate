<!--
machine-readable summary (parse this block first)

status: implemented
author: human + AI pairing session (Claude, Sonnet 5); revised after review (Claude, Opus 4.8)
implementation: Codex (GPT-5), with safety and parity corrections recorded below
date: 2026-07-14
implemented_date: 2026-07-14
depends_on_commits: ["2099481c4b8e07f1ba2005958f6ac8b932f13f8c", "de1bdeffc1caa6b446b37c1c1fa67afe000bf985"]
supersedes: "in-set games score prefix added in commit 2099481 — subsumed on BOTH surfaces (iOS Points tab + HTML export Points tab), not kept alongside and not left behind on one of them"
blocked_by: null
scope:
  in_scope:
    - "Packages/DeuceMateCore/Sources/DeuceMateCore/Scoring/ScoringEngine.swift (expose the shared regular-game completion predicate used by live scoring and historical reconciliation)"
    - "Packages/DeuceMateCore/Sources/DeuceMateCore/Stats/PointGamesScore.swift (fix the reconciliation guard — PR 1)"
    - "Packages/DeuceMateCore/Sources/DeuceMateCore/Stats/SetScoreLabel.swift (new — canonical set-score and pre-point game-score formatters, PR 2)"
    - "Packages/DeuceMateCore/Sources/DeuceMateCore/Stats/PointMatchScore.swift (new — PR 3)"
    - "Packages/DeuceMateCore/Tests/DeuceMateCoreTests/{ScoringEngineTests,PointGamesScoreTests,SetScoreLabelTests,PointMatchScoreTests,MatchWebExportTests}.swift"
    - "DeuceMate/DeuceMate/Views/MatchDetailView.swift (Points tab row + header scoreString)"
    - "DeuceMate/DeuceMate/Views/PointsGraphView.swift (selection/highlight summary, both inline + expanded)"
    - "DeuceMate/DeuceMate/Views/PastMatchesView.swift, DeuceMate/DeuceMate/Export/MatchExporter.swift (adopt the shared formatter)"
    - "Packages/DeuceMateCore/Sources/DeuceMateCore/WebExport/{MatchWebViewModel+Build,MatchWebViewModel,MatchWebTemplate}.swift (Points tab parity + schema bump)"
    - "docs/architecture/file-inventory.md (register new Core files)"
  out_of_scope:
    - "Watch app (DeuceMate Watch App) — this is an iOS-archive + export display feature"
    - "Per-point DoublesServer (S1/S2) attribution — PointStat stores only server: Player (the team). Reconstructing the individual doubles server from doublesServiceOrder is a separate change."
open_questions:
  - id: graph-highlight-layout
    question: "Replace cumulative Me/Opp points-won totals in the graph highlight strip, or add the new score line alongside them"
    resolution: "add alongside (second line) — total points won is not derivable from the score string, so it stays"
  - id: current-set-unknown
    question: "When the current set's live segment is unsuppressible (genuinely partial point history), render an em-dash placeholder or omit the segment"
    resolution: "omit the segment and show only the completed sets — after PR 1 this fires only for truly truncated histories, and prior sets remain authoritative. An em-dash reads like a score, not like 'unknown'."
key_data_model_facts:
  - "PointStat.gameScoreAtStart (GameScoreSnapshot: server/returner points + isTiebreak) is captured pre-point in ScoreViewModel.gameScoreSnapshotAtPointStart(), called before updateScore(for:) — capture is correct; the reported issue is a derivation bug, see root_cause_finding"
  - "GameScoreSnapshot is SERVER-RELATIVE (fields are `server`/`returner`, not me/opp). Every read must be re-oriented through point.server, exactly as MatchDetailView.gameScoreLabel(_:server:) does."
  - "PointStat carries server: Player (the team) only — there is NO per-point DoublesServer (PointStat.swift:100-116)"
  - "SetScore.gamesMe/gamesOpponent increment live as each game completes (ScoringEngine.gameWon, ScoringEngine.swift:394-399), not only at set-end — MatchRecord.setScores is live-accurate mid-match"
  - "A set won via a breaker has its games column OVERWRITTEN to the tiebreak-win value: 7–6, not 6–6 (ScoringEngine.swift:304-311). SetScore also carries tieBreakPointsMe/Opponent for the breaker's own score."
  - "setScores.count == completedSets + 1 while a match is in progress (completeSet appends a fresh SetScore for the next set), and == completedSets once the match is over — no trailing empty set (ScoringEngine.completeSet, ScoringEngine.swift:457-500)"
  - "PointGamesScore.atStart(of:setIndex:matchFormat:setScores:) derives a single set's live games score per point via 0-0 boundary detection; its final-point reconciliation now verifies actual game/tiebreak completion before crediting the winner"
root_cause_finding: "There IS a bug, and it is in the derivation, not the capture. PointGamesScore counts a game only when a LATER point in the set resets to 0-0, so after its loop the counters hold the games score at the START OF THE LAST TRACKED POINT — the game that the last point wins is never counted. It then requires that count to equal setScores[setIndex], which is incremented the moment the game is won. For any completed set the last tracked point wins a game (or the breaker), so derived == known - 1 and the guard suppresses the WHOLE SET. Net effect on main: the shipped in-set games score renders for no completed set at all, on either the iOS Points tab or the HTML export. Both original focused tests encoded the wrong invariant (their fixtures set setScores to the count BEFORE the last point), and there was no realistic completed-set web integration assertion. This is the 'the score isn't changing' report that prompted this plan."
implementation_review:
  - "The proposed PR 1 pseudocode was unsafe: blindly crediting the last point's winner could accept a one-game history gap even when that point was mid-game. The implementation credits it only when gameScoreAtStart plus the format rules prove that the point completed a regular game or tiebreak."
  - "Regular-game completion is centralized in ScoringEngine.isRegularGameComplete and used by both live scoring and PointGamesScore reconciliation, preventing the historical derivation from drifting from the rule engine."
  - "The HTML Points tab carried PointVM.server but did not render it. The implementation adds the same tennis-ball + Me/Opp serving indicator there, as well as on iOS."
  - "The opening example's lost-set tiebreak detail was backwards for the recorder perspective; canonical focal-oriented output is 6–7 (7–9), not 6–7 (9–7)."
-->

# Plan: Full Running Match Score + Server Indicator on Points Tab & Graph Highlight

## Context

Commits `2099481` ("feat: show in-set games score in the Points tab list") and `de1bdef`
("fix: suppress games score when tracked points are only a suffix of the set") landed on
2026-07-14 and added an in-set games score (e.g. `"0–1 ·"`) next to each point's existing
in-game tennis score (`"40–0"`) in the iOS Match Stats → Points tab and the HTML export's
Points tab.

Testing that feature against a real multi-set match, the request evolved in two rounds:

1. Initially: *"the score isn't changing"* — prompting an investigation into whether
   `PointStat.gameScoreAtStart` is captured correctly. **It is.** The first version of this
   plan concluded from that there was no bug at all, only missing context. That conclusion
   was wrong: capture is fine, but the *derivation* shipped in `de1bdef` suppresses the
   games score for every completed set. See **PR 1** below — it must land first, or
   everything built on top of it renders nothing.
2. Clarified: the user wants the **full match score as of that point**, not just the current
   set's games — completed prior sets (with tiebreak detail in parens) plus the live score of
   whatever set the point belongs to, e.g.:

   ```
   6–7 (7–9)  6–4  2–2
   ```

   = lost set 1 in a breaker (7–9), won set 2 6–4, and set 3 (here a deciding
   super-tiebreak) currently stands 2–2.

   This subsumes the narrower "games in current set" display, so it **replaces** it — on
   *both* Points tabs. Commit `2099481` deliberately shipped the games score to the iOS list
   and the HTML export together ("so they keep mirroring each other"), and
   `docs/architecture/file-inventory.md` records `PointGamesScore` as shared by both.
   Upgrading only one of them would silently break that contract.

Two more requirements layered on top:

- **Who was serving** on each point, shown on the Points tab row.
- The **points graph**'s tap/drag highlight strip should show the same score representation
  for whichever point is selected, not just the cumulative points-won totals it shows today.

---

## The blocking bug (why PR 1 comes first)

`Stats/PointGamesScore.swift` before this implementation:

```swift
var me = 0, opponent = 0
for (i, point) in points.enumerated() {
    guard let snap = point.gameScoreAtStart else { continue }
    if i > 0, snap.server == 0, snap.returner == 0 {           // a LATER point resetting to 0–0
        if points[i - 1].winner == .me { me += 1 } else { opponent += 1 }
    }
    result[point.id] = GamesScoreSnapshot(me: me, opponent: opponent)
}
let known = setIndex < setScores.count ? setScores[setIndex] : SetScore()
guard me == known.gamesMe, opponent == known.gamesOpponent else { return [:] }   // ← always fails
```

A game is credited only when a **later** point in the set resets to `0–0`. After the loop the
counters therefore hold the games score **at the start of the last tracked point**; the game
that the last point *wins* is never counted. `setScores[setIndex]`, meanwhile, is incremented
the moment that game is won (`ScoringEngine.gameWon`, `ScoringEngine.swift:394-399`).

| Set | Derived after loop | `setScores[i]` | Guard |
|---|---|---|---|
| Completed 6–4 | `5–4` | `6–4` | fails → **whole set suppressed** |
| Completed 7–6 (breaker; games overwritten to 7 at `ScoringEngine.swift:304-311`) | `6–6` | `7–6` | fails → **suppressed** |
| Live set, last tracked point ended a game | `n-1` games | `n` games | fails → **suppressed** |
| Live set, last tracked point mid-game | matches | matches | passes ✅ |

`atStart` returns a non-empty result **only** for a set whose last tracked point is mid-game.
Before this implementation, the iOS archive's in-set games score rendered for no completed set
at all — on the Points tab *and* the HTML export (which shared the helper through
`MatchWebViewModel.pointRows`).

The original focused fixtures in `PointGamesScoreTests` and `MatchWebExportTests` both set
`setScores` to the games count *before* the last
tracked point, and `MatchWebExportTests.makeRecord()` — the one realistic `6–4` / `7–5`
fixture — is never asserted against `gamesScoreLabel`, and the focused fixture encodes the
pre-final-game count. A realistic completed-set assertion would fail.

`PointMatchScore` delegates its current-set segment to `PointGamesScore`, so without the fix
every point of every set in every archived match would render its own set as unknown.

---

## Design decisions

1. **Fix the reconciliation, don't loosen it.** The suffix-suppression contract from `de1bdef`
   is right — a mis-attributed games count is worse than none. Compare like with like: accept
   the derived count, or credit the final tracked point only when its pre-point snapshot and
   the format's regular-game/tiebreak completion rules prove that the point ended the game.
   Blindly crediting any last-point winner is unsafe: a mid-game point plus a one-game stored
   offset would otherwise be accepted. Suffix suppression survives untouched: a resumed set
   with `setScores` at `4–2` and derived `0–0` fails both branches.
2. **One set-score formatter, in Core.** Before implementation, the three formatting rules
   were hand-copied across **five** call sites, which already disagreed with each other:

   | Pre-implementation call site | Emitted |
   |---|---|
   | `Core/WebExport/MatchWebViewModel+Build.swift` (`setScoreString`) | `6–7 (5–7)` — **with** space |
   | `iOS/Export/MatchExporter.swift` | `6–7 (5–7)` — **with** space |
   | `iOS/Views/MatchDetailView.swift` (header `scoreString`) | `6–7(5–7)` — no space |
   | `iOS/Views/PastMatchesView.swift` | `6–7(5–7)` — no space |

   Two of them also re-derive `decidingSetIndex` inline instead of calling
   `MatchFormatConfig.isDecidingSuperTiebreak(setIndex:)` (`ScoreTypes.swift:88-90`). Adding a
   sixth copy for `PointMatchScore` would be the wrong move; promoting one into Core settles
   the spacing question by construction and makes "the Points tab row agrees with the header
   above it" true rather than hoped for. **Canonical form: `6–7 (5–7)`, with the space** —
   it is already the majority, it is what Core and the exporter emit, and it reads better at
   caption size.
3. **Server indicator: 🎾 glyph on the serving side, not a coloured dot.** The first draft
   proposed a `meColor`/`oppColor` dot "matching `LiveScoreboardView.playerRow`". That dot is
   `theme.colors.server` — a dedicated *third* colour shown on whichever player row is serving
   (`LiveScoreboardView.swift:395-406`); identity comes from the **row**, not the colour. A
   points-list row has no row context, so a me/opp-coloured dot would be a new visual language
   *and* colour-only. The real prior art is the watch's `ContentView.serverIndicator`
   (`ContentView.swift:433-457`): a 🎾 glyph plus `.accessibilityLabel("Serving")`. Mirror
   that on both Points tabs. Review found that the HTML view model already carried the
   per-point `server` field, but the HTML Points row did not actually render it; that missing
   rendering is part of this implementation too.
   - The row must gain an `.accessibilityLabel` covering server + score; it has none today.
   - **Doubles shows the serving side, not S1/S2** — `PointStat` stores only `server: Player`.
4. **Live breaker keeps its games.** A non-deciding set inside a breaker renders
   `"6–6 (3–2)"`, not `"TB 3–2"`. The completed form of the same set is `"7–6 (7–5)"`, so this
   keeps the shape stable and the string an actual match score.
5. **When the current set is unknowable, omit it.** After PR 1, suppression only fires for
   genuinely partial point histories (a `ManualMatchEntryView` mid-set reconstruction resumed
   on the watch). Prior *completed* sets come from `MatchRecord.setScores` and stay
   authoritative regardless, so the row still shows them; the live segment is simply absent
   rather than rendered as a placeholder that looks like a score.

### Per-format behaviour (this table is the test matrix)

`playRegularSets == false` formats have no games concept at all; `PointGamesScore` returns
`[:]` for them today and `PointMatchScore` must handle them directly from `gameScoreAtStart`.

| `MatchFormat` | Prior sets | The point's own set |
|---|---|---|
| `.standard` (best-of-3, deciding super-TB) | `6–4`, `7–6 (7–5)` | games `2–2`; in a breaker `6–6 (3–2)`; in the deciding super-TB, raw points `7–5` |
| `.bestOf3FullFinalSet` | same | same, but the final set is a regular set (no super-TB case) |
| `.quick4Games` (win at 3, TB at 2, 1-pt TB) | `3–1`, `3–2 (1–0)` | same rules — the derivation is format-driven, not special-cased |
| `.superTiebreak` (one TB to 10) | none | raw TB points `6–4` |
| `.perpetualSuperTiebreak` (endless TB sets) | prior TB scores `10–8  10–7` | raw TB points of the live breaker |
| `.perpetualPoints` | n/a | n/a — `disablesPointTracking`, so there are no `PointStat`s to render |

---

## Implementation sequence (completed in one change, in this order)

### PR 1 — `[Core] fix: reconcile in-set games score against the game the last point won`

Implemented first because it restores the shared derivation both later stages depend on.

`Stats/PointGamesScore.swift`, replacing the final guard:

```swift
let known = setIndex < setScores.count ? setScores[setIndex] : SetScore()
if me == known.gamesMe, opponent == known.gamesOpponent { return result }

// The final point has no later 0–0 boundary to reveal a completed game. Credit it only
// when its snapshot and the format rules prove that it ended the regular game/breaker.
guard let last = points.last,
      completesGame(last, setIndex: setIndex, matchFormat: matchFormat, setScores: setScores)
else { return [:] }
let finalMe = me + (last.winner == .me ? 1 : 0)
let finalOpponent = opponent + (last.winner == .opponent ? 1 : 0)
guard finalMe == known.gamesMe, finalOpponent == known.gamesOpponent else { return [:] }
return result
```

A breaker-decided set falls out of the same rule: derived `6–6`, the target/lead rule proves
the last point completed the breaker, and crediting its winner yields `7–6` == known. A
separate regression test proves a mid-game last point cannot excuse a one-game mismatch.

**Tests** (write the first one *before* the fix and watch it fail):
- `PointGamesScoreTests`: a realistic completed 6–4 set (points ending with the set-winning
  point, `setScores: [SetScore(gamesMe: 6, gamesOpponent: 4)]`) → non-empty, correct per-point
  values; a set won 7–6 via a breaker; a live set whose last tracked point ended a game.
- `MatchWebExportTests`: assert `matchScoreLabel` with a realistic completed 6–4 fixture.
- Both existing suffix-suppression tests must stay green, unchanged.

### PR 2 — `[Core] refactor: single set-score formatter`

De-duplication plus the intended live-breaker normalization (`6–6 (3–2)` instead of a
separate `TB 3–2` form), and canonical spacing on `6–7 (5–7)`.

- New `Stats/SetScoreLabel.swift` — promote `setScoreString(record:index:focal:)` out of the
  `WebExport` extension (the pre-implementation canonical
  version) into a public Core helper, using `MatchFormatConfig.isDecidingSuperTiebreak(setIndex:)`
  rather than re-deriving the deciding index.
- Adopt it in `MatchWebViewModel+Build`, `MatchExporter`, `MatchDetailView` (header
  `scoreString`), `PastMatchesView` (`scoreString` + `inProgressScoreString`).
- Tests: `SetScoreLabelTests` covering the three rules × the six formats; existing exporter and
  web-export tests pin the output.

### PR 3 — `[Core][iOS] feat: full running match score + server on the Points tab`

**New Core file** `Stats/PointMatchScore.swift`, sibling to `PointGamesScore.swift`:

```swift
public enum PointMatchScore {
    /// The match score immediately before a point: every set played so far, including
    /// the live score of the point's own set.
    public struct Snapshot: Equatable, Sendable {
        /// Completed sets before this point's set, e.g. ["6–7 (7–9)", "6–4"].
        public let completedSets: [String]
        /// The point's own set, live as of this point — e.g. "2–2", "6–6 (3–2)", "7–5".
        /// nil when the set's point history is only a suffix (see PointGamesScore).
        public let currentSet: String?
        /// The raw games tally behind `currentSet`, for callers that want the number.
        public let games: GamesScoreSnapshot?
        /// e.g. "6–7 (7–9)  6–4  2–2" — completed sets only when `currentSet` is nil.
        public var label: String { (completedSets + [currentSet].compactMap { $0 }).joined(separator: "  ") }
    }

    /// Keyed by point id. `points` is the whole match's stats (all sets), in order.
    public static func atStart(of points: [PointStat], record: MatchRecord) -> [PointStat.ID: Snapshot]
}
```

Returning a typed snapshot rather than a pre-joined `[String]` keeps formatting decisions in
the UI (the Points tab can emphasise the live set; the graph reuses the same value), and
follows the standing preference in `TECHNICAL_DEBT.md` #7. Both surfaces key by
`PointStat.ID`, so they provably look up the same value.

Logic:

- Group `points` by `setIndex` (the pattern `MatchDetailView.pointsListSections` already uses).
- `completedSets` for a point in set `i` = `SetScoreLabel` over `record.setScores[0..<i]` —
  always authoritative, independent of how much point history is tracked.
- `currentSet` for set `i`:
  - **No games concept** (`!config.playRegularSets`, or `config.isDecidingSuperTiebreak(setIndex: i)`):
    raw `me–opp` read from the point's own `gameScoreAtStart`, re-oriented through `point.server`.
  - **In a breaker within a regular set** (`gameScoreAtStart.isTiebreak == true`): `"6–6 (3–2)"`
    — games from `PointGamesScore`, breaker points from `gameScoreAtStart`.
  - **Otherwise**: games from `PointGamesScore.atStart(...)`; `nil` if that set is suppressed.
- Points with `gameScoreAtStart == nil` (recorded before per-point snapshotting) get no entry —
  same graceful degradation as `PointGamesScore`.

**New tests** `PointMatchScoreTests.swift` — one per row of the per-format table above, plus:
mid-match on set 2 where set 1 ended in a breaker; a deciding super-tiebreak in progress; an
in-set 6–6 breaker mid-way through a non-deciding set; the suffix case (prior sets still show,
current set omitted); a legacy match with no snapshots.

**`MatchDetailView.swift`**
- `pointsListSections`: replace the per-set `PointGamesScore.atStart` call with one
  whole-match `PointMatchScore.atStart(of: record.stats, record: record)`, threaded into
  `pointRow` as `matchScore: PointMatchScore.Snapshot?` in place of `games:`.
- `pointRow`: new first line `snapshot.label` (caption2, `.tertiary`), above the
  existing in-game-score line, omitted when empty; 🎾 server indicator in the in-game-score
  `HStack`; row `.accessibilityLabel`. `gameScoreLabel(_:server:)`, the `BP`/`2nd` badges and
  the outcome line are unchanged.

**`PointsGraphView.swift`**
- `PointsGraphData`: add `record`-derived inputs to `init`, call `PointMatchScore.atStart`
  once, and in the existing single-pass loop over `stats` populate
  `snapshotByID: [PointStat.ID: PointMatchScore.Snapshot]` plus an `idByIndex: [Int: PointStat.ID]`
  so the x-indexed selection can reach it. Update all three construction sites — each already
  has `record` in scope.
- `PointsGraphSelectionSummary`: add a second line below the existing
  "Pt N · Me X · Opp Y" with the server indicator, the in-game score, and `snapshot.label`.
  Both call sites pass the snapshot for the selected x.
- Lift the recorder-oriented `gameScoreLabel(_:server:)` into Core as `GameScoreLabel` alongside
  `SetScoreLabel`, then use it from the Points list, graph summary, and both web-export point-score
  fields. Review found that the original line reference identified the web chart's distinct
  server–returner helper rather than the actual duplicate; both web fields now use the shared,
  recorder-oriented formatter and canonical en dash.
- Resolve the numbering mismatch by showing `Set N · Pt M` in the graph summary, where `M`
  restarts within each set exactly as it does in the Points tab. The chart's x-axis remains the
  match-wide index.

**HTML export** (parity — the reason `2099481` touched both surfaces)
- `MatchWebViewModel.PointVM`: replace `gamesScoreLabel` with `matchScoreLabel`; bump
  `currentSchemaVersion` 6 → 7.
- `MatchWebViewModel.pointRows`: build it from `PointMatchScore` instead of
  `PointGamesScore`.
- `MatchWebTemplate.pointRow`: render `matchScoreLabel` in the point row.
- Render `🎾 Me` / `🎾 Opp` from the existing `server` field in the HTML point row too.
- `MatchWebExportTests`: update the two `gamesScoreLabel` tests to the new field and add the
  completed-set case.

**Docs**
- `docs/architecture/file-inventory.md`: register `Stats/SetScoreLabel.swift` and
  `Stats/PointMatchScore.swift`; update the `Stats/PointGamesScore.swift` row (it becomes an
  internal building block of `PointMatchScore` rather than a directly-rendered value).

---

## Verification

Automated verification completed on 2026-07-14:

- The new realistic `PointGamesScoreTests` failed against the original guard, then passed after
  the safe reconciliation fix.
- All 378 Core tests pass with `swift test`.
- The `DeuceMate` scheme builds successfully for a generic iOS Simulator destination (including
  its embedded Watch app) with signing disabled.

The following hands-on UI checks remain appropriate release smoke tests:

- Open a real multi-set **completed** archived match's Match Stats → Points tab (the case that was
  previously broken) and confirm: the match-score line is correct across a set boundary and across a
  tiebreak, the server indicator matches who actually served, and the score evolves point-by-point
  within a game and set-by-set across the match.
- Open the same match's Points Graph, drag across points spanning a set boundary, and confirm the
  highlight strip's new line agrees with the Points tab for the same point.
- Export the same match to HTML and confirm its Points tab shows the same string as iOS.

## Notes for reviewing AI models

- The HTML comment block at the top is a structured summary for quick machine parsing. Keep it in
  sync with the prose if you edit this doc — and note that the first version of this doc was
  *confidently wrong* in exactly that field (`root_cause_finding` asserted there was no bug).
  Verify header claims against `file:line` before building on them.
- Flag anything in `open_questions` you'd resolve differently.
- Flag any additional call site that formats a "sets so far" string beyond the five in the
  Design-decisions table — that list came from grepping `tieBreakPoints` / `scoreString` /
  `setScoreString` and may not be exhaustive.
- The `PointGamesScore` bug (PR 1) was found by hand-simulating the loop against a real 6–4 set.
  Derivations reconciled against a stored value are worth checking that way: confirm both sides of
  the comparison are measured at the same instant.

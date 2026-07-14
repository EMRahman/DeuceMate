<!--
machine-readable summary (parse this block first)

status: proposed
author: human + AI pairing session (Claude, Sonnet 5)
date: 2026-07-14
depends_on_commits: ["2099481c4b8e07f1ba2005958f6ac8b932f13f8c", "de1bdeffc1caa6b446b37c1c1fa67afe000bf985"]
supersedes: "in-set games score prefix added in commit 2099481 (subsumed, not kept alongside)"
scope:
  in_scope:
    - "Packages/DeuceMateCore/Sources/DeuceMateCore/Stats/PointMatchScore.swift (new)"
    - "Packages/DeuceMateCore/Tests/DeuceMateCoreTests/PointMatchScoreTests.swift (new)"
    - "DeuceMate/DeuceMate/Views/MatchDetailView.swift (Points tab row)"
    - "DeuceMate/DeuceMate/Views/PointsGraphView.swift (selection/highlight summary, both inline + expanded)"
    - "docs/architecture/file-inventory.md (register new Core file)"
  out_of_scope:
    - "HTML match export Points tab (MatchWebViewModel+Build.swift, MatchWebTemplate.swift, static SVG fallback) — flagged as a deliberate, separate follow-up"
    - "Watch app (DeuceMate Watch App) — this is an iOS-archive-only display feature"
open_questions:
  - id: server-indicator-style
    question: "Colored dot (matches LiveScoreboardView convention) vs text label for who served"
    resolution: "colored dot — proposed default, not yet explicitly confirmed by user"
  - id: graph-highlight-layout
    question: "Replace cumulative Me/Opp points-won totals in the graph highlight strip, or add the new score line alongside them"
    resolution: "add alongside (second line) — proposed default, not yet explicitly confirmed by user"
  - id: parenthetical-spacing
    question: "\"6–7 (9–7)\" (space before paren, per user's own example) vs \"6–7(9–7)\" (existing convention in 4 other call sites)"
    resolution: "space before paren, matching user's literal example; deliberately diverges from existing call sites since this is a new display context"
  - id: html-export-parity
    question: "Should MatchWebViewModel+Build.swift's Points tab mirror this the way it mirrored the in-set games score feature in commit 2099481?"
    resolution: "deferred — not requested, flagged as optional follow-up"
key_data_model_facts:
  - "PointStat.gameScoreAtStart (GameScoreSnapshot: server/returner points + isTiebreak) is captured pre-point in ScoreViewModel.gameScoreSnapshotAtPointStart(), called before updateScore(for:) — confirmed correct, not the source of the reported issue"
  - "SetScore.gamesMe/gamesOpponent increments live as each game completes (ScoringEngine.swift ~line 384-386), not only at set-end — MatchRecord.setScores is live-accurate mid-match"
  - "SetScore also carries tieBreakPointsMe/tieBreakPointsOpponent for the final breaker score of any set that went to one"
  - "PointGamesScore.atStart(of:setIndex:matchFormat:setScores:) already exists (Stats/PointGamesScore.swift) and derives a single set's live games score per point via 0-0 boundary detection, with suppression when the tracked points are a suffix (not the full history) of the set"
root_cause_finding: "No data-capture bug found. The per-point in-game tennis score (0/15/30/40) already updates correctly point-to-point. What was actually missing was match-level context: the games count for the CURRENT set only went in as far as commit 2099481, and there was no view of completed prior sets or a deciding-set tiebreak's live point score. This plan generalizes that into one full running match-score string per point."
-->

# Plan: Full Running Match Score + Server Indicator on Points Tab & Graph Highlight

## Context

Commits `2099481` ("feat: show in-set games score in the Points tab list")
and `de1bdef` ("fix: suppress games score when tracked points are only a
suffix of the set") landed on 2026-07-14 and added an in-set games score
(e.g. `"0–1 ·"`) next to each point's existing in-game tennis score
(`"40–0"`) in the iOS Match Stats → Points tab (`MatchDetailView`'s point
list).

Testing that feature against a real multi-set match, the request evolved in
two rounds:

1. Initially: "the score isn't changing, I just see `0-0 2nd`" — prompted an
   investigation into whether `PointStat.gameScoreAtStart` is captured
   correctly. It is (see `root_cause_finding` above); the real gap was
   missing context, not a stuck value.
2. Clarified: the user wants the **full match score as of that point**, not
   just the current set's games — completed prior sets (with tiebreak detail
   in parens) plus the live score of whatever set the point belongs to, e.g.:

   ```
   6–7 (9–7)  6–4  2–2
   ```

   = lost set 1 in a breaker (9–7), won set 2 6–4, and set 3 (in this
   example a deciding super-tiebreak format) currently stands 2–2.

   This fully subsumes the narrower "games in current set" display just
   shipped, so this plan **replaces** it rather than showing both.

Two more requirements layered on top:

- **Who was serving** on each point, shown on the Points tab row.
- The **points graph**'s tap/drag highlight strip should show the same score
  representation for whichever point is selected, not just the cumulative
  points-won totals it currently shows.

### Prior art already in the codebase

A "sets so far" formatter already exists — duplicated across four call
sites, none of which compute it for a specific *historical* point (only
"final" or "right now"):

| Call site | File |
|---|---|
| `scoreString` (list row) | `DeuceMate/DeuceMate/Views/PastMatchesView.swift` |
| `inProgressScoreString` | `DeuceMate/DeuceMate/Views/PastMatchesView.swift` |
| `scoreString` (header) | `DeuceMate/DeuceMate/Views/MatchDetailView.swift` (~line 156) |
| `scoreString` / `setBySetScores` | `DeuceMate/DeuceMate/Export/MatchExporter.swift` |
| `scoreString` / `setScoreString` | `Packages/DeuceMateCore/Sources/DeuceMateCore/WebExport/MatchWebViewModel+Build.swift` |

All four follow the same three formatting rules, which this plan reuses:

- Completed regular set → `"6–4"`.
- Completed set that went to a breaker → `"6–7(9–7)"` (games, tiebreak
  points in parens).
- A currently-live in-set breaker (not the deciding set) → `"TB 3–2"`.
- A deciding super-tiebreak-only set (`MatchFormatConfig.isDecidingSuperTiebreak`)
  → raw points, no games, no `"TB"` prefix: `"2–2"`.

## Design decisions (open to critique — see `open_questions` above)

1. **Server indicator**: a small dot filled in the server's color
   (`meColor`/`oppColor`), matching the serving-dot already used in
   `LiveScoreboardView.playerRow` (`DeuceMate/DeuceMate/Views/LiveScoreboardView.swift:395-406`).
   Reuses an existing visual language instead of inventing a new one.
2. **Graph highlight**: keep the existing cumulative "Me X / Opp Y"
   points-won badges (still independently useful — total points won isn't
   derivable from the score string), and add the match-score line as a
   second row beneath it, mirroring the Points tab row's two-line layout.
3. **Parenthetical spacing**: `"6–7 (9–7)"` with a space, matching the
   user's own example — diverges intentionally from the no-space convention
   (`"6–7(9–7)"`) used by the four existing call sites above, since this is
   a new, separate display context and reads more clearly at caption size.
4. **Suffix-only sets** (a match resumed mid-set via `ManualMatchEntryView`,
   where tracked points don't start at 0 games): `PointGamesScore` already
   detects and suppresses this per set. Prior *completed* sets are always
   authoritative from `MatchRecord.setScores` regardless of point-history
   coverage, so they still display; only the current set's live segment
   falls back to `"—"` instead of a confidently wrong number.
5. **HTML export parity is deliberately out of scope.** The HTML match
   export's own Points tab mirrors the in-set games score today (commit
   `2099481` touched both surfaces), so there's a real argument for mirroring
   this too — flagged as a follow-up, not silently dropped.

## Implementation

### 1. New Core derivation

**New file:** `Packages/DeuceMateCore/Sources/DeuceMateCore/Stats/PointMatchScore.swift`
— sibling to the existing `Stats/PointGamesScore.swift`.

```swift
public enum PointMatchScore {
    /// Full match score immediately before each point in `points`, as an
    /// ordered list of set-score labels (one per set played so far,
    /// including the point's own set's live score) — e.g.
    /// ["6–7 (9–7)", "6–4", "2–2"]. UI callers join with "  ".
    /// `points` is the whole match's stats (all sets), not a single-set slice.
    public static func atStart(
        of points: [PointStat],
        matchFormat: MatchFormat,
        setScores: [SetScore]
    ) -> [PointStat.ID: [String]]
}
```

Logic:

- Group `points` by `setIndex` (same pattern `MatchDetailView.pointsListSections`
  already uses).
- Prior-set labels for set `setIndex` = `setScores[0..<setIndex]`, each
  formatted with the three rules above — always authoritative since those
  sets are complete, independent of how much point history is tracked.
- The point's own set's live segment:
  - **Deciding super-tiebreak set** (`matchFormat.config.isDecidingSuperTiebreak(setIndex:)`):
    raw `"me–opp"` read directly off that point's own `gameScoreAtStart`
    (mapped through `point.server`) — no games concept, no boundary
    detection needed, no suppression risk.
  - **In-set breaker, not the deciding set** (`gameScoreAtStart.isTiebreak == true`):
    `"TB me–opp"`, matching `PastMatchesView.inProgressScoreString`'s
    existing convention.
  - **Otherwise**: reuse `PointGamesScore.atStart(of:setIndex:matchFormat:setScores:)`
    for that set's points to get the live games tally; `"—"` if suppressed.
- Points with `gameScoreAtStart == nil` (matches recorded before per-point
  snapshotting existed) get no entry — same graceful-degradation as
  `PointGamesScore`.

**New tests:** `Packages/DeuceMateCore/Tests/DeuceMateCoreTests/PointMatchScoreTests.swift`
(mirrors `PointGamesScoreTests.swift`), covering:

- Mid-match on set 2, where set 1 ended in a tiebreak.
- A deciding super-tiebreak set in progress.
- An in-set 6–6 breaker mid-way through a non-deciding set.
- The suffix-only suppression case: prior sets still show, current segment
  is `"—"`.

### 2. `MatchDetailView.swift` — Points tab row

- `pointsListSections` (~line 704): replace the per-set `PointGamesScore.atStart`
  call + `games: GamesScoreSnapshot?` parameter on `pointRow` with one
  whole-match call to `PointMatchScore.atStart(of: record.stats, matchFormat: record.matchFormat, setScores: record.setScores)`,
  threaded into `pointRow` as `matchScore: [String]`.
- `pointRow` (~line 719):
  - New first line: `matchScore.joined(separator: "  ")` (caption2,
    `.tertiary`), above the existing in-game-score line; omitted when empty.
  - Server dot added to the existing in-game-score `HStack`
    (`Circle().fill(point.server == .me ? meColor : oppColor)`).
  - Existing `gameScoreLabel(_:server:)`, `BP`/`2nd` badges, and the
    outcome chip/label line are unchanged.

### 3. `PointsGraphView.swift` — graph highlight

- `PointsGraphData` (private struct, ~line 132): add `matchFormat: MatchFormat`
  and `setScores: [SetScore]` to `init`; call `PointMatchScore.atStart` once
  and, inside the existing single-pass loop over `stats` (~line 208),
  populate two new index-keyed maps alongside `cumulativeByIndex`/
  `scatterByPoint`: `statByIndex: [Int: PointStat]` and
  `matchScoreByIndex: [Int: [String]]` (both keyed by the same 1-based
  `x = i + 1`).
- Update all three `PointsGraphData(...)` construction sites to pass
  `matchFormat: record.matchFormat, setScores: record.setScores` — inline
  `PointsGraphView.body` (~line 1238), `ExpandedPointsGraphView.init`
  (~line 1438), `ExpandedPointsGraphView.rebuildData()` (~line 1449) — all
  already have `record` in scope.
- `PointsGraphSelectionSummary` (~line 1016): add `point: PointStat?` and
  `matchScoreParts: [String]` params; add a second line below the existing
  "Pt N · Me X · Opp Y" line with the server dot + in-game score +
  `matchScoreParts.joined(separator: "  ")`.
- Both `selectionSummary` call sites (inline ~line 1359, expanded ~line 1594)
  pass `point: data.statByIndex[x]` and `matchScoreParts: data.matchScoreByIndex[x] ?? []`.
- `gameScoreLabel(_:server:)` currently lives as a private method on
  `MatchDetailView`; `PointsGraphView` needs identical output so the two
  views agree. Lift it to a shared fileprivate/internal helper at
  implementation time rather than duplicating the formatting logic a third
  time.

### 4. Docs

- `docs/architecture/file-inventory.md`: register the new
  `Stats/PointMatchScore.swift` (CLAUDE.md §6 hard rule for new source files;
  this plan doc itself is not tracked there — confirmed no existing
  `docs/features/*.md` entries appear in that inventory).

## Verification

- `cd DeuceMate/Packages/DeuceMateCore && swift test` (or `xcodebuild test
  -scheme DeuceMateCore -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO`)
  — run the new `PointMatchScoreTests` plus the full suite to confirm no
  regressions in `PointGamesScoreTests` / `MatchStatsSummaryTests` / etc.
- Build the iOS app in the simulator if the toolchain is available; if not,
  say so explicitly rather than claiming it was verified.
- Manually open a real multi-set archived match's Match Stats → Points tab
  and confirm: the match-score line reads correctly across a set boundary
  and across a tiebreak, the server dot matches who actually served, and
  scrolling shows the score evolving point-by-point within a game and
  set-by-set across the match.
- Open the same match's Points Graph, drag across a few points spanning a
  set boundary, and confirm the highlight strip's new line matches the
  corresponding Points tab row exactly for the same point.

## Notes for reviewing AI models

- This doc's HTML comment block at the top is a structured summary intended
  for quick machine parsing (scope, open questions, key facts, root-cause
  finding) — the prose below it is the full human-readable plan. Keep both
  in sync if this doc is edited.
- Flag anything in `open_questions` you'd resolve differently, and flag any
  additional call site that formats a "sets so far" string that isn't listed
  under "Prior art already in the codebase" above — that list was found by
  grepping for `tieBreakPoints`/`scoreString`/`setScoreString` and may not be
  exhaustive.
- Flag if `PointGamesScore`'s existing suppression contract (whole-set
  all-or-nothing) is the wrong granularity to inherit here, given this plan
  now also needs a per-point fallback (`"—"`) rather than an empty dictionary
  entry.

# Feature proposal: Opponent Game Plan

**Status:** Proposed — not implemented or scheduled.  
**Date:** 4 November 2026  
**Surface:** iPhone companion, accessed from an opponent's profile.

**Confirmed scope:** default to the last five eligible matches in full detail;
let the user choose any number up to all available eligible matches; display a
token estimate that updates with the actual selected export contents.

## 1. Purpose

Before playing someone again, turn the recorded history against that opponent
into a practical game plan: what to try on serve and return, what has caused
problems before, and how to adapt if the opening plan is not working.

The evidence should include every selected match's available point detail,
results, playing profiles and explicitly included private notes. Friendly,
league, tournament and practice matches remain distinguishable throughout.
The upcoming match's context should guide the advice: preparing for a league
rematch should foreground league evidence while still learning from friendlies.

“All history” means the history available in the user's phone archive, not the
opponent's career or matches recorded by other people. “Full detail” means all
saved tennis data; it cannot reconstruct points or shot information never recorded.

**Recommended first release:** assemble a detailed, reviewable evidence pack
locally, then use the existing user-initiated AI-app hand-off to request the game
plan. The AI response is read in the chosen AI app. DeuceMate must describe this
as **Prepare Game Plan**, not imply that it generates or receives an answer itself.

## 2. Existing foundations

| Existing capability | How the proposal uses it |
|---|---|
| `OpponentDirectory`, `PlayerRoster`, `OpponentsView` | Select an opponent by stable identity and open the preparation flow from their profile. |
| `MatchTags`, `CompetitionType` | Identify opposition, distinguish match types and competition contexts, and include recorded tennis profiles. |
| `PhoneStatsStore.history` | Read full local records across the phone archive; do not use the watch's rolling history or summary-only mirror as the evidence source. |
| `MatchNotesStore` | Read private notes by match UUID only after explicit inclusion and review. |
| `HeadToHead`, `MatchComparisonFormat` | Keep result scope and wording consistent with the existing opponent screen. |
| `MatchStatsSummary`, `TrendMetric`, `PerformanceTrends` | Reuse factual counts, correct denominators and cross-match pooling rules. |
| `MatchExporter`, `AICoachSheet`, `AICoachLauncher` | Reuse export conventions and explicit copy/share/open actions, adding a distinct pre-match prompt. |

Relevant designs: [match tags, notes and exports](MATCH_TAGS_PLAN.md),
[performance trends](PERFORMANCE_TRENDS_PLAN.md), and
[coaching evidence limitations](COACHING_INSIGHTS_PLAN.md).
The original Trends plan describes its historical starting point; opponent
identity and competition filters now exist, as documented in `CLAUDE.md`.

## 3. User journey

1. Open **Matches → Opponents → [player] → Prepare Game Plan**.
2. Set the upcoming match's competition type and format. Date is optional;
   competition starts unset, so the app does not assume it is another friendly.
   Optional preparation context can describe the surface, conditions or a
   particular concern. These are user statements, not tracked measurements.
3. Review the evidence selection. Default to the latest five completed singles
   matches against this opponent, or all available if fewer than five exist.
   Offer **Last 5**, **Last 10**, **Custom count** and **All matches**, alongside
   individual selection, date filtering and competition filtering. Show selected
   versus available match counts, point and note counts, date range, tracking
   coverage and exclusions. Do not impose a five- or ten-match cap.
4. Optionally include private notes and player names; both start off for every
   session. Review the exact selected notes by match and omit individual notes.
   Preview any new preparation text too. Explain that notes may contain names
   even when the names toggle is off.
5. Preview the evidence overview and complete prompt/file contents. Show the
   upcoming context, Friendly/League/etc. breakdown, detail mode and estimated
   input tokens. Update the estimate when selection, notes or other contents change.
6. Choose **Copy Prompt**, **Share Evidence File**, or an existing AI-app launch
   action. Explain any manual attachment/paste step. Opening an app does not
   mean it received or analysed the evidence.
7. Read the returned game plan in the chosen AI app before the match.

The flow does not create an upcoming `MatchRecord`, start a watch match or
complete an existing checkpoint. A secondary entry from a match's AI Coach can
be added later once the opponent-profile flow is established.

## 4. History selection and relevance

### Match count and ordering

Start each preparation session with **Last 5**. Resolve opposition identity and
eligibility, apply date/competition filters, then take the latest requested number
by `startTime` descending, with UUID as a deterministic tie-breaker. Initially
there is no date or competition filter. Show the resulting date range so five
recent meetings cannot be mistaken for five meetings spread across several years.

Custom count accepts any positive whole number up to the eligible filtered count;
**All matches** selects that entire set, including phone records older than the
watch cap. If fewer matches than a preset requests exist, include those available
and show the actual count. No eligible matches means an explanatory empty state.
Individual additions/removals switch the selection to **Custom selection**.
Filter changes recompute count presets; in Custom selection they intersect the
selected IDs with the filtered eligible set without silently adding other matches.

Only selected matches contribute to the prompt, summaries, head-to-head and notes.
Older unselected matches are not automatically included as background summaries.
Keep full point detail for every selected match unless the user explicitly chooses
Summary only. A larger token estimate must not silently reduce the chosen count.

### Identity and eligibility

- Match the selected player's UUID in opposition tags, never their display name.
  Appearing as the recorder's partner is not evidence of playing against them.
  Use the current roster/forgotten-player rules after renames, merges and forgets.
- Deduplicate by match UUID from the canonical phone archive. Untagged matches
  cannot be automatically assigned; direct the user to Match Info to tag them.
- Completed draws and matches explicitly ended at the current score remain
  eligible, with their recorded status explained. Do not infer completion from
  `iWon != nil`; use the existing lifecycle/result rules.
- In-progress matches are excluded by default. An explicit option can include
  their saved checkpoints as partial evidence, separately from completed results
  and head-to-head. Never describe the checkpoint as the live watch's latest score.
- Score-only/manual matches contribute results and opted-in notes, but not
  invented serve, return or pressure statistics. Partial tracking is visible.
- First release targets singles. List excluded doubles matches and explain why.
  A later doubles mode must select the same partner and exact opponent pair via
  `Matchup`; team-level points cannot establish one opponent's individual weakness.

### Friendly versus league

Keep separate rows for Friendly, League, Tournament, Practice, Unspecified and
unknown future competition values. Unknown is not Friendly or Unspecified.
Do not infer competitive intensity, motivation or nerves from a category alone.

For an upcoming league match, present league evidence first, then other contexts
as supporting or conflicting evidence. If only friendlies exist, say so and
request a provisional plan with early-match checks. Do not apply arbitrary
multipliers such as “a league match counts twice.” All selected evidence stays
available; relevance is expressed through grouping and explicit interpretation.

When more than five completed matches are selected, show both all-selected history
and its latest five completed matches, each with counts and dates. When five or
fewer are selected, show one scope rather than duplicate the same figures.
Recency does not remove older selected full-detail evidence. Show format
differences rather than equating raw game totals across short formats, full sets
and deciding tiebreaks.

An optional later extension could compare the recorder's general recent form
against other opponents. It must be a separately labelled baseline, never evidence
about the selected opponent. It is outside the first release.

## 5. Evidence pack

Build one versioned pack with a stable ordering and session-local references
such as `M001` and `M001-P023`. Keep archive UUIDs in local selection state; the
external pack does not need them. Every numerical observation and quoted note
must be traceable to a match, and point-level claims to point references.

| Section | Contents |
|---|---|
| Preparation brief | Upcoming competition/format/date if provided, recorder perspective, selected opponent profile, reviewed preparation text. |
| Manifest | Pack version, build time, selected date range, match/point counts, partial and score-only counts, exclusions, included names/notes, omitted fields and detail mode. |
| Cross-match evidence | Completed head-to-head within the selection, per-competition and recent/all-selected breakdowns, pooled serve/return/error/pressure figures with raw counts and coverage. |
| Match dossier, repeated for every selected match | Reference, date, competition, format, completion status, score, set breakdowns, available tennis statistics for both sides and data limitations. |
| Private observations | Exact opted-in note per match, quoted as user observations, plus recorded profiles clearly labelled as user-entered. |
| Full point appendix | Every saved point in recorded order, with match/point reference, set, server, winner, outcome, available serve/ending-phase and trustworthy score context. Preserve unclassified rows and missing values. |
| Coaching request | A single pre-match instruction and output structure covering the whole pack. |

Do not concatenate existing complete AI prompts: that repeats post-match
instructions and can pull in unwanted fields. Reuse factual derivation and
formatting beneath a dedicated multi-match builder.

Pool rates as summed numerators divided by summed denominators, not the average
of match percentages. Apply the existing metric-specific availability rules;
zero means a measured zero, while unavailable remains unavailable. Retain
per-match and per-context figures so a long friendly cannot obscure contrary
league evidence in a pooled total. Do not concatenate points across match
boundaries and treat them as one continuous match.

The pack is tennis-only in v1: omit recorded heart rate, steps, calories and
Health-derived insights, including from raw rows and summaries. Free-text notes
can still contain health information; disclose and preview that separately.

### Large histories and prompt size

The user's hypothesis is that many detailed matches can be supplied together.
Support that path, but do not assume a particular AI app's context capacity or
that a launch URL can carry a whole archive.

- **Full detail is the default:** one UTF-8 evidence file containing every
  selected match and saved point, with a short accompanying coaching request.
- Show exact file bytes, match and point counts alongside the required token
  estimator below; it is not a promise that a service will accept the file.
- For large packs, prefer the file/share path over URL prefill. Capability limits
  for copy and launch must be tested during implementation, not guessed here.
- Offer deterministic numbered parts if a single file is impractical. Split at
  match boundaries where possible; an oversized match splits into labelled point
  ranges with its metadata and coverage retained. A manifest identifies all parts.
- The staged prompt asks the AI to acknowledge each part and wait for the final
  synthesis request. Require it to state which match references it actually
  analysed; this is a check, not a guarantee of perfect model recall.
- An optional **Summary only** mode includes every selected match's summary and
  opted-in note but omits raw rows. Label the omission explicitly. Never silently
  truncate matches, point rows or notes to fit a transport limit.

The initial performance fixture should include 100 matches / 20,000 saved points
plus notes. Measure generation time and peak memory on a supported iPhone to
choose transport/part sizes, not an arbitrary match-count cap. Build off the main
actor with progress and cancellation.

### Token count estimator (required in v1)

Show **Estimated input: ~X tokens** beside the selected match count and in the
final preview. Estimate the actual formatted evidence plus the coaching request,
including selected notes, preparation text, names when enabled, legends and
headers. Do not multiply the match count by a fixed per-match allowance: a short
score-only record and a long fully tracked match have very different sizes.

- Recalculate locally whenever any export input changes, including Full detail /
  Summary only. Use the same allowlisted, immutable build snapshot as the preview.
  Clear a stale estimate while rebuilding; cancelled work cannot publish one.
- Use a dependency-free text estimator in Core, calibrated against representative
  prose and point-table fixtures with reference tokenizer counts during development.
  Document the heuristic and measured error; numerical tables and non-English
  notes need their own fixtures. A simple English characters-per-token rule alone
  must not be presented as an exact count.
- Label the result approximate and round to avoid false precision. Explain that
  the receiving model's tokenizer, file handling and conversation overhead can
  change actual usage. Exclude the future answer and hidden reasoning from this
  input estimate; no external service receives text just to estimate its size.
- For split packs show per-part estimates and the total exported input, including
  repeated wrappers. Explain that multi-turn processing can charge for earlier
  conversation context again; this total is not a total-session bill estimate.
- Keep the estimate available before copy/share even when no AI app is installed.
  Expose it to VoiceOver alongside the selected match count.

The owner accepts larger histories when their input cost is modest; token count
is information for choosing the scope, not a mandatory budget gate. Do not promise
“ten matches costs ten cents”: token volume and provider/model rates vary. A live
price catalogue or monetary-cost calculator is outside v1; the export-only flow
does not itself incur an AI API charge.

## 6. Requested game plan

The prompt should ask for a brief courtside checklist first, followed by evidence:

1. **Three priorities:** specific, memorable actions for the upcoming match.
2. **Warm-up checks:** two or three observations to test historical concerns or
   gaps in the evidence, with what to watch for and how it could change the
   opening plan. Keep these compatible with a normal cooperative warm-up.
3. **Serve and return plan:** an opening approach, with references supporting it.
4. **Rally plan:** patterns worth trying, separating measured evidence from notes
   and tentative experiments.
5. **Pressure situations:** practical routines and decisions, supported by recorded
   score context where available.
6. **Plan B:** observable signs that the approach is not working and an adjustment
   to test at a changeover.
7. **Confidence and unknowns:** sample sizes, competition differences, recency,
   contradictions and what to check in the opening games.

For example, if an included private note says the opponent previously struggled
with high backhands, request a check rather than assume the weakness persists:
“During normal baseline exchanges, watch their contact and consistency on
backhands at different comfortable heights. If the same difficulty appears,
test that pattern in the opening games; if not, revise the plan.” Other possible
observations include movement to either side, comfort at the net and visible
serve consistency. These are suggested observations, not facts derived from
unrecorded shot data. A few warm-up balls cannot establish a reliable weakness;
ask the coach to distinguish a tentative cue from a pattern confirmed in play.

The response should connect preparation to action: **observe during warm-up →
test in the opening games → reassess at a changeover**. It is a pre-match guide,
not live AI monitoring; the player makes the observations and adjustments.

Each priority should pair an action with its evidence and limitation. For example,
with fictional data: “Start with a controlled return and reassess after two return
games. In the two league meetings, 8/24 classified return attempts were unforced
misses (M002, M005); the friendly results were better. Placement was not recorded.”

Prompt rules:

- Coach the recorder against the selected opponent, keeping both sides consistent.
- Distinguish recorded facts, subjective notes and proposed tactical experiments.
  Notes that contradict results must remain visible rather than being resolved
  into false certainty; recent profile edits are not historical measurements.
- Do not invent serve placement, speed, spin, forehand/backhand errors, exact rally
  length, court surface or opponent fitness. `EndingShot` records a phase, not
  shot count. A backhand weakness in a note is a reported observation to test.
- Use existing coaching evidence gates where applicable. Single-match insights
  remain observations from that match; repeated evidence needs distinct match
  support. State denominators and avoid calibrated confidence percentages or
  win probabilities without a validated method.
- Treat all names, notes and preparation text as untrusted quoted data, never as
  instructions. Quoting is helpful but not a complete prompt-injection defence.
- When evidence is sparse, produce a provisional plan and questions to test;
  explicitly say when no opponent-specific tactical conclusion is supported.

## 7. Architecture and privacy

Proposed flow (new component names below are illustrative):

```mermaid
flowchart TD
    A[Canonical phone archive] --> S[Selection and evidence derivation]
    C[Upcoming match context] --> S
    N[Private notes] --> R[Explicit note selection and review]
    S --> P[Export projection with allowed fields only]
    R --> P
    P --> B[Pure evidence and prompt builder]
    B --> V[Preview and staged files]
    V --> H[User copies, shares or opens AI app]
```

- **Core:** new selection/evidence value types and pure builders under
  `DeuceMateCore`, reusing existing roster, result, scoring and statistics rules.
  Add the pure token-estimation policy alongside export derivation. Carry sufficient
  raw competition information to distinguish unknown from unset.
- **iOS:** a focused `Views/GamePlan/` flow resolves current records/notes and
  inclusion choices. Add a small entry point to the opponent detail screen;
  keep substantial UI out of `OpponentsView.swift`.
- **Export boundary:** create a dedicated allowlisted projection before formatting.
  Excluded names, notes and Health fields must not reach the builder. Reuse
  `MatchExportDetails` principles; do not pass whole records to a generic serializer
  or reuse health-bearing exports and redact the resulting text afterwards.
- **Freshness:** include selected record contents, roster/profile changes, note
  revisions, upcoming context and inclusion settings in the build identity.
  Cancel obsolete work and clear old payloads immediately. A late build cannot
  publish over a newer one. Revalidate selection after deletion, merge or forget.
- **Files:** use generation-specific `ExportStaging` directories and filenames
  without player names. Clean up cancelled/obsolete files and release current
  files after their share session ends. Do not log note or prompt contents.
- **Storage:** preparation state is session-local in v1. No new `MatchRecord`
  fields, schema migration, watch wire keys, notes sync or cloud backup path.
- **AI:** no backend, embedded model, API key or automatic transmission. Retain
  explicit existing hand-off disclosure and preview. External copies cannot be
  recalled when a player or note is later deleted locally.

Saving or importing an AI-generated plan is a later feature. It needs its own
local storage, deletion and backup policy because the generated text can repeat
private notes. A watch checklist and scheduled match reminders are also deferred.

## 8. Delivery plan

| Stage | Reviewable result |
|---|---|
| 1. Selection and evidence | Core scope rules, competition breakdowns, coverage and stable match references, with fixtures and tests. No UI or AI hand-off yet. |
| 2. Full-detail prompt and files | Allowlisted export projection, pre-match prompt, full/summary modes, calibrated token estimator and deterministic splitting. Privacy, estimate and completeness tests. |
| 3. iPhone preparation flow | Opponent entry point, upcoming context, Last 5/Last 10/custom/all selection, notes review, preview with updating token estimate, cancellation and copy/share/AI launch. |
| 4. Release validation | Device performance, accessibility, fixture-based AI quality review and browser-demo parity for the exposed flow; update user-facing documentation when shipping. |

Stages are implementation slices, not independently sufficient releases. The
first release includes the complete user journey, five-match default, unrestricted
eligible-history selection, full-detail history, token estimates, reviewed notes
and explicit Friendly/League separation.

At implementation time, update `docs/architecture/file-inventory.md` for every
new production source file, the relevant architecture/data-flow diagrams,
`CLAUDE.md`, the user guide and the iPhone demo. This proposal alone changes no
runtime architecture or published website behaviour.

## 9. Acceptance and validation

- Selecting a player defaults to the latest five eligible completed matches,
  or all available when fewer exist. Last 10, arbitrary valid counts, individual
  selection and All matches work across canonical history older than the watch
  cap. Test zero/fewer-than-five/exactly-five/more-than-ten records, tied dates,
  filter-before-limit ordering and filter changes in Custom selection. Unselected
  matches never contribute summaries or notes. Same-name players remain distinct;
  partner appearances, unrelated opponents and mirror duplicates stay excluded.
- Friendly and league results have separate counts/rates and match references;
  an upcoming league match with no league history clearly exposes that gap.
- Old, incomplete, score-only, mixed-tracking, drawn and explicitly stopped
  records produce honest availability and completion labels. Unknown competition
  values remain distinct. Filtering updates every summary and head-to-head scope.
- Full-detail export contains exactly the saved selected point rows, including
  unclassified rows, with no duplicates or omissions across file parts. Summary
  mode and every excluded match/field are disclosed.
- The token estimate covers the actual request plus evidence and updates after
  count/filter/selection changes, note inclusion or edits, preparation edits,
  names toggles and detail-mode changes. Validate its documented error against
  reference prose, table and multilingual fixtures; test stale-build rejection,
  per-part totals and offline availability. No count or detail is silently reduced
  because an estimate is large, and no fixed monetary cost is promised.
- Excluded names and notes never appear in output, temporary files or logs.
  Notes inclusion does not imply anonymization. Structured Health fields and
  derived Health advice never appear in this feature's pack.
- Edits, note clears, tag changes, match deletion, player merges/forgets and
  changed inclusion choices invalidate previews/files; cancelled builds cannot
  reintroduce old data. Unreadable notes report an error, not “no notes.”
- Copy/share works without an AI app installed. Launch failure retains usable
  copy/file options. Large files remain complete, cancellation works, and the UI
  stays responsive on the performance fixture.
- Validate UI with Dynamic Type, VoiceOver, long names and large histories.
  Test pure derivation/export deterministically; run relevant local Swift/iOS
  checks when the toolchain is available, without triggering GitHub Actions.
- Manually evaluate fictional prompts covering rich league history, friendly-only
  history, contradictory notes, sparse tracking and hostile note instructions.
  Returned advice should cite real pack references, acknowledge unknowns, avoid
  invented shot data and provide usable actions, including warm-up checks linked
  to opening-game tests and a reassessment point. Warm-up observations must not
  be presented as proven weaknesses. External model wording is not
  a deterministic unit-test target.

## 10. Decisions to revisit after a prototype

The recommended defaults above are sufficient to build a prototype. Review:

- Estimator accuracy and whether a model-specific estimate would materially help.
- File/copy thresholds and part sizes after device and hand-off testing.
- Whether users need saved in-app plans enough to justify a separate private store.
- Whether doubles preparation and an optional general-form baseline merit the
  next release after the singles evidence and workflow have been evaluated.

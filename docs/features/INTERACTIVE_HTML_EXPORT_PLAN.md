# Interactive HTML Match Export

## Why

After a match, opponents (most of whom don't have DeuceMate installed) want to
see and *interact with* the stats and graphs. Plain-text and AI-prompt exports
already exist, but they can't show the points-momentum chart or let someone poke
at individual points. This feature lets a user export a single finished match as
**one self-contained, interactive HTML file** and share it via the normal iOS
share sheet. The opponent opens it in any browser — phone or laptop — and
explores the full match **offline**: the momentum chart with set bands and
`PointsGraphView`-style counted outcome/Serving/ending-shot scatter pills, a
**Stats/Points tab toggle** and **All/Set N set filter**, the set-filtered TV-style Me-vs-Opp stat
comparison (with points-won bar + duration), a point-by-point list with
reader-relative 🎾 Serving / racquet Receiving status, the recorder's
HR/steps overlays, and an **AI Coach card** (copy the coaching prompt + opt-in
launch links to ChatGPT/Claude/Gemini/…). The page is **reader-framed**
throughout (no perspective toggle), mirroring the iOS archive detail: the share
menu offers **My Perspective** and **Opponent's Perspective**, and each file's
"Me" is whoever it is for — see *Two perspectives* below. *(Schema history: v2
replaced the per-perspective stat cards with the fixed Me-vs-Opp comparison and
dropped the me⇄opponent toggle; v3 added the Stats/Points tabs and the per-set
`filters`; v4 added the optional `aiCoach` block.)* The page still loads **zero
external resources** on open — the AI-app links are user-clicked navigations, not
fetches. *(Later schema history: v5 added per-point step deltas; v6 added in-set
game scores; v7 replaced them with full pre-point match scores; v8 added each
point's tiebreak state for iOS-parity chart bands; v9 added per-player Serving
counts and palette metadata; v10 adds after-point game/match labels for graph inspection while preserving before-point history scores; v11 adds the top-level
`perspective` + `meta.perspectiveNote` and makes every "me" field reader-framed; v12
adds the `promo` block — a "Tracked with DeuceMate" strip at the top of the page linking
to the App Store and the marketing site, since the recipient usually doesn't have the app.)*

Chosen over a hosted "share a link" approach because it needs **no server, no
hosting, no database, no link expiry**, and adds **no networking** to an app that
has none. It fits two existing constraints perfectly: `MatchRecord` is already
`Codable` (one match → self-contained JSON), and the repo already hand-rolls
dependency-free browser JS (`docs/website/assets/watch-demo.js`), so an embedded
zero-library chart renderer honours the hard "Apple frameworks only / zero
third-party dependencies" rule.

## Shape

```
MatchRecord ──► MatchWebViewModel.make(from:maxHR:perspective:)  (pure, Core, tested)
                  │  flattens, framed for the reader (.me or .opponent):
                  │           meta + reader/other stat perspectives
                  │           + reader-framed point list + set bands
                  │           + the recorder's HR/steps blocks
                  ▼
            JSON (sortedKeys) ──► MatchHTMLExporter.html(for:perspective:)  (pure, Core, tested)
                  │  script-safe inject into ▼
            MatchWebTemplate.page(jsonLiteral:)   (HTML skeleton + CSS + SVG/JS,
                  │                                 Swift raw-string constants)
                  ▼
       one self-contained .html String
                  ▼
   MatchDetailView: both files (mine + `_opponent`) built off-thread in `.task`,
   written to temp files, shared via the system share sheet from the
   "Interactive Web Page" submenu (My Perspective / Opponent's Perspective).
```

## Key decisions

- **Where the viewer lives.** The HTML skeleton + CSS + JS are Swift raw-string
  constants (`#"""…"""#`) in `MatchWebTemplate.swift`. Rationale: zero machinery
  — no `project.pbxproj` edit, no `Package.swift` `resources:`, no
  `Bundle.module` lookup that can fail at runtime, and it stays trivially
  unit-testable as a pure string. Rejected (heavier): SPM resources +
  `Bundle.module`; or a generator that compiles a `.js` source into a Swift
  constant + drift-guard test. Revisit only if the JS grows enough that lacking
  JS tooling hurts.

- **Derivation in Swift, not JS.** All stats are computed by `MatchStatsSummary`
  (called twice — `focal: .me` and `focal: .opponent`) and shaped into structured
  rows by `MatchWebViewModel+Build.swift`, mirroring `MatchExporter`'s section
  structure. The browser JS only paints what the JSON gives it. This keeps the
  HTML and text exports in lock-step and the logic testable.

- **Shared Serving categories.** Core's `ServingPointCategory` owns the matching
  rules used by iOS and the Swift-derived HTML counts: distinct first-serve,
  landed-second-serve and double-fault buckets, plus overlapping Ace and Serve FE
  tags. The interactive viewer mirrors those rules only to decide which emitted
  points receive a selected SVG mark; every Me/Opp pill displays its Swift count.
  Serving and Outcomes controls hide when no categorised points exist. Uncategorised
  points are excluded from serve counts and scatter marks in mixed matches; their
  default second-serve flag must not imply a tracked first serve.

- **Two perspectives, one reader-framed shape.** The recorder's page says
  "Lost" when they lost, which is wrong on the page they send the opponent. So
  `make(from:maxHR:perspective:)` builds the page for a *reader*: every "me"
  field — the result badge, score and set lines, `PointVM.server`/`winner`,
  `cumulativeMe`, chips and outcome text, game/match score labels (via the
  `focal:` parameter on `GameScoreLabel` and `PointMatchScore`), the per-set
  comparison and points-won bar — is the reader's side. `perspective: .me` (the
  default) is unchanged from the recorder-only page; `.opponent` swaps every
  side, so the opponent's page says they won. The static fallback and the JS
  paint "Me" as before and need no perspective logic of their own, which is
  what keeps the no-JS preview and the interactive rebuild in agreement; the
  opponent's page adds one `meta.perspectiveNote` line under the header. All
  four static momentum charts stay in both files, drawn from the reader's side.
  Rejected: mirroring the `MatchRecord` itself (a fake persisted model every
  future field would have to remember to flip, with no clean mirror for
  `DoublesServer.partner`).

- **Recorder-only HR.** Heart rate / steps / distance / calories are the
  *recorder's* physiology, carried in the top-level `hr` / `steps` /
  `meta.totals` blocks and on each point in **both** files — the opponent's AI
  prompt finds them useful. In the opponent's file the viewer labels them "Opp"
  (`Opp Heart Rate`, `Opp HR:`, `Opp Steps`, and the `durationRows`), keyed off
  `perspective`. The HR-zone win rates and PulseCoach insights pair the
  recorder's HR with the reader's results, so only the recorder's own page
  carries them (`hr.zones` is empty and `pulseInsights` `nil` in the opponent's)
  — the same line `MatchExporter` draws for the opponent's text export. The
  opponent share discloses as `.opponent` + raw points, which is exactly this
  set (no zones). (Both perspectives are still flattened into the JSON — the
  other side feeds the Me-vs-Opp comparison.)

- **SVG, not Canvas.** A transparent pointer surface uses pointer capture,
  nearest-point hit testing, and an in-place selection rule so click/touch
  dragging scrubs continuously without rebuilding the SVG. The scatter pills
  toggle declarative SVG marks without a canvas redraw loop.

- **Progressive enhancement (no-JS fallback).** The interactive UI is drawn by JS
  into `#root`, but `#root` ships pre-filled with a styled static report
  (`MatchWebStaticFallback.staticFallback`: an "open in a browser" banner, header
  + score, **four server-rendered SVG momentum charts** — one per interactive
  preset (Points Won/Lost outcome scatter, Ending Shots All Won/Lost shot
  scatter), each with its scatter overlay + colour/label/count pills, via
  `staticChartSVG(_:scatter:)` mirroring the JS `buildSVG`/`stepPath`/`symbol`
  geometry — and the **TV-style Me/Opp split-bar comparison** for the whole match
  plus a per-set breakdown, via `pointsWonBar`/`comparisonCard`/`splitBar`
  mirroring the JS bars). Environments that don't run scripts —
  notably the **iOS Quick Look file preview** and many local `file://` opens —
  show that near-complete report instead of a blank page. When the viewer JS runs
  it does `root.innerHTML = ""` and rebuilds, so the fallback is replaced
  seamlessly. (This is why the page is never empty: a 100%-JS-rendered body looked
  blank on iPhone previews.)

- **Share a file, not a link.** The system share sheet shares the generated
  `.html` as a real file (type inferred from the extension). One page per
  reader; the Me-vs-Opp comparison shows both sides at once. The opponent's page
  offers only the opponent AI prompt (no My/Opponent toggle).

- **Colour parity.** `WebExportColors` is the single source of the export's
  palette/symbols (outcome, serving and ending-shot scatter, set bands, me/opponent
  lines, HR/steps), kept in step with `PointsGraphView`. Per-point `isTiebreak`
  state splits regular and TB segments so both interactive and fallback charts
  use iOS's yellow tiebreak wash. The JS never re-encodes colours — Swift emits hex.

## Files

| File | Role |
|---|---|
| `Packages/DeuceMateCore/Sources/DeuceMateCore/WebExport/MatchWebViewModel.swift` | The `Encodable` view-model types + `make(from:maxHR:)`. |
| `…/WebExport/MatchWebViewModel+Build.swift` | Pure derivation (per-perspective sections, counted outcome/Serving/ending-shot pills, points, set bands, HR/steps, formatting). |
| `…/WebExport/MatchWebViewModel+Comparison.swift` | Pure builder for the per-set `filters` + TV-style Me-vs-Opp `comparison` block (mirrors `MatchDetailView`'s split bars). |
| `…/WebExport/MatchWebViewModel+AICoach.swift` | Pure builder for the optional `aiCoach` block (intro copy + AI-app launch list) wrapped around the injected prompt(s). |
| `…/WebExport/MatchWebViewModel+Promo.swift` | The `promo` block: "Tracked with DeuceMate" copy + the App Store and marketing-site URLs, rendered as the first thing on the page — above the header — in both the static fallback and the viewer, so a recipient without the app sees where to get it before anything else. |
| `…/WebExport/MatchWebStaticFallback.swift` | The no-JS `#root` fallback: header + server-rendered SVG momentum charts (`staticChartSVG`) + the TV-style Me/Opp split-bar comparison (`pointsWonBar`/`comparisonCard`/`splitBar`) for the whole match plus a per-set breakdown, so file previews that can't run scripts still show the match. |
| `…/WebExport/WebExportColors.swift` | Palette/symbol single source of truth. |
| `…/WebExport/MatchWebTemplate.swift` | The viewer (HTML/CSS/SVG-JS) as raw-string constants. |
| `…/WebExport/MatchHTMLExporter.swift` | Assembles + script-safely injects the JSON; pure entry point. |
| `DeuceMate/Views/MatchDetailView.swift` | Builds both HTML files off-thread, temp-file writes, the My/Opponent's Perspective share submenu. |
| `Tests/DeuceMateCoreTests/MatchWebExportTests.swift` | View-model shape, mirrored Serving counts/rules/palette, both-perspective consistency, recorder-only-HR, the opponent's reader-framed export (result, scores, points, comparison, static charts, health labels), self-contained HTML and script safety. |

## Verifying

- Core tests (Mac toolchain): `cd DeuceMate/Packages/DeuceMateCore && xcodebuild
  test -scheme DeuceMateCoreTests -destination "platform=macOS"
  CODE_SIGNING_ALLOWED=NO`.
- Generate a sample from a fixture and open it in a browser **in airplane mode**
  to confirm it renders fully offline; exercise the counted scatter pills
  (Outcomes / Serving / Ending Shots), click/touch-drag point scrubbing, point
  popups, HR/steps overlay toggles, the Stats/Points tabs,
  the All/Set N set filter (the comparison + points-won + duration must update),
  the Me-vs-Opp comparison split bars, the point-by-point list, and the AI Coach
  card (Copy Prompt, Show/Hide prompt, My/Opponent toggle). Repeat with the
  opponent's file: it should read Won when the recorder lost, label the health
  overlays "Opp", and offer no zone card or AI toggle. The AI-app links and
  the two promo links (App Store, website) are the only external URLs and must
  open on click only — nothing loads on open.
- `MatchExporter` is iOS-target but pure (`Foundation` + `DeuceMateCore`); the
  AI prompt is generated there and **injected** via
  `MatchHTMLExporter.html(for:aiPromptMe:aiPromptOpponent:)`. The offline test
  (`test_html_withAICoach_addsOnlyOptInLinks`) asserts every `https://` is a
  known AI host or exactly one of the two promo URLs, and that no resource is
  auto-loaded.
- The "self-contained" test asserts no external resource loads (`src=`, `<link`,
  `cdn`) and that every `https://` is exactly a promo URL
  (`assertOnlyOptInLinks`); the only permissible `http://` is the SVG namespace
  identifier `http://www.w3.org/2000/svg`, which is not a network fetch.

## Future ideas (not built)

- A hosted "share a link" variant (viewer on the existing GitHub Pages site in
  `docs/website/`, match data in the URL fragment) if a tappable link is later preferred
  over a file attachment.
- Reusing `MatchWebTemplate`'s renderer on the marketing site demo.

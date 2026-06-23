# Interactive HTML Match Export

## Why

After a match, opponents (most of whom don't have DeuceMate installed) want to
see and *interact with* the stats and graphs. Plain-text and AI-prompt exports
already exist, but they can't show the points-momentum chart or let someone poke
at individual points. This feature lets a user export a single finished match as
**one self-contained, interactive HTML file** and share it via the normal iOS
share sheet. The opponent opens it in any browser — phone or laptop — and
explores the full match **offline**: the momentum chart with set bands and
`PointsGraphView`-style outcome/ending-shot scatter pills, a **Stats/Points tab
toggle** and **All/Set N set filter**, the set-filtered TV-style Me-vs-Opp stat
comparison (with points-won bar + duration), a point-by-point list, recorder-only
HR/steps overlays, and an **AI Coach card** (copy the coaching prompt + opt-in
launch links to ChatGPT/Claude/Gemini/…). The page is recorder-framed throughout
(no perspective toggle), mirroring the iOS archive detail. *(Schema history: v2
replaced the per-perspective stat cards with the fixed Me-vs-Opp comparison and
dropped the me⇄opponent toggle; v3 added the Stats/Points tabs and the per-set
`filters`; v4 added the optional `aiCoach` block.)* The page still loads **zero
external resources** on open — the AI-app links are user-clicked navigations, not
fetches.

Chosen over a hosted "share a link" approach because it needs **no server, no
hosting, no database, no link expiry**, and adds **no networking** to an app that
has none. It fits two existing constraints perfectly: `MatchRecord` is already
`Codable` (one match → self-contained JSON), and the repo already hand-rolls
dependency-free browser JS (`docs/assets/watch-demo.js`), so an embedded
zero-library chart renderer honours the hard "Apple frameworks only / zero
third-party dependencies" rule.

## Shape

```
MatchRecord ──► MatchWebViewModel.make(from:maxHR:)  (pure, Core, tested)
                  │  flattens: meta + both me/opponent stat perspectives
                  │           + perspective-neutral point list + set bands
                  │           + recorder-only HR/steps blocks
                  ▼
            JSON (sortedKeys) ──► MatchHTMLExporter.html(for:)  (pure, Core, tested)
                  │  script-safe inject into ▼
            MatchWebTemplate.page(jsonLiteral:)   (HTML skeleton + CSS + SVG/JS,
                  │                                 Swift raw-string constants)
                  ▼
       one self-contained .html String
                  ▼
   MatchDetailView: built off-thread in `.task`, written to a temp file,
   shared via `ShareLink(item: fileURL)` ("Share Interactive Web Page").
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

- **Recorder-only HR.** Heart rate / steps / distance / calories are the
  *recorder's* physiology. They populate only the `me` perspective and the
  top-level `hr` / `steps` / `meta.totals` blocks; the `opponent` perspective is
  HR-free. Since the page is recorder-framed, HR/steps/PulseCoach always show
  (when present). This mirrors `MatchExporter`'s rule exactly. (Both perspectives
  are still flattened into the JSON — the `opponent` side feeds the Me-vs-Opp
  comparison even though the viewer never renders it as a standalone view.)

- **SVG, not Canvas.** Each point is a DOM element with a tap handler — faithful
  to `PointsGraphView`'s declarative marks — and the scatter pills toggle marks
  without a redraw loop or manual hit-testing.

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

- **Share a file, not a link.** `ShareLink(item: fileURL)` shares the generated
  `.html` as a real file (type inferred from the extension). A single recorder-
  framed page; the Me-vs-Opp comparison shows both sides at once.

- **Colour parity.** `WebExportColors` is the single source of the export's
  palette/symbols (outcome scatter, ending-shot scatter, set bands, me/opponent
  lines, HR/steps), kept in step with `PointsGraphView`. The JS never re-encodes
  colours — Swift emits hex.

## Files

| File | Role |
|---|---|
| `Packages/DeuceMateCore/Sources/DeuceMateCore/WebExport/MatchWebViewModel.swift` | The `Encodable` view-model types + `make(from:maxHR:)`. |
| `…/WebExport/MatchWebViewModel+Build.swift` | Pure derivation (per-perspective sections, scatter-pill counts, points, set bands, HR/steps, formatting). |
| `…/WebExport/MatchWebViewModel+Comparison.swift` | Pure builder for the per-set `filters` + TV-style Me-vs-Opp `comparison` block (mirrors `MatchDetailView`'s split bars). |
| `…/WebExport/MatchWebViewModel+AICoach.swift` | Pure builder for the optional `aiCoach` block (intro copy + AI-app launch list) wrapped around the injected prompt(s). |
| `…/WebExport/MatchWebStaticFallback.swift` | The no-JS `#root` fallback: header + server-rendered SVG momentum charts (`staticChartSVG`) + the TV-style Me/Opp split-bar comparison (`pointsWonBar`/`comparisonCard`/`splitBar`) for the whole match plus a per-set breakdown, so file previews that can't run scripts still show the match. |
| `…/WebExport/WebExportColors.swift` | Palette/symbol single source of truth. |
| `…/WebExport/MatchWebTemplate.swift` | The viewer (HTML/CSS/SVG-JS) as raw-string constants. |
| `…/WebExport/MatchHTMLExporter.swift` | Assembles + script-safely injects the JSON; pure entry point. |
| `DeuceMate/Views/MatchDetailView.swift` | Builds the HTML off-thread, temp-file write, share action. |
| `Tests/DeuceMateCoreTests/MatchWebExportTests.swift` | View-model shape, both-perspective consistency, recorder-only-HR, self-contained-HTML, script-safety. |

## Verifying

- Core tests (Mac toolchain): `cd DeuceMate/Packages/DeuceMateCore && xcodebuild
  test -scheme DeuceMateCoreTests -destination "platform=macOS"
  CODE_SIGNING_ALLOWED=NO`.
- Generate a sample from a fixture and open it in a browser **in airplane mode**
  to confirm it renders fully offline; exercise the scatter pills (Outcomes /
  Ending Shots), point popups, HR/steps overlay toggles, the Stats/Points tabs,
  the All/Set N set filter (the comparison + points-won + duration must update),
  the Me-vs-Opp comparison split bars, the point-by-point list, and the AI Coach
  card (Copy Prompt, Show/Hide prompt, My/Opponent toggle). The AI-app links are
  the only external URLs and must open on click only — nothing loads on open.
- `MatchExporter` is iOS-target but pure (`Foundation` + `DeuceMateCore`); the
  AI prompt is generated there and **injected** via
  `MatchHTMLExporter.html(for:aiPromptMe:aiPromptOpponent:)`. The offline test
  (`test_html_withAICoach_addsOnlyOptInLinks`) asserts every `https://` is a
  known AI host and that no resource is auto-loaded.
- The "self-contained" test asserts no external resource loads (`src=`, `<link`,
  `https://`, `cdn`); the only permissible `http://` is the SVG namespace
  identifier `http://www.w3.org/2000/svg`, which is not a network fetch.

## Future ideas (not built)

- A hosted "share a link" variant (viewer on the existing GitHub Pages `docs/`
  site, match data in the URL fragment) if a tappable link is later preferred
  over a file attachment.
- Reusing `MatchWebTemplate`'s renderer on the marketing site demo.

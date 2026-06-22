# Interactive HTML Match Export

## Why

After a match, opponents (most of whom don't have DeuceMate installed) want to
see and *interact with* the stats and graphs. Plain-text and AI-prompt exports
already exist, but they can't show the points-momentum chart or let someone poke
at individual points. This feature lets a user export a single finished match as
**one self-contained, interactive HTML file** and share it via the normal iOS
share sheet. The opponent opens it in any browser — phone or laptop — and
explores the full match **offline**: all stats, point-by-point, the momentum
chart with set bands, outcome/shot scatter overlays, recorder-only HR/steps
overlays, and a me⇄opponent perspective toggle.

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
  top-level `hr` / `steps` / `meta.totals` blocks; the `opponent` perspective and
  its overlays are HR-free, and the viewer hides HR/steps/PulseCoach when the
  toggle is on "opponent". This mirrors `MatchExporter`'s rule exactly.

- **SVG, not Canvas.** Each point is a DOM element with a tap handler and recolours
  on the perspective toggle without a redraw loop or manual hit-testing — faithful
  to `PointsGraphView`'s declarative marks.

- **Share a file, not a link.** `ShareLink(item: fileURL)` shares the generated
  `.html` as a real file (type inferred from the extension). A single entry, not
  per-perspective — both perspectives live inside the file behind its toggle.

- **Colour parity.** `WebExportColors` is the single source of the export's
  palette/symbols (outcome scatter, ending-shot scatter, set bands, me/opponent
  lines, HR/steps), kept in step with `PointsGraphView`. The JS never re-encodes
  colours — Swift emits hex.

## Files

| File | Role |
|---|---|
| `Packages/DeuceMateCore/Sources/DeuceMateCore/WebExport/MatchWebViewModel.swift` | The `Encodable` view-model types + `make(from:maxHR:)`. |
| `…/WebExport/MatchWebViewModel+Build.swift` | Pure derivation (sections, points, set bands, HR/steps, formatting). |
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
  to confirm it renders fully offline; exercise the perspective toggle, chip
  toggles, point popups, and HR-hidden-on-opponent behaviour.
- The "self-contained" test asserts no external resource loads (`src=`, `<link`,
  `https://`, `cdn`); the only permissible `http://` is the SVG namespace
  identifier `http://www.w3.org/2000/svg`, which is not a network fetch.

## Future ideas (not built)

- A hosted "share a link" variant (viewer on the existing GitHub Pages `docs/`
  site, match data in the URL fragment) if a tappable link is later preferred
  over a file attachment.
- Reusing `MatchWebTemplate`'s renderer on the marketing site demo.

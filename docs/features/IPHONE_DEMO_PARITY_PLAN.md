# iPhone Browser Demo Parity Plan

**Status: implemented and locally verified against the actual iPhone simulator,
Chromium and WebKit. Native captures and verification are recorded below.**

## Native exports, full AI prompts, manual entry and rotation (28 October 2026)

The exported interactive report now packages the actual HTML/CSS/JavaScript
from Core's `MatchWebTemplate`, with a browser adapter for its native view model.
It uses the native promo/header, momentum chart and scatter/serving/shot controls,
HR/Steps overlays, segmented Stats/Points and set filters, comparison split bars,
set-grouped point rows and AI Coach card. Its static preview includes four
scatter presets and per-set comparison bars. Only sample provenance and the
external AI service boundary are adapted: demo AI clicks stay local.

`phone-demo-native-export.js` is generated from the Swift viewer and both native
coaching instruction strings. Run `node scripts/sync-iphone-demo-exports.cjs`
to refresh it and add `--check` to detect drift. The app sheet's Copy Prompt,
prompt preview/download, browser export tools and exported web card all use one
full prompt builder. Every saved point appears exactly once in the Markdown raw
table, including game score, server/winner, second serve, break point,
outcome/shot, recorder HR, per-point steps and cumulative steps. Opponent prompts
retain native recorder-framed raw rows and the explanation of that framing;
recorder-only HR-zone/fitness conclusions stay out of their summary.

Manual Entry now follows `ManualMatchEntryView`: grouped Match rows, trailing
picker values, date/time pills, plus/minus steppers for completed sets and scores,
conditional final-set/tiebreak/doubles controls, native labels, separate footers,
centered title, leading Cancel and grouped Save Match. Validation and discard
semantics are retained. Fresh simulator captures `18`–`19` in
`/tmp/deucemate-native-parity-shots` come from the passing
`NativeDemoParityTests.testManualEntryNativeAppearance` test in
`/tmp/deucemate-native-manual-appearance.xcresult`.

The external **Rotate iPhone** control is available on every screen; the live
scoreboard also has a named rotate button. The frame is genuinely wider than
tall at desktop, mobile landscape and mobile portrait browser sizes. Scores
scale to keep both rows visible; keyboard and swipe scoring/undo still use the
same Watch instance. Escape returns to portrait, and existing popup presenters
track the rotated frame. Route changes clear stale notices from the old screen.

`NativeDemoParitySeedTests.testWriteNativeExportReferences` uses the actual iOS
exporters to write 18 fictional reference reports/prompts under
`/tmp/deucemate-native-export-references` (no archive changes). The test passes
in `/tmp/deucemate-native-export-references.xcresult`. Run it with the same
opt-in `.xctestrun` setup described below, then:

```sh
node scripts/iphone-demo-native-export-qa.cjs /tmp/deucemate-native-export-references /tmp/deucemate-native-parity.json
PLAYWRIGHT_MODULE=/path/to/playwright node scripts/iphone-demo-export-qa.cjs
PLAYWRIGHT_BROWSER=webkit PLAYWRIGHT_MODULE=/path/to/playwright node scripts/iphone-demo-export-qa.cjs
```

The native comparison verifies every cell of **1,608 raw-point rows**, native
point/chip/score fields, and all whole-match/per-set comparison rows in both
perspectives of all nine fixtures. The browser suite checks actual clipboard
contents against all recorded rallies, identical prompt hand-offs, downloaded
native reports with/without JavaScript, grouped manual forms in light/dark mode,
cancellation, and actual keyboard/swipe/undo scoring after rotation. Captures
are saved under `/tmp/deucemate-iphone-qa`. Older QA expectations were deliberately
updated for the native report DOM, segmented set filters, complete Markdown
prompts, score steppers and toolbar Cancel; their behavior assertions remain.
All six browser suites pass in Chromium and WebKit, along with both model
suites, the generated-source drift check and the native export comparison.
AI app demo buttons also copy the complete prompt before showing their local
hand-off notice; clipboard failure keeps the full prompt available for selection.

## Share-menu revision (27 October 2026)

Compared the current `MatchDetailView` with fresh iPhone 17/iOS 27 simulator
captures, rather than deriving the appearance from the existing browser demo.
The report toolbar now opens the native compact 250-point material menu,
anchored at the trailing toolbar control without dimming the report or adding a
sheet title/Done toolbar. Its sections and labels match the app:

- **Interactive** → **Interactive Web Page** opens a layered submenu with
  **My Perspective** / **Opponent's Perspective**. The covered parent is inert;
  Escape/Left returns to it, and a second Escape dismisses the menu.
- **My Stats** / **Opponent's Stats** each offer **Share Summary** and
  **Share Summary + Raw Points**. The latter is absent when no points were saved.
- The health disclosure uses Core's field ordering, copy and perspective/raw
  gates, including the opponent-summary exception, with native side-by-side
  Cancel/Share pills. AI Coach uses the same disclosure with Continue.

Browser-only CSV/prompt downloads and report previews remain available under
**Demo controls → Browser export tools** after opening a match. The native share
menu contains only the app's choices; actual file downloads remain the browser
substitute for the iOS system share sheet.

`NativeDemoParityTests.testShareMenuMatchesNativeExportChoices` passes against
the actual native app (no production changes) and captures the menu, layered
perspectives and disclosure as `15`–`17` in
`/tmp/deucemate-native-parity-shots`; results are retained in
`/tmp/deucemate-native-share.xcresult`. Model checks now pin recorder versus
opponent fields, summary versus raw-point coverage, positive match totals and
health-free exports. Browser popup coverage checks all four native text choices,
both web perspectives, no-point availability, nested keyboard focus and
cancellation, light/dark appearance, viewport containment and the separate
browser tools. Existing download/content assertions follow the intended new UI.
All five browser suites pass in both Chromium and WebKit after this revision,
alongside both dependency-free model suites. The popup suite now exercises 17
presentations, including the separate browser tools. Light/dark share-menu,
perspective, disclosure and score-only captures are saved under
`/tmp/deucemate-iphone-qa/*-popup-export-*` and `*-popup-health-alert.png`.

## Final user-flow audit (27 October 2026)

Independent agents reviewed the current native views, exercised the browser in
Chromium and WebKit, and compared rendered captures. This pass found and fixed
gaps beyond the previous passing suites:

- Settings **Sync Now** now shares the archive handler: it actually copies
  Watch-only records and never claims success for unavailable, pending or failed
  sync. The control follows native activation/pending availability.
- A max-HR override disables and dims the age-derived controls. The resolved
  row uses the native default/resolved label, and Birth Year has an explicit
  accessible name.
- The archive's unavailable-iCloud status opens the native-style medium-height guide, with
  four setup steps and the Health exclusions explanation. Open Settings stops
  at a disclosed simulated hand-off. The footer counts the retained archive.
- Every stored row supports a Delete swipe and confirmation; full swipe only
  executes recoverable Watch removal. Confirmation names the actual storage
  targets and follows the selected row in a native-style material popover with
  explicit Cancel and destructive confirmation. Cancelling preserves every copy.
- Confirming **End at Current Score** returns to Matches. Completed detail
  titles follow the native format/outcome rules; records without points omit
  the Stats/Points switch. Manual Entry uses its native toolbar title and
  clears tiebreak mode when the score leaves 6–6.
- Chart overlays use native category-specific shapes, including cross,
  asterisk, triangle, pentagon, square and plus. The inline and expanded
  inspectors share one set-local point label, one inclusive cumulative-total
  row, filter-aware scatter badges, after-point scores and per-point steps.
  Sparse samples and legacy total-step fallback match the chart's derivation;
  offline reports serialize the same helpers.
- Fresh iOS 27 captures exposed the system-appearance gap: archive, Settings,
  manual entry, reports and their popups now follow light/dark appearance,
  including an already-open presentation. The live court keeps its theme.
  Expanded filters use native ordering, labels and colours; HR is red, Steps
  green, both right axes remain visible, and graph ticks use rounded intervals.
- The score-only graph is a native-style icon/empty-state card. The end-match
  confirmation matches the observed 240-point material popover, without dimming
  or a visible Cancel row; outside tap and Escape cancel. Screen-reader users
  also retain an explicit Cancel action. Archive Stats badges depend on saved
  point history, and storage badges disappear when no watch is paired.

The model suites now pin format titles, all-uncategorized records, native
symbol mappings, after-point suffix and terminal-tiebreak scores, sparse steps
and total-step fallback. Browser state regressions exercise actual Settings
sync outcomes, cloud guidance, each storage type's Delete swipe, override
availability, manual tiebreak reset and completion dismissal. Visual regressions
inspect actual SVG shapes and selected second-set rally totals/scores/steps,
including filter-aware badges and absence of duplicate totals.

### Native simulator evidence

Agents built and exercised the actual app on an iPhone 17 simulator (iOS 27.0,
Xcode 27.1). `scripts/iphone-demo-native-fixtures.cjs` maps the browser's nine
fictional matches to deterministic native UUIDs. The opt-in simulator-only
`NativeDemoParitySeedTests` imports them through `PhoneStatsStore` and verifies
every identity; `NativeDemoParityTests` performs real taps and scrolling through
tracked report/expanded graph/HR/Steps/Points/comparisons, Trends and thin-data
filters, Settings override availability, iCloud guidance, score-only detail and
cancelled/confirmed completion. Captures and accessibility trees live in
`/tmp/deucemate-native-parity-shots` (`01`–`14`); the XCTest results also retain
screenshots. These fresh light-appearance captures informed the final browser
changes above, alongside the existing dark native references.

Final native results: all three parity UI tests pass with zero failures/skips
in `/tmp/deucemate-native-parity-current.xcresult`; the nine-record import
passes in `/tmp/deucemate-native-seed-final.xcresult`. Trends explicitly resets
its persisted type filter to All before verifying populated charts and the
Doubles thin-data state. The separate manual/share flow below also passes.
The existing native archive regression also passes unchanged in
`/tmp/deucemate-native-delete-current.xcresult`: selected-row confirmation
placement, long-press/swipe, full-swipe safety, cancellation, repeat presentation
and deletion retained after relaunch. Its retained screenshots informed the
demo's row-anchored permanent-delete popover.

The native build required one rendering-equivalent SwiftUI compatibility fix:
`HomeButtonStyle` now fills a rectangle before applying opacity, disambiguating
`LinearGradient.opacity` under Xcode 27.1. The existing manual-entry/export UI
test initially failed its old “In Progress — view only on iPhone” expectation.
With explicit user approval, it now checks the current “In Progress” label and
also asserts that End at Current Score is enabled; the complete manual → review
→ AI Coach → system share-sheet flow passes in
`/tmp/deucemate-native-manual-current.xcresult`.

To repeat native QA, use a disposable simulator: the explicitly enabled seed
test replaces its archive with the nine fictional matches. Build the iPhone
test bundle with `xcodebuild build-for-testing` (the normal project/scheme and
simulator destination in `CLAUDE.md`), using a scratch derived-data directory.
Then prepare the test-run file **beside the generated original** so Xcode's
`__TESTROOT__` paths remain valid:

```sh
node scripts/iphone-demo-native-fixtures.cjs /tmp/deucemate-native-parity.json
python3 scripts/iphone-demo-native-config.py /path/to/generated.xctestrun /tmp/deucemate-native-parity.json
```

The config helper prints a new `_NativeParity.xctestrun` path and sets the
explicit `DEUCEMATE_NATIVE_PARITY=1` and fixture path in both test runners.
Run `xcodebuild test-without-building -xctestrun <printed-path>` with the same
simulator destination, `-parallel-testing-enabled NO` and
`-collect-test-diagnostics never`, first selecting
`-only-testing:DeuceMateTests/NativeDemoParitySeedTests`, then
`-only-testing:DeuceMateUITests/NativeDemoParityTests`. Both helpers are opt-in
and simulator-only; ordinary test runs cannot seed an archive.

## Trends, report and expanded graph revision (27 October 2026)

### Phone-bounded popups

Every iPhone app popup now uses one presenter in `phone-demo.js`, with native
sheet, action-sheet, popover, menu, alert and full-screen-cover treatments. All stay
inside both the phone frame and its visible viewport, including when switching
between desktop and narrow layouts. Dimming stays inside the phone; full-screen
covers and native popovers remain undimmed. Modal content has
independent scrolling, browser focus trapping, Escape/Done/Cancel, appropriate
outside-tap/header-swipe dismissal and focus restoration. Resize/scroll and
visual-viewport observers are disposed when the presentation closes. Queued
close events cannot tear down the next presentation.
Size observers reposition the popup without scrolling the phone into view again;
otherwise a page scroll changes the popup height and triggers a scroll back.

AI Coach follows `AICoachSheet.swift`: grouped introduction, perspective Picker
and explanation, one app row per supported demo hand-off, and the Other
copy/share section. Prompt preview is disclosed, and clipboard failure reveals
and selects it. Feedback appears inside the active sheet. Export choices use
native menu rows and previews fill the phone; sharing consent and archive
replacement are in-phone alerts. Replacement still requires the same explicit
destructive choice; the browser `window.confirm` was removed and its regression
test now exercises the in-phone alert instead. Native file chooser/download
operations remain browser-owned service boundaries.

`scripts/iphone-demo-popup-qa.cjs` passes in Chromium and WebKit for all 16
presentations: export menu, health disclosure, report preview, AI Coach, AI prompt
sharing, match actions, permanent deletion, ending a match, connection details,
archive export/import/replacement, cloud restore, iCloud guidance, reset and expanded graph.
It checks containment in the phone and visible viewport, long-menu scrolling,
perspective/prompt correctness, clipboard fallback, local feedback, focus,
dismissal, downloads, cancellation retention and absence of browser alerts.
Wheel gestures also check that webpage scrolling retains its requested position
while the graph moves with the phone at a constant size, and filter scrolling
leaves the chart and page in place, at mobile and desktop widths.
Screenshots are saved as `*-popup-*.png` in `/tmp/deucemate-iphone-qa`.

The detailed UI comparison uses `TrendsView.swift`, `TrendChart.swift`,
`MatchDetailView.swift`, `PulseCoachSection.swift`, `ExpandedPointsGraphView`
and the native captures `docs/app-store-screenshots/iphone-6.9/03-match-stats.png`,
`04-coaching-insights.png`, `06-trends-overview.png` and
`07-trends-serve-return.png`.

- Trends uses the native segmented window/type/display controls, format menu,
  in-progress switch, titles outside cards, monotone line charts with right-side
  axes/dates, metric-specific colours, paired dashed opponent lines, two-column
  toggle legends, static rally legends and W:UE sparkline. Its system appearance
  follows the browser's light/dark preference. The archive's entire Trends card
  opens the screen, with the native thin-data gate.
- Below the report graph: Stats/Points, a Stats-only segmented set picker,
  Duration/activity, scoped Coaching Insights, Pulse Coach with HR-zone and
  timeline charts, then the native Me/Opp split-bar comparison groups. Points
  shows the full history grouped by set, independent of the Stats scope. Share
  and AI actions are in the toolbar; exports no longer fill the report body.
  Per-set activity mirrors Core `SetActivitySplit`, covered by model regressions.
- The expanded graph is positioned inside the iPhone frame, including after a
  viewport change. Its inner surface keeps the full phone height while the outer
  dialog clips to the visible viewport, so page scrolling moves the graph with
  the phone without squeezing its chart. The chart stays fixed above independently
  scrolling native filter/overlay controls. Pointer gestures implement centred
  two-finger pinch,
  drag-to-pan, tap inspection and double-tap reset. Native Points Won/Lost and
  All Won/Lost quick selections are mutually exclusive; filter/overlay choices
  survive reopening while zoom resets. Keyboard zoom/pan and disclosed Graph
  controls remain accessible alternatives. Watch timer-only renders no longer
  replace the phone court or interrupt a gesture.

`scripts/iphone-demo-visual-qa.cjs` checks these layouts and interactions in
Chromium and WebKit, including an actual two-touch Chromium pinch, touch/keyboard
trend inspection, report set scoping, graph pan/reset, filter persistence,
independent filter scrolling, and 320px/mobile/desktop graph containment. It
saves `chromium-*` / `webkit-*` screenshots under `/tmp/deucemate-iphone-qa`.
The existing suites were updated for intentional native UI changes (segments
instead of dropdowns, grouped comparisons instead of tiles, set-grouped Points,
and toolbar sharing), preserving the underlying behavior assertions. An empty
Trends state asserts absence of **charts**, since its format-control icon is SVG.

## Current evidence (26 October 2026)

The visual review was repeated against the saved native iPhone captures and the
current `PastMatchesView`, `MatchDetailView`, `TrendSparkline`, `SettingsView` and
`LiveScoreboardView`. The replica now uses the native toolbar/sheet treatment,
inset-grouped spacing and surfaces, date/status/storage row structure, white
scores with separate result capsules, compact trend sparklines, an unboxed
points-won header, larger inline chart, and two-column theme cards. Settings
headers/footers sit outside the grouped rows. The existing theme-selection QA
now clicks the Clay Court card instead of selecting a dropdown; its setting
assertion is unchanged. Browser share/download and demo controls remain the
documented substitutes for native services.

The Try page now presents both simulators. `phone-demo.js` owns the phone archive
and sends commands to the existing watch scorer; `phone-demo-settings.js`
implements settings, manual entry and demo archive transfer;
`phone-demo-reports.js` and `phone-demo-export.js` provide details and an offline
report using the same graph renderer; `phone-demo-trends.js` ports the native
metric catalogue, pooling, coverage and chart controls. `phone-demo-coaching.js`
ports all eight deterministic Rec Coach and three Pulse Coach rules, including
their data gates, priority, focal-player framing and adjacent-set scope. Phone data persists in a
namespaced browser archive. Device/cloud scenarios and reset live outside the
replica under **Demo controls**.

`node scripts/iphone-demo-model-qa.cjs` passes. It exercises seeded match scoring,
doubles, full-history versus suffix-history score reconstruction, both report
perspectives, generated viewer syntax and escaping, archive validation, all
native trend metric identifiers, filtering before windowing, zero-denominator
pooling, delta orientation, and completed-set/decider/step coverage. This is
model evidence, not browser or visual evidence.

`node scripts/iphone-demo-coaching-qa.cjs` also passes. Synthetic cases exercise
all eleven coaching rules, missing-data gates, focal/set scope and threshold pins
against the current Core sources. Expanded app and offline charts support native
Raw/Smoothed/Per-point-average HR and Cumulative/Per-point Steps modes. Smoothed
HR uses the native five-observation window; per-point averages simulate a Health
fetch locally and explicitly disclose that boundary.

Real browser execution now works with approved sandbox escalation for the macOS
browser process. The existing external Playwright installation is used without
adding a project dependency. No GitHub Actions were triggered.

| Suite | Observed coverage |
|---|---|
| `scripts/iphone-demo-qa.cjs` | Expanded graph filters/zoom/pan/reset; Stats/Points; both offline HTML exports; Trends filtering; gated swipe input sharing the Watch scorer; outcome/shot/double-fault/undo; end confirmation; manual entry and Watch resume; invalid import retention. |
| `scripts/iphone-demo-extended-qa.cjs` | Chromium and WebKit: actual downloads opened with and without JavaScript; set filtering; transparent offline hit targets; touch graph inspection; reduced motion; repeated keyboard scoring/focus; theme/max-HR settings; full-final-set validation; cloud restore; Merge/Replace confirmations; manual JSON export; phone/desktop screenshots. |
| `scripts/iphone-demo-state-qa.cjs` | Chromium and WebKit: recoverable full swipe and keyboard activation; Watch-only storage across timer refresh; activation/sync/error states; corrupt archive preservation; disconnected input; blank dates; deletion across reload/sync; empty archives and reset; Trends modes/coverage; all text and CSV perspectives, in-app report previews; consent Cancel; AI stub and clipboard fallback; failed exports retaining the archive; narrow/landscape layout; manual Cancel/draw; health-free backup and Restore/Not Now; spoken-name settings; visible Watch start/warm-up/server/scoring flowing to iPhone. |
| `scripts/iphone-demo-visual-qa.cjs` | Native Trends controls/charts/light/dark appearance, report group order and set-filtered bars, set-grouped Points, in-phone expanded cover, touch pinch (Chromium), pan/reset, filter persistence and narrow/desktop containment. |
| `scripts/iphone-demo-popup-qa.cjs` | Chromium/WebKit: all 16 phone popup presentations, native AI/export/iCloud guidance layout, device/visible-viewport containment, resizing/scrolling, local dimming/feedback, clipboard fallback, focus, dismissal and cancellation. |

Run the model suites and all five browser suites. The default browser is Chromium;
set `PLAYWRIGHT_BROWSER=webkit` for Safari-engine checks:

```sh
node scripts/iphone-demo-model-qa.cjs
node scripts/iphone-demo-coaching-qa.cjs
PLAYWRIGHT_MODULE=/path/to/playwright node scripts/iphone-demo-qa.cjs
PLAYWRIGHT_MODULE=/path/to/playwright node scripts/iphone-demo-extended-qa.cjs
PLAYWRIGHT_MODULE=/path/to/playwright node scripts/iphone-demo-state-qa.cjs
PLAYWRIGHT_MODULE=/path/to/playwright node scripts/iphone-demo-visual-qa.cjs
PLAYWRIGHT_MODULE=/path/to/playwright node scripts/iphone-demo-popup-qa.cjs
```

The default opens the local Try page; `PLAYWRIGHT_URL` can point to a local HTTP
preview instead. Screenshots are saved to `/tmp/deucemate-iphone-qa`. Native
comparison used the current Swift view/reducer sources and the repository's
`screenshots/setup/iphone-01-matches.png` and `iphone-02-match-detail.png`.
This validates browser behavior and rendering, not a physical iPhone's sensors
or VoiceOver. Browser downloads/preview replace the native share sheet, touch
pinch/pan has accessible keyboard/control alternatives, and device/cloud/AI hand-offs
use the explicitly simulated boundaries below.

Browser testing found and fixed duplicate scoring from keyboard event
propagation, lost scoring focus, archive actions intercepted by toast/header,
Watch-only records immediately auto-syncing, reset being overwritten during
pagehide, date/full-final-set validation, nested report scrolling, graph geometry
and hit-target rendering, gestures interrupted by redraws, export error handling,
and landscape clipping of the second player row.
The original text-length tab assertion was replaced with summary/history and
stable-match checks with explicit user approval under `CLAUDE.md` §3.

Build a browser-based iPhone companion demo alongside the existing watch demo.
It should feel like a believable iPhone app and let a visitor exercise the
major current iPhone workflows with local simulated data. Use the current Swift
implementation below as the behavior source; older iPhone plans describe
features that have since changed.

## Scope and simulation boundary

- Simulate the iPhone app's archive, live scoreboard/input, match detail and
  analysis, trends, manual entry, settings, sharing/export, and confirmation
  flows in the browser. Keep interactions coherent across screens during the
  current page session; resettable seeded data is acceptable.
- Simulate watch connectivity, archive storage, Health measurements, and
  iCloud backup locally. Make connection state, pending sync, errors, and
  unavailable sensors visible where those states affect the interface.
- AI Coach is a stub: show a representative prompt/result or a clear
  simulated hand-off. Do not call an AI service or imply that a real request
  was sent.
- Export actions must work in-browser: generate a self-contained interactive
  match report that can be opened/shared or downloaded, with functional charts,
  filters, and reader perspective. Browser share/download substitutes for the
  native share sheet. Any health-data disclosure must precede a simulated
  export that includes health fields.
- This is a demo, not a replacement for the native app: no real WatchConnectivity,
  HealthKit, native filesystem archive, or iCloud operations. Browser downloads
  and optional browser speech are real. Keep the existing
  watch demo intact and link the two demos where the site navigation allows.

## Current iPhone behavior to mirror

Source references below point to current code, not planned behavior.

| Area | Required browser behavior | Current source anchors |
|---|---|---|
| Archive home | Native-feeling iPhone frame; Trends entry; Live Match row and scoreboard entry; Past Matches rows sorted newest first; settings and manual-entry entry points; match storage badges (both devices, phone only, watch only). | `DeuceMate/DeuceMate/ContentView.swift`; `Views/PastMatchesView.swift` `archiveList`, `rowLocation(for:)`, `rowView(for:location:)` |
| Empty/loading/error | Distinguish connecting, no paired watch, paired watch with no matches, and activation unavailable. Empty states still offer manual entry. A failed/corrupt archive read is an error, never an empty archive; retain visible cached records when sync fails. | `Views/PastMatchesView.swift` `emptyStateView`; `Persistence/PhoneStatsStore.swift` `loadHistory`, `loadCanonicalOnQueue`; `Sync/PhoneMatchSyncService.swift` `finishActivation`, `handle(_:)` |
| Sync/storage actions | Simulate sync-now/pull refresh, pending transfers and reachability. Row actions vary by storage: remove from watch while retaining phone copy, sync to watch, sync to iPhone, or permanent delete. Permanent delete requires confirmation; when on both devices it deletes both and stays deleted (tombstone). | `Views/PastMatchesView.swift` `rowDeleteSwipe`, `rowContextActions`, `permanentDeletePopover`, `performPermanentDelete`; `Sync/PhoneMatchSyncService.swift` `requestFullHistorySync`, `sendDeleteMatchOnWatch`; `Persistence/PhoneStatsStore.swift` `deletePermanently` |
| Live scoreboard | Portrait/landscape scoreboard with server, sets/games/points, tiebreak, second-serve and recent-points momentum cues; close/ended states. When iPhone Input is enabled, swipe up awards Me, down awards Opp, left undoes. Keep the watch as simulated scoring authority and expose delayed/unavailable response states. | `Views/LiveScoreboardView.swift` main `body`, `handleSwipe`, `closeAndRestorePortrait`; `Sync/PhoneMatchSyncService.swift` `sendScoreCommand` |
| Live point categorization | When input and point tracking are active, show outcome choices only valid for the point (double fault only if second serve and server lost), then ending-shot phase where enabled. Double fault skips shot selection; Undo, cancel/back, and watch-echo-driven completion behave as in the phone panel. | `Views/LivePointCategoryPanel.swift` `outcomeStep`, `selectableOutcomes`, `endingShotStep`; `Sync/PhoneMatchSyncService.swift` `sendSelectOutcome`, `sendCommitEndingShot`, `sendCancelOutcomeSelection`, `sendUndoPoint` |
| Match detail | Match title/result/format, score and in-progress label; Points Graph with outcome, serving and ending-shot controls; Stats/Points tabs; per-set filter where applicable; duration, steps/calories, Rec Coach and Pulse Coach sections; comparison rows for Me and Opp. Score-only/manual records explain missing point data. | `Views/MatchDetailView.swift` `body`, `scoreString`, `storageInfoRow`; `Views/PointsGraphView.swift`; `Views/Coaching/RecCoachSection.swift`; `Views/PulseCoach/PulseCoachSection.swift` |
| End in-progress match | Offer “End at Current Score” only for in-progress detail. Confirm before completing; explain it cannot be resumed and a tied score becomes a draw. | `Views/MatchDetailView.swift` `showEndAtCurrentScoreConfirmation`, `endAtCurrentScore()` |
| Trends | Archive trends card opens a full screen. Filters: window (last 5/10/20/all per `TrendWindow.presets`), Singles/Doubles/All, all selectable formats, include in-progress, Rate/Count. Filter before windowing; require minimum matches after filtering; show partial tracking note. Render grouped Errors, Serve & Return, Attack, Rally Depth (including serving-side split), Pressure and Fatigue where covered. Chart controls include legend visibility, selected-match readout, Serve & Return Serves In/Serves Win/Returns Win, rally side/depth modes; sparse or unsupported data is a gap/empty state, not fabricated zero. | `Views/Trends/TrendsSection.swift`; `Views/Trends/TrendsView.swift` `scopedSamples`, `coverageNote(for:)`, `body`, filter pickers; `Views/Trends/TrendChart.swift` `standardBody`, `serveReturnBody`, `rallyDepthByServiceBody`; Core `Stats/PerformanceTrends.swift`, `Stats/TrendMetric.swift` |
| Manual match entry | Form for format (Best of 3 with super-tiebreak decider or full final set), singles/doubles, start date, 0–2 completed sets, current set/game/tiebreak/server/second-serve state. Save stays disabled until validation passes; cancel discards. Saving creates an in-progress local record and simulates sending it to the watch if paired. | `Views/ManualMatchEntryView.swift` `body`, `completedSetSection`, `currentSetSection`, `currentGameSection`, `isValid`, `save()` |
| Settings | Theme palette selection; point-outcome tracking and changeover compass watch settings; spoken-score announcement toggle, player name and test control; iPhone Input; player level; Pulse Coach birth year, max-HR override and value; Sync Now, last-sync/connectivity details and ping; manual archive export/import; support/about/privacy copy. Keep local-only Trends display filters separate from synced settings. | `Views/SettingsView.swift` `watchConfigSection`, `sharedConfigSection`, `aiCoachingSection`, `iPhoneOnlySection`, `pulseCoachSectionView`, `Backup & Transfer` controls; `AppTheme.swift`; `Core/Settings/SettingsCopy.swift` |
| Backup and restore | Simulate iCloud availability/upload/restore prompt states and explain that automatic backup excludes Health measurements. Restore requires an explicit Restore/Not Now choice. Manual archive export/import offers Merge, Replace Archive, Cancel; Replace has an additional destructive confirmation. Invalid/import/export failures are surfaced without clearing the archive. | `Views/PastMatchesView.swift` restore alert and `iCloudGuideSheet`; `Views/SettingsView.swift` file exporter/importer and import confirmations; `Persistence/PhoneStatsStore.swift` restore/import methods; Core `Persistence/ManualMatchArchiveBackup.swift`, `Sync/ArchiveBackupPolicy.swift` |
| Export and AI | Share menu contains interactive HTML report for My Perspective and Opponent's Perspective plus text summary/full/AI exports by perspective. Interactive report has Stats/Points, All/Set N, and outcome/serve/ending-shot chart controls; no-JS/static preview should remain meaningful. AI Coach is a separate sheet with prompt copy and opt-in launch choices. Before sharing raw points or Health fields, show the applicable consent disclosure and honor Cancel. | `Views/MatchDetailView.swift` `ExportMode`, toolbar export menu, `beginShare`, health disclosure alert; `Views/AICoachSheet.swift`; `Export/MatchExporter.swift`; Core `WebExport/MatchWebViewModel.swift`, `MatchHTMLExporter.swift`, `MatchWebStaticFallback.swift` |

## Implementation checklist

- [x] Inspect existing `docs/website/try.html` and watch demo shell/assets; place the iPhone alongside the Watch using the existing scorer.
- [x] Add an iPhone-sized browser shell with navigation, back behavior, scrollable screens, responsive desktop presentation, and shared visual treatment with the watch demo.
- [x] Create deterministic sample archive records covering completed/in-progress, score-only, singles/doubles, varied formats, tracked/untracked points, and partial/missing Health data.
- [x] Implement archive states, storage badges, sync simulation, row action menus, recoverable remove-from-watch, and confirmed permanent deletion.
- [x] Implement live scoreboard and settings-gated swipe input, undo, point categorization, simulated watch acknowledgment, and disconnected/rejected command states.
- [x] Implement match detail graphs, tabs, filters, native comparison/stat and coaching sections, and End at Current Score confirmation.
- [x] Implement Trends filters and charts against the documented behavior, including minimum-sample, partial-tracking, and per-metric coverage states.
- [x] Implement manual-entry validation and save/cancel flow.
- [x] Implement theme/settings controls, sync status, backup/restore states, and archive import/export merge/replace confirmation flows.
- [x] Implement both interactive HTML perspectives and verify their chart controls/set filters work; gate health-bearing sharing behind the simulated disclosure.
- [x] Mark AI integrations clearly simulated; source has no AI-service request or launch. The offline viewer includes a restrictive CSP.
- [x] Check accessibility labels, keyboard operation, reduced motion, narrow/large viewport behavior, and all overlays' close/cancel paths.
- [x] Exercise each checklist flow in a real browser and review rendered screenshots; record intentional native-service substitutions here.

## Verification scenarios

- [x] Fresh install: connecting → no paired watch, and paired/empty archive; manual entry remains reachable in both.
- [x] Sync failure leaves existing archive intact and visibly reports failure; corrupt/unreadable archive is not presented as first-run empty.
- [x] For a row on both devices, full swipe removes watch copy only; context delete asks first and then removes both. Cancel preserves both. Phone-only and watch-only action menus differ correctly.
- [x] Swipe scoring changes a live score only when iPhone Input is enabled; disabled input ignores gestures. Undo and pending point categorization route correctly, including double-fault eligibility and skipped ending-shot step.
- [x] Match detail's graph selection, Stats/Points, set filter, and score-only empty states agree. End-at-current-score Cancel leaves the match live; confirm resolves a tie as draw.
- [x] Trends filter combinations apply before the sample window; fewer than the minimum yields the empty state. Missing Health/rally coverage shows gaps; Count and Rate modes and serve/return/depth controls change the plotted data.
- [x] Manual-entry invalid scores cannot save; valid match can save/cancel and appears in archive, then in simulated watch history if paired.
- [x] Settings visibly affect theme, live input, point tracking, announcements, and Pulse Coach values. Trends UI filters remain independent.
- [x] Restore prompt supports Restore and Not Now; import Merge preserves unrelated rows; Replace requires confirmation; invalid import/export errors retain archive data.
- [x] Each export menu choice yields the right perspective and format. Interactive report controls work offline. Health-bearing share shows disclosure first; Cancel prevents sharing. AI Coach copy works and external hand-off is explicitly simulated.

## Source-of-truth notes

`docs/features/IPHONE_COMPANION_APP_PLAN.md` and other future-work plans are
historical context only. In particular, the current iPhone app has live
scoreboard/input, Trends, manual entry, extensive settings, iCloud backup, and
interactive web export. Re-audit the Swift anchors above when the demo is
changed. The checked items above are backed by the model/browser suites and
rendered-artifact review described above; hardware services remain simulated.

# Screenshots — capture guide

This folder holds the marketing screenshots shown in the [root README](../../README.md).
Most of them (02, 03, 05, 07, 08, 10, 11, 12, 13, 14) are now captured by
reusable automation instead of by hand — see "How to capture" below. The rest
(01, 04, 06) still need a person driving a simulator.

> Capturing requires a Mac with Xcode (watchOS + iOS simulators). It can't be
> done from the web/Linux session that scaffolded this folder.

## The shots

Capture them from a **single, realistic demo match** (e.g. a competitive
three-setter) so scores and stats stay consistent across images. Pick **one
primary theme** — `Classic` or `Hard Court (Night)` — for the hero and watch
shots so the gallery feels cohesive; only `06-themes.png` shows multiple themes.

| # | Filename | What to capture | Screen (source file) |
|---|----------|-----------------|----------------------|
| 1 | `01-hero-watch-iphone.png` | A live-match iPhone landscape scoreboard. (Despite the filename this is currently a solo iPhone shot, not a true watch+iPhone composite — a genuine side-by-side composite needs a paired watch+phone simulator session; see "Live-match shots" below.) | `DeuceMate/DeuceMate/Views/LiveScoreboardView.swift` |
| 2 | `02-points-momentum-graph.png` | iPhone **points-momentum graph** with the heart-rate and steps overlays on, set bands and outcome markers visible. The flagship "wow" shot. | `DeuceMate/DeuceMate/Views/PointsGraphView.swift` |
| 3 | `03-match-stats.png` | iPhone **match stats** tab — Outcome Breakdown (Winners/Unforced Errors/Aggression Index, with raw counts inside the bars). | `DeuceMate/DeuceMate/Views/MatchDetailView.swift` |
| 4 | `04-watch-scoreboard.png` | **Clean solo** Apple Watch live scoreboard mid-match — score rows, momentum strip, heart-rate badge. | `DeuceMate/DeuceMate Watch App/ContentView.swift` |
| 5 | `05-pulse-coach-hr-zones.png` | iPhone **PulseCoach** — win % by HR zone bars + the zone-banded HR timeline. | `DeuceMate/DeuceMate/Views/PulseCoach/PulseCoachSection.swift` |
| 6 | `06-themes.png` | *(Optional, manual only)* a strip of the watch scoreboard across the five court-inspired themes. | `DeuceMate/DeuceMate Watch App/AppTheme.swift` |
| 7 | `07-points-outcomes-won.png` | Expanded Points Graph filtered to the **Points Won** quick-select chip. | `DeuceMate/DeuceMate/Views/PointsGraphView.swift` (`ExpandedPointsGraphView`) |
| 8 | `08-points-outcomes-lost.png` | Expanded Points Graph filtered to the **Points Lost** quick-select chip. | same |
| 10 | `10-ai-coach-prompt.png` | The real generated AI-coach prompt text (top: coaching instructions + match overview + serve/return performance). | `DeuceMate/DeuceMate/Export/MatchExporter.swift` (`aiPromptExport`) |
| 11 | `11-ai-coach-stats.png` | Same prompt, scrolled ~44% (heart-rate analysis, PulseCoach insight, movement & fatigue, set-by-set scores, start of the raw point table). | same |
| 12 | `12-ai-coach-raw-data.png` | Same prompt, scrolled to the bottom — the full point-by-point raw data table. | same |
| 13 | `13-web-export-points.png` | Interactive **HTML web export**, Points tab — the momentum chart, outcome/serving/ending-shot pills, and point-by-point list. | `Packages/DeuceMateCore/Sources/DeuceMateCore/WebExport/` |
| 14 | `14-web-export-stats.png` | Interactive **HTML web export**, Stats tab (the default view) — the Me-vs-Opponent comparison bar, set filters, and match statistics. | same |
| 15 | `15-watch-start-tracking.png` | Watch **start screen** — Start Match above the remembered `Singles · Best of 3` setup row, with the Points / Health / Pulse tracking chips beneath it. Capture with all three reading **On**, which needs HealthKit granted and a birth year (or max-HR override) set. | `DeuceMate/DeuceMate Watch App/HomeView.swift`, `TrackingStatusStrip.swift` |
| 16 | `16-watch-match-setup.png` | Watch **Match Setup sheet** — the Singles/Doubles choice above the format list, with a format selected and its detail line visible. Reached by tapping the setup row in 15. | `DeuceMate/DeuceMate Watch App/HomeView.swift` |
| 17 | `17-watch-changeover-prompt.png` | The **set-complete changeover modal** ("Set complete — players change ends" + OK). The prompt half of the ends-switch story; pairs with 18. Committed for the App Store set, where the prompt → sticky before/after is worth showing; **not** currently used by the site or README, which show only the sticky half. | `DeuceMate/DeuceMate Watch App/ContentView.swift` (`ChangeoverAckOverlay`) |
| 18 | `18-watch-changeover-sticky.png` | The **sticky ends reminder** on the live scoreboard after the modal is dismissed — the banner sits in the momentum strip's slot until the first point of the next set. | `DeuceMate/DeuceMate Watch App/ContentView.swift` |

> **15–18 are manual captures** (see "Manual-only shots" below) — the automation
> drives a live match, not the start screen, the setup sheet, or a set boundary.
> Shoot them at the **same 396×484** size as `04`: the App Store requires one
> consistent Watch size, so moving to 416×496 (Series 10/11) means redoing every
> Watch shot together, not just the new ones.
>
> `17`/`18` each have a **balls-change-ends** counterpart as well as the
> players variant committed here. The site and README use the players pair,
> because "which end do I stand on" is the question the reminder exists to
> answer; reshoot the balls variants only if a surface needs both.

## How to capture

### iOS screens driven by real archive data (02, 03, 05, 07, 08)

These come from `DeuceMateUITests/ScreenshotTests.swift`, which navigates a
real seeded match's detail view and captures via `XCUIScreen.main.screenshot()`
(written straight to a host path — no macOS Screen Recording permission needed,
since the UI-test process runs unsandboxed on the simulator host).

```bash
# 1. Seed a real archive into a booted iPhone simulator's container.
xcrun simctl get_app_container <device-udid> ehsan.DeuceMate data
cd DeuceMate/Packages/DeuceMateCore
swift run DeuceMateArchiveTool seed /path/to/archive.json "<that path>/Library/Application Support" replace

# 2. Run it — opt-in only (DEUCEMATE_CAPTURE_SCREENSHOTS=1), since this test
#    target ships in the default "DeuceMate" scheme and must never run (or
#    fail) as part of an ordinary test pass. DEUCEMATE_TARGET_MATCH_ID
#    defaults to the match used for the currently-committed shots; override
#    it with a UUID from `DeuceMateArchiveTool list` to capture a different one.
cd ../../DeuceMate
DEUCEMATE_CAPTURE_SCREENSHOTS=1 \
DEUCEMATE_SCREENSHOT_OUTPUT_DIR=/tmp/ios-shots \
xcodebuild test -project DeuceMate.xcodeproj -scheme "DeuceMate" \
  -destination "platform=iOS Simulator,id=<device-udid>" \
  -only-testing:DeuceMateUITests/ScreenshotTests
```
Screenshots land in `DEUCEMATE_SCREENSHOT_OUTPUT_DIR` (defaults to a temp
folder if unset) — copy the ones you want into this folder under the names in
the table above.

### AI-coach prompt shots (10, 11, 12)

`AICoachSheet` never renders the prompt text on-screen (it only copies it to
the pasteboard or hands it to a share sheet), so these aren't driven by
tapping through the app. Instead, `DeuceMateTests/AIPromptExportCaptureTests.swift`
calls `MatchExporter.aiPromptExport(for:)` directly — the exact function the
app's "Copy Prompt to Clipboard" button uses — and writes the real generated
text to a file:

```bash
# Opt-in only (DEUCEMATE_CAPTURE_SCREENSHOTS=1) — this target ships in the
# default "DeuceMate" scheme, and DEUCEMATE_ARCHIVE_PATH has no safe default
# (it would otherwise depend on a personal file), so both must be set explicitly.
DEUCEMATE_CAPTURE_SCREENSHOTS=1 \
DEUCEMATE_ARCHIVE_PATH=/path/to/archive.json \
DEUCEMATE_SCREENSHOT_OUTPUT_DIR=/tmp/ios-shots \
xcodebuild test -project DeuceMate.xcodeproj -scheme "DeuceMate" \
  -destination "platform=iOS Simulator,id=<device-udid>" \
  -only-testing:DeuceMateTests/AIPromptExportCaptureTests
```

Then render that text into a presentable page and capture it at three scroll
positions with `DeuceMateWebSnapshot` (it wraps a `.txt` input in a simple
styled dark page automatically):

```bash
cd DeuceMate/Packages/DeuceMateCore
swift run DeuceMateWebSnapshot /path/to/ai-prompt.txt /tmp/prompt-shots 1200 1600 "scroll:44" "scroll:100"
```
Save `00-default.png` / `01-scroll-44.png` / `02-scroll-100.png` as
`10-ai-coach-prompt.png` / `11-ai-coach-stats.png` / `12-ai-coach-raw-data.png`.

### Web export shots (13, 14)

These don't need the app UI at all — two small command-line tools in the Core
package render them directly from a match archive:

```bash
cd DeuceMate/Packages/DeuceMateCore

# 1. List matches in an exported/imported archive (Settings > Backup & Transfer
#    > Export Match Archive on the phone) to pick a good one — a competitive,
#    fully-tracked three-setter shows the export off best.
swift run DeuceMateArchiveTool list /path/to/archive.json

# 2. Render that match's interactive HTML export to a file.
swift run DeuceMateArchiveTool webexport /path/to/archive.json <index> /tmp/match.html

# 3. Screenshot it headlessly. The default view is the Stats tab; passing
#    "Points" also clicks into the Points tab for a second shot.
swift run DeuceMateWebSnapshot /tmp/match.html /tmp/web-shots 1400 1600 Points
```

`DeuceMateWebSnapshot` writes `00-default.png` (Stats tab) and `01-points.png`
(Points tab) — save those as `14-web-export-stats.png` and
`13-web-export-points.png` respectively.

### Live-match shots (01, 04) — the fragile one

Both need a genuinely **live, in-progress** match, since the watch only shows
live matches (not archive history). `DeuceMate Watch AppUITests/LiveMatchScreenshotTests.swift`
drives this via real swipe gestures (the app's whole live-scoring model is
gesture-based — swipe up = point to me, swipe down = point to opponent):

```bash
# Pair a watch simulator with a booted phone simulator so the phone can
# mirror the watch live over WatchConnectivity (only needed for 01).
xcrun simctl pair <watch-udid> <phone-udid>
xcrun simctl boot <phone-udid>
xcrun simctl boot <watch-udid>

# Opt-in only (DEUCEMATE_CAPTURE_SCREENSHOTS=1) — this target ships in the
# default "DeuceMate Watch App" scheme, and this test takes minutes and
# mutates live app state, so it must never run as part of an ordinary pass.
DEUCEMATE_CAPTURE_SCREENSHOTS=1 \
DEUCEMATE_SCREENSHOT_OUTPUT_DIR=/tmp/watch-shots \
xcodebuild test -project DeuceMate.xcodeproj -scheme "DeuceMate Watch App" \
  -destination "platform=watchOS Simulator,id=<watch-udid>" \
  -only-testing:"DeuceMate Watch AppUITests/LiveMatchScreenshotTests"
```

This captures `04-watch-scoreboard.png` directly. For `01`, after the watch
test finishes, check whether the paired phone simulator is mirroring the live
match (`xcrun simctl io <phone-udid> screenshot`) and, if so, capture it there
(rotate to landscape via the Simulator app's Device menu first).

**Known fragility**: the test handles the first-launch HealthKit permission
sheet and a leftover in-progress match from an interrupted prior run, but
simulator-to-simulator WatchConnectivity pairing and long-running watchOS UI
test sessions can both become unreliable within a long session (simulators
occasionally get stuck mid-boot and need a fresh `xcrun simctl shutdown` +
`boot`). If the phone never picks up the live match, ship a fresh `04`
(doesn't need pairing at all) and leave `01` as whatever is already committed
rather than force a broken composite.

### Manual-only shots (06, 15–18, and a true `01` composite)

1. Run the iPhone scheme on a Pro-class iPhone simulator and the watch scheme
   on an Apple Watch simulator; play out a demo match.
2. Save each simulator screen with **⌘S** (Simulator → File → Save Screen).
3. For a true side-by-side hero composite, frame both captures with official
   **Apple device frames** (Apple Design Resources) and place them side by
   side in an image editor — unframed screenshots look unfinished.
4. Save the file here under the exact name in the table above (PNG).

For the Watch feature shots (15–18), the states are reached in this order from
one sitting, which is also the order they tell the story in:

1. **15** — on the start screen before starting anything. Grant HealthKit and
   set a birth year first, or the Health and Pulse chips won't read `On`.
2. **16** — tap the `Singles · Best of 3` row on that screen.
3. **17** — play a set to completion; the changeover modal appears by itself.
4. **18** — tap **OK** on that modal. The banner stays until the first point of
   the next set, so capture before scoring again.

Note that `04` is *not* superseded by `18`: the sticky banner occupies the
momentum strip's slot while it is showing, so `04` remains the shot for the
ordinary scoreboard, with the strip and a richer mid-match score.

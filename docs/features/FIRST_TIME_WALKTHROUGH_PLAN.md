# First-time animated guide

Updated 20 September 2026. This replaces the implemented interactive practice
walkthrough. The watch demonstrates every action for the user; the user only
chooses **Previous**, **Next**, and **Done**.

## Experience

Entry is **Guide → Animated guide**. Eligible first-time users see
**Learn the controls → Show guide / Not now** after normal launch restoration
and authorization presentation finish. Dismissal suppresses later automatic
offers; the guide can still be opened from Guide when the app is idle.

Each situation introduces a concrete example, shows the starting score,
animates the appropriate swipe or tap on the score, then shows the screen response.
Selections, stats scrolling and changeover acknowledgement happen automatically.
The result stays visible until Next or Previous. No exercise completion gate,
lesson list, replay menu, Show me menu, category input or scoring buttons remain.
Navigating back restarts that situation’s demonstration from its fixture.
Next is available immediately, including during animations.

| Situation | Automatic demonstration | Screen response |
|---|---|---|
| You won a point | Swipe up on the score | 0–0 becomes 15–0; Me still serves, now left/ad. |
| Opp won a point | Swipe down | 15–0 becomes 15–15; Me still serves, now right/deuce. |
| Correct a mistake | Swipe left | Undo the last point: back to 15–0, left/ad. |
| You hit a rally ball out | Swipe down; show Unforced Error, then Rally being selected | 0–15; exactly one rally unforced error attributed to Me. Outcome and detailed shot tracking are enabled only in this synthetic example. |
| Mark a second serve | Double tap the score | The second-serve marker appears; the score remains 0–15. |
| Record a double fault | Swipe down on the second serve; show Double Fault being selected | 0–30; exactly one double fault attributed to Me. |
| Find the error stats | Swipe right; automatically scroll Live Stats to Errors | Show the shared Unforced Errors and Double Faults rows: Me 1, Opp 0 each. |
| Win a game | Separate example, Me leads 1–0 and serves at 40–0; swipe up | Games 2–0, points 0–0, Opp serves right/deuce. Show balls-only changeover, automatically acknowledge, return to score. |
| Finish a set 6–3 | Separate example, Me leads 5–3 and serves at 40–0; swipe up | Show player-change message, automatically select OK, hold the sticky Players change ends reminder, then demonstrate the first new-set swipe and its clearing. Opp serves set two. |

The final Ready to play card explains enabling Track point outcome in Settings
for real error statistics. Previous returns to the last situation; Done records
completion and dismisses the guide. Settings remain a separate normal app entry.
Tiebreak and doubles examples are deferred. In a real match, point tracking must
be enabled for outcome recording and the error statistics shown in steps 4–7.

## Implementation

- Core `WalkthroughStep` describes nine situations. `WalkthroughFixtures`
  supplies deterministic, valid singles states and synthetic error data.
- `WalkthroughSession` advances animation beats automatically. It uses the
  existing `ScoringEngine`, changeover events, reminder rules and summaries.
  No expected-action checks, wrong-action hints, practice undo stack,
  interactive category methods, replay or arbitrary chapter-jump APIs remain.
- Each navigation resets the fixture and generation. Delayed callbacks must
  match the current generation; disposed adapters ignore all callbacks.
- The Watch view runs a cancellable task per page/active scene. It pauses in
  background and continues the current situation on return. Navigation and
  dismissal cancel the old task. Completed situations never advance themselves.
- The score uses shared `ScoringScoreRow`, point badge, court and sticky banner.
  Category cards are read-only previews of the fixed Unforced Error / Rally
  example, with a selection marker. They perform no independent category rules.
  Stats use `MatchStatsContent` and automatically scroll to its actual Errors row.
- Previous/Next stay outside the demonstration. No tutorial scoring drag
  recognizer is attached to any view. Live scoring gestures stay unchanged.

## Isolation and first-use eligibility

The guide never instantiates `ScoreViewModel`, constructs a `MatchRecord`,
changes real settings or scores, persists/syncs/exports points, announces on the
phone, starts/stops workouts, accesses heading or requests sensor permissions.
It reads the current theme and owns only disposable scoring snapshots and points.
Normal app-launch authorization and production background/remote work remain
separate. A real session becoming active dismisses the guide.

Entry requires idle match, warmup, pending category and setup state. Automatic
offers additionally require successful state/history reads, empty history,
completed launch presentation and no competing modal. Failed reads never imply
an empty archive. Only `walkthroughOfferSeenVersion` and
`walkthroughCompletedVersion` persist locally. They do not sync or replace
`hasCompletedFirstGame`, remembered setup or tracking/input settings.

## Accessibility and layout

Text names the gesture and explains the visible result. Reduce Motion replaces
the moving touch marker with a static directional arrow, removes animated
transitions/scrolling and preserves the timed sequence and all navigation.
VoiceOver announces the demonstration beat and resulting score/server. Selection
previews are text, not interactive buttons. Previous/Next remain available at
every beat, including stats, category and reminder previews. Long content can
scroll vertically; tutorial navigation never uses horizontal swipes.

Verify on 40 mm and 46 mm Watch simulators. Physical-device VoiceOver,
background/return, denied Health/offline acceptance and observed comprehension
remain manual checks. No GitHub Actions verification.

## Verification

Core tests verify all nine automatic scripts, four gesture directions, score
and server/side results, unforced-error and double-fault attribution and sensor-free points,
game and set boundaries, reminder acknowledgement/clearing, navigation before
completion, previous from Done and stale-callback rejection. The shared live
input-threshold regression test remains intact.

Watch integration tests verify first-use flags and readiness, corrupt/absent/
valid restore outcomes, warmup/pending/live guards, callback disposal and
unchanged production stores, score, settings, sync, workout and heading baselines.
UI tests intentionally replace the former practice-interaction assertions with
all nine automatic demonstrations, visible shared error stats, reminder lifetime,
Previous/Next interruption, Reduce Motion, score bounds, completion/reopening
and absence of lesson/replay menus. Screenshot attachments retain layout evidence.

Local verification on 20 September 2026: Core **604 passed**; Watch unit
**65 passed**; Watch UI **7 passed on 46 mm**, including all three walkthrough
tests; the three walkthrough UI tests also **passed on 40 mm**. iPhone unit
**34 passed**, with the opt-in screenshot helper skipped. Physical-device
VoiceOver and observed comprehension remain manual checks.

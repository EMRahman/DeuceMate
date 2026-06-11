# DeuceMate User Guide

The complete reference for everything DeuceMate does — every gesture, match
format, statistic, coaching rule, and export mode. For a quick overview, see
the [project README](https://github.com/EMRahman/DeuceMate#readme); for help
and FAQs, see the [support page](https://emrahman.github.io/DeuceMate/).

**Contents**

- [Score Tracking](#score-tracking)
- [Match Logistics](#match-logistics)
- [Point Outcome Tracking & Quantitative Analysis](#point-outcome-tracking--quantitative-analysis)
- [AI Coaching Prompts & Further Analysis](#ai-coaching-prompts--further-analysis)
- [Battery Usage](#battery-usage)
- [Padel compatibility](#padel-compatibility)
- [Tricky tennis rules to remember](#tricky-tennis-rules-to-remember)
- [Requirements](#requirements)

---

## Score Tracking

DeuceMate handles the full complexity of tennis scoring automatically so you never have to keep score in your head.

**Gesture-first scoring on Apple Watch**

| Gesture | Action |
|---------|--------|
| Swipe up | Award point to you |
| Swipe down | Award point to opponent |
| Double tap | Toggle second-serve context (yellow "2" badge on server indicator) |
| Swipe left | Undo last point (full game-state rollback) |
| Swipe right | Open live stats view |

**What the app tracks automatically**
- Point scores (Love / 15 / 30 / 40 / Deuce / Advantage)
- Game scores per set
- Set scores across the match
- Tiebreak point sequences with correct serve rotation
- Server identity — rotates automatically after each game and at tiebreak milestones
- Second-serve context — manually marked with a double-tap, drives double-fault detection and coaching metrics
- Break-point status — flagged in real time when the returner can win the game
- Side changes — visual prompt fires at the correct game totals; compass badge shows court bearing

**Match formats**

| Format | Sets | Deciding set |
|--------|------|--------------|
| Standard (Best of 3) | Win 2 | 10-point super tiebreak |
| Best of 3 — Full Final Set | Win 2 | Full set + 7-point tiebreak at 6–6 |
| Super Tiebreak | Single 10-point tiebreak | — |
| Perpetual Super Tiebreak | Ongoing tiebreak series (draw result when tied) | — |
| Quick 4 Games | Abbreviated set format | — |
| Perpetual Points | Continuous point accumulation | — |

Supports both **singles** and **doubles** with full service-order management for both teams.

**Undo stack** — every swipe left rolls back the complete game state: score, server, set progress, break-point flag, and any mid-game categorisation. Undo works across game and set boundaries.

**Persistent state** — the app automatically saves and restores an in-progress match when sent to the background. Pick up exactly where you left off after a notification, wrist-down pause, or overnight.

**Point Confirm Highlight** — when you score on the watch, the point badge blinks twice so a registered point is unmissable. While your finger is still down, the row that will receive the point also lights up green (a win) or red (a loss) so a wrong-direction swipe is visible before you lift (watch and iPhone Input). Toggle in Settings.

**Momentum strip** — an optional 8-slot indicator above the scoreboard colours the last eight points by winner, giving a glanceable read of who is on a run. Mirrored on the iPhone live scoreboard; toggle in Settings.

**Appearance themes** — five court-inspired colour skins (Classic, Clay Court, Grass Court, Hard Court, Hard Court Night) recolour both the watch and iPhone UI; the theme is synced between devices.

---

## Match Logistics

Everything needed to run a match from setup through completion, without paper or a separate scorekeeper.

**Match setup**
- Choose singles or doubles before starting
- Enter player names (used by the iPhone announcement engine for personalised score calls)
- Select the match format that matches your event rules
- Optionally link a HealthKit workout session for fitness data

**Doubles service management**
- Full four-player service rotation tracked automatically
- Receiving team chooses which player receives first at the start of each set
- The app enforces the correct receiver order within each set and rotates the receiving team between sets

**Court and side-change tools**
- Automatic side-change prompts fire at the correct game totals (after game 1, then every odd game)
- Compass badge calibrated to your court heading shows which end you are currently on, so you always know where to go at the changeover

**Health & fitness (optional)**
- HealthKit workout session for tennis activity type
- Live heart rate display during the match
- Calorie, step count, and distance tracking
- Per-set and total match timer showing accumulated active play duration

**iPhone live scoreboard**
- Stadium-style scoreboard mirrors the watch in real time over WatchConnectivity
- Red LIVE badge with blinking indicator; screen stays on so you can leave your phone courtside
- Full set-score history plus current game score in standard tennis notation
- Reachable-session path for instant updates; durable transfer queue for when the phone is backgrounded

**Umpire-style announcements (iPhone)**
- iPhone speaks scores aloud as points are scored — proper tennis terminology ("Love", "Fifteen", "Deuce")
- Uses the player name set on the watch for personalised calls ("Advantage Ehsan")
- Plays while DeuceMate is open on screen — keep the app in the foreground courtside; routes through the iPhone speaker or a connected Bluetooth speaker
- Ducks other audio while speaking each score, then restores it between points

**iPhone Input (spectator scoring)**
- Optional swipe-to-score directly on the iPhone live scoreboard — up for you, down for opponent, left to undo — mirroring the watch gestures
- The same post-point categorisation panel surfaces on the iPhone when outcome tracking is on
- The watch remains the source of truth; iPhone inputs are forwarded to it

**Manual match entry**
- Reconstruct a match that started on paper (or after a watch crash) using a simple form on the iPhone
- Enter completed set scores, the current set/game/tiebreak score, server, and 2nd-serve flag
- The match is saved as in-progress in the archive and pushed to the watch so live scoring can resume there

**Match history**
- Unlimited archive of completed and in-progress matches, stored on-device (no cloud sync)
- Pull-to-refresh; swipe-to-delete individual records
- In-progress matches appear at the top with a live indicator
- Per-match and per-set filtering throughout all statistics views — Duration, Steps, Calories, Coaching Insights, and every Outcome / Serve / Return / Break-point / Pressure / Rally / Score-state / HR section follow the All / Set 1 / Set 2 / Set 3 picker
- Tiebreak set scores render with a superscript parenthetical, e.g. 7‑6(7‑2)

---

## Point Outcome Tracking & Quantitative Analysis

When outcome tracking is enabled, every point is tagged with a cause and an ending shot. This turns a raw score into a structured dataset that drives all of the coaching metrics below.

### Point categorisation workflow

**Step 1 — Choose outcome** (after each point)

| Outcome | When available |
|---------|----------------|
| Winner | Always |
| Forced Error | Always |
| Unforced Error | Always |
| Double Fault | Only when 2nd-serve context is active and server lost |
| (Skip) | Tap to record score without categorising |

**Step 2 — Choose ending shot** (when Detailed Shot Tracking is on; skipped for Double Fault)

The app auto-routes the question and available options based on who served and who won the point, ensuring the shot is attributed to the correct player.

| Server | Who won | Outcome | Question asked | Ending shot options |
|--------|---------|---------|----------------|---------------------|
| Me | Me | Winner | Winning shot? | Ace · S+1 · Rally |
| Me | Me | Forced Error | Shot that forced it? | Serve · S+1 · Rally |
| Me | Me | Unforced Error | Shot of the error? | Return · Rally |
| Me | Opp | Winner | Winning shot? | Return · Rally |
| Me | Opp | Forced Error | Shot that forced it? | Return · Rally |
| Me | Opp | Unforced Error | Shot of the error? | S+1 · Rally |
| Me | Opp | Double Fault | *(n/a)* | *(auto-locked to Serve)* |
| Opp | Me | Winner | Winning shot? | Return · Rally |
| Opp | Me | Forced Error | Shot that forced it? | Return · Rally |
| Opp | Me | Unforced Error | Shot of the error? | S+1 · Rally |
| Opp | Me | Double Fault | *(n/a)* | *(auto-locked to Serve)* |
| Opp | Opp | Winner | Winning shot? | Ace · S+1 · Rally |
| Opp | Opp | Forced Error | Shot that forced it? | Serve · S+1 · Rally |
| Opp | Opp | Unforced Error | Shot of the error? | Return · Rally |

S+1 is the server's third shot (serve plus one). It appears only when the server's shots are being attributed.

After categorisation, the score updates, the point is saved to the match record, and game/set/match completion is checked.

### Statistics computed per match (and per set)

All metrics are available filtered to an individual set or across the full match.

**Points summary**
- Total points played, points won, points lost (with percentages)

**Serve performance**
- Service points win %
- 1st serve in % and win %
- 2nd serve in % and win %
- Double faults (count and as % of second-serve opportunities)

**Return performance**
- Return win % versus opponent's first serve
- Return win % versus opponent's second serve

**Break points**
- Opportunities as returner and conversion rate
- Break points faced as server and save rate

**Error analysis**
- Winners, unforced errors, forced errors, double faults (yours and opponent's)
- Self-inflicted losses % — own errors (UE + DF) as a share of points lost
- Winners-to-Unforced-Error ratio (W:UE) — target >1.0
- Aggression Index — winners as a share of all aggressive outcomes (W + UE)

**Pressure vs. normal points**
- Win rate on "big" points (break points, deuce/advantage games, tiebreak points) versus all other points

**Rally depth breakdown**
- Win rate at each rally length stage: Serve (shot 1) / Return (shot 2) / S+1 (server's 3rd) / Rally (4+ shots)
- Shows where in the rally you win or lose points most often

**Score-state win rates**
- Win rate at 30-All
- Win rate at Deuce / Advantage
- Win rate in tiebreak points

**Heart rate analysis (when HealthKit active)**
- Win rate by HR zone (Zone 1 Recovery through Zone 5 Max)
- HR timeline correlated with point outcomes

**Set durations**
- Elapsed time per set alongside the game score

### Automated coaching insights (RecCoach)

After a match with sufficient outcome data (≥ 20 categorised points), the engine generates up to three prioritised plain-English observations, chosen from these eight rules:

1. **Self-inflicted loss share** — fires when ≥55% of points lost were unforced errors or double faults; calls out reliability as the primary lever
2. **Per-set UE drift** — compares unforced-error rate between consecutive sets; surfaces fatigue-driven shot-selection changes
3. **Double-fault leakage** — flags when double faults exceed 0.5 per service game, framing each one as a free point given away
4. **Pressure-point drop** — detects a ≥20-percentage-point win-rate gap between normal points and "big" points (break / deuce / tiebreak) and prescribes simplifying shot choice under pressure
5. **Rally-length signal** — compares win rates at S+1 vs. extended rallies; recommends finishing points earlier when the gap is ≥15 percentage points
6. **Second-serve vulnerability** — flags when the first-serve win rate is ≥20 percentage points above the second-serve win rate, suggesting a slower spin-heavy second serve
7. **Return unforced errors** — fires when ≥40% of your return-game losses were return UEs, recommending a safer deep crosscourt return target
8. **Set-duration energy decline** — detects a ≥15% win-rate drop in a set following one that lasted more than 30 minutes

The insights respect the active set filter on the iPhone match detail — choose Set 1, Set 2, … to scope the engine to that set and to the transition into it, or All for the whole-match view.

### PulseCoach insights (heart-rate gated)

When ≥10 heart-rate tagged points are available, the engine generates up to three HR-correlated observations:

1. **Zone delta** — identifies the HR zone where you win most versus least, when the gap is ≥15 percentage points across zones with ≥5 points each
2. **Break-point HR spike** — flags when you lose ≥60% of break points played with a HR above the median, pointing to a measurable pressure response
3. **Late-match decline** — catches a ≥15% win-rate drop in the second half of the match combined with a ≥10 bpm average HR climb

### Points graph

An interactive timeline view on iPhone plots cumulative points for both players across the whole match, with the following overlays and controls:

- **Per-player outcome scatter** — independently toggle Winner / Unforced / Forced / Double Fault dots for you and your opponent
- **Per-player ending-shot scatter** — independently toggle Serve / Return / S+1 / Rally dots for you and your opponent
- **Heart-rate overlay** — when HealthKit was active, BPM is plotted as a secondary axis (toggle on/off)
- **Steps overlay** — real per-point cumulative step counts plotted as a secondary axis (toggle on/off)
- **Set-boundary bands** — alternating background bands mark where each set begins and ends; tiebreak segments are visually distinct
- **Touch-to-inspect** — tap or drag along the chart to see the score, scatter markers, and overlay values at that point
- **Expandable fullscreen view** — tap the expand icon for a fullscreen chart with pinch-to-zoom and pan; landscape orientation is enabled inside this view for a wider field of view

---

## AI Coaching Prompts & Further Analysis

DeuceMate exports match data in a format built for feeding directly into any large-language-model AI tool for deeper, conversational coaching analysis that goes beyond the automated insights.

### Export formats

Three export modes are available from the match detail view:

| Mode | Contents | Best for |
|------|----------|----------|
| Summary only | Match overview + all computed stats | Quick review or sharing a score card |
| Full export | Summary + raw point-by-point table | Spreadsheet analysis, archiving |
| AI coaching prompt | Structured coaching prompt + summary + raw point table | Pasting into ChatGPT, Claude, Gemini, or any other AI |

### What the AI prompt contains

The AI coaching prompt export is a self-contained document structured for immediate use with any GenAI tool. It includes:

- A **system-level coaching brief** instructing the AI to act as an experienced recreational-tennis coach, scoped to the NTRP band you set in iPhone Settings (Beginner 2.5–3.0, Intermediate 3.0–3.5, or Club 3.5–4.5)
- A **structured analysis framework** specifying four required output sections:
  1. Biggest Weakness — the single most impactful problem, identified using the match numbers
  2. Hidden Strength — one thing that is genuinely going well, cited with specific stats
  3. Two Tactical Adjustments — practical in-match changes requiring no extra practice (based on serve win rates, rally depth data, pressure-point performance)
  4. One Practice Drill — a single targeted drill for the biggest weakness, doable on a public court without a coach
- The full **match overview** (date, format, result, score, duration, steps, calories, distance)
- All **computed statistics sections** (serve, return, break points, error analysis, pressure points, rally depth, score states, HR zones if available)
- The raw **point-by-point table** (when outcome tracking was on) so the AI can spot patterns — error clusters in specific games, performance at key scores, serve/return trends — that summary stats alone miss

The tone instruction in the prompt ("Direct and specific. Use the numbers. Skip any section where the data shows '—' or is missing.") prevents the AI from generating generic advice disconnected from your actual match data.

### Dual-perspective analysis

Every AI export can be generated from two perspectives:

- **My Stats** — the standard view, coaching you as the match recorder
- **Opponent's Stats** — flips the perspective and relabels all metrics so the output reads as coaching for your opponent; designed to be shared with them directly

This makes it straightforward to give your opponent useful feedback after a practice match using data collected from a single watch.

### One-tap AI app launch

The AI Coach sheet on iPhone detects which AI apps are installed and shows them as one-tap launch targets:

- Supported apps: ChatGPT, Claude, Gemini, Perplexity, Copilot, Poe, Grok
- Apps that support a prompt URL parameter receive the coaching prompt pre-filled and ready to submit
- All others copy the prompt to the clipboard and open the app, ready to paste
- A fallback system share sheet is always available for any app not in the detected list

The full prompt is also always copyable to the clipboard as a backup.

### Prompting tips for deeper analysis

The exported AI prompt is a starting point. After the AI returns its initial analysis you can continue the conversation with follow-up questions based on what the data actually showed:

**Serve strategy**
- "My first-serve win rate is [X]% but my second-serve win rate is only [Y]%. What is the optimal risk balance for my serve speed and placement?"
- "I had [N] double faults in [G] service games. What are two cues I can use to keep the ball in play on the second serve under pressure?"

**Return game**
- "I return [X]% of first serves but [Y]% of second serves. Does that ratio suggest a technique problem or a tactical one?"
- "My break-point conversion was [X]%. What mental or tactical routines do ATP/WTA players use to stay composed on break points?"

**Rally tactics**
- "My win rate at Serve+1 was [X]% versus [Y]% in long rallies. Design a two-week practice plan to close that gap."
- "I have a [Z]-point tiebreak win rate. What are the three highest-leverage points in a tiebreak and how should I approach each?"

**Physical / HR**
- "My win rate dropped from [X]% in set 1 to [Y]% in set 2 and my average HR climbed by [N] bpm. What conditioning drill addresses that specific fatigue pattern?"
- "I lost [N] of [M] break points when my HR was above [BPM]. What breathing or between-point routine would help me manage that HR spike?"

**Pattern mining from raw data**
- "Looking at the point-by-point table, identify any games where I lost three or more consecutive points and what the score context was."
- "Which game scores (e.g. 30-All, 0-30) appear most often before a run of points I lost? Is there a pattern?"
- "At what stage of the match (early sets vs. late sets) does my unforced-error rate spike most? What does that suggest about my stamina vs. concentration?"

The raw point table gives any AI enough context to answer these questions with your specific numbers rather than generic advice.

---

## Battery Usage

For typical matches:
- **1-hour match:** ~15-20% battery
- **2-hour match:** ~20-30% battery

The app automatically dims the display when your wrist is lowered for additional power savings.

---

## Padel compatibility

Padel uses the same game/set scoring structure as tennis (games to 6 with a 2-game margin, tiebreaks at 6–6, and a match-deciding super tiebreak in many formats). Because of that, DeuceMate can be used to keep score in padel matches without changes to the scoring logic.

Keep in mind that some of the rules tips and prompts are tennis-specific (for example, ball-change reminders and foot-fault notes). You can still use the scoring and server rotation for padel, but ignore tennis-only guidance that does not apply to your padel ruleset.

---

## Tricky tennis rules to remember

- **End changes after games:** Players change ends after the first game of each set and then after every odd-numbered game (1, 3, 5, etc.). They do not change ends if the set score reaches an even total (for example, 4–0) until the next odd game is completed.
- **Changing ends after a set:** If a set ends with an odd total of games (e.g., 6–3 or 7–6), players change ends before starting the next set. If the set ends on an even number of total games (e.g., 6–2), players stay on the same ends and change after the first game of the following set.
- **Tiebreak serve order:** The player whose turn it is to serve begins the tiebreak with a single point from the deuce court. The serve then switches every two points, starting from the ad court (e.g., points 2–3, 4–5, etc.).
- **Tiebreak end changes:** Players change ends after every six points during a standard tiebreak (6, 12, 18, …).
- **Serve and balls after a tiebreak:** The next set begins with the player who did **not** serve first in the tiebreak. A tiebreak counts as a game for ball-change timing, so if balls are due after an odd number of games, apply the change before the first game of the next set when a tiebreak ends it.

### Other commonly forgotten rules

- New balls are often introduced after the first seven games (including the warm-up) and then every nine games, but local tournaments may set different intervals—check the event sheet.
- In doubles, the receiving team can choose which player receives first and may not switch receiver order within the same set.
- A let on serve is replayed without penalty; a serve that touches the receiver or their partner before bouncing counts as a fault.
- Foot faults include stepping on or over the baseline before making contact **and** running outside the imaginary extension of the center mark when serving from the deuce court.
- If continuous play is paused for a toilet or medical timeout, warm-up serves are not permitted when resuming unless allowed by the official; otherwise, play resumes immediately.

---

## Requirements

**Compatible Devices:**
- Apple Watch Series 4 or later
- Apple Watch SE (1st generation or later)
- Apple Watch Ultra (all models)

**Software:**
- watchOS 9.0 or later
- iOS 17.0 or later (iPhone companion)

DeuceMate will be available for download on the App Store (submission in progress).

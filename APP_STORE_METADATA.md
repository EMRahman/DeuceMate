# DeuceMate - App Store Metadata

Complete copy for App Store Connect submission.

DeuceMate ships as a single App Store product: an **iPhone app with a bundled
Apple Watch app**. Scoring happens on the Apple Watch; the iPhone app is a
companion for live viewing, spoken announcements, match history, and detailed
statistics. The submission is the iOS app (`ehsan.DeuceMate`); the watchOS app
(`ehsan.DeuceMate.watchkitapp`) is embedded and installs alongside it.

---

## App Information

**App Name:** DeuceMate
**Subtitle:** Tennis Score Keeper + Stats
**Primary Category:** Sports
**Secondary Category:** Utilities
**Age Rating:** **9+** — calculated by the App Store Connect questionnaire (Health/Wellness topics: heart-rate zones, calorie display, fitness coaching), confirmed 6 August 2026.
**Platforms:** iPhone (iOS 17.0+) with Apple Watch app (watchOS 9.0+)

---

## Promotional Text (170 characters max)

```
Score on Apple Watch, tag how every point ended, then hand the match to your favourite AI for real coaching. Free forever. No ads, no tracking.
```

**Character count:** 143 characters. Live on the store from the 1.1.0
submission (19 August 2026); the previous line was "Score tennis on Apple
Watch, then review live scores, spoken announcements, and full match stats on
iPhone. Free forever. No ads."

Two deliberate choices here:

- **"your favourite AI"**, not "ChatGPT, Claude or Gemini". The Description
  above uses the same generic phrasing, and promotional text renders directly
  on top of it — naming the apps in one and not the other reads as an
  oversight. (Naming them is permissible; guideline 2.3.10 is about rival
  *platforms*. This is a consistency choice, not a compliance one.)
- **"tag how every point ended"** — outcome tracking is opt-in and costs two
  taps per point, so the copy says it is something the player does, not
  something the app infers on its own.

Promotional text is the **only** App Store copy that can be changed without
submitting a new version for review, so it is the right home for anything
time-sensitive. Update it here whenever it is changed on the store, or this
file starts lying about what users actually see.

---

## Keywords (100 characters max)

```
tennis,score,match,tiebreak,sports,watch,referee,umpire,deuce,padel,game,set,stats
```

**Optimization Notes:**
- Focus on tennis-specific terms (deuce, tiebreak, set)
- Include "padel" for the international tennis variant
- "stats" covers the iPhone statistics feature set
- No spaces after commas to maximize character count

---

## Description (4000 characters max)

```
DeuceMate is a tennis scoring app for Apple Watch — with an iPhone companion app for live score viewing, spoken announcements, and a complete match archive with detailed statistics. Score on your wrist; review everything on your phone.

SCORE ON APPLE WATCH
• Swipe up/down to award points; swipe left to undo
• Automatic tennis scoring (love, fifteen, deuce, advantage)
• Game, set, and tiebreak tracking handled for you
• Standard tiebreaks, super tiebreaks, and multiple match formats
• Singles and doubles with full service-order management
• Large, glanceable score display; current server always visible
• Side-change reminders at the correct games

iPHONE COMPANION APP
• Live stadium-style scoreboard that mirrors the watch in real time
• Spoken, umpire-style score announcements through your iPhone or a Bluetooth speaker
• Unlimited match history archived on your phone
• Detailed per-match and per-set statistics: serve, return, break points, winners and errors, pressure points, rally depth, and more
• Interactive points timeline graph
• Export a match or generate an AI-coaching prompt to review with your favourite AI app

OPTIONAL FITNESS TRACKING (APPLE WATCH)
• Link a HealthKit workout to record your match as a Tennis activity
• Live heart rate, calories, steps, and distance during play
• Heart-rate zone statistics and coaching insights
• Entirely optional — the app works fully without it

COURT COMPASS (OPTIONAL)
• Enable "Check Changeover" for compass guidance on which end to take
• Uses the watch's built-in compass heading only — no GPS, no location tracking

UNDO ANYTHING
• Full undo back to the start of the match, restoring complete game state

PERFECT FOR
✓ Recreational players keeping official scores
✓ Club matches without an umpire
✓ Coaches tracking student progress
✓ Padel players (compatible scoring system)
✓ Practice sessions to track improvement

PRIVACY FIRST
• No account required
• No analytics, no tracking, no ads
• The developer collects no data and operates no servers
• Match data is stored on your devices and in your personal iCloud Drive archive
• Watch ↔ iPhone sync uses Apple's WatchConnectivity, with no developer server
• Core scoring and match review work offline
• DeuceMate's automatic iCloud Drive archive excludes HealthKit measurements
• You can choose to export match and HealthKit data to another person, a manual backup, or an AI service; the recipient then handles that data

NO SUBSCRIPTION. NO ADS. NO TRACKING.
Completely free for unlimited match tracking.

REQUIREMENTS
• iPhone running iOS 17.0 or later
• Apple Watch running watchOS 9.0 or later (Series 4 or later, SE, or Ultra)

Start scoring like a pro with DeuceMate. Game, set, match!
```

**Character count:** ~2,250 characters (well under 4,000 limit)

---

## What's New (4000 characters max)

### Version 1.1.0 - Watch match-start improvements and archive fixes

```
Thanks for the early feedback on DeuceMate — this update is built on it.

NEW ON APPLE WATCH
• The ends-switch reminder now sticks around. After a set finishes, it stays
  on the scoreboard until the first point of the next set, so you can check
  whether you're changing ends without undoing a point to see it again.
• Faster match starts. DeuceMate remembers your last format and your singles
  or doubles choice, so Start Match goes straight to who serves first.
• Know what's being recorded before you play. The start screen now shows
  whether point tracking, Health and Pulse Coach are on — and how to switch
  on anything that isn't.

FIXED
• The Health chip on the start screen now turns on as soon as you grant
  access, instead of staying amber until the next time you open the app.
• A match you just finished on your Watch is marked as stored on both
  devices straight away, instead of briefly reading "iPhone only" until
  the next sync.
• Swipe a match in the iPhone archive, tap Delete, and the confirmation now
  stays on screen until you answer it. It previously appeared and vanished
  straight away, so a match couldn't be deleted by swiping.

IMPROVED
• Matches kept on both your iPhone and Apple Watch can now be deleted in a
  single swipe — no need to remove the Watch copy first. A full swipe still
  only frees up Watch space, so your archive is never deleted by accident.

Found something? Tap Settings → Support & FAQ to get in touch. Your feedback
shapes what comes next.

Game, set, match!
```

**Character count:** ~1,520 characters

> **Scope — why the three Watch items are here.** The released 1.0.0 is
> **build 2**, cut on 6 August 2026 (`[iOS] Prepare build 2 submission
> candidate`). The Guideline 2.1 rejection was an *information* request
> answered by the 17 August Resolution Center reply, not a new binary; build 3
> was a TestFlight-only build cut on 16 August to film the demo recording and
> never went to users. So everything merged after 6 August reaches users for
> the first time in 1.1.0 — the remembered match setup (#83), the pre-match
> tracking strip (#84), and the sticky ends-switch reminder (#88), alongside
> this release's archive and Health-chip fixes. Confirmed against App Store
> Connect by the owner on 19 August 2026, who also observed build 3 sitting in
> TestFlight. Three features made this a minor release, not a patch — hence
> **1.1.0**, with the build number continuing at 4 because build 3 is already
> consumed in App Store Connect.

---

### Version 1.0.0 - Initial Release

```
Welcome to DeuceMate — tennis scoring done right.

SCORE ON APPLE WATCH
• Swipe to score, swipe to undo
• Automatic game, set, and tiebreak tracking
• Multiple match formats; singles and doubles

iPHONE COMPANION
• Live scoreboard mirrored from the watch in real time
• Spoken, umpire-style score announcements
• Unlimited match history with detailed statistics
• Interactive points timeline and match export

OPTIONAL FITNESS
• HealthKit workout with live heart rate and heart-rate-zone stats

PRIVACY FOCUSED
No account, no developer data collection, and no tracking. Your automatic
iCloud Drive archive excludes HealthKit measurements; sharing is your choice.

Ready to play? Start your first match.

Game, set, match!
```

**Character count:** ~620 characters

---

## App Preview / Screenshots

### iPhone screenshots (Required)

App Store Connect requires at least one set of iPhone screenshots. Provide the
6.9" display size; the 6.5" set is required only when a 6.9" set is absent.

- **6.9" display:** 1–10 screenshots at one accepted portrait size:
  1260×2736, 1290×2796, or 1320×2868; 3–6 screenshots recommended
- **6.5" display** (optional when 6.9" is supplied): 1–10 screenshots

Suggested iPhone screenshot content (in order):
1. Live scoreboard mirroring an in-progress match
2. Match history list
3. Match statistics (serve / return / break points)
4. Points timeline graph
5. Settings showing the spoken-announcements toggle

### Apple Watch screenshots (Required for the Watch app)

- Upload 1–10 screenshots at **one accepted Watch size**, used consistently
  across every localization; 3–5 screenshots are recommended.
- Prefer **416×496** (Series 10/11) for a new set, or use the existing
  **396×484** (Series 7–9) size. Separate 41 mm and 45 mm sets are not required.

Suggested Apple Watch screenshot content (in order):
1. Main scoring screen during an active match
2. Live stats view
3. Server selection at match setup
4. Side-change reminder
5. Settings toggles

> **Note:** iPad screenshots are NOT required — DeuceMate is an iPhone-only app
> (device family: iPhone) plus its Apple Watch companion.

### Screenshot title overlays (optional)

1. "Track Every Point"
2. "Live On Your iPhone"
3. "Know Your Game"
4. "See Every Momentum Swing"
5. "Hear The Score"

---

## App Preview Video (Optional but Recommended)

**Length:** 15-30 seconds
**Content suggestion:**
1. Score a few points on the watch with swipe gestures (0-10s)
2. Cut to the iPhone live scoreboard updating (10-18s)
3. Show match statistics / points graph (18-25s)
4. End on the match-history archive (25-30s)

---

## Support Information

**Support URL:** `https://emrahman.github.io/DeuceMate/support.html`
**Support Email:** `mail@ehsanrahman.com`
**Marketing URL (optional):** `https://emrahman.github.io/DeuceMate/`
**Privacy Policy URL (REQUIRED):** `https://emrahman.github.io/DeuceMate/privacy.html`

**Note:** These point at the public GitHub Pages site served from the `/docs`
folder (`docs/index.html` = marketing landing page, `docs/support.html` =
support/help, `docs/privacy.html` = privacy policy).
**Pages must be enabled before submission:** repo **Settings → Pages → Build
and deployment → Deploy from a branch → `main` / `/docs`**. GitHub Pages on a
private repo requires GitHub Pro or higher; on the free plan the repository must
be public for Pages to publish. If you'd rather host on your own domain, drop
the same two files on `ehsanrahman.com` and use those URLs instead — Apple only
needs the Privacy Policy and Support URLs to resolve publicly.

---

## App Privacy ("Nutrition Label") Guidance

When completing the App Privacy questionnaire in App Store Connect:

- DeuceMate has **no developer-controlled servers, analytics, or third-party
  SDKs**. Its automatic archive uses the user's personal iCloud Drive account,
  but the developer cannot access that archive. Select **No, we do not collect
  data from this app** in App Store Connect; this matches Apple's definition of
  collection and the audited implementation. Preview the resulting product-page
  label against the final privacy policy before publishing it.
- HealthKit data (heart rate, energy, steps, distance) is read and analysed in
  DeuceMate. HealthKit-derived match fields are excluded from DeuceMate's
  automatic iCloud Drive archive and are never sent to the developer. Maximum
  heart rate for Pulse Coach zones is estimated from an optional user-entered
  birth year (or manual value), not read from HealthKit.
- Match exports, AI-coaching hand-offs, and manual archive backups are
  **user-initiated** and may include HealthKit-derived measurements. The user
  chooses the recipient or service, whose privacy terms then apply; the
  developer does not receive the export.
- Before a health-bearing export leaves the device, DeuceMate presents an
  **in-app disclosure** that names exactly which of those measurements the
  export contains and reminds the user of the destination; the export proceeds
  only on confirmation. Exports of matches with no recorded health data skip the
  prompt. This is the informed-consent step for HealthKit data sharing.
- HealthKit apps must have a privacy policy — see `PRIVACY_POLICY.md`, which
  includes a dedicated Health & Fitness Data section.

---

## Copyright & Legal

**Copyright:** © 2026 Ehsan Rahman
**Developer Name:** Ehsan Rahman
**Bundle ID (iOS app):** `ehsan.DeuceMate`
**Bundle ID (bundled watchOS app):** `ehsan.DeuceMate.watchkitapp`
**SKU:** `deucemate` (or your choice)

---

## Pricing & Availability

**Pricing:** FREE (no subscriptions, no in-app purchases, no ads)

**Rationale:**
- Maximize downloads and user base
- Portfolio showcase: a widely used free app demonstrates real-world impact
- Removes friction for club members and viral adoption

**Availability:** All territories (no content restrictions)

---

## App Review Information — Notes (Guideline 2.1 information request)

Apple's Guideline 2.1 "Information Needed" template asks seven questions and
requires a screen recording captured on physical hardware. The block below is
the exact text sent as the Resolution Center reply for the 17 August 2026
resubmission — it links the recording on YouTube rather than attaching a
file, since a hosted link avoids the Resolution Center attachment size limit.
The video link is currently marked `<video removed>` below (the hosted video
was taken down); restore it before reusing this text. Update the OS versions,
TestFlight build number, and the recording link before reusing this for a
future submission; paste the result into **App Store Connect → App Review
Information → Notes** and send the same text as the Resolution Center reply.

Apple's App Review Information Notes field has a 4000-character limit; the
block below is 3,862 characters.

```
Dear Team,

1. SCREEN RECORDING

See <video removed>
Captured on physical hardware on the latest OS — iPhone 16 (iOS 26.6) and Apple Watch Series 7 45mm (watchOS 26.6). From launch, it covers: scoring a match on Apple Watch, a force-quit/relaunch mid-match with score/server/timer intact, the live iPhone scoreboard, archive, statistics, points timeline and export.

Your listed flows:
- Account registration/login/deletion: N/A — no accounts.
- Paid content/purchases/subscriptions: N/A — free, no IAP, no ads.
- User-generated content: N/A — no social layer; the only content is the user's own match data, deletable from the archive (shown in the recording).
- Sensitive-data prompts: shown in context — (a) Watch HealthKit at first launch, (b) iPhone HealthKit when "Per-point avg" heart rate is selected, (c) optional location for the Watch's Check Changeover compass. No ATT, camera, mic, photos, contacts, calendar, notifications, or Bluetooth. Usable with every prompt denied.

2. DEVICES AND OS TESTED

Physical: iPhone 16 (iOS 26.6, TestFlight 1.0.0 (3)) and Apple Watch Series 7 45mm (watchOS 26.6), plus the same iPhone unpaired. Covered: first-launch HealthKit grant/denial, a live match mirrored to iPhone, Watch-to-iPhone transfer, Sync Now/Sync to Watch with an empty Watch, match recovery, foreground/background announcements, health-data exports, and iCloud Drive unavailable.

3. WHAT THE APP DOES, AND FOR WHOM

A tennis scorekeeping app. Apple Watch is the on-court scorer — swipe up/down to score, swipe left to undo, full tennis scoring rules. iPhone is the live scoreboard and archive — announcements, match/set statistics, a points timeline, text/HTML export. State saves atomically after every point and mirrors to iPhone, so a crash never loses the score. Point-level capture drives statistics and an on-device coaching prompt the user can paste into an AI assistant. Optional HealthKit records a Tennis workout. Audience: recreational/club players and coaches. Age rating 9+ (health/wellness topics).

4. SETUP AND MAIN FEATURES

No login, nothing gated, no network required.
No Watch: iPhone app → Manual Match Entry → enter a score → open it for statistics, export, and AI Coach (point-level sections show empty states — manual entry has no point data).
With a Watch: open Watch app → accept/decline HealthKit → Start Match → choose server → swipe to score → optionally categorize a point → iPhone mirrors live → end match to archive it with full statistics.
Optional: Check Changeover (Watch Settings, uses location) and Backup & Transfer / iCloud backup indicator (iPhone Settings).

5. EXTERNAL SERVICES USED

None. No third-party SDKs, backend, analytics, ads, crash reporting, auth, or payments — everything computes on device. Apple frameworks only: HealthKit; WatchConnectivity (peer-to-peer); iCloud Drive (user's account, HealthKit fields stripped from this backup); AVFoundation speech; Core Location (heading only); SwiftUI/Swift Charts.

One optional hand-off: the AI Coach card lets the user copy a generated prompt and, if tapped, open a third-party AI app (ChatGPT, Claude, Gemini, Perplexity, Copilot, Poe, Grok) at its public URL. DeuceMate transmits nothing itself and holds no account or API key with any provider.

6. REGIONAL DIFFERENCES

None. Single English UI, no localizations, no region-gated features, free everywhere; scoring rules are the same worldwide.

7. REGULATED INDUSTRY / THIRD-PARTY MATERIAL

Neither applies. A sports scorekeeping app, not medical — no medical claims, diagnosis, or treatment; HealthKit data is shown as fitness information only. No third-party or protected content, branding, logos, trademarks, or affiliation with any governing body. All code, art, and copy are original.

Let me know if anything further would help the review.

Ehsan Rahman
mail@ehsanrahman.com
```

---

## Demo screen recording — capture plan

Apple's request is specific: **physical devices, latest OS, starts with launching
the app, and shows every permission prompt in context.** watchOS has no built-in
screen recorder, so film the Watch with a second camera while screen-recording
the iPhone, then cut the four segments below into one file.

**Before recording — reset so the permission prompts actually appear:**
1. Delete DeuceMate from the iPhone (this removes the Watch app too), then
   reinstall the exact submitted TestFlight build.
2. Confirm both devices are on the latest public iOS/watchOS release.
3. Do not open the app before recording starts — the recording must begin with
   the launch.

**Run both recorders for the whole session.** The Watch match must still be
live when the iPhone segment is filmed: finishing a match calls
`ScoreViewModel.resetMatch()`, which calls `clearActiveMatch()` on the sync
service, so the iPhone live scoreboard disappears the instant the match ends.
Film in the order below and cut afterwards. Use the Standard match format —
Perpetual Points fixes the deuce side and never engages the compass.

**Segment A — Apple Watch (filmed), match left in progress:** Home Screen →
tap the DeuceMate icon → HealthKit authorization sheet (allow) → start screen
with the setup card and the Points/Health/Pulse tracking strip → Settings →
enable Check Changeover → back to the start screen → Match Setup sheet →
Start Match → choose first server. The "When In Use" location prompt fires at
the first game start once Check Changeover is on; show it and the compass hint.
Then score points with swipe up / swipe down through deuce and advantage to win
a game → categorize a point in the sheet → swipe left to undo and show the
score restored → the ends-switch reminder → live stats.

Then, still in Segment A, demonstrate the crash-safety claim from item 3:
force-quit DeuceMate on the Watch (hold the side button until the power screen
appears, then hold the Digital Crown until the app quits) and relaunch it. The
start screen comes back reading **"Resume Match"** rather than "Start Match";
tap it and hold on the restored scoreboard long enough to show the score, the
server and the match timer intact. Score another point afterwards so the match
is visibly still live. **Do not finish the match yet.**

**Segment B — iPhone (screen recording), while that match is still live:**
Home Screen → launch DeuceMate → the live scoreboard mirroring the Watch →
score another point or two on the Watch so the mirroring is visibly live →
Settings, toggle "Announce scores aloud" and let one announcement play audibly.

**Segment C — back to the Apple Watch:** finish the match. The iPhone live
scoreboard clears at this point, which is expected.

**Segment D — iPhone (screen recording):** archive list showing the finished
match → match detail statistics and set breakdown → points timeline with the
outcome filters, tapping a point to show its full pre-point score → **switch
the heart-rate series control from "Raw" to "Per-point avg"** — this is the
only action that requests Health access on iPhone, so the HealthKit
authorization sheet appears here and nowhere else → AI Coach card →
share/export, including the health-data disclosure prompt before a
health-bearing export → Manual Match Entry, saving a match and opening it, to
show the no-Watch reviewer path and its two intentional empty states.

Keep it in real time with no jump cuts across a prompt, aim for three to five
minutes, and export H.264 at 1080p so the file stays inside the Resolution
Center attachment limit.

---

## Launch Checklist

### Required
- [ ] All metadata text finalized (name, subtitle, description, keywords)
- [ ] iPhone screenshots prepared (6.9" required)
- [ ] Apple Watch screenshots prepared at one accepted size used consistently
- [ ] Privacy policy page live and accessible (includes HealthKit section)
- [ ] Support URL or email verified
- [ ] App Privacy questionnaire completed ("Data Not Collected")
- [x] Age rating completed via the current questionnaire — confirmed 9+ (Health/Wellness topics; not 4+) on 6 August 2026
- [ ] Pricing tier selected (Free)
- [ ] Territories/regions selected
- [ ] Build archived from Xcode and uploaded
- [ ] Build tested on a real iPhone + Apple Watch (not just simulator)
- [ ] TestFlight review pass
- [ ] App Review Information → Notes filled in with the seven-item block above
- [ ] Demo screen recording captured on physical devices per the capture plan
  above, and attached to the submission or its Resolution Center thread.
  Apple's Guideline 2.1 "Information Needed" template requests it for new app
  submissions; DeuceMate was rejected under it in August 2026 for its absence.

### Recommended
- [ ] App preview video created (separate from the review recording — this one
  is the marketing video shown on the product page)
- [ ] Friends/family beta tested via TestFlight
- [ ] Support page with FAQ created

---

## Post-Launch

### Monitor
- App Store reviews and ratings
- Crash logs in App Store Connect
- Support email for user feedback
- Search ranking for key terms

### Iterate
- Respond to reviews
- Release updates based on feedback
- Consider localization (Spanish, French) for international tennis

---

*Generated for DeuceMate v1.0.0 - 2026*

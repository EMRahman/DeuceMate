# DeuceMate — App Store Submission Review

A pre-flight review of DeuceMate against the [App Store Review
Guidelines](https://developer.apple.com/app-store/review/guidelines/), focused
on blockers and likely rejection reasons. Items fixed in the branch that
introduced this file are marked **[fixed in this PR]**; everything else is a
manual step for the submitter.

Legend: `[ ]` to do · `[x]` done · `[~]` partially done / needs a manual switch.

---

## 🛑 Blockers (must be resolved before/at submission)

### 1. Privacy Policy & Support URLs must resolve publicly — Guideline 5.1.1 / 1.5
The submission's Privacy Policy URL (required, and strictly enforced for
HealthKit apps), Support URL, and Marketing URL previously pointed at
`github.com/EMRahman/DeuceMate`, which is a **private** repository — those URLs
return 404 to Apple's reviewers.

- [x] **[fixed in this PR]** Added a public site under `/docs`
  (`docs/index.html` = support, `docs/privacy.html` = privacy policy), with
  `docs/_config.yml` excluding the internal `docs/features/` plans from the
  published build.
- [x] **[fixed in this PR]** Updated the URLs in `APP_STORE_METADATA.md` to the
  GitHub Pages site.
- [x] **MANUAL — enable GitHub Pages:** repo **Settings → Pages → Build and
  deployment → Deploy from a branch → `main` / `/docs`**. Note: Pages on a
  **private** repo requires GitHub Pro or higher; on the free plan the repo must
  be **public** for Pages to publish.
  - Alternative: host `index.html` + `privacy.html` on `ehsanrahman.com` and use
    those URLs instead — Apple only needs the two URLs to resolve publicly.
- [~] **MANUAL — verify** both URLs load in a private/logged-out browser window
  before submitting. Re-audited 2026-07-08: this session's egress proxy blocks
  `github.io`, so `https://emrahman.github.io/DeuceMate/{privacy,index}.html`
  could not be re-checked here — confirm directly in a logged-out browser
  before submitting. This is the one hard rejection trigger for a HealthKit app.

---

## ⚠️ High-risk items (likely to draw a rejection)

### 2. Background-audio keep-alive — Guideline 2.5.4
The iPhone announcement feature previously used the `audio` background mode plus
a silent looping buffer (`outputVolume = 0.0`) to stay alive between
announcements — the textbook pattern reviewers reject under 2.5.4.

- [x] **[fixed in this PR]** Reworked announcements to be **foreground-only**:
  removed the `audio` background mode from `Info.plist`, removed the silent-loop
  keep-alive (`AVAudioEngine`/`AVAudioPlayerNode`) and the inactivity watchdog
  from `LiveAnnouncementService.swift`. A score is spoken only while the app is
  on screen; it is skipped (not queued) when backgrounded/locked.
- [x] **[fixed in this PR]** Updated the Settings copy, README, and the App
  Review notes so no doc still claims "works with the screen locked / in the
  background."
- [ ] **MANUAL — verify on device:** with the iPhone app foreground, scoring on
  the watch produces spoken announcements; locking the phone stops them; no
  audio background mode appears in the built app's capabilities.

---

## 🟡 Medium-risk items

### 3. iPhone app must be reviewable without a paired Apple Watch — Guideline 4.2 / 2.1
Reviewers usually don't pair an Apple Watch, yet the headline features (scoring,
live scoreboard, announcements) need one. The testable no-watch surface is
**Manual Match Entry → history → statistics → points graph → export**.

- [ ] **MANUAL** — In the App Review notes, make the **Manual Match Entry** flow
  step 1 of "How to test" so a reviewer without a watch has a clear path.
- [ ] **MANUAL** — Attach a **demo video** in App Review Information showing the
  watch scoring + iPhone live scoreboard + announcements (Apple explicitly
  recommends a demo video for hardware-dependent features).
- [x] **[fixed in this PR]** Manual Match Entry is now reachable from the
  "No Apple Watch Paired" empty state — the first screen a reviewer without
  a watch sees. `PastMatchesView.swift` — `emptyStateView`.

### 4. HealthKit specifics — Guideline 5.1.3
- [x] HealthKit usage strings present (read + write on watch via
  `INFOPLIST_KEY_NSHealthShareUsageDescription` /
  `…NSHealthUpdateUsageDescription`; read on iOS via `Info.plist`).
- [x] HealthKit entitlement present on both targets; privacy policy has a
  dedicated Health & Fitness section (tie-in to Blocker #1 — must be reachable).
- [ ] **MANUAL — verify** the app degrades gracefully if Health access is
  **denied** and if **date of birth** is unavailable (fall back to an age-based
  max-HR estimate). Two authorization surfaces (watch + iPhone) is allowed but
  means two permission prompts.
- [x] HealthKit integration is described in the App Store description/metadata.

---

## 🔵 Low-risk / polish

- [ ] **Bundle ID** is `ehsan.DeuceMate` (non-reverse-DNS). Apple accepts it, but
  it is effectively permanent after the first submission — confirm it's the
  desired final ID (vs. e.g. `com.ehsanrahman.deucemate`).
- [x] Keyword `padel` is borderline-relevant but defensible (the description
  explains scoring compatibility). Keep the explanation in the description.
- [x] App Store description says "your favourite AI app" rather than naming
  ChatGPT/Claude/etc. — **keep it that way** (naming third-party trademarks in
  metadata invites scrutiny; the in-app launch buttons are fine).
- [x] **[fixed in this PR]** Corrected stale `SUPPORT_PAGE.md` answers that said
  the app was watch-only and a "one-time purchase" (it's a free iPhone+watch app).
- [x] **[fixed in this PR]** Corrected the privacy policy's iCloud claim. Match
  data lives in the Documents directory and is therefore eligible for the user's
  own encrypted iCloud Backup; the policy previously claimed "not backed up to
  iCloud." It now accurately states the App never uploads data and does not use
  iCloud itself, while the OS-level device backup is under the user's control.
  (`.completeFileProtection` is encryption-at-rest, not backup exclusion.)
- [x] Privacy policy effective date aligned (June 11, 2026).
- [ ] **AccentColor colorset is empty** on both targets (`Contents.json` has no
  color defined) while `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME =
  AccentColor` — falls back to system blue. Either populate the colorset or
  note this is intentional (theming is handled by `AppTheme`).
- [ ] Watch target pins `CODE_SIGN_IDENTITY = "Apple Development"` in the
  Release configuration — harmless under automatic signing, but worth knowing
  at export/archive time.

---

## ✅ Verified clean (no action needed)

- [x] **[fixed in this PR]** One force-unwrap (`realSteps.first!` in
  `PointsGraphView.swift:325`) replaced with `realSteps[0]` (guarded by the
  surrounding `count >= 2` check). Zero force-unwraps remain in the codebase.
- [x] **No data collection / no network** — verified in source: no `URLSession`
  and no networking APIs anywhere in Swift. The only `http(s)` URL literals are
  the public privacy-policy / support-site links in Settings → About, opened by
  the system browser via SwiftUI `Link` (plus a `mailto:` support link) — the
  app itself still makes no network requests. The "Data Not Collected"
  nutrition label and privacy claims are accurate. Note: those About links
  point at the GitHub Pages site, so they resolve once Blocker #1's manual
  Pages setup is done.
- [x] **Privacy manifests** present on both targets with valid API reason codes
  (UserDefaults `CA92.1`, System Boot Time `35F9.1`).
- [x] **Location is heading-only** — `startUpdatingHeading` only, never
  `startUpdatingLocation`/`requestLocation`; "no GPS" claim holds. When-in-use
  usage string present on the watch, and justified by a real feature (compass
  heading, `HomeView.swift` / `ContentView.swift` `CompassBadgeView`) — not
  unused permission scope.
- [x] **App icons** are 1024×1024, **RGB with no alpha channel** (transparent
  icons are auto-rejected at upload), with light/dark/tinted iOS variants.
- [x] **Export compliance** declared (`ITSAppUsesNonExemptEncryption = false`) on
  both targets — skips the encryption questionnaire.
- [x] **`LSApplicationQueriesSchemes`** lists 7 AI-app schemes (well under the
  50-scheme limit); AI launch uses `canOpenURL` + `open` (permitted).
- [x] **Test suites** (Core + watch) run locally via Xcode before submission.
  GitHub Actions was removed to cut macOS runner costs — no automated CI;
  run tests locally (`xcodebuild`, see `CLAUDE.md` §3).
- [x] Age 4+, Free, no IAP — the simplest review lane.
- [x] **No required-reason API gaps** — grep confirms no
  `contentModificationDate` / `fileModificationDate` / `attributesOfItem` /
  `creationDate` anywhere in Swift, so the existing privacy-manifest entries
  (UserDefaults `CA92.1`, System Boot Time `35F9.1`) are complete. Both
  `.xcprivacy` files sit inside file-system-synchronized target folders, so
  they're bundled automatically (no `project.pbxproj` edit needed).
- [x] iOS correctly **omits** `NSHealthUpdateUsageDescription` (it only reads
  HR data, never writes); app version/build (`1.0.0` / `1`) is consistent
  across both targets; the Release build configuration is clean (no debug
  leakage).

---

## 📸 Screenshot & demo-video plan (one session, ~2 hours)

### 1. Confirm required sizes (5 min)
- [ ] Open App Store Connect → version → screenshot panel and note the device
  classes it actually asks for (Apple shuffles these periodically). Expected:
  **iPhone 6.9"** (one set covers all smaller iPhones; iPhone-only device
  family ⇒ no iPad set) and **Apple Watch** (largest size required; smaller
  sizes optional / auto-scaled).

### 2. Seed good-looking data (20–30 min)
- [ ] Real matches on the physical devices for authentic stats — and for every
  HR-dependent panel (PulseCoach, HR/steps overlays): **simulators have no
  HealthKit**, so those screens must come from a real match.
- [ ] Staged simulator match for everything else: boot the paired
  watch+iPhone simulators, enable outcome tracking, swipe through a 2-set
  match on the watch sim (~10 min) to fill the stats views, category sheet,
  and points graph. WatchConnectivity between paired sims can be flaky — if
  the live scoreboard won't mirror, capture that one screen on real devices.

### 3. Shot list (5–6 per platform; the first 3 show in search results)
Use one theme across all shots (e.g. Hard Court Night for contrast).
- **Watch:** ① live scoreboard mid-match (server badge + momentum strip),
  ② match setup, ③ live stats, ④ point-category sheet, ⑤ history.
- **iPhone:** ① live scoreboard with LIVE badge, ② match detail stats,
  ③ points graph with overlays on, ④ AI Coach sheet, ⑤ archive list,
  ⑥ manual match entry (doubles as the reviewer test path, Item #3).

### 4. Capture mechanics (30–40 min)
- [ ] Run each scheme on the size-exact simulator (6.9"-class iPhone; largest
  watch). **Cmd+S** in Simulator saves a pixel-perfect PNG at native
  resolution — no resolution math, which is why sims beat physical devices here.
- [ ] Polish the iPhone status bar before capturing:
  `xcrun simctl status_bar booted override --time "9:41" --batteryLevel 100
  --cellularBars 4 --wifiBars 3` (watch sims don't support the override — fine).
- Raw screens are acceptable for v1; skip marketing frames/captions.

### 5. Demo video in the same session (feeds Item #3)
- [ ] Shoot watch scoring → iPhone live scoreboard → announcements on real
  devices (phone propped up), or `xcrun simctl io booted recordVideo demo.mp4`
  if sim pairing cooperates. Attach in App Review Information.

### 6. Upload
- [ ] Drag the sets into App Store Connect, confirm the dimensions are
  accepted, then tick the screenshots line in the checklist below.

---

## Final pre-submit checklist

- [~] GitHub Pages enabled (or URLs hosted elsewhere); both URLs still need a
      **logged-out browser confirmation** — this environment's egress proxy
      blocks `github.io` and couldn't re-verify it this session — **Blocker #1**.
- [ ] Build archived from Xcode and tested on a **real** iPhone + Apple Watch.
- [ ] App Review notes updated: manual-entry-first test path + demo video
      attached — **Item #3**.
- [ ] HealthKit denied/again-no-DOB paths verified — **Item #4**.
- [ ] App Privacy questionnaire = "Data Not Collected"; HealthKit declared as
      on-device only.
- [ ] Screenshots prepared (iPhone 6.9"; Apple Watch 41mm + 45mm) — see the
      screenshot & demo-video plan above.
- [ ] Bundle ID confirmed as final — **low-risk item**.
- [ ] Developer-portal capability/container check: the App ID has HealthKit +
      iCloud capabilities enabled and the `iCloud.ehsan.DeuceMate` container
      exists — otherwise archive validation fails.

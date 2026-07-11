# DeuceMate - App Store Submission Review

Current pre-flight review of DeuceMate against the
[App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/),
focused on upload blockers, likely rejection reasons, and the manual work needed
in App Store Connect.

## Codex codebase audit - 11 July 2026

Items marked **CODEX FINDING** were found by Codex during a fresh review of the
source, Xcode project and scheme, entitlements, privacy and store metadata,
compiled products, tests, and a generated archive. They are current repository
findings, not historical notes copied from an earlier PR.

**Current status: not ready to submit.** Resolve Blockers 1-4, reconcile the
public claims in Item 5, and complete a signed Organizer validation before
uploading a build.

Legend: `[ ]` to do, `[x]` verified, `[~]` partly verified or awaiting a product
decision.

---

## Blockers

### 1. Archive has two top-level apps

**CODEX FINDING:** An unsigned Release archive produced this layout:

```text
Products/Applications/DeuceMate.app
Products/Applications/DeuceMate Watch App.app
Products/Applications/DeuceMate.app/Watch/DeuceMate Watch App.app
```

The Watch app is correctly embedded in the iPhone app, but it is also installed
as a second top-level product. This produces the generic archive shape described
in [TN3110](https://developer.apple.com/documentation/technotes/tn3110-resolving-generic-xcode-archive-issue),
which cannot be distributed as an iOS app archive.

Evidence:

- `DeuceMate/DeuceMate.xcodeproj/project.pbxproj`: the Watch target has
  `SKIP_INSTALL = NO` in Debug and Release (currently around lines 720 and 758).
- `DeuceMate/DeuceMate.xcodeproj/xcshareddata/xcschemes/DeuceMate.xcscheme`:
  both the iPhone app and Watch app are independently enabled for archiving,
  even though the iPhone target already depends on and embeds the Watch app.
- The Watch Release configuration explicitly pins
  `CODE_SIGN_IDENTITY = "Apple Development"` while using automatic signing.
  That can also cause a distribution-signature mismatch.

Required work:

- [ ] Set the embedded Watch target to `SKIP_INSTALL = YES` for archive builds.
- [ ] Remove the redundant Watch app archive entry from the iPhone scheme, or
  at minimum disable `buildForArchiving` for that separate entry.
- [ ] Remove the explicit `Apple Development` identity from the Watch Release
  configuration and let automatic distribution signing choose the identity.
- [ ] Create a signed archive in Xcode Organizer and confirm it is classified as
  an iOS app archive with only `DeuceMate.app` at `Products/Applications`.
- [ ] Run **Distribute App -> App Store Connect -> Validate App** successfully.

### 2. iCloud Documents entitlement is incomplete

**CODEX FINDING:** `DeuceMate/DeuceMate/DeuceMate.entitlements` declares
`CloudDocuments` and `com.apple.developer.icloud-container-identifiers`, but not
`com.apple.developer.ubiquity-container-identifiers`. The app calls
`FileManager.url(forUbiquityContainerIdentifier:)` in `PhoneStatsStore.swift`,
so the current source entitlements do not fully configure the advertised iCloud
Documents feature. Apple's
[iCloud configuration guide](https://developer.apple.com/documentation/Xcode/configuring-icloud-services)
states that enabling iCloud Documents adds both container entitlement arrays.

The in-app guide in `PastMatchesView.swift` also tells users to enable
**iCloud Backup**. This feature uses **iCloud Drive/Documents**, which is a
different setting and should be named accurately.

Required work:

- [ ] Configure iCloud Documents through Xcode Signing & Capabilities for the
  iPhone target and `iCloud.ehsan.DeuceMate` container.
- [ ] Verify the source and signed-product entitlements contain both
  `com.apple.developer.icloud-container-identifiers` and
  `com.apple.developer.ubiquity-container-identifiers`.
- [ ] Change the in-app recovery instructions from iCloud Backup to iCloud
  Drive, including the correct Settings path.
- [ ] Test upload, update, deletion, signed-out/Drive-disabled handling, and
  first-install restore on a physical iPhone using the production container.

### 3. HealthKit permission is not opt-in as documented

**CODEX FINDING:** The privacy policy and App Review notes describe HealthKit
fitness features as off by default and enabled by the user. The Watch app
instead calls `requestAuthorization` unconditionally from `DeuceMateApp.swift`
on first appearance, and every match attempts to start or resume a workout.
There is a `workoutSessionEnabled` preference key, but it does not currently
gate the authorization or workout paths.

The Watch authorization request reads workout, heart rate, active and basal
energy, steps, walking/running distance, and date of birth. Its current
`NSHealthShareUsageDescription` mentions only heart rate, calories, and date of
birth. Apple recommends asking for HealthKit access in context and only when the
user invokes the relevant feature; see the
[HealthKit HIG](https://developer.apple.com/design/human-interface-guidelines/healthkit/).

Required work:

- [ ] Add or restore an explicit **Record Apple Health workout** control,
  defaulted off for a fresh install.
- [ ] Request HealthKit authorization only after the user enables that feature
  or starts a match with it enabled.
- [ ] Gate all start, resume, and recovery workout paths on that setting.
- [ ] Expand the Watch read-purpose string to accurately mention steps and
  walking/running distance, or stop requesting data the feature does not need.
- [ ] Test fresh-install grant, denial, partial authorization, revocation, no
  date of birth, and HealthKit-unavailable behavior.
- [ ] Update `PRIVACY_POLICY.md`, `docs/privacy.html`, `APP_STORE_METADATA.md`,
  and App Review notes only after the implemented behavior is settled.

### 4. Health-derived data needs an iCloud and sharing compliance decision

**CODEX FINDING:** `ArchiveBackupPolicy` correctly strips the match's five
HealthKit-derived metrics from the app-managed iCloud archive. Other paths still
need resolution before the document can claim Health data stays on-device:

- Full records containing health-derived values are stored in Documents or
  Application Support on iPhone and Watch, and are not marked as excluded from
  normal device backup.
- Health-derived preferences such as birth-year provenance and Pulse Coach max
  heart rate are stored in `UserDefaults`, which is also part of device backup.
- Full-fidelity manual archive export can be saved to iCloud Drive.
- Normal text, HTML, and AI exports can contain heart rate, zones, steps,
  calories, and distance. The opponent summary still receives match-level
  movement/energy totals, and the AI hand-off has no health-specific consent.

Guideline 5.1.3 says apps may not store personal health information in iCloud.
Apple's
[HealthKit privacy guidance](https://developer.apple.com/documentation/healthkit/protecting-user-privacy)
also limits disclosure to third parties and requires prior express consent.
Treat these paths as unresolved rather than assuming user-controlled backup or
the generic Share sheet makes every transfer compliant.

Safest resolution before submission:

- [ ] Exclude health-bearing local archive files and related preferences from
  device backup, or remove the HealthKit-derived values from those stores.
- [ ] Strip HealthKit-derived values from every file that can be saved to iCloud
  Drive, including full-fidelity manual archives.
- [ ] Strip HealthKit-derived values from normal, opponent, HTML, and AI exports
  by default. If any health sharing remains, review whether the recipient and
  purpose are permitted, then add specific informed consent for the exact data.
- [ ] Add focused tests proving every cloud/export representation omits the
  protected fields.
- [ ] Re-audit the privacy policy and App Privacy answers after this product
  decision. Do not submit while the policy and behavior disagree.

---

## High-risk review items

### 5. Privacy and store metadata contain contradictory absolute claims

**CODEX FINDING:** The codebase has no developer-controlled web service and no
`URLSession` networking stack. However, the current documents go further and
claim that the app makes no network requests, never transmits HealthKit data,
and only contains the privacy/support URL literals. Those statements are no
longer accurate because the app:

- automatically writes its stripped archive to the user's iCloud Documents
  container;
- sends match data between Watch and iPhone;
- creates user-initiated exports and AI-app hand-offs; and
- generates seven external AI-service links in the HTML match experience.

The public policy also describes an obsolete iPhone Documents storage path and
`.completeFileProtection`, while the canonical phone archive now uses
Application Support and the stores use
`.completeFileProtectionUntilFirstUserAuthentication`.

Required work:

- [ ] Replace "no network" / "never transmitted" with the narrower and accurate
  claim: no developer-controlled backend and no data collected by the developer;
  system-managed personal iCloud storage and explicit user sharing are separate.
- [ ] Reconcile `APP_STORE_METADATA.md`, `PRIVACY_POLICY.md`,
  `docs/privacy.html`, `docs/support.html`, README, App Review notes, and in-app
  copy from one agreed description of the implemented behavior.
- [ ] Update the policy's storage locations, file-protection class, and date.
- [ ] Point Settings -> Support & FAQ directly to `docs/support.html` rather
  than the marketing root.
- [~] "Data Not Collected" may remain the correct App Privacy answer under
  Apple's developer-access definition, but do not justify it by claiming that
  no information ever leaves either device.

### 6. The iPhone experience must be reviewable without a Watch

Reviewers may not pair an Apple Watch. The no-Watch review path is
**Manual Match Entry -> history -> statistics -> points graph -> export**.

- [x] Manual Match Entry is reachable from the "No Apple Watch Paired" empty
  state in `PastMatchesView.swift`.
- [ ] Put Manual Match Entry first in the App Review notes' test instructions.
- [ ] Attach a demo video showing Watch scoring, iPhone live scoreboard, and
  foreground announcements. Apple recommends a video when hardware-specific
  features are difficult to reproduce during review.
- [ ] Confirm every central iPhone screen has a useful no-Watch state and no
  indefinite connectivity loading state.

### 7. Age rating needs the current questionnaire

**CODEX FINDING:** The existing checklist assumes age 4+. Apple's current age
rating questionnaire includes **Health or Wellness Topics**, including exercise
recommendations and calorie tracking. DeuceMate's heart-rate zones, fitness
coaching, and calorie display mean the calculated rating is likely 9+ on newer
OS versions, subject to App Store Connect's regional result.

- [ ] Complete the current questionnaire accurately instead of forcing the old
  4+ assumption. See Apple's
  [age-rating definitions](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions).
- [ ] Update `APP_STORE_METADATA.md` to the rating App Store Connect calculates.
- [ ] Do not describe DeuceMate as diagnosing or treating a medical condition.

---

## Build and test evidence

Codex ran the following checks on 11 July 2026:

- [x] `swift test`: 345 DeuceMateCore tests passed with zero failures.
- [x] Watch unit tests, including the StatsStore tests, passed on a Series 11
  46 mm watchOS 26.2 simulator.
- [x] iOS Release generic-simulator build succeeded and embedded the Watch app.
- [x] Watch Release simulator build succeeded.
- [x] An unsigned Release archive completed, but exposed Blocker 1's duplicate
  top-level Watch app. This is not a successful distribution validation.
- [x] Privacy, Support, and Marketing URLs all returned HTTP 200 on 11 July 2026:
  `https://emrahman.github.io/DeuceMate/privacy.html`,
  `https://emrahman.github.io/DeuceMate/support.html`, and
  `https://emrahman.github.io/DeuceMate/`.

Remaining gaps:

- [ ] The iOS unit-test target contains no assertions; the UI tests are launch
  and performance templates. Add coverage for important iPhone persistence,
  iCloud, export, and no-Watch flows.
- [ ] A signed App Store archive has not passed Organizer validation.
- [ ] HealthKit, iCloud restore, WatchConnectivity, foreground announcements,
  and backup exclusion have not been verified on a real iPhone and Watch.
- [ ] Run the full manual matrix on a TestFlight build: fresh install, upgrade,
  paired/unpaired Watch, signed-in/out of iCloud, iCloud Drive disabled, all
  HealthKit authorization states, and foreground/background transitions.

Non-blocking Release build warnings to clean up:

- [ ] `MatchExporter.swift` calls main-actor-isolated helpers from
  `nonisolated` synchronous functions. Resolve these before Swift language-mode
  changes turn the warnings into errors.
- [ ] Replace deprecated iOS 17 `onChange(of:perform:)` uses in Settings and the
  app entry point.

---

## Verified implementation details

- [x] The prior background-audio keep-alive was removed. Announcements are
  foreground-only and scores received while backgrounded are skipped.
- [x] Both app icons are 1024 x 1024 RGB images with no alpha channel, including
  the iOS light/dark/tinted variants.
- [x] Privacy manifests are bundled for both targets with current UserDefaults
  `CA92.1` and System Boot Time `35F9.1` reason codes.
- [x] Location use is heading-only; the code does not request GPS location.
- [x] `ITSAppUsesNonExemptEncryption = false` is declared on both targets.
- [x] The iPhone target correctly omits `NSHealthUpdateUsageDescription`; it
  reads HealthKit but does not write workouts.
- [x] App version/build is consistently `1.0.0` / `1` across both targets.
- [x] No third-party package dependencies or developer-controlled backend were
  found.
- [x] No production force-unwraps were found in the source audit.
- [x] The empty AccentColor asset falls back to system blue; this is polish, not
  an App Store blocker, because runtime theming is handled by `AppTheme`.

---

## Screenshot and demo-video plan

### Required formats

- [ ] Upload an accepted iPhone 6.9-inch portrait set: 1260 x 2736,
  1290 x 2796, or 1320 x 2868 pixels. A separate 6.5-inch set is only required
  when no 6.9-inch set is supplied.
- [ ] Upload one consistent accepted Watch size across every localization. Both
  416 x 496 (Series 10/11) and the existing 396 x 484 size are accepted; a
  separate 41 mm plus 45 mm set is not required.
- [ ] Confirm the accepted dimensions in Apple's current
  [screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)
  immediately before capture.

### Recommended shot list

Use one theme across the set. The first three images carry the most weight in
search results.

- **Watch:** live scoreboard mid-match, match setup, live stats,
  point-category sheet, and history.
- **iPhone:** live scoreboard, match detail stats, points graph with overlays,
  AI Coach sheet, archive list, and Manual Match Entry.
- Capture HealthKit-dependent screens on real hardware; simulators cannot
  provide authentic HealthKit workout data.
- Record the demo video on real devices where possible: Watch scoring -> iPhone
  live scoreboard -> foreground announcements.

---

## App Store Connect checklist

### Build and compliance

- [ ] Blockers 1-4 resolved in code, configuration, tests, and public copy.
- [ ] Archive and validate with Xcode 26 / the iOS 26 SDK or newer. Submissions
  have required this toolchain since 28 April 2026; see
  [Upcoming Requirements](https://developer.apple.com/news/upcoming-requirements/).
- [ ] Test the validated build on a real iPhone and Apple Watch, then TestFlight.
- [ ] HealthKit and iCloud production capabilities/container verified for the
  App ID and signed products.
- [ ] Final bundle ID `ehsan.DeuceMate` explicitly accepted as permanent.

### Store record

- [ ] App Review notes start with the no-Watch Manual Match Entry path and include
  the hardware demo video.
- [ ] App Privacy answers are based on final behavior, not the old absolute
  "on-device only" wording.
- [ ] Current age-rating questionnaire completed and metadata updated to match.
- [ ] EU Digital Services Act trader/non-trader status supplied. See Apple's
  [DSA guidance](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/).
- [ ] Content Rights question, support contact, copyright, app availability
  (including Mac/Vision compatibility), and manual/automatic release mode set.
- [ ] Accessibility Nutrition Labels claimed only after auditing the supported
  common tasks on both iPhone and Watch.
- [ ] Privacy, Support, and Marketing URLs rechecked while logged out immediately
  before submission.
- [ ] Correct iPhone and Watch screenshot sets uploaded and accepted.

### Final smoke test

- [ ] Fresh install without a paired Watch can create, inspect, and export a
  manually entered match.
- [ ] Paired Watch can create a match, live-sync it, finish it, and recover it on
  iPhone without duplicates.
- [ ] HealthKit off means no permission request, workout, or health values.
- [ ] HealthKit denial/revocation never blocks scoring or corrupts a match.
- [ ] iCloud disabled/signed out never blocks local history; a later sign-in
  backs up and restores the stripped archive correctly.
- [ ] No HealthKit-derived values appear in iCloud or third-party exports after
  the chosen compliance fix.
- [ ] Foreground announcements work; locking/backgrounding the iPhone stops them
  without a background-audio entitlement.

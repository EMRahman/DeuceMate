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

**Current status: not ready to submit.** Resolve Blockers 1-4, finalize the App
Privacy answer in Item 5, and complete a signed Organizer validation before
uploading a build.

Legend: `[ ]` to do, `[x]` verified, `[~]` partly verified or awaiting a product
decision.

---

## Copy-only follow-up - 13 July 2026

At the owner's direction, this follow-up updates disclosure and configuration
copy only; it makes no Swift implementation changes:

- [x] The Watch `NSHealthShareUsageDescription` now names heart rate, calories,
  steps, walking/running distance, and date of birth in both build
  configurations.
- [x] App Review notes and the Markdown/HTML privacy policy now distinguish
  DeuceMate's automatic app-managed iCloud Drive archive (HealthKit-derived
  fields stripped) from Apple-managed device backups and user-initiated
  exports.
- [x] The chosen disclosure says a user may deliberately share HealthKit-derived
  match data with another person or an AI/LLM for analysis, or include it in a
  manual archive backup. The developer has no backend and does not receive
  those exports.
- [x] The accepted HealthKit posture is now explicit: the Watch requests access
  on first launch. Once authorized, the HealthKit integration applies
  automatically to each match. Scoring remains available when access is denied
  or revoked; no in-app toggle is planned.
- [ ] This copy change does **not** exclude local files or preferences from
  Apple device backups, add health-specific export consent, or change what any
  export contains. Blocker 4 therefore remains open.

---

## Blockers

### 1. Archive configuration fixed; signed validation pending

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

**REPOSITORY FIX VERIFIED - 13 July 2026:** The embedded Watch target now uses
`SKIP_INSTALL = YES` in Debug and Release, its Release configuration no longer
pins a development signing identity, and the iPhone scheme archives only the
iPhone target. The existing target dependency and Embed Watch Content phase
continue to build and embed the Watch app.

An Xcode 26.2 unsigned Release archive completed successfully after the fix.
`Products/Applications` contained only `DeuceMate.app`, the Watch app remained
at `DeuceMate.app/Watch/DeuceMate Watch App.app`, and the archive metadata
identified `Applications/DeuceMate.app` with bundle identifier
`ehsan.DeuceMate`. No valid code-signing identity is installed on the audit
machine, so signed Organizer classification and App Store validation remain
owner steps.

Required work:

- [x] Set the embedded Watch target to `SKIP_INSTALL = YES` for archive builds.
- [x] Remove the redundant Watch app archive entry from the iPhone scheme.
- [x] Remove the explicit `Apple Development` identity from the Watch Release
  configuration and let automatic distribution signing choose the identity.
- [ ] Create a signed archive in Xcode Organizer and confirm it is classified as
  an iOS app archive with only `DeuceMate.app` at `Products/Applications`.
- [ ] Run **Distribute App -> App Store Connect -> Validate App** successfully.

### 2. iCloud Documents source configuration fixed; signed/device verification pending

**CODEX FINDING:** Before this fix,
`DeuceMate/DeuceMate/DeuceMate.entitlements` declared `CloudDocuments` and
`com.apple.developer.icloud-container-identifiers`, but not
`com.apple.developer.ubiquity-container-identifiers`. The app calls
`FileManager.url(forUbiquityContainerIdentifier:)` in `PhoneStatsStore.swift`,
so the source entitlements did not fully configure the advertised iCloud
Documents feature. Apple's
[iCloud configuration guide](https://developer.apple.com/documentation/Xcode/configuring-icloud-services)
states that enabling iCloud Documents adds both container entitlement arrays.

The original in-app guide in `PastMatchesView.swift` also told users to enable
**iCloud Backup**. This feature uses **iCloud Drive/Documents**, which is a
different setting and should be named accurately.

**REPOSITORY FIX VERIFIED - 13 July 2026:** The iPhone source entitlements now
declare `CloudDocuments`, `com.apple.developer.icloud-container-identifiers`,
and `com.apple.developer.ubiquity-container-identifiers`, with both container
arrays set to `iCloud.ehsan.DeuceMate`. Debug and Release both use that
entitlements file. An Xcode 26.2 Release simulator build succeeded, and its
generated simulated entitlement payload contained all three declarations.

The recovery sheet now says iCloud Drive and directs the user through
**Settings -> Apple Account -> iCloud -> Drive -> Sync this iPhone**, followed
by the per-app DeuceMate switch under **Saved to iCloud**. A simulator build
does not prove production-container assignment or distribution-signed
entitlements, so those checks remain open.

Required work:

- [x] Configure the iPhone target's source entitlements for iCloud Documents and
  the `iCloud.ehsan.DeuceMate` container.
- [x] Verify the source and generated simulator entitlements contain both
  `com.apple.developer.icloud-container-identifiers` and
  `com.apple.developer.ubiquity-container-identifiers`.
- [ ] Verify the distribution-signed product entitlements contain both
  container arrays and use the production `iCloud.ehsan.DeuceMate` container.
- [ ] Confirm iCloud Documents and the `iCloud.ehsan.DeuceMate` container are
  enabled for the production App ID in the Apple Developer portal.
- [x] Change the in-app recovery instructions from iCloud Backup to iCloud
  Drive, including the correct Settings path.
- [ ] Test upload, update, deletion, signed-out/Drive-disabled handling, and
  first-install restore on a physical iPhone using the production container.

### 3. HealthKit first-launch posture accepted; device verification pending

**PRODUCT DECISION - 13 July 2026:** The owner confirmed that the intended
experience is one optional HealthKit system request when the Watch app first
launches. watchOS normally presents the authorization prompt only until the user
makes a choice. When access is granted, each match automatically starts or
resumes a Tennis workout; when access is denied, revoked, partially granted,
or unavailable, tennis scoring must continue without the unavailable fitness
measurements. The user can review or revoke HealthKit authorization in system
settings.

No separate in-app workout toggle is planned. The earlier finding that public
copy promised an off-by-default toggle was stale: the current policy describes
HealthKit access as optional and explains denial and revocation. Apple's
[HealthKit HIG](https://developer.apple.com/design/human-interface-guidelines/healthkit/)
recommends requesting protected data in context, but the owner accepts the
first-launch request for this prominently advertised Watch fitness integration.
The unused `workoutSessionEnabled` wire key is technical debt, not a product
control or a submission blocker.

The Watch authorization request reads workout, heart rate, active and basal
energy, steps, walking/running distance, and date of birth. The Watch read-purpose
string now names those requested measurements. The privacy policy and App Review
notes now also state the first-launch timing and automatic per-match workout
behavior.

Required work:

- [x] Confirm the intended first-launch authorization and automatic per-match
  workout behavior; no separate in-app toggle is required by the chosen design.
- [x] Expand the Watch read-purpose string to accurately mention steps and
  walking/running distance.
- [x] Update `PRIVACY_POLICY.md`, `docs/privacy.html`, `APP_STORE_METADATA.md`,
  and App Review notes to describe the implemented behavior.
- [ ] Test fresh-install grant, denial, partial authorization, revocation, no
  date of birth, and HealthKit-unavailable behavior.

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

Chosen disclosure posture and remaining work before submission:

- [ ] Exclude health-bearing local archive files and related preferences from
  device backup, or remove the HealthKit-derived values from those stores.
- [~] The product copy now permits a user-initiated full-fidelity manual archive,
  including HealthKit-derived values. This disclosure does not resolve the fact
  that the Files picker can save it to iCloud Drive; confirm a compliant design
  before submission.
- [~] The product copy now permits user-initiated match, HTML, and AI/LLM
  analysis exports containing HealthKit-derived values. Review whether each
  recipient and purpose is permitted, then add specific informed consent for
  the exact data before it leaves DeuceMate.
- [ ] Add focused tests proving every cloud/export representation omits the
  protected fields or, for an approved consent-gated representation, contains
  only the fields the user expressly authorized.
- [x] Update the privacy policy and App Review notes to describe the current
  automatic-backup and user-export behavior without the false "never
  transmitted" claim.
- [ ] Re-audit the final App Privacy answers after the implementation and
  consent design are settled. Do not submit while the policy and behavior
  disagree.

---

## High-risk review items

### 5. Privacy copy reconciled; App Privacy answer pending

**CODEX FINDING:** The codebase has no developer-controlled web service and no
`URLSession` networking stack. Before this reconciliation, README, support,
marketing, and in-app copy went further and claimed that the app made no network
requests, never transmitted HealthKit data, and kept all data on the user's
devices. Those statements were not accurate because the app:

- automatically writes its stripped archive to the user's iCloud Documents
  container;
- sends match data between Watch and iPhone;
- creates user-initiated exports and AI-app hand-offs; and
- generates seven external AI-service links in the HTML match experience.

The public policy also previously described an obsolete iPhone Documents
storage path and `.completeFileProtection`, while the canonical phone archive
uses Application Support and the stores use
`.completeFileProtectionUntilFirstUserAuthentication`.

**REPOSITORY FIX VERIFIED - 13 July 2026:** Current public, support, and in-app
copy now uses one description of the implemented behavior: the developer has no
backend and does not collect or receive DeuceMate data; WatchConnectivity sync
is local; the automatic archive uses the user's personal iCloud Drive and
excludes HealthKit measurements; and user-initiated exports or AI hand-offs are
handled by the recipient or service the user selects. File-specific statements
that the self-contained HTML export opens without automatic network requests,
and that compass data stays on-device, remain because those narrower claims are
accurate. Settings now opens the dedicated Support & FAQ page directly.

Required work:

- [x] Replace "no network" / "never transmitted" with the narrower and accurate
  claim: no developer-controlled backend and no data collected by the developer;
  system-managed personal iCloud storage and explicit user sharing are separate.
  Completed across store metadata, privacy, README, marketing, support, user
  guide, App Review notes, and current iPhone/Watch copy.
- [x] Reconcile `APP_STORE_METADATA.md`, `PRIVACY_POLICY.md`,
  `docs/privacy.html`, `docs/support.html`, README, App Review notes, and in-app
  copy from one agreed description of the implemented behavior.
- [x] Update the policy's storage locations, file-protection class, and date.
- [x] Point Settings -> Support & FAQ directly to `docs/support.html` rather
  than the marketing root.
- [~] "Data Not Collected" may remain the correct App Privacy answer under
  Apple's developer-access definition, but do not justify it by claiming that
  no information ever leaves either device.

### 6. The iPhone experience must be reviewable without a Watch

Reviewers may not pair an Apple Watch. The no-Watch review path is
**Manual Match Entry -> history -> statistics -> points graph -> export**.

- [x] Manual Match Entry is reachable from the "No Apple Watch Paired" empty
  state in `PastMatchesView.swift`.
- [x] Put Manual Match Entry first in the App Review notes' test instructions.
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

Codex ran the following checks on 11 and 13 July 2026:

- [x] `swift test`: 345 DeuceMateCore tests passed with zero failures.
- [x] Watch unit tests, including the StatsStore tests, passed on a Series 11
  46 mm watchOS 26.2 simulator.
- [x] iOS Release generic-simulator build succeeded and embedded the Watch app.
- [x] Watch Release simulator build succeeded.
- [x] After the Blocker 1 configuration fix, an unsigned Release archive
  contained one top-level `DeuceMate.app`, retained the embedded Watch app, and
  included iOS application archive metadata. This is not a signed distribution
  validation.
- [x] An Xcode 26.2 Release simulator build succeeded after the Blocker 2 source
  fix; its generated simulated entitlements contained `CloudDocuments` and both
  iCloud container arrays for `iCloud.ehsan.DeuceMate`.
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
- [ ] A fresh Watch install presents the optional HealthKit request; granting
  access starts or resumes one Tennis workout per match and records only the
  measurements the user authorized.
- [ ] HealthKit denial/revocation never blocks scoring or corrupts a match.
- [ ] iCloud disabled/signed out never blocks local history; a later sign-in
  backs up and restores the stripped archive correctly.
- [ ] The automatic app-managed iCloud archive contains no HealthKit-derived
  values; any approved user-initiated export follows the final disclosure and
  consent design.
- [ ] Foreground announcements work; locking/backgrounding the iPhone stops them
  without a background-audio entitlement.

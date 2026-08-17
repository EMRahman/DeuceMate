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

**Current status: rejected under Guideline 2.1 - Information Needed (August
2026); Resolution Center reply sent 17 August 2026, Apple's decision pending.**
Apple cited no bug, crash, or guideline violation in the app itself. The
rejection is the standard new-app information request: a screen recording
captured on a physical device running the latest OS, plus six written answers
(devices tested, app description and audience, setup instructions, external
services, regional differences, and regulated-industry/third-party-material
status). The seven-item response sent on 17 August 2026 and the recording
capture plan are in
[`APP_STORE_METADATA.md`](APP_STORE_METADATA.md#app-review-information--notes-guideline-21-information-request);
that block links the recording on YouTube rather than attaching a file; the
video has since been taken down and the link is marked `<video removed>`
pending a replacement. Update the OS versions, TestFlight build number, and
the recording link before reusing it for a future submission.

Build 2 was archived, uploaded, installed via TestFlight as an
upgrade, and confirmed at `1.0.0 (2)` before submission. The App Privacy
answer, age-rating questionnaire (calculated 9+, matching the prediction), and
EU DSA trader/non-trader declaration (non-trader) were completed as part of
the mandatory App Store Connect submission flow. The reproducible
physical-device cases for Blockers 2-4 are complete; HealthKit-unavailable
remains documented as not manually reproducible on supported hardware. No demo
video was attached to the App Review notes for the 6 August submission; the 2.1
information request subsequently asked for one, so a physical-device recording
was captured and linked (rather than attached) in the 17 August 2026
Resolution Center reply.

Legend: `[ ]` to do, `[x]` verified, `[~]` partly verified or awaiting a product
decision.

---

## Next manual pass - 5-6 August 2026

This is the next useful test order after reviewing the current source and the
4 August device evidence. Production-code changes since the first TestFlight
pass are limited to the iPhone fresh-Watch synchronization fix in PR #78:
empty manifests now complete **Sync Now**, Watch installation/reachability state
refreshes after activation, and successful syncs show both device counts plus
zero-on-Watch guidance. The Watch sender, scoring engine, HealthKit flow, iCloud
archive policy, backup exclusion, and export-consent paths did not change.

The full iOS scheme passed again on 5 August 2026 on an iPhone 17 Pro iOS 26.3
simulator, including the three focused PR #78 tests and the no-Watch manual-entry
and export UI route. One opt-in marketing-screenshot helper was skipped as
designed. The remaining risk is the real WatchConnectivity lifecycle, which a
simulator/unit test cannot prove; the 6 August device pass below subsequently
verified that behavior.

**OWNER DEVICE VERIFICATION - 6 August 2026:** The owner completed manual steps
2-9 from the prioritized handoff on physical iPhone and Apple Watch hardware and
reported that all passed. This covered the fresh empty-Watch state and live
installation status, empty-manifest **Sync Now** result and counts, selected
**Sync to Watch** restore, new Watch match transfer without duplication,
unreachable/reachable recovery, the no-Watch reviewer path, Health-bearing and
Health-free exports, foreground/background announcements, and local archive use
with iCloud Drive unavailable. The behavior gate is therefore closed. Build 2
was subsequently uploaded and installed via TestFlight as an upgrade, confirmed
at `1.0.0 (2)`, and submitted to Apple for review on 6 August 2026.

### 1. Prepare one exact release candidate

- [x] Increment `CURRENT_PROJECT_VERSION` from `1` to `2` for both the iPhone app
  and embedded Watch app in Debug and Release, while keeping
  `MARKETING_VERSION = 1.0.0`. **Repository update - 6 August 2026.** Test-target
  build numbers remain at 1 because they are not shipped.
- [x] Commit the intended release changes, archive and upload build 2, then
  install it from TestFlight as an **upgrade** over the previous iPhone build.
  Confirm iPhone and Watch both display `1.0.0 (2)`, launch successfully, retain
  the existing archive/settings without duplicates, and complete one basic
  **Sync Now**. This is a distribution-candidate sanity check, not a repeat of
  the already-passed full matrix. **Owner verification — confirmed via
  TestFlight before the 6 August 2026 submission.**

### 2. Test the fixed fresh-Watch path first - submission gate

Start with at least two archived iPhone matches and a newly installed Watch app
with zero Watch matches. Keep iPhone Settings -> Connection Details visible
where a step specifically asks for live state.

- [x] Remove/reinstall or freshly install the Watch app and verify **Watch App
  Installed** changes to **Yes** without relaunching the iPhone app. Confirm
  **Watch Paired**, **Watch Reachable**, and **Pending Transfers** remain
  truthful rather than frozen at their activation-time values.
- [x] With the empty Watch app open and reachable, tap **Sync Now**. Within ten
  seconds it must show **Sync complete**, never **No response from watch**. The
  message must report the correct non-zero iPhone count, **Apple Watch: 0
  matches**, and the fresh-Watch **Sync to Watch** guidance.
- [x] Open one older iPhone match, choose **Sync to Watch**, and confirm exactly
  that match appears in Watch history. Run **Sync Now** again and verify the
  counts update (for example, iPhone: 2 matches / Apple Watch: 1 match) and the
  fresh-Watch guidance disappears.
- [x] Create a distinct short match on the Watch, exercise score and undo, watch
  the live iPhone scoreboard update, then finish the match. Confirm it appears
  exactly once in the iPhone archive, the older restored match is not
  duplicated, and a final **Sync Now** reports the expected counts.
- [x] While Connection Details stays open, make the Watch temporarily
  unreachable, then open the Watch app again. **Watch Reachable** may correctly
  say **No (normal)** while unavailable, but it must recover without an iPhone
  relaunch; **Ping Watch** and **Sync Now** must succeed once reachable.

If any of these fail, stop the submission and record the exact iPhone/Watch
build numbers, which apps were foregrounded, the displayed counts/state, and
whether the failure recovered after relaunch. If all pass, the only known
code/device submission gate is cleared.

### 3. Concise final-candidate smoke pass

- [x] On an unpaired/spare iPhone if available, follow the reviewer route:
  **Manual Match Entry -> history -> detail -> statistics/Points Graph ->
  export**. It must not wait indefinitely for WatchConnectivity. The automated
  version of this path already passes, but one TestFlight pass is still useful.
- [x] Open one Health-bearing archived match and one Health-free match. Confirm
  a health-bearing export still names the fields present and Cancel stops the
  share flow; confirm the Health-free export still opens sharing directly.
- [x] With both apps foregrounded, confirm one live score announcement. Lock or
  background the iPhone for the next point and confirm it stays silent, then
  foreground it and confirm announcements resume.
- [x] Launch the archive with iCloud Drive temporarily unavailable and confirm
  local history still opens. A destructive clean restore or a repeat of the
  full signed-out/deletion/backup-exclusion matrix is **not** needed unless the
  final candidate changes those already-verified code paths.

Do not hold submission for the HealthKit-unavailable cases: supported physical
hardware does not expose a reproducible way to force `HKHealthStore` itself to
be unavailable, and grant, denial, partial authorization, and revocation have
already passed.

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
- [x] ~~This copy change does **not** exclude local files or preferences from
  Apple device backups, add health-specific export consent, or change what any
  export contains. Blocker 4 therefore remains open.~~ **Superseded:** the
  device-backup work (15 July) excludes the Health-bearing local files, and the
  export-consent gate (16 July, PRs #64–#68) added the health-specific
  disclosure. Blocker 4's code is resolved; only owner device/App-Store-Connect
  steps remain.

---

## Implementation update - 15 July 2026

Birth year is no longer read from HealthKit. This is a code change (not copy),
made to shrink the HealthKit surface and remove a health-derived value from
`UserDefaults` ahead of the Blocker 4 device-backup work:

- [x] Removed the HealthKit `dateOfBirth` read (`WorkoutManager` no longer
  requests the characteristic; `requestBirthYearAuthorization` /
  `fetchBirthYearFromHealth` deleted). Birth year is now entered by the user in
  the app's Birth Year picker only. Max HR resolves as
  `manual override → 220 − age → 190`.
- [x] Deleted the `userBirthYearFromHealth` provenance flag and the dead
  computed-percentile path (`maxHRComputed`, the `pulseCoachMaxHR` wire key, and
  the `historical99thPct` parameter of `HRZone.resolveMaxHR`). The watch now
  computes the resolved max HR locally from the synced birth year and override.
- [x] Reconciled the Watch `NSHealthShareUsageDescription`, privacy policy
  (Markdown + HTML), and App Store metadata / App Review notes to drop date of
  birth from the HealthKit read list. This supersedes the 13 July copy-follow-up
  statement that the usage string names date of birth.
- See `docs/features/TECHNICAL_DEBT.md` #16 for the full rationale.

---

## Device-backup implementation update - 15 July 2026

The five HealthKit-derived match fields are now separated from the iPhone's
normally backed-up canonical history. `matchHistory.json` contains the stripped
records; `healthData.json` contains only the Health projection and is
marked backup-excluded after every save. The watch's Health-bearing match
history and live state files are likewise marked backup-excluded after every
atomic write. Automatic iCloud Drive and iPhone device restores therefore retain
scores and non-health statistics but not recorded heart rate, steps, distance,
or calories. A restored Watch starts without those backup-excluded files;
selected records can be copied back from the iPhone archive. A user-initiated
manual archive remains the full-fidelity migration path on iPhone.

- [x] Added pure split/merge policy tests covering all five protected fields.
- [x] Added app-target tests for legacy migration, corrupt/missing sidecars,
  unreadable-main write suspension, import repair, and repeated backup-exclusion
  application.
- [x] Verify exclusion and restore behavior on signed physical iPhone and Apple
  Watch hardware before submission. **Owner verification — 4 August 2026:** the
  iPhone restore retained scores and non-Health tennis statistics while heart
  rate, steps, calories, and distance did not return. The backup-excluded Watch
  history/live-state files did not repopulate the Watch; selected stripped
  records could be copied back from the restored iPhone archive with **Sync to
  Watch**. The manual full-fidelity archive remained the successful control path
  for restoring the HealthKit-derived measurements on iPhone.

---

## Export-consent implementation update - 16 July 2026

The consent gate from Blocker 4 is now implemented across every user-initiated
export path (PRs #64–#67). Per the 16 July decision, exports stay
**full-fidelity** — the change adds an informed **disclosure**, not stripping:

- A single Core policy, `HealthExportConsent`, is the source of truth. It reports
  exactly which HealthKit-derived fields a given export would expose
  (`presentFields` for rendered text/HTML/AI; `archiveFields` for the raw manual
  archive) and builds the "Share health data?" copy naming those fields plus the
  recipient.
- The iPhone match-detail share menu (summary/full/HTML, both perspectives), the
  AI Coach hand-off, and the Settings manual-archive export each present that
  disclosure before a health-bearing export leaves the device; a match with no
  recorded health data exports without a prompt.
- Rendered exports gate totals on `> 0` (they omit zeros); the raw archive
  discloses any non-nil value, including a stored `0` that still ships in the JSON.

- [x] Consent gate implemented for the share menu, AI hand-off, and manual
  archive; disclosure copy centralised in Core.
- [x] Proving tests: `HealthExportConsentTests` verifies the disclosure names
  exactly the fields each representation exposes (per perspective and export
  kind, and for the raw archive); a UI test confirms health-free matches skip the
  prompt and share directly.
- [x] Verify the health-bearing disclosure on a real match (with recorded
  HealthKit data) on signed hardware. **Owner verification — 1 August 2026:** on
  the production-signed TestFlight build, the text/summary, HTML, AI Coach, and
  manual-archive export paths all showed the health-specific disclosure before
  sharing; the named fields matched the data present, Cancel prevented the Share
  sheet from opening, confirmation opened the expected sharing flow, and a
  health-free match exported directly without an unnecessary prompt.

---

## Configuration re-audit - 18 July 2026

A three-surface re-audit (project configuration, code behavior, and store
metadata/docs, including every change merged after 16 July — PRs #68–#70) found
**no new blockers**. Changes from that pass:

- [x] Corrected two "Verified implementation details" entries below (the Watch
  privacy-manifest reason codes and the iOS icon appearance variants were
  overstated).
- [x] Recorded three newly verified configuration facts below (`WKApplication`
  in the generated Watch Info.plist, the `LSApplicationQueriesSchemes` ↔
  `AICoachLauncher` match, and the WatchConnectivity transit shape).
- [x] Added the iPhone-side HealthKit prompt to the Blocker 3 device matrix and
  the final smoke test — the previous matrix was Watch-only.
- [x] Reconciled the remaining "iCloud backup" wording in `SUPPORT_PAGE.md`,
  `docs/support.html`, and the `docs/index.html` badge to the iCloud Drive
  archive terminology agreed in Item 5.

---

## TestFlight fresh-Watch sync finding - 1 August 2026

**CODEX FINDING — FIX BEFORE SUBMISSION:** A production-signed TestFlight build
was installed on an iPhone and a freshly installed paired Apple Watch. Live
reachability and normal match transfer worked, but the empty-Watch recovery path
displayed two misleading failure states:

- The iPhone showed **Watch App Installed: No** while the Watch app was open and
  reachable. `PhoneMatchSyncService` snapshots `session.isWatchAppInstalled`
  during initial activation but does not refresh it through
  `sessionWatchStateDidChange(_:)` when installation state changes.
- **Sync Now** ended with **No response from watch** when the fresh Watch had no
  match history. The Watch correctly replied with an empty manifest, but
  `MatchSyncTransport.sendHistory` intentionally sends no history payload for an
  empty array and the iPhone does not count the manifest as a completed sync.
  Once the Watch held a new match, the same path reported **Sync complete** and
  transferred it normally.

The empty Watch is expected after a fresh installation. The iPhone archive may
have been restored from iCloud, but archived matches are not automatically
copied back to the Watch; the user can restore selected records with each
match's **Sync to Watch** action, subject to the Watch's 25-match rolling cap.

**OWNER DEVICE VERIFICATION - 1 August 2026:** The following passed on the
production-signed TestFlight build:

- [x] A fresh first-install iCloud restore completed without hanging or creating
  duplicate matches.
- [x] The expected matches, scores, and normal tennis statistics were restored.
- [x] Heart rate, steps, calories, and distance were absent from the restored
  matches, as required for the automatic Health-stripped iCloud archive.
- [x] Merging a previously exported full-fidelity manual archive restored the
  recorded HealthKit-derived data, confirming the intended user-initiated
  full-fidelity migration path.
- [x] Restoring a selected older iPhone match with **Sync to Watch** worked, and
  a newly created Watch match synced back to the iPhone normally.

Those 1 August results did not by themselves verify Apple device-backup
exclusion or the remaining iCloud and HealthKit cases; the reproducible gaps
were subsequently verified on signed hardware on 4 August 2026 below.

Required work:

- [x] Treat receipt of a Watch manifest — including an empty manifest — as a
  successful response to **Sync Now**, rather than allowing the ten-second
  timeout to report a connectivity failure. **Repository fix — 4 August 2026.**
- [x] Refresh the published paired/installed Watch state from
  `sessionWatchStateDidChange(_:)` so Connection Details reflects the live
  installation state. **Repository fix — 4 August 2026.**
- [x] After a successful sync, show the iPhone and Watch match counts. When the
  iPhone has archived matches and the Watch has none, explain that a fresh Watch
  starts empty and direct the user to open a match and choose **Sync to Watch**
  if they want to copy selected records back. **Repository fix — 4 August 2026.**
- [x] Add focused tests for an empty-manifest sync response, Watch installation
  state changes, and the zero-on-Watch restore guidance. **Added 4 August 2026.**
- [x] Verify the corrected empty-Watch flow on a new TestFlight build: no false
  error, accurate installation state/counts, selected **Sync to Watch** restore,
  and normal Watch-to-iPhone transfer of a newly created match. **Behavior
  verified on physical devices - 6 August 2026;** build 2's TestFlight
  install/build-number and basic launch/sync sanity were subsequently confirmed
  ahead of the 6 August 2026 submission.

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
- [x] Create a signed archive in Xcode Organizer and confirm it is classified as
  an iOS app archive with only `DeuceMate.app` at `Products/Applications`.
- [x] Run **Distribute App -> App Store Connect -> Validate App** successfully.

### 2. iCloud Documents source, signing, and device behavior verified

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
by the per-app DeuceMate switch under **Saved to iCloud**.

**OWNER VERIFICATION - 1 August 2026:** The production App ID has iCloud enabled
with the `iCloud.ehsan.DeuceMate` container assigned. Xcode 26.2 generated a new
App Store distribution profile containing `CloudDocuments`, both required
container arrays, and the production container environment. The resulting
signed iOS archive passed App Store Connect validation.

Required work:

- [x] Configure the iPhone target's source entitlements for iCloud Documents and
  the `iCloud.ehsan.DeuceMate` container.
- [x] Verify the source and generated simulator entitlements contain both
  `com.apple.developer.icloud-container-identifiers` and
  `com.apple.developer.ubiquity-container-identifiers`.
- [x] Verify the distribution-signed product entitlements contain both
  container arrays and use the production `iCloud.ehsan.DeuceMate` container.
- [x] Confirm iCloud Documents and the `iCloud.ehsan.DeuceMate` container are
  enabled for the production App ID in the Apple Developer portal.
- [x] Change the in-app recovery instructions from iCloud Backup to iCloud
  Drive, including the correct Settings path.
- [x] Test upload, update, deletion, signed-out/Drive-disabled handling, and
  first-install restore on a physical iPhone using the production container.
  **1 August 2026:** first-install restore passed on the production-signed
  TestFlight build with the expected scores/statistics, no duplicates or hang,
  and no HealthKit-derived measurements. **Owner verification — 4 August 2026:**
  new and updated archive states backed up without duplicates, and deletion
  tombstones survived a clean restore without resurrection. Signed-out and
  Drive-disabled states left local history fully usable; signing back in and
  re-enabling Drive resumed the stripped archive backup and restore.

### 3. HealthKit first-launch posture and reproducible device states verified

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
energy, steps, and walking/running distance. (Date of birth is no longer read —
see the 15 July 2026 implementation update; birth year is now user-entered.) The
Watch read-purpose string now names those requested measurements. The privacy
policy and App Review notes now also state the first-launch timing and automatic
per-match workout behavior.

Required work:

- [x] Confirm the intended first-launch authorization and automatic per-match
  workout behavior; no separate in-app toggle is required by the chosen design.
- [x] Expand the Watch read-purpose string to accurately mention steps and
  walking/running distance.
- [x] Update `PRIVACY_POLICY.md`, `docs/privacy.html`, `APP_STORE_METADATA.md`,
  and App Review notes to describe the implemented behavior.
- [x] Test the manually reproducible fresh-install grant, denial, partial
  authorization, and revocation states. (The date-of-birth authorization case was
  removed on 15 July 2026 — the app no longer reads it.) **Owner device
  verification — 1 August 2026:** the production TestFlight Watch app presented
  the expected first-launch request. With every Health permission denied, a
  short match supported scoring, undo, completion, and Watch-to-iPhone sync
  without another blocking prompt; it saved no Health-derived match fields or
  Tennis workout, showed the expected health-empty UI, and exported without a
  health-sharing disclosure. **Owner verification — 4 August 2026:** full grant
  created one Tennis workout per match and recorded the authorized measurements;
  partial authorization recorded only available measurements; revocation did not
  block scoring, undo, completion, or Watch-to-iPhone sync, corrupt a match, or
  cause another blocking prompt. Health-bearing export disclosures continued to
  match the fields present.
- [~] HealthKit-unavailable behavior cannot be manually forced on supported
  physical hardware, so it remains an explicitly unverified platform state.
- [~] Test the iPhone's own HealthKit read prompt (`HealthKitHRFetcher`),
  triggered the first time the user selects the Per-point avg heart-rate view
  in the Points Graph or Pulse Coach section: verify grant, denial, and
  HealthKit-unavailable states on a health-bearing match, with scoring and all
  non-heart-rate statistics unaffected. (Added 18 July 2026 — the earlier
  matrix covered only the Watch prompt.) **Owner device verification — 1 August
  2026:** on the production TestFlight build, denied access showed the expected
  Settings guidance only for Per-point avg while Raw and Smoothed remained
  available from the match's stored snapshots; after access was granted,
  Per-point avg loaded correctly. The HealthKit-unavailable case remains open.

### 4. Health-derived data protections implemented; ASC answer pending

**CODEX FINDING:** `ArchiveBackupPolicy` correctly strips the match's five
HealthKit-derived metrics from the app-managed iCloud archive. Other paths still
need resolution before the document can claim Health data stays on-device:

- ~~Full records containing health-derived values are stored in Documents or
  Application Support on iPhone and Watch, and are not marked as excluded from
  normal device backup.~~ **Resolved 15 July 2026:** the phone persists a
  health-stripped main archive plus a backup-excluded Health sidecar, and both
  Health-bearing watch files reapply backup exclusion after every save.
- ~~Health-derived preferences such as birth-year provenance and Pulse Coach max
  heart rate are stored in `UserDefaults`, which is also part of device backup.~~
  **Resolved 15 July 2026:** the birth-year provenance flag and the computed max
  heart rate were removed (see the implementation update above). The remaining
  Pulse Coach preferences in `UserDefaults` — the user-entered birth year and the
  manual max-HR override — are user-supplied values, not HealthKit-derived data.
- ~~Full-fidelity manual archive export can be saved to iCloud Drive.~~
  **Addressed 16 July 2026:** the export now names iCloud Drive as a possible
  destination and requires confirmation; it remains a user-chosen, user-owned
  location, not developer-managed iCloud storage.
- ~~Normal text, HTML, and AI exports can contain heart rate, zones, steps,
  calories, and distance. The opponent summary still receives match-level
  movement/energy totals, and the AI hand-off has no health-specific consent.~~
  **Resolved 16 July 2026:** every such export now presents the per-export
  disclosure — including the opponent summary and the AI hand-off — before
  leaving the device (see the implementation update above).

Guideline 5.1.3 says apps may not store personal health information in iCloud.
Apple's
[HealthKit privacy guidance](https://developer.apple.com/documentation/healthkit/protecting-user-privacy)
also limits disclosure to third parties and requires prior express consent.
Treat these paths as unresolved rather than assuming user-controlled backup or
the generic Share sheet makes every transfer compliant.

**PRODUCT DECISION - 15 July 2026:** The owner chose to **consent-gate**
health-bearing user exports rather than strip them. The automatic app-managed
iCloud archive stays HealthKit-stripped (unchanged); the manual full-fidelity
archive and the match / HTML / AI-analysis exports may still contain the five
HealthKit-derived fields, but only behind an explicit, informed consent step
that names the exact data being shared and the recipient/purpose before it
leaves DeuceMate.

**Refinement (16 July 2026):** the consent is a per-export **disclosure that
always includes health data** — a two-way *Share / Cancel* prompt, not a
three-way include/exclude. An opt-out that strips health is deferred to future
work. **Implemented 16 July 2026** (PRs #64–#67); see the export-consent
implementation update above.

Chosen disclosure posture and remaining work before submission:

- [x] Exclude health-bearing local archive files from device backup, while
  retaining a normally backed-up health-stripped phone archive. The remaining
  preferences are user-entered rather than HealthKit-derived (implemented and
  tested 15 July 2026; signed-device restore verified 4 August 2026).
- [x] The manual full-fidelity archive export is now gated behind the
  informed-consent step (PR #67, 16 July 2026). The disclosure names iCloud Drive
  as a possible destination; the archive remains a user-chosen, user-owned
  location, not developer-managed iCloud storage.
- [x] User-initiated match, HTML, and AI/LLM analysis exports keep the health
  fields but now show the specific informed-consent step before any such export
  or AI hand-off (PRs #65–#66, 16 July 2026), including the opponent summary.
- [x] Focused tests prove the consent-gated representation discloses exactly the
  fields it exposes: `HealthExportConsentTests` cross-checks `presentFields`
  against the rendered exporters (both perspectives, both export kinds) and
  covers the raw archive's non-nil field set; a UI test confirms the health-free
  path shares directly.
- [x] Update the privacy policy and App Review notes to describe the current
  automatic-backup and user-export behavior without the false "never
  transmitted" claim; the per-export disclosure is now documented there too
  (16 July 2026).
- [~] In App Store Connect, select **No, we do not collect data from this app**
  and compare the resulting product-page preview with the final privacy policy
  before publishing the answer. The codebase audit and Apple's current
  definition support **Data Not Collected**: DeuceMate has no developer backend
  or integrated third-party vendor code, and neither the user's personal iCloud
  container nor an explicit user-directed export gives the developer access to
  the data. Do not submit while the ASC answer and policy disagree. *Some* App
  Privacy answer was necessarily submitted for the 6 August 2026 submission —
  it's a mandatory App Store Connect gate — but which value was selected, and
  whether the product-page preview was compared against the policy, is
  unconfirmed. Leave open until the owner confirms the selected answer was
  exactly **Data Not Collected**.

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
- [x] **Data Not Collected** is the recommended App Privacy answer under
  [Apple's current definition](https://developer.apple.com/app-store/app-privacy-details/).
  Apple defines collection around off-device data accessible to the developer
  or integrated third-party vendor code; the source audit found neither. Keep
  the narrower public explanation: personal iCloud storage and explicit
  user-directed sharing can move data off-device even though the developer does
  not collect it.

### 6. The iPhone experience must be reviewable without a Watch

Reviewers may not pair an Apple Watch. The no-Watch review path is
**Manual Match Entry -> history -> statistics -> points graph -> export**.

- [x] Manual Match Entry is reachable from the "No Apple Watch Paired" empty
  state in `PastMatchesView.swift`.
- [x] Put Manual Match Entry first in the App Review notes' test instructions.
- [x] Provide a demo video showing Watch scoring, iPhone live scoreboard, and
  foreground announcements. It was not attached for the 6 August 2026
  submission, and Apple's Guideline 2.1 information request explicitly asked
  for a screen recording captured on a physical device running the latest OS,
  beginning with app launch and showing every sensitive data prompt. Captured
  per the capture plan in
  [`APP_STORE_METADATA.md`](APP_STORE_METADATA.md#demo-screen-recording--capture-plan)
  and linked (rather than attached, to stay under the Resolution Center
  attachment limit) in the 17 August 2026 Resolution Center reply. That video
  has since been taken down; the link is marked `<video removed>` in
  `APP_STORE_METADATA.md` pending a replacement.
- [x] Confirm every central iPhone screen has a useful no-Watch state and no
  indefinite connectivity loading state. WatchConnectivity activation now
  leaves the connecting state after at most 10 seconds (and immediately when
  unsupported); manually entered matches expose truthful statistics and Points
  Graph empty states plus the normal export menu. Four focused iOS unit tests
  and the Manual Entry -> history -> detail -> export UI test passed on an
  unpaired iPhone 17 Pro simulator with Xcode 26.2 on 13 July 2026.

### 7. Age rating needs the current questionnaire

**CODEX FINDING:** The existing checklist assumes age 4+. Apple's current age
rating questionnaire includes **Health or Wellness Topics**, including exercise
recommendations and calorie tracking. DeuceMate's heart-rate zones, fitness
coaching, and calorie display mean the calculated rating is likely 9+ on newer
OS versions, subject to App Store Connect's regional result.

- [x] Complete the current questionnaire accurately instead of forcing the old
  4+ assumption. See Apple's
  [age-rating definitions](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions).
  **Owner confirmation — 6 August 2026:** the App Store Connect questionnaire
  calculated **9+**, matching the Health/Wellness-topics prediction.
- [x] Update `APP_STORE_METADATA.md` to the rating App Store Connect calculates.
  **16 July 2026:** the metadata stated the expected **9+** (Health/Wellness
  topics) instead of the stale 4+. **Confirmed 6 August 2026:** the
  ASC-calculated rating is 9+, matching the metadata as written.
- [x] Do not describe DeuceMate as diagnosing or treating a medical condition.
  **Audited 16 July 2026:** no diagnose/treat/medical-condition language in the
  public or in-app copy — the coaching insights are tennis-performance advice
  (one clinical-sounding verb in `USER_GUIDE.md` softened to "recommends").

---

## Build and test evidence

Codex ran the following checks on 11 and 13 July and 4-5 August 2026:

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
- [x] On 1 August 2026, an Xcode 26.2 signed iOS archive used App Store
  distribution profiles for the iPhone and embedded Watch products, included
  the production iCloud Documents entitlements for `iCloud.ehsan.DeuceMate`,
  and passed **Validate App** in Organizer.
- [x] On 4 August 2026, the full iOS `DeuceMate` scheme passed on an iPhone 17
  Pro iOS 26.3.1 simulator, including the new empty-manifest acknowledgement,
  live Watch-installation state, and zero-on-Watch count/guidance tests. The one
  opt-in marketing screenshot helper remained intentionally skipped.
- [x] On 5 August 2026, the full iOS `DeuceMate` scheme passed again on an
  iPhone 17 Pro iOS 26.3 simulator from the current checkout. All app unit and
  UI tests passed; the same opt-in marketing-screenshot helper was skipped as
  designed.
- [x] On 6 August 2026, a Release generic-simulator build succeeded after the
  build-number increment. The generated iPhone app and its embedded Watch app
  both report `CFBundleShortVersionString = 1.0.0` and `CFBundleVersion = 2`.

Remaining gaps:

- [~] The iOS targets now cover WatchConnectivity activation fallbacks and the
  Manual Entry -> history -> detail empty states -> export no-Watch route.
  `PhoneStatsStoreTests` now also covers the on-device persistence contract:
  the Health-sidecar split/merge and backup exclusion, tombstone persistence and
  no-resurrection across reload (via `syncToPhone`/`mergeIncoming`), legacy
  Documents migration into the backup-excluded canonical store, `appendMatch`
  same-id update semantics, manual `.replace` import, and read-failure ≠ empty
  archive on both the history and tombstone files. The shared Core target already
  covers backup policy and export derivation. **Device-only verification:** the
  iCloud ubiquity-container push/restore path uses
  `FileManager.url(forUbiquityContainerIdentifier:)`, which is not injectable;
  its production-container matrix passed on signed hardware by 4 August 2026 but
  remains outside automated coverage.
- [~] Signed-device verification is substantially complete. The production
  TestFlight build has passed first-install iCloud restore, selected
  iPhone-to-Watch restore, new-match Watch-to-iPhone transfer, health-bearing
  export consent, and foreground/background announcement behavior. The
  reproducible HealthKit authorization matrix, previously outstanding iCloud
  states, and backup exclusion passed on signed hardware by 4 August 2026. The
  corrected
  fresh-Watch sync result and broader connectivity transitions still need a new
  TestFlight build.
- [~] The broad physical-device matrix has been run across the 1 and 4 August
  passes. On the final TestFlight candidate, run the focused fresh-Watch,
  upgrade, connectivity-transition, and concise smoke sequence in **Next manual
  pass** above. Do not repeat destructive restore/authorization combinations
  whose code did not change unless the candidate exposes a regression.

Non-blocking Release build warnings to clean up:

- [x] `MatchExporter.swift` calls main-actor-isolated helpers from
  `nonisolated` synchronous functions. **Resolved 15 July 2026:** the whole
  pure string-builder type is now `nonisolated`, so its private helpers are
  non-isolated too and the public builders call them without a main-actor
  warning. No behavior change; the iOS unit-test build is warning-free for this
  file.
- [x] Replace deprecated iOS 17 `onChange(of:perform:)` uses in Settings and the
  app entry point. **Resolved 15 July 2026:** the four sites in `DeuceMateApp`
  and `SettingsView` now use the two-parameter `onChange(of:_:)` form. The
  `.build` grep and the iOS test build report zero `onChange(of:perform:)`
  deprecation warnings.

---

## Verified implementation details

- [x] The prior background-audio keep-alive was removed. Announcements are
  foreground-only and scores received while backgrounded are skipped. **Owner
  device verification — 1 August 2026:** the production TestFlight build spoke
  points while both apps were foregrounded, stayed silent while the iPhone was
  locked or DeuceMate was backgrounded, and resumed announcements after the app
  returned to the foreground.
- [x] Both app icons are 1024 x 1024 RGB images with no alpha channel. The iOS
  set ships light and tinted assets; the dark appearance reuses the light PNG
  per the asset catalog's `Contents.json`.
- [x] Privacy manifests are bundled for both targets. The iPhone manifest
  declares UserDefaults `CA92.1` and System Boot Time `35F9.1`
  (`ProcessInfo.systemUptime` is used only in `LiveScoreboardView.swift`); the
  Watch manifest declares `CA92.1` only, which is correct because the Watch app
  uses no boot-time API.
- [x] Location use is heading-only; the code does not request GPS location.
- [x] `ITSAppUsesNonExemptEncryption = false` is declared on both targets.
- [x] The iPhone target correctly omits `NSHealthUpdateUsageDescription`; it
  reads HealthKit but does not write workouts.
- [x] App version/build is consistently `1.0.0` / `2` across both production
  targets in Debug and Release. Test targets remain at build 1 and are not
  shipped. **Repository update - 6 August 2026.**
- [x] No third-party package dependencies or developer-controlled backend were
  found.
- [x] No production force-unwraps were found in the source audit.
- [x] The empty AccentColor asset falls back to system blue; this is polish, not
  an App Store blocker, because runtime theming is handled by `AppTheme`.
- [x] `WKApplication` is `true` in the generated Watch `Info.plist` — verified
  in a Release build product on 18 July 2026. The key is injected by Xcode's
  generated-Info.plist path (`GENERATE_INFOPLIST_FILE = YES`), so its absence
  from the source tree is not an upload risk.
- [x] `LSApplicationQueriesSchemes` in the iPhone `Info.plist` declares exactly
  the seven AI-app schemes `AICoachLauncher` probes with `canOpenURL`
  (`chatgpt`, `claude`, `googlegemini`, `perplexity`, `ms-copilot`, `poe`,
  `grok`), so no scheme is probed undeclared and the launcher cannot silently
  report every app as uninstalled.
- [x] WatchConnectivity transit uses `sendMessage`, `transferUserInfo`, and
  `transferFile` (the latter with an ephemeral temporary-directory copy that is
  deleted after hand-off and never backed up); `updateApplicationContext` is
  not used. This is local device-to-device sync, consistent with the disclosed
  privacy posture.

---

## Screenshot and demo-video plan

### Required formats

- [x] Prepare an upload-ready screenshot package under
  [`docs/app-store-screenshots/`](docs/app-store-screenshots/README.md): five
  iPhone 6.9-inch PNGs at 1320 x 2868 and four physical Apple Watch Series 7
  (45 mm) PNGs at 396 x 484. Dimensions and absence of alpha were verified on
  6 August 2026.
- [x] Upload an accepted iPhone 6.9-inch portrait set: 1260 x 2736,
  1290 x 2796, or 1320 x 2868 pixels. A separate 6.5-inch set is only required
  when no 6.9-inch set is supplied. **Owner verification — 6 August 2026:** all
  five 1320 x 2868 screenshots were uploaded to App Store Connect.
- [x] Upload all four 396 x 484 Series 7 Watch screenshots consistently across
  every localization. A separate 41 mm plus 45 mm set is not required. **Owner
  verification — 6 August 2026:** all four screenshots were uploaded.
- [x] Confirm the accepted dimensions in Apple's current
  [screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)
  immediately before capture. **Verified 6 August 2026.**

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
- The upload package intentionally uses the latest completed match with point
  statistics from the 6 August full-fidelity archive. Its authentic score,
  outcomes, steps, calories, heart-rate samples, coaching insights, and Pulse
  Coach output are shown; no screenshot data was fabricated.

---

## App Store Connect checklist

### Build and compliance

- [x] Blockers 1-4 resolved in code, configuration, tests, and public copy;
  PR #78's final TestFlight device verification remains the separate next gate.
- [x] Archive and validate with Xcode 26 / the iOS 26 SDK or newer. Submissions
  have required this toolchain since 28 April 2026; see
  [Upcoming Requirements](https://developer.apple.com/news/upcoming-requirements/).
- [x] Test the validated build on a real iPhone and Apple Watch, then
  TestFlight. Verified across the 4-6 August 2026 device passes and the
  build-2 TestFlight upgrade install ahead of the 6 August 2026 submission.
- [x] HealthKit and iCloud production capabilities/container verified for the
  iPhone and Watch App IDs and signed products.
- [x] Final bundle ID `ehsan.DeuceMate` explicitly accepted as permanent.

### Store record

- [x] App Review notes start with the no-Watch Manual Match Entry path and
  include the hardware demo video. Manual Match Entry is first (see Item 6);
  no demo video was attached for the 6 August 2026 submission, but the
  17 August 2026 Resolution Center reply links the physical-device recording
  (see Item 6; the video has since been taken down and the link is marked
  `<video removed>` pending a replacement).
- [~] App Privacy answers are based on final behavior, not the old absolute
  "on-device only" wording. *Some* answer was necessarily submitted as part of
  the mandatory App Store Connect submission flow, but the exact selected
  value is unconfirmed — see the matching item under Blocker 4 above.
- [x] Current age-rating questionnaire completed and metadata updated to match.
  Confirmed 9+ on 6 August 2026 (see Item 7).
- [x] EU Digital Services Act trader/non-trader status supplied (declared
  non-trader). See Apple's
  [DSA guidance](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/).
- [~] Content Rights question, support contact, copyright, app availability
  (including Mac/Vision compatibility), and manual/automatic release mode set.
  Content Rights and release mode are mandatory to submit, so both are set;
  worth a quick spot check that the Mac/Vision-compatibility toggle reflects
  the intended iPhone/Watch-only availability.
- [ ] Accessibility Nutrition Labels claimed only after auditing the supported
  common tasks on both iPhone and Watch.
- [~] Privacy, Support, and Marketing URLs rechecked while logged out immediately
  before submission. Whether this recheck happened during the 6 August 2026
  submission window is unconfirmed. **Separately re-verified 12 August 2026**
  (six days after submission, so it doesn't stand in for the pre-submit check):
  all three (`emrahman.github.io/DeuceMate/`, `/privacy.html`, `/support.html`)
  returned HTTP 200 on an unauthenticated request.
- [x] Correct iPhone and Watch screenshot sets uploaded and accepted. Uploaded
  6 August 2026 (see Screenshot and demo-video plan); acceptance confirmed by
  the successful 6 August 2026 submission.

### Final smoke test

- [x] Fresh install without a paired Watch can create, inspect, and export a
  manually entered match. Verified in the **Concise final-candidate smoke
  pass** above.
- [x] Paired Watch can create a match, live-sync it, finish it, and recover it on
  iPhone without duplicates. Verified in the **Next manual pass** section above
  (item 2, fourth bullet).
- [x] A fresh Watch install presents the optional HealthKit request; granting
  access starts or resumes one Tennis workout per match and records only the
  measurements the user authorized. Verified 4 August 2026.
- [x] HealthKit denial/revocation never blocks scoring or corrupts a match.
  Fresh-install denial passed on the production TestFlight build on 1 August
  2026; revocation passed on signed hardware on 4 August 2026.
- [~] On iPhone, the Per-point avg heart-rate view's own HealthKit prompt
  handles grant, denial, and unavailable states without affecting the rest of
  the match detail. Grant and denial passed on the production TestFlight build
  on 1 August 2026; HealthKit unavailable remains outstanding.
- [x] iCloud disabled/signed out never blocks local history; a later sign-in
  backs up and restores the stripped archive correctly. Verified 4 August 2026.
- [x] The automatic app-managed iCloud archive contains no HealthKit-derived
  values; any approved user-initiated export follows the final disclosure and
  consent design. Verified through production-container and device-backup restore
  checks by 4 August 2026.
- [x] Foreground announcements work; locking/backgrounding the iPhone stops them
  without a background-audio entitlement. Verified on the production TestFlight
  build on 1 August 2026.

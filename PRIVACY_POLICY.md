# Privacy Policy for DeuceMate

**Effective Date:** June 11, 2026  
**Last Updated:** November 15, 2026

## Overview

DeuceMate is committed to protecting your privacy. This privacy policy explains how DeuceMate ("the App") handles information.

## Data Collection

**The developer does not collect or receive personal information or user data from DeuceMate.** DeuceMate has no developer-controlled backend, analytics, advertising, or tracking. The App does store data for you on your devices and, as described below, uses your personal iCloud Drive account and supports sharing that you explicitly initiate.

Specifically, the App does NOT collect:

- Personal identification information (name, email, phone number, etc.). Names you choose to type for opponents or partners stay in your own match archive and are never sent to the developer — see "Match Details, Player Names & Private Notes" below.
- GPS location data or coordinates
- Usage analytics or statistics
- Device information
- Crash reports
- Advertising identifiers
- Any other personal or non-personal data

## Compass / Heading Permission

The optional **Check Changeover** feature uses your Apple Watch's built-in compass to show which direction the court faces after a side change. If you enable this feature:

- The App requests the **"When In Use" location permission** on watchOS, which is required to access compass heading data.
- Only the **magnetic heading angle** (a compass bearing in degrees) is read — no GPS coordinates, no location history, and no movement tracking of any kind.
- The locked court bearing is stored **locally on your device only** and is cleared when you reset or end the match.
- The compass heading is **never transmitted** to any server or third party.
- This feature is **entirely optional**. You can use DeuceMate without enabling it; if you do not enable "Check Changeover", the App never requests or reads any heading data.

## Health & Fitness Data (HealthKit)

DeuceMate includes fitness features on Apple Watch that use Apple's **HealthKit** framework. When the Apple Watch app first launches, it requests optional HealthKit access. You can deny that request or later revoke access, and tennis scoring remains fully usable without it. If you grant access, DeuceMate automatically starts or resumes a Tennis workout for each match.

If you grant access, the App:

- **Reads**, during each match, the following data from the Health app on your Apple Watch: heart rate, active and resting energy, step count, and walking/running distance.
- **Writes** one workout of type "Tennis" to the Health app for each match you record.

How this data is handled:

- Heart-rate samples and derived fitness metrics are analysed in DeuceMate to show live stats during the match and compute per-match statistics and coaching insights.
- Your maximum heart rate for Pulse Coach zones is estimated from a birth year you optionally enter in the app (or a manual max-HR value you set). This is **not** read from the Health app.
- Heart-rate values are saved as part of the match record stored **locally on your devices** (see "Local Data Storage" below), so heart-rate statistics remain available when you review a past match.
- DeuceMate's automatic app-managed iCloud Drive archive (see "iCloud Sync" below) **excludes** HealthKit-derived heart rate, steps, distance, and calories.
- DeuceMate stores these HealthKit-derived values in separate local files that it marks for exclusion from Apple's system-managed device backups. The App reapplies that exclusion whenever it saves those files.
- When you deliberately export a match, share match analysis with another person or an AI/LLM, or create a manual archive backup, that user-initiated export may include HealthKit-derived measurements. The recipient, storage location, or AI service you select then handles that data under its own terms.
- HealthKit data is **not** used for advertising or marketing, is **not** sold, and is never sent to or accessible by the developer.
- You can review or revoke DeuceMate's HealthKit access at any time in the Apple Watch Settings app or the iPhone Health app.

## Local Data Storage

The App stores the following information locally on your devices:

- Current match state (scores, games, sets, server)
- Match history (completed and in-progress matches, including point-by-point statistics and, when HealthKit access is granted, heart-rate values recorded during the match)
- User preferences (haptic feedback settings, control preferences)
- Locked court bearing angle (only when Check Changeover is enabled; cleared on match reset)
- Match details you choose to add on iPhone: names, optional tennis playing-style details (handedness, backhand, play style) and optional playing style notes you choose to enter for opponents or partners, and a match's competition type (Friendly, League, Tournament or Practice)
- Private match notes you choose to write on iPhone, which are kept separately and are **not** backed up (see "Match Details, Player Names & Private Notes" below)

This data:

- Is never sent to a developer-controlled server; DeuceMate has no such backend
- When iCloud Drive is available, the iPhone app stores a stripped backup copy of the match archive in your personal iCloud Drive account — see "iCloud Sync" below for details.
- Non-health local data may also be included in your device's standard **iCloud Backup** if you have it enabled. DeuceMate marks its HealthKit-derived match files and its private-notes file for exclusion, so automatic device restore is intentionally partial: matches, scores, non-health statistics, player names and competition types can return, but recorded heart rate, steps, distance, calories, and private notes do not.
- May leave your device when you deliberately export or share it, as described in "Sharing, Export & AI Coaching" below
- Is removed from your device when you uninstall the App
- Can be cleared by resetting the match or reinstalling the App

## iCloud Sync

The iPhone app stores your match archive on your iPhone and automatically keeps a backup copy of it in **iCloud Drive** when your Apple ID is signed in and iCloud Drive is available on your device. This means:

- Your match archive always lives on your iPhone; a backup copy is kept in your personal **iCloud Drive** container so it can be restored if you reinstall the App or move to a new iPhone.
- This automatic app-managed iCloud Drive copy **excludes** HealthKit-derived measurements (heart rate, steps, distance, and calories) to comply with App Store Review Guideline 5.1.3(ii). Match scores, point statistics, player names and competition types you add, and the other match data are included. Private match notes are **not** included.
- A manual archive export is separate from the automatic iCloud Drive copy. When you explicitly create one, it may include HealthKit-derived match measurements and can be saved to a location you choose, including iCloud Drive.
- This data lives in **your own Apple ID account** — it is not accessible to the developer and is not shared with any third party.
- iCloud Drive is Apple's own service, governed by Apple's privacy policy and encrypted using your credentials.

If iCloud is unavailable (e.g., you are signed out of iCloud or iCloud Drive is disabled in iOS Settings), the archive is stored locally on your iPhone only. You can prevent iCloud from being used by disabling iCloud Drive in your iPhone's Settings app.

## Match Details, Player Names & Private Notes

On iPhone you can optionally add details to a match — who you played (and, in doubles, your partner), its competition type, and a private note. Nothing is required, and DeuceMate never reads your contacts: names are only what you type. First names or nicknames are enough, which is worth keeping in mind for junior players.

**Your own name:** in Settings you can optionally enter **Your name**, and a shorter **Name for announcements**. Both are kept in DeuceMate's settings on your iPhone and Apple Watch, which sync them to each other over WatchConnectivity. Your name is used to say who recorded a match in reports, AI Coaching prompts and game plans, only while player names are included. The name for announcements (or, if you leave it blank, the first part of your name) is spoken in live score announcements.

**Player names, playing style and competition type:**

- Are saved with the match in your match archive on iPhone, and are sent to your paired Apple Watch over WatchConnectivity so it can show them in its match history.
- Are included in DeuceMate's automatic iCloud Drive backup copy and may be included in your device's iCloud Backup, like other non-health match data. They are not health data.
- Are included in a manual archive file when you create one in Settings → Backup & Transfer.
- Appear in shared text and interactive web-page reports, AI Coaching prompts and game plans by default, with an **Include player names** switch on each to leave them out (a prompt then says "Opponent" and "Partner"). It is one choice: if you switch names off, DeuceMate remembers that on your iPhone and leaves them out of every report, prompt and game plan until you switch them back on. The competition type is included when set. Whoever or whatever you send a report, prompt or game plan to receives the names you chose to include.
- Playing style notes are free text you write about a player. They are stored with that player like their name, so they are synced to your Apple Watch and included in DeuceMate's iCloud Drive backup copy and manual archive files. They are used only in a game plan for a match against that player, where they are included unless you switch off **Playing style notes** (DeuceMate remembers that choice); they are never added to reports or AI Coaching prompts.
- Never appear in exported file names and are never spoken aloud by live score announcements.
- Can be renamed, merged, or forgotten in Settings → Players. **Forget Player** removes that person from every match on your iPhone, from your Apple Watch when it next syncs, and from DeuceMate's iCloud Drive backup copy after its next successful upload. So that an older copy (for example a stale Apple Watch copy, an older backup or an older archive file) cannot bring the name back, DeuceMate keeps a random identifier for each forgotten player — never the name — alongside your archive and its backups. Forgetting cannot change reports you have already shared, archive files you exported earlier, earlier device backups, or copies held by an older version of the App; and restoring only an archive file made before you forgot someone, on a device without that record, can bring the name back.

**Private notes:**

- Are stored **only on your iPhone**, in a separate file that DeuceMate keeps out of its iCloud Drive backup and marks for exclusion from device backups (reapplied each time a note is saved). Notes can contain anything you type — including health information such as an injury — so they are handled more conservatively than other match data.
- Are not synced to your Apple Watch.
- Are **never** added to a shared report, an AI Coaching prompt, a game plan or a manual archive file unless you switch on **Include private note** (**Private notes** in a game plan, **Include private notes** for an archive) for that export. It is off by default every time and is never remembered. When you switch it on, DeuceMate shows the exact text that will be included and tells you it may contain personal or health information; if player names are off, it also warns that the note may still contain names, because the note is included exactly as written. An included note is also shown in the disclosure you confirm before sharing. It is included in both the report you keep and the opponent's version of an interactive report, and it is quoted in an AI prompt as background context.
- If you include notes in a manual archive file and import that file on another iPhone, they are restored only to that iPhone's private notes (a newer note already there is kept); a file without a notes section never changes your notes.
- Are therefore not recovered if you delete the App, restore your device, or move to a new iPhone.
- Are deleted when you permanently delete their match. Forgetting a player does not edit note text that may mention them; when you forget a player, DeuceMate offers to delete the notes on that player's matches.

## iPhone Companion App & WatchConnectivity

DeuceMate includes an iPhone companion app. When both the Apple Watch app and iPhone app are installed, match data is automatically synced between your Apple Watch and iPhone using **Apple's WatchConnectivity framework**.

This sync is:

- **Entirely on-device and peer-to-peer** — data travels directly between your Apple Watch and iPhone over their local wireless connection.
- **Not a network transmission** — no data passes through any server, the internet, or any third party.
- **Not iCloud** — the sync does not use Apple's iCloud service and does not require an Apple ID.

The iPhone app stores its canonical match history in Application Support and the watch stores its history in Documents. Both use `.completeFileProtectionUntilFirstUserAuthentication` so background WatchConnectivity delivery can work after the first device unlock.

## Sharing, Export & AI Coaching

DeuceMate lets you **choose** to share your own match data:

- **Export / Share** — From a match's detail screen you can export a match summary or full point-by-point data, or an interactive web-page report, and share it through the standard iOS share sheet (for example to Files, Messages, or Mail). These can include the competition type and, unless you switch it off, the opponent and partner names you added, and, only if you switch it on, your private note.
- **AI Coaching prompt** — You can generate a coaching prompt built from your match statistics and the match's competition type, optional tennis playing-style details (handedness, backhand, play style), and head-to-head record, and copy it to the clipboard or open it in a third-party AI app you already have installed (such as ChatGPT, Claude, or Gemini). Player names are included unless you switch them off; your private note is left out unless you switch it on for that prompt.
- **Game plan** — From an opponent's page you can prepare a game plan: a text summary of the singles matches you recorded against that player, which you can copy, share or open in a third-party AI app you choose. DeuceMate prepares it on your iPhone and never sends it anywhere itself. It includes player names and playing style notes unless you switch them off, and your private notes only if you switch them on and confirm which ones, after seeing their exact text. Heart rate, steps, calories and other health data are never included in a game plan.
- **Manual archive backup** — From Settings → Backup & Transfer you can create a full match-archive file and save or share it using a location you choose. It includes player names; private notes are included only if you switch on **Include private notes**.

Important points about these features:

- They are **always initiated by you**. DeuceMate never shares, exports, or uploads match data on its own.
- These exports may include HealthKit-derived heart rate, heart-rate zones, steps, distance, and calories when recorded.
- **DeuceMate asks you to confirm before health data leaves the device.** When the match you are exporting, sharing, or handing to an AI includes any of those recorded measurements, DeuceMate shows a prompt naming exactly which ones are included and reminding you they will reach the recipient, storage location, or AI service you choose; the export proceeds only if you confirm. A match with no recorded health data exports without the prompt.
- When you export, share, or send a prompt to another app, that data **leaves your device** and is then handled by the app or service you chose. Once it reaches a third-party AI tool or another app, **that third party's privacy policy — not this one — governs how the data is used.** Please review their policies before sending data you consider sensitive.
- DeuceMate has no developer-controlled server. To show which AI apps are available, the App checks for their app URL schemes locally on your device; no information about your installed apps is collected or sent to the developer.

## Services

DeuceMate contains no third-party SDKs and does not automatically send data to analytics, advertising, social-media, or crash-reporting services. Its automatic archive uses your personal Apple iCloud Drive account. If you choose an export, AI/LLM hand-off, or other sharing destination, the service you select handles the shared data under its own privacy terms.

## Internet Connectivity

Core scoring, local match review, and WatchConnectivity operation do not require internet access. Internet access is needed for the optional automatic iCloud Drive archive and for any online destination or AI/LLM service that you choose when exporting or sharing.

## Children's Privacy

DeuceMate does not collect any data from anyone, including children under the age of 13. The App is suitable for users of all ages. If you record a junior player's name as an opponent or partner, it stays in your own match archive as described above; a first name or nickname is enough.

## Changes to This Privacy Policy

We may update this Privacy Policy from time to time. Any changes will be reflected by updating the "Last Updated" date at the top of this policy.

## Your Rights

Because the developer does not collect or receive your data, the developer has no account record to access, modify, or delete. You manage DeuceMate's local data on your devices, automatic backups through Apple device settings, and any exports through the storage location or recipient you select. To migrate HealthKit-derived match values, create a manual archive in Settings → Backup & Transfer before switching devices and import it on the new iPhone. To remove a person you named from your matches, use Forget Player in Settings → Players; private notes are removed by deleting the note or its match.

## Contact

If you have any questions about this Privacy Policy, please contact:

**Ehsan Rahman**  
Email: mail@ehsanrahman.com  
Website: https://ehsanrahman.com

## Consent

By using DeuceMate, you consent to this Privacy Policy.

---

**In Summary:**

- ✅ No developer data collection — no developer servers, analytics, ads, or tracking
- ✅ No GPS or location tracking (optional compass reads heading only)
- ✅ Core scoring and local match review work without internet access
- ✅ Match data stays under your control in DeuceMate, your personal iCloud archive, and destinations you explicitly choose
- ✅ Watch ↔ iPhone sync is on-device peer-to-peer only — no servers, no iCloud
- ✅ iCloud Sync: match archive is automatically stored in your own iCloud Drive account when available — never accessible to the developer
- ✅ DeuceMate's automatic iCloud Drive archive excludes HealthKit-derived measurements
- ✅ Opponent/partner names and playing style notes you type stay in your own archive and its backups; private notes stay on your iPhone only and are never backed up or shared automatically
- ✅ Match, manual-backup, and AI/LLM exports are user-initiated and may include HealthKit-derived measurements; the selected recipient or service then governs that data

---

*This privacy policy applies to DeuceMate for Apple Watch and the DeuceMate iPhone companion app, developed by Ehsan Rahman. It is also published at https://emrahman.github.io/DeuceMate/privacy.html, which is the version linked from the App Store.*

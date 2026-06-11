# Privacy Policy for DeuceMate

**Effective Date:** June 11, 2026
**Last Updated:** June 11, 2026

## Overview

DeuceMate is committed to protecting your privacy. This privacy policy explains how DeuceMate ("the App") handles information.

## Data Collection

**DeuceMate does NOT collect, store, transmit, or share any personal information or user data.**

Specifically, the App does NOT collect:
- Personal identification information (name, email, phone number, etc.)
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

DeuceMate includes optional fitness features on Apple Watch that use Apple's **HealthKit** framework. These features are off by default and activate only if you turn them on in Settings (the workout session and the Pulse Coach heart-rate features).

If you enable them, the App:

- **Reads**, during a match, the following data from the Health app on your Apple Watch: heart rate, active and resting energy, step count, walking/running distance, and your date of birth. Date of birth is used only to estimate your maximum heart rate for Pulse Coach heart-rate zones.
- **Writes** a single workout of type "Tennis" to the Health app to record the match as a fitness activity.

How this data is handled:

- Heart-rate samples and the derived fitness metrics are used **on-device only** — to show live stats during the match and to compute per-match statistics and coaching insights.
- Heart-rate values are saved as part of the match record stored **locally on your devices** (see "Local Data Storage" below), so heart-rate statistics remain available when you review a past match.
- The iCloud backup copy of your archive (see "iCloud Sync" below) **excludes** heart-rate and fitness measurements (heart rate, steps, distance, and calories); those fields stay on your devices only. A manual archive export from Settings → Backup & Transfer in the iPhone app retains them in full.
- HealthKit data is **never transmitted** by the App to any server or third party.
- HealthKit data is **not** used for advertising or marketing, is **not** sold, and is **not** shared with third parties.
- These features are **entirely optional**. If you do not enable the workout session or Pulse Coach, the App does not request HealthKit access and reads no health data.
- You can review or revoke DeuceMate's Health permissions at any time in the Apple Watch Settings app or the iPhone Health app.

## Local Data Storage

The App stores the following information **locally on your devices only**:
- Current match state (scores, games, sets, server)
- Match history (completed and in-progress matches, including point-by-point statistics and, when the workout session is enabled, heart-rate values recorded during the match)
- User preferences (control preferences, appearance settings)
- Locked court bearing angle (only when Check Changeover is enabled; cleared on match reset)

This data:
- Is never sent to any server or third party by the App
- When iCloud Drive is available, the iPhone app stores a backup copy of the match archive in your personal iCloud Drive account — see "iCloud Sync" below for details. No data is ever sent to any third-party server.
- May also be included in your device's standard **iCloud Backup** if you have iCloud Backup enabled in iOS/watchOS Settings. That backup is encrypted and tied to your own Apple ID and is managed by iOS — the App does not trigger or control it. You can exclude DeuceMate from iCloud Backup, or turn iCloud Backup off entirely, in your device Settings.
- Is removed from your device when you uninstall the App
- Can be cleared by resetting the match or reinstalling the App

## iCloud Sync

The iPhone app automatically stores your match archive in **iCloud Drive** when your Apple ID is signed in and iCloud Drive is available on your device. This means:

- Your match archive always lives on your iPhone; a backup copy is kept in your personal **iCloud Drive** container so it can be restored if you reinstall the App or move to a new iPhone.
- The iCloud backup copy **excludes** HealthKit-derived measurements (heart rate, steps, distance, and calories) to comply with App Store Review Guideline 5.1.3(ii). Match scores, point statistics, and all other match data are included. A manual archive export (Settings → Backup & Transfer) includes health measurements in full.
- This data lives in **your own Apple ID account** — it is not accessible to the developer and is not shared with any third party.
- iCloud Drive is Apple's own service, governed by Apple's privacy policy and encrypted using your credentials.

If iCloud is unavailable (e.g., you are signed out of iCloud or iCloud Drive is disabled in iOS Settings), the archive is stored locally on your iPhone only. You can prevent iCloud from being used by disabling iCloud Drive in your iPhone's Settings app.

## iPhone Companion App & WatchConnectivity

DeuceMate includes an optional iPhone companion app. When both the Apple Watch app and iPhone app are installed, match data is automatically synced between your Apple Watch and iPhone using **Apple's WatchConnectivity framework**.

This sync is:
- **Entirely on-device and peer-to-peer** — data travels directly between your Apple Watch and iPhone over their local wireless connection.
- **Not a network transmission** — no data passes through any server, the internet, or any third party.
- **Not iCloud** — the sync does not use Apple's iCloud service and does not require an Apple ID.

The iPhone app stores your complete match history locally in its Documents directory with `.completeFileProtection` file protection, the same protection used on the watch. No match data is shared with any external service.

## Sharing, Export & AI Coaching

DeuceMate lets you **choose** to share your own match data:

- **Export / Share** — From a match's detail screen you can export a match summary or full point-by-point data and share it through the standard iOS share sheet (for example to Files, Messages, or Mail).
- **AI Coaching prompt** — You can generate a coaching prompt built from your match statistics and copy it to the clipboard or open it in a third-party AI app you already have installed (such as ChatGPT, Claude, or Gemini).

Important points about these features:

- They are **always initiated by you**. DeuceMate never shares, exports, or uploads match data on its own.
- When you export, share, or send a prompt to another app, that data **leaves your device** and is then handled by the app or service you chose. Once it reaches a third-party AI tool or another app, **that third party's privacy policy — not this one — governs how the data is used.** Please review their policies before sending data you consider sensitive.
- DeuceMate itself still makes **no network requests** and has no servers. To show which AI apps are available, the App checks for their app URL schemes locally on your device; no information about your installed apps is collected or transmitted.

## Third-Party Services

DeuceMate does NOT use any third-party services, including but not limited to:
- Analytics services (no Google Analytics, Firebase, etc.)
- Advertising networks
- Social media integrations
- Third-party cloud storage services (the App automatically uses your own Apple iCloud Drive account when available — see "iCloud Sync" above)
- Crash reporting tools

## Internet Connectivity

DeuceMate does NOT require internet connectivity and functions completely offline. The App makes NO network requests to external servers. The WatchConnectivity sync between the Apple Watch and iPhone companion app uses the local wireless connection between your paired devices — it is not an internet connection.

## Children's Privacy

DeuceMate does not collect any data from anyone, including children under the age of 13. The App is suitable for users of all ages.

## Changes to This Privacy Policy

We may update this Privacy Policy from time to time. Any changes will be reflected by updating the "Last Updated" date at the top of this policy.

## Your Rights

Since DeuceMate does not collect any data, there is no data to:
- Access
- Delete
- Modify
- Export
- Or manage in any way

All match data is stored locally on your device and is under your complete control.

## Contact

If you have any questions about this Privacy Policy, please contact:

**Ehsan Rahman**
Email: mail@ehsanrahman.com
Website: https://ehsanrahman.com

## Consent

By using DeuceMate, you consent to this Privacy Policy.

---

**In Summary:**
- ✅ No data collection by the app — no servers, no analytics, no tracking
- ✅ No GPS or location tracking (optional compass reads heading only)
- ✅ No internet required — the app makes no network requests
- ✅ Match data stays on your devices unless you choose to export or share it
- ✅ Watch ↔ iPhone sync is on-device peer-to-peer only — no servers, no iCloud
- ✅ iCloud Sync: match archive is automatically stored in your own iCloud Drive account when available — never accessible to the developer
- ✅ HealthKit data (heart rate, etc.) is optional, used on-device only, and never transmitted
- ✅ Export / AI-coaching is always user-initiated; shared data is then governed by the receiving app's policy

---

*This privacy policy applies to DeuceMate for Apple Watch and the DeuceMate iPhone companion app, developed by Ehsan Rahman.*

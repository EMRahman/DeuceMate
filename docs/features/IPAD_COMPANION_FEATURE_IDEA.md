# Feature Idea: iPad Companion (read-only spectator / archive / stats)

## Status
**Idea — not planned, not scheduled.** This is a feasibility note captured for
future consideration, not a commitment or a design sign-off. No code changes
have been made. Revisit when iPhone-companion and Watch-scoring priorities are
clear.

## TL;DR
An iPad version is **feasible and low-risk to the data layer**, but the current
iOS UI is phone-first with zero adaptivity, so a *good* iPad experience is a
real (~1 week) UI effort, not a checkbox flip. Recommendation: **don't ship the
half-day "stretched phone" version** — it reflects worse on the product than no
iPad app at all. If pursued, do the "decent" tier (NavigationSplitView shell).
Priority: **below** anything improving core Watch scoring or the iPhone archive.

---

## Context

DeuceMate is a watchOS-first scorer with a **read-only iPhone companion** (live
spectating, archive, per-match stats, charts, AI coaching). The Apple Watch is
the sole source of truth for scoring; the phone never authors match results.

An iPad would inherit the **companion** role only — never the scorer role
(nobody scores a live match on an iPad). Its plausible use cases:

- A larger "second screen" courtside for live spectating.
- Comfortable couch-side review of the archive, stats, and charts — where the
  big screen genuinely flatters `PointsGraphView` / `MatchDetailView` far more
  than a phone does.

This is an **enhancement, not a strategic need**: it adds no new core
capability, it just gives the existing companion surface more room.

---

## Why the data/logic layer is already ready

All portable logic lives in `DeuceMateCore` (models, scoring, stats, sync wire
format), and device-to-device transport is `WatchConnectivity`
(iPhone ↔ Watch). An iPad build needs **zero** changes to:

- `DeuceMateCore` (models, `MatchStatsSummary`, stats, codecs).
- The sync wire format / merge policy.
- Persistence (`PhoneStatsStore` / `StatsStoring`) or the iCloud backup policy.

> ⚠️ One thing to verify if this is ever pursued: WatchConnectivity pairs a
> Watch with **one** iPhone, not an iPad. An iPad would therefore most likely be
> an **archive/stats + (optionally) iCloud-restored** device, or a follower in
> the dual-device broadcast model (see `DUAL_DEVICE_MATCH_BROADCAST_PLAN.md`),
> *not* a direct WatchConnectivity peer. The "live spectator" use case needs a
> transport story before it's real. The archive/stats use case does not.

So the work is **purely UI adaptation** — the cheap kind, with no risk to the
Watch/sync/data invariants.

---

## Why it is not a checkbox flip (the real cost)

The iOS UI (~10k lines across ~19 files) was written **phone-first with no
adaptivity**. Current state, as of this note:

| Area | Current state | iPad impact |
|------|---------------|-------------|
| Device targeting | `TARGETED_DEVICE_FAMILY = 1` (iPhone only), `SDKROOT = iphoneos`, `LSRequiresIPhoneOS = true` | iPad not a build target at all |
| Root navigation | Plain `NavigationStack` (`ContentView.swift` → `PastMatchesView.swift`); detail screens are **modal sheets**, not columns | Renders as a single narrow column — ~60% of the iPad screen wasted; never list+detail side by side |
| Size classes | **No `horizontalSizeClass` / size-class logic anywhere** | Zero adaptive layout to build on |
| Orientation | Hard-locked to portrait in `AppDelegate.orientationLock`; `LiveScoreboardView` force-flips to landscape | Neither honors iPad orientation |
| Fixed widths | A few hardcoded frames (e.g. `frame(width: 44)` stat labels in `MatchDetailView`) | Look undersized / awkward at iPad width |

The good news: individual views already use `GeometryReader`, `Spacer`, and
flexible grids, so they reflow reasonably **once the navigation shell is right**.
The effort concentrates in **one structural change** (NavigationStack →
size-class-aware NavigationSplitView, converting the big modal sheets to
columns) rather than rewriting each view.

---

## Effort tiers

| Tier | Rough effort | What you get |
|------|--------------|--------------|
| **"It runs"** | ~½ day | Flip `TARGETED_DEVICE_FAMILY` to `"1,2"`, relax the portrait lock. Launches on iPad but looks like a blown-up phone. **Not recommended to ship** — worse than nothing. |
| **"It's decent"** ⭐ | ~1 week | Above + swap root `NavigationStack` for a size-class-aware `NavigationSplitView`; convert `MatchDetailView` / `SettingsView` modal sheets to split-view columns on `.regular` width; fix the hardcoded widths. The sweet spot. |
| **"It's polished"** | ~2–3 weeks | Above + iPad-tuned `LiveScoreboardView`, landscape charts, adaptive spacing/fonts, multi-iPad-size testing, possibly keyboard shortcuts / multi-window. |

### Key files a "decent"-tier effort would touch
- `DeuceMate/DeuceMate/DeuceMateApp.swift` — relax orientation lock, inject size class.
- `DeuceMate/DeuceMate/ContentView.swift` — conditional `NavigationSplitView`.
- `DeuceMate/DeuceMate/Views/PastMatchesView.swift` — sheets → split-view columns.
- `DeuceMate/DeuceMate/Views/MatchDetailView.swift` — column layout, fix `frame(width: 44)` stat labels.
- `DeuceMate.xcodeproj/project.pbxproj` — `TARGETED_DEVICE_FAMILY` (a build-setting edit — one of the cases that genuinely needs a pbxproj change).

---

## Open questions to resolve before promoting this to a plan
1. **Transport for the live-spectator use case.** WatchConnectivity won't pair
   the iPad with the Watch. Is the iPad archive/stats-only (iCloud-restored), or
   does it ride the dual-device broadcast model? This decides scope.
2. **iCloud as the iPad's data source.** The iPad would likely depend on the
   iCloud backup for its archive. Today iCloud is backup/restore-only and the UI
   is never gated on it — an iPad would change that assumption and needs a
   deliberate decision (see `ICLOUD_BACKUP_HARDENING_PLAN.md`).
3. **Is the live spectator even worth it on iPad,** or is archive + stats +
   coaching the whole value? The latter is dramatically cheaper and avoids #1.

---

## Recommendation

Capture and defer. If it's pursued later, scope it to **archive + stats +
coaching on a NavigationSplitView shell** ("decent" tier, ~1 week) and treat the
live spectator as a separate follow-on contingent on resolving the transport
question. Keep it **below** core Watch-scoring and iPhone-archive work in
priority.

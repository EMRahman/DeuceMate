# Plan: Consent-gate HealthKit-derived data in user exports (Blocker 4)

## Context

`docs/release/SUBMISSION_REVIEW.md` Blocker 4 has two halves. The **backup** half is done:
the automatic iCloud archive is HealthKit-stripped (`ArchiveBackupPolicy`), the
local Health sidecar is backup-excluded (`HealthSidecarPolicy`), and the watch's
Health-bearing files are backup-excluded. The **export/sharing** half is open:
user-initiated exports and the AI hand-off can still carry the five
HealthKit-derived fields with **no informed consent**.

**Product decision (15 July 2026):** *consent-gate*, don't strip. Keep sharing
health-bearing exports, but only behind an explicit, informed step that names the
exact data and the destination before it leaves DeuceMate. The automatic iCloud
archive stays stripped and is out of scope here.

**Refinement (16 July 2026):** the consent is a **per-export informed disclosure
that always includes health data** — a two-way *Share / Cancel* gate, not a
three-way include/exclude. Rationale: most users are not expected to object to
sharing heart-rate / steps in an export they chose to create, and a clear
per-export disclosure + affirmative action is sufficient informed consent for
Guideline 5.1.3. An **opt-out that strips health** is deferred to Future work and
can be added later without reworking this gate (the disclosure/skip logic and the
choke points are the same; only the button set and a strip path change). This
means **no stripping is wired into export paths now** — exports stay
full-fidelity, exactly as today, but gained a disclosure.

The five HealthKit-derived fields (already the unit of `strippingHealthData()`,
which is what a future opt-out would reuse):

| Field | Type | Site |
|-------|------|------|
| `heartRateBPM` | `Int?` | `PointStat` |
| `stepsCumulative` | `Int?` | `PointStat` |
| `totalSteps` | `Int?` | `MatchRecord` |
| `totalDistanceMeters` | `Double?` | `MatchRecord` |
| `totalCaloriesKcal` | `Double?` | `MatchRecord` |

Everything derived (HR zones, PulseCoach insights, steps timeline) reads from
these five.

## Goals

- No HealthKit-derived value leaves the device through any user-initiated export
  or AI hand-off **without** the user first seeing a per-export disclosure that
  names the exact fields present and the destination, then affirmatively
  proceeding.
- Keep exports full-fidelity (no behavior/content change beyond the added gate).
- Keep the disclosure copy + "which fields are present" logic in Core (tested);
  keep the iOS layer a thin presenter, per `CLAUDE.md`.
- Prove it with Core tests: the disclosure names exactly the health fields the
  export actually contains — no over-claim, no under-claim — for both
  perspectives.

## Current surfaces (audited 15 July 2026)

Four choke points, none gated today.

1. **Manual archive export** — `SettingsView.swift:166-171` (`.alert`, Export/
   Cancel, already discloses health in prose) → `prepareManualArchiveExport()`
   (`:648`) → `PhoneStatsStore.exportManualArchiveData()` (`PhoneStatsStore.swift:242`)
   → `ManualMatchArchiveBackup.encode(records:)` (`ManualMatchArchiveBackup.swift:99`,
   always `includesHealthData = true`) → `.fileExporter` (Files picker, can target
   iCloud Drive). *Closest to compliant already — it discloses and is Export/Cancel.*
2. **Text exports (summary / full, me + opponent)** —
   `MatchDetailView.swift:633-665` share `Menu`, each item a bare `ShareLink`
   (`shareLinks(for:)` `:282-316`) sharing `MatchExporter.summaryExport` /
   `fullExport` output (built in `.task` `:586-589`). **No disclosure.**
3. **Interactive HTML export** — `MatchDetailView.swift:638-643` `ShareLink` of a
   temp `.html` URL built at `:594-603` via `MatchHTMLExporter.html(...)`. Embeds
   recorder HR/steps/totals **and** the AI-prompt card. **No disclosure.**
4. **AI hand-off** — "AI Coach" button (`:624-631`) → `AICoachSheet` (`:667-675`)
   with `exportAI`/`exportAIOpp` from `MatchExporter.aiPromptExport`.
   `AICoachLauncher.launch` copies the full prompt to the clipboard and opens one
   of 7 third-party AI apps; the sheet also offers "Copy Prompt" and a
   `ShareLink`. **No disclosure.** The HTML "AI Coach card" embeds the same prompt
   with user-clicked web links — covered transitively via surface 3.

**Two findings the plan must handle:**

- **`ShareLink` shares on tap** — there is no pre-share hook. Surfaces 2 and 3
  must move from bare `ShareLink`s to Buttons that present the disclosure first,
  then present the payload. (This restructuring is needed even for a Share/Cancel
  gate, because we still must interrupt the tap to disclose.)
- **Opponent variants also carry health.** `matchOverview` emits steps / calories
  / distance for *both* perspectives (`MatchExporter.swift:162-170`), so the
  opponent text/AI/HTML exports do contain health. The disclosure's field list
  (and its tests) must reflect the opponent set, not assume "opponent = no health."

## Design

### Consent shape (locked: two-way, per-export, always includes health)

Before a health-bearing export leaves the app, present a `confirmationDialog`
(or `.alert`) with:

- **Share** (or "Export") → proceed full-fidelity (health included).
- **Cancel** → abort.

Properties:

- **Per-export.** Shown each time; **no** persisted "don't ask again" flag (a
  silent memory would let health leave without a fresh, visible choice).
- **Names only the fields actually present.** Driven by `HealthExportConsent.presentFields`
  so an opponent export lists only steps/calories/distance, not HR/zones.
- **Skips itself when there's nothing to disclose.** If the record (for that
  focal) has none of the five fields — e.g. a manually-entered match or one
  recorded with HealthKit denied — share directly with no dialog.

### Core: `HealthExportConsent` (new, tested)

New file `Settings/HealthExportConsent.swift` in Core — single source of truth for
*which fields are present* and *what the disclosure says* (mirrors `SettingsCopy`
/ `ICloudBackupCopy`).

```swift
public enum HealthExportField: CaseIterable, Sendable {
    case heartRate, heartRateZones, steps, calories, distance
    public var displayName: String { … }   // "heart rate", "heart-rate zones", …
}

public enum HealthExportDestination: Sendable {
    case archiveFile     // manual archive → Files / iCloud Drive
    case sharedReport    // text / HTML / AI Coach — all reach the share sheet
    // No AI-only case: the AI Coach sheet also exposes general share options
    // (Mail, Files, …), so an "AI app/website only" clause would under-disclose.
}

public enum HealthExportConsent {
    /// Which of the five fields THIS record would actually expose for this
    /// perspective and export kind. `includesRawPoints` = summary (false) vs
    /// summary + raw-point table (true). Empty ⇒ no dialog needed. Totals gate
    /// on > 0 (matching the exporters); opponent HR and per-point-only steps
    /// require the raw table; zones are recorder-only.
    public static func presentFields(in record: MatchRecord,
                                     focal: Player,
                                     includesRawPoints: Bool) -> [HealthExportField]

    /// Disclosure copy naming the exact fields + destination. One source, used
    /// by every surface so the wording can't drift.
    public static func disclosure(fields: [HealthExportField],
                                  destination: HealthExportDestination)
        -> (title: String, message: String)
}
```

No `include/exclude` choice type is needed now (there is only proceed/cancel). A
future opt-out would add a `HealthExportChoice` and a strip path — see Future work.

### iOS: presenter + share coordinator

- **Reusable presenter** — a small SwiftUI helper (a `func healthExportConsent(...)`
  view modifier) that renders the dialog from `HealthExportConsent.disclosure` and
  calls back on Share.
- **Share coordinator for `MatchDetailView`** — replace the bare `ShareLink`s
  (surfaces 2 & 3) with Buttons. On tap: compute `presentFields` for the tapped
  item's `focal` and export kind (`includesRawPoints`: summary = false;
  full / AI = true; HTML → `focal: .me`, true); if empty share immediately, else
  show the disclosure; on Share, present the system share sheet via a
  `.sheet(item:)` hosting a `UIActivityViewController` representable
  (`ShareSheet`). Removes `ShareLink`'s "shares on tap" problem.
- **Manual archive (`SettingsView`)** — smallest change: it already gates on an
  Export/Cancel alert; just source its copy from `HealthExportConsent.disclosure`
  so it names the exact fields and stays consistent with the other surfaces.
- **AI Coach** — gate at sheet entry: present the disclosure before `AICoachSheet`
  so all of its actions (copy, share, 7 app launches) sit behind one affirmative
  step. The HTML AI card is covered by surface 3.

## Consent copy (draft — final text lives in Core)

Share report (text/HTML), fields = HR, zones, steps, calories, distance:

> **Title:** Share health data?
> **Message:** This export includes your recorded heart rate, heart-rate zones,
> steps, calories, and distance. DeuceMate has no server and never receives it,
> but whoever or whatever you send it to — a person, the Files app or iCloud
> Drive, or an AI service — will.
> **Buttons:** Share · Cancel

AI destination swaps the last clause for "…the AI app or website you choose will
receive it." Archive destination names "the Files app or iCloud Drive location
you choose." Copy is generated from the actual `presentFields` list, so an
opponent export names only the fields it really carries.

## Implementation sequence (one concern per PR)

- **PR 1 — `[Core]` consent policy.** Add `HealthExportConsent` (`presentFields`,
  `disclosure`, `HealthExportField`, `HealthExportDestination`) + full tests
  (below). No UI, no strip plumbing. Update `file-inventory.md` for the new Core
  file + `HealthExportConsentTests`.
- **PR 2 — `[iOS]` match-detail share consent.** Convert the text + HTML
  `ShareLink`s to the disclosure-gated Button → `ShareSheet` coordinator. Covers
  the embedded HTML AI card. (This is the biggest gap — surfaces 2 & 3.)
- **PR 3 — `[iOS]` AI Coach consent.** Gate `AICoachSheet` entry behind the
  disclosure.
- **PR 4 — `[iOS]` manual archive copy.** Source the "Export Match Archive"
  alert body from Core. The archive serialises **raw** records, so it uses a
  dedicated `HealthExportConsent.archiveFields(in:)` (union across the archive;
  heart rate / steps / calories / distance, **never** derived zones) feeding
  `disclosure(…, destination: .archiveFile)`; a health-free archive shows a
  plain export note instead. Because the archive serialises records as-is, it
  counts **any non-nil** field (including a stored `0` total) — not the rendered
  `> 0` gating, which would under-disclose a `0` that still ships in the JSON.
  The alert stays always-shown (unlike the per-match skip) because it doubles as
  the bulk-export confirmation.
- **PR 5 — `docs:`** Update `PRIVACY_POLICY.md`, `docs/website/privacy.html`,
  `docs/release/APP_STORE_METADATA.md`, and App Review notes to describe the
  per-export disclosure; flip the Blocker 4 export items in
  `docs/release/SUBMISSION_REVIEW.md` and
  re-audit the App Privacy answer (Item 5). (Doc touches may instead ride along
  with each PR — decide at review.)

## Tests (Core — the Blocker 4 proving tests)

New `HealthExportConsentTests.swift` (+ small additions where useful):

- `presentFields`: correct set for `.me` (all five) vs `.opponent` (steps /
  calories / distance, no HR / zones); empty for a health-free record.
- **Disclosure fidelity:** `disclosure(fields:destination:)` names exactly the
  fields passed — every listed field appears in the message, and no *unlisted*
  health field name appears (guards over- and under-claiming). Destination clause
  is correct per `HealthExportDestination`.
- **Disclosure ↔ export agreement:** for both focal perspectives, the set from
  `presentFields` matches the health fields the corresponding export actually
  emits — i.e. cross-check against `MatchExporter` / `MatchWebViewModel` output so
  the copy can never drift from what ships. This is the "contains only the fields
  the user was told about" proof the Blocker 4 checklist asks for.
- **Skip condition:** a record with all five fields nil ⇒ `presentFields` empty ⇒
  callers skip the dialog.

## Verification

- `swift test` (Core) green, including the new proving tests.
- iOS unit + UI: each surface presents the disclosure with the right field list,
  shares on confirm, cancels on Cancel, and skips the dialog for a health-free
  match.
- Manual device pass folds into the existing Blocker 4 signed-hardware step.

## Future work (opt-out stripping)

If users ask to share without health, add — without reworking the gate:

1. `HealthExportChoice { include, exclude }` and a third dialog button
   ("Exclude health data").
2. `ManualMatchArchiveBackup.encode(records:includeHealthData:exportedAt:)` +
   `PhoneStatsStore.exportManualArchiveData(includeHealth:)`; text/HTML/AI paths
   pass `record.strippingHealthData()` when excluded (already sufficient — a
   stripped record nils all downstream health output).
3. Optional polish: drop the empty `—` HR/steps *columns* from a stripped
   raw-point table (`MatchExporter.rawPointData`).
4. Tests for the stripped variant: every representation omits all five fields
   (both focals).

## Resolved decisions

- **Consent shape:** two-way *Share / Cancel*, always includes health
  (16 July 2026). Three-way include/exclude deferred to Future work.
- **Frequency:** per-export; no persisted "always share / don't ask again".
- **Empty raw-table columns:** moot for now (exports always carry real values);
  revisit only if the opt-out ships.

## Open decisions

- **Doc PR grouping** — one `docs:` PR (PR 5) vs docs riding each PR.

## Notes for reviewing AI models

- Do not gate the automatic iCloud archive here — it is already stripped and must
  stay one-way (`ArchiveBackupPolicy`). This plan is strictly about
  *user-initiated* exports and the AI hand-off.
- Exports stay full-fidelity; this change adds a disclosure, not stripping.
- Opponent focal is a real health path (`matchOverview`) — the disclosure field
  list and its tests must cover `.opponent`, not just `.me`.

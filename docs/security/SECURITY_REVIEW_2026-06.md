# Security Review — DeuceMate (June 2026)

A senior iOS/watchOS security review of the DeuceMate codebase (native SwiftUI,
iOS + watchOS companion, shared `DeuceMateCore` Swift package, zero third-party
dependencies). This document records what was examined, what was found to be
sound, the input-bounds hardening that was applied as a result, and a short
list of future hardening to consider before a wider release.

**Bottom line: no critical or high real-world vulnerabilities were found.** The
codebase is defensively written — guarded casts, no force-unwraps in the data
paths, backward-compatible decoding, a correctly enforced phone→watch trust
boundary, and output escaping in the HTML export. The actionable work was a set
of **input-size/range bounds** on the two decode surfaces that previously
type-checked but did not size-check their input.

---

## 1. Scope

Three parallel read-only audits:

1. **HTML / AI-coach export surface** — `WebExport/` (Core) +
   `MatchExporter`/`MatchDetailView` (iOS): injection, resource loading,
   data leakage in the exported document.
2. **Sync + trust boundary + persistence** — WatchConnectivity payload decoding
   (`SyncIncomingPayload`), the "iPhone Input" score-command path
   (`ScoreViewModel.applyRemoteScoreCommand`), and JSON persistence
   (`MatchRecord` decoding, manual archive import).
3. **Platform posture** — entitlements, networking, data-at-rest file
   protection, HealthKit privacy compartmentalisation, and logging redaction.

## 2. Threat model

DeuceMate has an unusually small attack surface:

- **No network code.** There is no `URLSession`/`NWConnection` anywhere; the app
  never opens a socket. The only outbound navigation is a user-tapped HTTPS
  deep-link to a third-party AI app.
- **WatchConnectivity peers are the user's own Apple-paired devices.** There is
  no untrusted remote sender on that channel. Hardening it defends against
  **corrupt state, buggy/old app versions, and malformed payloads** — an
  availability/robustness concern, not confidentiality or integrity compromise.
- **The one genuinely externally-sourced input is a manually-imported archive
  file** (Settings → Backup & Transfer → Import), which may have been shared
  from another device or hand-edited. This is the highest-priority input to
  bound.

Accordingly, severity below is framed as availability/robustness (resource
exhaustion / DoS), not remote code execution or data exfiltration.

## 3. Findings that were already sound (no change)

### 3.1 HTML export — no injection
- JSON embedded in the `<script>` block is passed through `scriptSafe()`, which
  neutralises `</` → `<\/`, HTML comment openers, and the JS line separators
  U+2028/U+2029 — so embedded match data cannot break out of the script context.
- The progressive-enhancement static fallback (`MatchWebStaticFallback`)
  HTML-escapes every interpolation via `esc()`.
- AI-app launch URLs are assembled with `URLComponents`/`URLQueryItem` (Swift)
  and `encodeURIComponent` (JS) — no string concatenation into a URL.
- The export contains only structured `MatchRecord`/stats data. There are **no
  free-text note fields** anywhere in the model, so there is no user-authored
  string that could carry a payload.

### 3.2 No networking / no auto-loaded resources
- Zero networking primitives in the codebase; no App Transport Security
  exceptions.
- The exported HTML loads **zero external resources** on open — enforced by a
  `MatchWebExportTests` invariant that rejects `src=`, `<link>`, `@import`, and
  CDN references. The AI links are user-clicked navigations, not auto-loads.

### 3.3 Privacy & data-at-rest
- Entitlements are minimal and match declared features (HealthKit, WatchConnectivity,
  iCloud backup container).
- HealthKit usage-description strings are present.
- iCloud backup strips the five HealthKit-derived fields
  (`MatchRecord.strippingHealthData()`, via `ArchiveBackupPolicy`) to comply with
  App Store Review Guideline 5.1.3(ii) — health data is not written to iCloud.
- Local JSON stores are written with complete file protection.
- Logging uses `privacy: .public` only on non-sensitive error text; sensitive
  diagnostics are gated behind `#if DEBUG`.

### 3.4 Trust boundary (iPhone Input)
- `ScoreViewModel.applyRemoteScoreCommand` gates every phone-issued score command
  on: the `iPhoneInputEnabled` toggle, a match-ID equality check against the
  watch's current live match identity, and re-checked completion/pending guards.
  The watch validates and applies — it never blindly trusts the phone.
- All inbound payload field access uses guarded `as?` casts; decode failures are
  caught and surfaced as `.decodeError` events, never force-unwrapped or fatal.

## 4. Findings that were hardened (this PR)

The two decode surfaces correctly type-checked input but trusted its **size and
range**. A corrupt/buggy peer or a malicious imported file could supply oversized
or out-of-range values causing resource exhaustion. Bounds were added, centralised
in the tested Core package so both apps inherit them.

| # | Surface | Risk | Fix | Severity |
|---|---------|------|-----|----------|
| 1 | Manual archive import (`ManualMatchArchiveBackup.decode`) | Oversized blob buffered into memory; huge record count bloats merge/persist | Reject `> maxArchiveBytes` (50 MB) before decode; reject `> maxArchiveRecords` (10,000) in `validate` — surfaced as user-facing `LocalizedError` | Medium (only externally-sourced input) |
| 2 | WatchConnectivity decode (`SyncIncomingPayload.decode`) | Over-long announcement wedges TTS; over-long name; giant manifest Set; out-of-range numeric settings persisted | Truncate `playerName` to 128; drop announcement `> 2000`; cap manifest at 200 (→ `decodeError`); range-check HR (`0…300`) and birth year (`0` or `1900…2100`) | Low (own paired devices) |
| 3 | Phone file-transfer receive (`PhoneMatchSyncService.session(_:didReceive:)`) | Unbounded `Data(contentsOf:)` read of a transferred file; unexpected metadata key | Validate `key` ∈ {history, single-match}; reject files larger than the shared 50 MB ceiling before reading | Low (own paired devices) |

Caps are deliberately generous — a heavy multi-season user records hundreds of
matches and short announcements, so none of these bounds is reachable in normal
use. Tests in `ManualMatchArchiveBackupTests` and `SyncIncomingPayloadTests`
cover both the rejection and the at-limit acceptance cases.

## 5. Future hardening (accepted, not changed)

These are low-priority and intentionally left as-is for now:

- **iCloud container id is personalised** (`iCloud.ehsan.DeuceMate`). Consider a
  team-generic identifier before a wide public release. Functional, not a
  vulnerability.
- ~~**Temp HTML export file** is written to a sandboxed temporary location and
  immediately handed to the share sheet, but without an explicit
  `.completeFileProtection` attribute.~~ **Fixed in the August 2026 pass (§7.1).**
- **The stringly-typed `UserDefaults`/`MatchSyncKey` coupling** (tracked in
  `docs/features/TECHNICAL_DEBT.md` #3/#10) is a correctness/maintainability
  trap, not a security one, but a typed `AppSettingKey` enum would also remove a
  class of silent settings-sync bugs.

## 6. Verification

- Core tests cover the new bounds (`xcodebuild test -scheme DeuceMateCoreTests
  -destination "platform=macOS"`). The file-transfer guard (#3) is app-layer
  transport code, verified statically and sharing the `maxArchiveBytes` constant
  with #1.
- This review was conducted in an environment without the Swift/Xcode toolchain;
  code changes were verified statically per `CLAUDE.md` §0 (types in scope,
  exhaustive switches, no plain `decode` introduced for persisted fields). The
  owner should run the package test suite locally to confirm.

---

## 7. August 2026 re-scan

A second full sweep for the usual web-app vulnerability classes (hardcoded
secrets, SQL injection, unvalidated input, insecure dependencies, permissive
CORS, exposed debug endpoints, missing auth checks) plus the iOS/watchOS
equivalents. **No critical or high findings.** Most of those classes do not
exist here: no secrets or tokens of any kind in source, plists, entitlements or
CI; no SQL / Core Data / raw predicates in production code; zero package
dependencies (`Package.swift` declares none) so no vulnerable transitive tree;
no server, so no CORS surface, no debug endpoints, and no authentication layer
to bypass — the only trust boundary is phone→watch, still correctly gated
(§3.4). The `.github` workflow is a no-op placeholder with no secrets and no
untrusted-input steps. Input bounds from §4 are all still in place.

Three defence-in-depth items were hardened:

### 7.1 Data-at-rest on staged export / transfer files
The canonical stores carry
`.completeFileProtectionUntilFirstUserAuthentication`, but two derived copies of
the same match data did not:

- `MatchDetailView` writes the interactive HTML export (full record, including
  HealthKit-derived values) to `temporaryDirectory` with plain `.atomic` — the
  item accepted in §5 above.
- `MatchSyncTransport.transferAsFile` stages full history JSON in
  `temporaryDirectory` with no options at all before handing it to
  `WCSession.transferFile`.

Both now write with
`[.atomic, .completeFileProtectionUntilFirstUserAuthentication]`, matching the
stores. The transport is in the cross-platform Core package, so the protection
option is applied under `#if os(iOS) || os(watchOS)` (the macOS test host keeps
plain `.atomic`).

### 7.2 Content-Security-Policy on the exported page
The export already loads zero external resources (invariant-tested), but the
shared HTML file had no policy enforcing that at open time. The page now ships
`default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline';
base-uri 'none'; form-action 'none'` — exactly what the hand-written inline
viewer needs. A future edit that adds a fetch, a form post, a `<base>`, or an
external asset now fails in the browser instead of silently shipping an egress
path in a file users share.

### 7.3 `esc()` now escapes quotes
Every current call site places `esc()` output in element content, where escaping
`& < >` is sufficient. It now also escapes `"` and `'`, so the helper stays safe
if a value is ever interpolated into a quoted attribute instead — the cheap
fix for the one way the export's injection story could regress.

### 7.4 Verification
Still no Swift/Xcode toolchain in this environment (`CLAUDE.md` §0): the changes
were verified statically and covered by two new `MatchWebExportTests` cases
(CSP presence, `esc` quote escaping). The owner should run
`xcodebuild test -scheme DeuceMateCoreTests -destination "platform=macOS"`
locally to confirm.

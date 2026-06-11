# Security Review — DeuceMate (Apple Watch)

## Scope

Reviewed application source and configuration files:
- `DeuceMate/DeuceMate Watch App/*.swift`
- `DeuceMate/DeuceMate-Watch-App-Info.plist`
- `DeuceMate/DeuceMate Watch App/DeuceMate Watch App.entitlements`

## Summary

This is a low-risk offline app with no direct network stack, no third-party SDKs, and no sensitive authentication flows.

### High severity findings
- None found.

### Medium severity findings
- None found.

### Low severity findings
1. **Both persisted JSON files lacked explicit iOS/watchOS Data Protection on write**.
   - `appState.json` (current match state) and `matchHistory.json` (completed/parked matches with timestamped `PointStat` records) are persisted to app documents as JSON. While neither file contains credentials, `matchHistory.json` accumulates a time-ordered record of user activity across sessions, making data-at-rest protection a meaningful privacy control for both.
   - **Fix applied:** write options for both files now include `.completeFileProtection` — `ScoreViewModel.saveState()` and `StatsStore._writeUnsafe()` use `[.atomic, .completeFileProtection]`.

2. **Error logs previously emitted raw error details**.
   - Runtime errors were printed directly, which can expose internal file paths or implementation details in logs.
   - **Fix applied:** switched to generic debug-only logging statements.

## Additional observations

- App entitlements are empty, which minimizes permission exposure.
- `Info.plist` is empty (no ATS exceptions, no extra capabilities), reducing attack surface.
- Only external URL interaction is a hard-coded `mailto:` link in UI; no user-supplied URL handling path was identified.

## Recommendations

- Keep all external links hard-coded and avoid dynamically opening user-provided URLs.
- If app scope grows (accounts/sync/telemetry), introduce a lightweight threat model and secure coding checklist in CI.
- Consider adding simple static checks in CI (`swiftlint`, secret scanners) to prevent regressions.


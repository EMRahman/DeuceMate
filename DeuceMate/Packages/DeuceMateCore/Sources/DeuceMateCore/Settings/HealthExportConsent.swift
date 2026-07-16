// HealthExportConsent.swift — the single source of truth for the per-export
// HealthKit-data disclosure shown before a user-initiated export or AI hand-off
// leaves the phone (App Store Blocker 4, Guideline 5.1.3).
//
// Design (see docs/features/HEALTH_EXPORT_CONSENT_PLAN.md): a per-export, two-way
// "Share / Cancel" informed disclosure that ALWAYS includes health data. This
// type does not strip anything — it only (a) reports which of the five
// HealthKit-derived fields a given export would actually expose, so callers can
// name them exactly and skip the dialog when there are none, and (b) builds the
// disclosure copy once so every surface (share menu, AI Coach, manual archive)
// stays consistent. A future opt-out that strips health would add a choice type
// and reuse `MatchRecord.strippingHealthData()`; it does not exist yet.
import Foundation

/// One HealthKit-derived value a user export can carry. `displayName` is the
/// human phrase used verbatim in the disclosure copy.
public enum HealthExportField: String, CaseIterable, Sendable {
    case heartRate
    case heartRateZones
    case steps
    case calories
    case distance

    public var displayName: String {
        switch self {
        case .heartRate: return "heart rate"
        case .heartRateZones: return "heart-rate zones"
        case .steps: return "steps"
        case .calories: return "calories"
        case .distance: return "distance"
        }
    }
}

/// Where a health-bearing export is headed. Selects the recipient clause of the
/// disclosure so the copy names the right destination.
public enum HealthExportDestination: Sendable {
    /// Manual full-fidelity archive written via the Files picker (can target iCloud Drive).
    case archiveFile
    /// A shared match report (text, interactive HTML, or the AI Coach prompt).
    /// All reach the system share sheet, so any target — a person, Files/iCloud
    /// Drive, or an AI app — can receive it, and the copy says so. There is no
    /// AI-only destination: the AI Coach sheet also offers general share options,
    /// so an "AI app/website only" clause would under-disclose (Blocker 4).
    case sharedReport
}

public enum HealthExportConsent {

    /// The HealthKit-derived fields an export for `focal` would actually expose
    /// for this record. Empty ⇒ nothing to disclose, so callers share directly
    /// with no dialog.
    ///
    /// `includesRawPoints` distinguishes the two text-export kinds: `false` for a
    /// summary-only export (`MatchExporter.summaryExport`), `true` for one that
    /// appends the raw point-by-point table (`fullExport` / `aiPromptExport`).
    /// HTML and the manual archive are recorder-framed and full-detail, so their
    /// callers pass `focal: .me, includesRawPoints: true`.
    ///
    /// Mirrors the gating in `MatchExporter` and `MatchWebViewModel`:
    /// - Match totals (steps/calories/distance) appear in every overview, but
    ///   only when strictly greater than zero — matching `matchOverview` and
    ///   `MatchWebViewModel.totals`.
    /// - For the recorder (`.me`), the heart-rate and movement summary sections
    ///   render regardless of the raw table, so the export kind doesn't change
    ///   which health categories are present.
    /// - For the `.opponent`, those recorder summary sections are suppressed, so
    ///   per-point heart rate and per-point-only steps reach the export **only**
    ///   through the raw-point table (`includesRawPoints`). Heart-rate **zones**
    ///   are the recorder's own and are never shown for the opponent.
    public static func presentFields(
        in record: MatchRecord,
        focal: Player,
        includesRawPoints: Bool
    ) -> [HealthExportField] {
        let hasHeartRate = record.stats.contains { $0.heartRateBPM != nil }
        let hasTotalSteps = (record.totalSteps ?? 0) > 0
        let hasPerPointSteps = record.stats.contains { $0.stepsCumulative != nil }
        let hasCalories = (record.totalCaloriesKcal ?? 0) > 0
        let hasDistance = (record.totalDistanceMeters ?? 0) > 0

        // Built in `HealthExportField.allCases` order for stable, canonical copy.
        var fields: [HealthExportField] = []
        switch focal {
        case .me:
            if hasHeartRate {
                fields.append(.heartRate)
                fields.append(.heartRateZones)
            }
            if hasTotalSteps || hasPerPointSteps { fields.append(.steps) }
        case .opponent:
            if hasHeartRate && includesRawPoints { fields.append(.heartRate) }
            if hasTotalSteps || (hasPerPointSteps && includesRawPoints) { fields.append(.steps) }
        }
        if hasCalories { fields.append(.calories) }
        if hasDistance { fields.append(.distance) }
        return fields
    }

    /// The HealthKit-derived fields present across a full-fidelity manual archive
    /// of `records`. The archive serialises **raw** `MatchRecord`s, so it stores
    /// heart rate, steps, calories, and distance but **never** derived heart-rate
    /// zones — hence a dedicated union rather than `presentFields`. Empty ⇒ no
    /// health to disclose. Order follows `HealthExportField.allCases`.
    public static func archiveFields(in records: [MatchRecord]) -> [HealthExportField] {
        var union: Set<HealthExportField> = []
        for record in records {
            union.formUnion(rawStoredFields(in: record))
            if union.count == 4 { break } // the four raw categories are all present
        }
        return HealthExportField.allCases.filter { union.contains($0) }
    }

    /// The raw stored health categories in one record — heart rate, steps,
    /// calories, distance (never derived zones). The manual archive serialises
    /// raw records as-is, so **any non-nil value counts**, including a stored `0`
    /// total (`WorkoutManager` can record 0 totals). This deliberately differs
    /// from `presentFields`/the rendered exporters, which omit `0` totals — a
    /// `0` is still a HealthKit key in the archive JSON, so it must be disclosed.
    private static func rawStoredFields(in record: MatchRecord) -> Set<HealthExportField> {
        var fields: Set<HealthExportField> = []
        if record.totalSteps != nil { fields.insert(.steps) }
        if record.totalCaloriesKcal != nil { fields.insert(.calories) }
        if record.totalDistanceMeters != nil { fields.insert(.distance) }
        // Per-point heart rate and steps in a single pass; stop once both found.
        let needSteps = !fields.contains(.steps)
        for stat in record.stats {
            if stat.heartRateBPM != nil { fields.insert(.heartRate) }
            if needSteps, stat.stepsCumulative != nil { fields.insert(.steps) }
            if fields.contains(.heartRate) && fields.contains(.steps) { break }
        }
        return fields
    }

    /// The disclosure title + message naming exactly `fields` and the recipient
    /// implied by `destination`. Callers must pass a non-empty `fields` (they
    /// obtain it from `presentFields` and skip the dialog when it is empty).
    public static func disclosure(
        fields: [HealthExportField],
        destination: HealthExportDestination
    ) -> (title: String, message: String) {
        // Contract: callers pass a non-empty set (from `presentFields`) and skip
        // the dialog when it is empty. `assert` (debug-only) catches a miswired
        // caller in development without risking a release crash on this
        // user-facing path if the contract is ever broken in production.
        assert(!fields.isEmpty, "HealthExportConsent.disclosure requires a non-empty fields set")
        let list = formattedList(fields.map(\.displayName))
        let recipient: String
        switch destination {
        case .archiveFile:
            recipient = "the Files app or iCloud Drive location you choose"
        case .sharedReport:
            recipient = "whoever or whatever you send it to — a person, the Files app or iCloud Drive, or an AI service"
        }
        let message = "This export includes your recorded \(list). "
            + "DeuceMate has no server and never receives it, but \(recipient) will receive it."
        return (title: "Share health data?", message: message)
    }

    /// "a" · "a and b" · "a, b, and c" (Oxford comma).
    private static func formattedList(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) and \(items[1])"
        default:
            let head = items.dropLast().joined(separator: ", ")
            return "\(head), and \(items[items.count - 1])"
        }
    }
}

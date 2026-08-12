// MatchTrackingStatus.swift — single source of truth for the "what will this
// match actually record?" indicators shown before a match starts.
//
// Three things decide whether a finished match is rich or thin, and all three
// are easy to forget because they are set once and then invisible:
//   • Point tracking  — the user toggle that produces every derived stat.
//                       Suppressed entirely by formats that set
//                       `disablesPointTracking` (Perpetual Points), regardless
//                       of the toggle — see `pointTracking(isEnabled:matchFormat:)`.
//   • Health tracking — HealthKit access, which produces heart rate / steps /
//                       calories. There is no in-app toggle; it is a system
//                       permission, so the app can only report it.
//   • Pulse Coach     — heart-rate zone coaching, which needs Health *and* a
//                       calibrated max HR (birth year or manual override).
//                       Unlike the other two, an uncalibrated Pulse Coach is
//                       reversible: set a birth year later and past matches
//                       recompute, because zones are derived at display time.
//
// Kept in the package — like `SettingsCopy` and `ICloudBackupCopy` — so the
// pre-match strip, the settings screen, and any future iPhone mirror all read
// the same rule, and so the resolution stays unit-testable with no simulator.
// Deliberately free of HealthKit: the caller maps the platform authorization
// status onto `HealthAccess`. See docs/features/MATCH_START_UX_PLAN.md.
import Foundation

/// Platform-independent view of the app's HealthKit access, mapped by the watch
/// app from `HKHealthStore` so this package stays portable.
public enum HealthAccess: CaseIterable, Sendable {
    /// The device cannot record Health data at all.
    case unavailable
    /// The permission sheet has not been answered yet.
    case notDetermined
    /// The user declined, so no workout, heart rate, steps, or calories.
    case denied
    /// Granted — a workout session will record during the match.
    case authorized
}

/// How completely a tracking facet will record the next match.
public enum TrackingReadiness: Sendable, Equatable {
    /// Fully configured; the match will record this.
    case on
    /// Will record, but degraded — e.g. Pulse Coach running on the default max HR.
    case partial
    /// Will not record.
    case off
}

/// The three pre-match tracking facets, in the order they are displayed.
public enum TrackingFacet: String, CaseIterable, Sendable {
    case pointTracking
    case healthTracking
    case pulseCoach

    /// Full name, used in the settings list.
    public var title: String {
        switch self {
        case .pointTracking:  return "Point tracking"
        case .healthTracking: return "Health tracking"
        case .pulseCoach:     return "Pulse Coach"
        }
    }

    /// One-word name for the pre-match strip, where three chips share the width
    /// of a watch screen.
    public var shortTitle: String {
        switch self {
        case .pointTracking:  return "Points"
        case .healthTracking: return "Health"
        case .pulseCoach:     return "Pulse"
        }
    }

    /// SF Symbol paired with the label.
    public var systemImage: String {
        switch self {
        case .pointTracking:  return "hand.tap.fill"
        case .healthTracking: return "heart.fill"
        case .pulseCoach:     return "waveform.path.ecg"
        }
    }
}

/// A resolved facet: what it is, whether it will record, and the one line that
/// tells the user how to change it.
public struct MatchTrackingStatus: Sendable, Equatable {
    public let facet: TrackingFacet
    public let readiness: TrackingReadiness
    /// Two-to-four character state badge for the strip ("On", "Off", "Est.", "Ask", "—").
    public let stateLabel: String
    /// One line explaining the current state — and, when it is not `.on`, how
    /// to fix it. May contain `**...**` Markdown emphasis (render via
    /// `Text(LocalizedStringKey(_:))`, not the plain-`String` `Text` initializer,
    /// which does not parse Markdown).
    public let detail: String

    public init(
        facet: TrackingFacet,
        readiness: TrackingReadiness,
        stateLabel: String,
        detail: String
    ) {
        self.facet = facet
        self.readiness = readiness
        self.stateLabel = stateLabel
        self.detail = detail
    }

    public var title: String { facet.title }
    public var shortTitle: String { facet.shortTitle }
    public var systemImage: String { facet.systemImage }

    /// Spoken/VoiceOver form, e.g. "Point tracking: Off. …". Strips the
    /// Markdown emphasis markers — VoiceOver should speak the words, not "star star".
    public var accessibilityDescription: String {
        let plainDetail = detail.replacingOccurrences(of: "**", with: "")
        return "\(title): \(stateLabel). \(plainDetail)"
    }

    // MARK: - Copy

    /// How to grant Health access once it has been declined. Watch-app HealthKit
    /// permissions are managed from the paired iPhone.
    public static let healthAccessFixItNote =
        "Allow DeuceMate under Privacy → Health in the Watch app on iPhone."

    // MARK: - Resolution

    /// Point tracking is a plain user toggle — unless `matchFormat` disables it
    /// outright (Perpetual Points: no games/sets, no per-point categorisation),
    /// in which case it reports as suppressed regardless of the toggle. Feature
    /// A is only *correct* with this check: reading the toggle alone would claim
    /// "Points: On" for a format that records no point outcomes at all.
    public static func pointTracking(isEnabled: Bool, matchFormat: MatchFormat) -> MatchTrackingStatus {
        guard !matchFormat.config.disablesPointTracking else {
            return MatchTrackingStatus(
                facet: .pointTracking,
                readiness: .off,
                stateLabel: "—",
                detail: "Perpetual Points doesn't record point outcomes."
            )
        }
        return MatchTrackingStatus(
            facet: .pointTracking,
            readiness: isEnabled ? .on : .off,
            stateLabel: isEnabled ? "On" : "Off",
            detail: isEnabled
                ? SettingsCopy.trackPointOutcome.text
                : "No shot or outcome stats will be recorded for this match."
        )
    }

    /// Health tracking mirrors the system permission; the app cannot turn it on
    /// itself, so `.notDetermined` is reported separately from `.denied` —
    /// the first is answered by a prompt, the second only in iPhone settings.
    public static func healthTracking(access: HealthAccess) -> MatchTrackingStatus {
        switch access {
        case .authorized:
            return MatchTrackingStatus(
                facet: .healthTracking,
                readiness: .on,
                stateLabel: "On",
                detail: SettingsCopy.workoutSession.text
            )
        case .notDetermined:
            return MatchTrackingStatus(
                facet: .healthTracking,
                readiness: .partial,
                stateLabel: "Ask",
                detail: "DeuceMate will ask for Health access when the match starts."
            )
        case .denied:
            return MatchTrackingStatus(
                facet: .healthTracking,
                readiness: .off,
                stateLabel: "Off",
                detail: "No heart rate, steps, or calories. \(healthAccessFixItNote)"
            )
        case .unavailable:
            return MatchTrackingStatus(
                facet: .healthTracking,
                readiness: .off,
                stateLabel: "Off",
                detail: "This watch cannot record Health data."
            )
        }
    }

    /// Pulse Coach needs heart rate (so Health must be granted) *and* a max HR
    /// the user has calibrated. Without calibration it still runs, but on the
    /// 190 bpm fallback — reported as `.partial` rather than a confident "On",
    /// with copy that says the fix is retroactive (unlike Points/Health, this
    /// facet is calibration, not capture — see the file header).
    ///
    /// - Parameters:
    ///   - access: the same Health access used by `healthTracking(access:)`.
    ///   - birthYear: 0 when the user skipped it.
    ///   - maxHROverride: 0 (or out of range) when no manual override is set.
    public static func pulseCoach(
        access: HealthAccess,
        birthYear: Int,
        maxHROverride: Int,
        currentYear: Int = Calendar(identifier: .gregorian).component(.year, from: Date())
    ) -> MatchTrackingStatus {
        guard access == .authorized || access == .notDetermined else {
            return MatchTrackingStatus(
                facet: .pulseCoach,
                readiness: .off,
                stateLabel: "Off",
                detail: access == .unavailable
                    ? "Needs heart rate, which this watch cannot record."
                    : "Needs heart rate. \(healthAccessFixItNote)"
            )
        }
        let hasOverride = HRZone.isValidOverride(maxHROverride)
        let hasBirthYear = HRZone.isUsableBirthYear(birthYear, currentYear: currentYear)
        guard hasOverride || hasBirthYear else {
            return MatchTrackingStatus(
                facet: .pulseCoach,
                readiness: .partial,
                stateLabel: "Est.",
                detail: "\(SettingsCopy.defaultMaxHRNote). **Past matches recompute if you set it later.**"
            )
        }
        let maxHR = HRZone.resolveMaxHR(
            manualOverride: hasOverride ? maxHROverride : nil,
            birthYear: hasBirthYear ? birthYear : nil,
            currentYear: currentYear
        )
        return MatchTrackingStatus(
            facet: .pulseCoach,
            readiness: .on,
            stateLabel: "On",
            detail: "Heart-rate zones use your \(maxHR) bpm max HR."
        )
    }

    /// The full strip, in display order. One call site so the watch and any
    /// future iPhone mirror can never show a different set or a different
    /// order. Always three facets — used as-is by the Settings rows, where
    /// there's room to show the complete picture even when Pulse is off only
    /// because Health is off. The pre-match strip instead uses
    /// `collapsingPulseWhenHealthOff(_:)` on this result (see OQ-1).
    public static func all(
        matchFormat: MatchFormat,
        pointTrackingEnabled: Bool,
        healthAccess: HealthAccess,
        birthYear: Int,
        maxHROverride: Int,
        currentYear: Int = Calendar(identifier: .gregorian).component(.year, from: Date())
    ) -> [MatchTrackingStatus] {
        [
            pointTracking(isEnabled: pointTrackingEnabled, matchFormat: matchFormat),
            healthTracking(access: healthAccess),
            pulseCoach(
                access: healthAccess,
                birthYear: birthYear,
                maxHROverride: maxHROverride,
                currentYear: currentYear
            )
        ]
    }

    /// Drops the Pulse Coach status from `statuses` when Health is off — Pulse
    /// is off for that exact same single cause, and a second grey chip is pure
    /// redundancy on a 41 mm screen (OQ-1). Reads the Health status already in
    /// `statuses` rather than taking a separate `HealthAccess`, so this can never
    /// disagree with the Health chip sitting right next to it.
    public static func collapsingPulseWhenHealthOff(
        _ statuses: [MatchTrackingStatus]
    ) -> [MatchTrackingStatus] {
        guard let health = statuses.first(where: { $0.facet == .healthTracking }),
              health.readiness == .off else {
            return statuses
        }
        return statuses.filter { $0.facet != .pulseCoach }
    }
}

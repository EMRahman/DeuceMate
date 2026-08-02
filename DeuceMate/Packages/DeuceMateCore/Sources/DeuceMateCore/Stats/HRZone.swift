// HRZone.swift — heart-rate effort zones, derived from a percentage of the
// player's max HR. Zone boundaries follow the standard 5-zone training model.
import Foundation

public enum HRZone: Int, CaseIterable, Codable, Sendable {
    case z1 = 1
    case z2
    case z3
    case z4
    case z5

    public var displayLabel: String {
        switch self {
        case .z1: return "Z1"
        case .z2: return "Z2"
        case .z3: return "Z3"
        case .z4: return "Z4"
        case .z5: return "Z5"
        }
    }

    public var descriptiveLabel: String {
        switch self {
        case .z1: return "Very Light"
        case .z2: return "Light"
        case .z3: return "Moderate"
        case .z4: return "Hard"
        case .z5: return "Maximum"
        }
    }

    public static func zone(forBPM bpm: Int, maxHR: Int) -> HRZone {
        guard maxHR > 0 else { return .z1 }
        let pct = Double(bpm) / Double(maxHR)
        switch pct {
        case ..<0.60:  return .z1
        case ..<0.70:  return .z2
        case ..<0.80:  return .z3
        case ..<0.90:  return .z4
        default:       return .z5
        }
    }

    public static func ceilingBPM(for zone: HRZone, maxHR: Int) -> Int {
        switch zone {
        case .z1: return Int(Double(maxHR) * 0.60) - 1
        case .z2: return Int(Double(maxHR) * 0.70) - 1
        case .z3: return Int(Double(maxHR) * 0.80) - 1
        case .z4: return Int(Double(maxHR) * 0.90) - 1
        case .z5: return maxHR
        }
    }

    /// Valid bpm range for a manual override. Values outside this range are ignored
    /// by `resolveMaxHR` and must not be treated as "active" in the UI.
    public static let overrideMinBPM: Int = 120
    public static let overrideMaxBPM: Int = 220
    /// Sensible starting value when the user first enables the manual override.
    public static let defaultOverrideBPM: Int = 180

    /// Returns `true` when `bpm` falls within the valid manual-override range.
    public static func isValidOverride(_ bpm: Int) -> Bool {
        bpm >= overrideMinBPM && bpm <= overrideMaxBPM
    }

    /// Returns `true` when `birthYear` produces an age `resolveMaxHR` will
    /// actually use (rather than silently falling back to the 190 bpm default).
    /// Exposed so the UI can tell "calibrated" from "running on the default"
    /// without re-deriving — and without comparing against 190, which is also a
    /// legitimate age-derived result (age 30).
    public static func isUsableBirthYear(
        _ birthYear: Int,
        currentYear: Int = Calendar(identifier: .gregorian).component(.year, from: Date())
    ) -> Bool {
        guard birthYear > 1900, birthYear <= currentYear else { return false }
        let age = currentYear - birthYear
        return age >= 5 && age <= 100
    }

    /// Resolve the player's max HR using the configured precedence:
    /// manual override → 220−age → 190.
    public static func resolveMaxHR(
        manualOverride: Int?,
        birthYear: Int?,
        currentYear: Int = Calendar(identifier: .gregorian).component(.year, from: Date())
    ) -> Int {
        if let m = manualOverride, isValidOverride(m) { return m }
        if let by = birthYear, isUsableBirthYear(by, currentYear: currentYear) {
            return 220 - (currentYear - by)
        }
        return 190
    }
}

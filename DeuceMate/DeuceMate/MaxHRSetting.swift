// MaxHRSetting.swift — the phone's shared READER of the max-HR user setting.
//
// `userBirthYear` and `userMaxHROverride` are synced settings whose local
// UserDefaults keys are also `MatchSyncKey` raw values, so every extra literal
// copy is another chance to drift (CLAUDE.md §5). Before this type the pair
// plus the same `HRZone.resolveMaxHR` call were duplicated in `SettingsView`
// and `MatchDetailView`, and Trends needed a third copy.
//
// `SettingsView` deliberately keeps its own `@AppStorage` declarations: it is
// the settings *editor*, so it needs write bindings and pushes each change over
// WatchConnectivity. This type serves the read-only consumers, which only ever
// need the resolved value and whether it is calibrated.
import SwiftUI
import DeuceMateCore

/// Resolves the player's max HR from the two stored Pulse Coach settings.
///
/// Conforms to `DynamicProperty` so its nested `@AppStorage` members keep
/// participating in SwiftUI's update cycle: declare it as a plain `private var`
/// in a `View` and the view still redraws when either setting changes.
struct MaxHRSetting: DynamicProperty {
    @AppStorage("userBirthYear") private var birthYear: Int = 0
    @AppStorage("userMaxHROverride") private var manualOverride: Int = 0

    /// Manual override → 220−age → 190, via Core's single precedence rule.
    var resolved: Int {
        HRZone.resolveMaxHR(
            manualOverride: manualOverride > 0 ? manualOverride : nil,
            birthYear: birthYear > 0 ? birthYear : nil
        )
    }

    /// `true` when `resolved` reflects the player's own data rather than the
    /// 190 bpm fallback. Uses `HRZone.isUsableBirthYear` rather than comparing
    /// `resolved` against 190, which is also a legitimate age-derived result
    /// (age 30) — the exact distinction that helper exists to make.
    var isCalibrated: Bool {
        if HRZone.isValidOverride(manualOverride) { return true }
        return birthYear > 0 && HRZone.isUsableBirthYear(birthYear)
    }
}

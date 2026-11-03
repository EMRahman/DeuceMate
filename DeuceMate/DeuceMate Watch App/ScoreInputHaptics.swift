//
//  ScoreInputHaptics.swift
//  DeuceMate Watch App
//
//  Optional wrist confirmation that an on-watch score input actually counted,
//  so a player can tell without looking down that a sweaty or wet swipe
//  registered. Off by default. Watch-local: only the watch vibrates, so the
//  preference has no wire key and never syncs to the phone.
//

import DeuceMateCore
import WatchKit

enum ScoreInputHaptics {
    /// Watch-local `UserDefaults` key. Deliberately not a `MatchSyncKey`.
    static let enabledKey = "swipeHapticsEnabled"
    static let isEnabledByDefault = false

    /// The pattern confirming an action, or nil when it changes no score.
    static func hapticType(for action: ScoreInputAction) -> WKHapticType? {
        switch action {
        case .win: return .directionUp
        case .lose: return .directionDown
        case .undo: return .click
        case .stats: return nil
        }
    }

    /// Call only after the action has been applied, so a tap always means the
    /// score changed and silence means "swipe again".
    static func confirm(
        _ action: ScoreInputAction,
        isEnabled: Bool,
        play: (WKHapticType) -> Void = { WKInterfaceDevice.current().play($0) }
    ) {
        guard isEnabled, let haptic = hapticType(for: action) else { return }
        play(haptic)
    }
}

//
//  ScoreInputHaptics.swift
//  DeuceMate Watch App
//
//  Optional wrist confirmation that an on-watch score input actually counted,
//  so a player can tell without looking down that a sweaty or wet swipe
//  registered. Off by default. Only the watch vibrates, but the preference
//  syncs both ways with the iPhone's Settings (last write wins) under the same
//  string as its `MatchSyncKey`.
//

import DeuceMateCore
import WatchKit

enum ScoreInputHaptics {
    /// `UserDefaults` key; the same string as `MatchSyncKey.swipeHapticsEnabled`.
    static let enabledKey = MatchSyncKey.swipeHapticsEnabled
    static let isEnabledByDefault = false

    /// Persists a value the paired iPhone sent. Writes `UserDefaults` only: the
    /// views observe it via `@AppStorage`, and because no setter runs, nothing is
    /// pushed back (no echo loop).
    static func storeIncoming(_ enabled: Bool, defaults: UserDefaults = .standard) {
        guard defaults.object(forKey: enabledKey) as? Bool != enabled else { return }
        defaults.set(enabled, forKey: enabledKey)
    }

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

// SettingsCopy.swift — single source of truth for the one-line summary shown
// under each user-configurable setting on both the iPhone and the Apple Watch.
// Defined once here so the two apps can never drift apart (the settings copy and
// the wire keys live in this package precisely to avoid that trap).
import Foundation

public enum SettingsCopy: CaseIterable, Sendable {
    case trackPointOutcome
    case workoutSession
    case changeoverCompass
    case appearanceTheme
    case announceScores
    case iPhoneInput
    case birthYear
    case overrideMaxHR
    case playerLevelNTRP
    case iCloudSync

    /// One concise sentence describing what the setting does. Plain language a club
    /// player understands, ends with a period, and kept short enough for the Watch.
    public var text: String {
        switch self {
        case .trackPointOutcome:     return "After each point, tag the winner and shot to build detailed stats."
        case .workoutSession:        return "Runs an Apple Watch workout to log heart rate and calories."
        case .changeoverCompass:     return "Uses the watch compass to confirm your court end at changeovers."
        case .appearanceTheme:       return "Sets the scoreboard color theme on both your iPhone and watch."
        case .announceScores:        return "Speaks the score aloud through your iPhone speaker."
        case .iPhoneInput:           return "Lets you swipe to score on the iPhone scoreboard."
        case .birthYear:             return "Estimates your maximum heart rate from your age."
        case .overrideMaxHR:         return "Sets your maximum heart rate manually instead of by age."
        case .playerLevelNTRP:       return "Your skill level, used to tailor AI coaching advice."
        case .iCloudSync:            return "Backs up your match history to your personal iCloud account."
        }
    }

    /// Shared length budget so the UI, the copy author, and the unit test agree on
    /// one number. Kept tight so summaries stay one short line on the Apple Watch.
    public static let maxLength = 90
}

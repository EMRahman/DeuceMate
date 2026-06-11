// MatchStats.swift
import SwiftUI
import DeuceMateCore

// Re-export package types under the ScoreViewModel namespace so existing code
// that references ScoreViewModel.Player etc. continues to compile without
// changes throughout the watch target. All canonical definitions now live in
// DeuceMateCore.
extension ScoreViewModel {
    typealias Player        = DeuceMateCore.Player
    typealias MatchType     = DeuceMateCore.MatchType
    typealias MatchFormat   = DeuceMateCore.MatchFormat
    typealias DoublesServer = DeuceMateCore.DoublesServer
    typealias SetScore      = DeuceMateCore.SetScore
}

// MARK: - SwiftUI presentation extensions (watch-only, platform-specific)

extension MatchFormat {
    var displayLabel: String {
        switch self {
        case .standard: return "Best of 3"
        case .bestOf3FullFinalSet: return "Best of 3 (Full Final Set)"
        case .superTiebreak: return "Super Tiebreak"
        case .perpetualSuperTiebreak: return "Perpetual Tiebreak"
        case .quick4Games: return "Quick 4 Games"
        case .perpetualPoints: return "Perpetual Points"
        }
    }
}

extension PointOutcome {
    // Static constants so Color objects are created once, not on every button render.
    static let tintDoubleFault   = Color(red: 0.86, green: 0.36, blue: 0.36)
    static let tintWinner        = Color(red: 0.30, green: 0.78, blue: 0.50)
    static let tintForcedError   = Color(red: 0.92, green: 0.70, blue: 0.30)
    static let tintUnforcedError = Color(red: 0.66, green: 0.50, blue: 0.92)

    var tintColor: Color {
        switch self {
        case .doubleFault:   return PointOutcome.tintDoubleFault
        case .winner:        return PointOutcome.tintWinner
        case .forcedError:   return PointOutcome.tintForcedError
        case .unforcedError: return PointOutcome.tintUnforcedError
        case .uncategorized: return .gray
        }
    }
}

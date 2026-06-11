// ScoreTypes.swift — top-level types lifted from ScoreViewModel so both the
// watch and phone targets share a single definition.
import Foundation

/// The two sides of a match from the user's perspective.
public enum Player: String, Codable, Sendable {
    case me, opponent
}

/// Whether the match is singles or doubles.
public enum MatchType: String, Codable, Sendable {
    case singles, doubles
}

/// Overall match structure.
///
/// - `.standard`: best-of-3 sets, deciding set is a 10-pt super-tiebreak.
/// - `.bestOf3FullFinalSet`: best-of-3 sets, deciding set is a full set with 7-pt tiebreak at 6–6 (ATP tour).
/// - `.superTiebreak`: the entire match is a single 10-pt tiebreak.
/// - `.perpetualSuperTiebreak`: continuous series of 10-pt tiebreaks ("Perpetual Tiebreak").
/// - `.quick4Games`: single short set, first to 3 games; at 2–2 a single sudden-death point decides the match.
/// - `.perpetualPoints`: simple running point counter with tiebreak-style server rotation; no games/sets, no auto-completion, no post-point categorisation.
public enum MatchFormat: String, Codable, Sendable {
    case standard, bestOf3FullFinalSet, superTiebreak, perpetualSuperTiebreak, quick4Games, perpetualPoints
}

/// How the deciding set is played when both players need one more set to win.
public enum FinalSetStyle: Equatable, Sendable {
    case superTiebreak          // jump straight to a tiebreak-only set
    case fullSetWithTiebreak    // play a full regular set; tiebreak triggers at 6–6
}

/// Data-driven description of a match format's rules.
/// Add a new format by adding a `MatchFormat` case and defining its `MatchFormatConfig`.
public struct MatchFormatConfig: Sendable {
    public let setsToWin: Int
    public let playRegularSets: Bool        // false = entire match is tiebreak(s)
    public let regularSetWinAtGames: Int    // games needed to win a regular set (6 normally, 3 for Quick 4)
    public let regularSetTiebreakAtGames: Int // games at which a tiebreak triggers (6 normally, 2 for Quick 4)
    public let regularSetTiebreakPoints: Int
    public let finalSetStyle: FinalSetStyle
    public let finalSetTiebreakPoints: Int
    public let tiebreakRequiresTwoPointLead: Bool // false = sudden death (single decisive point)
    public let isEndless: Bool              // true = match never ends automatically
    public let disablesPointTracking: Bool  // true = never present the post-point categorisation sheet
    public let fixedDeuceSide: Bool         // true = always display the server on the deuce side (no side toggle)

    public init(setsToWin: Int,
                playRegularSets: Bool,
                regularSetWinAtGames: Int = 6,
                regularSetTiebreakAtGames: Int = 6,
                regularSetTiebreakPoints: Int,
                finalSetStyle: FinalSetStyle,
                finalSetTiebreakPoints: Int,
                tiebreakRequiresTwoPointLead: Bool = true,
                isEndless: Bool,
                disablesPointTracking: Bool = false,
                fixedDeuceSide: Bool = false) {
        self.setsToWin = setsToWin
        self.playRegularSets = playRegularSets
        self.regularSetWinAtGames = regularSetWinAtGames
        self.regularSetTiebreakAtGames = regularSetTiebreakAtGames
        self.regularSetTiebreakPoints = regularSetTiebreakPoints
        self.finalSetStyle = finalSetStyle
        self.finalSetTiebreakPoints = finalSetTiebreakPoints
        self.tiebreakRequiresTwoPointLead = tiebreakRequiresTwoPointLead
        self.isEndless = isEndless
        self.disablesPointTracking = disablesPointTracking
        self.fixedDeuceSide = fixedDeuceSide
    }

    /// Game count recorded for the winner of a regular-set tiebreak
    /// (e.g. 7 for a standard 6–6 tiebreak set, 3 for the Quick 4 sudden death).
    public var regularSetTiebreakWinAtGames: Int { regularSetTiebreakAtGames + 1 }

    /// True when a regular (non-pure-tiebreak) set is complete given its game counts.
    /// Covers both "reached win threshold with a 2-game lead" and
    /// "won via the in-set tiebreak" (game count equals the tiebreak-win value).
    public func isNormalSetComplete(gamesMe: Int, gamesOpponent: Int) -> Bool {
        let diff = abs(gamesMe - gamesOpponent)
        return ((gamesMe >= regularSetWinAtGames || gamesOpponent >= regularSetWinAtGames) && diff >= 2)
            || gamesMe == regularSetTiebreakWinAtGames
            || gamesOpponent == regularSetTiebreakWinAtGames
    }

    /// True when the set at `setIndex` is the deciding set played as a super tiebreaker
    /// (i.e. no games are played — the set is a standalone 10-point tiebreak).
    public func isDecidingSuperTiebreak(setIndex: Int) -> Bool {
        playRegularSets && finalSetStyle == .superTiebreak && setIndex == setsToWin * 2 - 2
    }
}

extension MatchFormat {
    public var config: MatchFormatConfig {
        switch self {
        case .standard:
            return MatchFormatConfig(setsToWin: 2, playRegularSets: true,
                                     regularSetTiebreakPoints: 7,
                                     finalSetStyle: .superTiebreak,
                                     finalSetTiebreakPoints: 10, isEndless: false)
        case .bestOf3FullFinalSet:
            return MatchFormatConfig(setsToWin: 2, playRegularSets: true,
                                     regularSetTiebreakPoints: 7,
                                     finalSetStyle: .fullSetWithTiebreak,
                                     finalSetTiebreakPoints: 7, isEndless: false)
        case .superTiebreak:
            return MatchFormatConfig(setsToWin: 1, playRegularSets: false,
                                     regularSetTiebreakPoints: 10,
                                     finalSetStyle: .superTiebreak,
                                     finalSetTiebreakPoints: 10, isEndless: false)
        case .perpetualSuperTiebreak:
            return MatchFormatConfig(setsToWin: 1, playRegularSets: false,
                                     regularSetTiebreakPoints: 10,
                                     finalSetStyle: .superTiebreak,
                                     finalSetTiebreakPoints: 10, isEndless: true)
        case .quick4Games:
            return MatchFormatConfig(setsToWin: 1, playRegularSets: true,
                                     regularSetWinAtGames: 3,
                                     regularSetTiebreakAtGames: 2,
                                     regularSetTiebreakPoints: 1,
                                     finalSetStyle: .fullSetWithTiebreak,
                                     finalSetTiebreakPoints: 1,
                                     tiebreakRequiresTwoPointLead: false,
                                     isEndless: false)
        case .perpetualPoints:
            // Single endless point counter. Server rotates with tiebreak-style
            // ball changes (every 2 points after the opening point). No games,
            // no sets, no win condition, no categorisation sheet, and the
            // server display sticks to the deuce side instead of toggling.
            return MatchFormatConfig(setsToWin: 1, playRegularSets: false,
                                     regularSetTiebreakPoints: 10,
                                     finalSetStyle: .superTiebreak,
                                     finalSetTiebreakPoints: 10,
                                     isEndless: true,
                                     disablesPointTracking: true,
                                     fixedDeuceSide: true)
        }
    }
}

/// Which doubles player is serving. Team membership is encoded in `team`.
public enum DoublesServer: String, Codable, CaseIterable, Sendable {
    case me, partner, opponentS1, opponentS2

    public var team: Player {
        switch self {
        case .me, .partner: return .me
        case .opponentS1, .opponentS2: return .opponent
        }
    }

    public var displayName: String {
        switch self {
        case .me:         return "Me"
        case .partner:    return "Partner"
        case .opponentS1: return "S1"
        case .opponentS2: return "S2"
        }
    }
}

/// The score of a single set, regular games or tiebreak.
public struct SetScore: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public var gamesMe: Int
    public var gamesOpponent: Int
    public var isTieBreak: Bool
    public var tieBreakPointsMe: Int
    public var tieBreakPointsOpponent: Int

    public init(
        id: UUID = UUID(),
        gamesMe: Int = 0,
        gamesOpponent: Int = 0,
        isTieBreak: Bool = false,
        tieBreakPointsMe: Int = 0,
        tieBreakPointsOpponent: Int = 0
    ) {
        self.id = id
        self.gamesMe = gamesMe
        self.gamesOpponent = gamesOpponent
        self.isTieBreak = isTieBreak
        self.tieBreakPointsMe = tieBreakPointsMe
        self.tieBreakPointsOpponent = tieBreakPointsOpponent
    }
}

// ScoreTypesTests.swift — the shared score vocabulary: doubles server identity
// and the `SetScore` value type both apps display.
import XCTest
@testable import DeuceMateCore

final class ScoreTypesTests: XCTestCase {

    // MARK: - DoublesServer

    func test_doublesServer_teamMembership() {
        XCTAssertEqual(DoublesServer.me.team, .me)
        XCTAssertEqual(DoublesServer.partner.team, .me)
        XCTAssertEqual(DoublesServer.opponentS1.team, .opponent)
        XCTAssertEqual(DoublesServer.opponentS2.team, .opponent)
    }

    func test_doublesServer_everyCaseHasATeamAndDistinctDisplayName() {
        let names = DoublesServer.allCases.map(\.displayName)
        XCTAssertEqual(names, ["Me", "Partner", "S1", "S2"])
        XCTAssertEqual(Set(names).count, DoublesServer.allCases.count)
        // Exactly one service pair per side, so the alternating service order
        // the watch builds is always two-and-two.
        XCTAssertEqual(DoublesServer.allCases.filter { $0.team == .me }.count, 2)
        XCTAssertEqual(DoublesServer.allCases.filter { $0.team == .opponent }.count, 2)
    }

    func test_doublesServer_rawValuesArePersistedIdentifiers() throws {
        // Raw values reach persisted match JSON — renaming one breaks archives.
        XCTAssertEqual(DoublesServer.allCases.map(\.rawValue),
                       ["me", "partner", "opponentS1", "opponentS2"])
        let data = try JSONEncoder().encode(DoublesServer.opponentS2)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "\"opponentS2\"")
        XCTAssertEqual(try JSONDecoder().decode(DoublesServer.self, from: Data("\"partner\"".utf8)),
                       .partner)
    }

    // MARK: - MatchFormat

    func test_matchFormat_rawValuesArePersistedIdentifiers() throws {
        // Raw values reach persisted match JSON (`matchHistory.json`, `appState.json`) —
        // retired cases such as `.quick4Games` must remain decodable with their pinned
        // raw value forever.
        let persisted: [(MatchFormat, String)] = [
            (.standard, "standard"),
            (.bestOf3FullFinalSet, "bestOf3FullFinalSet"),
            (.superTiebreak, "superTiebreak"),
            (.perpetualSuperTiebreak, "perpetualSuperTiebreak"),
            (.quick4Games, "quick4Games"),
            (.shortSets, "shortSets"),
            (.fast4, "fast4"),
            (.perpetualPoints, "perpetualPoints")
        ]
        for (format, raw) in persisted {
            XCTAssertEqual(format.rawValue, raw)
            XCTAssertEqual(try JSONDecoder().decode(MatchFormat.self, from: Data("\"\(raw)\"".utf8)), format)
        }
        XCTAssertFalse(MatchFormat.userSelectable.contains(.quick4Games))
        XCTAssertTrue(MatchFormat.userSelectable.contains(.shortSets))
        XCTAssertTrue(MatchFormat.userSelectable.contains(.fast4))
    }

    // MARK: - SetScore

    func test_setScore_defaultsToAnUnplayedRegularSet() {
        let score = SetScore()
        XCTAssertEqual(score.gamesMe, 0)
        XCTAssertEqual(score.gamesOpponent, 0)
        XCTAssertFalse(score.isTieBreak)
        XCTAssertEqual(score.tieBreakPointsMe, 0)
        XCTAssertEqual(score.tieBreakPointsOpponent, 0)
    }

    func test_setScore_identityIsStableAcrossRoundTrip() throws {
        let score = SetScore(gamesMe: 7, gamesOpponent: 6,
                             isTieBreak: true,
                             tieBreakPointsMe: 7, tieBreakPointsOpponent: 5)
        let decoded = try JSONDecoder().decode(
            SetScore.self, from: try JSONEncoder().encode(score)
        )
        XCTAssertEqual(decoded, score)
        XCTAssertEqual(decoded.id, score.id)
    }
}

// SetScoreLabelTests.swift — canonical set and pre-point game-score labels.
import XCTest
@testable import DeuceMateCore

final class SetScoreLabelTests: XCTestCase {
    func test_regularSet_orientsBothPerspectives() {
        let set = SetScore(gamesMe: 6, gamesOpponent: 4)

        XCTAssertEqual(label(set, index: 0, format: .standard), "6–4")
        XCTAssertEqual(label(set, index: 0, format: .standard, focal: .opponent), "4–6")
        XCTAssertEqual(label(set, index: 2, format: .bestOf3FullFinalSet), "6–4")
        XCTAssertEqual(label(SetScore(gamesMe: 3, gamesOpponent: 1), index: 0, format: .quick4Games), "3–1")
    }

    func test_regularSetTiebreak_includesCanonicalSpaceAndOrientsBothScores() {
        let set = SetScore(
            gamesMe: 7,
            gamesOpponent: 6,
            isTieBreak: true,
            tieBreakPointsMe: 7,
            tieBreakPointsOpponent: 5
        )

        XCTAssertEqual(label(set, index: 0, format: .standard), "7–6 (7–5)")
        XCTAssertEqual(label(set, index: 0, format: .standard, focal: .opponent), "6–7 (5–7)")
        XCTAssertEqual(label(set, index: 2, format: .bestOf3FullFinalSet), "7–6 (7–5)")

        let quick = SetScore(
            gamesMe: 3,
            gamesOpponent: 2,
            isTieBreak: true,
            tieBreakPointsMe: 1,
            tieBreakPointsOpponent: 0
        )
        XCTAssertEqual(label(quick, index: 0, format: .quick4Games), "3–2 (1–0)")
    }

    func test_tiebreakOnlyScores_useRawPointsForEveryApplicableFormat() {
        let deciding = SetScore(
            isTieBreak: true,
            tieBreakPointsMe: 10,
            tieBreakPointsOpponent: 8
        )
        XCTAssertEqual(label(deciding, index: 2, format: .standard), "10–8")
        XCTAssertEqual(label(deciding, index: 0, format: .superTiebreak), "10–8")
        XCTAssertEqual(label(deciding, index: 1, format: .perpetualSuperTiebreak), "10–8")
        XCTAssertEqual(label(deciding, index: 0, format: .perpetualPoints), "10–8")
        XCTAssertEqual(label(deciding, index: 0, format: .superTiebreak, focal: .opponent), "8–10")
    }

    func test_gameScoreLabel_reorientsServerRelativeSnapshots() {
        XCTAssertEqual(
            GameScoreLabel.string(
                for: GameScoreSnapshot(server: 1, returner: 2, isTiebreak: false),
                server: .me
            ),
            "15–30"
        )
        XCTAssertEqual(
            GameScoreLabel.string(
                for: GameScoreSnapshot(server: 1, returner: 2, isTiebreak: false),
                server: .opponent
            ),
            "30–15"
        )
    }

    func test_gameScoreLabel_formatsDeuceAdvantageAndTiebreaks() {
        XCTAssertEqual(
            GameScoreLabel.string(
                for: GameScoreSnapshot(server: 3, returner: 3, isTiebreak: false),
                server: .me
            ),
            "Deuce"
        )
        XCTAssertEqual(
            GameScoreLabel.string(
                for: GameScoreSnapshot(server: 4, returner: 3, isTiebreak: false),
                server: .opponent
            ),
            "Ad Opp"
        )
        XCTAssertEqual(
            GameScoreLabel.string(
                for: GameScoreSnapshot(server: 4, returner: 6, isTiebreak: true),
                server: .opponent
            ),
            "6–4"
        )
    }

    private func label(
        _ set: SetScore,
        index: Int,
        format: MatchFormat,
        focal: Player = .me
    ) -> String {
        SetScoreLabel.string(
            for: set,
            setIndex: index,
            matchFormat: format,
            focal: focal
        )
    }
}

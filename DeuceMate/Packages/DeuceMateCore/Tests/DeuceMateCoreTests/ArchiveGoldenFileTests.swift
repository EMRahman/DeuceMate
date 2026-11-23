// ArchiveGoldenFileTests.swift — a frozen archive every build must still decode
// (ARCHIVE_DERISK_PLAN.md §2, TECHNICAL_DEBT #18).
//
// ⚠️ APPEND-ONLY FIXTURE. `goldenRecordsJSON` was encoded ONCE, on 2026-11-23,
// by that day's `JSONEncoder` and committed as text. Never regenerate it from
// the current encoder and never edit an existing line: either would make this
// test pass against whatever the code does now, so it would test nothing. A new
// field or enum case gets a NEW match appended at the end (and the expected
// count raised); the JSON already here stays exactly as written.
//
// The eight fictional matches together use every case of every persisted enum
// (`MatchFormat`, `MatchType`, `Player`, `DoublesServer`, `PointOutcome`,
// `EndingShot`), plus tags with playing profiles, a match-type revision, a
// resume event, a parked checkpoint and the Health fields. A deleted or renamed
// case, a renamed property or a newly required field fails here in Xcode
// rather than on an iPhone, where it would empty the archive.
import XCTest
@testable import DeuceMateCore

final class ArchiveGoldenFileTests: XCTestCase {

    func test_goldenRecords_decodeAsCanonicalArchive() throws {
        let records = try JSONDecoder().decode([MatchRecord].self, from: Data(Self.goldenRecordsJSON.utf8))
        try assertGoldenRecords(records)
    }

    func test_goldenRecords_decodeAsManualArchiveFile() throws {
        let archive = try ManualMatchArchiveBackup.decode(Data(Self.goldenManualArchiveJSON.utf8))
        try assertGoldenRecords(archive.records)
        XCTAssertTrue(archive.includesHealthData)
        XCTAssertEqual(archive.exportedAt, Date(timeIntervalSinceReferenceDate: 784_700_000))
        XCTAssertEqual(archive.forgottenPlayers?.playerIDs, [Self.uuid(999)])
    }

    /// The other two canonical files: `deletedMatchIDs.json` and `forgottenPlayers.json`.
    func test_goldenTombstonesAndLedger_decode() throws {
        let tombstones = try JSONDecoder().decode([UUID].self, from: Data(Self.goldenTombstonesJSON.utf8))
        XCTAssertEqual(tombstones, [Self.uuid(998)])
        let ledger = try JSONDecoder().decode(ForgottenPlayerLedger.self, from: Data(Self.goldenLedgerJSON.utf8))
        XCTAssertEqual(ledger.playerIDs, [Self.uuid(999)])
        XCTAssertEqual(ledger.schemaVersion, 1)
    }

    // MARK: - Assertions

    private func assertGoldenRecords(_ records: [MatchRecord], file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(records.count, 8, file: file, line: line)
        let byID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        func match(_ n: Int) throws -> MatchRecord { try XCTUnwrap(byID[Self.uuid(n)], file: file, line: line) }
        let points = records.flatMap(\.stats)

        // Every case of every persisted enum decodes.
        XCTAssertEqual(Set(records.map(\.matchFormat)), [
            .standard, .bestOf3FullFinalSet, .superTiebreak, .perpetualSuperTiebreak,
            .quick4Games, .shortSets, .fast4, .perpetualPoints
        ], file: file, line: line)
        XCTAssertEqual(Set(records.map(\.matchType)), [.singles, .doubles], file: file, line: line)
        XCTAssertEqual(Set(points.map(\.server)), [.me, .opponent], file: file, line: line)
        XCTAssertEqual(Set(points.map(\.winner)), [.me, .opponent], file: file, line: line)
        // `allCases`: a new case fails here until a match using it is appended.
        XCTAssertEqual(Set(records.compactMap(\.doublesServer)), Set(DoublesServer.allCases), file: file, line: line)
        XCTAssertEqual(Set(points.map(\.outcome)), Set(PointOutcome.allCases), file: file, line: line)
        XCTAssertEqual(Set(points.compactMap(\.endingShot)), Set(EndingShot.allCases), file: file, line: line)

        // A few values per enum, pinned to the match that holds them.
        let standard = try match(1)
        XCTAssertEqual(standard.matchFormat, .standard, file: file, line: line)
        XCTAssertEqual(standard.stats.map(\.outcome), [.winner, .doubleFault], file: file, line: line)
        XCTAssertEqual(standard.stats.map(\.endingShot), [.return, .serve], file: file, line: line)
        XCTAssertEqual(standard.recentPoints, [.me, .opponent], file: file, line: line)
        XCTAssertEqual(try match(2).stats.first?.endingShot, .servePlusOne, file: file, line: line)
        let tiebreak = try match(3)
        XCTAssertEqual(tiebreak.matchFormat, .superTiebreak, file: file, line: line)
        XCTAssertEqual(tiebreak.tiebreakStartServer, .opponent, file: file, line: line)
        XCTAssertEqual(tiebreak.tiebreakFirstPointReceiver, .me, file: file, line: line)
        XCTAssertEqual(tiebreak.stats.first?.gameScoreAtStart, GameScoreSnapshot(server: 4, returner: 4, isTiebreak: true), file: file, line: line)
        let parked = try match(4)
        XCTAssertEqual(parked.matchType, .doubles, file: file, line: line)
        XCTAssertEqual(parked.doublesServer, .partner, file: file, line: line)
        XCTAssertEqual(parked.doublesServiceOrder, [.me, .opponentS1, .partner, .opponentS2], file: file, line: line)
        XCTAssertEqual(parked.currentServer, .opponent, file: file, line: line)
        XCTAssertEqual(try match(5).matchFormat, .quick4Games, file: file, line: line)
        XCTAssertEqual(try match(5).stats.first?.outcome, .uncategorized, file: file, line: line)
        XCTAssertEqual(try match(7).doublesServer, .opponentS2, file: file, line: line)
        XCTAssertFalse(try match(7).momentumEnabled, file: file, line: line)
        let points8 = try match(8)
        XCTAssertEqual(points8.matchFormat, .perpetualPoints, file: file, line: line)
        XCTAssertEqual(points8.currentPointsMe, 11, file: file, line: line)
        XCTAssertEqual(points8.checkpointRevision, 21, file: file, line: line)

        // Dates keep their numeric (seconds since 2001) encoding.
        XCTAssertEqual(standard.startTime, Date(timeIntervalSinceReferenceDate: 784_000_000), file: file, line: line)
        XCTAssertEqual(standard.endTime, Date(timeIntervalSinceReferenceDate: 784_003_600), file: file, line: line)
        XCTAssertEqual(standard.setScores.last?.tieBreakPointsMe, 10, file: file, line: line)
        XCTAssertEqual(standard.setElapsedSeconds[2], 600.5, file: file, line: line)

        // Health fields.
        XCTAssertEqual(standard.totalSteps, 4321, file: file, line: line)
        XCTAssertEqual(standard.totalDistanceMeters, 2875.25, file: file, line: line)
        XCTAssertEqual(standard.totalCaloriesKcal, 512.75, file: file, line: line)
        XCTAssertEqual(standard.stats.map(\.heartRateBPM), [141, 148], file: file, line: line)
        XCTAssertEqual(standard.stats.map(\.stepsCumulative), [35, 61], file: file, line: line)

        // Tags, match-type revision, resume events, parked checkpoint.
        let opponent = try XCTUnwrap(standard.tags?.opponents.first, file: file, line: line)
        XCTAssertEqual(opponent.name, "Sam Sample", file: file, line: line)
        XCTAssertEqual(opponent.handedness, .leftHanded, file: file, line: line)
        XCTAssertEqual(opponent.backhand, .oneHanded, file: file, line: line)
        XCTAssertEqual(opponent.playStyle, .serveAndVolley, file: file, line: line)
        XCTAssertNotNil(opponent.playingNotes, file: file, line: line)
        XCTAssertEqual(standard.tags?.competitionType, .league, file: file, line: line)
        XCTAssertEqual(parked.tags?.competitionType, .tournament, file: file, line: line)
        XCTAssertEqual(parked.tags?.opponents.count, 2, file: file, line: line)
        XCTAssertEqual(parked.tags?.partner?.name, "Casey Fixture", file: file, line: line)
        XCTAssertEqual(try match(2).matchTypeRevision?.matchType, .singles, file: file, line: line)
        XCTAssertEqual(standard.resumeEvents.first?.precedingPointID, Self.uuid(111), file: file, line: line)
        XCTAssertEqual(standard.resumeEvents.first?.breakDuration, 100, file: file, line: line)
        XCTAssertEqual(parked.parkedAt, Date(timeIntervalSinceReferenceDate: 784_260_000), file: file, line: line)
        XCTAssertTrue(parked.isInProgress, file: file, line: line)
    }

    private static func uuid(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", n)) ?? UUID()
    }

    // MARK: - Fixture (append-only — see the header)

    private static let goldenRecordsJSON = #"""
[
{"checkpointRevision":7,"currentPointsMe":0,"currentPointsOpponent":0,"doublesServiceIndex":0,"doublesServiceOrder":[],"endTime":784003600,"gameCount":0,"iWon":true,"id":"00000000-0000-4000-8000-000000000001","isOnSecondServe":false,"matchElapsedSeconds":3500.5,"matchFormat":"standard","matchType":"singles","momentumEnabled":true,"pointCountInTiebreak":0,"recentPoints":["me","opponent"],"resumeEvents":[{"id":"00000000-0000-4000-8000-000000000131","pausedAt":784001700,"precedingPointID":"00000000-0000-4000-8000-000000000111","resumedAt":784001800}],"setElapsedSeconds":{"0":1500,"1":1400,"2":600.5},"setScores":[{"gamesMe":6,"gamesOpponent":4,"id":"00000000-0000-4000-8000-000000000101","isTieBreak":false,"tieBreakPointsMe":0,"tieBreakPointsOpponent":0},{"gamesMe":3,"gamesOpponent":6,"id":"00000000-0000-4000-8000-000000000102","isTieBreak":false,"tieBreakPointsMe":0,"tieBreakPointsOpponent":0},{"gamesMe":0,"gamesOpponent":0,"id":"00000000-0000-4000-8000-000000000103","isTieBreak":true,"tieBreakPointsMe":10,"tieBreakPointsOpponent":8}],"startTime":784000000,"stats":[{"endingShot":"return","gameScoreAtStart":{"isTiebreak":false,"returner":0,"server":0},"heartRateBPM":141,"id":"00000000-0000-4000-8000-000000000111","isBreakPoint":false,"isSecondServe":false,"outcome":"winner","server":"me","setIndex":0,"stepsCumulative":35,"timestamp":784000060,"winner":"me"},{"endingShot":"serve","gameScoreAtStart":{"isTiebreak":false,"returner":0,"server":1},"heartRateBPM":148,"id":"00000000-0000-4000-8000-000000000112","isBreakPoint":false,"isSecondServe":true,"outcome":"doubleFault","server":"me","setIndex":0,"stepsCumulative":61,"timestamp":784000120,"winner":"opponent"}],"tags":{"competitionTypeRaw":"league","opponents":[{"backhandRaw":"oneHanded","handednessRaw":"leftHanded","id":"00000000-0000-4000-8000-000000000901","name":"Sam Sample","playStyleRaw":"serveAndVolley","playingNotes":"Fictional: big first serve."}],"revisionID":"00000000-0000-4000-8000-000000000121","updatedAt":784004000},"tiebreakStartDoublesIndex":0,"totalCaloriesKcal":512.75,"totalDistanceMeters":2875.25,"totalSteps":4321},
{"checkpointRevision":0,"currentPointsMe":0,"currentPointsOpponent":0,"doublesServiceIndex":0,"doublesServiceOrder":[],"endTime":784090000,"gameCount":0,"iWon":false,"id":"00000000-0000-4000-8000-000000000002","isOnSecondServe":false,"matchElapsedSeconds":0,"matchFormat":"bestOf3FullFinalSet","matchType":"singles","matchTypeRevision":{"matchType":"singles","revisionID":"00000000-0000-4000-8000-000000000221","updatedAt":784091000},"momentumEnabled":true,"pointCountInTiebreak":0,"recentPoints":[],"resumeEvents":[],"setElapsedSeconds":{},"setScores":[{"gamesMe":4,"gamesOpponent":6,"id":"00000000-0000-4000-8000-000000000201","isTieBreak":false,"tieBreakPointsMe":0,"tieBreakPointsOpponent":0},{"gamesMe":5,"gamesOpponent":7,"id":"00000000-0000-4000-8000-000000000202","isTieBreak":false,"tieBreakPointsMe":0,"tieBreakPointsOpponent":0}],"startTime":784086400,"stats":[{"endingShot":"servePlusOne","gameScoreAtStart":{"isTiebreak":false,"returner":3,"server":2},"id":"00000000-0000-4000-8000-000000000211","isBreakPoint":true,"isSecondServe":false,"outcome":"forcedError","server":"opponent","setIndex":0,"timestamp":784086500,"winner":"me"}],"tiebreakStartDoublesIndex":0},
{"checkpointRevision":0,"currentPointsMe":0,"currentPointsOpponent":0,"doublesServiceIndex":0,"doublesServiceOrder":[],"endTime":784173700,"gameCount":0,"iWon":false,"id":"00000000-0000-4000-8000-000000000003","isOnSecondServe":false,"lastTiebreakPointServer":"opponent","matchElapsedSeconds":0,"matchFormat":"superTiebreak","matchType":"singles","momentumEnabled":true,"pointCountInTiebreak":18,"recentPoints":[],"resumeEvents":[],"setElapsedSeconds":{},"setScores":[{"gamesMe":0,"gamesOpponent":0,"id":"00000000-0000-4000-8000-000000000301","isTieBreak":true,"tieBreakPointsMe":8,"tieBreakPointsOpponent":10}],"startTime":784172800,"stats":[{"endingShot":"rally","gameScoreAtStart":{"isTiebreak":true,"returner":4,"server":4},"id":"00000000-0000-4000-8000-000000000311","isBreakPoint":false,"isSecondServe":false,"outcome":"unforcedError","server":"opponent","setIndex":0,"timestamp":784172900,"winner":"opponent"}],"tiebreakFirstPointReceiver":"me","tiebreakStartDoublesIndex":0,"tiebreakStartServer":"opponent"},
{"checkpointRevision":3,"currentPointsMe":3,"currentPointsOpponent":2,"currentServer":"opponent","doublesServer":"partner","doublesServiceIndex":2,"doublesServiceOrder":["me","opponentS1","partner","opponentS2"],"gameCount":0,"id":"00000000-0000-4000-8000-000000000004","isOnSecondServe":true,"matchElapsedSeconds":0,"matchFormat":"perpetualSuperTiebreak","matchType":"doubles","momentumEnabled":true,"parkedAt":784260000,"pointCountInTiebreak":0,"recentPoints":["me","me","opponent"],"resumeEvents":[],"setElapsedSeconds":{},"setScores":[{"gamesMe":0,"gamesOpponent":0,"id":"00000000-0000-4000-8000-000000000401","isTieBreak":true,"tieBreakPointsMe":3,"tieBreakPointsOpponent":2}],"startTime":784259200,"stats":[{"endingShot":"serve","gameScoreAtStart":{"isTiebreak":true,"returner":0,"server":0},"id":"00000000-0000-4000-8000-000000000411","isBreakPoint":false,"isSecondServe":false,"outcome":"winner","server":"me","setIndex":0,"timestamp":784259300,"winner":"me"}],"tags":{"competitionTypeRaw":"tournament","opponents":[{"id":"00000000-0000-4000-8000-000000000902","name":"Riley Example"},{"id":"00000000-0000-4000-8000-000000000903","name":"Jordan Placeholder"}],"partner":{"id":"00000000-0000-4000-8000-000000000904","name":"Casey Fixture"},"revisionID":"00000000-0000-4000-8000-000000000421","updatedAt":784259400},"tiebreakStartDoublesIndex":1},
{"checkpointRevision":0,"currentPointsMe":0,"currentPointsOpponent":0,"doublesServer":"me","doublesServiceIndex":0,"doublesServiceOrder":["me","opponentS1","partner","opponentS2"],"endTime":784346800,"gameCount":0,"iWon":true,"id":"00000000-0000-4000-8000-000000000005","isOnSecondServe":false,"matchElapsedSeconds":0,"matchFormat":"quick4Games","matchType":"doubles","momentumEnabled":true,"pointCountInTiebreak":0,"recentPoints":[],"resumeEvents":[],"setElapsedSeconds":{},"setScores":[{"gamesMe":3,"gamesOpponent":2,"id":"00000000-0000-4000-8000-000000000501","isTieBreak":false,"tieBreakPointsMe":0,"tieBreakPointsOpponent":0}],"startTime":784345600,"stats":[{"id":"00000000-0000-4000-8000-000000000511","isBreakPoint":false,"isSecondServe":false,"outcome":"uncategorized","server":"opponent","setIndex":0,"timestamp":784345700,"winner":"me"}],"tiebreakStartDoublesIndex":0},
{"checkpointRevision":0,"currentPointsMe":0,"currentPointsOpponent":0,"doublesServer":"opponentS1","doublesServiceIndex":1,"doublesServiceOrder":["opponentS1","me","opponentS2","partner"],"endTime":784434000,"gameCount":0,"iWon":true,"id":"00000000-0000-4000-8000-000000000006","isOnSecondServe":false,"matchElapsedSeconds":0,"matchFormat":"shortSets","matchType":"doubles","momentumEnabled":true,"pointCountInTiebreak":0,"recentPoints":[],"resumeEvents":[],"setElapsedSeconds":{},"setScores":[{"gamesMe":5,"gamesOpponent":3,"id":"00000000-0000-4000-8000-000000000601","isTieBreak":false,"tieBreakPointsMe":0,"tieBreakPointsOpponent":0}],"startTime":784432000,"stats":[{"endingShot":"return","id":"00000000-0000-4000-8000-000000000611","isBreakPoint":false,"isSecondServe":false,"outcome":"forcedError","server":"opponent","setIndex":0,"timestamp":784432100,"winner":"opponent"}],"tiebreakStartDoublesIndex":0},
{"checkpointRevision":0,"currentPointsMe":0,"currentPointsOpponent":0,"doublesServer":"opponentS2","doublesServiceIndex":3,"doublesServiceOrder":["partner","opponentS2","me","opponentS1"],"endTime":784519600,"gameCount":0,"iWon":true,"id":"00000000-0000-4000-8000-000000000007","isOnSecondServe":false,"matchElapsedSeconds":0,"matchFormat":"fast4","matchType":"doubles","momentumEnabled":false,"pointCountInTiebreak":0,"recentPoints":[],"resumeEvents":[],"setElapsedSeconds":{},"setScores":[{"gamesMe":4,"gamesOpponent":1,"id":"00000000-0000-4000-8000-000000000701","isTieBreak":false,"tieBreakPointsMe":0,"tieBreakPointsOpponent":0}],"startTime":784518400,"stats":[{"endingShot":"servePlusOne","id":"00000000-0000-4000-8000-000000000711","isBreakPoint":false,"isSecondServe":false,"outcome":"unforcedError","server":"me","setIndex":0,"timestamp":784518500,"winner":"opponent"}],"tiebreakStartDoublesIndex":0},
{"checkpointRevision":21,"currentPointsMe":11,"currentPointsOpponent":9,"currentServer":"me","doublesServiceIndex":0,"doublesServiceOrder":[],"gameCount":0,"id":"00000000-0000-4000-8000-000000000008","isOnSecondServe":false,"matchElapsedSeconds":0,"matchFormat":"perpetualPoints","matchType":"singles","momentumEnabled":true,"pointCountInTiebreak":0,"recentPoints":[],"resumeEvents":[],"setElapsedSeconds":{},"setScores":[],"startTime":784604800,"stats":[{"id":"00000000-0000-4000-8000-000000000811","isBreakPoint":false,"isSecondServe":false,"outcome":"uncategorized","server":"me","setIndex":0,"timestamp":784604900,"winner":"opponent"}],"tiebreakStartDoublesIndex":0}
]
"""#

    /// The same records as a Settings › Backup & Transfer export, with a
    /// forgotten-player ledger. Also frozen.
    private static let goldenManualArchiveJSON = #"""
{"exportedAt":784700000,"forgottenPlayers":{"playerIDs":["00000000-0000-4000-8000-000000000999"],"schemaVersion":1},"format":"deucemate.matchArchive","includesHealthData":true,"schemaVersion":1,
"records":\#(goldenRecordsJSON)}
"""#

    private static let goldenTombstonesJSON = #"["00000000-0000-4000-8000-000000000998"]"#

    private static let goldenLedgerJSON = #"{"playerIDs":["00000000-0000-4000-8000-000000000999"],"schemaVersion":1}"#
}

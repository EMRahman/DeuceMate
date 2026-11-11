// GamePlanBuildTests.swift — the iPhone's Prepare Game Plan build: every
// part staged in the build's own generation, filenames without names, the
// file bytes equal to the previewed text, and cancellation before staging.
import Foundation
import Testing
import DeuceMateCore
@testable import DeuceMate

struct GamePlanBuildTests {
    private let opponentID = UUID()
    private let builtAt = Date(timeIntervalSince1970: 1_790_000_000)

    private func record(day: Int, points: Int = 60) -> MatchRecord {
        let start = Date(timeIntervalSince1970: 1_780_000_000 + Double(day) * 86_400)
        let stats = (0..<points).map { i in
            PointStat(timestamp: start.addingTimeInterval(Double(i) * 30), setIndex: 0,
                      server: i.isMultiple(of: 2) ? .me : .opponent,
                      winner: i % 3 == 0 ? .opponent : .me,
                      outcome: i % 5 == 0 ? .uncategorized : .winner,
                      endingShot: .rally,
                      gameScoreAtStart: GameScoreSnapshot(server: 0, returner: 0, isTiebreak: false),
                      heartRateBPM: 150, stepsCumulative: i * 10)
        }
        let tags = MatchTags(opponents: [TaggedPlayer(id: opponentID, name: "Jordan Secretname")],
                             competitionType: .league, updatedAt: start)
        return MatchRecord(startTime: start, endTime: start.addingTimeInterval(3_600),
                           setScores: [SetScore(gamesMe: 6, gamesOpponent: 3)], stats: stats, iWon: true,
                           totalSteps: 4_000, tags: tags)
    }

    private func inputs(_ records: [MatchRecord], delivery: GamePlanDelivery = .singleFile,
                        includeNames: Bool = false) -> GamePlanBuildInputs {
        let candidates = GamePlanEligibility.candidates(for: opponentID, in: records)
        let selection = GamePlanSelection(mode: .all)
        return GamePlanBuildInputs(
            opponentID: opponentID,
            opponent: PlayerRoster.entries(from: records).first { $0.id == opponentID },
            selected: selection.resolve(candidates),
            candidateCounts: candidates.counts,
            availableCount: selection.filtered(candidates).count,
            upcoming: GamePlanUpcomingMatch(competition: .league),
            notes: [:], includeNotes: false, omittedNoteMatchIDs: [],
            includeNames: includeNames, includePlayingNotes: false, detailMode: .full, delivery: delivery,
            selectionDescription: selection.manifestDescription(timeZone: .current)
        )
    }

    private func staging() -> (ExportStaging, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("game-plan-build-\(UUID().uuidString)", isDirectory: true)
        return (ExportStaging(rootURL: root), root)
    }

    @Test func stagesOneFileMatchingTheTextWithoutNamesInTheFilename() throws {
        let (staging, root) = staging()
        defer { try? FileManager.default.removeItem(at: root) }
        let generation = staging.beginGeneration()
        let output = try GamePlanBuild.run(inputs((0..<3).map { record(day: $0) }, includeNames: true),
                                           builtAt: builtAt, staging: staging, generation: generation)
        #expect(output.fileURLs.count == 1)
        let url = try #require(output.fileURLs.first)
        #expect(generation.contains(url))
        #expect(url.lastPathComponent.hasPrefix("deuce_mate_game_plan_"))
        #expect(!url.lastPathComponent.contains("Jordan"))
        let written = try String(contentsOf: url, encoding: .utf8)
        #expect(written == output.pack.parts[0].text)
        #expect(written.contains("\"Jordan Secretname\""), "names were opted in")
        #expect(!written.contains("bpm") && !written.contains("Total Steps"))
    }

    @Test func splitPacksStageEveryPartInOrder() throws {
        let (staging, root) = staging()
        defer { try? FileManager.default.removeItem(at: root) }
        let generation = staging.beginGeneration()
        let output = try GamePlanBuild.run(inputs((0..<8).map { record(day: $0, points: 200) },
                                                  delivery: .parts(targetTokens: 5_000)),
                                           builtAt: builtAt, staging: staging, generation: generation)
        #expect(output.pack.parts.count > 1)
        #expect(output.fileURLs.count == output.pack.parts.count)
        for (index, url) in output.fileURLs.enumerated() {
            #expect(url.lastPathComponent.hasSuffix("_part\(index + 1)of\(output.pack.parts.count).txt"))
            #expect(try String(contentsOf: url, encoding: .utf8) == output.pack.parts[index].text)
        }
    }

    @Test func aCancelledBuildStagesNothing() async throws {
        let (staging, root) = staging()
        defer { try? FileManager.default.removeItem(at: root) }
        let generation = staging.beginGeneration()
        let built = inputs((0..<3).map { record(day: $0) })
        let task = Task.detached { () throws -> GamePlanBuildOutput in
            withUnsafeCurrentTask { $0?.cancel() }
            return try GamePlanBuild.run(built, staging: staging, generation: generation)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(!FileManager.default.fileExists(atPath: generation.directoryURL.path))
    }

    @Test func gamePlanFilenamesCarryOnlyTheBuildTime() {
        let single = ExportFilenames.gamePlan(builtAt: builtAt, part: 1, of: 1)
        let part = ExportFilenames.gamePlan(builtAt: builtAt, part: 2, of: 3)
        #expect(single.hasPrefix("deuce_mate_game_plan_") && single.hasSuffix(".txt"))
        #expect(!single.contains("part"))
        #expect(part.hasSuffix("_part2of3.txt"))
    }
}

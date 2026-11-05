// GamePlanBuild.swift — builds one Opponent Game Plan pack off the main
// actor and stages its file(s) in that build's own `ExportStaging`
// generation (docs/features/OPPONENT_GAME_PLAN_PROPOSAL.md §7).
//
// `GamePlanBuildInputs` is the build identity: every value the pack text
// depends on. `GamePlanView` restarts its build task whenever it changes, so
// an edit, a note change, a merge or a toggle can never leave an old pack or
// file on screen. The inputs carry already-resolved records and only the
// notes of SELECTED matches; the Core projection then applies the names /
// notes / Health boundary before any text exists.
import Foundation
import DeuceMateCore

nonisolated struct GamePlanBuildInputs: Equatable, Sendable {
    let opponentID: UUID
    /// Current roster entry (latest name and playing profile).
    let opponent: RosterEntry?
    /// The resolved selection, newest first.
    let selected: [MatchRecord]
    let candidateCounts: GamePlanCandidateCounts
    let availableCount: Int
    let upcoming: GamePlanUpcomingMatch
    /// Stored note text for the selected matches only.
    let notes: [UUID: String]
    let includeNotes: Bool
    let omittedNoteMatchIDs: Set<UUID>
    let includeNames: Bool
    let detailMode: GamePlanDetailMode
    let delivery: GamePlanDelivery
    let selectionDescription: String
}

nonisolated struct GamePlanBuildOutput: Sendable {
    let evidence: GamePlanEvidence
    let pack: GamePlanPack
    /// One staged file per part, in part order.
    let fileURLs: [URL]
}

nonisolated enum GamePlanBuild {

    /// Builds the projection and pack, then writes every part into
    /// `generation`. Throws `CancellationError` as soon as the calling task
    /// is cancelled, so a superseded build never stages or publishes.
    static func run(
        _ inputs: GamePlanBuildInputs,
        builtAt: Date = Date(),
        timeZone: TimeZone = .current,
        staging: ExportStaging,
        generation: ExportStaging.Generation,
        progress: (@Sendable (Double) -> Void)? = nil
    ) throws -> GamePlanBuildOutput {
        let evidence = try GamePlanEvidence(
            opponentID: inputs.opponentID,
            opponent: inputs.opponent,
            selected: inputs.selected,
            candidateCounts: inputs.candidateCounts,
            availableCount: inputs.availableCount,
            upcoming: inputs.upcoming,
            notes: inputs.notes,
            includeNotes: inputs.includeNotes,
            omittedNoteMatchIDs: inputs.omittedNoteMatchIDs,
            includeNames: inputs.includeNames,
            detailMode: inputs.detailMode,
            builtAt: builtAt,
            progress: { done, total in progress?(total == 0 ? 0.8 : 0.8 * Double(done) / Double(total)) }
        )
        let pack = try GamePlanPackBuilder.build(evidence, selectionLabel: inputs.selectionDescription,
                                                 delivery: inputs.delivery, timeZone: timeZone)
        progress?(0.9)
        var urls: [URL] = []
        for part in pack.parts {
            try Task.checkCancellation()
            let name = ExportFilenames.gamePlan(builtAt: builtAt, part: part.number, of: part.total)
            urls.append(try staging.write(Data(part.text.utf8), named: name, in: generation))
        }
        progress?(1)
        return GamePlanBuildOutput(evidence: evidence, pack: pack, fileURLs: urls)
    }
}

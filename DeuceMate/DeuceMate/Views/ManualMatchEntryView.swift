// ManualMatchEntryView.swift — manually reconstruct a best-of-3 match from a
// screenshot when live scoring was lost. Saves an in-progress MatchRecord into
// the phone archive and pushes it to the watch so play can be resumed there.
import SwiftUI
import DeuceMateCore

struct ManualMatchEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: PhoneStatsStore
    @EnvironmentObject private var syncService: PhoneMatchSyncService

    // MARK: - Inputs

    @State private var matchFormat: MatchFormat = .standard
    @State private var matchType: MatchType = .singles
    @State private var startDate: Date = Date()

    /// Number of fully completed sets entered (0…2).
    @State private var completedSetCount: Int = 0

    // Set 1 (regular)
    @State private var set1GamesMe: Int = 0
    @State private var set1GamesOpp: Int = 0
    @State private var set1TBMe: Int = 0
    @State private var set1TBOpp: Int = 0

    // Set 2 (regular)
    @State private var set2GamesMe: Int = 0
    @State private var set2GamesOpp: Int = 0
    @State private var set2TBMe: Int = 0
    @State private var set2TBOpp: Int = 0

    // Current set (last, in-progress)
    @State private var currentGamesMe: Int = 0
    @State private var currentGamesOpp: Int = 0
    /// Currently in a regular-set tiebreak (6-6 reached)? Only relevant when the
    /// current set is a regular set.
    @State private var currentSetIsTiebreak: Bool = false
    @State private var currentTBMe: Int = 0
    @State private var currentTBOpp: Int = 0

    // Current game (only when current set is a regular set, not yet in tiebreak)
    /// 0 = love, 1 = 15, 2 = 30, 3 = 40, 4 = advantage.
    @State private var currentPointsMe: Int = 0
    @State private var currentPointsOpponent: Int = 0
    @State private var currentServer: Player = .me
    @State private var doublesServer: DoublesServer = .me
    @State private var isOnSecondServe: Bool = false

    private var currentSetIndex: Int { completedSetCount }
    private var isDecidingSet: Bool { currentSetIndex == 2 }
    /// True when the deciding set should be played as a pure 10-pt super-tiebreak.
    private var currentSetIsPureTiebreak: Bool {
        isDecidingSet && matchFormat.config.finalSetStyle == .superTiebreak
    }

    private static let pointLabels = ["0", "15", "30", "40", "AD"]

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                Section("Match") {
                    Picker("Format", selection: $matchFormat) {
                        Text("Best of 3 (Super TB Decider)").tag(MatchFormat.standard)
                        Text("Best of 3 (Full Final Set)").tag(MatchFormat.bestOf3FullFinalSet)
                    }
                    Picker("Type", selection: $matchType) {
                        Text("Singles").tag(MatchType.singles)
                        Text("Doubles").tag(MatchType.doubles)
                    }
                    DatePicker("Started", selection: $startDate, displayedComponents: [.date, .hourAndMinute])
                }

                Section {
                    Stepper(value: $completedSetCount, in: 0...2) {
                        Text("Completed sets: \(completedSetCount)")
                    }
                } footer: {
                    Text("How many sets are finished. The next set is the one currently in play.")
                }

                if completedSetCount >= 1 {
                    completedSetSection(
                        title: "Set 1 (final)",
                        gamesMe: $set1GamesMe, gamesOpp: $set1GamesOpp,
                        tbMe: $set1TBMe, tbOpp: $set1TBOpp
                    )
                }
                if completedSetCount >= 2 {
                    completedSetSection(
                        title: "Set 2 (final)",
                        gamesMe: $set2GamesMe, gamesOpp: $set2GamesOpp,
                        tbMe: $set2TBMe, tbOpp: $set2TBOpp
                    )
                }

                currentSetSection

                if !currentSetIsPureTiebreak && !currentSetIsTiebreak {
                    currentGameSection
                }

                Section {
                    Button("Save Match") { save() }
                        .disabled(!isValid)
                        .frame(maxWidth: .infinity, alignment: .center)
                } footer: {
                    Text("The match will be added as in-progress and pushed to your Apple Watch so you can resume scoring there.")
                }
            }
            .onChange(of: currentGamesMe) { _, _ in resetTiebreakIfLeftSixAll() }
            .onChange(of: currentGamesOpp) { _, _ in resetTiebreakIfLeftSixAll() }
            .navigationTitle("Manual Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func completedSetSection(
        title: String,
        gamesMe: Binding<Int>, gamesOpp: Binding<Int>,
        tbMe: Binding<Int>, tbOpp: Binding<Int>
    ) -> some View {
        Section(title) {
            Stepper(value: gamesMe, in: 0...7) {
                HStack { Text("Me"); Spacer(); Text("\(gamesMe.wrappedValue)").monospacedDigit() }
            }
            Stepper(value: gamesOpp, in: 0...7) {
                HStack { Text("Opponent"); Spacer(); Text("\(gamesOpp.wrappedValue)").monospacedDigit() }
            }
            if gamesMe.wrappedValue == 7 && gamesOpp.wrappedValue == 6 ||
               gamesMe.wrappedValue == 6 && gamesOpp.wrappedValue == 7 {
                Stepper(value: tbMe, in: 0...30) {
                    HStack { Text("Tiebreak — Me"); Spacer(); Text("\(tbMe.wrappedValue)").monospacedDigit() }
                }
                Stepper(value: tbOpp, in: 0...30) {
                    HStack { Text("Tiebreak — Opp"); Spacer(); Text("\(tbOpp.wrappedValue)").monospacedDigit() }
                }
            }
        }
    }

    @ViewBuilder
    private var currentSetSection: some View {
        let header = "Current Set (Set \(currentSetIndex + 1) — in progress)"
        Section(header) {
            if currentSetIsPureTiebreak {
                Stepper(value: $currentTBMe, in: 0...30) {
                    HStack { Text("Super TB — Me"); Spacer(); Text("\(currentTBMe)").monospacedDigit() }
                }
                Stepper(value: $currentTBOpp, in: 0...30) {
                    HStack { Text("Super TB — Opp"); Spacer(); Text("\(currentTBOpp)").monospacedDigit() }
                }
                serverPickers
            } else {
                Stepper(value: $currentGamesMe, in: 0...6) {
                    HStack { Text("Games — Me"); Spacer(); Text("\(currentGamesMe)").monospacedDigit() }
                }
                Stepper(value: $currentGamesOpp, in: 0...6) {
                    HStack { Text("Games — Opp"); Spacer(); Text("\(currentGamesOpp)").monospacedDigit() }
                }
                if currentGamesMe == 6 && currentGamesOpp == 6 {
                    Toggle("In set tiebreak", isOn: $currentSetIsTiebreak)
                    if currentSetIsTiebreak {
                        Stepper(value: $currentTBMe, in: 0...30) {
                            HStack { Text("TB — Me"); Spacer(); Text("\(currentTBMe)").monospacedDigit() }
                        }
                        Stepper(value: $currentTBOpp, in: 0...30) {
                            HStack { Text("TB — Opp"); Spacer(); Text("\(currentTBOpp)").monospacedDigit() }
                        }
                        serverPickers
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var currentGameSection: some View {
        Section("Current Game") {
            serverPickers
            Picker("Me points", selection: $currentPointsMe) {
                ForEach(0..<Self.pointLabels.count, id: \.self) { i in
                    Text(Self.pointLabels[i]).tag(i)
                }
            }
            Picker("Opp points", selection: $currentPointsOpponent) {
                ForEach(0..<Self.pointLabels.count, id: \.self) { i in
                    Text(Self.pointLabels[i]).tag(i)
                }
            }
            Toggle("Second serve", isOn: $isOnSecondServe)
        }
    }

    @ViewBuilder
    private var serverPickers: some View {
        Picker("Server", selection: $currentServer) {
            Text("Me").tag(Player.me)
            Text("Opponent").tag(Player.opponent)
        }
        if matchType == .doubles {
            Picker("Serving player", selection: $doublesServer) {
                ForEach(DoublesServer.allCases, id: \.self) { ds in
                    Text(ds.displayName).tag(ds)
                }
            }
            .onChange(of: doublesServer) { _, newValue in
                currentServer = newValue.team
            }
        }
    }

    // MARK: - Validation

    private var isValid: Bool {
        // Game scores can't both be a regular advantage simultaneously.
        if currentPointsMe == 4 && currentPointsOpponent == 4 { return false }
        if currentPointsMe == 4 && currentPointsOpponent < 3 { return false }
        if currentPointsOpponent == 4 && currentPointsMe < 3 { return false }
        if !isCompletedSetValid(gamesMe: set1GamesMe, gamesOpp: set1GamesOpp,
                                tbMe: set1TBMe, tbOpp: set1TBOpp, enabled: completedSetCount >= 1) {
            return false
        }
        if !isCompletedSetValid(gamesMe: set2GamesMe, gamesOpp: set2GamesOpp,
                                tbMe: set2TBMe, tbOpp: set2TBOpp, enabled: completedSetCount >= 2) {
            return false
        }
        if currentSetIsPureTiebreak {
            // At least one point must be entered for a "current" tiebreak; if both
            // are zero it's effectively a brand-new match — still allowed.
            return true
        }
        // Regular current set: not allowed to already meet a "set complete" condition.
        let cfg = matchFormat.config
        if currentSetIsTiebreak {
            return true // tiebreak inputs can be any score the user typed
        }
        if cfg.isNormalSetComplete(gamesMe: currentGamesMe, gamesOpponent: currentGamesOpp) {
            return false
        }
        return true
    }

    private func isCompletedSetValid(gamesMe: Int, gamesOpp: Int, tbMe: Int, tbOpp: Int, enabled: Bool) -> Bool {
        guard enabled else { return true }
        let cfg = matchFormat.config
        guard cfg.isNormalSetComplete(gamesMe: gamesMe, gamesOpponent: gamesOpp) else { return false }
        if gamesMe + gamesOpp == 13 {
            // 7-6 / 6-7: at least one tiebreak point should be > 0
            return (tbMe + tbOpp) > 0
        }
        return true
    }

    // MARK: - Save

    private func save() {
        guard let record = buildRecord() else { return }
        store.appendMatch(record)
        syncService.sendManualMatch(record)
        dismiss()
    }

    private func buildRecord() -> MatchRecord? {
        var setScores: [SetScore] = []

        if completedSetCount >= 1 {
            setScores.append(makeCompletedSet(gamesMe: set1GamesMe, gamesOpp: set1GamesOpp,
                                              tbMe: set1TBMe, tbOpp: set1TBOpp))
        }
        if completedSetCount >= 2 {
            setScores.append(makeCompletedSet(gamesMe: set2GamesMe, gamesOpp: set2GamesOpp,
                                              tbMe: set2TBMe, tbOpp: set2TBOpp))
        }

        // Current (in-progress) set
        let currentSet: SetScore
        if currentSetIsPureTiebreak {
            currentSet = SetScore(
                gamesMe: 0, gamesOpponent: 0,
                isTieBreak: true,
                tieBreakPointsMe: currentTBMe,
                tieBreakPointsOpponent: currentTBOpp
            )
        } else if currentSetIsTiebreak {
            currentSet = SetScore(
                gamesMe: 6, gamesOpponent: 6,
                isTieBreak: true,
                tieBreakPointsMe: currentTBMe,
                tieBreakPointsOpponent: currentTBOpp
            )
        } else {
            currentSet = SetScore(
                gamesMe: currentGamesMe,
                gamesOpponent: currentGamesOpp,
                isTieBreak: false
            )
        }
        setScores.append(currentSet)

        let totalGames = setScores.reduce(0) { $0 + $1.gamesMe + $1.gamesOpponent }

        let pointsMe: Int
        let pointsOpp: Int
        if currentSet.isTieBreak {
            // Not used by the watch's game-point logic in tiebreak mode; the
            // tiebreak score lives on SetScore. Keep these at zero so the
            // resume flow doesn't confuse them with normal game points.
            pointsMe = 0
            pointsOpp = 0
        } else {
            pointsMe = currentPointsMe
            pointsOpp = currentPointsOpponent
        }

        let pointCountInTiebreak = currentSet.isTieBreak
            ? currentSet.tieBreakPointsMe + currentSet.tieBreakPointsOpponent
            : 0

        // The watch's tiebreak rotation derives every later server from
        // `tiebreakStartServer` + `pointCountInTiebreak`. The manual entry only
        // captures who's about to serve next, so back-derive the original opener
        // of the tiebreak from those two values.
        let tiebreakStartServer: Player? = currentSet.isTieBreak
            ? Self.derivedTiebreakStartServer(
                upcomingServer: currentServer,
                pointsAlreadyPlayed: pointCountInTiebreak
            )
            : nil
        let tiebreakFirstReceiver: Player? = tiebreakStartServer.map {
            $0 == .me ? .opponent : .me
        }

        let resolvedDoublesServer: DoublesServer? = matchType == .doubles ? doublesServer : nil
        // For doubles, build the full 4-player rotation starting at the chosen
        // server (alternating teams) so the watch advances through all four
        // players after each game instead of looping on a single-element order.
        let doublesOrder: [DoublesServer] = matchType == .doubles
            ? Self.doublesRotation(startingFrom: doublesServer)
            : []
        // If we're mid-tiebreak in doubles, anchor `tiebreakStartDoublesIndex`
        // so that the watch's `(start + offset) % 4` formula hits index 0
        // (where the chosen server sits) for the next point.
        let tbStartDoublesIndex: Int = (matchType == .doubles && currentSet.isTieBreak)
            ? Self.tiebreakStartDoublesIndex(forUpcomingPointsPlayed: pointCountInTiebreak,
                                             rotationCount: doublesOrder.count)
            : 0

        return MatchRecord(
            id: UUID(),
            startTime: startDate,
            endTime: nil,
            setScores: setScores,
            stats: [],
            iWon: nil,
            currentPointsMe: pointsMe,
            currentPointsOpponent: pointsOpp,
            currentServer: currentServer,
            gameCount: totalGames,
            pointCountInTiebreak: pointCountInTiebreak,
            tiebreakStartServer: tiebreakStartServer,
            tiebreakFirstPointReceiver: tiebreakFirstReceiver,
            lastTiebreakPointServer: nil,
            isOnSecondServe: currentSet.isTieBreak ? false : isOnSecondServe,
            matchType: matchType,
            matchFormat: matchFormat,
            doublesServer: resolvedDoublesServer,
            doublesServiceOrder: doublesOrder,
            doublesServiceIndex: 0,
            tiebreakStartDoublesIndex: tbStartDoublesIndex,
            matchElapsedSeconds: 0,
            setElapsedSeconds: [:],
            recentPoints: []
        )
    }

    /// Reverse-engineer the original tiebreak opener from the upcoming point's
    /// server and how many points have already been played. Mirrors the watch's
    /// rotation (point 1: start; pts 2–3: other; pts 4–5: start; pts 6–7: other; …).
    private static func derivedTiebreakStartServer(upcomingServer: Player,
                                                   pointsAlreadyPlayed: Int) -> Player {
        let nextPointNumber = pointsAlreadyPlayed + 1
        let nextIsStart: Bool
        if nextPointNumber == 1 {
            nextIsStart = true
        } else {
            let pairIndex = (nextPointNumber - 2) / 2
            nextIsStart = (pairIndex % 2 == 1)
        }
        if nextIsStart { return upcomingServer }
        return upcomingServer == .me ? .opponent : .me
    }

    /// Standard 4-player doubles rotation starting from `server`. The four
    /// positions alternate teams (server's team, opposing team, partner's team,
    /// other opposing player), matching the watch's startServeOrder layout.
    private static func doublesRotation(startingFrom server: DoublesServer) -> [DoublesServer] {
        switch server {
        case .me:         return [.me, .opponentS1, .partner, .opponentS2]
        case .partner:    return [.partner, .opponentS1, .me, .opponentS2]
        case .opponentS1: return [.opponentS1, .me, .opponentS2, .partner]
        case .opponentS2: return [.opponentS2, .me, .opponentS1, .partner]
        }
    }

    /// Pick `tiebreakStartDoublesIndex` so the watch's `(start + offset) % count`
    /// lookup lands on index 0 (the chosen server) for the next point.
    private static func tiebreakStartDoublesIndex(forUpcomingPointsPlayed pointsPlayed: Int,
                                                  rotationCount: Int) -> Int {
        guard rotationCount > 0 else { return 0 }
        let nextPointNumber = pointsPlayed + 1
        let offset = nextPointNumber == 1 ? 0 : ((nextPointNumber - 2) / 2 + 1)
        return (rotationCount - (offset % rotationCount)) % rotationCount
    }

    private func resetTiebreakIfLeftSixAll() {
        if !(currentGamesMe == 6 && currentGamesOpp == 6) {
            currentSetIsTiebreak = false
        }
    }

    private func makeCompletedSet(gamesMe: Int, gamesOpp: Int, tbMe: Int, tbOpp: Int) -> SetScore {
        let isTB = (gamesMe + gamesOpp) == 13
        return SetScore(
            gamesMe: gamesMe,
            gamesOpponent: gamesOpp,
            isTieBreak: isTB,
            tieBreakPointsMe: isTB ? tbMe : 0,
            tieBreakPointsOpponent: isTB ? tbOpp : 0
        )
    }
}

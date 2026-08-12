//
//  MatchSetupDefaultsWatchTests.swift
//  DeuceMate Watch AppTests
//
//  The remembered-match-setup hydration paths (docs/features/MATCH_START_UX_PLAN.md
//  §5.4): loadState() must hydrate matchFormat/matchType from the remembered pair
//  on every idle exit (success-with-idle-state and the catch path alike) and must
//  never touch a genuinely restored live match; resetMatch() must persist the
//  remembered pair — not the hard-coded .singles/.standard fallback — into the
//  saved AppState.
//

import Foundation
import DeuceMateCore
import Testing
@testable import DeuceMate_Watch_App

/// Serialized: these tests read/write real `UserDefaults.standard` keys
/// (`MatchSetupDefaults.formatKey`/`.typeKey`), so running them concurrently
/// would race on shared global state.
@Suite(.serialized)
struct MatchSetupDefaultsWatchTests {

    // MARK: - Helpers

    private func makeTempURL(_ prefix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString).json")
    }

    /// Sets the remembered-setup UserDefaults pair for the duration of `body`,
    /// then restores whatever was there before — these are real
    /// `UserDefaults.standard` keys, so tests must not leak values into each
    /// other (or a real device).
    private func withRememberedSetup(
        format: MatchFormat,
        type: MatchType,
        _ body: () throws -> Void
    ) rethrows {
        try withRestoredUserDefaults {
            UserDefaults.standard.set(format.rawValue, forKey: MatchSetupDefaults.formatKey)
            UserDefaults.standard.set(type.rawValue, forKey: MatchSetupDefaults.typeKey)
            try body()
        }
    }

    private func withNoRememberedSetup(_ body: () throws -> Void) rethrows {
        try withRestoredUserDefaults {
            UserDefaults.standard.removeObject(forKey: MatchSetupDefaults.formatKey)
            UserDefaults.standard.removeObject(forKey: MatchSetupDefaults.typeKey)
            try body()
        }
    }

    private func withRestoredUserDefaults(_ body: () throws -> Void) rethrows {
        let defaults = UserDefaults.standard
        let originalFormat = defaults.string(forKey: MatchSetupDefaults.formatKey)
        let originalType = defaults.string(forKey: MatchSetupDefaults.typeKey)
        defer {
            if let originalFormat {
                defaults.set(originalFormat, forKey: MatchSetupDefaults.formatKey)
            } else {
                defaults.removeObject(forKey: MatchSetupDefaults.formatKey)
            }
            if let originalType {
                defaults.set(originalType, forKey: MatchSetupDefaults.typeKey)
            } else {
                defaults.removeObject(forKey: MatchSetupDefaults.typeKey)
            }
        }
        try body()
    }

    private func makeViewModel(stateURL: URL) -> ScoreViewModel {
        ScoreViewModel(statsStore: StatsStore(fileURL: makeTempURL("matchsetup-store")), stateFileURL: stateURL)
    }

    private func writeAppState(_ state: ScoreViewModel.AppState, to url: URL) throws {
        try JSONEncoder().encode(state).write(to: url)
    }

    private func idleAppState(matchFormat: MatchFormat, matchType: MatchType) -> ScoreViewModel.AppState {
        ScoreViewModel.AppState(
            version: 5,
            sets: [SetScore()],
            currentPointsMe: 0,
            currentPointsOpponent: 0,
            history: [],
            currentServer: nil,
            gameCount: 0,
            pointCountInTiebreak: 0,
            tiebreakStartServer: nil,
            tiebreakFirstPointReceiver: nil,
            lastTiebreakPointServer: nil,
            matchType: matchType,
            matchFormat: matchFormat
        )
    }

    private func liveAppState(matchFormat: MatchFormat, matchType: MatchType) -> ScoreViewModel.AppState {
        ScoreViewModel.AppState(
            version: 5,
            sets: [SetScore(gamesMe: 2, gamesOpponent: 1)],
            currentPointsMe: 1,
            currentPointsOpponent: 0,
            history: [],
            currentServer: .me,
            gameCount: 3,
            pointCountInTiebreak: 0,
            tiebreakStartServer: nil,
            tiebreakFirstPointReceiver: nil,
            lastTiebreakPointServer: nil,
            matchStartTime: Date(),
            currentMatchID: UUID(),
            matchType: matchType,
            matchFormat: matchFormat
        )
    }

    // MARK: - loadState() hydration

    @Test func loadState_absentFile_hydratesFromRememberedDefaults() throws {
        try withRememberedSetup(format: .quick4Games, type: .doubles) {
            // Deliberately does not exist on disk — exercises the catch path.
            let viewModel = makeViewModel(stateURL: makeTempURL("loadstate-absent"))
            viewModel.loadState()
            #expect(viewModel.matchFormat == .quick4Games)
            #expect(viewModel.matchType == .doubles)
        }
    }

    @Test func loadState_corruptFile_hydratesFromRememberedDefaults() throws {
        try withRememberedSetup(format: .superTiebreak, type: .doubles) {
            let url = makeTempURL("loadstate-corrupt")
            defer { try? FileManager.default.removeItem(at: url) }
            try Data("not valid json {{{".utf8).write(to: url)

            let viewModel = makeViewModel(stateURL: url)
            viewModel.loadState()
            #expect(viewModel.matchFormat == .superTiebreak)
            #expect(viewModel.matchType == .doubles)
        }
    }

    @Test func loadState_idleSavedState_hydratesFromRememberedDefaults() throws {
        try withRememberedSetup(format: .perpetualPoints, type: .singles) {
            let url = makeTempURL("loadstate-idle")
            defer { try? FileManager.default.removeItem(at: url) }
            // The saved state itself carries a different (stale) pair — the point
            // of this test is that an idle restore defers to the remembered pair.
            try writeAppState(idleAppState(matchFormat: .standard, matchType: .doubles), to: url)

            let viewModel = makeViewModel(stateURL: url)
            viewModel.loadState()
            #expect(viewModel.matchFormat == .perpetualPoints)
            #expect(viewModel.matchType == .singles)
        }
    }

    @Test func loadState_liveMatchRestored_isNotOverwritten() throws {
        try withRememberedSetup(format: .standard, type: .singles) {
            let url = makeTempURL("loadstate-live")
            defer { try? FileManager.default.removeItem(at: url) }
            // A genuinely in-progress match (currentServer set) using a format
            // that differs from the remembered pair.
            try writeAppState(liveAppState(matchFormat: .quick4Games, matchType: .doubles), to: url)

            let viewModel = makeViewModel(stateURL: url)
            viewModel.loadState()
            #expect(viewModel.currentServer == .me)
            #expect(viewModel.matchFormat == .quick4Games, "a restored live match must not be rewritten to the remembered pair")
            #expect(viewModel.matchType == .doubles)
        }
    }

    // MARK: - resetMatch() persistence

    @Test func resetMatch_persistsRememberedPair_notHardFallback() throws {
        try withRememberedSetup(format: .quick4Games, type: .doubles) {
            let url = makeTempURL("resetmatch")
            defer { try? FileManager.default.removeItem(at: url) }
            let viewModel = makeViewModel(stateURL: url)
            viewModel.currentServer = .me
            viewModel.matchStartTime = Date()

            viewModel.resetMatch()

            #expect(viewModel.matchFormat == .quick4Games, "resetMatch() must reseed from the remembered pair, not hard-code .standard")
            #expect(viewModel.matchType == .doubles, "resetMatch() must reseed from the remembered pair, not hard-code .singles")

            // The persisted AppState (written by resetMatch()'s own saveState())
            // must carry the remembered pair forward too, not the fallback —
            // otherwise the next launch's loadState() success path would restore
            // .standard/.singles regardless of what's remembered.
            let saved = try JSONDecoder().decode(
                ScoreViewModel.AppState.self,
                from: Data(contentsOf: url)
            )
            #expect(saved.matchFormat == .quick4Games)
            #expect(saved.matchType == .doubles)
        }
    }

    // MARK: - persistMatchSetupDefaults()

    @Test func persistMatchSetupDefaults_writesCurrentViewModelState() throws {
        try withNoRememberedSetup {
            let viewModel = makeViewModel(stateURL: makeTempURL("persist"))
            viewModel.matchFormat = .perpetualSuperTiebreak
            viewModel.matchType = .doubles

            viewModel.persistMatchSetupDefaults()

            let resolved = MatchSetupDefaults.resolve(
                formatRaw: UserDefaults.standard.string(forKey: MatchSetupDefaults.formatKey),
                typeRaw: UserDefaults.standard.string(forKey: MatchSetupDefaults.typeKey))
            #expect(resolved.format == .perpetualSuperTiebreak)
            #expect(resolved.type == .doubles)
        }
    }

    // MARK: - init() never hydrates

    /// Regression guard for the §5.4 warning: `init` runs before either restore
    /// path, so hydrating there would just be silently discarded. If a future
    /// edit adds hydration to `init`, this fails.
    @Test func init_neverHydratesFromRememberedDefaults() throws {
        try withRememberedSetup(format: .quick4Games, type: .doubles) {
            let viewModel = ScoreViewModel(statsStore: StatsStore(fileURL: makeTempURL("init-store")))
            #expect(viewModel.matchFormat == .standard)
            #expect(viewModel.matchType == .singles)
        }
    }
}

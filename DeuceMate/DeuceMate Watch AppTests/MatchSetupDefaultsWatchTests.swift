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
//  Each test gets its own throwaway UserDefaults(suiteName:) domain via
//  ScoreViewModel's injectable `userDefaults` initializer parameter, rather than
//  mutating the real UserDefaults.standard. Swift Testing runs different suites
//  concurrently by default, and DeuceMate_Watch_AppTests has its own tests that
//  call resetMatch() — which now reads these same keys — so sharing
//  UserDefaults.standard would race against a suite this file has no control
//  over (a real Codex review finding on this feature's first PR).
//

import Foundation
import DeuceMateCore
import Testing
@testable import DeuceMate_Watch_App

struct MatchSetupDefaultsWatchTests {

    // MARK: - Helpers

    private func makeTempURL(_ prefix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString).json")
    }

    /// A private, uniquely-named UserDefaults domain, torn down via
    /// `teardown(_:)` when the test ends — never the shared `.standard`
    /// domain other tests/the app read.
    private func makeIsolatedDefaults() -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "matchsetup-defaults-test-\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }

    private func teardown(_ suiteName: String) {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    private func makeViewModel(stateURL: URL, defaults: UserDefaults) -> ScoreViewModel {
        ScoreViewModel(
            statsStore: StatsStore(fileURL: makeTempURL("matchsetup-store")),
            stateFileURL: stateURL,
            userDefaults: defaults
        )
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
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { teardown(suiteName) }
        defaults.set(MatchFormat.quick4Games.rawValue, forKey: MatchSetupDefaults.formatKey)
        defaults.set(MatchType.doubles.rawValue, forKey: MatchSetupDefaults.typeKey)

        // Deliberately does not exist on disk — exercises the catch path.
        let viewModel = makeViewModel(stateURL: makeTempURL("loadstate-absent"), defaults: defaults)
        viewModel.loadState()
        #expect(viewModel.matchFormat == .quick4Games)
        #expect(viewModel.matchType == .doubles)
    }

    @Test func loadState_corruptFile_hydratesFromRememberedDefaults() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { teardown(suiteName) }
        defaults.set(MatchFormat.superTiebreak.rawValue, forKey: MatchSetupDefaults.formatKey)
        defaults.set(MatchType.doubles.rawValue, forKey: MatchSetupDefaults.typeKey)

        let url = makeTempURL("loadstate-corrupt")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not valid json {{{".utf8).write(to: url)

        let viewModel = makeViewModel(stateURL: url, defaults: defaults)
        viewModel.loadState()
        #expect(viewModel.matchFormat == .superTiebreak)
        #expect(viewModel.matchType == .doubles)
    }

    @Test func loadState_idleSavedState_hydratesFromRememberedDefaults() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { teardown(suiteName) }
        defaults.set(MatchFormat.perpetualPoints.rawValue, forKey: MatchSetupDefaults.formatKey)
        defaults.set(MatchType.singles.rawValue, forKey: MatchSetupDefaults.typeKey)

        let url = makeTempURL("loadstate-idle")
        defer { try? FileManager.default.removeItem(at: url) }
        // The saved state itself carries a different (stale) pair — the point
        // of this test is that an idle restore defers to the remembered pair.
        try writeAppState(idleAppState(matchFormat: .standard, matchType: .doubles), to: url)

        let viewModel = makeViewModel(stateURL: url, defaults: defaults)
        viewModel.loadState()
        #expect(viewModel.matchFormat == .perpetualPoints)
        #expect(viewModel.matchType == .singles)
    }

    @Test func loadState_liveMatchRestored_isNotOverwritten() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { teardown(suiteName) }
        defaults.set(MatchFormat.standard.rawValue, forKey: MatchSetupDefaults.formatKey)
        defaults.set(MatchType.singles.rawValue, forKey: MatchSetupDefaults.typeKey)

        let url = makeTempURL("loadstate-live")
        defer { try? FileManager.default.removeItem(at: url) }
        // A genuinely in-progress match (currentServer set) using a format
        // that differs from the remembered pair.
        try writeAppState(liveAppState(matchFormat: .quick4Games, matchType: .doubles), to: url)

        let viewModel = makeViewModel(stateURL: url, defaults: defaults)
        viewModel.loadState()
        #expect(viewModel.currentServer == .me)
        #expect(viewModel.matchFormat == .quick4Games, "a restored live match must not be rewritten to the remembered pair")
        #expect(viewModel.matchType == .doubles)
    }

    // MARK: - resetMatch() persistence

    @Test func resetMatch_persistsRememberedPair_notHardFallback() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { teardown(suiteName) }
        defaults.set(MatchFormat.quick4Games.rawValue, forKey: MatchSetupDefaults.formatKey)
        defaults.set(MatchType.doubles.rawValue, forKey: MatchSetupDefaults.typeKey)

        let url = makeTempURL("resetmatch")
        defer { try? FileManager.default.removeItem(at: url) }
        let viewModel = makeViewModel(stateURL: url, defaults: defaults)
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

    // MARK: - persistMatchSetupDefaults()

    @Test func persistMatchSetupDefaults_writesCurrentViewModelState() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { teardown(suiteName) }

        let viewModel = makeViewModel(stateURL: makeTempURL("persist"), defaults: defaults)
        viewModel.matchFormat = .perpetualSuperTiebreak
        viewModel.matchType = .doubles

        viewModel.persistMatchSetupDefaults()

        let resolved = MatchSetupDefaults.resolve(
            formatRaw: defaults.string(forKey: MatchSetupDefaults.formatKey),
            typeRaw: defaults.string(forKey: MatchSetupDefaults.typeKey))
        #expect(resolved.format == .perpetualSuperTiebreak)
        #expect(resolved.type == .doubles)
    }

    // MARK: - init() never hydrates

    /// Regression guard for the §5.4 warning: `init` runs before either restore
    /// path, so hydrating there would just be silently discarded. If a future
    /// edit adds hydration to `init`, this fails.
    @Test func init_neverHydratesFromRememberedDefaults() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { teardown(suiteName) }
        defaults.set(MatchFormat.quick4Games.rawValue, forKey: MatchSetupDefaults.formatKey)
        defaults.set(MatchType.doubles.rawValue, forKey: MatchSetupDefaults.typeKey)

        let viewModel = ScoreViewModel(
            statsStore: StatsStore(fileURL: makeTempURL("init-store")),
            userDefaults: defaults
        )
        #expect(viewModel.matchFormat == .standard)
        #expect(viewModel.matchType == .singles)
    }
}

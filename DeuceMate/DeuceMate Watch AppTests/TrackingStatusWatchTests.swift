//
//  TrackingStatusWatchTests.swift
//  DeuceMate Watch AppTests
//
//  Two things the Core-level MatchTrackingStatusTests can't see: that
//  ScoreViewModel.trackingStatuses actually wires the live matchFormat/
//  settings/workoutManager.healthAccess into MatchTrackingStatus.all(...), and
//  that WorkoutManager's changes reach views observing only the view model
//  (the prior-art bug this feature's plan called out by name — a strip that
//  takes `@ObservedObject var workoutManager` and never reads it looks
//  load-bearing but silently never redraws without this forward).
//

import Combine
import Foundation
import DeuceMateCore
import Testing
@testable import DeuceMate_Watch_App

struct TrackingStatusWatchTests {

    private func makeTempURL(_ prefix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString).json")
    }

    private func makeViewModel() -> ScoreViewModel {
        ScoreViewModel(statsStore: StatsStore(fileURL: makeTempURL("trackingstatus-store")))
    }

    @Test func trackingStatuses_wiresLiveFormatAndSettings() throws {
        let viewModel = makeViewModel()
        viewModel.matchFormat = .perpetualPoints
        viewModel.statsTrackingEnabled = true

        let statuses = viewModel.trackingStatuses

        #expect(statuses.count == 3)
        #expect(statuses[0].facet == .pointTracking)
        // Perpetual Points suppresses point tracking regardless of the toggle
        // (§3.3's hard coupling) — this only holds if trackingStatuses actually
        // passes the live matchFormat through to MatchTrackingStatus.all(...).
        #expect(statuses[0].stateLabel == "—")
    }

    @Test func trackingStatuses_reflectsWorkoutManagerHealthAccess() throws {
        let viewModel = makeViewModel()
        // requestAuthorization/refreshHealthAccess touch real HealthKit state,
        // which is environment-dependent — assert against the property directly
        // instead, matching whatever this simulator's HealthKit reports.
        let expectedAccess = viewModel.workoutManager.healthAccess
        let healthStatus = viewModel.trackingStatuses.first { $0.facet == .healthTracking }
        let expectedReadiness: TrackingReadiness = {
            switch expectedAccess {
            case .authorized: return .on
            case .notDetermined: return .partial
            case .denied, .unavailable: return .off
            }
        }()
        #expect(healthStatus?.readiness == expectedReadiness)
    }

    /// Regression guard for the prior-art bug: `WorkoutManager` is a plain
    /// stored property on `ScoreViewModel`, not an `@ObservedObject` any view
    /// separately observes, so a view watching only the view model must still
    /// redraw when `healthAccess` changes. `ScoreViewModel.init` forwards
    /// `workoutManager.$healthAccess` into its own `objectWillChange` for
    /// exactly this reason — scoped to just that property (not the manager's
    /// whole `objectWillChange`), since during a live match `currentHeartRate`/
    /// `totalKilocalories` publish every 2–5 seconds and forwarding those too
    /// would invalidate every view observing the view model on each tick
    /// (a real Codex review finding on this PR).
    @Test func healthAccessChanges_forwardToViewModelsObjectWillChange() throws {
        let viewModel = makeViewModel()
        var fired = false
        let cancellable = viewModel.objectWillChange.sink { _ in fired = true }
        defer { cancellable.cancel() }

        // Every path through refreshHealthAccess() assigns `healthAccess`,
        // and `@Published` publishes on every write regardless of whether the
        // new value equals the old one — so this reliably exercises the forward
        // without depending on this simulator's actual HealthKit permission state.
        viewModel.workoutManager.refreshHealthAccess()

        #expect(fired == true)
    }

    /// The forward must be scoped narrowly: poking the workout manager's
    /// general `objectWillChange` (as opposed to a `healthAccess` write) must
    /// NOT reach the view model — that was the bug the fix above corrects.
    @Test func unrelatedWorkoutManagerObjectWillChange_doesNotForward() throws {
        let viewModel = makeViewModel()
        var fired = false
        let cancellable = viewModel.objectWillChange.sink { _ in fired = true }
        defer { cancellable.cancel() }

        viewModel.workoutManager.objectWillChange.send()

        #expect(fired == false)
    }
}

import Foundation
import DeuceMateCore
import Testing
@testable import DeuceMate_Watch_App

@MainActor
struct MatchSessionsWatchTests {
    private func url() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("sessions-\(UUID()).json")
    }
    private func parked() -> MatchRecord {
        MatchRecord(startTime: Date().addingTimeInterval(-600_000), setScores: [SetScore()], stats: [],
                    currentServer: .me, matchElapsedSeconds: 300, setElapsedSeconds: [0: 300],
                    totalSteps: 100, totalDistanceMeters: 120, totalCaloriesKcal: 30,
                    parkedAt: Date().addingTimeInterval(-500_000))
    }
    private final class WorkoutSpy: WorkoutManager {
        var startDates: [Date] = []
        var activity: (steps: Int, distanceMeters: Double, caloriesKcal: Double)?
        override func startWorkout(startDate: Date) { startDates.append(startDate) }
        override func stopWorkout() { activity = nil }
        override func snapshotActivity() -> (steps: Int, distanceMeters: Double, caloriesKcal: Double)? { activity }
        override func currentTotalStepsForStat() -> Int? { activity?.steps }
    }
    private final class FailureSwitch { var fail = false }

    @Test func failedResumePreservesOnlyCheckpointAndExistingLiveState() throws {
        let store = StatsStore(fileURL: url())
        let saved = parked(); store.saveHistory([saved])
        let stateURL = url()
        let sentinel = Data("retained previous bytes".utf8)
        try sentinel.write(to: stateURL)
        let vm = ScoreViewModel(statsStore: store, stateFileURL: stateURL,
            writeLiveState: { _, _ in throw CocoaError(.fileWriteOutOfSpace) })
        #expect(!vm.resumeMatch(saved))
        #expect(vm.currentMatchID == nil)
        #expect(!vm.shouldOpenMatchView)
        #expect(vm.persistenceError != nil)
        #expect(store.loadHistory() == [saved])
        #expect(try Data(contentsOf: stateURL) == sentinel)
    }

    @Test func failedParkCannotClearLiveOrReplaceItWithAnotherMatch() throws {
        let failure = FailureSwitch()
        let store = StatsStore(fileURL: url(), writeHistory: { records, target in
            if failure.fail { throw CocoaError(.fileWriteOutOfSpace) }
            try BackupExcludedFileWriter.write(records, to: target)
        })
        let saved = parked(); store.saveHistory([saved])
        let vm = ScoreViewModel(statsStore: store, stateFileURL: url())
        vm.currentServer = .me; vm.winPoint(player: .me)
        let liveID = try #require(vm.currentMatchID)
        failure.fail = true
        vm.resetMatch()
        #expect(vm.currentMatchID == liveID)
        #expect(vm.currentPointsMe == 1)
        #expect(!vm.resumeMatch(saved))
        #expect(vm.currentMatchID == liveID)
        #expect(store.loadHistory() == [saved])
    }

    @Test func failedIdleWriteAfterArchivingKeepsLiveStateAndCanRetryWithoutNewResume() throws {
        let store = StatsStore(fileURL: url()), stateURL = url(), failure = FailureSwitch()
        let vm = ScoreViewModel(statsStore: store, stateFileURL: stateURL, writeLiveState: { state, target in
            if failure.fail && state.currentMatchID == nil { throw CocoaError(.fileWriteOutOfSpace) }
            try BackupExcludedFileWriter.write(state, to: target)
        }, workoutManager: WorkoutSpy())
        vm.currentServer = .me; vm.winPoint(player: .me)
        let id = try #require(vm.currentMatchID)
        failure.fail = true
        vm.resetMatch()
        #expect(vm.currentMatchID == id)
        #expect(vm.currentPointsMe == 1)
        #expect(vm.persistenceError != nil)
        #expect(store.loadHistory().first?.id == id)
        let persistedLive = try JSONDecoder().decode(ScoreViewModel.AppState.self, from: Data(contentsOf: stateURL))
        #expect(persistedLive.currentMatchID == id)
        failure.fail = false
        vm.resetMatch()
        #expect(vm.currentMatchID == nil)
        let idle = try JSONDecoder().decode(ScoreViewModel.AppState.self, from: Data(contentsOf: stateURL))
        #expect(idle.currentMatchID == nil)
        #expect(store.loadHistory().first?.resumeEvents.isEmpty == true)
    }

    @Test func repeatedResumeRelaunchUndoAndNoScoringKeepExactlyOneEventPerExplicitResume() throws {
        let store = StatsStore(fileURL: url()); let saved = parked(); store.saveHistory([saved])
        let stateURL = url()
        let vm = ScoreViewModel(statsStore: store, stateFileURL: stateURL, workoutManager: WorkoutSpy())
        #expect(vm.resumeMatch(saved))
        let first = try #require(vm.resumeEvents.first)
        #expect(first.pausedAt == saved.parkedAt)
        #expect(vm.resumeMatch(saved))
        #expect(vm.resumeEvents.count == 1)
        #expect(vm.saveState())
        let restored = ScoreViewModel(statsStore: store, stateFileURL: stateURL, workoutManager: WorkoutSpy())
        restored.loadState()
        #expect(restored.resumeEvents == [first])
        restored.statsTrackingEnabled = false
        restored.winPoint(player: .me); restored.undo()
        #expect(restored.resumeEvents == [first])
        restored.resetMatch()
        let reparking = try #require(store.loadHistory().first)
        #expect(reparking.resumeEvents == [first])
        #expect(reparking.parkedAt != nil)
        #expect(restored.resumeMatch(reparking))
        #expect(restored.resumeEvents.count == 2)
        #expect(restored.resumeEvents.first?.id == first.id)
    }

    @Test func resumedWorkoutUsesNowAndFitnessAccumulatesOnceAcrossRetryRelaunchAndHealthOff() throws {
        let store = StatsStore(fileURL: url()); let saved = parked(); store.saveHistory([saved])
        let stateURL = url(); let workout = WorkoutSpy()
        let vm = ScoreViewModel(statsStore: store, stateFileURL: stateURL, workoutManager: workout)
        let before = Date()
        #expect(vm.resumeMatch(saved))
        #expect(try #require(workout.startDates.first) >= before)
        workout.activity = (steps: 12, distanceMeters: 20, caloriesKcal: 2)
        #expect(vm.saveState()); #expect(vm.saveState())
        let state = try JSONDecoder().decode(ScoreViewModel.AppState.self, from: Data(contentsOf: stateURL))
        #expect(state.activityTotals.steps == 112)
        #expect(state.activityTotals.distanceMeters == 140)
        #expect(state.activityTotals.caloriesKcal == 32)
        // A relaunch has a fresh builder with a counter starting from zero.
        let nextWorkout = WorkoutSpy()
        let restored = ScoreViewModel(statsStore: store, stateFileURL: stateURL, workoutManager: nextWorkout)
        restored.loadState(); restored.resumeWorkoutIfMatchInProgress()
        nextWorkout.activity = (steps: 3, distanceMeters: 4, caloriesKcal: 1)
        restored.statsTrackingEnabled = false
        restored.winPoint(player: .me)
        #expect(restored.currentMatchStats.last?.stepsCumulative == 115)
        restored.resetMatch()
        let second = try #require(store.loadHistory().first)
        #expect(second.totalSteps == 115)
        #expect(second.totalDistanceMeters == 144)
        #expect(second.totalCaloriesKcal == 33)
        // Health is unavailable for the next session; old totals remain present.
        #expect(restored.resumeMatch(second))
        restored.resetMatch()
        #expect(store.loadHistory().first?.totalSteps == 115)
        #expect(store.loadHistory().first?.totalCaloriesKcal == 33)
    }

    @Test func unreadableOrFutureLiveStateRefusesOverwriteAndScoring() throws {
        for future in [false, true] {
            let stateURL = url()
            let bytes: Data
            if future {
                let vm = ScoreViewModel(statsStore: StatsStore(fileURL: url()), stateFileURL: stateURL)
                #expect(vm.saveState())
                var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: stateURL)) as? [String: Any])
                json["version"] = 999
                bytes = try JSONSerialization.data(withJSONObject: json)
            } else { bytes = Data("unreadable".utf8) }
            try bytes.write(to: stateURL)
            let vm = ScoreViewModel(statsStore: StatsStore(fileURL: url()), stateFileURL: stateURL)
            vm.loadState(); vm.currentServer = .me; vm.winPoint(player: .me)
            #expect(!vm.saveState())
            #expect(!vm.stateRestorationSucceeded)
            #expect(vm.currentPointsMe == 0)
            #expect(vm.persistenceError != nil)
            #expect(try Data(contentsOf: stateURL) == bytes)
        }
    }
}

import Foundation
import HealthKit
import DeuceMateCore
import Testing
@testable import DeuceMate_Watch_App

/// All lifecycle decisions run through the production manager and finalizer.
/// Only the system's session/store boundary is deterministic.
@MainActor
struct WorkoutManagerTests {
    final class Session: WorkoutRecordingSession {
        weak var observer: WorkoutRecordingObserver?
        var state: HKWorkoutSessionState = .running
        var startDate: Date?
        var endDate: Date?
        var measurements = WorkoutMeasurements()
        var events: [String] = []
        var collectionEndDate: Date?
        var beginCompletion: ((Bool, Error?) -> Void)?
        var endCompletion: ((Bool, Error?) -> Void)?
        var saveCompletion: ((Error?) -> Void)?
        func startActivity(with date: Date) { startDate = date; events.append("start") }
        func beginCollection(at date: Date, completion: @escaping (Bool, Error?) -> Void) {
            events.append("begin"); beginCompletion = completion
        }
        func stopActivity(with date: Date?) { events.append("stop") }
        func endCollection(withEnd date: Date, completion: @escaping (Bool, Error?) -> Void) {
            events.append("endCollection"); collectionEndDate = date; endCompletion = completion
        }
        func finishSaving(completion: @escaping (Error?) -> Void) {
            events.append("save"); saveCompletion = completion
        }
        func end() { events.append("end") }
        func stopped(at date: Date = Date()) {
            state = .stopped; endDate = date
            observer?.recordingSession(self, changedTo: .stopped, at: date)
        }
        func finish(_ error: Error? = nil) throws {
            let collection = try #require(endCompletion)
            endCompletion = nil
            collection(true, nil)
            let save = try #require(saveCompletion)
            saveCompletion = nil
            save(error)
        }
    }

    final class Store: WorkoutSessionStore {
        var healthAccess: HealthAccess = .authorized
        var sessions: [Session] = []
        var creationError: Error?
        var recoveries = 0
        var recoveryCompletion: ((WorkoutRecordingSession?, Error?) -> Void)?
        func requestAuthorization(completion: @escaping (Bool) -> Void) { completion(true) }
        func makeSession() throws -> WorkoutRecordingSession {
            if let creationError { throw creationError }
            let session = Session(); sessions.append(session); return session
        }
        func recoverSession(completion: @escaping (WorkoutRecordingSession?, Error?) -> Void) {
            recoveries += 1; recoveryCompletion = completion
        }
    }

    final class Fixture {
        let directory: URL
        let store = Store()
        let manager: WorkoutManager
        let history: StatsStore
        let vm: ScoreViewModel
        let defaults: UserDefaults
        init() throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defaults = try #require(UserDefaults(suiteName: "workout-tests-\(UUID())"))
            history = StatsStore(fileURL: directory.appendingPathComponent("history.json"))
            manager = WorkoutManager(store: store)
            vm = ScoreViewModel(statsStore: history, stateFileURL: directory.appendingPathComponent("state.json"),
                                userDefaults: defaults, workoutManager: manager)
            vm.statsTrackingEnabled = false
            vm.checkChangeover = false
        }
        deinit { try? FileManager.default.removeItem(at: directory) }
        func start() {
            vm.beginMatchSession()
            vm.matchFormat = .superTiebreak
            vm.currentServer = .me
            vm.prepareTiebreakOnlySet()
            vm.syncMatchStart()
            vm.winPoint(player: .me)
        }
        func restored(_ manager: WorkoutManager) -> ScoreViewModel {
            let restored = ScoreViewModel(statsStore: history,
                stateFileURL: directory.appendingPathComponent("state.json"), userDefaults: defaults,
                workoutManager: manager)
            restored.statsTrackingEnabled = false
            restored.checkChangeover = false
            restored.loadState()
            return restored
        }
    }

    // Drain nested main-queue deliveries deterministically; no timing sleeps.
    private func drain() async {
        for _ in 0..<4 {
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
        }
    }

    @Test(arguments: ["park", "complete", "phone", "switch", "resumeWithoutScoring"])
    func matchExitReachesSaveExactlyOnce(exit: String) throws {
        let f = try Fixture(); f.start()
        let session = try #require(f.store.sessions.first)
        if exit == "complete" {
            for _ in 0..<9 { f.vm.winPoint(player: .me) }
            #expect(f.vm.isMatchComplete())
            #expect(!session.events.contains("stop"), "Winning-point undo still needs the active workout")
            f.vm.resetMatch()
        } else if exit == "phone" {
            f.vm.completeCurrentMatchIfMatching(try #require(f.vm.currentMatchID))
            #expect(f.history.loadHistory().first?.isInProgress == false)
        } else if exit == "switch" {
            let parked = MatchRecord(startTime: Date().addingTimeInterval(-100), setScores: [SetScore()],
                                     stats: [], currentServer: .me)
            f.history.saveHistory([parked])
            #expect(f.vm.resumeMatch(parked))
            #expect(f.store.sessions.count == 2)
            #expect(!f.store.sessions[1].events.contains("stop"))
        } else if exit == "resumeWithoutScoring" {
            f.vm.resetMatch()
            let parked = try #require(f.history.loadHistory().first)
            #expect(f.vm.resumeMatch(parked))
            f.vm.resetMatch()
            let resumed = try #require(f.store.sessions.last)
            resumed.stopped(); try resumed.finish()
            #expect(resumed.events == ["start", "begin", "stop", "endCollection", "save", "end"])
        } else {
            f.vm.resetMatch()
        }
        #expect(session.events == ["start", "begin", "stop"])
        let stoppedAt = Date(timeIntervalSince1970: 12345)
        session.stopped(at: stoppedAt)
        session.stopped(at: stoppedAt) // Duplicate delegate delivery.
        #expect(session.collectionEndDate == stoppedAt)
        #expect(session.events == ["start", "begin", "stop", "endCollection"])
        try session.finish()
        #expect(session.events == ["start", "begin", "stop", "endCollection", "save", "end"])
        if exit == "switch" {
            f.vm.resetMatch()
            let replacement = f.store.sessions[1]
            replacement.stopped(); try replacement.finish()
        }
    }

    @Test func completingAnAlreadyParkedMatchDoesNotCreateAnotherWorkout() throws {
        let f = try Fixture(); f.start(); f.vm.resetMatch()
        let session = try #require(f.store.sessions.first)
        session.stopped(); try session.finish()
        let parked = try #require(f.history.loadHistory().first)
        #expect(f.vm.endStoredMatchAtCurrentScore(parked))
        #expect(f.store.sessions.count == 1)
        #expect(session.events.filter { $0 == "save" }.count == 1)
    }

    @Test func stoppingRetainsTheSystemHandleUntilDelayedSaveCompletes() throws {
        let store = Store()
        // Use a separate manager whose store can release its test-only references.
        let subject = WorkoutManager(store: store)
        subject.startWorkout(startDate: Date())
        weak var retained = store.sessions.first
        subject.stopWorkout()
        store.sessions.removeAll()
        #expect(retained != nil)
        retained?.stopped()
        do {
            let end = try #require(retained?.endCompletion)
            retained?.endCompletion = nil; end(true, nil)
        }
        #expect(retained?.events.last == "save")
        do {
            let saved = try #require(retained?.saveCompletion)
            retained?.saveCompletion = nil; saved(nil)
        }
        #expect(retained == nil)
        #expect(!subject.isRunning)
    }

    @Test(arguments: [false, true])
    func recoveredLiveWorkoutKeepsBuilderAndCountsActivityOnce(completed: Bool) async throws {
        let f = try Fixture(); f.start()
        let original = try #require(f.store.sessions.first)
        original.measurements = WorkoutMeasurements(steps: 12, distanceMeters: 20, caloriesKcal: 3)
        if completed { for _ in 0..<9 { f.vm.winPoint(player: .me) } }
        #expect(f.vm.saveState())
        let nextStore = Store()
        let subject = WorkoutManager(store: nextStore)
        let vm = f.restored(subject)
        vm.restoreWorkoutAfterLaunch()
        vm.restoreWorkoutAfterLaunch() // WatchKit and launch can both request recovery.
        #expect(nextStore.recoveries == 1)
        subject.startWorkout(startDate: Date())
        #expect(nextStore.sessions.isEmpty)
        let recovered = Session()
        recovered.startDate = original.startDate
        recovered.measurements = WorkoutMeasurements(steps: 15, distanceMeters: 25, caloriesKcal: 4)
        let callback = try #require(nextStore.recoveryCompletion)
        callback(recovered, nil)
        await drain()
        #expect(subject.isRunning)
        #expect(nextStore.sessions.isEmpty)
        #expect(recovered.events.isEmpty, "Never restart recovered collection")
        #expect(vm.saveState()); #expect(vm.saveState())
        vm.resetMatch()
        let result = try #require(f.history.loadHistory().first)
        #expect(result.totalSteps == 15)
        #expect(result.totalDistanceMeters == 25)
        #expect(result.totalCaloriesKcal == 4)
        #expect(result.resumeEvents.isEmpty)
        recovered.stopped(); try recovered.finish()
        #expect(recovered.events == ["stop", "endCollection", "save", "end"])
        #expect(!subject.isRunning)
    }

    @Test(arguments: [false, true])
    func recoveredStoppedWorkoutFinishesEvenAfterLiveStateWasCleared(idle: Bool) async throws {
        let f = try Fixture(); f.start()
        let original = try #require(f.store.sessions.first)
        original.measurements = WorkoutMeasurements(steps: 10)
        if idle { f.vm.resetMatch() } else { #expect(f.vm.saveState()) }
        let store = Store(), manager = WorkoutManager(store: store)
        let vm = f.restored(manager)
        vm.restoreWorkoutAfterLaunch()
        let recovered = Session()
        recovered.state = .stopped; recovered.startDate = original.startDate
        recovered.endDate = Date(timeIntervalSince1970: 5678)
        recovered.measurements = WorkoutMeasurements(steps: 13)
        let callback = try #require(store.recoveryCompletion); callback(recovered, nil)
        await drain()
        #expect(recovered.events == ["endCollection"])
        #expect(recovered.collectionEndDate == recovered.endDate)
        try recovered.finish()
        #expect(recovered.events == ["endCollection", "save", "end"])
        #expect(store.sessions.count == (idle ? 0 : 1))
        if !idle {
            let fresh = try #require(store.sessions.first)
            fresh.measurements = WorkoutMeasurements(steps: 2)
            vm.resetMatch()
            #expect(f.history.loadHistory().first?.totalSteps == 15)
            fresh.stopped(); try fresh.finish()
        }
    }

    @Test(arguments: [false, true])
    func noRecoverableWorkoutStartsFreshOnlyForUnfinishedMatch(completed: Bool) async throws {
        let f = try Fixture(); f.start()
        if completed { for _ in 0..<9 { f.vm.winPoint(player: .me) } }
        let original = try #require(f.store.sessions.first)
        original.measurements = WorkoutMeasurements(steps: 10)
        #expect(f.vm.saveState())
        let store = Store(), manager = WorkoutManager(store: store)
        let vm = f.restored(manager); vm.restoreWorkoutAfterLaunch()
        let callback = try #require(store.recoveryCompletion); callback(nil, nil)
        await drain()
        #expect(store.sessions.count == (completed ? 0 : 1))
        store.sessions.first?.measurements = WorkoutMeasurements(steps: 2)
        vm.resetMatch()
        #expect(f.history.loadHistory().first?.totalSteps == (completed ? 10 : 12))
        if let fresh = store.sessions.first { fresh.stopped(); try fresh.finish() }
    }

    @Test func recoveryFailureWarnsAndDoesNotStartCompetingSession() async throws {
        let f = try Fixture(); f.start(); #expect(f.vm.saveState())
        let store = Store(), manager = WorkoutManager(store: store)
        let vm = f.restored(manager); vm.restoreWorkoutAfterLaunch()
        let callback = try #require(store.recoveryCompletion)
        callback(nil, CocoaError(.fileReadUnknown))
        await drain()
        #expect(manager.workoutError?.contains("Fitness recording") == true)
        #expect(store.sessions.isEmpty)
        let pointsBefore = vm.currentMatchStats.count
        vm.winPoint(player: .me)
        #expect(vm.currentMatchStats.count == pointsBefore + 1)
        #expect(vm.currentMatchStats.last?.winner == .me)
        #expect(vm.currentMatchID != nil)
    }

    @Test(arguments: ["creation", "denied", "begin", "collectionEnd", "save", "session"])
    func failuresWarnWithoutBlockingScoring(stage: String) async throws {
        let f = try Fixture()
        if stage == "creation" { f.store.creationError = CocoaError(.fileWriteUnknown) }
        if stage == "denied" { f.store.healthAccess = .denied }
        f.start()
        if let session = f.store.sessions.first {
            if stage == "begin" {
                let begin = try #require(session.beginCompletion); begin(false, nil)
            } else if stage == "session" {
                session.observer?.recordingSession(session, failedWith: CocoaError(.fileWriteUnknown))
            } else {
                f.vm.resetMatch(); session.stopped()
                if stage == "collectionEnd" {
                    let end = try #require(session.endCompletion); end(false, CocoaError(.fileWriteUnknown))
                } else { try session.finish(CocoaError(.fileWriteOutOfSpace)) }
            }
        }
        await drain()
        let message = try #require(f.manager.workoutError)
        #expect(message.contains(stage == "save" || stage == "collectionEnd" ? "couldn’t be saved" : "Fitness recording"))
        if f.vm.currentMatchID == nil { f.vm.currentServer = .me }
        let pointsBefore = f.vm.currentMatchStats.count
        f.vm.winPoint(player: .me)
        #expect(f.vm.currentMatchStats.count == pointsBefore + 1)
        #expect(f.vm.currentMatchStats.last?.winner == .me)
        // A dismissed warning must not suppress a subsequent failure.
        f.manager.workoutError = nil
        f.store.creationError = CocoaError(.fileWriteUnknown)
        f.manager.startWorkout(startDate: Date())
        await drain()
        #expect(f.manager.workoutError != nil)
        if stage == "begin", let session = f.store.sessions.first {
            session.stopped(); try session.finish()
        }
    }

    @Test func appStateWithoutRecoveryFieldsStillLoads() throws {
        let f = try Fixture(); f.start(); #expect(f.vm.saveState())
        let url = f.directory.appendingPathComponent("state.json")
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        json.removeValue(forKey: "workoutStartDate"); json.removeValue(forKey: "workoutBaseline")
        let legacy = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(ScoreViewModel.AppState.self, from: legacy)
        #expect(decoded.workoutStartDate == nil)
        #expect(decoded.workoutBaseline == nil)
        #expect(decoded.currentMatchID == f.vm.currentMatchID)
    }

    @Test func recoveryPreservesEarlierPlaySessionsWithoutCountingTheActiveBuilderTwice() async throws {
        let f = try Fixture()
        let parked = MatchRecord(startTime: Date().addingTimeInterval(-1000), setScores: [SetScore()],
            stats: [], currentServer: .me, totalSteps: 100, totalDistanceMeters: 120, totalCaloriesKcal: 30)
        f.history.saveHistory([parked])
        #expect(f.vm.resumeMatch(parked))
        let original = try #require(f.store.sessions.first)
        original.measurements = WorkoutMeasurements(steps: 12, distanceMeters: 20, caloriesKcal: 2)
        #expect(f.vm.saveState())
        let store = Store(), manager = WorkoutManager(store: store)
        let vm = f.restored(manager); vm.restoreWorkoutAfterLaunch()
        let recovered = Session(); recovered.startDate = original.startDate
        recovered.measurements = WorkoutMeasurements(steps: 15, distanceMeters: 25, caloriesKcal: 3)
        let callback = try #require(store.recoveryCompletion); callback(recovered, nil)
        await drain()
        #expect(vm.saveState()); #expect(vm.saveState())
        vm.resetMatch()
        let record = try #require(f.history.loadHistory().first)
        #expect(record.totalSteps == 115)
        #expect(record.totalDistanceMeters == 145)
        #expect(record.totalCaloriesKcal == 33)
        #expect(record.resumeEvents.count == 1)
        recovered.stopped(); try recovered.finish()
    }

    @Test func aDifferentRecoveredIdentityIsSavedSeparatelyAndNeverAddedToLiveTotals() async throws {
        let f = try Fixture(); f.start()
        f.store.sessions.first?.measurements = WorkoutMeasurements(steps: 10)
        #expect(f.vm.saveState())
        let store = Store(), manager = WorkoutManager(store: store)
        let vm = f.restored(manager); vm.restoreWorkoutAfterLaunch()
        let orphan = Session()
        orphan.startDate = Date(timeIntervalSince1970: 1)
        orphan.measurements = WorkoutMeasurements(steps: 999)
        let callback = try #require(store.recoveryCompletion); callback(orphan, nil)
        await drain()
        #expect(orphan.events == ["stop"])
        let fresh = try #require(store.sessions.first)
        fresh.measurements = WorkoutMeasurements(steps: 2)
        orphan.stopped(); try orphan.finish()
        #expect(manager.isRunning)
        vm.resetMatch()
        #expect(f.history.loadHistory().first?.totalSteps == 12)
        fresh.stopped(); try fresh.finish()
    }

    @Test func aStopNotificationDeliveredBeforeParkingCannotLeaveTheWorkoutUnsaved() throws {
        let f = try Fixture(); f.start()
        let session = try #require(f.store.sessions.first)
        session.stopped()
        f.vm.resetMatch()
        #expect(session.events == ["start", "begin", "endCollection"])
        try session.finish()
        #expect(session.events == ["start", "begin", "endCollection", "save", "end"])
    }

    @Test func watchKitRecoveryDelegateInvokesTheLaunchRestorationHandler() async {
        let delegate = WorkoutRecoveryDelegate()
        var requested = false
        delegate.recoverWorkout = { requested = true }
        delegate.handleActiveWorkoutRecovery()
        await drain()
        #expect(requested)
    }
}

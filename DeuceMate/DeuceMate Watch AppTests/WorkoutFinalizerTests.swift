import Foundation
import DeuceMateCore
import Testing
@testable import DeuceMate_Watch_App

struct WorkoutFinalizerTests {
    private final class Trace {
        var events: [String] = []
        var errors: [Error] = []
    }
    private final class Session: WorkoutFinalizationSession {
        let trace: Trace
        let name: String
        init(_ trace: Trace, name: String = "session") { self.trace = trace; self.name = name }
        func stopActivity(with date: Date?) { trace.events.append("\(name).stop") }
        func end() { trace.events.append("\(name).end") }
    }
    private final class Builder: WorkoutFinalizationBuilder {
        let trace: Trace
        var endDate: Date?
        var collectionCompletion: ((Bool, Error?) -> Void)?
        var saveCompletion: ((Error?) -> Void)?
        init(_ trace: Trace) { self.trace = trace }
        func endCollection(withEnd date: Date, completion: @escaping (Bool, Error?) -> Void) {
            trace.events.append("collection.end")
            endDate = date
            collectionCompletion = completion
        }
        func finishSaving(completion: @escaping (Error?) -> Void) {
            trace.events.append("save")
            saveCompletion = completion
        }
    }

    @Test func stopWaitsForStoppedStateThenSaveBeforeEndingSession() throws {
        let trace = Trace()
        let finalizer = WorkoutFinalizer { trace.errors.append($0) }
        let session = Session(trace), builder = Builder(trace)
        let date = Date(timeIntervalSince1970: 100)
        finalizer.stop(session: session, builder: builder, at: date)
        #expect(trace.events == ["session.stop"])
        finalizer.didStop(session: session, at: date)
        #expect(builder.endDate == date)
        #expect(trace.events == ["session.stop", "collection.end"])
        let callback1 = try #require(builder.collectionCompletion)
        callback1(true, nil)
        #expect(trace.events == ["session.stop", "collection.end", "save"])
        let callback2 = try #require(builder.saveCompletion)
        callback2(nil)
        #expect(trace.events == ["session.stop", "collection.end", "save", "session.end"])
        #expect(trace.errors.isEmpty)
    }

    @Test func stoppedSessionSurvivesReleaseOfActiveReferencesThroughSave() throws {
        let trace = Trace()
        let finalizer = WorkoutFinalizer { trace.errors.append($0) }
        var session: Session? = Session(trace)
        var builder: Builder? = Builder(trace)
        weak var retainedSession = session
        weak var retainedBuilder = builder
        finalizer.stop(session: try #require(session), builder: try #require(builder), at: Date())
        session = nil; builder = nil
        #expect(retainedSession != nil)
        #expect(retainedBuilder != nil)
        finalizer.didStop(session: try #require(retainedSession), at: Date())
        // HealthKit invokes these callbacks once, and releases them afterwards.
        do {
            let collection = try #require(retainedBuilder?.collectionCompletion)
            retainedBuilder?.collectionCompletion = nil
            collection(true, nil)
        }
        #expect(retainedSession != nil)
        do {
            let saved = try #require(retainedBuilder?.saveCompletion)
            retainedBuilder?.saveCompletion = nil
            saved(nil)
        }
        #expect(trace.events.last == "session.end")
        #expect(retainedSession == nil)
        #expect(retainedBuilder == nil)
    }

    @Test func resumedSessionCannotBeEndedByOlderSaveCallback() throws {
        let trace = Trace()
        let finalizer = WorkoutFinalizer { trace.errors.append($0) }
        let old = Session(trace, name: "old"), new = Session(trace, name: "new")
        let oldBuilder = Builder(trace), newBuilder = Builder(trace)
        finalizer.stop(session: old, builder: oldBuilder, at: Date())
        finalizer.didStop(session: old, at: Date())
        let callback3 = try #require(oldBuilder.collectionCompletion)
        callback3(true, nil)
        finalizer.stop(session: new, builder: newBuilder, at: Date())
        let callback4 = try #require(oldBuilder.saveCompletion)
        callback4(nil)
        #expect(trace.events.last == "old.end")
        #expect(!trace.events.contains("new.end"))
        finalizer.didStop(session: new, at: Date())
        let callback5 = try #require(newBuilder.collectionCompletion)
        callback5(true, nil)
        let callback6 = try #require(newBuilder.saveCompletion)
        callback6(nil)
        #expect(trace.events.last == "new.end")
    }

    @Test func repeatedStopNotificationsDoNotSaveTwice() throws {
        let trace = Trace()
        let finalizer = WorkoutFinalizer { trace.errors.append($0) }
        let session = Session(trace), builder = Builder(trace)
        finalizer.stop(session: session, builder: builder, at: Date())
        finalizer.stop(session: session, builder: builder, at: Date())
        finalizer.didStop(session: session, at: Date())
        finalizer.didStop(session: session, at: Date())
        let callback7 = try #require(builder.collectionCompletion)
        callback7(true, nil)
        let callback8 = try #require(builder.saveCompletion)
        callback8(nil)
        finalizer.didStop(session: session, at: Date())
        #expect(trace.events == ["session.stop", "collection.end", "save", "session.end"])
    }

    @Test func collectionFailureIsReportedWithoutAttemptingSave() throws {
        let trace = Trace()
        let finalizer = WorkoutFinalizer { trace.errors.append($0) }
        let session = Session(trace), builder = Builder(trace)
        finalizer.stop(session: session, builder: builder, at: Date())
        finalizer.didStop(session: session, at: Date())
        let callback9 = try #require(builder.collectionCompletion)
        callback9(false, CocoaError(.fileWriteNoPermission))
        #expect(trace.events == ["session.stop", "collection.end", "session.end"])
        #expect(trace.errors.count == 1)
    }

    @Test func saveFailureIsReportedAndSessionStillEnds() throws {
        let trace = Trace()
        let finalizer = WorkoutFinalizer { trace.errors.append($0) }
        let session = Session(trace), builder = Builder(trace)
        finalizer.stop(session: session, builder: builder, at: Date())
        finalizer.didStop(session: session, at: Date())
        let callback10 = try #require(builder.collectionCompletion)
        callback10(true, nil)
        let callback11 = try #require(builder.saveCompletion)
        callback11(CocoaError(.fileWriteOutOfSpace))
        #expect(trace.events.last == "session.end")
        #expect(trace.errors.count == 1)
        #expect((trace.errors.first as NSError?)?.code == CocoaError.fileWriteOutOfSpace.rawValue)
    }
    @Test func sessionFailureWhileStoppingReleasesAndReportsWithoutSaving() {
        let trace = Trace()
        let finalizer = WorkoutFinalizer { trace.errors.append($0) }
        let session = Session(trace), builder = Builder(trace)
        finalizer.stop(session: session, builder: builder, at: Date())
        #expect(finalizer.didFail(session: session, error: CocoaError(.fileWriteUnknown)))
        finalizer.didStop(session: session, at: Date())
        #expect(trace.events == ["session.stop", "session.end"])
        #expect(trace.errors.count == 1)
    }

    @Test func unsuccessfulCollectionWithoutErrorStillReportsFailure() throws {
        let trace = Trace()
        let finalizer = WorkoutFinalizer { trace.errors.append($0) }
        let session = Session(trace), builder = Builder(trace)
        finalizer.stop(session: session, builder: builder, at: Date())
        finalizer.didStop(session: session, at: Date())
        let callback12 = try #require(builder.collectionCompletion)
        callback12(false, nil)
        #expect(trace.errors.count == 1)
        #expect(!trace.events.contains("save"))
    }

    @MainActor
    @Test func parkingUnfinishedMatchStopsWorkoutAndResumeStartsSeparateSession() throws {
        final class RecordingWorkout: WorkoutManager {
            var starts = 0
            var stops = 0
            private var active = false
            override func startWorkout(startDate: Date) { starts += 1; active = true }
            override func stopWorkout() {
                if active { stops += 1; active = false }
            }
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = StatsStore(fileURL: directory.appendingPathComponent("history.json"))
        let workout = RecordingWorkout()
        let vm = ScoreViewModel(statsStore: store,
            stateFileURL: directory.appendingPathComponent("state.json"), workoutManager: workout)
        vm.beginMatchSession()
        vm.currentServer = .me
        vm.winPoint(player: .me)
        vm.resetMatch()
        let parked = try #require(store.loadHistory().first)
        #expect(parked.isInProgress)
        #expect(workout.starts == 1)
        #expect(workout.stops == 1)
        #expect(vm.resumeMatch(parked))
        #expect(workout.starts == 2)
        vm.winPoint(player: .me)
        vm.resetMatch()
        #expect(workout.stops == 2)
        #expect(store.loadHistory().count == 1)
        #expect(store.loadHistory().first?.id == parked.id)
    }

    @Test func lateCollectionCallbackAfterSessionFailureCannotStartSave() throws {
        let trace = Trace()
        let finalizer = WorkoutFinalizer { trace.errors.append($0) }
        let session = Session(trace), builder = Builder(trace)
        finalizer.stop(session: session, builder: builder, at: Date())
        finalizer.didStop(session: session, at: Date())
        finalizer.didFail(session: session, error: CocoaError(.fileWriteUnknown))
        let callback = try #require(builder.collectionCompletion)
        callback(true, nil)
        #expect(!trace.events.contains("save"))
        #expect(trace.events.filter { $0 == "session.end" }.count == 1)
        #expect(trace.errors.count == 1)
    }

}

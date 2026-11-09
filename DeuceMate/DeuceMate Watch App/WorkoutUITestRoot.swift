#if DEBUG
import SwiftUI
import HealthKit
import DeuceMateCore

/// Isolated, disposable UI fixture: production screens/manager, no Health or sync.
struct WorkoutUITestRoot: View {
    @StateObject private var model: ScoreViewModel
    private let store: WorkoutUITestStore
    @State private var home = false

    init() {
        let store = WorkoutUITestStore()
        self.store = store
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("workout-ui-\(UUID())")
        let model = ScoreViewModel(statsStore: StatsStore(fileURL: directory.appendingPathComponent("history.json")),
            stateFileURL: directory.appendingPathComponent("state.json"), workoutManager: WorkoutManager(store: store))
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        model.statsTrackingEnabled = false
        model.checkChangeover = false
        model.beginMatchSession()
        model.currentServer = .me
        model.syncMatchStart()
        model.winPoint(player: .me)
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Fail recording") {
                    if model.workoutManager.isRunning {
                        store.session.observer?.recordingSession(store.session, failedWith: CocoaError(.fileWriteUnknown))
                    } else {
                        store.failCreation = true
                        model.beginMatchSession()
                    }
                }.accessibilityIdentifier("failWorkoutRecording")
                if home {
                    Button("Fail save") { store.session.saveCompletion?(CocoaError(.fileWriteOutOfSpace)) }
                        .accessibilityIdentifier("failWorkoutSave")
                } else {
                    Button("Park") { model.resetMatch(); home = true }
                        .accessibilityIdentifier("parkWorkout")
                }
            }.font(.system(size: 9))
            Group {
                if home { HomeView() } else { ContentView() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .padding(.top, 20)
        .environmentObject(model)
        .environment(\.appTheme, .default)
    }
}

private final class WorkoutUITestStore: WorkoutSessionStore {
    var healthAccess: HealthAccess { .authorized }
    let session = WorkoutUITestSession()
    var failCreation = false
    func requestAuthorization(completion: @escaping (Bool) -> Void) { completion(true) }
    func recoverSession(completion: @escaping (WorkoutRecordingSession?, Error?) -> Void) { completion(nil, nil) }
    func makeSession() throws -> WorkoutRecordingSession {
        if failCreation { throw CocoaError(.fileWriteUnknown) }
        return session
    }
}

private final class WorkoutUITestSession: WorkoutRecordingSession {
    weak var observer: WorkoutRecordingObserver?
    var state: HKWorkoutSessionState { .running }
    var startDate: Date?
    var endDate: Date?
    var measurements: WorkoutMeasurements { WorkoutMeasurements() }
    var saveCompletion: ((Error?) -> Void)?
    func startActivity(with date: Date) { startDate = date }
    func beginCollection(at date: Date, completion: @escaping (Bool, Error?) -> Void) { completion(true, nil) }
    func stopActivity(with date: Date?) {
        endDate = date
        observer?.recordingSession(self, changedTo: .stopped, at: date ?? Date())
    }
    func endCollection(withEnd date: Date, completion: @escaping (Bool, Error?) -> Void) { completion(true, nil) }
    func finishSaving(completion: @escaping (Error?) -> Void) { saveCompletion = completion }
    func end() {}
}
#endif

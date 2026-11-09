import Foundation
import HealthKit
import OSLog
import DeuceMateCore

class WorkoutManager: NSObject, ObservableObject {
    private let store: WorkoutSessionStore
    private var session: WorkoutRecordingSession?
    private var requestedStartDate: Date?
    private lazy var finalizer = WorkoutFinalizer { [weak self] error in
        self?.reportWorkoutFailure(error, saving: true)
    }
    @Published var workoutError: String?
    private let logger = Logger(subsystem: "ehsan.DeuceMate.watchkitapp", category: "Workout")
    @Published private(set) var isRunning = false
    @Published private(set) var isRecovering = false
    @Published private(set) var currentHeartRate: Double?
    @Published private(set) var totalKilocalories: Double?
    /// Share authorization is the observable proxy; HealthKit hides read permission.
    @Published private(set) var healthAccess: HealthAccess = .notDetermined
    private var lastHeartRatePublishDate: Date?
    private var lastCaloriesPublishDate: Date?
    var workoutStartDate: Date? { session?.startDate ?? requestedStartDate }

    init(store: WorkoutSessionStore = HealthKitWorkoutStore()) {
        self.store = store
        super.init()
    }

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        store.requestAuthorization { success in
            DispatchQueue.main.async {
                self.settleHealthAccessAfterAuthorization()
                completion(success)
            }
        }
    }

    /// The authorization sheet need not change scenePhase, and its share status
    /// can lag the completion. Keep the bounded retry schedule after a fresh grant.
    private func settleHealthAccessAfterAuthorization(attempt: Int = 0) {
        refreshHealthAccess()
        guard let delay = HealthAccessSettlePolicy.nextRetryDelay(attempt: attempt, access: healthAccess) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.settleHealthAccessAfterAuthorization(attempt: attempt + 1)
        }
    }

    func refreshHealthAccess() { healthAccess = store.healthAccess }

    func startWorkout(startDate: Date) {
        guard !isRunning, !isRecovering else { return }
        refreshHealthAccess()
        guard healthAccess == .authorized else {
            reportWorkoutFailure(nil, saving: false)
            return
        }
        do {
            let starting = try store.makeSession()
            session = starting
            requestedStartDate = startDate
            starting.observer = self
            _ = finalizer
            isRunning = true
            starting.startActivity(with: startDate)
            starting.beginCollection(at: startDate) { [weak self, weak starting] success, error in
                guard !success || error != nil else { return }
                DispatchQueue.main.async {
                    guard let self, let starting, self.session === starting else { return }
                    self.reportWorkoutFailure(error, saving: false)
                    self.stopWorkout()
                }
            }
        } catch {
            session = nil
            requestedStartDate = nil
            reportWorkoutFailure(error, saving: false)
        }
    }

    /// The caller decides whether this recovered identity belongs to its live match.
    /// While recovery is pending, a start cannot create a competing workout.
    func recoverWorkout(completion: @escaping (WorkoutRecordingSession?, Error?) -> Void) {
        guard !isRecovering, session == nil else { return }
        isRecovering = true
        store.recoverSession { [weak self] recovered, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isRecovering = false
                if let error { self.reportWorkoutFailure(error, saving: false) }
                completion(recovered, error)
            }
        }
    }

    func adoptRecoveredWorkout(_ recovered: WorkoutRecordingSession) {
        guard session == nil else { return }
        session = recovered
        requestedStartDate = recovered.startDate
        recovered.observer = self
        _ = finalizer
        isRunning = true
        recordingSession(recovered, collected: recovered.measurements)
    }

    /// Snapshotting a stopped recovery precedes handing it to the finalizer.
    func detachRecoveredWorkout() {
        session = nil
        requestedStartDate = nil
        isRunning = false
        currentHeartRate = nil
        totalKilocalories = nil
    }

    /// Finish orphaned/stopped workouts even when the live file is already idle.
    func finishRecoveredWorkout(_ recovered: WorkoutRecordingSession) {
        recovered.observer = self
        _ = finalizer
        if recovered.state == .stopped || recovered.state == .ended {
            finalizer.resumeStopped(session: recovered, builder: recovered, at: recovered.endDate ?? Date())
        } else {
            finalizer.stop(session: recovered, builder: recovered, at: Date())
        }
    }

    func stopWorkout() {
        guard let stopping = session else { return }
        session = nil
        requestedStartDate = nil
        // Clear synchronously so a replacement can start in the same turn.
        isRunning = false
        currentHeartRate = nil
        totalKilocalories = nil
        lastHeartRatePublishDate = nil
        lastCaloriesPublishDate = nil
        if stopping.state == .stopped || stopping.state == .ended {
            finalizer.resumeStopped(session: stopping, builder: stopping, at: stopping.endDate ?? Date())
        } else {
            finalizer.stop(session: stopping, builder: stopping, at: Date())
        }
    }

    private func reportWorkoutFailure(_ error: Error?, saving: Bool) {
        let nsError = error as NSError?
        logger.error("Workout operation failed: domain=\(nsError?.domain ?? "unknown", privacy: .public) code=\(nsError?.code ?? 0)")
        DispatchQueue.main.async {
            self.workoutError = saving
                ? "Workout couldn’t be saved to Health. Your match score is kept. Check DeuceMate’s Workouts access in Health."
                : "Fitness recording couldn’t start or continue. Scoring is still available. Check DeuceMate’s Workouts access in Health."
        }
    }

    func snapshotActivity() -> (steps: Int, distanceMeters: Double, caloriesKcal: Double)? {
        guard let values = session?.measurements, isRunning,
              values.steps != nil || values.distanceMeters != nil || (values.caloriesKcal ?? 0) > 0 else { return nil }
        return (values.steps ?? 0, values.distanceMeters ?? 0, values.caloriesKcal ?? 0)
    }

    func currentTotalStepsForStat() -> Int? { session?.measurements.steps }
}

extension WorkoutManager: WorkoutRecordingObserver {
    func recordingSession(_ originating: WorkoutRecordingSession, changedTo state: HKWorkoutSessionState, at date: Date) {
        if state == .stopped { finalizer.didStop(session: originating, at: date) }
    }

    func recordingSession(_ originating: WorkoutRecordingSession, failedWith error: Error) {
        if finalizer.didFail(session: originating, error: error) { return }
        DispatchQueue.main.async {
            guard self.session === originating else { return }
            self.reportWorkoutFailure(error, saving: false)
            self.session = nil
            self.requestedStartDate = nil
            originating.end()
            self.isRunning = false
            self.currentHeartRate = nil
            self.totalKilocalories = nil
        }
    }

    func recordingSession(_ originating: WorkoutRecordingSession, collected values: WorkoutMeasurements) {
        DispatchQueue.main.async {
            guard self.isRunning, self.session === originating else { return }
            let now = Date()
            if let bpm = values.heartRate,
               self.lastHeartRatePublishDate.map({ now.timeIntervalSince($0) >= 2 }) ?? true {
                self.currentHeartRate = bpm
                self.lastHeartRatePublishDate = now
            }
            if let kcal = values.caloriesKcal,
               self.lastCaloriesPublishDate.map({ now.timeIntervalSince($0) >= 5 }) ?? true {
                self.totalKilocalories = kcal
                self.lastCaloriesPublishDate = now
            }
        }
    }
}

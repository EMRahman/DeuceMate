import Foundation
import HealthKit
import OSLog
import DeuceMateCore

class WorkoutManager: NSObject, ObservableObject {
    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private lazy var finalizer = WorkoutFinalizer { [weak self] error in
        self?.reportWorkoutFailure(error, saving: true)
    }
    @Published var workoutError: String?
    private let logger = Logger(subsystem: "ehsan.DeuceMate.watchkitapp", category: "Workout")
    private let lifecycleLock = NSLock()

    @Published private(set) var isRunning = false
    @Published private(set) var currentHeartRate: Double? = nil
    @Published private(set) var totalKilocalories: Double? = nil
    /// Whether a match will record heart rate, steps, and calories. There is no
    /// in-app toggle for this — it is the system HealthKit permission — so the
    /// pre-match tracking strip reads it from here. Refreshed after the
    /// authorization request and whenever the app returns to the foreground,
    /// since the user can revoke access from the iPhone while the app is away.
    @Published private(set) var healthAccess: HealthAccess = .notDetermined
    private var lastHeartRatePublishDate: Date?
    private var lastCaloriesPublishDate: Date?
    private let heartRatePublishInterval: TimeInterval = 2.0
    private let caloriesPublishInterval: TimeInterval = 5.0

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else { completion(false); return }
        let share: Set<HKSampleType> = [HKQuantityType.workoutType()]
        let read: Set<HKObjectType> = [
            HKQuantityType.workoutType(),
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.basalEnergyBurned),
            HKQuantityType(.stepCount),
            HKQuantityType(.distanceWalkingRunning)
        ]
        healthStore.requestAuthorization(toShare: share, read: read) { success, _ in
            DispatchQueue.main.async {
                self.settleHealthAccessAfterAuthorization()
                completion(success)
            }
        }
    }

    /// Re-reads the share status until it stops saying `.notDetermined`.
    ///
    /// This completion is the *only* chance the app gets to notice a fresh
    /// grant: the scene never leaves `.active` for a system sheet, so
    /// `DeuceMateApp`'s `scenePhase` refresh doesn't fire, and the start
    /// screen's `onAppear` already ran before the sheet was answered. When the
    /// status isn't readable yet at this instant, a single read here leaves the
    /// tracking strip showing a yellow "Ask" until the next launch — the
    /// reported bug. `HealthAccessSettlePolicy` (Core, tested) owns the bounded
    /// schedule; re-reading also republishes `healthAccess`, so the strip
    /// redraws even if it somehow missed the first value.
    private func settleHealthAccessAfterAuthorization(attempt: Int = 0) {
        refreshHealthAccess()
        guard let delay = HealthAccessSettlePolicy.nextRetryDelay(
            attempt: attempt,
            access: healthAccess
        ) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.settleHealthAccessAfterAuthorization(attempt: attempt + 1)
        }
    }

    /// Re-reads the HealthKit permission into `healthAccess`.
    ///
    /// Only *share* authorization can be queried — HealthKit deliberately hides
    /// read authorization so an app cannot infer what the user is hiding. The
    /// workout share status is the honest proxy: without it no workout session
    /// is saved, and with it the session runs and collects the samples the user
    /// allowed. Call on foreground; permissions change outside the app.
    func refreshHealthAccess() {
        guard HKHealthStore.isHealthDataAvailable() else {
            healthAccess = .unavailable
            return
        }
        switch healthStore.authorizationStatus(for: HKQuantityType.workoutType()) {
        case .sharingAuthorized: healthAccess = .authorized
        case .sharingDenied:     healthAccess = .denied
        case .notDetermined:     healthAccess = .notDetermined
        @unknown default:        healthAccess = .notDetermined
        }
    }

    func startWorkout(startDate: Date) {
        guard HKHealthStore.isHealthDataAvailable(), !isRunning else { return }
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        let config = HKWorkoutConfiguration()
        config.activityType = .tennis
        config.locationType = .indoor
        do {
            session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            builder = session?.associatedWorkoutBuilder()
            let dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)
            dataSource.enableCollection(for: HKQuantityType(.stepCount), predicate: nil)
            dataSource.enableCollection(for: HKQuantityType(.distanceWalkingRunning), predicate: nil)
            builder?.dataSource = dataSource
            session?.delegate = self
            builder?.delegate = self
            // Initialize on the caller's queue before HealthKit can call back.
            _ = finalizer
            session?.startActivity(with: startDate)
            let startingSession = session
            builder?.beginCollection(withStart: startDate) { [weak self] success, error in
                guard !success || error != nil else { return }
                self?.reportWorkoutFailure(error, saving: false)
                DispatchQueue.main.async {
                    guard let self, self.session === startingSession else { return }
                    self.stopWorkout()
                }
            }
            isRunning = true
        } catch {
            session = nil
            builder = nil
            reportWorkoutFailure(error, saving: false)
        }
    }

    func stopWorkout() {
        guard isRunning else { return }
        lifecycleLock.lock()
        let stoppingSession = session
        let stoppingBuilder = builder
        builder = nil
        session = nil
        lifecycleLock.unlock()
        if let stoppingSession, let stoppingBuilder {
            finalizer.stop(session: stoppingSession, builder: stoppingBuilder, at: Date())
        } else {
            stoppingSession?.end()
        }
        // Set synchronously — always called from main thread — so that a
        // subsequent startWorkout() call in the same turn sees isRunning = false.
        isRunning = false
        currentHeartRate = nil
        totalKilocalories = nil
        lastHeartRatePublishDate = nil
        lastCaloriesPublishDate = nil
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

    /// Returns accumulated steps, distance, and calories from the current workout builder.
    /// Take this snapshot before stopping; a stopped builder can never contribute to
    /// a later session or overwrite its values through a delayed callback.
    func snapshotActivity() -> (steps: Int, distanceMeters: Double, caloriesKcal: Double)? {
        guard let b = builder, isRunning else { return nil }
        let steps = b.statistics(for: HKQuantityType(.stepCount))?
            .sumQuantity()?.doubleValue(for: .count())
        let dist = b.statistics(for: HKQuantityType(.distanceWalkingRunning))?
            .sumQuantity()?.doubleValue(for: .meter())
        let kcalUnit = HKUnit.kilocalorie()
        let active = b.statistics(for: HKQuantityType(.activeEnergyBurned))?
            .sumQuantity()?.doubleValue(for: kcalUnit) ?? 0
        let basal = b.statistics(for: HKQuantityType(.basalEnergyBurned))?
            .sumQuantity()?.doubleValue(for: kcalUnit) ?? 0
        let calories = active + basal
        guard steps != nil || dist != nil || calories > 0 else { return nil }
        return (steps: steps.map { Int($0) } ?? 0, distanceMeters: dist ?? 0, caloriesKcal: calories)
    }

    /// Cumulative step count accumulated by the live workout builder so far.
    /// Returns nil when no workout is running or before HealthKit has produced
    /// any step samples. Called per-point to stamp `PointStat.stepsCumulative`.
    func currentTotalStepsForStat() -> Int? {
        guard let b = builder else { return nil }
        guard let v = b.statistics(for: HKQuantityType(.stepCount))?
            .sumQuantity()?.doubleValue(for: .count()) else { return nil }
        return Int(v)
    }
}

extension WorkoutManager: HKWorkoutSessionDelegate {
    func workoutSession(_ session: HKWorkoutSession,
                        didChangeTo toState: HKWorkoutSessionState,
                        from fromState: HKWorkoutSessionState,
                        date: Date) {
        if toState == .stopped {
            finalizer.didStop(session: session, at: date)
        }
    }

    func workoutSession(_ session: HKWorkoutSession, didFailWithError error: Error) {
        if finalizer.didFail(session: session, error: error) { return }
        DispatchQueue.main.async {
            guard self.session === session else { return }
            self.reportWorkoutFailure(error, saving: false)
            self.lifecycleLock.lock()
            self.session = nil
            self.builder = nil
            self.lifecycleLock.unlock()
            session.end()
            self.isRunning = false
            self.currentHeartRate = nil
            self.totalKilocalories = nil
        }
    }
}

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                        didCollectDataOf collectedTypes: Set<HKSampleType>) {
        lifecycleLock.lock()
        let originatingSession = session
        let isCurrent = builder === workoutBuilder && originatingSession != nil
        lifecycleLock.unlock()
        guard isCurrent else { return }
        var bpmValue: Double?
        if collectedTypes.contains(HKQuantityType(.heartRate)),
           let heartRateStats = workoutBuilder.statistics(for: HKQuantityType(.heartRate)),
           let quantity = heartRateStats.mostRecentQuantity() {
            let bpmUnit = HKUnit.count().unitDivided(by: .minute())
            bpmValue = quantity.doubleValue(for: bpmUnit)
        }

        let activeEnergyType = HKQuantityType(.activeEnergyBurned)
        let basalEnergyType = HKQuantityType(.basalEnergyBurned)
        var totalKilocalories: Double?
        if collectedTypes.contains(activeEnergyType) || collectedTypes.contains(basalEnergyType) {
            let kcalUnit = HKUnit.kilocalorie()
            let active = workoutBuilder.statistics(for: activeEnergyType)?
                .sumQuantity()?
                .doubleValue(for: kcalUnit) ?? 0
            let basal = workoutBuilder.statistics(for: basalEnergyType)?
                .sumQuantity()?
                .doubleValue(for: kcalUnit) ?? 0
            totalKilocalories = active + basal
        }

        DispatchQueue.main.async {
            if self.isRunning, self.session === originatingSession, self.builder === workoutBuilder {
                let now = Date()
                if let bpmValue,
                   self.shouldPublish(at: now,
                                      lastPublishDate: self.lastHeartRatePublishDate,
                                      minInterval: self.heartRatePublishInterval) {
                    self.currentHeartRate = bpmValue
                    self.lastHeartRatePublishDate = now
                }
                if let totalKilocalories,
                   self.shouldPublish(at: now,
                                      lastPublishDate: self.lastCaloriesPublishDate,
                                      minInterval: self.caloriesPublishInterval) {
                    self.totalKilocalories = totalKilocalories
                    self.lastCaloriesPublishDate = now
                }
            }
        }
    }

    private func shouldPublish(at now: Date,
                               lastPublishDate: Date?,
                               minInterval: TimeInterval) -> Bool {
        guard let lastPublishDate else { return true }
        return now.timeIntervalSince(lastPublishDate) >= minInterval
    }
}

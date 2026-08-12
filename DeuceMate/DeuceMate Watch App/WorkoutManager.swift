import Foundation
import HealthKit
import DeuceMateCore

class WorkoutManager: NSObject, ObservableObject {
    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var finalizingBuilder: HKLiveWorkoutBuilder?

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
                self.refreshHealthAccess()
                completion(success)
            }
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
            session?.startActivity(with: startDate)
            builder?.beginCollection(withStart: startDate) { _, _ in }
            DispatchQueue.main.async { self.isRunning = true }
        } catch {
            // Non-fatal: app continues without workout session
        }
    }

    func stopWorkout() {
        guard isRunning else { return }
        finalizingBuilder = builder
        builder = nil
        session?.end()
        // Set synchronously — always called from main thread — so that a
        // subsequent startWorkout() call in the same turn sees isRunning = false.
        isRunning = false
        currentHeartRate = nil
        totalKilocalories = nil
        lastHeartRatePublishDate = nil
        lastCaloriesPublishDate = nil
    }

    /// Returns accumulated steps, distance, and calories from the current (or just-stopped) workout builder.
    /// Safe to call synchronously right after `stopWorkout()` — the builder retains statistics
    /// until `endCollection` is called asynchronously in the session delegate.
    func snapshotActivity() -> (steps: Int, distanceMeters: Double, caloriesKcal: Double)? {
        guard let b = finalizingBuilder ?? builder else { return nil }
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
        guard toState == .ended else { return }
        let b = finalizingBuilder
        finalizingBuilder = nil
        b?.endCollection(withEnd: date) { _, _ in
            b?.finishWorkout { _, _ in }
        }
    }
    func workoutSession(_ session: HKWorkoutSession, didFailWithError error: Error) {
        DispatchQueue.main.async { self.isRunning = false }
    }
}

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                        didCollectDataOf collectedTypes: Set<HKSampleType>) {
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
            if self.isRunning {
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

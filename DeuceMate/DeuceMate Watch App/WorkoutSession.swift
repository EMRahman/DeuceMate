import Foundation
import HealthKit
import DeuceMateCore

/// Only the HealthKit boundary is replaced in tests; the manager and finalizer stay real.
protocol WorkoutSessionStore {
    var healthAccess: HealthAccess { get }
    func requestAuthorization(completion: @escaping (Bool) -> Void)
    func makeSession() throws -> WorkoutRecordingSession
    func recoverSession(completion: @escaping (WorkoutRecordingSession?, Error?) -> Void)
}

protocol WorkoutRecordingSession: WorkoutFinalizationSession, WorkoutFinalizationBuilder {
    var observer: WorkoutRecordingObserver? { get set }
    var state: HKWorkoutSessionState { get }
    var startDate: Date? { get }
    var endDate: Date? { get }
    var measurements: WorkoutMeasurements { get }
    func startActivity(with date: Date)
    func beginCollection(at date: Date, completion: @escaping (Bool, Error?) -> Void)
}

protocol WorkoutRecordingObserver: AnyObject {
    func recordingSession(_ session: WorkoutRecordingSession, changedTo state: HKWorkoutSessionState, at date: Date)
    func recordingSession(_ session: WorkoutRecordingSession, failedWith error: Error)
    func recordingSession(_ session: WorkoutRecordingSession, collected measurements: WorkoutMeasurements)
}

struct WorkoutMeasurements {
    var heartRate: Double?
    var steps: Int?
    var distanceMeters: Double?
    var caloriesKcal: Double?
}

final class HealthKitWorkoutStore: WorkoutSessionStore {
    private let store = HKHealthStore()

    var healthAccess: HealthAccess {
        guard HKHealthStore.isHealthDataAvailable() else { return .unavailable }
        switch store.authorizationStatus(for: HKQuantityType.workoutType()) {
        case .sharingAuthorized: return .authorized
        case .sharingDenied: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else { completion(false); return }
        let read: Set<HKObjectType> = [HKQuantityType.workoutType(), HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned), HKQuantityType(.basalEnergyBurned),
            HKQuantityType(.stepCount), HKQuantityType(.distanceWalkingRunning)]
        store.requestAuthorization(toShare: [HKQuantityType.workoutType()], read: read) { success, _ in
            completion(success)
        }
    }

    func makeSession() throws -> WorkoutRecordingSession {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .tennis
        configuration.locationType = .indoor
        return HealthKitWorkoutSession(try HKWorkoutSession(healthStore: store, configuration: configuration), store: store)
    }

    func recoverSession(completion: @escaping (WorkoutRecordingSession?, Error?) -> Void) {
        store.recoverActiveWorkoutSession { [store] session, error in
            completion(session.map { HealthKitWorkoutSession($0, store: store) }, error)
        }
    }
}

/// Reattaches the same builder on recovery; never starts recovered collection again.
private final class HealthKitWorkoutSession: NSObject, WorkoutRecordingSession,
    HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    private let session: HKWorkoutSession
    private let builder: HKLiveWorkoutBuilder
    weak var observer: WorkoutRecordingObserver?
    var state: HKWorkoutSessionState { session.state }
    var startDate: Date? { session.startDate ?? builder.startDate }
    var endDate: Date? { session.endDate ?? builder.endDate }

    init(_ session: HKWorkoutSession, store: HKHealthStore) {
        self.session = session
        builder = session.associatedWorkoutBuilder()
        super.init()
        let source = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: session.workoutConfiguration)
        source.enableCollection(for: HKQuantityType(.stepCount), predicate: nil)
        source.enableCollection(for: HKQuantityType(.distanceWalkingRunning), predicate: nil)
        builder.dataSource = source
        session.delegate = self
        builder.delegate = self
    }

    var measurements: WorkoutMeasurements {
        func sum(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit) -> Double? {
            builder.statistics(for: HKQuantityType(identifier))?.sumQuantity()?.doubleValue(for: unit)
        }
        let heartRate = builder.statistics(for: HKQuantityType(.heartRate))?.mostRecentQuantity()?
            .doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        let active = sum(.activeEnergyBurned, unit: .kilocalorie())
        let basal = sum(.basalEnergyBurned, unit: .kilocalorie())
        return WorkoutMeasurements(heartRate: heartRate,
            steps: sum(.stepCount, unit: .count()).map { Int($0) },
            distanceMeters: sum(.distanceWalkingRunning, unit: .meter()),
            caloriesKcal: active == nil && basal == nil ? nil : (active ?? 0) + (basal ?? 0))
    }

    func startActivity(with date: Date) { session.startActivity(with: date) }
    func stopActivity(with date: Date?) { session.stopActivity(with: date) }
    func end() { session.end() }
    func beginCollection(at date: Date, completion: @escaping (Bool, Error?) -> Void) {
        builder.beginCollection(withStart: date, completion: completion)
    }
    func endCollection(withEnd date: Date, completion: @escaping @Sendable (Bool, Error?) -> Void) {
        // A recovered stopped builder may already have ended collection before the crash.
        if builder.endDate != nil { completion(true, nil) }
        else { builder.endCollection(withEnd: date, completion: completion) }
    }
    func finishSaving(completion: @escaping (Error?) -> Void) { builder.finishSaving(completion: completion) }

    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                        from fromState: HKWorkoutSessionState, date: Date) {
        observer?.recordingSession(self, changedTo: toState, at: date)
    }
    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        observer?.recordingSession(self, failedWith: error)
    }
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        observer?.recordingSession(self, collected: measurements)
    }
}

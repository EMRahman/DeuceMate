import Foundation
import HealthKit

protocol WorkoutFinalizationSession: AnyObject {
    func stopActivity(with date: Date?)
    func end()
}

protocol WorkoutFinalizationBuilder: AnyObject {
    func endCollection(withEnd date: Date, completion: @escaping (Bool, Error?) -> Void)
    func finishSaving(completion: @escaping (Error?) -> Void)
}

extension HKWorkoutSession: WorkoutFinalizationSession {}
extension HKLiveWorkoutBuilder: WorkoutFinalizationBuilder {
    func finishSaving(completion: @escaping (Error?) -> Void) {
        // A nil workout AND nil error is also success (e.g. device locked).
        finishWorkout { _, error in completion(error) }
    }
}

/// Retains each stopped session AND its builder until saving has completed.
/// HealthKit calls back on arbitrary queues; never hold the lock across its calls.
final class WorkoutFinalizer {
    private struct Pending {
        let session: WorkoutFinalizationSession
        let builder: WorkoutFinalizationBuilder
        var saving = false
    }
    private let lock = NSLock()
    private var pending: [ObjectIdentifier: Pending] = [:]
    private let reportFailure: (Error) -> Void

    init(reportFailure: @escaping (Error) -> Void) {
        self.reportFailure = reportFailure
    }

    func stop(session: WorkoutFinalizationSession, builder: WorkoutFinalizationBuilder, at date: Date) {
        let id = ObjectIdentifier(session)
        lock.lock()
        guard pending[id] == nil else { lock.unlock(); return }
        pending[id] = Pending(session: session, builder: builder)
        lock.unlock()
        session.stopActivity(with: date)
    }

    func didStop(session: WorkoutFinalizationSession, at date: Date) {
        let id = ObjectIdentifier(session)
        lock.lock()
        guard var item = pending[id], !item.saving else { lock.unlock(); return }
        item.saving = true
        pending[id] = item
        lock.unlock()
        item.builder.endCollection(withEnd: date) { [self] success, error in
            lock.lock()
            let stillPending = pending[id] != nil
            lock.unlock()
            guard stillPending else { return }
            guard success, error == nil else {
                complete(id: id, error: error ?? CocoaError(.fileWriteUnknown))
                return
            }
            item.builder.finishSaving { [self] error in
                complete(id: id, error: error)
            }
        }
    }

    @discardableResult
    func didFail(session: WorkoutFinalizationSession, error: Error) -> Bool {
        complete(id: ObjectIdentifier(session), error: error)
    }

    @discardableResult
    private func complete(id: ObjectIdentifier, error: Error?) -> Bool {
        lock.lock()
        let item = pending.removeValue(forKey: id)
        lock.unlock()
        guard let item else { return false }
        // Keep session mode until the HealthKit save callback, including failure.
        item.session.end()
        if let error { reportFailure(error) }
        return true
    }
}

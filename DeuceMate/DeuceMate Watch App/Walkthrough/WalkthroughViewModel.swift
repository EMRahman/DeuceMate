import Foundation
import DeuceMateCore

/// UI adapter cannot reach live scoring, stores, sync, workout or heading.
@MainActor
final class WalkthroughViewModel: ObservableObject {
    @Published private(set) var session = WalkthroughSession()
    @Published private(set) var isDisposed = false

    func beginExample() { guard !isDisposed else { return }; session.beginExample() }
    func restartCurrentExample() { guard !isDisposed else { return }; session.restartCurrentExample() }
    func advanceDemonstration(generation: UUID) {
        guard !isDisposed else { return }
        session.advanceDemonstration(generation: generation)
    }
    func advanceAfterResult() { guard !isDisposed else { return }; session.advanceAfterResult() }
    // Retained for deterministic adapter tests; the guide UI advances itself.
    func next() { guard !isDisposed else { return }; session.next() }
    func previous() { guard !isDisposed else { return }; session.previous() }
    func dispose() { isDisposed = true; session = WalkthroughSession() }
}

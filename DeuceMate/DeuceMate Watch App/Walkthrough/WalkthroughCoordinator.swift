import Foundation

/// Owns exactly two watch-local flags. No production match dependencies.
final class WalkthroughCoordinator: ObservableObject {
    static let version = 1
    static let offerKey = "walkthroughOfferSeenVersion"
    static let completedKey = "walkthroughCompletedVersion"
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func shouldOffer(launchReady: Bool, stateReadSucceeded: Bool,
                     historyCount: Int?, idle: Bool, modalActive: Bool) -> Bool {
        launchReady && stateReadSucceeded && historyCount == 0 && idle && !modalActive
            && defaults.integer(forKey: Self.offerKey) == 0
            && defaults.integer(forKey: Self.completedKey) == 0
    }
    func markSeen() { defaults.set(Self.version, forKey: Self.offerKey) }
    func complete() {
        markSeen()
        defaults.set(Self.version, forKey: Self.completedKey)
    }
}

import Foundation
import DeuceMateCore
import Testing
@testable import DeuceMate_Watch_App

@MainActor
struct WalkthroughWatchTests {
    private func defaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "walkthrough-test-\(UUID().uuidString)"))
    }
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("walkthrough-\(UUID().uuidString).json")
    }
    @Test func offerRequiresSuccessfulReadsReadyIdleAndNoModal() throws {
        let c = WalkthroughCoordinator(defaults: try defaults())
        #expect(c.shouldOffer(launchReady: true, stateReadSucceeded: true, historyCount: 0, idle: true, modalActive: false))
        #expect(!c.shouldOffer(launchReady: false, stateReadSucceeded: true, historyCount: 0, idle: true, modalActive: false))
        #expect(!c.shouldOffer(launchReady: true, stateReadSucceeded: false, historyCount: 0, idle: true, modalActive: false))
        #expect(!c.shouldOffer(launchReady: true, stateReadSucceeded: true, historyCount: nil, idle: true, modalActive: false))
        #expect(!c.shouldOffer(launchReady: true, stateReadSucceeded: true, historyCount: 1, idle: true, modalActive: false))
        #expect(!c.shouldOffer(launchReady: true, stateReadSucceeded: true, historyCount: 0, idle: false, modalActive: false))
        #expect(!c.shouldOffer(launchReady: true, stateReadSucceeded: true, historyCount: 0, idle: true, modalActive: true))
    }
    @Test func skipDismissExitAndCompletionOnlyWriteTheirOwnFlags() throws {
        let d = try defaults()
        d.set(false, forKey: "statsTrackingEnabled")
        d.set("quick4Games", forKey: MatchSetupDefaults.formatKey)
        d.set(false, forKey: "hasCompletedFirstGame")
        let baseline = d.dictionaryRepresentation()
        let c = WalkthroughCoordinator(defaults: d)
        c.markSeen() // Not now, interactive dismissal, Guide launch and exit share this operation.
        #expect(d.integer(forKey: WalkthroughCoordinator.offerKey) == 1)
        #expect(d.integer(forKey: WalkthroughCoordinator.completedKey) == 0)
        #expect(!c.shouldOffer(launchReady: true, stateReadSucceeded: true, historyCount: 0, idle: true, modalActive: false))
        c.complete()
        #expect(d.integer(forKey: WalkthroughCoordinator.completedKey) == 1)
        for (key, value) in baseline {
            #expect(String(describing: d.object(forKey: key)) == String(describing: Optional(value)))
        }
        #expect(Set(d.dictionaryRepresentation().keys).subtracting(baseline.keys) ==
                [WalkthroughCoordinator.offerKey, WalkthroughCoordinator.completedKey])
        d.set(1, forKey: WalkthroughCoordinator.offerKey) // Earlier content versions never force another offer.
        #expect(!c.shouldOffer(launchReady: true, stateReadSucceeded: true, historyCount: 0, idle: true, modalActive: false))
    }
    @Test func restoreDistinguishesAbsentCorruptAndValidState() throws {
        let url = tempURL()
        let vm = ScoreViewModel(statsStore: StatsStore(fileURL: tempURL()), stateFileURL: url, userDefaults: try defaults())
        vm.loadState()
        #expect(vm.stateRestorationSucceeded)
        #expect(vm.walkthroughIsIdle)
        try Data("broken JSON".utf8).write(to: url)
        vm.loadState()
        #expect(!vm.stateRestorationSucceeded)
        vm.currentServer = .me
        vm.currentPointsMe = 1
        vm.saveState()
        let restored = ScoreViewModel(statsStore: StatsStore(fileURL: tempURL()), stateFileURL: url, userDefaults: try defaults())
        restored.loadState()
        #expect(restored.stateRestorationSucceeded)
        #expect(!restored.walkthroughIsIdle)
        #expect(restored.currentPointsMe == 1)
        #expect(restored.currentServer == .me)
    }
    @Test func warmupAndPendingPointPreventEntry() throws {
        let vm = ScoreViewModel(statsStore: StatsStore(fileURL: tempURL()), stateFileURL: tempURL(), userDefaults: try defaults())
        #expect(vm.walkthroughIsIdle)
        vm.sessionStartTime = Date()
        #expect(!vm.walkthroughIsIdle)
        vm.sessionStartTime = nil
        vm.pendingStatPoint = PendingPointInfo(server: .me, winner: .opponent, setIndex: 0, isSecondServe: false)
        #expect(!vm.walkthroughIsIdle)
        vm.pendingStatPoint = nil
        vm.currentServer = .opponent
        #expect(!vm.walkthroughIsIdle)
    }
    @Test func navigationAndExitRejectDelayedAnimationCallbacks() {
        let m = WalkthroughViewModel()
        let old = m.session.generation
        m.beginExample()
        #expect(m.session.phase == .gesture)
        m.next()
        m.advanceDemonstration(generation: old)
        #expect(m.session.step == .losePoint)
        #expect(m.session.phase == .situation)
        let current = m.session.generation
        m.previous()
        m.advanceDemonstration(generation: current)
        #expect(m.session.step == .winPoint)
        #expect(m.session.state.currentPointsMe == 0)
        m.dispose()
        let disposedState = m.session.state
        m.advanceDemonstration(generation: m.session.generation)
        m.advanceDemonstration(generation: old)
        m.beginExample(); m.restartCurrentExample()
        m.next(); m.previous()
        #expect(m.session.state == disposedState)
        #expect(m.isDisposed)
    }
    @Test func guideLeavesProductionStateStoresSettingsAndSensorsAtBaseline() throws {
        let archive = tempURL()
        let stateURL = tempURL()
        let d = try defaults()
        let store = PracticeStoreSpy()
        let sync = PracticeSyncSpy()
        let live = ScoreViewModel(statsStore: store, stateFileURL: stateURL, userDefaults: d)
        live.syncService = sync
        let storeBaseline = store.calls
        let syncBaseline = sync.calls
        let tracking = live.statsTrackingEnabled
        let detailedTracking = live.detailedShotTrackingEnabled
        let changeoverSetting = live.checkChangeover
        let theme = live.selectedTheme
        let sets = live.sets
        let settings = d.dictionaryRepresentation()
        let workout = live.workoutManager.isRunning
        let heading = live.currentDeviceHeading
        let practice = WalkthroughViewModel()
        for step in WalkthroughStep.allCases {
            #expect(practice.session.step == step)
            practice.beginExample()
            for _ in 0..<10 where !practice.session.demonstrationFinished {
                practice.advanceDemonstration(generation: practice.session.generation)
            }
            #expect(practice.session.demonstrationFinished)
            practice.next()
        }
        practice.dispose()
        #expect(store.calls == storeBaseline)
        #expect(sync.calls == syncBaseline)
        #expect(live.statsTrackingEnabled == tracking)
        #expect(live.detailedShotTrackingEnabled == detailedTracking)
        #expect(live.checkChangeover == changeoverSetting)
        #expect(live.selectedTheme == theme)
        #expect(live.sets == sets)
        #expect(live.currentServer == nil)
        #expect(live.currentMatchStats.isEmpty)
        #expect(live.history.isEmpty)
        #expect(live.pendingStatPoint == nil)
        #expect(live.matchStartTime == nil)
        #expect(live.workoutManager.isRunning == workout)
        #expect(live.currentDeviceHeading == heading)
        #expect(!FileManager.default.fileExists(atPath: archive.path))
        #expect(!FileManager.default.fileExists(atPath: stateURL.path))
        #expect(NSDictionary(dictionary: d.dictionaryRepresentation()).isEqual(to: settings))
    }
}


private final class PracticeStoreSpy: StatsStoring {
    var calls = 0
    func loadHistory() -> [MatchRecord] { calls += 1; return [] }
    func saveHistory(_ records: [MatchRecord]) { calls += 1 }
    func appendMatch(_ record: MatchRecord) { calls += 1 }
    func removeMatch(id: UUID) { calls += 1 }
}

private final class PracticeSyncSpy: MatchSyncService {
    var calls = 0
    var lastSyncDate: Date? { nil }
    func start() { calls += 1 }
    func sendMatch(_ record: MatchRecord, announcement: String?) { calls += 1 }
    func sendFullHistory(_ records: [MatchRecord]) { calls += 1 }
    func clearActiveMatch() { calls += 1 }
    func sendPendingPointState(_ pending: PendingPointInfo?, outcome: PointOutcome?) { calls += 1 }
}

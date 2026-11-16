import Foundation
import DeuceMateCore
import Testing
@testable import DeuceMate_Watch_App

@MainActor
struct LiveMatchWatchTests {
    private final class Files {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        init() throws { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        func url(_ name: String) -> URL { directory.appendingPathComponent(name) }
        deinit { try? FileManager.default.removeItem(at: directory) }
    }
    private final class Workout: WorkoutManager {
        override func startWorkout(startDate: Date) {}
        override func stopWorkout() {}
    }
    private final class SyncSpy: MatchSyncService {
        var lastSyncDate: Date? { nil }
        var onSendMatch: ((MatchRecord) -> Void)?
        func start() {}
        func sendMatch(_ record: MatchRecord, announcement: String?) { onSendMatch?(record) }
        func sendFullHistory(_ records: [MatchRecord]) {}
        func clearActiveMatch() {}
    }
    private func model(_ files: Files, scoreFirstPoint: Bool = true) -> ScoreViewModel {
        let vm = ScoreViewModel(statsStore: StatsStore(fileURL: files.url("history.json")),
            stateFileURL: files.url("state.json"), workoutManager: Workout())
        vm.loadState()
        vm.iPhoneInputEnabled = true
        vm.statsTrackingEnabled = false
        vm.detailedShotTrackingEnabled = false
        vm.matchFormat = .standard
        vm.matchType = .singles
        vm.currentServer = .me
        if scoreFirstPoint { vm.winPoint(player: .me) }
        return vm
    }

    private func doublesGameAwaitingCategory(_ files: Files) -> ScoreViewModel {
        let vm = model(files, scoreFirstPoint: false)
        vm.startDoublesMatch(firstServer: .opponentS1)
        for _ in 0..<3 { vm.winPoint(player: .me) }
        vm.statsTrackingEnabled = true
        vm.winPoint(player: .me)
        return vm
    }

    @Test func acknowledgingChangeoverSavesAndPublishesUnlockedStateWithoutAnotherPoint() throws {
        let files = try Files(), vm = model(files)
        for _ in 0..<3 { vm.winPoint(player: .me) }
        #expect(vm.pendingChangeoverAck != nil)
        #expect(vm.handleLiveRequest(LiveMatchRequest()).state?.blockingReason != nil)
        let points = vm.currentMatchStats
        let spy = SyncSpy()
        var published: [LiveMatchState] = []
        spy.onSendMatch = { [weak vm] _ in
            if let state = vm?.handleLiveRequest(LiveMatchRequest()).state { published.append(state) }
        }
        vm.syncService = spy

        vm.acknowledgeChangeover()

        #expect(published.count == 1, "Acknowledgement must trigger the service's live-state publication path")
        let state = try #require(published.last)
        #expect(state.blockingReason == nil)
        #expect(LiveScoreboardStatus(isWatchReachable: true, isInputEnabled: state.inputEnabled,
            isStateConfirmed: true, blockingReason: state.blockingReason).acceptsInput)
        #expect(vm.currentMatchStats == points, "No additional scoring is needed to release input")
        let saved = try JSONDecoder().decode(ScoreViewModel.AppState.self, from: Data(contentsOf: files.url("state.json")))
        #expect(saved.pendingAnnouncementMessage == nil)
        #expect(saved.pendingAnnouncementReason == nil)
        #expect(saved.gameCount == 1)
    }

    @Test func doublesPendingCategoryAllowsSelectionBackAndCommitBeforeServerDecision() throws {
        let files = try Files(), vm = doublesGameAwaitingCategory(files)
        #expect(vm.gameCount == 1)
        #expect(vm.needsDoublesTeamServerDecision)
        let pending = try #require(vm.pendingStatPoint)
        let state = try #require(vm.handleLiveRequest(LiveMatchRequest()).state)
        #expect(state.blockingReason == nil, "The phone category panel must remain actionable")
        let blockedScore = vm.handleLiveRequest(LiveMatchRequest(action: MatchSyncKey.scoreCommandWinMe,
            matchID: vm.currentMatchID))
        #expect(blockedScore.message != nil)
        #expect(vm.pendingStatPoint == pending)
        #expect(vm.currentPointsMe == 0)

        let picked = vm.handleLiveRequest(LiveMatchRequest(action: MatchSyncKey.statActionSelectOutcome,
            matchID: vm.currentMatchID, outcome: .winner, pendingPoint: pending))
        #expect(picked.message == nil)
        #expect(picked.state?.pendingOutcome == .winner)
        let back = vm.handleLiveRequest(LiveMatchRequest(action: MatchSyncKey.statActionCancelOutcomeSelection,
            matchID: vm.currentMatchID, pendingPoint: pending, pendingOutcome: .winner))
        #expect(back.message == nil)
        #expect(back.state?.pendingOutcome == nil)
        let repicked = vm.handleLiveRequest(LiveMatchRequest(action: MatchSyncKey.statActionSelectOutcome,
            matchID: vm.currentMatchID, outcome: .winner, pendingPoint: pending))
        #expect(repicked.message == nil)
        let committed = vm.handleLiveRequest(LiveMatchRequest(action: MatchSyncKey.statActionCommitEndingShot,
            matchID: vm.currentMatchID, endingShot: .rally, pendingPoint: pending, pendingOutcome: .winner))
        #expect(committed.message == nil)
        #expect(vm.pendingStatPoint == nil)
        #expect(vm.currentMatchStats.last?.outcome == .winner)
        #expect(vm.needsDoublesTeamServerDecision)
        #expect(committed.state?.blockingReason != nil, "Next-point input still requires the Watch decision")
        #expect(vm.handleLiveRequest(LiveMatchRequest(action: MatchSyncKey.scoreCommandWinMe,
            matchID: vm.currentMatchID)).message != nil)
    }

    @Test func doublesPendingPointCanBeUndoneBeforeServerDecision() throws {
        let files = try Files(), vm = doublesGameAwaitingCategory(files)
        let pending = try #require(vm.pendingStatPoint)
        let reply = vm.handleLiveRequest(LiveMatchRequest(action: MatchSyncKey.statActionUndoPoint,
            matchID: vm.currentMatchID, pendingPoint: pending))
        #expect(reply.message == nil)
        #expect(vm.pendingStatPoint == nil)
        #expect(vm.gameCount == 0)
        #expect(vm.currentPointsMe == 3)
        #expect(vm.currentServer == .opponent)
        #expect(reply.state?.blockingReason == nil)
    }

    @Test func refreshReturnsCurrentLiveScoreWithoutWritingOrAddingSessionEvents() throws {
        let files = try Files(), vm = model(files)
        vm.winPoint(player: .opponent)
        let before = try Data(contentsOf: files.url("state.json"))
        let events = vm.resumeEvents
        let reply = vm.handleLiveRequest(LiveMatchRequest())
        #expect(reply.state?.record?.currentPointsMe == 1)
        #expect(reply.state?.record?.currentPointsOpponent == 1)
        #expect(reply.state?.record?.stats.isEmpty == true)
        #expect(vm.resumeEvents == events)
        #expect(try Data(contentsOf: files.url("state.json")) == before)
    }

    @Test func commandIsAppliedSavedAndReturnedByTheWatch() throws {
        let files = try Files(), vm = model(files)
        let reply = vm.handleLiveRequest(LiveMatchRequest(action: MatchSyncKey.scoreCommandWinMe, matchID: vm.currentMatchID))
        #expect(reply.message == nil)
        #expect(reply.state?.record?.currentPointsMe == 2)
        let saved = try JSONDecoder().decode(ScoreViewModel.AppState.self, from: Data(contentsOf: files.url("state.json")))
        #expect(saved.currentPointsMe == 2)
        let wrongMatch = vm.handleLiveRequest(LiveMatchRequest(action: MatchSyncKey.scoreCommandWinMe, matchID: UUID()))
        #expect(wrongMatch.message != nil)
        #expect(vm.currentPointsMe == 2)
    }

    @Test func pendingCategoryGuardAndPhaseSurviveAcknowledgementAndRelaunch() throws {
        let files = try Files(), vm = model(files)
        vm.statsTrackingEnabled = true
        vm.detailedShotTrackingEnabled = true
        vm.winPoint(player: .opponent)
        let pending = try #require(vm.pendingStatPoint)
        let blocked = vm.handleLiveRequest(LiveMatchRequest(action: MatchSyncKey.scoreCommandWinMe, matchID: vm.currentMatchID))
        #expect(blocked.message != nil)
        let picked = vm.handleLiveRequest(LiveMatchRequest(action: MatchSyncKey.statActionSelectOutcome,
            matchID: vm.currentMatchID, outcome: .winner, pendingPoint: pending))
        #expect(picked.message == nil)
        #expect(picked.state?.pendingOutcome == .winner)
        let restored = ScoreViewModel(statsStore: StatsStore(fileURL: files.url("history.json")),
            stateFileURL: files.url("state.json"), workoutManager: Workout())
        restored.loadState()
        #expect(restored.pendingOutcome == .winner)
        let stale = vm.handleLiveRequest(LiveMatchRequest(action: MatchSyncKey.statActionCommitEndingShot,
            matchID: UUID(), endingShot: .rally, pendingPoint: pending, pendingOutcome: .winner))
        #expect(stale.message != nil)
        #expect(vm.pendingStatPoint != nil)
        let committed = vm.handleLiveRequest(LiveMatchRequest(action: MatchSyncKey.statActionCommitEndingShot,
            matchID: vm.currentMatchID, endingShot: .rally, pendingPoint: pending, pendingOutcome: .winner))
        #expect(committed.message == nil)
        #expect(committed.state?.pendingPoint == nil)
        #expect(vm.currentMatchStats.last?.outcome == .winner)
    }

    @Test func unreadableStateDoesNotReportIdleOrAcceptCommands() throws {
        let files = try Files()
        let bytes = Data("unreadable saved match".utf8)
        try bytes.write(to: files.url("state.json"))
        let vm = ScoreViewModel(stateFileURL: files.url("state.json"), workoutManager: Workout())
        vm.loadState()
        let reply = vm.handleLiveRequest(LiveMatchRequest())
        #expect(reply.state == nil)
        #expect(reply.message != nil)
        #expect(try Data(contentsOf: files.url("state.json")) == bytes)
    }

    @Test(arguments: [false, true])
    func failedSaveCannotAcknowledgeSuccessfulApplication(tracking: Bool) throws {
        let files = try Files()
        final class Failure { var enabled = false }
        let failure = Failure()
        let vm = ScoreViewModel(statsStore: StatsStore(fileURL: files.url("history.json")),
            stateFileURL: files.url("state.json"), writeLiveState: { state, target in
                if failure.enabled { throw CocoaError(.fileWriteOutOfSpace) }
                try BackupExcludedFileWriter.write(state, to: target)
            }, workoutManager: Workout())
        vm.loadState()
        vm.iPhoneInputEnabled = true
        vm.statsTrackingEnabled = false
        vm.matchFormat = .standard
        vm.matchType = .singles
        vm.currentServer = .me
        vm.winPoint(player: .me)
        let saved = try Data(contentsOf: files.url("state.json"))
        vm.statsTrackingEnabled = tracking
        failure.enabled = true
        let reply = vm.handleLiveRequest(LiveMatchRequest(action: MatchSyncKey.scoreCommandWinMe, matchID: vm.currentMatchID))
        #expect(reply.message != nil)
        #expect(reply.state?.blockingReason != nil)
        #expect(try Data(contentsOf: files.url("state.json")) == saved)
        if tracking {
            let pending = try #require(vm.pendingStatPoint)
            let category = vm.handleLiveRequest(LiveMatchRequest(action: MatchSyncKey.statActionSelectOutcome,
                matchID: vm.currentMatchID, outcome: .winner, pendingPoint: pending))
            #expect(category.message != nil, "Pending categories must not bypass a persistence error")
            #expect(vm.pendingOutcome == nil)
            #expect(try Data(contentsOf: files.url("state.json")) == saved)
        }
    }

    @Test func olderLiveFilesDefaultTheNewPendingPhaseToNil() throws {
        let files = try Files(), vm = model(files)
        _ = vm
        let bytes = try Data(contentsOf: files.url("state.json"))
        var json = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        json.removeValue(forKey: "pendingOutcome")
        let legacy = try JSONDecoder().decode(ScoreViewModel.AppState.self,
            from: JSONSerialization.data(withJSONObject: json))
        #expect(legacy.pendingOutcome == nil)
    }
}

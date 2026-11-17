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
        var liveStateChanges = 0
        func start() {}
        func liveStateDidChange() { liveStateChanges += 1 }
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

    @Test(arguments: [false, true], [false, true])
    func watchPhaseChangesSurviveRelaunch(startOnPhone: Bool, backOnly: Bool) throws {
        let files = try Files(), vm = model(files)
        vm.statsTrackingEnabled = true
        vm.winPoint(player: .opponent)
        let pending = try #require(vm.pendingStatPoint)
        let points = vm.currentMatchStats
        if startOnPhone {
            let reply = vm.handleLiveRequest(LiveMatchRequest(action: MatchSyncKey.statActionSelectOutcome,
                matchID: vm.currentMatchID, outcome: .winner, pendingPoint: pending))
            #expect(reply.message == nil)
        } else {
            vm.selectOutcome(.winner)
            let selected = try JSONDecoder().decode(ScoreViewModel.AppState.self,
                from: Data(contentsOf: files.url("state.json")))
            #expect(selected.pendingOutcome == .winner)
        }

        // These are the direct Watch sheet calls, with no phone handler or
        // background save to hide an unsaved phase change.
        vm.cancelOutcomeSelection()
        if !backOnly { vm.selectOutcome(.unforcedError) }
        let expected: PointOutcome? = backOnly ? nil : .unforcedError
        let saved = try JSONDecoder().decode(ScoreViewModel.AppState.self,
            from: Data(contentsOf: files.url("state.json")))
        #expect(saved.pendingOutcome == expected)
        let restored = ScoreViewModel(statsStore: StatsStore(fileURL: files.url("history.json")),
            stateFileURL: files.url("state.json"), workoutManager: Workout())
        restored.loadState()
        #expect(restored.pendingOutcome == expected)
        #expect(restored.pendingStatPoint == pending)
        #expect(restored.currentMatchID == vm.currentMatchID)
        #expect(restored.currentPointsMe == vm.currentPointsMe)
        #expect(restored.currentPointsOpponent == vm.currentPointsOpponent)
        #expect(restored.currentMatchStats == points)
        if !backOnly {
            restored.commitEndingShot(.rally)
            #expect(restored.currentMatchStats.last?.outcome == .unforcedError)
            #expect(restored.pendingStatPoint == nil)
        }
    }

    @Test(arguments: [false, true])
    func phaseSaveFailureRejectsPhoneAcknowledgementWithoutRetry(back: Bool) throws {
        let files = try Files()
        final class Writes { var failNext = false; var attempts = 0 }
        let writes = Writes()
        let vm = ScoreViewModel(statsStore: StatsStore(fileURL: files.url("history.json")),
            stateFileURL: files.url("state.json"), writeLiveState: { state, target in
                writes.attempts += 1
                if writes.failNext {
                    writes.failNext = false
                    throw CocoaError(.fileWriteOutOfSpace)
                }
                try BackupExcludedFileWriter.write(state, to: target)
            }, workoutManager: Workout())
        vm.loadState()
        vm.iPhoneInputEnabled = true
        vm.statsTrackingEnabled = true
        vm.matchType = .singles
        vm.matchFormat = .standard
        vm.currentServer = .me
        vm.winPoint(player: .me)
        let pending = try #require(vm.pendingStatPoint)
        if back { vm.selectOutcome(.winner) }
        let saved = try Data(contentsOf: files.url("state.json"))
        let attempts = writes.attempts
        writes.failNext = true
        let reply = vm.handleLiveRequest(LiveMatchRequest(
            action: back ? MatchSyncKey.statActionCancelOutcomeSelection : MatchSyncKey.statActionSelectOutcome,
            matchID: vm.currentMatchID, outcome: back ? nil : .winner,
            pendingPoint: pending, pendingOutcome: back ? .winner : nil))
        #expect(reply.message != nil)
        #expect(reply.state?.blockingReason != nil)
        #expect(writes.attempts == attempts + 1, "The phone handler must not retry or mask a failed shared save")
        #expect(try Data(contentsOf: files.url("state.json")) == saved)
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

    // MARK: - Watch prompts answered from the iPhone

    /// Singles, first game just won (odd games): the changeover screen is up.
    private func changeoverShowing(_ files: Files) throws -> (ScoreViewModel, LiveWatchPrompt) {
        let vm = model(files)
        for _ in 0..<3 { vm.winPoint(player: .me) }
        let prompt = try #require(vm.handleLiveRequest(LiveMatchRequest()).state?.prompt)
        return (vm, prompt)
    }

    /// Doubles, opponents served first and the game just ended: "Who serves
    /// next?" and the odd-games changeover are both open on the Watch.
    private func doublesDecisionShowing(_ files: Files) -> ScoreViewModel {
        let vm = model(files, scoreFirstPoint: false)
        vm.startDoublesMatch(firstServer: .opponentS1)
        for _ in 0..<4 { vm.winPoint(player: .me) }
        return vm
    }

    private func answer(_ vm: ScoreViewModel, _ prompt: LiveWatchPrompt, _ index: Int = 0) -> LiveMatchReply {
        vm.handleLiveRequest(prompt.request(for: prompt.answers[index], matchID: vm.currentMatchID))
    }

    @Test func changeoverIsSentToThePhoneAsAnAnswerablePrompt() throws {
        let files = try Files()
        let (vm, prompt) = try changeoverShowing(files)
        let info = try #require(vm.pendingChangeoverAck)
        #expect(prompt == LiveWatchPrompt.changeover(symbol: info.symbol, reason: info.reason).occurring(info.id))
        #expect(prompt.answers.map(\.label) == ["OK"])
        let state = try #require(vm.handleLiveRequest(LiveMatchRequest()).state)
        #expect(state.blockingReason != nil, "Older phones still see the text fallback")
        #expect(!LiveScoreboardStatus(isWatchReachable: true, isInputEnabled: state.inputEnabled,
            blockingReason: state.blockingReason, prompt: state.prompt).acceptsInput)
        #expect(LiveScoreboardStatus(isWatchReachable: true, isInputEnabled: state.inputEnabled,
            blockingReason: state.blockingReason, prompt: state.prompt).acceptsPromptAnswer)
    }

    @Test func phoneOKClearsTheWatchChangeoverSavesAndPublishes() throws {
        let files = try Files()
        let (vm, prompt) = try changeoverShowing(files)
        let points = vm.currentMatchStats
        let spy = SyncSpy()
        var published: [LiveMatchState] = []
        spy.onSendMatch = { [weak vm] _ in
            if let state = vm?.handleLiveRequest(LiveMatchRequest()).state { published.append(state) }
        }
        vm.syncService = spy

        let reply = answer(vm, prompt)

        #expect(reply.message == nil)
        #expect(vm.pendingChangeoverAck == nil, "The Watch overlay is bound to this, so it closes too")
        #expect(reply.state?.prompt == nil)
        #expect(reply.state?.blockingReason == nil)
        #expect(published.last?.prompt == nil, "The Watch pushes the cleared state to every listener")
        #expect(vm.currentMatchStats == points, "Answering never scores")
        let saved = try JSONDecoder().decode(ScoreViewModel.AppState.self, from: Data(contentsOf: files.url("state.json")))
        #expect(saved.pendingAnnouncementMessage == nil)
        let next = vm.handleLiveRequest(LiveMatchRequest(action: MatchSyncKey.scoreCommandWinMe, matchID: vm.currentMatchID))
        #expect(next.message == nil, "Scoring resumes from the phone straight away")
    }

    @Test func watchOKClearsThePhonePrompt() throws {
        let files = try Files()
        let (vm, _) = try changeoverShowing(files)
        vm.acknowledgeChangeover()
        let state = try #require(vm.handleLiveRequest(LiveMatchRequest()).state)
        #expect(state.prompt == nil)
        #expect(state.blockingReason == nil)
    }

    @Test func staleOrMismatchedPromptAnswersAreRefused() throws {
        let files = try Files()
        let (vm, prompt) = try changeoverShowing(files)
        let other = LiveWatchPrompt.changeover(symbol: "🔁 👥", reason: "A different changeover")
        let stale = vm.handleLiveRequest(other.request(for: other.answers[0], matchID: vm.currentMatchID))
        #expect(stale.message != nil)
        #expect(vm.pendingChangeoverAck != nil)

        let wrongMatch = vm.handleLiveRequest(prompt.request(for: prompt.answers[0], matchID: UUID()))
        #expect(wrongMatch.message != nil)
        #expect(vm.pendingChangeoverAck != nil)

        let noPrompt = vm.handleLiveRequest(LiveMatchRequest(
            action: MatchSyncKey.promptActionAcknowledgeChangeover, matchID: vm.currentMatchID))
        #expect(noPrompt.message != nil)
        #expect(vm.pendingChangeoverAck != nil)

        let wrongAction = vm.handleLiveRequest(LiveMatchRequest(action: MatchSyncKey.promptActionChooseDoublesServer,
            matchID: vm.currentMatchID, prompt: prompt, doublesServer: .me))
        #expect(wrongAction.message != nil)
        #expect(vm.pendingChangeoverAck != nil)

        // Already answered on the Watch: a late phone tap does nothing.
        vm.acknowledgeChangeover()
        let late = answer(vm, prompt)
        #expect(late.message != nil)
        #expect(vm.pendingChangeoverAck == nil)
    }

    @Test func lateAnswerCannotCloseALaterChangeoverWithTheSameWords() throws {
        let files = try Files()
        let (vm, earlier) = try changeoverShowing(files)
        // Undo the game-ending point and play it again: the same reminder
        // reopens, word for word, but it is a new screen.
        vm.undo()
        vm.winPoint(player: .me)
        let current = try #require(vm.handleLiveRequest(LiveMatchRequest()).state?.prompt)
        #expect(current.title == earlier.title && current.detail == earlier.detail)
        #expect(current != earlier)

        let late = answer(vm, earlier)
        #expect(late.message != nil, "An answer to the earlier reminder must not close this one")
        #expect(vm.pendingChangeoverAck != nil)
        #expect(late.state?.prompt == current)

        #expect(answer(vm, current).message == nil)
        #expect(vm.pendingChangeoverAck == nil)
    }

    @Test func lateDoublesAnswerCannotSettleAReplayedDecision() throws {
        let files = try Files(), vm = doublesDecisionShowing(files)
        let earlier = try #require(vm.handleLiveRequest(LiveMatchRequest()).state?.prompt)
        vm.undo()
        #expect(vm.handleLiveRequest(LiveMatchRequest()).state?.prompt == nil, "Game one is not over yet")
        vm.winPoint(player: .me)
        let current = try #require(vm.handleLiveRequest(LiveMatchRequest()).state?.prompt)
        #expect(current.kind == .doublesServer)
        #expect(current != earlier)

        #expect(answer(vm, earlier, 1).message != nil)
        #expect(vm.needsDoublesTeamServerDecision)
        #expect(answer(vm, current, 1).message == nil)
        #expect(vm.doublesServer == .partner)
    }

    @Test func promptAnswersNeedIPhoneInput() throws {
        let files = try Files()
        let (vm, prompt) = try changeoverShowing(files)
        vm.iPhoneInputEnabled = false
        let reply = answer(vm, prompt)
        #expect(reply.message != nil)
        #expect(vm.pendingChangeoverAck != nil)
        #expect(reply.state?.prompt == prompt, "Spectators still see what the Watch is asking")
    }

    @Test func doublesServerDecisionComesFirstThenTheChangeover() throws {
        let files = try Files(), vm = doublesDecisionShowing(files)
        #expect(vm.needsDoublesTeamServerDecision)
        #expect(vm.pendingChangeoverAck != nil)
        let first = try #require(vm.handleLiveRequest(LiveMatchRequest()).state?.prompt)
        #expect(first.kind == .doublesServer, "The Watch draws this overlay on top")

        let chosen = answer(vm, first, 1) // Partner
        #expect(chosen.message == nil)
        #expect(!vm.needsDoublesTeamServerDecision)
        #expect(vm.doublesServer == .partner)
        #expect(vm.doublesServiceOrder == [.opponentS1, .partner, .opponentS2, .me])
        #expect(vm.currentServer == .me)
        let saved = try JSONDecoder().decode(ScoreViewModel.AppState.self, from: Data(contentsOf: files.url("state.json")))
        #expect(saved.needsDoublesTeamServerDecision == false)

        let second = try #require(chosen.state?.prompt)
        #expect(second.kind == .changeover, "The changeover underneath is next, on both devices")
        #expect(answer(vm, second).message == nil)
        #expect(vm.pendingChangeoverAck == nil)
    }

    @Test func doublesChoiceOfMeKeepsTheProvisionalRotation() throws {
        let files = try Files(), vm = doublesDecisionShowing(files)
        let prompt = try #require(vm.handleLiveRequest(LiveMatchRequest()).state?.prompt)
        #expect(answer(vm, prompt, 0).message == nil)
        #expect(vm.doublesServer == .me)
        #expect(vm.doublesServiceOrder == [.opponentS1, .me, .opponentS2, .partner])
    }

    @Test func doublesAnswerRejectsAnOpponentAsTheNextServer() throws {
        let files = try Files(), vm = doublesDecisionShowing(files)
        let prompt = try #require(vm.handleLiveRequest(LiveMatchRequest()).state?.prompt)
        let reply = vm.handleLiveRequest(LiveMatchRequest(action: MatchSyncKey.promptActionChooseDoublesServer,
            matchID: vm.currentMatchID, prompt: prompt, doublesServer: .opponentS2))
        #expect(reply.message != nil)
        #expect(vm.needsDoublesTeamServerDecision)
    }

    @Test func noPromptWhileAPointAwaitsItsCategory() throws {
        let files = try Files(), vm = doublesGameAwaitingCategory(files)
        #expect(vm.needsDoublesTeamServerDecision)
        #expect(vm.handleLiveRequest(LiveMatchRequest()).state?.prompt == nil,
                "The category panel comes first, as on the Watch")
    }

    @Test func deferredChangeoverIsPublishedWhenItAppears() async throws {
        let files = try Files(), vm = model(files, scoreFirstPoint: false)
        vm.statsTrackingEnabled = true
        let spy = SyncSpy()
        vm.syncService = spy
        for _ in 0..<4 {
            vm.winPoint(player: .me)
            vm.commitPointStat(outcome: .winner, endingShot: nil)
        }
        // The Watch waits for its category sheet to close before showing the
        // changeover; until then there is nothing for the phone to answer.
        #expect(vm.isChangeoverPending)
        #expect(vm.handleLiveRequest(LiveMatchRequest()).state?.prompt == nil)
        let before = spy.liveStateChanges
        try await Task.sleep(for: .milliseconds(700))
        #expect(vm.pendingChangeoverAck != nil)
        #expect(spy.liveStateChanges > before, "The phone must hear the prompt without waiting for a point")
        #expect(vm.handleLiveRequest(LiveMatchRequest()).state?.prompt?.kind == .changeover)
    }

    @Test func watchSyncUpdatesApplicationContextOfflineAndSkipsDuplicates() async throws {
        final class RecordingSession: MatchSyncSessing {
            var isActivated = true
            var isReachable = false
            private(set) var sentMessages: [[String: Any]] = []
            private(set) var queuedUserInfos: [[String: Any]] = []
            private(set) var applicationContexts: [[String: Any]] = []
            func sendMessage(_ message: [String: Any], replyHandler: (([String: Any]) -> Void)?, errorHandler: ((Error) -> Void)?) {
                sentMessages.append(message)
                replyHandler?([:])
            }
            func queueUserInfo(_ userInfo: [String: Any]) { queuedUserInfos.append(userInfo) }
            func transferFile(at url: URL, metadata: [String: Any]?) {}
            func updateApplicationContext(_ context: [String: Any]) throws { applicationContexts.append(context) }
        }

        let files = try Files(), vm = model(files, scoreFirstPoint: true)
        let session = RecordingSession()
        let sync = WatchMatchSyncService(transport: MatchSyncTransport(session: session))
        sync.onLiveRequest = { [weak vm] req in
            vm?.handleLiveRequest(req) ?? LiveMatchReply(state: nil)
        }
        sync.onCurrentLiveRecord = { [weak vm] in vm?.currentLiveRecord() }

        sync.liveStateDidChange()
        await Task.yield()
        try await Task.sleep(for: .milliseconds(30))
        #expect(session.applicationContexts.count == 1)
        let decoded = SyncIncomingPayload.decode(try #require(session.applicationContexts.last))
        guard case .liveState(let reply) = decoded.first else {
            Issue.record("Expected liveState in applicationContext")
            return
        }
        #expect(reply.state?.record?.currentPointsMe == 1)

        // Unchanged live state should not re-write applicationContext.
        sync.liveStateDidChange()
        try await Task.sleep(for: .milliseconds(30))
        #expect(session.applicationContexts.count == 1)

        // Scoring another point updates applicationContext even while unreachable.
        vm.winPoint(player: .me)
        sync.liveStateDidChange()
        try await Task.sleep(for: .milliseconds(30))
        #expect(session.applicationContexts.count == 2)

        // Full-history request also pushes the live record reliably while unreachable.
        sync.handle([MatchSyncKey.requestFullHistory: true])
        try await Task.sleep(for: .milliseconds(30))
        #expect(session.queuedUserInfos.contains { $0[MatchSyncKey.singleMatch] != nil })
    }
}

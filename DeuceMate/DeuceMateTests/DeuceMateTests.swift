//
//  DeuceMateTests.swift
//  DeuceMateTests
//

import Dispatch
import Foundation
import Testing
import DeuceMateCore
@testable import DeuceMate

struct DeuceMateTests {
    @MainActor
    @Test func unsupportedWatchConnectivityLeavesConnectingState() {
        var didTryToActivate = false
        var didScheduleTimeout = false
        let service = PhoneMatchSyncService(
            isSessionSupported: { false },
            activateSession: { _ in didTryToActivate = true },
            scheduleAfter: { _, _ in didScheduleTimeout = true }
        )

        service.beginSessionActivation()

        #expect(service.isActivating == false)
        #expect(service.activationState == "Unavailable")
        #expect(service.isActivationUnavailable)
        #expect(didTryToActivate == false)
        #expect(didScheduleTimeout == false)
    }

    @MainActor
    @Test func activationTimeoutLeavesConnectingState() {
        var scheduledWorkItem: DispatchWorkItem?
        let service = PhoneMatchSyncService(
            isSessionSupported: { true },
            activateSession: { _ in },
            scheduleAfter: { _, workItem in scheduledWorkItem = workItem }
        )

        service.beginSessionActivation()
        #expect(service.isActivating)
        #expect(service.activationState == "Activating")

        scheduledWorkItem?.perform()

        #expect(service.isActivating == false)
        #expect(service.activationState == "Timed Out")
        #expect(service.isActivationUnavailable)
    }

    @MainActor
    @Test func resolvedActivationIsNotReplacedByTimeout() {
        var scheduledWorkItem: DispatchWorkItem?
        let service = PhoneMatchSyncService(
            isSessionSupported: { true },
            activateSession: { _ in },
            scheduleAfter: { _, workItem in scheduledWorkItem = workItem }
        )

        service.beginSessionActivation()
        service.finishActivation(state: "Activated")
        scheduledWorkItem?.perform()

        #expect(service.isActivating == false)
        #expect(service.activationState == "Activated")
        #expect(service.isActivationUnavailable == false)
    }

    @MainActor
    @Test func emptyWatchManifestCompletesSyncAndPublishesZeroMatches() async {
        let service = PhoneMatchSyncService(
            isSessionSupported: { true },
            activateSession: { _ in },
            scheduleAfter: { _, _ in }
        )

        service.handle([.watchManifest([])])
        await drainMainQueue()

        #expect(service.lastSyncDate != nil)
        #expect(service.watchMatchIDs.isEmpty)
    }

    @MainActor
    @Test func watchInstallationStateCanRefreshAfterActivation() {
        let service = PhoneMatchSyncService(
            isSessionSupported: { true },
            activateSession: { _ in },
            scheduleAfter: { _, _ in }
        )

        service.updatePublishedWatchState(
            isPaired: true,
            isWatchAppInstalled: false,
            isReachable: false,
            pendingTransferCount: 0
        )
        #expect(service.isWatchAppInstalled == false)

        service.updatePublishedWatchState(
            isPaired: true,
            isWatchAppInstalled: true,
            isReachable: true,
            pendingTransferCount: 2
        )

        #expect(service.isPaired)
        #expect(service.isWatchAppInstalled)
        #expect(service.isWatchReachable)
        #expect(service.pendingTransferCount == 2)
    }

    @Test func syncCompletionShowsCountsAndFreshWatchRestoreGuidance() {
        let emptyWatch = SettingsView.syncCompletionMessage(iPhoneCount: 3, watchCount: 0)
        #expect(emptyWatch.contains("iPhone: 3 matches"))
        #expect(emptyWatch.contains("Apple Watch: 0 matches"))
        #expect(emptyWatch.contains("fresh Apple Watch starts empty"))
        #expect(emptyWatch.contains("open it and choose Sync to Watch"))

        let populatedWatch = SettingsView.syncCompletionMessage(iPhoneCount: 3, watchCount: 1)
        #expect(populatedWatch.contains("iPhone: 3 matches"))
        #expect(populatedWatch.contains("Apple Watch: 1 match"))
        #expect(populatedWatch.contains("fresh Apple Watch") == false)
    }

    @MainActor
    @Test func manualEntryFooterDescribesPairedAndUnpairedBehavior() {
        let paired = ManualMatchEntryView.saveFooterText(isWatchPaired: true)
        let unpaired = ManualMatchEntryView.saveFooterText(isWatchPaired: false)

        #expect(paired.contains("Apple Watch"))
        #expect(paired.contains("resume scoring"))
        #expect(unpaired.contains("saved as in progress on this iPhone"))
        #expect(unpaired.contains("without an Apple Watch"))
    }

    // MARK: - Storage badging while a match is still on the wire

    /// The reported bug: a match scored on the Watch showed "iPhone only" in the
    /// archive for a few moments after it ended. The phone learns about it from
    /// in-progress checkpoints, which the mirror excludes and which the Watch's
    /// manifest cannot list until the match finishes — so nothing knew the Watch
    /// held it. A received record is proof, so it must badge as on-Watch at once.
    @Test func inProgressCheckpointMarksTheMatchAsHeldOnTheWatch() async {
        let service = PhoneMatchSyncService(
            isSessionSupported: { true },
            activateSession: { _ in },
            scheduleAfter: { _, _ in }
        )
        let id = UUID()

        service.handle([.singleMatch(Self.liveRecord(id: id))])
        await drainMainQueue()

        #expect(
            service.onWatchIDs.contains(id),
            "A checkpoint received from the Watch proves the Watch holds the match"
        )
    }

    /// The optimism must not outlive the evidence: once the match is no longer
    /// live, a manifest that omits it means it was deleted on the Watch.
    @Test func manifestRetiresAReportedMatchTheWatchNoLongerHolds() async {
        let service = PhoneMatchSyncService(
            isSessionSupported: { true },
            activateSession: { _ in },
            scheduleAfter: { _, _ in }
        )
        let id = UUID()

        service.handle([.singleMatch(Self.liveRecord(id: id))])
        await drainMainQueue()
        #expect(service.onWatchIDs.contains(id))

        service.handle([.watchManifest([])])
        await drainMainQueue()

        #expect(
            service.onWatchIDs.contains(id) == false,
            "An empty manifest with no live match retires the optimistic id"
        )
    }

    /// …but a manifest arriving *during* the match must not retire the live one,
    /// which is legitimately absent from the Watch's saved history.
    @Test func manifestDuringALiveMatchKeepsItBadgedOnTheWatch() async {
        let service = PhoneMatchSyncService(
            isSessionSupported: { true },
            activateSession: { _ in },
            scheduleAfter: { _, _ in }
        )
        let id = UUID()

        service.handle([.activeMatchID(id), .singleMatch(Self.liveRecord(id: id))])
        await drainMainQueue()

        service.handle([.watchManifest([])])
        await drainMainQueue()

        #expect(
            service.onWatchIDs.contains(id),
            "The live match is not in the Watch's history yet — its omission is expected"
        )
    }

    /// An in-progress checkpoint, as the Watch sends on every point.
    private static func liveRecord(id: UUID) -> MatchRecord {
        MatchRecord(
            id: id,
            startTime: Date(timeIntervalSince1970: 1_000),
            endTime: nil,
            setScores: [SetScore(gamesMe: 2, gamesOpponent: 1)],
            stats: [],
            iWon: nil
        )
    }

    @MainActor
    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }
}

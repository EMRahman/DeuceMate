//
//  DeuceMateTests.swift
//  DeuceMateTests
//

import Dispatch
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

    @MainActor
    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }
}

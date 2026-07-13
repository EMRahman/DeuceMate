//
//  DeuceMateTests.swift
//  DeuceMateTests
//

import Dispatch
import Testing
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
    @Test func manualEntryFooterDescribesPairedAndUnpairedBehavior() {
        let paired = ManualMatchEntryView.saveFooterText(isWatchPaired: true)
        let unpaired = ManualMatchEntryView.saveFooterText(isWatchPaired: false)

        #expect(paired.contains("Apple Watch"))
        #expect(paired.contains("resume scoring"))
        #expect(unpaired.contains("saved as in progress on this iPhone"))
        #expect(unpaired.contains("without an Apple Watch"))
    }
}

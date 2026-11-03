//
//  ScoreInputHapticsTests.swift
//  DeuceMate Watch AppTests
//
//  The rules behind the optional swipe vibration: off unless the user opts in,
//  a distinct pattern per scoring action, and no confirmation for an undo that
//  had nothing to undo.
//

import DeuceMateCore
import Foundation
import Testing
import WatchKit
@testable import DeuceMate_Watch_App

struct ScoreInputHapticsTests {

    private func played(_ action: ScoreInputAction, isEnabled: Bool) -> [WKHapticType] {
        var haptics: [WKHapticType] = []
        ScoreInputHaptics.confirm(action, isEnabled: isEnabled) { haptics.append($0) }
        return haptics
    }

    private func makeTempURL(_ prefix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString).json")
    }

    @Test func settingIsOffByDefault() {
        #expect(ScoreInputHaptics.isEnabledByDefault == false)
    }

    @Test func settingKeyIsPinned() {
        // Renaming a UserDefaults key silently resets the user's stored choice.
        #expect(ScoreInputHaptics.enabledKey == "swipeHapticsEnabled")
    }

    @Test func settingKeyMatchesTheSyncWireKey() {
        // One string for UserDefaults and the wire, so a phone toggle lands on
        // the value the watch's @AppStorage reads.
        #expect(ScoreInputHaptics.enabledKey == MatchSyncKey.swipeHapticsEnabled)
    }

    @Test func incomingPhoneValueIsPersistedUnderTheSettingKey() throws {
        let suiteName = "scoreinputhaptics-incoming-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        #expect(defaults.object(forKey: ScoreInputHaptics.enabledKey) == nil)
        ScoreInputHaptics.storeIncoming(true, defaults: defaults)
        #expect(defaults.bool(forKey: ScoreInputHaptics.enabledKey) == true)
        ScoreInputHaptics.storeIncoming(false, defaults: defaults)
        #expect(defaults.bool(forKey: ScoreInputHaptics.enabledKey) == false)
    }

    @Test func disabledSettingPlaysNothing() {
        for action in [ScoreInputAction.win, .lose, .undo, .stats] {
            #expect(played(action, isEnabled: false).isEmpty)
        }
    }

    @Test func enabledSettingPlaysAPatternForEachScoreChange() {
        #expect(played(.win, isEnabled: true) == [.directionUp])
        #expect(played(.lose, isEnabled: true) == [.directionDown])
        #expect(played(.undo, isEnabled: true) == [.click])
    }

    @Test func openingStatsNeverVibrates() {
        #expect(played(.stats, isEnabled: true).isEmpty)
    }

    @Test func undoReportsWhetherAPointWasReversed() throws {
        let storeURL = makeTempURL("scoreinputhaptics-store")
        let stateURL = makeTempURL("scoreinputhaptics-state")
        let suiteName = "scoreinputhaptics-defaults-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            try? FileManager.default.removeItem(at: storeURL)
            try? FileManager.default.removeItem(at: stateURL)
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }

        let viewModel = ScoreViewModel(
            statsStore: StatsStore(fileURL: storeURL),
            stateFileURL: stateURL,
            userDefaults: defaults
        )
        viewModel.currentServer = .me

        #expect(viewModel.undo() == false)

        viewModel.winPoint(player: .me)
        #expect(viewModel.undo() == true)
        #expect(viewModel.currentPointsMe == 0)
        #expect(viewModel.undo() == false)
    }
}

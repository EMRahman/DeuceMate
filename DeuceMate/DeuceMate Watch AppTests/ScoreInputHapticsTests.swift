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

    private func makeViewModel() -> ScoreViewModel {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("scoreinputhaptics-\(UUID().uuidString).json")
        let viewModel = ScoreViewModel(statsStore: StatsStore(fileURL: url))
        viewModel.currentServer = .me
        return viewModel
    }

    @Test func settingIsOffByDefault() {
        #expect(ScoreInputHaptics.isEnabledByDefault == false)
    }

    @Test func settingKeyIsPinned() {
        // Renaming a UserDefaults key silently resets the user's stored choice.
        #expect(ScoreInputHaptics.enabledKey == "swipeHapticsEnabled")
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

    @Test func undoReportsWhetherAPointWasReversed() {
        let viewModel = makeViewModel()
        #expect(viewModel.undo() == false)

        viewModel.winPoint(player: .me)
        #expect(viewModel.undo() == true)
        #expect(viewModel.currentPointsMe == 0)
        #expect(viewModel.undo() == false)
    }
}
